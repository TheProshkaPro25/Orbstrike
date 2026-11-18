extends CanvasLayer
## Reprojects the painted sea and terrain sheets against the live battle camera.
## The cloud sprites and their painted shadow mask drift together in world space.

const SEA_SHADER := preload("res://scenes/experiments/illustrated_harbor/sea.gdshader")
const COAST := preload("res://assets/experiments/illustrated_harbor/coast.png")
const TERRAIN := preload("res://assets/experiments/illustrated_harbor/terrain.png")
const MAP := preload("res://assets/experiments/illustrated_harbor/map.png")
const CLOUD_ATLAS := preload("res://assets/experiments/illustrated_harbor/clouds.png")
const LANDMARK_ATLAS := preload("res://assets/experiments/illustrated_harbor/landmarks.png")
const DETAIL_ATLAS := preload("res://assets/experiments/illustrated_harbor/details.png")
const LANDMARKS := [Vector4(-400, -255, 59, 84), Vector4(-194, -165, 13, 51), Vector4(193, -145, 6, 34)]
const FlightInk := preload("res://scenes/experiments/illustrated_harbor/flight_ink.gd")
const CLOUDS := [
	Vector4(-288, -198, 80, 92), Vector4(145, -239, 103, 70), Vector4(340, -370, 121, 133),
	Vector4(-498, -341, 101, 125), Vector4(-221, -594, 150, 167), Vector4(43, -689, 96, 101),
	Vector4(360, -96, 81, 114), Vector4(589, -38, 171, 130), Vector4(799, -233, 105, 98),
	Vector4(873, -545, 191, 183), Vector4(544, -711, 98, 111), Vector4(-664, -183, 149, 104),
	Vector4(-578, 135, 112, 147), Vector4(-244, 243, 103, 97), Vector4(-21, 425, 81, 110),
	Vector4(216, 368, 132, 153), Vector4(432, 298, 70, 75), Vector4(723, 468, 155, 140),
	Vector4(-452, 532, 107, 123), Vector4(-705, 435, 118, 112), Vector4(-955, 142, 161, 175),
	Vector4(-1179, -440, 204, 151), Vector4(-1001, -663, 180, 127), Vector4(-756, -899, 164, 181),
	Vector4(-470, -1023, 189, 202), Vector4(-64, -1036, 149, 154), Vector4(462, -1188, 251, 220),
	Vector4(1093, -806, 193, 194), Vector4(1072, -120, 129, 133), Vector4(1066, 166, 139, 157),
	Vector4(831, 824, 201, 208), Vector4(381, 894, 135, 123), Vector4(-62, 848, 160, 157),
	Vector4(-348, 983, 148, 112), Vector4(-706, 972, 202, 189), Vector4(-967, 713, 160, 144),
	Vector4(1335, 604, 218, 187), Vector4(-1282, 834, 202, 252), Vector4(88, -438, 116, 65),
]

var camera: CameraRig
var _sea := ShaderMaterial.new()
var _cloud_sprites: Array[Sprite2D] = []
var _landmark_sprites: Array[Sprite2D] = []
var _detail_sprites: Array[Sprite2D] = []
var _detail_shadows: Array[Polygon2D] = []
var _shadow_points: Array[PackedVector3Array] = []
var _details: Array[Vector4] = []
var _field: Image
var _details_camera_transform: Transform3D
var _details_frame := Vector2.ZERO
var _details_ray_left := Vector3.ZERO
var _flight_ink := FlightInk.new()
var _age := 0.0


func _ready() -> void:
	name = "IllustratedHarborCanvas"
	layer = -1
	# Read the drawing transform after the regular battle camera has moved.
	process_priority = 30
	_sea.shader = SEA_SHADER
	_sea.set_shader_parameter("coast_atlas", COAST)
	_sea.set_shader_parameter("terrain_atlas", TERRAIN)
	_sea.set_shader_parameter("map_atlas", MAP)
	var backdrop := ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.material = _sea
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in CLOUDS.size():
		var sprite := Sprite2D.new()
		sprite.texture = CLOUD_ATLAS
		sprite.region_enabled = true
		sprite.region_rect = Rect2((i % 4) * 192, 0, 192, 144)
		sprite.region_filter_clip_enabled = true
		sprite.hide()
		add_child(sprite)
		_cloud_sprites.append(sprite)
	for i in LANDMARKS.size():
		var sprite := Sprite2D.new()
		sprite.texture = LANDMARK_ATLAS
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0 if i == 0 else 256, 0, 256, 256)
		sprite.region_filter_clip_enabled = true
		sprite.hide()
		add_child(sprite)
		_landmark_sprites.append(sprite)
	_prepare_details()
	var ink_layer := CanvasLayer.new()
	ink_layer.layer = 0
	add_child(ink_layer)
	_flight_ink.camera = camera
	ink_layer.add_child(_flight_ink)
	_update_projection()


