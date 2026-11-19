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
const HAIR_STYLE_COUNT := HairCatalog.SLOT_COUNT
const VITA_FACE_VARIANTS_PATH := "res://assets/avatars/vrm/parts/vita_face_variants.res"
const VIVI_FACE_SKIN_PATH := "res://assets/avatars/vrm/parts/vivi_face_skin.png"
const VITA_FACE_VIVI_BLEND := &"OrbstrikeFaceVivi"
const VITA_FACE_VIVI_BLINK := &"OrbstrikeFaceViviBlink"
const VIVI_SOURCE := 4
static var _vita_face_variants: ArrayMesh
static var _vita_face_variants_checked := false

static func vita_face_variants(original: ArrayMesh) -> ArrayMesh:
	if _vita_face_variants_checked: return _vita_face_variants
	_vita_face_variants_checked = true
	if not ResourceLoader.exists(VITA_FACE_VARIANTS_PATH, "ArrayMesh"): return null
	var prepared := load(VITA_FACE_VARIANTS_PATH) as ArrayMesh
	if prepared == null: return null
	var shape_count := original.get_blend_shape_count()
	if prepared.get_blend_shape_count() != shape_count + 2: return null
	if prepared.get_blend_shape_name(shape_count) != VITA_FACE_VIVI_BLEND or prepared.get_blend_shape_name(shape_count + 1) != VITA_FACE_VIVI_BLINK:
		return null
	if prepared.get_blend_shape_mode() != original.get_blend_shape_mode() or prepared.get_surface_count() != original.get_surface_count():
		return null
	for index in shape_count:
		if prepared.get_blend_shape_name(index) != original.get_blend_shape_name(index): return null
	for surface in original.get_surface_count():
		if prepared.surface_get_primitive_type(surface) != original.surface_get_primitive_type(surface):
			return null
		if prepared.surface_get_array_len(surface) != original.surface_get_array_len(surface):
			return null
		if prepared.surface_get_array_index_len(surface) != original.surface_get_array_index_len(surface):
			return null
	_vita_face_variants = prepared
	return _vita_face_variants

static func supports_denim(model: int, outfit: int) -> bool:
	return not WardrobeCatalog.is_addition(model, outfit) and outfit != SPORT_IDS[model] and not (model == 1 and outfit < 3)

static func supports_case(model: int, outfit: int) -> bool:
	return outfit == BOMBER_IDS[model]

static var materials: Dictionary = {}
const SKINS := [preload("res://assets/avatars/vrm/parts/skin_0.res"),preload("res://assets/avatars/vrm/parts/skin_1.res")]

static func hair_mesh(model: int, source: int) -> ArrayMesh:
	if source < HairCatalog.LEGACY_COUNT: return HAIR[model][source]
	# GameLoading holds the prepared meshes, so this uses the resource cache.
	return load(HairCatalog.asset_path(model, source)) as ArrayMesh

static func outfit_mesh(model: int, id: int) -> ArrayMesh:
	if not WardrobeCatalog.is_addition(model, id): return BODY[model][id]
	# GameLoading holds the prepared meshes, so this uses the resource cache.
	return load(WardrobeCatalog.asset_path(model, id)) as ArrayMesh

static func material_for(part: Mesh,surface: int) -> ShaderMaterial:
	var overrides: Dictionary = part.get_meta("variant_materials",{})
	if overrides.has(surface): return overrides[surface]
	var names: PackedStringArray = part.get_meta("surface_materials")
	var sources_by_surface: Dictionary = part.get_meta("surface_sources",{})
	return source_material(int(sources_by_surface.get(surface,part.get_meta("part_source"))), names[surface])

static func source_material(source: int, name: String) -> ShaderMaterial:
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
	return materials[source].get(name) as ShaderMaterial

