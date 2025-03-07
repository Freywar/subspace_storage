local icons = require("entity_icons")
local pictures = require("entity_pictures")


-- We copy certain properties from the vanilla steel chest and storage tank
local steel_chest = data.raw["container"]["steel-chest"]
local storage_tank = data.raw["storage-tank"]["storage-tank"]
local accumulator = data.raw["accumulator"]["accumulator"]

-- Circuit connector helpers are defined in lualib/circuit-connector-sprites
-- but due to the shared lua env for data stage it just exists as a global.
local connector_definition = { variation = 25, main_offset = { 1.875, 1 }, shadow_offset = { 4.5, 2.5625 } }
local interactor_circuit_connector_1_way = circuit_connector_definitions.create(
	universal_connector_template,
	{
		connector_definition,
	}
)

local interactor_circuit_connector_4_way = circuit_connector_definitions.create(
	universal_connector_template,
	{
		connector_definition,
		connector_definition,
		connector_definition,
		connector_definition,
	}
)

local standard_ingredients = {
	{ "electronic-circuit", 50 },
	{ "antimatter",         1 },
}

local function subspace_interactor_entity(options)
	for _, v in ipairs(standard_ingredients) do
		table.insert(options.ingredients, v)
	end

	local entity = {
		name = options.name,
		icon = icons[options.name],
		icon_size = 64,
		icon_mipmaps = 4,
		flags = { "placeable-player", "player-creation" },
		minable = { mining_time = 4, result = options.name },
		max_health = 500,
		corpse = nil,
		dying_explosion = nil,
		collision_box = { { -3.7, -3.7 }, { 3.7, 3.7 } },
		selection_box = { { -4, -4 }, { 4, 4 } },
		damaged_trigger_effect = steel_chest.damaged_trigger_effect,
		resistances = {
			{ type = "fire",   percent = 90 },
			{ type = "impact", percent = 60 },
		},
		fast_replaceable_group = "subspace-interactor",
		vehicle_impact_sound = steel_chest.vehicle_impact_sound,
		picture = pictures[options.name],
	}

	if options.circuit_connector then
		entity.circuit_wire_connection_points = options.circuit_connector.points
		entity.circuit_wire_connection_point = options.circuit_connector.points
		entity.circuit_connector_sprites = options.circuit_connector.sprites
		entity.circuit_wire_max_distance = 9
	end


	for key, value in pairs(options.entity_properties) do
		entity[key] = value
	end

	data:extend {
		{
			type = "recipe",
			name = options.name,
			enabled = true,
			ingredients = options.ingredients,
			result = options.name,
			requester_paste_multiplier = options.requester_paste_multiplier or 4,
		},
		{
			type = "item",
			name = options.name,
			icon = icons[options.name],
			icon_size = 64, icon_mipmaps = 4,
			subgroup = options.subgroup or "subspace-logistics",
			order = options.order,
			place_result = options.name,
			stack_size = options.stack_size or 50,
		},
		entity,
	}
end

-----------------------------------
--[[Make subspace interactors]] --
-----------------------------------

subspace_interactor_entity {
	name = "subspace-item-injector",
	order = "a[injector]-a[subspace-item-injector]",
	ingredients = {
		{ "steel-chest", 1 }
	},
	entity_properties = {
		type = "container",
		inventory_size = 60,
		open_sound = steel_chest.open_sound,
		close_sound = steel_chest.close_sound,
	},
	circuit_connector = interactor_circuit_connector_1_way,
}

subspace_interactor_entity {
	name = "subspace-item-extractor",
	order = "b[extractor]-a[subspace-item-extractor]",
	ingredients = {
		{ "steel-chest", 1 }
	},
	entity_properties = {
		type = "logistic-container",
		inventory_size = 60,
		logistic_mode = "buffer",
		render_not_in_network_icon = false,
		open_sound = steel_chest.open_sound,
		close_sound = steel_chest.close_sound,
	},
	circuit_connector = interactor_circuit_connector_1_way,
}