func _process(delta: float) -> void:
	_age += delta
	_update_projection()
	_flight_ink.update_path(delta)


func set_active(active: bool) -> void:
	visible = active
	set_process(active)
	_flight_ink.visible = active
	if not active:
		_flight_ink.clear_path()


func _update_projection() -> void:
	var frame := camera.get_viewport().get_visible_rect().size
	if frame.x <= 0.0 or frame.y <= 0.0:
		return
	var camera_transform := camera.get_camera_transform()
	var ray_middle := camera.project_ray_normal(frame * .5)
	var ray_top := camera.project_ray_normal(Vector2(frame.x * .5, 0.0))
	var ray_left := camera.project_ray_normal(Vector2(0.0, frame.y * .5))
	_sea.set_shader_parameter("eye", camera_transform.origin)
	_sea.set_shader_parameter("forward", ray_middle)
	_sea.set_shader_parameter("up", ray_top / ray_top.dot(ray_middle) - ray_middle)
	_sea.set_shader_parameter("left", ray_left / ray_left.dot(ray_middle) - ray_middle)
	var wind := Vector2(4.4, -1.7) * sin(_age * .066)
	_sea.set_shader_parameter("wind", wind)
	for i in CLOUDS.size():
		var cloud: Vector4 = CLOUDS[i]
		var position := Vector3(cloud.x + wind.x, cloud.z, cloud.y + wind.y)
		var sprite := _cloud_sprites[i]
		var depth := (position - camera_transform.origin).dot(ray_middle)
		if depth < 18.0:
			sprite.hide()
			continue
		var center := camera.unproject_position(position)
		var edge := camera.unproject_position(position + camera_transform.basis.x * cloud.w * .5)
		var width := 2.0 * center.distance_to(edge)
		sprite.position = center
		sprite.scale = Vector2.ONE * width / 192.0
		sprite.z_index = 1 + maxi(0, 55 - int(depth / 30.0))
		var haze := smoothstep(320.0, 1750.0, depth)
		var opacity := smoothstep(.95, 2.0, depth / cloud.w)
		sprite.modulate = Color(1.0, 1.0, 1.0, opacity).lerp(Color(.79, .91, .94, .85 * opacity), haze * .5)
		sprite.visible = Rect2(-width, -width, frame.x + width * 2.0, frame.y + width * 2.0).has_point(center)
	for i in LANDMARKS.size():
		var point: Vector4 = LANDMARKS[i]
		var position := Vector3(point.x, point.z, point.y)
		var sprite := _landmark_sprites[i]
		var depth := (position - camera_transform.origin).dot(ray_middle)
		if depth < 18.0:
			sprite.hide()
			continue
		var center := camera.unproject_position(position)
		var edge := camera.unproject_position(position + camera_transform.basis.x * point.w * .5)
		var width := 2.0 * center.distance_to(edge)
		sprite.position = center
		sprite.scale = Vector2.ONE * width / 256.0
		sprite.z_index = 1 + maxi(0, 55 - int(depth / 30.0))
		sprite.modulate = Color.WHITE.lerp(Color(.73, .89, .93), smoothstep(850.0, 2200.0, depth) * .25)
		sprite.visible = Rect2(-width, -width, frame.x + width * 2.0, frame.y + width * 2.0).has_point(center)
	if camera_transform == _details_camera_transform and frame == _details_frame and ray_left == _details_ray_left:
		return
	_details_camera_transform = camera_transform
	_details_frame = frame
	_details_ray_left = ray_left
	for i in _details.size():
		var point := _details[i]
		var position := Vector3(point.x, point.z, point.y)
		var sprite := _detail_sprites[i]
		var shadow := _detail_shadows[i]
		var depth := (position - camera_transform.origin).dot(ray_middle)
		sprite.hide()
		shadow.hide()
		if depth < 18.0:
			continue
		var base := camera.unproject_position(position)
		var top := camera.unproject_position(position + Vector3.UP * point.w)
		var height := base.distance_to(top)
		if height < 2.0 or not Rect2(-height, -height, frame.x + height * 2.0, frame.y + height * 2.0).has_point(base):
			continue
		if not _detail_visible(camera_transform.origin, position + Vector3.UP * point.w * .35):
			continue
		sprite.position = base
		sprite.rotation = (top - base).angle() + PI * .5
		sprite.scale = Vector2.ONE * height / 192.0
		sprite.z_index = 1 + maxi(0, 55 - int(depth / 30.0))
		sprite.modulate = Color.WHITE.lerp(Color(.73, .89, .93), smoothstep(850.0, 2200.0, depth) * .25)
		sprite.show()
		var outline := PackedVector2Array()
		for vertex in _shadow_points[i]:
			outline.append(camera.unproject_position(vertex))
		shadow.polygon = outline
		shadow.show()


