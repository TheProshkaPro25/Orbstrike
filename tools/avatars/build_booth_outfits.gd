extends "res://tools/avatars/build_street_set.gd"
## Offline build from authored BOOTH geometry and maps. Runtime uses the existing prepared Skin.
const WORK := "res://build/wardrobe-nov12/"
const BOOTH := "res://assets/avatars/booth/"
const CUTOUT := preload("res://addons/Godot-MToon-Shader/mtoon_cutout_cull_off.gdshader")
const CUTOUT_OUTLINE := preload("res://addons/Godot-MToon-Shader/mtoon_outline_cutout.gdshader")

func run() -> void:
	var targets := []
	for model in 2:
		var actor := (load("res://assets/avatars/vrm/"+PATHS[model]+".vrm") as PackedScene).instantiate()
		root.add_child(actor)
		var rig := actor.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var skin := load(OUTPUT+"skin_%d.res" % model) as Skin
		var bones := {}
		for b in rig.get_bone_count():
			var rest := (rig.global_transform*rig.get_bone_global_rest(b)).origin
			var pose := skin.get_bind_pose(b).affine_inverse().origin
			bones[rig.get_bone_name(b)] = [b,[rest.x,rest.y,rest.z],[pose.x,pose.y,pose.z]]
		targets.append({"bones":bones})
		actor.free()
	if "--targets" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(WORK)
		var json := FileAccess.open(WORK+"targets.json", FileAccess.WRITE)
		json.store_string(JSON.stringify(targets, "  "))
		quit()
		return
	DirAccess.make_dir_recursive_absolute(BOOTH)
	for model in 2:
		if model == 0 and "--only-operator" in OS.get_cmdline_user_args(): continue
		var name: String = ["haori", "operator"][model]
		var part := build_outfit(model, name, targets[model].bones)
		var file := BOOTH+"%s_%d.res" % [name, model]
		assert(ResourceSaver.save(part, file, ResourceSaver.FLAG_COMPRESS) == OK)
		print(file, ": ", part.get_surface_count(), " surfaces ", part.get_aabb())
	quit()