subspace_interactor_entity {
	name = "subspace-fluid-injector",
	order = "a[injector]-b[subspace-fluid-injector]",
	ingredients = {
		{ "storage-tank", 1 }
	},
	entity_properties = {
		type = "storage-tank",
		fluid_box = {
			production_type = "input",
			base_area = 250,
			pipe_covers = pipecoverspictures(),
			pipe_connections = {
				{ type = "input", position = { -4.5, -2.5 } },
				{ type = "input", position = { -4.5, 2.5 } },
				{ type = "input", position = { -2.5, 4.5 } },
				{ type = "input", position = { 2.5, 4.5 } },
				{ type = "input", position = { 4.5, 2.5 } },
				{ type = "input", position = { 4.5, -2.5 } },
				{ type = "input", position = { 2.5, -4.5 } },
				{ type = "input", position = { -2.5, -4.5 } },
			},
		},
		window_bounding_box = { { -0.125, 0.6875 }, { 0.1875, 1.1875 } },
		pictures = {
			picture = pictures["subspace-fluid-injector"],
			window_background = storage_tank.pictures.window_background,
			fluid_background = storage_tank.pictures.fluid_background,
			flow_sprite = storage_tank.pictures.flow_sprite,
			gas_flow = storage_tank.pictures.gas_flow,
		},
		flow_length_in_ticks = 360,
		working_sound = storage_tank.working_sound,
		open_sound = storage_tank.open_sound,
		close_sound = storage_tank.close_sound,
	},
	circuit_connector = interactor_circuit_connector_4_way,
}

subspace_interactor_entity {
	name = "subspace-fluid-extractor",
	order = "b[extractor]-b[subspace-fluid-extractor]",
	ingredients = {
		{ "storage-tank", 1 }
	},
	entity_properties = {
		type = "assembling-machine",
		fluid_boxes = {
			{
				production_type = "output",
				pipe_covers = pipecoverspictures(),
				base_area = 250,
				base_level = 1,
				pipe_connections = {
					{ type = "output", position = { -4.5, -2.5 } },
					{ type = "output", position = { -4.5, 2.5 } },
					{ type = "output", position = { -2.5, 4.5 } },
					{ type = "output", position = { 2.5, 4.5 } },
					{ type = "output", position = { 4.5, 2.5 } },
					{ type = "output", position = { 4.5, -2.5 } },
					{ type = "output", position = { 2.5, -4.5 } },
					{ type = "output", position = { -2.5, -4.5 } },
				},
			},
			off_when_no_fluid_recipe = false,
		},
		open_sound = storage_tank.open_sound,
		close_sound = storage_tank.close_sound,
		animation = pictures["subspace-fluid-extractor"],
		crafting_categories = { "subspace-extraction" },
		crafting_speed = 1,
		energy_source = {
			type = "electric",
			usage_priority = "secondary-input",
			emissions_per_minute = 2,
		},
		energy_usage = "1kW",
		ingredient_count = 1,
		module_specification = nil,
		allowed_effects = nil,
	},
}

subspace_interactor_entity {
	name = "subspace-electricity-injector",
	ingredients = {
		{ "substation",  1 },
		{ "accumulator", 2000 },
	},
	requester_paste_multiplier = 1,
	order = "a[injector]-c[subspace-electricity-injector]",
	stack_size = 5,
	entity_properties = {
		type = "accumulator",
		energy_source = {
			type = "electric",
			buffer_capacity = "10GJ",
			usage_priority = "tertiary",
			input_flow_limit = "1GW",
			output_flow_limit = "0kW"
		},
		charge_cooldown = 30,
		discharge_cooldown = 60,
		open_sound = accumulator.open_sound,
		close_sound = accumulator.close_sound,
		default_output_signal = { type = "virtual", name = "signal-E" },
	},
	circuit_connector = interactor_circuit_connector_1_way,
}

subspace_interactor_entity {
	name = "subspace-electricity-extractor",
	ingredients = {
		{ "substation",  1 },
		{ "accumulator", 2000 },
	},
	requester_paste_multiplier = 1,
	subgroup = "subspace-logistics",
	order = "b[extractor]-c[subspace-electricity-extractor]",
	stack_size = 5,
	entity_properties = {
		type = "accumulator",
		energy_source = {
			type = "electric",
			buffer_capacity = "10GJ",
			usage_priority = "tertiary",
			input_flow_limit = "0kW",
			output_flow_limit = "1GW"
		},
		charge_cooldown = 30,
		discharge_cooldown = 60,
		open_sound = accumulator.open_sound,
		close_sound = accumulator.close_sound,
		default_output_signal = { type = "virtual", name = "signal-E" },
	},
	circuit_connector = interactor_circuit_connector_1_way,
}
