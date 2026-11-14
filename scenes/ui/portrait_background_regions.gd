extends RefCounted
## Sol-reviewed negative-space background only, on two immutable source images.
## Never remove arbitrary enclosed white: armour, wings, blade and aura stay.
## RGBA fingerprint + exact connected-component size make changed art fail closed.
const REGIONS := {
	&"creature_dragnar_shadow": {
		"rgba_sha256": "f3e9e2f288ab933a27ca73fcd6808acd2d36e310c62bbaa45a60b881d1539eee",
		"components": [
			{"seed": Vector2i(66, 159), "pixels": 2115, "reason": "empty background inside tail loop"},
			{"seed": Vector2i(104, 146), "pixels": 457, "reason": "empty gap between arm and torso"},
		],
	},
	&"creature_levian_shadow": {
		"rgba_sha256": "561c7aca14c0d53b5489e2f6fbef0f5e6d68836c887b6283c69f48fc48d9b088",
		"components": [
			{"seed": Vector2i(104, 141), "pixels": 841, "reason": "empty background below left wing"},
			{"seed": Vector2i(89, 198), "pixels": 79, "reason": "narrow empty gap inside coiled tail"},
		],
	},
}

## Additional negative-space gaps reviewed in the battle HUD. Kept separate
## from the common matte so portraits outside battle retain their look.
const BATTLE_REGIONS := {
	&"creature_dragnar_gale": {
		"rgba_sha256": "0a4216c0a9789b11f5088da09bf55bbb2375a540e3d4d81c03ea67195c272355",
		"components": [
			{"seed": Vector2i(66, 160), "pixels": 2091, "reason": "gap inside curled tail"},
			{"seed": Vector2i(105, 145), "pixels": 446, "reason": "gap between arm and torso"},
		],
	},
	&"creature_dragnar_light": {
		"rgba_sha256": "0325622e16916fec7c5f44deaa5a6be7458b27e3572ea0a5b74a9a8f9c94ab01",
		"components": [
			{"seed": Vector2i(105, 145), "pixels": 509, "reason": "gap between arm and torso"},
		],
	},
	&"creature_dragnar_stone": {
		"rgba_sha256": "15891b242699cb3bf65a707d569ed642a452f244022f6034e22948bb967f3720",
		"components": [
			{"seed": Vector2i(105, 145), "pixels": 443, "reason": "gap between arm and torso"},
		],
	},
	&"creature_dragnar_tide": {
		"rgba_sha256": "a1577a7d3af2974c6bbb8ea29c5b381e90a87d5be71133ffaad4f76c80cd9248",
		"components": [
			{"seed": Vector2i(105, 146), "pixels": 438, "reason": "gap between arm and torso"},
		],
	},
	&"creature_gorgul_fire": {
		"rgba_sha256": "97656abb15438b97e0b34867461d4969fd7010622d4c2fc579a59b37987702b4",
		"components": [
			{"seed": Vector2i(173, 149), "pixels": 1071, "reason": "gap between arm, thigh and tail flames"},
			{"seed": Vector2i(148, 178), "pixels": 115, "reason": "gap between tail and leg"},
		],
	},
	&"creature_gorgul_gale": {
		"rgba_sha256": "34a13cfc86ee6a7dc70b105a70ddf0db0d35b09797cbf63b038b578d07a8fe3b",
		"components": [
			{"seed": Vector2i(148, 179), "pixels": 103, "reason": "gap between tail and leg"},
		],
	},
	&"creature_gorgul_light": {
		"rgba_sha256": "ccc9ee6fe62fe14d2cf21fc9530421ff57be003898be454c02138a9cddcb33b7",
		"components": [
			{"seed": Vector2i(148, 179), "pixels": 107, "reason": "gap between tail and leg"},
		],
	},
	&"creature_gorgul_shadow": {
		"rgba_sha256": "9b6b1a39d3752579b725847ea9ff249cd7f3e2fe0a434d781dc6e09a63ca2ce5",
		"components": [
			{"seed": Vector2i(148, 178), "pixels": 130, "reason": "gap between tail and leg"},
		],
	},
	&"creature_gorgul_stone": {
		"rgba_sha256": "ed92b3828e8a6138ed62c17c601f9f0ceb20d8cb34e289345aaa04341868faa5",
		"components": [
			{"seed": Vector2i(148, 179), "pixels": 109, "reason": "gap between tail and leg"},
		],
	},
	&"creature_gorgul_tide": {
		"rgba_sha256": "4762f5fb7370cc5c8e8f37d633b582811e838cf88e71f11520c9de70b34bed65",
		"components": [
			{"seed": Vector2i(148, 178), "pixels": 117, "reason": "gap between tail and leg"},
		],
	},
	&"creature_grifalon_fire": {
		"rgba_sha256": "1a94aec3a7f79ee1dbb3dcd8e020ba7d7ad012709ee855eb6f3ad962a35563bd",
		"components": [
			{"seed": Vector2i(100, 140), "pixels": 574, "reason": "gap between wing and torso"},
		],
	},
	&"creature_grifalon_gale": {
		"rgba_sha256": "e0d7b5675a03026b83b0718b22febeb79e28210d88da1f7a541e22c1210e47e8",
		"components": [
			{"seed": Vector2i(99, 141), "pixels": 485, "reason": "gap between wing and torso"},
		],
	},
	&"creature_grifalon_light": {
		"rgba_sha256": "68c9b6cf9ce0c5fc72f5e7e916b589d0328af43d17cc08becf89db0422102fe6",
		"components": [
			{"seed": Vector2i(102, 141), "pixels": 448, "reason": "gap between wing and torso"},
		],
	},
	&"creature_grifalon_shadow": {
		"rgba_sha256": "c35afded6cda5caf440c3f90208560b4ce740f2f8cf26dab32aedfeb39ee63fa",
		"components": [
			{"seed": Vector2i(103, 140), "pixels": 451, "reason": "gap between wing and torso"},
		],
	},
	&"creature_grifalon_stone": {
		"rgba_sha256": "3f7e02179e5ab5d4b47ca20b8df2d6a59fd708d75bc76f3d28789dc3f7ce9748",
		"components": [
			{"seed": Vector2i(101, 140), "pixels": 603, "reason": "gap between wing and torso"},
		],
	},
	&"creature_grifalon_tide": {
		"rgba_sha256": "9dca188d8953b54c08cbbe2cf4e18892b1f3c0de7e9a19d8b80858b61c6403bd",
		"components": [
			{"seed": Vector2i(96, 141), "pixels": 617, "reason": "gap between wing and torso"},
		],
	},
	&"creature_klykar_fire": {
		"rgba_sha256": "45c4d099c476baeff798d55dc3c59b964ddeba328e17d17d64b095ebb2824c0d",
		"components": [
			{"seed": Vector2i(116, 201), "pixels": 229, "reason": "gap between legs"},
		],
	},
	&"creature_klykar_gale": {
		"rgba_sha256": "0cb8c03d2d53b5be5601c7208acf88730b90c5a4f5cab2f1a32ed9837ea3e7c4",
		"components": [
			{"seed": Vector2i(117, 201), "pixels": 277, "reason": "gap between legs"},
		],
	},
	&"creature_klykar_light": {
		"rgba_sha256": "66ee3a14785db8b278a0c9f7f02a43ae8517b4a901d8e500bc6614583dd1ad08",
		"components": [
			{"seed": Vector2i(117, 199), "pixels": 365, "reason": "gap between legs"},
		],
	},
	&"creature_klykar_shadow": {
		"rgba_sha256": "b451f89ededf42c7819f26c72be41bb3287d295fcfcc54406d2d0f50c557ecd1",
		"components": [
			{"seed": Vector2i(115, 202), "pixels": 154, "reason": "gap between legs"},
		],
	},
	&"creature_klykar_stone": {
		"rgba_sha256": "d24bd6a09c08b0d5fd009a2cba1021b3f94d0fa9a4d01d5df3ec0f524cd3733d",
		"components": [
			{"seed": Vector2i(115, 202), "pixels": 156, "reason": "gap between legs"},
		],
	},
	&"creature_klykar_tide": {
		"rgba_sha256": "4d42f2cebd186332e6fc5dcc2c8e7e24e9000092b58f62f802f2a96c3c6a1932",
		"components": [
			{"seed": Vector2i(115, 202), "pixels": 96, "reason": "gap between legs"},
		],
	},
	&"creature_kolossar_fire": {
		"rgba_sha256": "c1b9e526f48d379e2ec8b9f3209b8d386650fe786ec593af2c75e33d3ded7e88",
		"components": [
			{"seed": Vector2i(86, 129), "pixels": 943, "reason": "gap between arm and torso"},
		],
	},
	&"creature_kolossar_tide": {
		"rgba_sha256": "f66ab532b49ed20fb61a8abf2c1634b9451fe6dd81e02013d15fd437d501205d",
		"components": [
			{"seed": Vector2i(86, 128), "pixels": 878, "reason": "gap between arm and torso"},
		],
	},
	&"creature_levian_fire": {
		"rgba_sha256": "f272de7bb508ea8c7c7ca30e447c806caff804fd2ac5d6d754c88d3408b01ae5",
		"components": [
			{"seed": Vector2i(102, 149), "pixels": 1642, "reason": "gap below wing"},
			{"seed": Vector2i(86, 199), "pixels": 79, "reason": "gap inside coiled tail"},
		],
	},
	&"creature_levian_gale": {
		"rgba_sha256": "e6f313754b424cb55b4000c00beb3b94f04adbee470e3d9bb07b6fa5e1adaac2",
		"components": [
			{"seed": Vector2i(104, 144), "pixels": 1217, "reason": "gap below wing"},
			{"seed": Vector2i(64, 138), "pixels": 67, "reason": "tip of gap below wing"},
			{"seed": Vector2i(85, 160), "pixels": 36, "reason": "gap inside coiled tail"},
			{"seed": Vector2i(113, 165), "pixels": 23, "reason": "gap inside coiled tail"},
		],
	},
	&"creature_levian_shadow": {
		"rgba_sha256": "561c7aca14c0d53b5489e2f6fbef0f5e6d68836c887b6283c69f48fc48d9b088",
		"components": [
			{"seed": Vector2i(109, 164), "pixels": 39, "reason": "gap inside coiled tail"},
		],
	},
	&"creature_levian_tide": {
		"rgba_sha256": "0a126cc488beed82346fe7f4c095688bff5ce21ce11839875b77764959f20ccc",
		"components": [
			{"seed": Vector2i(90, 199), "pixels": 104, "reason": "gap inside coiled tail"},
		],
	},
	&"creature_likorez_shadow": {
		"rgba_sha256": "569b4c5e065402858156bad25b8df59a42cd9ed4b31c7a9f666c96cd7791e855",
		"components": [
			{"seed": Vector2i(165, 115), "pixels": 149, "reason": "gap between arm and torso"},
		],
	},
	&"creature_rogozhuk_fire": {
		"rgba_sha256": "1a89afa42b571fdef3b0406237231ef84215495bdcefa50dde186fd0f1c360c6",
		"components": [
			{"seed": Vector2i(44, 144), "pixels": 395, "reason": "gap enclosed by flame, leg and shell"},
		],
	},
	&"creature_rogozhuk_shadow": {
		"rgba_sha256": "7030438920f894532751a62120480b13bb7fe8030ae1b2f39c3e2e34c1994251",
		"components": [
			{"seed": Vector2i(41, 151), "pixels": 709, "reason": "gap inside hooked leg"},
		],
	},
	&"creature_rogozhuk_stone": {
		"rgba_sha256": "46c57b57bb7374e88c7a8a939f721be30efdacf9e54bfee5d3e3b703d2ebe2f3",
		"components": [
			{"seed": Vector2i(40, 152), "pixels": 704, "reason": "gap inside hooked leg"},
		],
	},
	&"creature_rogozhuk_tide": {
		"rgba_sha256": "d21346817ae3210b22dd17b5790a705e296e04c7fb5b496cd58c1bcbe2af301f",
		"components": [
			{"seed": Vector2i(39, 151), "pixels": 748, "reason": "gap inside hooked leg"},
		],
	},
}
