extends SceneTree
## Offline conversion of an exported costume donor into the existing avatar's skin space.
## Input: editor-imported donor VRM path, the costume key, output path or "inspect".
const RECIPES := {
	"oc_uniform": [1, ["Tops", "Bottoms", "Shoes", "InnerTop", "InnerBottom", "ArmAccessory", "NeckAccessory"]],
	"dirndl": [1, ["Tops", "Shoes", "Onepiece"]],
	"fantasy_robe": [0, ["Tops", "Bottoms", "Shoes"]],
	"jacket_pants": [1, ["Tops", "Onepiece", "Shoes"]],
	"dreamy_angel": [1, ["Tops", "Onepiece", "Shoes"]],
	"deer_haori": [0, ["Tops"]],
	"orchid_armor": [0, ["Tops", "Onepiece", "Hair"]],
	"orchid_uniform": [0, ["Tops", "Bottoms", "NeckAccessory"]],
}
const SEGMENT_CHILDREN := {
	"Hips": "Spine", "Spine": "Chest", "Chest": "UpperChest", "UpperChest": "Neck", "Neck": "Head",
	"LeftShoulder": "LeftUpperArm", "RightShoulder": "RightUpperArm",
	"LeftUpperArm": "LeftLowerArm", "RightUpperArm": "RightLowerArm",
	"LeftLowerArm": "LeftHand", "RightLowerArm": "RightHand",
	"LeftUpperLeg": "LeftLowerLeg", "RightUpperLeg": "RightLowerLeg",
	"LeftLowerLeg": "LeftFoot", "RightLowerLeg": "RightFoot",
}
const VISIBLE_SKIN_LIMIT := .025
# Corrections measured from the lower soles in the target fighter's idle pose.
const SOLE_OFFSETS := {"oc_uniform": -.011, "dirndl": .042, "jacket_pants": -.018}
var _local_textures: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or not RECIPES.has(args[1]):
		printerr("FAIL: usage: -- res://editor_imported_donor.vrm recipe /absolute/output.res|inspect")
		quit(2)
		return
	var donor_scene := load(args[0]) as PackedScene
	if donor_scene == null:
		printerr("FAIL: could not load editor-imported donor")
		quit(2)
		return
	var donor := donor_scene.instantiate() as Node3D
	var key := args[1]
	var model: int = RECIPES[key][0]
	var allowed: Array = RECIPES[key][1]
	donor.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(donor)
	var skeleton := donor.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	skeleton.force_update_all_bone_transforms()
	var base := VrmAvatar.MODELS[model].instantiate() as Node3D
	base.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(base)
	var target_skeleton := base.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var target_skin: Skin = VrmParts.SKINS[model]
	var outfit := ArrayMesh.new()
	var names := PackedStringArray()
	var materials := {}
	var garment_roles := {}
	var donor_skin := []
	for instance: MeshInstance3D in donor.find_children("*", "MeshInstance3D", true, false):
		if instance.skin == null: continue
		var fits := get_fits(instance, skeleton, target_skeleton, target_skin)
		for slot in instance.mesh.get_surface_count():
			var shader := instance.mesh.surface_get_material(slot) as ShaderMaterial
			if shader == null: continue
			var role := material_role(instance, shader.resource_name)
			var arrays := instance.mesh.surface_get_arrays(slot)
			print(instance.name, "/", slot, " ", shader.resource_name, " role=", role, " vertices=", arrays[Mesh.ARRAY_VERTEX].size())
			if args[2] == "inspect" or (role not in allowed and role != "Skin"): continue
			# The uniform export contains default black shorts and the authored white trousers.
			if key == "orchid_uniform" and role == "Bottoms" and "_CLOTH_02" not in shader.resource_name: continue
			arrays = fit_surface(arrays, fits)
			if role == "Skin":
				donor_skin.append({"arrays": arrays, "material": shader})
				continue
			if key == "dirndl" and role == "Onepiece": offset_shell(arrays, .008)
			if key == "fantasy_robe" and "_007_03_Tops_" in shader.resource_name:
				offset_robe_waist(arrays)
				close_robe_underarm(arrays)
			if role == "Hair":
				# The Orchid helmet is authored in the donor's hair slot. Its
				# shell stays fixed to the head during gameplay animations.
				var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				joints.fill(target_skeleton.find_bone("Head"))
				arrays[Mesh.ARRAY_BONES] = joints
			garment_roles[role] = true
			var local := shader.duplicate(false) as ShaderMaterial
			local.next_pass = null
			localize_textures(local)
			var cloth := role != "Hair" and role != "NeckAccessory"
			local.resource_name = "Booth_%s_%s_%d%s" % [key, role, names.size(), "_CLOTH" if cloth else ""]
			append_surface(outfit, names, materials, arrays, local)
	if args[2] != "inspect":
		var missing := expected_roles(key).filter(func(role: String) -> bool: return not garment_roles.has(role))
		if not missing.is_empty() or donor_skin.is_empty():
			printerr("FAIL: missing clothing surfaces ", missing, " or body mask")
			quit(1)
			return
		var neck := target_skin.get_bind_pose(target_skeleton.find_bone("Neck")).affine_inverse().origin
		append_target_parts(outfit, names, materials, donor_skin, model, garment_roles, key, neck.y, target_skeleton)
		outfit.set_meta("part_source", model)
		outfit.set_meta("surface_materials", names)
		outfit.set_meta("variant_materials", materials)
		if garment_roles.has("Hair"): outfit.set_meta("covers_hair", true)
		if SOLE_OFFSETS.has(key): outfit.set_meta("sole_offset", SOLE_OFFSETS[key])
		var saved := ResourceSaver.save(outfit, args[2], ResourceSaver.FLAG_COMPRESS)
		print("COSTUME ", key, " model=", model, " roles=", garment_roles.keys(), " surfaces=", names.size(), " save=", error_string(saved))
		if saved != OK: printerr("FAIL: costume save failed")
		base.queue_free()
		donor.queue_free()
		VrmParts.materials.clear()
		await process_frame
		quit(int(saved != OK))
	else:
		base.queue_free()
		donor.queue_free()
		await process_frame
		quit()

