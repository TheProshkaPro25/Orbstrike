extends MeshInstance3D
## Tracks the parent shell in world space. One indexed strip and a bounded sample
## history are reused through every throw, irrespective of the shell's spin.

enum Style { COSMOS, DARK, EARTH, ELECTRIC, FIRE, ICE, NATURE, SOUND, VOID, WATER }

const SHADER := preload("res://assets/vfx/trails/elemental_trail.gdshader")
const POINT_COUNT := 25
const HISTORY_CAPACITY := POINT_COUNT + 1
const MAX_SAMPLE_JUMP_SQUARED := 36.0
# Lifetime, half-width in shell radii, hot core, body, distant halo.
const PROFILES := [
	[0.53, 1.45, Color("#fff0a4"), Color("#ff500d"), Color("#861950")], # Cosmos
	[0.47, 1.25, Color("#ffbdd8"), Color("#fa1151"), Color("#63152d")], # Dark
	[0.48, 1.35, Color("#fff3d1"), Color("#ca9055"), Color("#593524")], # Earth
	[0.51, 1.20, Color("#e6fbff"), Color("#438aff"), Color("#1539ba")], # Electric
	[0.48, 1.36, Color("#fff4a4"), Color("#ff490c"), Color("#b3180c")], # Fire
	[0.48, 1.06, Color("#e8faff"), Color("#7bb7d7"), Color("#23455b")], # Ice
	[0.49, 1.23, Color("#f6ffa1"), Color("#38eb57"), Color("#08764a")], # Nature
	[0.51, 1.35, Color("#fff5ce"), Color("#ffd17b"), Color("#8c5417")], # Sound
	[0.50, 1.40, Color("#f6c1ff"), Color("#922cff"), Color("#1f168d")], # Void
	[0.49, 1.23, Color("#b0f9ff"), Color("#079cf9"), Color("#102994")], # Water
]

var style: Style = Style.FIRE
var manual_sampling := false
var _active := false
var _mesh_visible := false
var _history_count := 0
var _history_head := 0
var _history := PackedVector3Array()
var _centers := PackedVector3Array()
var _vertex_bytes := PackedByteArray()
var _strip := ArrayMesh.new()
var _material := ShaderMaterial.new()
var _previous_center := Vector3.ZERO
var _since_sample := 0.0
var _elapsed := 0.0
var _step := float(PROFILES[Style.FIRE][0]) / (POINT_COUNT - 1)
var _half_width := 0.0
var _width_in_radii := float(PROFILES[Style.FIRE][1])


