class_name VrmAvatar
extends Node3D
## Imported once by the editor. Runtime uses the prepared PackedScenes and MToon.
const MODELS: Array[PackedScene] = [preload("res://assets/avatars/vrm/Sakurada_Fumiriya.vrm"),preload("res://assets/avatars/vrm/Vita.vrm")]
const TITLES := ["Sakurada Fumiriya", "Vita"]
var actor: Node3D
var skeleton: Skeleton3D
var animation: AnimationPlayer
var selected := -1
var meshes: Array[MeshInstance3D] = []
var _bind_poses: Array[Transform3D] = []
var _static_pose := false
var hair_part: MeshInstance3D
var body_part: MeshInstance3D
var case_part: MeshInstance3D
var _hair_source := -1
var _outfit := -1
var appearance_profile: Dictionary = {}

func select_model(index: int) -> void:
	if selected == index and actor != null: return
	if actor != null:
		_hold_materials_until_draw()
		remove_child(actor)
		actor.queue_free()
	meshes.clear()
	selected = clampi(index,0,MODELS.size()-1)
	actor = MODELS[selected].instantiate() as Node3D
	add_child(actor)
	for node in actor.find_children("*","MeshInstance3D",true,false):
		meshes.append(node)
	var rigs := actor.find_children("*","Skeleton3D",true,false)
	skeleton = rigs[0] if not rigs.is_empty() else null
	var players := actor.find_children("*","AnimationPlayer",true,false)
	animation = players[0] if not players.is_empty() else null
	_relax_arms()
	_setup_parts()
	_localize_materials()
	_static_pose = false
	_bind_poses.clear()
	if skeleton != null:
		for bone in skeleton.get_bone_count(): _bind_poses.append(skeleton.get_bone_pose(bone))

func _relax_arms() -> void:
	if skeleton == null: return
	for side in ["Left", "Right"]:
		var bone := skeleton.find_bone(side+"UpperArm")
		if bone < 0: continue
		var rest := skeleton.get_bone_global_rest(bone)
		var world_axis := rest.basis.get_rotation_quaternion()
		var angle := -signf(rest.origin.x) * 1.08
		var offset := world_axis.inverse() * Quaternion(Vector3(0,0,1),angle) * world_axis
		skeleton.set_bone_pose_rotation(bone,skeleton.get_bone_pose_rotation(bone)*offset)

func set_expression(expression: String) -> void:
	if animation == null: return
	if animation.has_animation("RESET"):
		animation.play("RESET")
		animation.advance(0)
	if expression != "RESET" and animation.has_animation(expression):
		animation.play(expression)
		animation.advance(0)
	animation.stop(true)
	_apply_face()

func expression_names() -> PackedStringArray:
	return animation.get_animation_list() if animation != null else PackedStringArray()

const HAIR_COLORS := [Color.WHITE,Color("4f3023"),Color("191d28"),Color("edc576"),Color("a9b9d0"),Color("8f4c43")]
const EYE_COLORS := [Color.WHITE,Color("597fbf"),Color("68a079"),Color("b93e53"),Color("a67949"),Color("947db5")]
const SKIN_TINTS := [Color.WHITE,Color("f6ddc8"),Color("d5a887"),Color("ac7d62")]
const OUTFIT_COLORS := [Color.WHITE,Color("a83b4a"),Color("40659d"),Color("3f826f"),Color("70608e")]
const HEIGHTS := [.92,1.0,1.08]
var palette_materials: Array[Dictionary] = []
var local_materials: Array[ShaderMaterial] = []

func apply_profile(profile: Dictionary) -> void:
	var p := PlayerProfile.normalized(profile)
	select_model(p.vrm_model)
	appearance_profile = p
	_sync_parts(p)
	case_part.visible = p.vrm_case == 1 and VrmParts.supports_case(selected,p.vrm_clothes)
	_freeze_secondary_motion()
	actor.scale = Vector3.ONE * HEIGHTS[p.vrm_height]
	for entry in palette_materials:
		var mat: ShaderMaterial = entry.material
		var index: int = 0
		var color := Color.WHITE
		match entry.role:
			"hair":
				index = p.vrm_hair
				color = HAIR_COLORS[index]
			"eyes":
				index = p.vrm_eyes
				color = EYE_COLORS[index]
			"outfit":
				index = p.vrm_outfit
				color = OUTFIT_COLORS[index]
			"skin":
				color = SKIN_TINTS[p.vrm_skin]
		mat.set_shader_parameter("palette_enabled",index != 0)
		mat.set_shader_parameter("palette_color",color)
		if entry.role == "skin":
			mat.set_shader_parameter("_Color",entry.base_color * color)
			mat.set_shader_parameter("_ShadeColor",entry.shade_color * color)

	_apply_denim(p.vrm_denim if VrmParts.supports_denim(selected,p.vrm_clothes) else 0)
	_apply_face()

func _apply_denim(index: int) -> void:
	for surface in body_part.mesh.get_surface_count():
		var original := VrmParts.material_for(body_part.mesh,surface)
		if original == null or not "Bottoms_" in original.resource_name: continue
		var mat := body_part.get_surface_override_material(surface) as ShaderMaterial
		mat.set_shader_parameter("_MainTex",DenimWardrobe.TEXTURES[index-1] if index > 0 else original.get_shader_parameter("_MainTex"))
		mat.set_shader_parameter("_ShadeTexture",DenimWardrobe.TEXTURES[index-1] if index > 0 else original.get_shader_parameter("_ShadeTexture"))
		mat.set_shader_parameter("_Color",Color.WHITE if index > 0 else original.get_shader_parameter("_Color"))
		mat.set_shader_parameter("_ShadeColor",Color("b4b4b4") if index > 0 else original.get_shader_parameter("_ShadeColor"))