func localize_textures(material: ShaderMaterial) -> void:
	for uniform in material.shader.get_shader_uniform_list():
		var param: String = uniform.name
		var value: Variant = material.get_shader_parameter(param)
		if not value is Texture2D: continue
		var original: Texture2D = value
		var id := original.get_instance_id()
		if not _local_textures.has(id):
			var image := original.get_image()
			if image == null or image.is_empty(): continue
			if image.is_compressed(): image.decompress()
			if image.get_width() >= 64 and image.get_height() >= 64:
				if not image.has_mipmaps(): image.generate_mipmaps()
				var source := Image.COMPRESS_SOURCE_NORMAL if param == "_BumpMap" else Image.COMPRESS_SOURCE_SRGB
				image.compress(Image.COMPRESS_BPTC,source)
			_local_textures[id] = ImageTexture.create_from_image(image)
		material.set_shader_parameter(param, _local_textures[id])

func material_role(mesh: MeshInstance3D, name: String) -> String:
	if "Face" in str(mesh.name) or "Face" in name: return ""
	if "_SKIN" in name: return "Skin"
	if "_HairBack_" in name: return ""
	if "_HAIR" in name or "Hair" in str(mesh.name): return "Hair"
	if "_Accessory_Tie_" in name: return "NeckAccessory"
	for role in ["Tops", "Bottoms", "Shoes", "InnerTop", "InnerBottom", "ArmAccessory", "NeckAccessory", "Onepiece"]:
		if role.to_lower() in name.to_lower(): return role
	for role in ["Arm", "Neck"]:
		if "Accessory%s" % role in name: return role + "Accessory"
	return ""

func expected_roles(key: String) -> Array:
	if key == "oc_uniform": return ["Tops", "Bottoms", "Shoes", "NeckAccessory"]
	return RECIPES[key][1]

