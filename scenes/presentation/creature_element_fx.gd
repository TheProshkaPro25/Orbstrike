extends MeshInstance3D
## Общие материалы и сетки для замаха у модели и выброса при контакте.

const SHADER := preload("res://scenes/shaders/creature_element_fx.gdshader")
const DETAIL_COUNTS := [8, 12, 16]
const IMPACT_DURATIONS := [0.64, 0.56, 0.56, 0.89, 0.68, 0.82]
const LIGHT_COLORS := [Color("ff632f"), Color("68dcff"), Color("ffdf90"), Color.WHITE, Color.WHITE, Color("709db7")]
const LIGHT_ENERGY := [11.0, 6.8, 8.9, 0.0, 0.0, 3.7]
const TEXTURES := {
	&"impact_fire": preload("res://assets/vfx_vendor/elemental_impact/textures/t_fireball.png"),
	&"impact_smoke": preload("res://assets/vfx_vendor/elemental_impact/textures/t_smokepuff.png"),
	&"impact_glint": preload("res://assets/vfx_vendor/elemental_impact/textures/t_sparkglint.png"),
	&"storm_spark": preload("res://assets/vfx_vendor/kenney/spark_05.png"),
	&"storm_flare": preload("res://assets/vfx_vendor/kenney/flare_01.png"),
	&"dust_texture": preload("res://assets/vfx_vendor/kenney/smoke_04.png"),
	&"soft_noise": preload("res://assets/vfx_vendor/reeboo/textures/noise_soft.png"),
}

static var _material: ShaderMaterial
static var _meshes: Array[ArrayMesh] = []
static var _stone_meshes: Array[ArrayMesh] = []

var element: int
var _charge_tween: Tween
var _light: OmniLight3D
var impact_contact: Vector3
var impact_surface_y: float


func configure(element: int, footprint: Vector2, height: float) -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		for parameter in TEXTURES:
			_material.set_shader_parameter(parameter, TEXTURES[parameter])
		for count in DETAIL_COUNTS:
			_meshes.append(_detail_mesh(count, false))
			_stone_meshes.append(_detail_mesh(count, true))
	name = &"ElementEffect"
	hide()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _material
	var width := clampf(footprint.x, height * 0.34, height * 1.20)
	var length := clampf(footprint.y, height * 0.34, height * 1.35)
	set_instance_shader_parameter(&"figure_size", Vector3(width, height, length))
	set_element(element)
	update_quality()
	set_instance_shader_parameter(&"phase_offset", float(get_instance_id() % 997) / 997.0)
	var margin := Vector3(width + height * 0.48, height * 0.95, length + height * 0.48)
	custom_aabb = AABB(Vector3(0, height * 0.47, 0) - margin, 2.0 * margin)


func set_element(value: int) -> void:
	element = value
	set_instance_shader_parameter(&"element", value)


func update_quality() -> void:
	var meshes := _stone_meshes if element == Attr.A.STONE else _meshes
	mesh = meshes[GraphicsSettings.current()]


func begin_charge(local_target: Vector3, amount: float) -> void:
	reset_effect()
	if not get_parent_node_3d().is_visible_in_tree():
		return
	update_quality()
	var forward := local_target.slide(Vector3.UP).normalized()
	rotation.y = atan2(forward.x, forward.z)
	set_instance_shader_parameter(&"impact", false)
	set_instance_shader_parameter(&"amplitude", amount)
	windup(0.0)
	show()


func windup(progress: float) -> void:
	set_instance_shader_parameter(&"progress", progress)


func finish_charge(landed: bool) -> void:
	if not landed or not is_visible_in_tree():
		reset_effect()
		return
	_charge_tween = create_tween()
	_charge_tween.tween_method(windup, 1.0, 1.36, 0.16)
	_charge_tween.tween_callback(hide)


func reset_effect() -> void:
	if _charge_tween != null and _charge_tween.is_valid():
		_charge_tween.kill()
	_charge_tween = null
	if _light != null:
		_light.light_energy = 0.0
		_light.hide()
	hide()


func prepare_impact() -> void:
	configure(0, Vector2.ONE, 1.0)
	name = &"ElementImpact"
	set_instance_shader_parameter(&"impact", true)
	custom_aabb = AABB(Vector3(-3.0, -0.5, -2.9), Vector3(6.0, 4.6, 6.6))
	_light = OmniLight3D.new()
	_light.name = &"ImpactLight"
	_light.shadow_enabled = false
	_light.light_cull_mask = 1
	_light.omni_attenuation = 1.25
	_light.light_volumetric_fog_energy = 0.0
	_light.light_energy = 0.0
	_light.hide()
	add_child(_light)