func build_outfit(model: int, name: String, bones: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var names := PackedStringArray()
	var overrides := {}
	var base := load(OUTPUT+"body_%d_0.res" % model) as ArrayMesh
	var skin_surface := base.surface_get_arrays(0)
	var skin_tool := skinned_tool()
	var lining_tool := skinned_tool()
	var neck := pos(bones, "Neck")
	var left := pos(bones, "LeftHand")
	var right := pos(bones, "RightHand")
	var left_axis := (left-pos(bones, "LeftLowerArm")).normalized()
	var right_axis := (right-pos(bones, "RightLowerArm")).normalized()
	var neck_start := neck.y-(.072 if model == 0 else .061)
	for polygon in skin_polygons(skin_surface):
		# The target's own texture, UVs and fingers stay in place. Remove hidden skin
		# at wrists/neck/legs instead of flattening the incoming authored cloth.
		var neckline: Callable = func(v: Vector3) -> float:
			return v.y-neck_start-absf(v.x)*1.27
		emit_polygon(skin_tool, cut(polygon, neckline), 0., true)
		for pair in [[left, left_axis, 1.], [right, right_axis, -1.]]:
			var wrist: Vector3 = pair[0]
			var axis: Vector3 = pair[1]
			var sign_x: float = pair[2]
			var hand: Callable = func(v: Vector3) -> float:
				return minf((v-wrist).dot(axis)+.053, sign_x*v.x-.26)
			emit_polygon(skin_tool, cut(polygon, hand), 0., true)
		if model == 0:
			var ankle: Callable = func(v: Vector3) -> float: return .166-v.y
			emit_polygon(skin_tool, cut(polygon, ankle), 0., true)
		else:
			# The open coat has no undershirt in the source. Use fitted Vita torso
			# as the plain inner layer, and existing trousers/shoes beneath it.
			var lining: Callable = func(v: Vector3) -> float:
				return minf(minf(-neckline.call(v), v.y-1.035), .125-absf(v.x))
			var panel := cut(polygon, lining)
			for i in panel.size():
				var vertex: Dictionary = panel[i].duplicate()
				panel[i] = vertex
				var p: Vector3 = vertex.p
				var seam := clampf(-neckline.call(p)*24., 0., 1.)
				p.x *= 1.-.065*seam
				p.z *= 1.-.13*seam
				vertex.p = p
			emit_polygon(lining_tool, panel, 0., false)
	skin_tool.generate_tangents()
	skin_tool.index()
	skin_tool.commit(mesh)
	names.append(base.get_meta("surface_materials")[0])
	if model == 1:
		lining_tool.index()
		lining_tool.commit(mesh)
		var lining_material := make_cloth("Operator_Inner", null, Color("343943"), .5)
		lining_material.set_shader_parameter("_Color", Color("242933"))
		overrides[mesh.get_surface_count()-1] = lining_material
		names.append(lining_material.resource_name)
		var pants := load(OUTPUT+"body_1_3.res") as ArrayMesh
		var material := part_material(pants, 2).duplicate(false) as ShaderMaterial
		material.resource_name = "Operator_Under_Trousers"
		material.set_shader_parameter("_Color", Color("2d3138"))
		material.set_shader_parameter("_ShadeColor", Color("777b86"))
		# Original next pass still uses the trousers' authored blue. Keep this
		# underlayer neutral so it does not compete with the source coat.
		material.next_pass = null
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pants.surface_get_arrays(2))
		overrides[mesh.get_surface_count()-1] = material
		names.append(material.resource_name)
	var shoe := 4 if model == 0 else 2
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base.surface_get_arrays(shoe))
	names.append(base.get_meta("surface_materials")[shoe])
	var file := FileAccess.open(WORK+"input/"+name+".meshdata", FileAccess.READ)
	assert(file != null)
	var metadata: Variant = null
	if model == 0:
		metadata = JSON.parse_string(FileAccess.get_file_as_string(WORK+"input/haori.json"))
	var count := file.get_32()
	for surface in count:
		var arrays := read_surface(file, bones.size())
		if model == 1: fit_coat_tails(arrays, bones)
		var id := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat: ShaderMaterial
		if model == 0:
			var data: Dictionary = metadata[surface]
			var tint: Array = data.shade
			var material_name: String = ["Kimono_Robe_CLOTH", "Kimono_Obi", "Kimono_Obi_Trim", "Kimono_Haori_CLOTH", "Kimono_Haneri"][surface]
			mat = make_cloth(material_name, texture(data.texture), Color(tint[0], tint[1], tint[2], tint[3]), data.cutoff)
			var outline := mat.duplicate(false) as ShaderMaterial
			outline.shader = CUTOUT_OUTLINE
			outline.set_shader_parameter("_OutlineWidth", .05)
			outline.set_shader_parameter("_OutlineColor", Color("25242b"))
			mat.next_pass = outline
		else:
			mat = make_cloth("Silver_Operator_CLOTH", texture("operator_AlbedoTransparency.png"), Color("cad3e0"), .5)
			mat.set_shader_parameter("_BumpMap", texture("operator_NormalGL.png", true))
			mat.set_shader_parameter("_BumpScale", .8)
			mat.set_shader_parameter("_ShadingGradeTexture", texture("operator_AmbientOcclusion.png"))
			mat.set_shader_parameter("_ShadingGradeRate", .62)
		names.append(mat.resource_name)
		overrides[id] = mat
	assert(file.get_position() == file.get_length())
	mesh.set_meta("part_source", model)
	mesh.set_meta("surface_materials", names)
	mesh.set_meta("variant_materials", overrides)
	return mesh

func fit_coat_tails(arrays: Array, target_bones: Dictionary) -> void:
	# Let each panel follow its thigh through the throw while the waist stays
	# anchored to the pelvis. The blend at the center keeps the lining continuous.
	var hips: int = target_bones["Hips"][0]
	var left_thigh: int = target_bones["LeftUpperLeg"][0]
	var right_thigh: int = target_bones["RightUpperLeg"][0]
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	for vertex in points.size():
		var point := points[vertex]
		var to_thighs := .63 * (1.0 - smoothstep(.78, 1.01, point.y))
		if to_thighs <= 0.0: continue
		var influences := {}
		var start := vertex * 4
		for index in range(start, start + 4):
			var weight := weights[index]
			if weight <= 0.0: continue
			var joint := joints[index]
			influences[joint] = influences.get(joint, 0.0) + weight
		var hip_weight: float = influences.get(hips, 0.0)
		if hip_weight <= 0.0: continue
		var shared := hip_weight * to_thighs
		var left := smoothstep(-.075, .075, point.x)
		influences[hips] = hip_weight - shared
		influences[left_thigh] = influences.get(left_thigh, 0.0) + shared * left
		influences[right_thigh] = influences.get(right_thigh, 0.0) + shared * (1.0 - left)
		var sorted := influences.keys()
		sorted.sort_custom(func(a: int, b: int) -> bool: return influences[a] > influences[b])
		var count := mini(4, sorted.size())
		var total := 0.0
		for slot in count: total += influences[sorted[slot]]
		for slot in 4:
			joints[start + slot] = sorted[slot] if slot < count else 0
			weights[start + slot] = influences[sorted[slot]] / total if slot < count else 0.0
	arrays[Mesh.ARRAY_BONES] = joints
	arrays[Mesh.ARRAY_WEIGHTS] = weights

