require("config")

data:extend {
	{
		type = "int-setting",
		name = "subspace_storage-injector-queue-ticks",
		setting_type = "runtime-global",
		order = "a[queueing]-1[injectors]-1[ticks]",
		default_value = 5
	},
	{
		type = "int-setting",
		name = "subspace_storage-injector-queue-size",
		setting_type = "runtime-global",
		order = "a[queueing]-1[injectors]-2[queue]",
		default_value = 5
	},
	{
		type = "int-setting",
		name = "subspace_storage-extractor-queue-ticks",
		setting_type = "runtime-global",
		order = "a[queueing]-2[extractors]-1[ticks]",
		default_value = 6
	},
	{
		type = "int-setting",
		name = "subspace_storage-extractor-queue-size",
		setting_type = "runtime-global",
		order = "a[queueing]-2[extractors]-2[queue]",
		default_value = 5
	},
	{
		type = "int-setting",
		name = "subspace_storage-combinator-queue-ticks",
		setting_type = "runtime-global",
		order = "a[queueing]-3[combinators]-1[ticks]",
		default_value = 6
	},
	{
		type = "int-setting",
		name = "subspace_storage-combinator-queue-size",
		setting_type = "runtime-global",
		order = "a[queueing]-3[combinators]-2[queue]",
		default_value = 5
	},
	{
		type = "int-setting",
		name = "subspace_storage-electricity-queue-multiplier",
		setting_type = "runtime-global",
		order = "a[queueing]-4[electricity]",
		default_value = 5
	},

	{
		type = "int-setting",
		name = "subspace_storage-inject-call-ticks",
		setting_type = "runtime-global",
		order = "b[networking]-1[inject]",
		default_value = 59
	},
	{
		type = "int-setting",
		name = "subspace_storage-extract-call-ticks",
		setting_type = "runtime-global",
		order = "b[networking]--2[extract]",
		default_value = 61
	},
	{
		type = "int-setting",
		name = "subspace_storage-recycling-ticks",
		setting_type = "runtime-global",
		order = "b[networking]-3[recycling]",
		default_value = 601
	},
	{
		type = "int-setting",
		name = "subspace_storage-connection-timeout",
		setting_type = "runtime-global",
		order = "b[misc]-4[timeout]",
		default_value = 300,
	},

	{
		type = "int-setting",
		name = "subspace_storage-max-items",
		setting_type = "runtime-global",
		order = "c[limits]-1[items]",
		default_value = 4800
	},
	{
		type = "int-setting",
		name = "subspace_storage-max-fluid",
		setting_type = "runtime-global",
		order = "c[limits]-2[fluid]",
		default_value = 25000
	},
	{
		type = "int-setting",
		name = "subspace_storage-max-electricity",
		setting_type = "runtime-global",
		order = "c[limits]-3[electricity]",
		default_value = 10000 -- 10GJ, using ELECTRICITY_UNIT
	},
	{
		type = "bool-setting",
		name = "subspace_storage-infinity-mode",
		setting_type = "runtime-global",
		order = "d[misc]-2[infinity]",
		default_value = false,
	},
}
