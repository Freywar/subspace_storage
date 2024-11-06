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
	[STORAGE_COMBINATOR_NAME] = true,
}

local function relative(surface, force, position)
	local spawn = force.get_spawn_position(surface)
	return {
		x = position.x // CHUNK_SIZE - spawn.y // CHUNK_SIZE,
		y = position.y // CHUNK_SIZE - spawn.x // CHUNK_SIZE
	}
end

-------------------------
-- [[Queue structure]] --
-------------------------
local function queue()
	return { ci = 1 }
end

local function queue_ipairs(queue, portion)
	local i = queue.ci
	queue.ci = math.min(queue.ci + math.ceil(#queue * (portion or 1)), #queue)
	return function()
		if i >= queue.ci then
			return nil, nil
		end
		i = i + 1
		return i, queue[i]
	end
end

local function reset_queue(queue)
	queue.ci = 1
end

---------------------------
-- [[Storage structure]] --
---------------------------
local function storage(default)
	return { ["__default__"] = default }
end

local function set(storage, force, cx, cy, name, data)
	storage[force] = storage[force] or {}
	storage[force][cx] = storage[force][cx] or {}
	storage[force][cx][cy] = storage[force][cx][cy] or {}
	storage[force][cx][cy][name] = data or nil
	if not next(storage[force][cx][cy]) then
		storage[force][cx][cy] = nil
	end
	if not next(storage[force][cx]) then
		storage[force][cx] = nil
	end
	if not next(storage[force]) then
		storage[force] = nil
	end
end

local function get(storage, force, cx, cy, name)
	return storage[force]
			and storage[force][cx]
			and storage[force][cx][cy]
			and storage[force][cx][cy][name]
			or storage["__default__"]
end

local function update(storage, force, cx, cy, name, f)
	set(storage, force, cx, cy, name, f(get(storage, force, cx, cy, name)))
end

local function parse(data)
	local storage = {}
	for _, item in ipairs(data) do
		set(storage, item[1], item[2], item[3], item[4], item[5])
	end
	return storage
end

local function serialize(storage)
	local data = {}
	for force, chunks in pairs(storage) do
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

local function entries(storage)
	local entries = serialize(storage) -- TODO Avoid creating an array
	local i = 0
	return function()
		i = i + 1
		if i > #entries then
			return nil, nil, nil, nil, nil
		end
		local entry = entries[i]
		return entry[1], entry[2], entry[3], entry[4], entry[5]
	end
end

------------------------
-- [[Thing creation]] --
------------------------
local function RegisterEntity(entity)
	if not mod_entities[entity.name] then
		return
	end

	if entity.name == STORAGE_COMBINATOR_NAME then
		global.invControls[entity.unit_number] = entity.get_or_create_control_behavior()
		entity.operable = false
	else
		table.insert(global.entities[entity.name], entity)
	end

	local position = relative(entity.surface, entity.force, entity.position)
	clusterio_api.send_json("subspace_storage:broadcast_endpoints",
		{ { entity.force.name, position.x, position.y, entity.name } })
end

local function RegisterAll()
	for _, surface in pairs(game.surfaces) do
		for name, _ in pairs(mod_entities) do
			for _, entity in pairs(surface.find_entities_filtered { name = name }) do
				RegisterEntity(entity)
			end
		end
	end
end

local function OnEntityBuilt(event)
	local entity = event.entity
	if not entity or not entity.valid or entity.type == "entity-ghost" or not mod_entities[entity.name] then
		return
	end
	RegisterEntity(entity)
end

script.on_event(defines.events.on_built_entity, OnEntityBuilt)
script.on_event(defines.events.on_robot_built_entity, OnEntityBuilt)

-----------------------
-- [[Thing removal]] --
-----------------------
local function UnregisterEntity(entity)
	if not mod_entities[entity.name] then
		return
	end

	if entity.name == STORAGE_COMBINATOR_NAME then
		global.invControls[entity.unit_number] = nil
	else
		for i, e in ipairs(global.entities[entity.name]) do
			if e == entity then
				table.remove(global.entities[entity.name], i)
				break
			end
		end
	end
end

local function OnEntityRemoved(event)
	local entity = event.entity
	if not entity or not entity.valid or entity.type == "entity-ghost" or not mod_entities[entity.name] then
		return
	end
	UnregisterEntity(entity)
end

script.on_event(defines.events.on_entity_died, OnEntityRemoved)
script.on_event(defines.events.on_robot_pre_mined, OnEntityRemoved)
script.on_event(defines.events.on_pre_player_mined_item, OnEntityRemoved)
script.on_event(defines.events.script_raised_destroy, OnEntityRemoved)

------------------------
-- [[Initialization]] --
------------------------
local function Load()
	clusterio_api.init()
	script.on_event(clusterio_api.events.on_instance_updated, UpdateStorageCombinators)
end

local function Init()
	-- TODO Clean up.

	global.ticksSinceMasterPinged = 601
	global.isConnected = false
	global.prevIsConnected = false

	global.iteration = 0
	global.tick = 0

	-- TODO It would probably be more optimal to spread the processing by forces and chunks rather than by entity type.
	global.entities = {
		["subspace-item-injector"] = queue(),
		["subspace-fluid-injector"] = queue(),
		["subspace-electricity-injector"] = queue(),
		["subspace-item-extractor"] = queue(),
		["subspace-fluid-extractor"] = queue(),
		["subspace-electricity-extractor"] = queue()
	}

	global.global_storage = global.global_storage or storage(0)
	global.global_requests = storage(0)

	global.outbox = storage(0)
	global.inbox = storage(0)

	global.local_storage = global.local_storage or storage()
	for force, cx, cy, name, entry in entries(global.local_storage) do
		if not entry.remaining then
			set(global.local_storage, force, cx, cy, name, nil)
		else
			entry.initial = entry.initial or entry.remaining
			entry.accessed = entry.accessed or game.tick
		end
	end
	global.local_requests = {
		["subspace-item-extractor"] = queue(),
		["subspace-fluid-extractor"] = queue(),
		["subspace-electricity-extractor"] = queue()
	}

	global.invControls = {}

	global.zones = {}
	rendering.clear("subspace_storage")

	RegisterAll()
end

script.on_init(function()
	Load()
	Init()
end)

script.on_load(Load)

script.on_configuration_changed(function(data)
	if data.mod_changes and data.mod_changes["subspace_storage"] then
		Init()
	end
end)

script.on_event(defines.events.on_tick, function(event)
	global.ticksSinceMasterPinged = global.ticksSinceMasterPinged + 1

	--If the mod isn't connected then still pretend that it's
	--so items requests and removals can be fulfilled
	if settings.global["subspace_storage-infinity-mode"].value then
		global.ticksSinceMasterPinged = 0
	end

	if global.ticksSinceMasterPinged < 300 then
		global.isConnected = true

		if global.prevIsConnected == false then
			global.tick = 0
		end


		if global.tick < TICKS_TO_COLLECT_REQUESTS then
			if global.tick == 0 then
				for _, entities in global.entities do
					reset_queue(entities)
				end
			end
			CollectInjectorsContent(1 / (TICKS_TO_COLLECT_REQUESTS + TICKS_TO_FULFILL_REQUESTS))

			if global.tick == 0 then
				global.local_requests = {
					["subspace-item-extractor"] = queue(),
					["subspace-fluid-extractor"] = queue(),
					["subspace-electricity-extractor"] = queue()
				}
			end
			CollectExtractorsRequests(1 / TICKS_TO_COLLECT_REQUESTS)
		elseif global.tick < TICKS_TO_COLLECT_REQUESTS + TICKS_TO_FULFILL_REQUESTS then
			CollectInjectorsContent(1 / (TICKS_TO_COLLECT_REQUESTS + TICKS_TO_FULFILL_REQUESTS))

			if global.tick == TICKS_TO_COLLECT_REQUESTS then
				for force, cx, cy, name, count in entries(global.inbox) do
					local e = get(global.local_storage, force, cx, cy, name) or {
						initial = 0,
						remaining = 0,
						accessed = game.tick,
					}
					e.initial = e.remaining + count
					e.remaining = e.remaining + count
					set(global.local_storage, force, cx, cy, name, e)
				end
				global.inbox = storage(0)

				-- To be able to distribute it fairly, the requesters need to be sorted in order of how
				-- much they are missing, so the requester with the least missing of the item will be first.
				-- If this isn't done then there could be items leftover after they have been distributed
				-- even though they could all have been distributed if they had been distributed in order.
				table.sort(global.local_requests["subspace-item-extractor"],
					function(l, r) return l.name == r.name and l.count < r.count end)
			end
			FulfillExtractorsRequests(1 / TICKS_TO_FULFILL_REQUESTS)
			global.tick = global.tick + 1
		elseif global.tick == TICKS_TO_COLLECT_REQUESTS + TICKS_TO_FULFILL_REQUESTS then
			SendItems()
		else
			RequestItems()

			global.iteration = global.iteration + 1
			global.tick = -1
		end

		global.tick = global.tick + 1
	else
		global.isConnected = false
	end
	global.prevIsConnected = global.isConnected
end)

script.on_nth_tick(TICKS_BEFORE_RETURN, function()
	if settings.global["subspace_storage-infinity-mode"].value then
		return
	end

	for force, cx, cy, name, entry in entries(global.local_storage) do
		if entry.accessed < game.tick - TICKS_BEFORE_RETURN and entry.remaining then
			set(global.outbox, force, cx, cy, name, entry.remaining)
			entry.remaining = 0
		end
	end
end)

------------------------------------------
-- [[Getter and setter update methods]] --
------------------------------------------
local function CollectItemInjectorContent(entity)
	if not entity.valid then
		return
	end

	local position = relative(entity.surface, entity.force, entity.position)
	local inventory = entity.get_inventory(defines.inventory.chest)

	if settings.global["subspace_storage-infinity-mode"].value then
		inventory.clear()
		return
	end

	local limit = settings.global["subspace_storage-max-items"].value
	for name, count in pairs(inventory.get_contents()) do
		if limit <= 0 or (get(global.global_storage, entity.force.name, position.x, position.y, name) or 0) < limit then
			update(global.outbox, entity.force.name, position.x, position.y, name,
				function(c) return (c or 0) + count end)
			inventory.remove({ name = name, count = count })
		end
	end
end

local function CollectFluidInjectorContent(entity)
	if not entity.valid then
		return
	end

	local position = relative(entity.surface, entity.force, entity.position)
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

	local limit = settings.global["subspace_storage-max-fluid"].value
	if limit <= 0 or (get(global.global_storage, entity.force.name, position.x, position.y, fluid.name) or 0) < limit then
		local count = math.ceil(fluid.amount) - 1
		update(global.outbox, entity.force.name, position.x, position.y, fluid.name,
			function(c) return (c or 0) + count end)
		fluid.amount = fluid.amount - count
		fluidbox[1] = fluid
	end
end

local function CollectElectricityInjectorContent(entity)
	if not entity.valid then
		return
	end

	local position = relative(entity.surface, entity.force, entity.position)
	local energy = math.floor(entity.energy / ELECTRICITY_RATIO)
	if energy <= 0 then
		return
	end

	if settings.global["subspace_storage-infinity-mode"].value then
		entity.energy = 0
		return
	end

	local limit = settings.global["subspace_storage-max-electricity"].value
	if limit <= 0 or (get(global.global_storage, entity.force.name, position.x, position.y, ELECTRICITY_ITEM_NAME) or 0) < limit then
		update(global.outbox, entity.force.name, position.x, position.y, ELECTRICITY_ITEM_NAME,
			function(c) return (c or 0) + energy end)
		entity.energy = entity.energy - (energy * ELECTRICITY_RATIO)
	end
end

function CollectInjectorsContent(portion)
	for _, entity in queue_ipairs(global.entities["subspace-item-injector"], portion) do
		CollectItemInjectorContent(entity)
	end
	for _, entity in queue_ipairs(global.entities["subspace-fluid-injector"], portion) do
		CollectFluidInjectorContent(entity)
	end
	for _, entity in queue_ipairs(global.entities["subspace-electricity-injector"], portion) do
		CollectElectricityInjectorContent(entity)
	end
end

local function CollectItemExtractorRequests(entity)
	if not entity.valid or entity.to_be_deconstructed(entity.force) then
		return
	end

	local inventory = entity.get_inventory(defines.inventory.chest)

	local freeStacks = inventory.count_empty_stacks()
	for i = 1, entity.request_slot_count do
		local request = entity.get_request_slot(i)
		if request then
			local stack = game.item_prototypes[request.name].stack_size
			local required = math.min(request.count - inventory.get_item_count(request.name), freeStacks * stack)
			if required > 0 then
				freeStacks = freeStacks - math.ceil(required / stack)
				table.insert(global.local_requests, { entity = entity, name = request.name, count = required })
			end
		end
	end
end

local function CollectFluidExtractorRequests(entity)
	if not entity.valid then
		return
	end

	local fluidbox = entity.fluidbox

	local request = entity.get_recipe()
	if request then
		local fluid = fluidbox[1]
		if not fluid or fluid.name ~= request.products[1].name then
			fluid = { name = request.products[1].name, amount = 0 }
		end

		local required = math.ceil(MAX_FLUID_AMOUNT - fluid.amount)
		if required > 0 then
			table.insert(global.local_requests, { entity = entity, name = fluid.name, count = required })
		end
	end
end

local function CollectElectricityExtractorRequests(entity)
	if not entity.valid then
		return
	end

	local required = math.floor((entity.electric_buffer_size - entity.energy) / ELECTRICITY_RATIO)
	if required > 0 then
		table.insert(global.local_requests, { entity = entity, name = ELECTRICITY_ITEM_NAME, count = required })
	end
end

function CollectExtractorsRequests(portion)
	for _, entity in queue_ipairs(global.entities["subspace-item-extractor"], portion) do
		CollectItemExtractorRequests(entity)
	end
	for _, entity in queue_ipairs(global.entities["subspace-fluid-extractor"], portion) do
		CollectFluidExtractorRequests(entity)
	end
	if math.fmod(global.iteration, ITERATIONS_TO_COLLECT_ELECTRICITY_REQUESTS) == 0 then
		for _, entity in queue_ipairs(global.entities["subspace-electricity-extractor"], portion) do
			CollectElectricityExtractorRequests(entity)
		end
	end
end

local function InsertIntoItemExtractor(entity, name, count)
	if not entity.valid then
		return 0
	end
	return entity.get_inventory(defines.inventory.chest).insert { name = name, count = count }
end

local function InsertIntoFluidExtractor(entity, name, count)
	if not entity.valid then
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

local function InsertIntoElectricityExtractor(entity, _, count)
	if not entity.valid then
		return 0
	end
	entity.energy = entity.energy + count * ELECTRICITY_RATIO
	return count
end

local function FulfillRequest(requests, request, insert)
	-- TODO Gather the sums while requests are collected.
	local total_count = 0
	for _, r in ipairs(requests) do
		if r.name == request.name then
			total_count = total_count + r.count
		end
	end

	local entity = request.entity
	local position = relative(entity.surface, entity.force, entity.position)

	local count = 0
	if settings.global["subspace_storage-infinity-mode"].value then
		count = total_count
	else
		local entry = get(global.local_storage, entity.force.name, position.x, position.y, request.name);
		if not entry then
			count = 0
		else
			count = math.min(entry.remaining, total_count)
			entry.remaining = entry.remaining - count
			entry.accessed = game.tick
		end
	end

	--need to scale all the requests according to how much of the requested items are available.
	--Can't be more than 100% because otherwise the chests will overfill
	function GetInitialItemCount(itemName)
		--this method is used so the mod knows hopw to distribute
		--the items between all entities. If infinite resources is enabled
		--then all entities should get their requests fulfilled-
		--To simulate that this method returns 1mil which should be enough
		--for all entities to fulfill their whole item request
		if settings.global["subspace_storage-infinity-mode"].value then
			return 1000000 --1.000.000
		end

		if global.local_storage[itemName] == nil then
			return 0
		end
		return global.local_storage[itemName].initialItemCount
	end

	local available = GetInitialItemCount(request.name)

	local avaiableItemsRatio = math.min(available / total_count, 1)
	--Floor is used here so no chest uses more than its fair share.
	--If they used more then the last entity would bet less which would be
	--an issue with +1000 entities requesting items.
	local chestHold = math.floor(request.count * avaiableItemsRatio)
	--If there is less items than requests then floor will return zero and thus not
	--distributes the remaining items. Thus here the mining is set to 1 but still
	--it can't be set to 1 if there is no more items to distribute, which is what
	--the last min corresponds to.
	chestHold = math.max(chestHold, 1)
	chestHold = math.min(chestHold, count)

	--If there wasn't enough items to fulfill the whole request
	--then ask for more items from outside the game
	local missingItems = request.count - chestHold
	if missingItems > 0 then
		set(global.global_requests, force, x, y, request.itemName, missingItems)
	end

	if count > 0 then
		--No need to insert 0 of something
		if chestHold > 0 then
			local insertedItemsCount = insert(request, request.itemName, chestHold)
			count = count - insertedItemsCount
		end

		--In some cases it's possible for the entity to not use up
		--all the items.
		--In those cases the items should be put back into storage.
		if count > 0 then
			if global.local_storage[request.itemName] == nil then
				global.local_storage[request.itemName] =
				{
					initialItemCount = 0,
					remainingItems = 0,
					lastPull = game.tick,
				}
			end
			global.local_storage[request.itemName].remainingItems = global.local_storage[request.itemName].remainingItems +
			count
		end
	end
end

function FulfillExtractorsRequests(portion)
	for _, request in queue_ipairs(global.local_requests["subspace-item-extractor"], portion) do
		FulfillRequest(global.local_requests["subspace-item-extractor"], request, InsertIntoItemExtractor)
	end
	for _, request in queue_ipairs(global.local_requests["subspace-fluid-extractor"], portion) do
		FulfillRequest(global.local_requests["subspace-fluid-extractor"], request, InsertIntoFluidExtractor)
	end
	if math.fmod(global.iteration, ITERATIONS_TO_COLLECT_ELECTRICITY_REQUESTS) == 0 then
		for _, request in queue_ipairs(global.local_requests["subspace-electricity-extractor"], portion) do
			FulfillRequest(global.local_requests["subspace-electricity-extractor"], request, InsertIntoElectricityExtractor)
		end
	end
end

------------------------------------------
-- [[Methods that talk with Clusterio]] --
------------------------------------------
function ReceiveEndpoints(data)
	local endpoints = game.json_to_table(data)
	-- TODO
end

function SetStorage(data)
	global.global_storage = parse(data)
	UpdateStorageCombinators()
end

function UpdateStorage(data)
	for _, item in ipairs(game.json_to_table(data)) do
		set(global.global_storage, item[1], item[2], item[3], item[4], item[5])
	end
	UpdateStorageCombinators()
end

function SendItems()
	if not next(global.outbox) then
		return
	end
	clusterio_api.send_json("subspace_storage:send_items", serialize(global.outbox))
	global.outbox = {}
end

function RequestItems()
	if not next(global.global_requests) then
		return
	end
	clusterio_api.send_json("subspace_storage:request_items", serialize(global.global_requests))
	global.global_requests = {}
end

function ReceiveItems(data)
	for _, item in ipairs(game.json_to_table(data)) do
		update(global.inbox, item[1], item[2], item[3], item[4], function(c) return (c or 0) + item[5] end)
	end
end

---------------------------------
-- [[Update combinator methods]] --
---------------------------------
function UpdateStorageCombinators()
	-- Update all inventory Combinators
	-- Prepare a frame from the last inventory report, plus any virtuals
	local invframe = {}
	local instance_id = clusterio_api.get_instance_id()
	if instance_id then
		-- Clamp to 32-bit to avoid error raised by Factorio
		instance_id = math.min(instance_id, 0x7fffffff)
		instance_id = math.max(instance_id, -0x80000000)
		table.insert(invframe,
			{ count = instance_id, index = #invframe + 1, signal = { name = "signal-localid", type = "virtual" } })
	end

	local items = game.item_prototypes
	local fluids = game.fluid_prototypes
	local virtuals = game.virtual_signal_prototypes
	if global.global_storage then
		for name, count in pairs(global.global_storage) do
			-- Combinator signals are limited to a max value of 2^31-1
			count = math.min(count, 0x7fffffff)
			if items[name] then
				invframe[#invframe + 1] = { count = count, index = #invframe + 1, signal = { name = name, type = "item" } }
			elseif fluids[name] then
				invframe[#invframe + 1] = { count = count, index = #invframe + 1, signal = { name = name, type = "fluid" } }
			elseif virtuals[name] then
				invframe[#invframe + 1] = { count = count, index = #invframe + 1, signal = { name = name, type = "virtual" } }
			end
		end
	end

	for i, invControl in pairs(global.invControls) do
		if invControl.valid then
			compat.set_parameters(invControl, invframe)
			invControl.enabled = true
		end
	end
end

----------------------
-- [[Endpoints UI]] --
----------------------

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
		global.zones[player.name] = rendering.draw_rectangle {
			color = { r = 0.8, g = 0.1, b = 0 },
			width = 12,
			filled = false,
			left_top = { sx - width / 2, sy - height / 2 },
			right_bottom = { sx + width / 2, sy + height / 2 },
			surface = player.surface,
			players = { player },
			draw_on_ground = true,
		}
	elseif not mod_entities[entity] and global.zones[player.name] then
		rendering.destroy(global.zones[player.name])
		global.zones[player.name] = nil
	end
end)