func _prepare_details() -> void:
	_field = MAP.get_image()
	var rng := RandomNumberGenerator.new()
	rng.seed = 18213
	for i in 6500:
		var p := Vector2(rng.randf_range(-1250.0, 1250.0), rng.randf_range(-1250.0, 1250.0))
		var height := _height_at(p)
		if height < 2.0 or height > 44.0 or p.distance_to(Vector2(-400.0, -255.0)) < 68.0:
			continue
		var kind := rng.randi_range(0, 5)
		if kind < 3 and sin(p.x * .037) * cos(p.y * .043) < .05:
			continue
		var size := rng.randf_range(16.0, 25.0) if kind < 3 else rng.randf_range(8.0, 14.0)
		_details.append(Vector4(p.x, p.y, height, size))
		var sprite := Sprite2D.new()
		sprite.texture = DETAIL_ATLAS
		sprite.region_enabled = true
		sprite.region_rect = Rect2(kind * 128, 0, 128, 192)
		sprite.region_filter_clip_enabled = true
		sprite.offset.y = -96.0
		sprite.hide()
		add_child(sprite)
		_detail_sprites.append(sprite)
		var shadow := Polygon2D.new()
		shadow.color = Color(.12, .25, .17, .25 if kind < 3 else .18)
		shadow.antialiased = true
		add_child(shadow)
		_detail_shadows.append(shadow)
		var outline := PackedVector3Array()
		var direction := Vector2(.79, .61)
		var side := Vector2(-direction.y, direction.x)
		for corner in 12:
			var angle := TAU * corner / 12.0
			var vertex := p + direction * size * (.28 + cos(angle) * .27) + side * sin(angle) * size * .18
			outline.append(Vector3(vertex.x, _height_at(vertex) + .15, vertex.y))
		_shadow_points.append(outline)


func _height_at(p: Vector2) -> float:
	var uv := (p / 3200.0 + Vector2.ONE * .5) * Vector2(_field.get_size()) - Vector2.ONE * .5
	var pixel := Vector2i(uv.floor()).clamp(Vector2i.ZERO, _field.get_size() - Vector2i(2, 2))
	var blend := uv - Vector2(pixel)
	var a := _field.get_pixelv(pixel).lerp(_field.get_pixelv(pixel + Vector2i.RIGHT), blend.x)
	var b := _field.get_pixelv(pixel + Vector2i.DOWN).lerp(_field.get_pixelv(pixel + Vector2i.ONE), blend.x)
	var data := a.lerp(b, blend.y)
	return -8.0 + (data.r * (256.0 / 257.0) + data.a / 257.0) * 70.2


func _detail_visible(eye: Vector3, point: Vector3) -> bool:
	var steps := clampi(int(eye.distance_to(point) / 25.0), 4, 64)
	for i in range(1, steps):
		var sample := eye.lerp(point, float(i) / steps)
		if _height_at(Vector2(sample.x, sample.z)) > sample.y + 1.0:
			return false
	return true
