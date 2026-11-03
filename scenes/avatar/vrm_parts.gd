class_name VrmParts
extends RefCounted
## Prepared offline; meshes are shared, materials use the pinned original textures.
const SOURCES: Array[PackedScene] = [
	preload("res://assets/avatars/vrm/Sakurada_Fumiriya.vrm"),
	preload("res://assets/avatars/vrm/Vita.vrm"),
	preload("res://assets/avatars/vrm/HairSample_Male.vrm"),
	preload("res://assets/avatars/vrm/HairSample_Female.vrm"),
	preload("res://assets/avatars/vrm/Vivi.vrm"),
	preload("res://assets/avatars/itch/Kai.vrm"),
]
const HAIR := [
	[preload("res://assets/avatars/vrm/parts/hair_0_0.res"),preload("res://assets/avatars/vrm/parts/hair_0_1.res"),preload("res://assets/avatars/vrm/parts/hair_0_2.res"),preload("res://assets/avatars/vrm/parts/hair_0_3.res"),preload("res://assets/avatars/vrm/parts/hair_0_4.res"),preload("res://assets/avatars/vrm/parts/hair_0_5.res"),preload("res://assets/avatars/vrm/parts/hair_0_6.res"),preload("res://assets/avatars/itch/parts/hair_0.res"),preload("res://assets/avatars/itch/parts/hair_0_bob.res"),preload("res://assets/avatars/street/ponytail_0.res"),preload("res://assets/avatars/sport/swept_hair_0.res")],
	[preload("res://assets/avatars/vrm/parts/hair_1_0.res"),preload("res://assets/avatars/vrm/parts/hair_1_1.res"),preload("res://assets/avatars/vrm/parts/hair_1_2.res"),preload("res://assets/avatars/vrm/parts/hair_1_3.res"),preload("res://assets/avatars/vrm/parts/hair_1_4.res"),preload("res://assets/avatars/vrm/parts/hair_1_5.res"),preload("res://assets/avatars/vrm/parts/hair_1_6.res"),preload("res://assets/avatars/itch/parts/hair_1.res"),preload("res://assets/avatars/itch/parts/hair_1_bob.res"),preload("res://assets/avatars/street/ponytail_1.res"),preload("res://assets/avatars/sport/swept_hair_1.res")],
]
const BODY := [
	[preload("res://assets/avatars/vrm/parts/body_0_0.res"),preload("res://assets/avatars/vrm/parts/body_0_1.res"),preload("res://assets/avatars/vrm/parts/body_0_2.res"),preload("res://assets/avatars/vrm/parts/body_0_3.res"),preload("res://assets/avatars/itch/parts/body_0.res"),preload("res://assets/avatars/street/bomber_0.res"),preload("res://assets/avatars/sport/tracksuit_0.res")],
	[preload("res://assets/avatars/vrm/parts/body_1_0.res"),preload("res://assets/avatars/vrm/parts/body_1_1.res"),preload("res://assets/avatars/vrm/parts/body_1_2.res"),preload("res://assets/avatars/vrm/parts/body_1_3.res"),preload("res://assets/avatars/vrm/parts/body_1_4.res"),preload("res://assets/avatars/itch/parts/body_1.res"),preload("res://assets/avatars/street/bomber_1.res"),preload("res://assets/avatars/sport/tracksuit_1.res")],
]
const CASES := [preload("res://assets/avatars/street/case_0.res"),preload("res://assets/avatars/street/case_1.res")]

const BOMBER_IDS := [5,6]
const SPORT_IDS := [6,7]
const HAIR_STYLE_COUNT := 11

static func supports_denim(model: int, outfit: int) -> bool:
	return outfit != SPORT_IDS[model] and not (model == 1 and outfit < 3)

static func supports_case(model: int, outfit: int) -> bool:
	return outfit == BOMBER_IDS[model]

static var materials: Dictionary = {}
const SKINS := [preload("res://assets/avatars/vrm/parts/skin_0.res"),preload("res://assets/avatars/vrm/parts/skin_1.res")]

static func material_for(part: Mesh,surface: int) -> ShaderMaterial:
	var overrides: Dictionary = part.get_meta("variant_materials",{})
	if overrides.has(surface): return overrides[surface]
	if materials.is_empty():
		for index in SOURCES.size():
			var actor := SOURCES[index].instantiate()
			var lookup: Dictionary = {}
			for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
				for slot in mesh.mesh.get_surface_count():
					var material := mesh.mesh.surface_get_material(slot)
					lookup[material.resource_name] = material
			materials[index] = lookup
			actor.free()
	var names: PackedStringArray = part.get_meta("surface_materials")
	var sources_by_surface: Dictionary = part.get_meta("surface_sources",{})
	return materials[int(sources_by_surface.get(surface,part.get_meta("part_source")))][names[surface]] as ShaderMaterial

