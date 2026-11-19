extends SceneTree
## Run after preparing the outfits. The donor body and native head share VRoid scalp UVs.
## godot --headless --max-fps 60 --path . -s res://tools/avatars/fit_costume_scalps.gd

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var parts := load("res://scenes/avatar/vrm_parts.gd")
	for model in 2:
		var actor := VrmAvatar.MODELS[model].instantiate()
		var rig := actor.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var head_y: float = parts.SKINS[model].get_bind_pose(rig.find_bone("Head")).affine_inverse().origin.y
		actor.free()
		var native: ArrayMesh = parts.outfit_mesh(model, 0)
		var reference := native.surface_get_arrays(0)
		var scalp := {}
		for i in reference[Mesh.ARRAY_VERTEX].size():
			# Only the cranium above the nape. Face and ears have their own mesh.
			if reference[Mesh.ARRAY_VERTEX][i].y > head_y + .04:
				scalp[reference[Mesh.ARRAY_TEX_UV][i]] = i
		for outfit in WardrobeCatalog.available_ids(model):
			var mesh: ArrayMesh = parts.outfit_mesh(model, outfit)
			for surface in mesh.get_surface_count():
				if "_SKIN" not in parts.material_for(mesh, surface).resource_name: continue
				var changed := fit_scalp(mesh, surface, scalp, reference, head_y)
				if changed == 0: continue
				print(mesh.resource_path, ": ", changed, " fitted scalp vertices")
				if ResourceSaver.save(mesh, mesh.resource_path, ResourceSaver.FLAG_COMPRESS) != OK:
					quit(1)
					return
	parts.materials.clear()
	quit()

func fit_scalp(mesh: ArrayMesh, slot: int, scalp: Dictionary, reference: Array, head_y: float) -> int:
	var arrays := mesh.surface_get_arrays(slot)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var edited := PackedInt32Array()
	for i in points.size():
		if points[i].y < head_y or not scalp.has(uvs[i]): continue
		var match_index: int = scalp[uvs[i]]
		var target: Vector3 = reference[Mesh.ARRAY_VERTEX][match_index]
		if points[i].distance_to(target) < .00001: continue
		points[i] = target
		normals[i] = reference[Mesh.ARRAY_NORMAL][match_index]
		for axis in 4:
			tangents[4*i + axis] = reference[Mesh.ARRAY_TANGENT][4*match_index + axis]
		edited.append(i)
	if edited.is_empty(): return 0
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	var fitted := ArrayMesh.new()
	fitted.add_surface_from_arrays(mesh.surface_get_primitive_type(slot), arrays, [], {}, mesh.surface_get_format(slot))
	# Preserve the packed geometry of every other surface, as well as the UVs,
	# bone weights and triangle buffers of the fitted skin surface.
	var surfaces: Array = mesh.get("_surfaces")
	var updated: Dictionary = fitted.get("_surfaces")[0]
	# Packing decoded normals again can round their least significant bits.
	# Copy only the two encoded vertex fields of the edited scalp vertices.
	var data: PackedByteArray = surfaces[slot].vertex_data
	var encoded: PackedByteArray = updated.vertex_data
	var format := mesh.surface_get_format(slot)
	var count := points.size()
	var pos_stride := RenderingServer.mesh_surface_get_format_vertex_stride(format, count)
	var basis_stride := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, count)
	var basis_start := RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_NORMAL)
	for i in edited:
		for byte in pos_stride: data[i*pos_stride+byte] = encoded[i*pos_stride+byte]
		for byte in basis_stride:
			var index := basis_start+i*basis_stride+byte
			data[index] = encoded[index]
	surfaces[slot].vertex_data = data
	for key in ["aabb", "bone_aabbs"]:
		surfaces[slot][key] = updated[key]
	mesh.clear_surfaces()
	mesh.set("_surfaces", surfaces)
	return edited.size()
