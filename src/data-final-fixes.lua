require("config")

for _, fluid in pairs(data.raw.fluid) do
	if not fluid.hidden then
		data:extend {
			{
				type = "recipe",
				name = "subspace_storage-extract-" .. fluid.name,
				category = "subspace-extraction",
				energy_required = 1,
				subgroup = "fill-barrel",
				order = "b[fill-crude-oil-barrel]",
				enabled = true,
				ingredients = {},
				results =
				{
					{ type = "fluid", name = fluid.name, amount = 0 }
				}
			}
		}
	end
end
