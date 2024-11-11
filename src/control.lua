require("util")
require("config")

local clusterio_api = require("__clusterio_lib__/api")

local compat = require("compat")

local mod_entities = {
	["subspace-item-injector"] = true,
	["subspace-item-extractor"] = true,
	["subspace-fluid-injector"] = true,
	["subspace-fluid-extractor"] = true,
	["subspace-electricity-injector"] = true,
	["subspace-electricity-extractor"] = true,
	["subspace-storage-combinator"] = true,
}

local function absolute(surface, force, position)
	local spawn = force.get_spawn_position(surface)
	return {
		x = (position.x + spawn.y // CHUNK_SIZE) * CHUNK_SIZE,
		y = (position.y + spawn.x // CHUNK_SIZE) * CHUNK_SIZE
	}
end

local function relative(surface, force, position)
	local spawn = force.get_spawn_position(surface)
	return {
		x = position.x // CHUNK_SIZE - spawn.y // CHUNK_SIZE,
		y = position.y // CHUNK_SIZE - spawn.x // CHUNK_SIZE
	}
end

local function endpoint(entity)
	local position = relative(entity.surface, entity.force, entity.position)
	return entity.force.name, position.x, position.y
end

---------------
-- [[Queue]] --
---------------
local Queue = {}

function Queue:new()
	local queue = { ci = 1 }
	setmetatable(queue, self)
	self.__index = self
	return queue
end

function Queue:ipairs(portion)
	local ci = self.ci - 1
	local ei = math.min(ci + math.ceil(#self * (portion or 1)), #self)
	return function()
		ci = ci + 1
		self.ci = ci
		if ci > ei then
			return nil, nil
		end
		return ci, self[ci]
	end
end

function Queue:reset()
	self.ci = 1
end

-----------------
-- [[Storage]] --
-----------------
local Storage = {}

function Storage:new(default)
	local storage = { ["__default__"] = default }
	setmetatable(storage, self)
	self.__index = self
	return storage
end

function Storage.parse(data, default)
	local storage = Storage:new(default)
	for _, item in ipairs(data) do
		storage:set(item[1], item[2], item[3], item[4], item[5])
	end
	return storage
end

function Storage:set(force, cx, cy, name, data)
	self[force] = self[force] or {}
	self[force][cx] = self[force][cx] or {}
	self[force][cx][cy] = self[force][cx][cy] or {}
	self[force][cx][cy][name] = data
	if self[force][cx][cy][name] == self["__default__"] then
		self[force][cx][cy][name] = nil
	end
	if not next(self[force][cx][cy]) then
		self[force][cx][cy] = nil
	end
	if not next(self[force][cx]) then
		self[force][cx] = nil
	end
	if not next(self[force]) then
		self[force] = nil
	end
end

function Storage:get(force, cx, cy, name)
	return self[force]
			and self[force][cx]
			and self[force][cx][cy]
			and self[force][cx][cy][name]
			or self["__default__"]
end

function Storage:update(self, force, cx, cy, name, f)
	self:set(force, cx, cy, name, f(self:get(force, cx, cy, name)))
end

function Storage:serialize()
	local data = {}
	for force, chunks in pairs(self) do
		for cx, rows in pairs(chunks) do
			for cy, items in pairs(rows) do
				for name, data in pairs(items) do
					table.insert(data, { force, cx, cy, name, data })
				end
			end
		end
	end
	return data
end

function Storage:entries()
	local entries = self:serialize() -- TODO Avoid creating an array
	local i = 0
	return function()
		i = i + 1
		if i > #entries then
			return nil, nil, nil, nil, nil
		end
		return entries[i][1], entries[i][2], entries[i][3], entries[i][4], entries[i][5]
	end
end

-------------------------
-- [[Entity creation]] --
-------------------------
local function register_entity(entity, internal)
	if not mod_entities[entity.name] then
		return
	end

	if entity.name == "subspace-storage-combinator" then
		entity.operable = false
	end

	table.insert(global.entities[entity.name], entity)

	if not internal then
		local force, cx, cy = endpoint(entity)
		global.endpoints_outbox:update(force, cx, cy, entity.name, function(c) return c + 1 end)
	end
end

local function register_all()
	for _, surface in pairs(game.surfaces) do
		for name, _ in pairs(mod_entities) do
			for _, entity in pairs(surface.find_entities_filtered { name = name }) do
				register_entity(entity, true)
			end
		end
	end
end

local function on_entity_built(event)
	local entity = event.entity
	if not entity or not entity.valid or entity.type == "entity-ghost" or not mod_entities[entity.name] then
		return
	end
	register_entity(entity)
end

script.on_event(defines.events.on_built_entity, on_entity_built)
script.on_event(defines.events.on_robot_built_entity, on_entity_built)

------------------------
-- [[Entity removal]] --
------------------------
local function unregister_entity(entity, internal)
	if not mod_entities[entity.name] then
		return
	end

	for i, e in ipairs(global.entities[entity.name]) do
		if e == entity then
			table.remove(global.entities[entity.name], i)
			break
		end
	end

	if not internal then
		local force, cx, cy = endpoint(entity)
		global.endpoints_outbox:update(force, cx, cy, entity.name, function(c) return c - 1 end)
	end
end

local function on_entity_removed(event)
	local entity = event.entity
	if not entity or not entity.valid or entity.type == "entity-ghost" or not mod_entities[entity.name] then
		return
	end
	unregister_entity(entity)
end

script.on_event(defines.events.on_entity_died, on_entity_removed)
script.on_event(defines.events.on_robot_pre_mined, on_entity_removed)
script.on_event(defines.events.on_pre_player_mined_item, on_entity_removed)
script.on_event(defines.events.script_raised_destroy, on_entity_removed)

------------------------------------------
-- [[Getter and setter update methods]] --
------------------------------------------
local function enqueue_entities()
	for _, entities in global.entities do
		entities:reset()
	end
end

local function collect_items(entity, name, count, limit)
	if not entity.valid or count <= 0 then
		return 0
	end

	local force, cx, cy = endpoint(entity)
	if limit <= 0 or global.shared_storage:get(force, cx, cy, name) < limit then
		global.items_outbox:update(force, cx, cy, name, function(c) return c + count end)
		return count
	end
	return 0
end

local function collect_item_injector_items(entity)
	if not entity.valid then
		return
	end

	local inventory = entity.get_inventory(defines.inventory.chest)

	if settings.global["subspace_storage-infinity-mode"].value then
		inventory.clear()
		return
	end

	for name, count in pairs(inventory.get_contents()) do
		inventory.remove({
			name = name,
			count = collect_items(entity, name, count, settings.global["subspace_storage-max-items"].value)
		})
	end
end

local function collect_fluid_injector_items(entity)
	if not entity.valid then
		return
	end

	local fluidbox = entity.fluidbox
	local fluid    = fluidbox[1]

	if not fluid or fluid.amount <= 0 then
		return
	end

	if settings.global["subspace_storage-infinity-mode"].value then
		fluidbox[1] = nil
		return
	end

	if fluid.amount < 1 then
		if entity.get_merged_signal({ name = "signal-P", type = "virtual" }) == 1 then
			fluidbox[1] = nil
		end
		return
	end

	fluid.amount = fluid.amount - collect_items(
		entity,
		fluid.name,
		math.ceil(fluid.amount) - 1,
		settings.global["subspace_storage-max-fluid"].value
	)
	fluidbox[1] = fluid
end

local function collect_electricity_injector_items(entity)
	if not entity.valid then
		return
	end

	local energy = math.floor(entity.energy / ELECTRICITY_RATIO)
	if energy <= 0 then
		return
	end

	if settings.global["subspace_storage-infinity-mode"].value then
		entity.energy = 0
		return
	end

	entity.energy = entity.energy - ELECTRICITY_RATIO * collect_items(
		entity,
		ELECTRICITY_ITEM_NAME,
		energy,
		settings.global["subspace_storage-max-electricity"].value
	)
end

local function collect_injector_items(portion)
	for _, entity in global.entities["subspace-item-injector"]:ipairs(portion) do
		collect_item_injector_items(entity)
	end
	for _, entity in global.entities["subspace-fluid-injector"]:ipairs(portion) do
		collect_fluid_injector_items(entity)
	end
	for _, entity in global.entities["subspace-electricity-injector"]:ipairs(portion) do
		collect_electricity_injector_items(entity)
	end
end

local function collect_request(entity, name, count)
	if not entity.valid or entity.to_be_deconstructed(entity.force) or count <= 0 then
		return
	end

	local force, cx, cy = endpoint(entity)
	global.requests:update(force, cx, cy, name, function(request)
		request = request or { count = 0, subrequests = {} }
		request.count = request.count + count
		table.insert(request.subrequests, { entity = entity, count = count })
		return request
	end)
end

local function collect_item_extractor_requests(entity)
	if not entity.valid or entity.to_be_deconstructed(entity.force) then
		return
	end

	local inventory = entity.get_inventory(defines.inventory.chest)

	local freeStacks = inventory.count_empty_stacks()
	for i = 1, entity.request_slot_count do
		local request = entity.get_request_slot(i)
		if request then
			local stack = game.item_prototypes[request.name].stack_size
			local count = math.min(request.count - inventory.get_item_count(request.name), freeStacks * stack)
			if count > 0 then
				freeStacks = freeStacks - math.ceil(count / stack)
				collect_request(entity, request.name, count)
			end
		end
	end
end

local function collect_fluid_extractor_requests(entity)
	if not entity.valid or entity.to_be_deconstructed(entity.force) then
		return
	end

	local fluidbox = entity.fluidbox

	local request = entity.get_recipe()
	if request then
		local fluid = fluidbox[1]
		if not fluid or fluid.name ~= request.products[1].name then
			fluid = { name = request.products[1].name, amount = 0 }
		end

		collect_request(entity, fluid.name, math.ceil(MAX_FLUID_AMOUNT - fluid.amount))
	end
end

local function collect_electricity_extractor_requests(entity)
	if not entity.valid or entity.to_be_deconstructed(entity.force) then
		return
	end

	collect_request(entity, ELECTRICITY_ITEM_NAME,
		math.floor((entity.electric_buffer_size - entity.energy) / ELECTRICITY_RATIO))
end

local function collect_extractors_requests(portion)
	for _, entity in global.entities["subspace-item-extractor"]:ipairs(portion) do
		collect_item_extractor_requests(entity)
	end
	for _, entity in global.entities["subspace-fluid-extractor"]:ipairs(portion) do
		collect_fluid_extractor_requests(entity)
	end
	if math.fmod(global.iteration, ITERATIONS_TO_COLLECT_ELECTRICITY_REQUESTS) == 0 then
		for _, entity in global.entities["subspace-electricity-extractor"]:ipairs(portion) do
			collect_electricity_extractor_requests(entity)
		end
	end
end

local function insert_into_item_extractor(entity, name, count)
	if not entity.valid or entity.to_be_deconstructed(entity.force) or count <= 0 then
		return 0
	end
	return entity.get_inventory(defines.inventory.chest).insert { name = name, count = count }
end

local function insert_into_fluid_extractor(entity, name, count)
	if not entity.valid or entity.to_be_deconstructed(entity.force) or count <= 0 then
		return 0
	end

	local fluid = entity.fluidbox[1] or { name = name, amount = 0 }

	fluid.amount = fluid.amount + count
	if fluid.name == "steam" then
		fluid.temperature = 165 -- TODO Transfer fluid temperature too.
	end

	entity.fluidbox[1] = fluid
	return count
end

local function insert_into_electricity_extractor(entity, _, count)
	if not entity.valid or entity.to_be_deconstructed(entity.force) or count <= 0 then
		return 0
	end
	entity.energy = entity.energy + count * ELECTRICITY_RATIO
	return count
end

local function enqueue_extractor_requests()
	global.request_queues = {
		["subspace-item-extractor"] = Queue:new(),
		["subspace-fluid-extractor"] = Queue:new(),
		["subspace-electricity-extractor"] = Queue:new()
	}
	for force, cx, cy, name, request in global.requests:entries() do
		table.insert(global.local_requests_queue[request.subrequests[1].entity.name], {
			force = force,
			cx = cx,
			cy = cy,
			name = name,
			count = request.count,
			subrequests = request.subrequests
		})

		if request.subrequests[1].entity.name == "subspace-item-extractor" then
			-- To be able to distribute it fairly, the requesters need to be sorted in order of how
			-- much they are missing, so the requester with the least missing of the item will be first.
			-- If this isn't done then there could be items leftover after they have been distributed
			-- even though they could all have been distributed if they had been distributed in order.
			table.sort(request.subrequests, function(l, r) return l.count < r.count end)
		end
	end
	global.requests = Storage:new()
end

local function fulfill_request(request, insert)
	local entry
	if settings.global["subspace_storage-infinity-mode"].value then
		entry = { count = request.count }
	else
		entry = global.own_storage:get(request.force, request.cx, request.cy, request.name) or { count = 0 };
		entry.count = entry.count
		local outbox_count = global.own_storage:get(request.force, request.cx, request.cy, request.name)
		if outbox_count > 0 then
			entry.count = entry.count + outbox_count
			global.own_storage:set(request.force, request.cx, request.cy, request.name)
		end
	end

	local available = math.min(entry.count, request.count)
	local remaining = available
	for _, subrequest in ipairs(request.subrequests) do
		remaining = remaining - insert(
			subrequest.entity,
			request.name,
			math.min(math.max(1, math.floor(available * subrequest.count / request.count)), remaining))
	end

	local taken = available - remaining
	if taken < request.count then
		global.items_outbox:update(request.force, request.cx, request.cy, request.name, function(c)
			return c - (request.count - taken)
		end)
	end
	if taken < entry.count then
		global.items_outbox:update(request.force, request.cx, request.cy, request.name, function(c)
			return c + (entry.count - taken)
		end)
	end
	global.own_storage:set(request.force, request.cx, request.cy, request.name, nil)

	entry.accessed = game.tick
end

function fulfill_extractors_requests(portion)
	for _, request in global.request_queues["subspace-item-extractor"]:ipairs(portion) do
		fulfill_request(request, insert_into_item_extractor)
	end
	for _, request in global.request_queues["subspace-fluid-extractor"]:ipairs(portion) do
		fulfill_request(request, insert_into_fluid_extractor)
	end
	if math.fmod(global.iteration, ITERATIONS_TO_COLLECT_ELECTRICITY_REQUESTS) == 0 then
		for _, request in global.request_queues["subspace-electricity-extractor"]:ipairs(portion) do
			fulfill_request(request, insert_into_electricity_extractor)
		end
	end
end

function update_storage_combinators()
	local instance_id = clusterio_api.get_instance_id()

	for _, entity in global.entities["subspace-storage-combinator"] do
		if entity.valid then
			local eforce, ecx, ecy = endpoint(entity)

			local signals = {}
			if instance_id then
				table.insert(signals, {
					index = #signals + 1,
					signal = { name = "signal-localid", type = "virtual" },
					-- Clamp to 32-bit to avoid error raised by Factorio
					count = math.max(-0x80000000, math.min(instance_id, 0x7fffffff))
				})
			end

			for force, cx, cy, name, count in global.shared_storage:entries() do
				if force == eforce and cx == ecx and cy == ecy then
					-- Combinator signals are limited to a max value of 2^31-1
					count = math.min(count, 0x7fffffff)
					if game.item_prototypes[name] then
						table.insert(signals, { index = #signals + 1, signal = { name = name, type = "item" }, count = count })
					elseif game.fluid_prototypes[name] then
						table.insert(signals, { index = #signals + 1, signal = { name = name, type = "fluid" }, count = count })
					elseif game.virtual_signal_prototypes[name] then
						table.insert(signals, { index = #signals + 1, signal = { name = name, type = "virtual" }, count = count })
					end
				end
			end

			local behavior = entity.get_or_create_control_behavior()
			compat.set_parameters(behavior, signals)
			behavior.enabled = true
		end
	end
end

------------
-- [[UI]] --
------------
script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
	local player = game.players[event.player_index]
	if not player or not player.valid then
		return
	end

	local entity =
			player.cursor_stack and player.cursor_stack.valid and player.cursor_stack.valid_for_read and
			player.cursor_stack.name
			or player.cursor_ghost and player.cursor_ghost.name
			or ""

	if mod_entities[entity] and not global.zones[player.name] then
		global.zones[player.name] = {}
		for force, cx, cy, _, _ in global.endpoints:entries() do
			if player.force.name == force then
				local position = absolute(player.surface, player.force, { x = cx, y = cy })
				table.insert(global.zones[player.name], rendering.draw_rectangle {
					color = { r = 0.8, g = 0.1, b = 0 },
					width = 12,
					filled = false,
					left_top = { position.x, position.y },
					right_bottom = { position.x + CHUNK_SIZE, position.y + CHUNK_SIZE },
					surface = player.surface,
					players = { player },
					draw_on_ground = true,
				})
			end
		end
	elseif not mod_entities[entity] and global.zones[player.name] then
		for _, zone in ipairs(global.zones[player.name]) do
			rendering.destroy(zone)
		end
		global.zones[player.name] = nil
	end
end)

------------------------------------------
-- [[Methods that talk with Clusterio]] --
------------------------------------------
function SetEndpoints(data)
	global.endpoints = Storage.parse(data)
end

function UpdateEndpoints(data)
	for _, endpoint in ipairs(game.json_to_table(data)) do
		global.endpoints:set(endpoint[1], endpoint[2], endpoint[3], endpoint[4], endpoint[5])
	end
end

function SendEndpoints()
	clusterio_api.send_json("subspace_storage:place_endpoints", global.endpoints_outbox:serialize())
	global.endpoints_outbox = Storage:new()
end

function SetStorage(data)
	global.shared_storage = Storage.parse(data)
	update_storage_combinators()
end

function UpdateStorage(data)
	for _, item in ipairs(game.json_to_table(data)) do
		global.shared_storage:set(item[1], item[2], item[3], item[4], item[5])
	end
	update_storage_combinators()
end

function SendTransfer()
	if next(global.items_outbox) then
		clusterio_api.send_json("subspace_storage:transfer_items", global.items_outbox:serialize())
		global.items_outbox = Storage:new(0) -- TODO Confirm items received.
	end

end

function ReceiveTransfer(data)
	for _, item in ipairs(game.json_to_table(data)) do
		global.items_inbox:update(item[1], item[2], item[3], item[4], function(c) return c + item[5] end)
	end
end

function ProcessTransfer()
	for force, cx, cy, name, count in global.items_inbox:entries() do
		local e = global.own_storage:get(force, cx, cy, name) or { count = 0, accessed = game.tick }
		e.count = e.count + count
		global.own_storage:set(force, cx, cy, name, e)
	end
	global.items_inbox = Storage:new(0)
end

--------------------------------------
-- [[Initialization and main loop]] --
--------------------------------------
local function on_load()
	clusterio_api.init()
	script.on_event(clusterio_api.events.on_instance_updated, update_storage_combinators)
end

local function on_init()
	global.heartbeat_tick = 0
	global.connected = false

	global.iteration = 0
	global.tick = 0

	global.endpoints = Storage:new(0)
	global.endpoints_outbox = Storage:new(0)

	-- TODO It would probably be more optimal to spread the processing by forces and chunks rather than by entity type.
	global.entities = {
		["subspace-item-injector"] = Queue:new(),
		["subspace-fluid-injector"] = Queue:new(),
		["subspace-electricity-injector"] = Queue:new(),
		["subspace-item-extractor"] = Queue:new(),
		["subspace-fluid-extractor"] = Queue:new(),
		["subspace-electricity-extractor"] = Queue:new()
	}

	global.shared_storage = global.shared_storage or Storage:new(0)
	global.own_storage = global.own_storage or Storage:new()

	global.items_outbox = Storage:new(0)
	global.items_inbox = Storage:new(0)

	global.requests = Storage:new()
	global.request_queues = {
		["subspace-item-extractor"] = Queue:new(),
		["subspace-fluid-extractor"] = Queue:new(),
		["subspace-electricity-extractor"] = Queue:new()
	}

	global.zones = {}
	rendering.clear("subspace_storage")

	register_all()
end

script.on_init(function()
	on_load()
	on_init()
end)

script.on_load(on_load)

script.on_configuration_changed(function(data)
	if data.mod_changes and data.mod_changes["subspace_storage"] then
		on_init()
	end
end)

script.on_event(defines.events.on_tick, function()
	local connected =
			settings.global["subspace_storage-infinity-mode"].value
			or game.tick - global.heartbeat_tick < 300

	if connected then
		if not global.connected then
			global.tick = 0
		end

		if global.tick < TICKS_TO_COLLECT_REQUESTS then
			if global.tick == 0 then
				enqueue_entities()
			end
			collect_injector_items(1 / (TICKS_TO_COLLECT_REQUESTS + TICKS_TO_FULFILL_REQUESTS))

			if global.tick == 0 then
				global.requests = Storage:new()
			end
			collect_extractors_requests(1 / TICKS_TO_COLLECT_REQUESTS)
		elseif global.tick < TICKS_TO_COLLECT_REQUESTS + TICKS_TO_FULFILL_REQUESTS then
			collect_injector_items(1 / (TICKS_TO_COLLECT_REQUESTS + TICKS_TO_FULFILL_REQUESTS))

			if global.tick == TICKS_TO_COLLECT_REQUESTS then
				enqueue_extractor_requests()
				ProcessTransfer()
			end
			fulfill_extractors_requests(1 / TICKS_TO_FULFILL_REQUESTS)
		else
			SendEndpoints()
			SendTransfer()

			global.iteration = global.iteration + 1
			global.tick = -1
		end

		global.tick = global.tick + 1
	end

	global.connected = connected
end)

script.on_nth_tick(TICKS_TO_COLLECT_GARBAGE, function()
	if settings.global["subspace_storage-infinity-mode"].value then
		return
	end

	for force, cx, cy, name, entry in global.own_storage:entries() do
		if entry.accessed < game.tick - TICKS_TO_COLLECT_GARBAGE then
			global.items_outbox:update(force, cx, cy, name, function(c) return c + entry.count end)
			global.own_storage:set(force, cx, cy, name, nil)
		end
	end
end)
