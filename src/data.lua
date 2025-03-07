require("util")
require("config")

require("prototypes/entities")

local tint = { r = 100, g = 200, b = 255, a = 255 }

data:extend {
	{
		type = "sprite",
		name = "clusterio",
		filename = "__subspace_storage__/graphics/icons/clusterio.png",
		priority = "medium",
		width = 128,
		height = 128,
		flags = { "icon" }
	},
	-- Subgroup for new subspace interactors recipes
	{
		type = "item-subgroup",
		name = "subspace-logistics",
		group = "logistics",
		order = "g-subspace_storage", -- After logistic-network
	},

	-- "Extract fluid" recipe category, in order to simulate non-existent "fluid requests" via recipe selection
	{
		type = "recipe-category",
		name = "subspace-extraction"
	},

	-- Virtual signals
	{
		type = "item-subgroup",
		name = "virtual-signal-clusterio",
		group = "signals",
		order = "e"
	},
	{
		type = "virtual-signal",
		name = "signal-localid",
		icon = "__subspace_storage__/graphics/icons/signal_localid.png",
		icon_size = 32,
		subgroup = "virtual-signal-clusterio",
		order = "e[clusterio]-[4localid]"
	},
	{
		type = "virtual-signal",
		name = "electricity",
		icon = "__subspace_storage__/graphics/icons/signal_electricity.png",
		icon_size = 32,
		subgroup = "virtual-signal-clusterio",
		order = "e[clusterio]-[5electricity]"
	},
	-- Intermediate resources
	{
		type = "item",
		name = "antimatter",
		icons = {
			{
				icon = data.raw["item"]["uranium-238"].icon,
				tint = { r = 150, g = 0, b = 150, a = 150 },
			}
		},
		icon_size = data.raw["item"]["uranium-238"].icon_size,
		flags = {},
		subgroup = data.raw["item"]["uranium-238"].subgroup,
		order = "b[uranium-products]-d[antimatter]", -- After Kovarex
		stack_size = 1,
	},
	{
		type = "recipe",
		name = "antimatter",
		enabled = true, -- TODO do this on a tech somewhere
		category = "centrifuging",
		ingredients =
		{
			{ "uranium-238", 40 },
			{ "raw-fish",    1 }
		},
		energy_required = 60,
		emissions_multiplier = 100,
		result = "antimatter",
		requester_paste_multiplier = 1
	},
}

-- Inventory Combinator
local combinator = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
combinator.name = "subspace-inventory-combinator"
combinator.minable.result = "subspace-inventory-combinator"
combinator.item_slot_count = 2000
for _, sprite in pairs(combinator.sprites) do
	sprite.layers[1].tint = tint
	sprite.layers[1].hr_version.tint = tint
end
data:extend {
	combinator,
	{
		type = "item",
		name = "subspace-inventory-combinator",
		icons = {
			{
				icon = combinator.icon,
				tint = tint,
			}
		},
		icon_size = combinator.icon_size,
		flags = {},
		subgroup = "subspace-logistics",
		place_result = "subspace-inventory-combinator",
		order = "c[subspace-inventory-combinator]",
		stack_size = 50,
	},
	{
		type = "recipe",
		name = "subspace-inventory-combinator",
		enabled = true, -- TODO do this on a tech somewhere
		ingredients =
		{
			{ "constant-combinator", 1 },
			{ "electronic-circuit",  50 },
			{ "antimatter",          1 },
		},
		result = "subspace-inventory-combinator",
		requester_paste_multiplier = 1
	},
}