func pos(bones: Dictionary, name: String) -> Vector3:
	var p: Array = bones[name][2]
	return Vector3(p[0], p[1], p[2])

func skinned_tool() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool

func cut(polygon: Array, distance: Callable) -> Array:
	var result := []
	if polygon.is_empty(): return result
	var previous: Dictionary = polygon[-1]
	var a: float = distance.call(previous.p)
	for current: Dictionary in polygon:
		var b: float = distance.call(current.p)
		if (a >= 0.) != (b >= 0.):
			var t := a/(a-b)
			var mix := {}
			for pair in [[previous, 1.-t], [current, t]]:
				for k in pair[0].b.size():
					var bone: int = pair[0].b[k]
					mix[bone] = mix.get(bone, 0.)+pair[0].w[k]*pair[1]
			var order := mix.keys()
			order.sort_custom(func(x: int,y: int) -> bool: return mix[x] > mix[y])
			var indices := PackedInt32Array([0,0,0,0])
			var weights := PackedFloat32Array([0,0,0,0])
			var total := 0.
			for k in mini(4, order.size()):
				indices[k] = order[k]
				weights[k] = mix[order[k]]
				total += weights[k]
			for k in 4: weights[k] /= maxf(total, .00001)
			result.append({"p":previous.p.lerp(current.p,t), "n":previous.n.lerp(current.n,t).normalized(),
				"uv":previous.uv.lerp(current.uv,t), "b":indices, "w":weights})
		if b >= 0.: result.append(current)
		previous = current
		a = b
	return result

func read_surface(file: FileAccess, bone_count: int) -> Array:
	var length := file.get_32()
	var index_count := file.get_32()
	var vertices := read_vector3(file, length)
	var normals := read_vector3(file, length)
	var uv_raw := file.get_buffer(length*8).to_float32_array()
	var uvs := PackedVector2Array()
	uvs.resize(length)
	for i in length: uvs[i] = Vector2(uv_raw[i*2], uv_raw[i*2+1])
	var weights := file.get_buffer(length*16).to_float32_array()
	var joints := file.get_buffer(length*16).to_int32_array()
	var indices := file.get_buffer(index_count*4).to_int32_array()
	for i in length:
		var weight_sum := 0.
		for k in 4:
			assert(joints[i*4+k] >= 0 and joints[i*4+k] < bone_count)
			weight_sum += weights[i*4+k]
		assert(is_equal_approx(weight_sum, 1.))
	var tool := skinned_tool()
	for i in length:
		tool.set_bones(joints.slice(i*4, i*4+4))
		tool.set_weights(weights.slice(i*4, i*4+4))
		tool.set_uv(uvs[i])
		tool.set_normal(normals[i])
		tool.add_vertex(vertices[i])
	for index in indices: tool.add_index(index)
	tool.generate_tangents()
	return tool.commit_to_arrays()

func read_vector3(file: FileAccess, length: int) -> PackedVector3Array:
	var raw := file.get_buffer(length*12).to_float32_array()
	var result := PackedVector3Array()
	result.resize(length)
	for i in length: result[i] = Vector3(raw[i*3], raw[i*3+1], raw[i*3+2])
	return result

func texture(name: String, normal := false) -> Texture2D:
	var image := Image.load_from_file(WORK+"input/"+name)
	assert(image != null and not image.is_empty())
	image.generate_mipmaps(normal)
	# GPU block compression saves memory without a runtime import step.
	if name.begins_with("operator_"):
		var source := Image.COMPRESS_SOURCE_NORMAL if normal else Image.COMPRESS_SOURCE_GENERIC
		assert(image.compress(Image.COMPRESS_BPTC, source) == OK)
	return ImageTexture.create_from_image(image)

func make_cloth(name: String, map: Texture2D, shade: Color, alpha: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.resource_name = name
	mat.shader = CUTOUT
	mat.set_shader_parameter("_MainTex", map)
	mat.set_shader_parameter("_ShadeTexture", map)
	mat.set_shader_parameter("_Color", Color.WHITE)
	mat.set_shader_parameter("_ShadeColor", shade)
	mat.set_shader_parameter("_AlphaCutoutEnable", 1.)
	mat.set_shader_parameter("_Cutoff", alpha)
	mat.set_shader_parameter("_BumpScale", 0.)
	return mat
