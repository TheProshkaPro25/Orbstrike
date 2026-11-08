extends RefCounted
## Sparse, Astra-authored right-wing weights. Source meshes and GLBs stay immutable.
const PATH := "res://assets/animations/grifalon/gale-wing-skin.res"
const SOURCE := "res://assets/creatures_hd/grifalon_gale.glb"
const SOURCE_SHA := "0329fff5f70f53e6c14fbfaaf293c93860ff86cf5be79ef0f1e85f1c7d02bd79"
const CHAIN := ["wing.R", "wingtip.R", "wingfan.R"]
static var overlay: Resource
static var meshes: Dictionary = {}
static var load_count := 0
static var last_error := ""

static func digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()

static func payload_digest(candidate: Resource) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(String(candidate.get_meta("source_glb_sha256")).to_utf8_buffer())
	hashing.update("|".join(candidate.get_meta("bind_bone_names")).to_utf8_buffer())
	for surface in candidate.get_meta("surfaces"):
		for field in ["surface", "vertex_count", "stride", "positions_sha256", "source_bones_sha256", "source_weights_sha256", "indices_sha256"]: hashing.update(str(surface.get(field, "")).to_utf8_buffer())
		for field in ["vertex_ids", "bone_indices", "weights"]: hashing.update(surface[field].to_byte_array())
	return hashing.finish().hex_encode()

static func preload_required() -> bool:
	if overlay != null: return true
	var candidate := load(PATH) as Resource
	last_error = resource_error(candidate)
	if last_error.is_empty():
		for metric in ["visual_top_source", "visual_extent_source"]:
			var value := float(candidate.get_meta(metric, -1.0))
			if not is_finite(value) or value <= 0.0: last_error = "missing visual envelope " + metric
	if not last_error.is_empty():
		push_error("Grifalon Gale skin overlay: " + last_error)
		return false
	# Raw GLBs may be remapped away in exported PCKs; exact imported-surface
	# fingerprints and bind-name identity remain mandatory in either case.
	if FileAccess.file_exists(SOURCE) and FileAccess.get_sha256(SOURCE) != SOURCE_SHA:
		last_error = "source GLB changed"
		push_error("Grifalon Gale skin overlay: " + last_error)
		return false
	overlay = candidate
	load_count += 1
	return true

static func resource_error(candidate: Resource) -> String:
	if candidate == null: return "missing required resource"
	if int(candidate.get_meta("overlay_schema", 0)) != 1 or String(candidate.get_meta("creature_id", "")) != "creature_grifalon_gale": return "wrong schema/target"
	if String(candidate.get_meta("source_glb_sha256", "")) != SOURCE_SHA: return "wrong source fingerprint"
	var names: Variant = candidate.get_meta("bind_bone_names", PackedStringArray())
	if not names is PackedStringArray or names.size() != 21: return "invalid bind-name table"
	var seen: Dictionary = {}
	for name in names:
		if seen.has(name): return "duplicate bind name"
		seen[name] = true
	for name in CHAIN:
		if not seen.has(name): return "missing right-wing bind"
	var surfaces: Variant = candidate.get_meta("surfaces", [])
	if not surfaces is Array or surfaces.size() != 1: return "expected one sparse source surface"
	var surface: Dictionary = surfaces[0]
	if int(surface.get("surface", -1)) != 0 or int(surface.get("stride", 0)) != 8 or int(surface.get("vertex_count", 0)) != 97837: return "wrong imported vertex layout"
	var ids: Variant = surface.get("vertex_ids")
	var bones: Variant = surface.get("bone_indices")
	var weights: Variant = surface.get("weights")
	if not ids is PackedInt32Array or not bones is PackedInt32Array or not weights is PackedFloat32Array: return "invalid packed sparse arrays"
	if ids.is_empty() or bones.size() != ids.size() * 8 or weights.size() != ids.size() * 8: return "incomplete sparse rows"
	var previous := -1
	for index in ids.size():
		var vertex := int(ids[index])
		if vertex <= previous or vertex >= 97837: return "vertex ids must be unique, sorted and in range"
		previous = vertex
		var total := 0.0
		for influence in 8:
			var slot: int = bones[index * 8 + influence]
			var weight: float = weights[index * 8 + influence]
			if slot < 0 or slot >= names.size() or not is_finite(weight) or weight < 0.0 or weight > 1.0: return "invalid weight/bind index"
			total += weight
		if absf(total - 1.0) > .0003: return "weights are not normalized"
	return ""