func get_fits(instance: MeshInstance3D, source: Skeleton3D, target: Skeleton3D, target_skin: Skin) -> Array[Dictionary]:
	var source_height := source.get_bone_global_pose(source.find_bone("Head")).origin.y
	var target_height := target_skin.get_bind_pose(target.find_bone("Head")).affine_inverse().origin.y
	var scale := target_height / source_height
	var fits: Array[Dictionary] = []
	for slot in instance.skin.get_bind_count():
		var source_joint := instance.skin.get_bind_bone(slot)
		if source_joint < 0: source_joint = source.find_bone(instance.skin.get_bind_name(slot))
		assert(source_joint >= 0)
		var common := source_joint
		while common >= 0 and target.find_bone(source.get_bone_name(common)) < 0:
			common = source.get_bone_parent(common)
		assert(common >= 0)
		var bone_name := source.get_bone_name(common)
		var target_joint := target.find_bone(bone_name)
		var from := source.get_bone_global_pose(common)
		var to := target_skin.get_bind_pose(target_joint).affine_inverse()
		var rescale := Basis.from_scale(Vector3.ONE * scale)
		var next_name: String = SEGMENT_CHILDREN.get(bone_name, "")
		if not next_name.is_empty() and source.find_bone(next_name) >= 0 and target.find_bone(next_name) >= 0:
			var next_source := source.find_bone(next_name)
			var next_target := target.find_bone(next_name)
			var offset := from.affine_inverse() * source.get_bone_global_pose(next_source).origin
			var length := to.origin.distance_to(target_skin.get_bind_pose(next_target).affine_inverse().origin)
			if offset.length() > .001:
				var axis := offset.normalized()
				var axial := length / offset.length() - scale
				rescale = Basis(Vector3.RIGHT*scale + axis*axis.x*axial, Vector3.UP*scale + axis*axis.y*axial, Vector3.BACK*scale + axis*axis.z*axial)
		var actual := source.get_bone_global_pose(source_joint)
		var fit := to * Transform3D(rescale, Vector3.ZERO) * from.affine_inverse() * actual * instance.skin.get_bind_pose(slot)
		fits.append({"target": target_joint, "transform": fit, "normal": fit.basis.inverse().transposed()})
	return fits

func fit_surface(arrays: Array, fits: Array[Dictionary]) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride := weights.size() / vertices.size()
	for vertex in vertices.size():
		var point := Vector3.ZERO
		var normal := Vector3.ZERO
		var tangent := Vector3.ZERO
		for influence in stride:
			var index := vertex*stride+influence
			var fit := fits[joints[index]]
			joints[index] = fit.target
			var weight := weights[index]
			if weight <= 0.0: continue
			point += (fit.transform*vertices[vertex])*weight
			normal += (fit.normal*normals[vertex])*weight
			if not tangents.is_empty():
				var source_tangent := Vector3(tangents[vertex*4],tangents[vertex*4+1],tangents[vertex*4+2])
				tangent += (fit.transform.basis*source_tangent)*weight
		vertices[vertex] = point
		normals[vertex] = normal.normalized()
		if not tangents.is_empty():
			tangent = tangent.normalized()
			for axis in 3: tangents[vertex*4+axis] = tangent[axis]
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_BONES] = joints
	return arrays

func offset_shell(arrays: Array, thickness: float) -> void:
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in points.size(): points[index] += normals[index]*thickness
	arrays[Mesh.ARRAY_VERTEX] = points

func offset_robe_waist(arrays: Array) -> void:
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in points.size():
		var amount := .012 * (1.0-smoothstep(.06,.24,absf(points[index].y-1.13)))
		points[index] += normals[index]*amount
	arrays[Mesh.ARRAY_VERTEX] = points

func close_robe_underarm(arrays: Array) -> void:
	# Join the torso-side and sleeve-side edges under the left arm of the
	# pinned robe export. The gusset uses the existing cloth vertices and weights.
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert(points.size() == 2569 and points[919].distance_to(Vector3(.130,1.416,.120)) < .002 and points[909].distance_to(Vector3(.153,1.396,.092)) < .002, "Unexpected topology of the exported robe")
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	indices.append_array([1540,1148,909, 1540,909,919, 919,909,1516, 919,1516,1541])
	arrays[Mesh.ARRAY_INDEX] = indices

