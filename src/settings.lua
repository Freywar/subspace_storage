require("config")

data:extend {
	{
		type = "int-setting",
		name = "subspace_storage-max-items",
		setting_type = "runtime-global",
		order = "a1",
		default_value = 4800
	},
	{
		type = "int-setting",
		name = "subspace_storage-max-fluid",
		setting_type = "runtime-global",
		order = "a2",
		default_value = 25000
	},
	{
		type = "int-setting",
		name = "subspace_storage-max-electricity",
		setting_type = "runtime-global",
		order = "a3",
		default_value = 10000000000 / ELECTRICITY_RATIO --10GJ assuming a ratio of 1.000.000
	},
	{
		type = "bool-setting",
		name = "subspace_storage-infinity-mode",
		setting_type = "runtime-global",
		order = "b1",
		default_value = false,
	},
}
