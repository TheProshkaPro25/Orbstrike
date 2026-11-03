class_name FighterAvatar
extends Node3D
## Авторский аниме-боец, кисти и риг MakeHuman CC0, подготовленный заранее. В редакторе меняются параметры
## одного актёра; повторного импорта GLB, сборки и дублирования мешей нет.
const MODEL: PackedScene = preload("res://assets/avatars/fighter_mpfb.glb")
const TOON: Shader = preload("res://scenes/avatar/avatar_toon.gdshader")
const OUTLINE: Shader = preload("res://scenes/avatar/avatar_outline.gdshader")
const SKIN := [Color("ffe0c3"),Color("ffe9d5"),Color("dfab80"),Color("bd855b"),Color("91603f"),Color("68432f")]
const HAIR := [Color("6c452d"),Color("302b30"),Color("aaa59e"),Color("b89960"),Color("7e4840"),Color("2d3b49")]
const COATS := [Color("bd3f32"),Color("3f5f90"),Color("3b725f"),Color("70558d")]
const EYES := [Color("bd3342"),Color("6b8c72"),Color("825e3d"),Color("85818d"),Color("b59b58"),Color("947060")]
const ACCENTS := [Color("cf7351"),Color("62a5c9"),Color("bb9b60"),Color("87b58b"),Color("d4c589"),Color("9d87be")]
var body: Node3D
var materials: Dictionary = {}
var mesh_nodes: Array[MeshInstance3D] = []
var hairs: Array[MeshInstance3D] = []
var skeleton: Skeleton3D
var elapsed := 0.0
var _head := -1
var _spine := -1
var _head_rest := Quaternion.IDENTITY
var _spine_rest := Quaternion.IDENTITY
static var _eye_shader: Shader
static var _outline_material: ShaderMaterial

func build(profile: Dictionary) -> void:
	if body == null:
		body = MODEL.instantiate() as Node3D
		add_child(body)
		for node in body.find_children("*","MeshInstance3D",true,false):
			var mesh := node as MeshInstance3D
			mesh_nodes.append(mesh)
			if str(mesh.name).begins_with("Hair"): hairs.append(mesh)
			for surface in mesh.mesh.get_surface_count():
				var original := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if original == null: continue
				var role := original.resource_name
				var material: Material
				if role.begins_with("Eyes"):
					material = _eye_material(original)
				else:
					var toon := ShaderMaterial.new()
					toon.shader = TOON
					var kind := 0
					if role.begins_with("Outfit") or role.begins_with("Cloth") or role in ["Pants","Gloves","Accent"]: kind = 1
					elif role.begins_with("Hair"): kind = 2
					elif role.begins_with("Brows") or role.begins_with("Lashes") or role.begins_with("Mouth"): kind = 3
					elif role.begins_with("Shoes"): kind = 4
					toon.set_shader_parameter("role",kind)
					toon.set_shader_parameter("upper_lashes",false)
					if kind != 3:
						if _outline_material == null:
							_outline_material = ShaderMaterial.new()
							_outline_material.shader = OUTLINE
						toon.next_pass = _outline_material
					if kind == 3: toon.set_shader_parameter("cutout_texture",original.albedo_texture)
					toon.set_shader_parameter("albedo_color",Color("141a29") if kind == 3 else original.albedo_color)
					material = toon
				mesh.set_surface_override_material(surface,material)
				if not materials.has(role): materials[role] = []
				materials[role].append(material)
		var rigs := body.find_children("*","Skeleton3D",true,false)
		if not rigs.is_empty():
			skeleton = rigs[0]
			_head = skeleton.find_bone("head")
			_spine = skeleton.find_bone("spine02")
			if _head >= 0: _head_rest = skeleton.get_bone_pose_rotation(_head)
			if _spine >= 0: _spine_rest = skeleton.get_bone_pose_rotation(_spine)
	var p := PlayerProfile.normalized(profile)
	for mesh in mesh_nodes:
		for i in mesh.get_blend_shape_count():
			var key := str(mesh.mesh.get_blend_shape_name(i))
			mesh.set_blend_shape_value(i,1.0 if (key == "FaceNarrow" and p.face == 1) or (key == "FaceBroad" and p.face == 2) or (key == "BodyLean" and p.body == 1) or (key == "BodyAthletic" and p.body == 2) else 0.0)
	for hair in hairs: hair.visible = str(hair.name) == "Hair%d" % p.hair
	for role in materials:
		for material in materials[role]:
			if role.begins_with("Skin"):
				material.set_shader_parameter("albedo_color",SKIN[p.skin])
			elif role.begins_with("Hair") or role.begins_with("Brows"):
				material.set_shader_parameter("albedo_color",HAIR[p.hair_color])
			elif role.begins_with("Eyes"):
				material.set_shader_parameter("tint",EYES[p.eyes])
			elif role.begins_with("Accent"):
				material.set_shader_parameter("albedo_color",ACCENTS[p.element])
			elif role.begins_with("Outfit"):
				material.set_shader_parameter("albedo_color",COATS[p.jacket])
				material.set_shader_parameter("accent",ACCENTS[p.element])

static func _eye_material(_original: StandardMaterial3D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	if _eye_shader != null:
		material.shader = _eye_shader
		return material
	var shader := Shader.new()
	shader.code = """shader_type spatial; render_mode cull_disabled, unshaded;
uniform vec4 tint : source_color = vec4(.4,.5,.6,1.0);
void fragment() {

 vec2 d = (UV-vec2(.5,.50))/vec2(.29,.46);
 float radius = length(d);
 vec3 color = vec3(.95,.96,1.0);
 if (radius < 1.0) {
  color = tint.rgb*(.60+clamp(d.y,-.5,.8)*.8);
  if (radius > .88) color *= .24;
  if (length(d*vec2(1.0,.66)) < .32) color = vec3(.012,.018,.03);
  if (length(d-vec2(-.28,-.32)) < .19 || length(d-vec2(.32,.38)) < .08) color = vec3(1.0);
 }
 ALBEDO = color;
 ROUGHNESS = .28; SPECULAR = .4;
}"""
	_eye_shader = shader
	material.shader = shader
	return material

func _process(delta: float) -> void:
	elapsed += delta
	if skeleton != null:
		if _head >= 0: skeleton.set_bone_pose_rotation(_head,_head_rest * Quaternion(Vector3.UP,sin(elapsed*.65)*.015))
		if _spine >= 0: skeleton.set_bone_pose_rotation(_spine,_spine_rest * Quaternion(Vector3.RIGHT,sin(elapsed*1.5)*.003))
