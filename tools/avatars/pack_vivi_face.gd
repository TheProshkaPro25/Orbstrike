extends SceneTree
## Called by fit_vivi_face.py. Preserve all imported surface and blend buffers.
const OUT := "res://assets/avatars/vrm/parts/vita_face_variants.res"

func _initialize() -> void:
	var actor := (load("res://assets/avatars/vrm/Vita.vrm") as PackedScene).instantiate()
	var source: ArrayMesh = actor.find_children("*Face*", "MeshInstance3D", true, false)[0].mesh
	var candidate := ArrayMesh.new()
	candidate.blend_shape_mode = source.blend_shape_mode
	var surfaces: Array = source.get("_surfaces").duplicate()
	for i in source.get_blend_shape_count():
		candidate.add_blend_shape(source.get_blend_shape_name(i))
	candidate.add_blend_shape("OrbstrikeFaceVivi")
	candidate.add_blend_shape("OrbstrikeFaceViviBlink")
	var reader := FileAccess.open("res://build/vita-faces-nov19/vivi.bin", FileAccess.READ)
	for surface in surfaces.size():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		var blink_vertices := vertices.duplicate()
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL].duplicate()
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT].duplicate()
		var raw := {}
		for i in reader.get_32():
			var pos := read_vector(reader)
			var delta := read_vector(reader)
			var normal := read_vector(reader)
			raw[pos] = [delta, normal, read_vector(reader)]
		for i in vertices.size():
			var pos := vertices[i]
			if not raw.has(pos):
				push_error("Missing raw Vita correspondence on surface %d at %s" % [surface, pos])
				actor.free()
				quit(1)
				return
			var data: Array = raw[pos]
			blink_vertices[i] += Vector3(data[2])
			if data[0] == Vector3.ZERO: continue
			vertices[i] += Vector3(data[0])
			var new_normal: Vector3 = data[1]
			var offset := 4 * i
			var tangent := Vector3(tangents[offset], tangents[offset + 1], tangents[offset + 2])
			tangent = Quaternion(normals[i].normalized(), new_normal.normalized()) * tangent
			normals[i] = new_normal
			for axis in 3: tangents[offset + axis] = tangent[axis]
		var target := []
		target.resize(Mesh.ARRAY_MAX)
		target[Mesh.ARRAY_VERTEX] = vertices
		target[Mesh.ARRAY_NORMAL] = normals
		target[Mesh.ARRAY_TANGENT] = tangents
		var blink := target.duplicate()
		blink[Mesh.ARRAY_VERTEX] = blink_vertices
		blink[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		blink[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
		var encoder := ArrayMesh.new()
		encoder.add_blend_shape("OrbstrikeFaceVivi")
		encoder.add_blend_shape("OrbstrikeFaceViviBlink")
		encoder.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [target, blink])
		var surface_data: Dictionary = surfaces[surface].duplicate()
		var payload: PackedByteArray = encoder.get("_surfaces")[0].blend_shapes
		var original: PackedByteArray = surface_data.blend_shapes.duplicate()
		if payload.size() * source.get_blend_shape_count() != original.size() * 2:
			push_error("Incompatible imported blend shape buffer")
			actor.free()
			quit(1)
			return
		original.append_array(payload)
		surface_data.blend_shapes = original
		surfaces[surface] = surface_data
	candidate.set("_surfaces", surfaces)
	var err := ResourceSaver.save(candidate, OUT, ResourceSaver.FLAG_COMPRESS)
	actor.free()
	quit(err)

func read_vector(reader: FileAccess) -> Vector3:
	return Vector3(reader.get_float(), reader.get_float(), reader.get_float())