static func apply(model: Node3D, candidate: Resource = null) -> bool:
	if candidate == null:
		if not preload_required(): return false
		candidate = overlay
	last_error = resource_error(candidate)
	if not last_error.is_empty(): return false
	var found := 0
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if not node is MeshInstance3D or node.skin == null: continue
		var instance := node as MeshInstance3D
		var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
		if skeleton == null or not instance.mesh is ArrayMesh:
			last_error = "unsupported source mesh/skeleton"
			return false
		var names := PackedStringArray()
		for slot in instance.skin.get_bind_count():
			var bone := instance.skin.get_bind_bone(slot)
			names.append(skeleton.get_bone_name(bone) if bone >= 0 else instance.skin.get_bind_name(slot))
		var source := instance.mesh as ArrayMesh
		var key := str([source.get_instance_id(), payload_digest(candidate), names])
		if not meshes.has(key):
			var replacement := _clone(source, candidate, names)
			if replacement == null: return false
			meshes[key] = {"source": source, "overlay": candidate, "mesh": replacement}
		instance.mesh = meshes[key].mesh
		found += 1
	if found != 1:
		last_error = "expected exactly one source skinned mesh"
		return false
	model.set_meta("grifalon_gale_skin_overlay", 1)
	return true

static func _other_weights(bones: PackedInt32Array, weights: PackedFloat32Array, start: int, names: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for influence in 8:
		var slot := bones[start + influence]
		if weights[start + influence] > 0.0 and not CHAIN.has(names[slot]): result[names[slot]] = result.get(names[slot], 0.0) + weights[start + influence]
	return result

static func _clone(source: ArrayMesh, candidate: Resource, actual_names: PackedStringArray) -> ArrayMesh:
	if source.get_surface_count() != 1 or source.get_blend_shape_count() != 0:
		last_error = "unsupported surface/blend-shape layout"
		return null
	var patch: Dictionary = candidate.get_meta("surfaces")[0]
	var arrays := source.surface_get_arrays(0)
	for item in [[Mesh.ARRAY_VERTEX, "positions_sha256"], [Mesh.ARRAY_BONES, "source_bones_sha256"], [Mesh.ARRAY_WEIGHTS, "source_weights_sha256"], [Mesh.ARRAY_INDEX, "indices_sha256"]]:
		if digest(arrays[item[0]].to_byte_array()) != String(patch.get(item[1], "")):
			last_error = "source surface fingerprint mismatch: " + item[1]
			return null
	var declared_names: PackedStringArray = candidate.get_meta("bind_bone_names")
	var remap := PackedInt32Array()
	for name in declared_names:
		var slot := actual_names.find(name)
		if slot < 0:
			last_error = "target skin has no bind: " + name
			return null
		remap.append(slot)
	var old_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var old_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var bones := old_bones.duplicate()
	var weights := old_weights.duplicate()
	var ids: PackedInt32Array = patch.vertex_ids
	for index in ids.size():
		var start := ids[index] * 8
		for influence in 8:
			bones[start + influence] = remap[patch.bone_indices[index * 8 + influence]]
			weights[start + influence] = patch.weights[index * 8 + influence]
		var old_total := 0.0
		var new_total := 0.0
		for influence in 8:
			old_total += old_weights[start + influence]
			new_total += weights[start + influence]
		if absf(old_total - new_total) > .0000003:
			last_error = "overlay changed total influence mass"
			return null
		if _other_weights(old_bones, old_weights, start, actual_names) != _other_weights(bones, weights, start, actual_names):
			last_error = "overlay changed a non-right-wing influence"
			return null
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	# Let Godot encode skin data and recalculate bone AABBs from Astra's values.
	# Re-encoding the whole imported surface changes compressed normals, so use
	# only these two generated fields in the native ArrayMesh storage structure.
	var encoded := ArrayMesh.new()
	encoded.add_surface_from_arrays(source.surface_get_primitive_type(0), arrays, [], {}, source.surface_get_format(0))
	if encoded.get_surface_count() != 1:
		last_error = "skin encoding failed"
		return null
	var stored: Array = source.get("_surfaces").duplicate(true)
	var generated: Array = encoded.get("_surfaces")
	if stored.size() != 1 or generated.size() != 1 or not stored[0].has("skin_data") or not generated[0].has("bone_aabbs"):
		last_error = "unsupported native ArrayMesh storage layout"
		return null
	stored[0].skin_data = generated[0].skin_data
	stored[0].bone_aabbs = generated[0].bone_aabbs
	var result := ArrayMesh.new()
	result.resource_name = source.resource_name
	result.custom_aabb = source.custom_aabb
	result.lightmap_size_hint = source.lightmap_size_hint
	result.blend_shape_mode = source.blend_shape_mode
	# The imported optimized shadow mesh has old skin weights. A null shadow_mesh
	# makes the renderer use this updated full mesh for shadows as well.
	result.shadow_mesh = null
	# This is the same property used by native ResourceLoader/ResourceSaver;
	# it initializes ArrayMesh CPU metadata and its renderer surface together.
	result.set("_surfaces", stored)
	if result.get_surface_count() != 1:
		last_error = "native ArrayMesh reconstruction failed"
		return null
	var after := result.surface_get_arrays(0)
	for channel in Mesh.ARRAY_MAX:
		if channel in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS] or arrays[channel] == null: continue
		if after[channel] != arrays[channel]:
			last_error = "mesh rebuild changed a non-skin array: " + str(channel)
			return null
	return result

static func clear() -> void:
	meshes.clear()
	overlay = null
	load_count = 0
	last_error = ""