func append_surface(mesh: ArrayMesh, names: PackedStringArray, materials: Dictionary, arrays: Array, material: ShaderMaterial) -> void:
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if arrays[Mesh.ARRAY_BONES].size() == arrays[Mesh.ARRAY_VERTEX].size()*8 else 0
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	materials[names.size()] = material
	names.append(material.resource_name)

func append_target_parts(mesh: ArrayMesh, names: PackedStringArray, materials: Dictionary, donor_skin: Array, model: int, garment_roles: Dictionary, key: String, neck_y: float, skeleton: Skeleton3D) -> void:
	var base: ArrayMesh = VrmParts.BODY[model][0]
	var field := skin_samples(donor_skin)
	for surface in base.get_surface_count():
		var original := VrmParts.material_for(base, surface)
		if "_SKIN" in original.resource_name:
			var arrays := base.surface_get_arrays(surface)
			if key == "fantasy_robe": append_robe_underlayer(mesh, names, materials, arrays, original, skeleton)
			crop_skin(arrays, field, neck_y, key, skeleton)
			if SOLE_OFFSETS.has(key): tuck_skin_under_footwear(arrays, skeleton, key == "dirndl")
			if model == 1: original = vita_skin(original, donor_skin[0].material, key)
			append_surface(mesh, names, materials, arrays, original)
		elif "Shoes_" in original.resource_name and not garment_roles.has("Shoes"):
			append_surface(mesh, names, materials, base.surface_get_arrays(surface), original)
		elif "Bottoms_" in original.resource_name and not garment_roles.has("Bottoms") and key in ["deer_haori", "orchid_armor"]:
			var arrays := base.surface_get_arrays(surface)
			if key == "deer_haori": trim_haori_underlayer(arrays)
			append_surface(mesh, names, materials, arrays, original)

func tuck_skin_under_footwear(arrays: Array, skeleton: Skeleton3D, tall_stockings: bool) -> void:
	# Leave the exposed skin at the rim and taper the covered leg towards its
	# bone axis so it stays inside the shell when the ankle or knee bends.
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var skin: Skin = VrmParts.SKINS[1]
	var ankles: Array[Vector3] = []
	var knees: Array[Vector3] = []
	for side in ["Right", "Left"]:
		ankles.append(skin.get_bind_pose(skeleton.find_bone(side + "Foot")).affine_inverse().origin)
		knees.append(skin.get_bind_pose(skeleton.find_bone(side + "LowerLeg")).affine_inverse().origin)
	var rim := .509 if tall_stockings else .137
	var taper_start := .461 if tall_stockings else .083
	for index in vertices.size():
		var point := vertices[index]
		if point.y >= rim: continue
		var side := int(point.x >= 0.0)
		var ankle := ankles[side]
		var knee := knees[side]
		var axis := ankle.lerp(knee, clampf(inverse_lerp(ankle.y, knee.y, point.y), 0.0, 1.0))
		var taper := lerpf(.64, 1.0, smoothstep(taper_start, rim, point.y))
		vertices[index] = Vector3(lerpf(axis.x, point.x, taper), point.y, lerpf(axis.z, point.z, taper))
	arrays[Mesh.ARRAY_VERTEX] = vertices

func trim_haori_underlayer(arrays: Array) -> void:
	# The closed skirt covers the thighs and knees. Only the ankle section
	# of the game's trousers is visible where the hem meets the shoes.
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var ankles := PackedInt32Array()
	for at in range(0, indices.size(), 3):
		var a := indices[at]
		var b := indices[at+1]
		var c := indices[at+2]
		if (vertices[a].y+vertices[b].y+vertices[c].y)/3.0 < .40:
			ankles.append(a)
			ankles.append(b)
			ankles.append(c)
	arrays[Mesh.ARRAY_INDEX] = ankles

