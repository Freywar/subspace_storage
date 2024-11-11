require("util")
require("config")

require("prototypes/entities")

--adds a recipe to a tech and returns true or if that fails returns false
function AddEntityToTech(techName, name)
	--can't add the recipe to the tech if it doesn't exist
	if data.raw["technology"][techName] ~= nil then
		local effects = data.raw["technology"][techName].effects
		--if another mod removed the effects or made it nil then make a new table to put the recipe in
		effects = effects or {}
		--insert the recipe as an unlock when the research is done
		effects[#effects + 1] = {
			type = "unlock-recipe",
			recipe = name
		}
		--if a new table for the effects is made then the effects has to be attached to the
		-- tech again because the table won't otherwise be owned by the tech
		data.raw["technology"][techName].effects = effects
		return true
	end
	return false
end

-- Do some magic nice stuffs
data:extend(
	{
		{
			type = "item-subgroup",
			name = "subspace_storage-interactor",
			group = "logistics",
			order = "g-subspace_storage", -- After logistic-network
		},
	})

data:extend(
	{
		{
			type = "recipe-category",
			name = RECIPE_CATEGORY
		}
	})

-- Virtual signals
data:extend {
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
		name = "signal-unixtime",
		icon = "__subspace_storage__/graphics/icons/signal_unixtime.png",
		icon_size = 32,
		subgroup = "virtual-signal-clusterio",
		order = "e[clusterio]-[5unixtime]"
	},
	{
		type = "virtual-signal",
		name = "electricity",
		icon = "__subspace_storage__/graphics/icons/signal_electricity.png",
		icon_size = 32,
		subgroup = "virtual-signal-clusterio",
		order = "e[clusterio]-[5electricity]"
	},
}

-- Inventory Combinator
local storage_combinator = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
local tint = { r = 100, g = 200, b = 255, a = 255 }
storage_combinator.name = "subspace-storage-combinator"
storage_combinator.minable.result = storage_combinator.name
storage_combinator.item_slot_count = 2000
for _, sprite in pairs(storage_combinator.sprites) do
	sprite.layers[1].tint = tint
	sprite.layers[1].hr_version.tint = tint
end
data:extend {
	storage_combinator,
	{
		type = "item",
		name = storage_combinator.name,
		icons = {
			{
				icon = storage_combinator.icon,
				tint = tint,
			}
		},
		icon_size = storage_combinator.icon_size,
		flags = {},
		subgroup = "subspace_storage-interactor",
		place_result = storage_combinator.name,
		order = "c[" .. storage_combinator.name .. "]",
		stack_size = 50,
	},
	{
		type = "recipe",
		name = storage_combinator.name,
		enabled = true, -- TODO do this on a tech somewhere
		ingredients =
		{
			{ "constant-combinator", 1 },
			{ "electronic-circuit",  50 }
		},
		result = storage_combinator.name,
		requester_paste_multiplier = 1
	},
}

data:extend(
	{
		{
			type = "sprite",
			name = "clusterio",
			filename = "__subspace_storage__/graphics/icons/clusterio.png",
			priority = "medium",
			width = 128,
			height = 128,
			flags = { "icon" }
		}
	}
)
