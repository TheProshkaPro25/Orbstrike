extends SceneTree
## Offline mask for the skinned skin beneath closed sleeves of older outfits.
const PARTS := "res://assets/avatars/vrm/parts/"
const ITCH := "res://assets/avatars/itch/parts/"
const OUTFITS := [
	[PARTS + "body_0_1.res", PARTS + "body_0_2.res", PARTS + "body_0_3.res", ITCH + "body_0.res"],
	[PARTS + "body_1_3.res", PARTS + "body_1_4.res", ITCH + "body_1.res"],
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for model in OUTFITS.size():
		var actor := VrmAvatar.MODELS[model].instantiate()
		var skeleton := actor.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var joints := [skeleton.find_bone("LeftUpperArm"), skeleton.find_bone("RightUpperArm")]
		actor.free()
		for path: String in OUTFITS[model]:
			var source := load(path) as ArrayMesh
			assert(source.get_blend_shape_count() == 0)
			var mesh := ArrayMesh.new()
			var removed := 0
			for slot in source.get_surface_count():
				var arrays := source.surface_get_arrays(slot)
				if "_SKIN" in VrmParts.material_for(source, slot).resource_name:
					removed += mask_upper_arms(arrays, joints)
				var flags := source.surface_get_format(slot) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
				mesh.surface_set_material(slot, source.surface_get_material(slot))
			for key in source.get_meta_list(): mesh.set_meta(key, source.get_meta(key))
			if removed > 0: assert(ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS) == OK)
			print(path, ": ", removed, " covered skin triangles")
	VrmParts.materials.clear()
	quit()

func mask_upper_arms(arrays: Array, joints: Array) -> int:
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride := weights.size()/points.size()
	var arm_weights := PackedFloat32Array()
	arm_weights.resize(points.size())
	for vertex in points.size():
		for offset in stride:
			var index := vertex*stride + offset
			if bones[index] in joints: arm_weights[vertex] += weights[index]
	var kept := PackedInt32Array()
	for at in range(0, indices.size(), 3):
		var a := indices[at]
		var b := indices[at+1]
		var c := indices[at+2]
		if (arm_weights[a]+arm_weights[b]+arm_weights[c])/3.0 > .36: continue
		kept.append(a)
		kept.append(b)
		kept.append(c)
	arrays[Mesh.ARRAY_INDEX] = kept
	return (indices.size()-kept.size())/3