func append_robe_underlayer(mesh: ArrayMesh, names: PackedStringArray, materials: Dictionary, body: Array, original: ShaderMaterial, skeleton: Skeleton3D) -> void:
	var arrays := body.duplicate()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var inside := PackedInt32Array()
	for at in range(0, indices.size(), 3):
		var center := (vertices[indices[at]]+vertices[indices[at+1]]+vertices[indices[at+2]])/3.0
		if center.y > .235 and center.y < 1.08 and absf(center.x) < .24:
			inside.append(indices[at])
			inside.append(indices[at+1])
			inside.append(indices[at+2])
	arrays[Mesh.ARRAY_INDEX] = inside
	var skin: Skin = VrmParts.SKINS[0]
	var ankles: Array[Vector3] = []
	var knees: Array[Vector3] = []
	for side in ["Right", "Left"]:
		ankles.append(skin.get_bind_pose(skeleton.find_bone(side+"Foot")).affine_inverse().origin)
		knees.append(skin.get_bind_pose(skeleton.find_bone(side+"LowerLeg")).affine_inverse().origin)
	for index in vertices.size():
		var point := vertices[index]
		if point.y >= .34: continue
		var side := int(point.x >= 0.0)
		var ankle := ankles[side]
		var knee := knees[side]
		var axis := ankle.lerp(knee,clampf(inverse_lerp(ankle.y,knee.y,point.y),0.0,1.0))
		# Tuck the lower edge inside the boot instead of overlapping its wall.
		var taper := lerpf(.33,1.0,smoothstep(.27,.34,point.y))
		vertices[index] = Vector3(lerpf(axis.x,point.x,taper),point.y,lerpf(axis.z,point.z,taper))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var textile := original.duplicate(false) as ShaderMaterial
	textile.next_pass = null
	textile.resource_name = "Fantasy_InnerLeggings_CLOTH"
	var white := Image.create(2,2,false,Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var flat := ImageTexture.create_from_image(white)
	textile.set_shader_parameter("_MainTex", flat)
	textile.set_shader_parameter("_ShadeTexture", flat)
	textile.set_shader_parameter("_Color", Color("4b4c51"))
	textile.set_shader_parameter("_ShadeColor", Color("3c3d41"))
	textile.set_shader_parameter("_BumpMap", null)
	textile.set_shader_parameter("_RimColor", Color.BLACK)
	append_surface(mesh, names, materials, arrays, textile)

func vita_skin(original: ShaderMaterial, donor: ShaderMaterial, key: String) -> ShaderMaterial:
	# Vita's stage stockings and gloves are painted onto her body UV. Use the
	# clean pixiv VRoid skin atlas already used by the other clothes on this body.
	var sample: ArrayMesh = VrmParts.BODY[1][1]
	var neutral: Texture2D
	var neutral_bump: Texture2D
	for slot in sample.get_surface_count():
		var material := VrmParts.material_for(sample, slot)
		if "_SKIN" in material.resource_name:
			neutral = material.get_shader_parameter("_MainTex") as Texture2D
			neutral_bump = material.get_shader_parameter("_BumpMap") as Texture2D
			break
	assert(neutral != null)
	var skin := original.duplicate(false) as ShaderMaterial
	skin.next_pass = null
	skin.set_shader_parameter("_MainTex", neutral)
	if key == "oc_uniform":
		# The uniform's short black stockings are part of its VRoid body texture.
		# Transfer only the dark fabric in the two thigh islands of the shared UV.
		var result := neutral.get_image()
		var stockings := (donor.get_shader_parameter("_MainTex") as Texture2D).get_image()
		if result.is_compressed(): result.decompress()
		if stockings.is_compressed(): stockings.decompress()
		result.convert(Image.FORMAT_RGBA8)
		result.clear_mipmaps()
		stockings.resize(result.get_width(), result.get_height(), Image.INTERPOLATE_BILINEAR)
		var width := result.get_width()
		var height := result.get_height()
		for y in range(height/2, height*7/10):
			for x in width:
				if x >= width*24/100 and x < width*76/100: continue
				var fabric := stockings.get_pixel(x, y)
				if fabric.a > .5 and fabric.v < .24: result.set_pixel(x,y,fabric)
		neutral = ImageTexture.create_from_image(result)
	skin.set_shader_parameter("_MainTex", neutral)
	skin.set_shader_parameter("_ShadeTexture", neutral)
	skin.set_shader_parameter("_BumpMap", neutral_bump)
	localize_textures(skin)
	return skin

func sample_cell(point: Vector3) -> Vector3i:
	return Vector3i(floor(point / VISIBLE_SKIN_LIMIT))

func skin_samples(donor_skin: Array) -> Dictionary:
	var field := {}
	for entry in donor_skin:
		var texture := entry.material.get_shader_parameter("_MainTex") as Texture2D
		var image := texture.get_image() if texture != null else null
		var indices: PackedInt32Array = entry.arrays[Mesh.ARRAY_INDEX]
		var points: PackedVector3Array = entry.arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = entry.arrays[Mesh.ARRAY_TEX_UV]
		for index in range(0, indices.size(), 3):
			var a := indices[index]
			var b := indices[index+1]
			var c := indices[index+2]
			var center := (points[a]+points[b]+points[c])/3.0
			if image != null and not uv.is_empty():
				var coord := (uv[a]+uv[b]+uv[c])/3.0
				var pixel := Vector2i((coord*Vector2(image.get_size())).clamp(Vector2.ZERO,Vector2(image.get_size()-Vector2i.ONE)))
				if image.get_pixelv(pixel).a < .5: continue
			for point in [points[a], points[b], points[c], center]:
				var cell := sample_cell(point)
				if not field.has(cell): field[cell] = PackedVector3Array()
				field[cell].append(point)
	return field

func exposed(point: Vector3, field: Dictionary) -> bool:
	var cell := sample_cell(point)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for nearby in field.get(cell + Vector3i(dx,dy,dz), []):
					if point.distance_squared_to(nearby) < VISIBLE_SKIN_LIMIT*VISIBLE_SKIN_LIMIT: return true
	return false

func crop_skin(arrays: Array, field: Dictionary, neck_y: float, key: String, skeleton: Skeleton3D) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride := bones.size()/vertices.size()
	var hand_bones := {}
	var covered_bones := {}
	var long_sleeve := key in ["jacket_pants", "orchid_uniform"]
	if long_sleeve:
		for bone in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(bone)
			for part in ["Hand", "Thumb", "Index", "Middle", "Ring", "Little"]:
				if part in name: hand_bones[bone] = true
	if key in ["dirndl", "orchid_armor", "dreamy_angel"]:
		var segment := "LowerArm" if key == "dirndl" else "UpperArm"
		for side in ["Left", "Right"]: covered_bones[skeleton.find_bone(side + segment)] = true
	var keep := PackedInt32Array()
	for index in range(0, indices.size(), 3):
		var triangle := [indices[index], indices[index+1], indices[index+2]]
		var center := (vertices[triangle[0]]+vertices[triangle[1]]+vertices[triangle[2]])/3.0
		if key == "orchid_armor" and center.y < .9: continue
		if key == "deer_haori" and center.y < 1.20 and absf(center.x) < .24: continue
		if key == "fantasy_robe" and center.y < 1.08 and absf(center.x) < .24: continue
		var visible := center.y >= neck_y-.01 or exposed(center,field)
		# The exposed knees of the shorts outfit need the entire target skin ring.
		if key == "dreamy_angel" and center.y > .56 and center.y < .78: visible = true
		if long_sleeve and center.y < neck_y-.01:
			# Keep ankle bridges below the hems and hands past the wrist bones.
			visible = center.y < .16 or group_weight(triangle, bones, weights, stride, hand_bones) > .4
		if visible and not covered_bones.is_empty() and group_weight(triangle, bones, weights, stride, covered_bones) > .36:
			visible = false
		if visible: keep.append_array(triangle)
	arrays[Mesh.ARRAY_INDEX] = keep

func group_weight(triangle: Array, bones: PackedInt32Array, weights: PackedFloat32Array, stride: int, group: Dictionary) -> float:
	var total := 0.0
	for vertex: int in triangle:
		for offset in stride:
			var influence := vertex*stride+offset
			if group.has(bones[influence]): total += weights[influence]
	return total/3.0
