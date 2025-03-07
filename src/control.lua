require("util")
require("config")

require('lib.interactors')
local ItemStorage = require("lib.item-storage")

local clusterio_api = require("__clusterio_lib__/api")

local chunk_size = 32

local function recycle()
	-- TODO Should probably do it on item basis with expiration date.
	for force, cx, cy, item, count in global.inbox:entries() do
		global.outbox:update(force, cx, cy, item, function(c) return (c or 0) + count end)
	end
	global.inbox:clear()
end

local function inject()
	local items = {}
	for force, cx, cy, name, count in global.outbox:entries() do
		table.insert(items, { force, cx, cy, name, count })
	end

	if not settings.global["subspace_storage-infinity-mode"].value and #items > 0 then
		clusterio_api.send_json("subspace_storage:inject", items)
	end
	global.outbox:clear()
end

local function extract()
	local items = {}
	for force, cx, cy, item, entry in global.requests:entries() do
		local total = 0
		for _, count in ipairs(entry) do
			total = total + count
		end
		table.insert(items, { force, cx, cy, item, total })
	end
	if not settings.global["subspace_storage-infinity-mode"].value and #items > 0 then
		clusterio_api.send_json("subspace_storage:extract", items)
	end
	global.requests:clear()
end

local function init_clusterio()
	clusterio_api.init()
	script.on_event(clusterio_api.events.on_instance_updated, function() update_inventory("[]") end)
end

local function init_data()
	rendering.clear("subspace_storage")

	global.ping_tick = 0

	-- Inventory of all the items available in the subspace.
	global.inventory = ItemStorage:new()

	-- Items to be requested from the subspace.
	global.requests = ItemStorage:new()
	-- Items received from the subspace to be delivered to injectors.
	global.inbox = global.inbox or ItemStorage:new()
	-- Items to be sent into the subspace.
	global.outbox = global.outbox or ItemStorage:new()
	-- Signals for the combinators, cached from `global.inventory`.
	global.signals = ItemStorage:new()

	global.zones = {}

	init_interactors()
end

script.on_init(function()
	init_clusterio()
	init_data()
end)

script.on_load(function()
	init_clusterio()
end)

script.on_configuration_changed(function(data)
	if not data.mod_changes or not data.mod_changes["subspace_storage"] then
		return
	end
	init_data()
end)

script.on_event(defines.events.on_built_entity, function(event) register_interactor(event.created_entity) end)
script.on_event(defines.events.on_robot_built_entity, function(event) register_interactor(event.created_entity) end)

script.on_event(defines.events.on_entity_died, function(event) unregister_interactor(event.entity) end)
script.on_event(defines.events.on_robot_pre_mined, function(event) unregister_interactor(event.entity) end)
script.on_event(defines.events.on_pre_player_mined_item, function(event) unregister_interactor(event.entity) end)
script.on_event(defines.events.script_raised_destroy, function(event) unregister_interactor(event.entity) end)

script.on_event(defines.events.on_tick, function(event)
	if not settings.global["subspace_storage-infinity-mode"].value
			and event.tick - global.ping_tick > settings.global["subspace_storage-connection-timeout"].value then
		global.inventory:clear()
		global.requests:clear()
		global.injectors:reset()
		global.extractors:reset()
		global.combinators:reset()
		return
	end

	if settings.global["subspace_storage-recycling-ticks"].value ~= 0
			and event.tick % settings.global["subspace_storage-recycling-ticks"].value == 0 then
		recycle()
	end

	if event.tick % settings.global["subspace_storage-injector-queue-ticks"].value == 0 then
		for _, entity in global.injectors:ipairs(settings.global["subspace_storage-injector-queue-size"].value) do
			if entity.name ~= "subspace-electricity-injector"
					or (event.tick / settings.global["subspace_storage-injector-queue-ticks"].value) % settings.global["subspace_storage-electricity-queue-multiplier"].value == 0 then
				process_injector(entity)
			end
		end
		if settings.global["subspace_storage-inject-call-ticks"].value == 0 and global.injectors.pos == 0 then
			inject()
		end
	end

	if settings.global["subspace_storage-inject-call-ticks"].value ~= 0
			and event.tick % settings.global["subspace_storage-inject-call-ticks"].value == 0 then
		inject()
	end

	if event.tick % settings.global["subspace_storage-extractor-queue-ticks"].value == 0 then
		for _, entity in global.extractors:ipairs(settings.global["subspace_storage-extractor-queue-size"].value) do
			if entity.name ~= "subspace-electricity-injector"
					or (event.tick / settings.global["subspace_storage-injector-queue-ticks"].value) % settings.global["subspace_storage-electricity-queue-multiplier"].value == 0 then
				process_extractor(entity)
			end
		end
		if global.extractors.pos == 0 then
			if settings.global["subspace_storage-recycling-ticks"].value == 0 then
				recycle()
			end
			if settings.global["subspace_storage-extract-call-ticks"].value == 0 then
				extract()
			end
		end
	end

	if settings.global["subspace_storage-extract-call-ticks"].value ~= 0
			and event.tick % settings.global["subspace_storage-extract-call-ticks"].value == 0 then
		extract()
	end

	if settings.global["subspace_storage-combinator-queue-ticks"].value ~= 0
			and event.tick % settings.global["subspace_storage-combinator-queue-ticks"].value == 0 then
		for _, entity in global.combinators:ipairs(settings.global["subspace_storage-combinator-queue-size"].value) do
			process_combinator(entity)
		end
	end
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
	local player = game.players[event.player_index]
	if not player or not player.valid then
		return
	end

	local held_item =
			player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.name
			or player.cursor_ghost
	if held_item and subspace_interactors[held_item] then
		if not global.zones[event.player_index] then
			local spawn_position = player.force.get_spawn_position(player.surface)

			global.zones[event.player_index] = {}
			for force, cx, cy, _, _ in global.inventory:entries() do
				if force == player.force.name then
					table.insert(global.zones[event.player_index], rendering.draw_rectangle {
						color = { r = 0.8, g = 0.1, b = 0, a = 0.5 },
						filled = true,
						left_top = { cx * CHUNK_SIZE + spawn_position.x, cy * CHUNK_SIZE + spawn_position },
						right_bottom = { cx * CHUNK_SIZE + spawn_position.x + CHUNK_SIZE, cy * CHUNK_SIZE + spawn_position + CHUNK_SIZE },
						surface = player.surface,
						players = { player },
						draw_on_ground = true,
					})
				end
			end
		end
	else
		if global.zones[event.player_index] then
			for _, zone in ipairs(global.zones[event.player_index]) do
				rendering.destroy(zone)
			end
			global.zones[event.player_index] = nil
		end
	end
end)

-- Public endpoints for Clusterio plugin

function receive_items(data)
	for _, item in ipairs(game.json_to_table(data)) do
		global.inbox:update(item[1], item[2], item[3], item[4], function(c) return (c or 0) + item[5] end)
	end
end

function update_inventory(data, reset)
	if reset then
		global.inventory:clear()
	end
	for _, item in ipairs(game.json_to_table(data)) do
		global.inventory:set(item[1], item[2], item[3], item[4], item[5])
	end
	if settings.global["subspace_storage-combinator-queue-ticks"].value > 0 then
		global.combinators:reset()
		for _, entity in global.combinators:ipairs() do
			process_combinator(entity)
		end
	end
end