func _init() -> void:
	name = &"OrbstrikeTrail"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sorting_use_aabb_center = false
	_history.resize(HISTORY_CAPACITY)
	_centers.resize(POINT_COUNT)
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	positions.resize(2 * POINT_COUNT)
	for point in POINT_COUNT:
		var age := float(point) / (POINT_COUNT - 1)
		uvs.append(Vector2(age, 0.0))
		uvs.append(Vector2(age, 1.0))
		if point < POINT_COUNT - 1:
			var v := 2 * point
			indices.append_array([v, v + 1, v + 2, v + 2, v + 1, v + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	_vertex_bytes.resize(2 * POINT_COUNT * 3 * 4) # Two XYZ float32 positions per row.
	mesh = _strip
	_material.shader = SHADER
	material_override = _material
	hide()
	set_process(false)


## shape_scale widens the strip and brings more of its pattern into the close camera.
func configure(new_style: Style, duration_scale: float = 1.0, shape_scale: Vector2 = Vector2.ONE) -> void:
	style = new_style
	var profile: Array = PROFILES[style]
	_step = duration_scale * float(profile[0]) / (POINT_COUNT - 1)
	_width_in_radii = shape_scale.x * float(profile[1])
	_material.set_shader_parameter(&"style", style)
	_material.set_shader_parameter(&"pattern_scale", shape_scale.y)
	_material.set_shader_parameter(&"core_color", profile[2])
	_material.set_shader_parameter(&"body_color", profile[3])
	_material.set_shader_parameter(&"halo_color", profile[4])


func set_airborne(airborne: bool, radius: float = 0.045,
		quality: int = GraphicsSettings.Level.HIGH) -> void:
	if _active == airborne:
		return
	_active = airborne
	_reset_history()
	visible = airborne
	set_process(airborne and not manual_sampling)
	if airborne:
		_half_width = radius * _width_in_radii
		_material.set_shader_parameter(&"show_detail", quality != GraphicsSettings.Level.LOW)


func _reset_history() -> void:
	_history_count = 0
	_history_head = HISTORY_CAPACITY - 1
	_since_sample = 0.0
	_elapsed = 0.0
	_mesh_visible = false
	_material.set_shader_parameter(&"trail_span", 0.0)


func _push(point: Vector3) -> void:
	_history_head = (_history_head + 1) % HISTORY_CAPACITY
	_history[_history_head] = point
	_history_count = mini(_history_count + 1, HISTORY_CAPACITY)


func _process(delta: float) -> void:
	var shell := get_parent() as Node3D
	if shell != null:
		sample(shell.global_position, delta)


func sample(center: Vector3, delta: float) -> void:
	if not _active:
		return
	# A render stall or a teleport starts a fresh strip instead of drawing a
	# straight line between unrelated points. The loop is bounded by capacity.
	if _history_count > 0 and (delta >= _step * POINT_COUNT
			or _previous_center.distance_squared_to(center) > MAX_SAMPLE_JUMP_SQUARED):
		_reset_history()
	if _history_count == 0:
		_push(center)
		_previous_center = center
		return
	_elapsed += delta
	_since_sample += delta
	while _since_sample >= _step:
		_since_sample -= _step
		_push(_previous_center.lerp(center, 1.0 - _since_sample / delta))
	_previous_center = center
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_update_strip(center, camera)


func _update_strip(center: Vector3, camera: Camera3D) -> void:
	_centers[0] = Vector3.ZERO
	var fraction := _since_sample / _step
	for row in range(1, POINT_COUNT):
		var older := posmod(_history_head - mini(row, _history_count - 1), HISTORY_CAPACITY)
		var newer := posmod(_history_head - mini(row - 1, _history_count - 1), HISTORY_CAPACITY)
		_centers[row] = _history[older].lerp(_history[newer], fraction) - center
	var bounds := AABB()
	var side := camera.global_basis.x
	var orthographic := camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	for row in POINT_COUNT:
		var point := _centers[row]
		var tangent := _centers[maxi(row - 1, 0)] - _centers[mini(row + 1, POINT_COUNT - 1)]
		var view := camera.global_basis.z if orthographic else camera.global_position - center - point
		var across := tangent.cross(view)
		# Parallel tangents and duplicate padded points keep the last valid side.
		if across.length_squared() > 0.000000001:
			across = across.normalized()
			side = across if across.dot(side) >= 0.0 else -across
		var width := _half_width * lerpf(1.0, 0.68, float(row) / (POINT_COUNT - 1))
		_write_vertex(2 * row, point - side * width)
		_write_vertex(2 * row + 1, point + side * width)
		bounds = bounds.expand(point)
	# The shader reconstructs the sampled strip in world space and pins its
	# first row to the current shell transform. Cull against that world area.
	bounds.position += center
	custom_aabb = global_transform.affine_inverse() * bounds.grow(_half_width + 0.15)
	_material.set_shader_parameter(&"sample_center", center)
	_strip.surface_update_vertex_region(0, 0, _vertex_bytes)
	_mesh_visible = true
	_material.set_shader_parameter(&"trail_span", minf(_elapsed / (_step * (POINT_COUNT - 1)), 1.0))
	_material.set_shader_parameter(&"flow_time", _elapsed)


func _write_vertex(index: int, vertex: Vector3) -> void:
	var offset := index * 12
	_vertex_bytes.encode_float(offset, vertex.x)
	_vertex_bytes.encode_float(offset + 4, vertex.y)
	_vertex_bytes.encode_float(offset + 8, vertex.z)