func show_impact(value: int, at: Vector3, direction: Vector3, size: float, amount: float,
		surface: ArenaCardNode = null, floor_y: float = 0.0) -> void:
	reset_effect()
	set_element(value)
	update_quality()
	impact_contact = at
	var top := surface.surface_height_at(at) if is_instance_valid(surface) else -INF
	var on_gate := is_finite(top) and top > floor_y
	impact_surface_y = top if on_gate else floor_y
	var along := direction.slide(Vector3.UP).normalized()
	var base := Vector3(at.x, impact_surface_y, at.z)
	global_transform = Transform3D(Basis(Vector3.UP, atan2(along.x, along.z)).scaled(Vector3.ONE * size), base)
	var height := maxf((at.y - impact_surface_y) / size, 0.1)
	set_instance_shader_parameter(&"contact_height", height)
	set_instance_shader_parameter(&"surface_origin", surface.to_local(base) if on_gate else Vector3.ZERO)
	set_instance_shader_parameter(&"surface_axis_x", surface.global_basis.inverse() * global_basis.x if on_gate else Vector3.ZERO)
	set_instance_shader_parameter(&"surface_axis_z", surface.global_basis.inverse() * global_basis.z if on_gate else Vector3.ZERO)
	set_instance_shader_parameter(&"surface_limits", Vector2(ArenaCardNode.SIZE.x, ArenaCardNode.SIZE.z) * 0.5 if on_gate else Vector2.ZERO)
	set_instance_shader_parameter(&"surface_step", (impact_surface_y - floor_y) / size)
	set_instance_shader_parameter(&"amplitude", amount)
	_light.position = Vector3(0.0, height, -0.24)
	_light.light_color = LIGHT_COLORS[value]
	_light.omni_range = clampf(size * 3.5, 7.0, 14.0)
	_light.visible = bool(GraphicsSettings.param("lights")) and LIGHT_ENERGY[value] > 0.0
	_impact_frame(0.0)
	show()
	_charge_tween = create_tween()
	_charge_tween.tween_method(_impact_frame, 0.0, 1.0, IMPACT_DURATIONS[value])
	_charge_tween.tween_callback(reset_effect)


func _impact_frame(progress: float) -> void:
	windup(progress)
	if _light.visible:
		var amount := float(get_instance_shader_parameter(&"amplitude"))
		_light.light_energy = LIGHT_ENERGY[element] * amount * pow(maxf(1.0 - progress / 0.74, 0.0), 1.67)


static func _detail_mesh(count: int, stone: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for detail in count:
		var seed := fposmod(detail * 0.61803399, 1.0)
		if stone and detail % 4 != 3:
			_append_fragment(detail, seed, vertices, normals, uv, uv2, indices)
			# The first two pieces are dust at contact and stone during the windup.
			if detail >= 2:
				continue
		var first := vertices.size()
		for corner in corners:
			vertices.append(Vector3(corner.x - 0.5, 0.5 - corner.y, 0.0))
			normals.append(Vector3.BACK)
			uv.append(corner)
			uv2.append(Vector2(detail, seed))
		indices.append_array(PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


static func _append_fragment(detail: int, seed: float, vertices: PackedVector3Array, normals: PackedVector3Array,
		uv: PackedVector2Array, uv2: PackedVector2Array, indices: PackedInt32Array) -> void:
	var ring: Array[Vector3] = []
	var tip := Vector3(seed * 0.36 - 0.22, 0.54, sin(seed * TAU) * 0.20)
	var bottom := Vector3(-tip.x * 0.60, -0.48, tip.z * -0.70)
	for corner in 5:
		var angle := corner * TAU / 5.0 + seed * 3.0
		var offset := 0.37 + 0.15 * sin(detail * 5.69 + corner * 4.89)
		ring.append(Vector3(cos(angle) * offset, 0.21 * sin(corner * 5.1 + seed * 7.0), sin(angle) * offset))
	var center := (tip + bottom) * 0.5
	for face in 5:
		var a := ring[face]
		var b := ring[(face + 1) % 5]
		for pole in [tip, bottom]:
			var c: Vector3 = pole
			var normal := (b - a).cross(c - a).normalized()
			if normal.dot((a + b + c) / 3.0 - center) < 0.0:
				normal = -normal
			for vertex in [a, b, c]:
				indices.append(vertices.size())
				vertices.append(vertex)
				normals.append(normal)
				uv.append(Vector2.ZERO)
				uv2.append(Vector2(detail, 1.0 + seed))
