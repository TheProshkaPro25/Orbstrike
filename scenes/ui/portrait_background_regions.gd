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