func _localize_materials() -> void:
	palette_materials.clear()
	local_materials.clear()
	var copies: Dictionary = {}
	for mesh in meshes:
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface) as ShaderMaterial
			if mesh.mesh.has_meta("part_source"): original = VrmParts.material_for(mesh.mesh,surface)
			if original == null: continue
			var id := original.get_instance_id()
			if not copies.has(id): copies[id] = _copy_material(original)
			mesh.set_surface_override_material(surface,copies[id])

func _copy_material(original: ShaderMaterial) -> ShaderMaterial:
	var copy := original.duplicate(false) as ShaderMaterial
	local_materials.append(copy)
	var name := original.resource_name
	var role := ""
	if "_HAIR" in name or "FaceBrow" in name: role = "hair"
	elif "EyeIris" in name: role = "eyes"
	elif "_SKIN" in name: role = "skin"
	elif "Tops_" in name or "AccessoryNeck_" in name: role = "outfit"
	var key := original.shader.resource_path.get_file()
	if VrmPaletteShaders.SHADERS.has(key):
		copy.shader = VrmPaletteShaders.SHADERS[key]
		if not role.is_empty():
			palette_materials.append({"material":copy,"role":role,"base_color":original.get_shader_parameter("_Color"),"shade_color":original.get_shader_parameter("_ShadeColor")})
	if original.next_pass is ShaderMaterial: copy.next_pass = _copy_material(original.next_pass)
	return copy

func _hold_materials_until_draw() -> void:
	# Same-frame model switches can outlive renderer dependency updates.
	var held := local_materials.duplicate()
	if held.is_empty(): return
	if DisplayServer.get_name() == "headless":
		get_tree().process_frame.connect(held.clear,CONNECT_ONE_SHOT)
	elif not RenderingServer.frame_post_draw.is_connected(held.clear):
		RenderingServer.frame_post_draw.connect(held.clear,CONNECT_ONE_SHOT)

func _exit_tree() -> void:
	_hold_materials_until_draw()

func _freeze_secondary_motion() -> void:
	if _static_pose: return
	# The upstream spring solver explicitly requires global scale 1,1,1.
	# Appearance editing uses the imported rest hair pose at all heights.
	for node in actor.find_children("*","Node",true,false):
		if node.get_script() != null and node.get_script().resource_path.ends_with("/vrm_secondary.gd"):
			node.set_process(false)
			node.set_physics_process(false)
			var modifier: Node = node.get("internal_modifier_node")
			if modifier != null: modifier.set("active",false)
	if skeleton != null:
		for bone in _bind_poses.size(): skeleton.set_bone_pose(bone,_bind_poses[bone])
	_static_pose = true

func _setup_parts() -> void:
	for mesh in meshes:
		if not "Face" in str(mesh.name): mesh.hide()
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = &"Head"
	skeleton.add_child(attachment)
	hair_part = MeshInstance3D.new()
	hair_part.name = "ModularHair"
	attachment.add_child(hair_part)
	hair_part.mesh = VrmParts.HAIR[selected][selected]
	body_part = MeshInstance3D.new()
	body_part.name = "ModularCostume"
	actor.add_child(body_part)
	body_part.mesh = VrmParts.BODY[selected][0]
	body_part.skeleton = body_part.get_path_to(skeleton)
	body_part.skin = VrmParts.SKINS[selected]
	meshes.append(hair_part)
	meshes.append(body_part)
	case_part = MeshInstance3D.new()
	case_part.name = "SphereCase"
	actor.add_child(case_part)
	case_part.mesh = VrmParts.CASES[selected]
	case_part.skin = VrmParts.SKINS[selected]
	case_part.skeleton = case_part.get_path_to(skeleton)
	case_part.hide()
	meshes.append(case_part)
	_hair_source = selected
	_outfit = 0

func _sync_parts(p: Dictionary) -> void:
	var source: int = [selected,2,3,4,1-selected,5,6,7,8,9,10][p.vrm_style]
	if _hair_source == source and _outfit == p.vrm_clothes: return
	_hold_materials_until_draw()
	hair_part.mesh = VrmParts.HAIR[selected][source]
	body_part.mesh = VrmParts.BODY[selected][p.vrm_clothes]
	_hair_source = source
	_outfit = p.vrm_clothes
	_localize_materials()

func _apply_face() -> void:
	apply_profile_face_to(meshes)


func apply_profile_face_to(target_meshes: Array[MeshInstance3D]) -> void:
	if appearance_profile.is_empty(): return
	var eye: int = appearance_profile.vrm_eye_shape
	var brow: int = appearance_profile.vrm_brows
	var mouth: int = appearance_profile.vrm_mouth
	for mesh in target_meshes:
		if not "Face" in str(mesh.name): continue
		for index in mesh.get_blend_shape_count():
			var name := str(mesh.mesh.get_blend_shape_name(index))
			var weight := -1.0
			if name.ends_with("_EYE_Angry"): weight = .35 if eye == 1 else 0.0
			elif name.ends_with("_EYE_Sorrow"): weight = .30 if eye == 2 else 0.0
			elif name.ends_with("_BRW_Angry"): weight = .35 if brow == 1 else 0.0
			elif name.ends_with("_BRW_Fun"): weight = .40 if brow == 2 else 0.0
			elif name.ends_with("_MTH_Up"): weight = .25 if mouth == 1 else 0.0
			elif name.ends_with("_MTH_Down"): weight = .20 if mouth == 2 else 0.0
			if weight >= 0: mesh.set_blend_shape_value(index,weight)
