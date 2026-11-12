extends RefCounted
## Свет идёт от конкретного витража; его цвет и переплёт проецируются на геометрию.
const RADIUS := 102.5
const SHAFT_SHADER := preload("res://assets/vfx_vendor/effects_lab/shaft.gdshader")
# При изменении _pattern увеличивать версию. Хэш сохраняет совместимость с
# готовыми текстурами прежней версии, параметры каждого витража входят в ключ.
const PATTERN_VERSION := 1
const PATTERN_BASELINE := "f95ac95b0ebc076adf403d1f9ed498c5384b9c1676ed75c9f29560fb3f588eb3"
static var _textures: Dictionary = {}
static var _shaft_noise: Texture2D
static var _shaft_mesh: ArrayMesh

static func build(arena: Node3D) -> void:
	# Два дальних витража и два боковых дают холодные и золотистые пятна по краям поля.
	for index in 4:
		var bay: int = [16, 20, 8, 4][index]
		var angle := TAU * bay / 24.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		var tangent := Vector3(-sin(angle), 0, cos(angle))
		var color := VisualUtil.attr_color(bay / 4).lerp(Color(.80,.85,.9), .28)
		var origin := radial * RADIUS + Vector3.UP * 36
		var target := radial * 30 + tangent * (5 if index % 2 == 0 else -5)
		var light := SpotLight3D.new()
		light.name = "WindowProjection%d" % index
		arena._decor.add_child(light)
		light.position = origin
		light.look_at(target)
		light.light_color = Color.WHITE
		light.light_projector = _pattern(bay, color)
		light.light_energy = 520.0
		light.spot_range = 130
		light.spot_angle = 19
		light.spot_attenuation = 1.2
		light.spot_angle_attenuation = .25
		# Godot 4.7 требует включённую карту теней для правильной матрицы проектора.
		# https://docs.godotengine.org/en/4.7/classes/class_light3d.html#class-light3d-property-light-projector
		light.shadow_enabled = true
		light.shadow_bias = .03
		light.shadow_normal_bias = .35
		light.shadow_blur = .8
		light.set_meta("window_projector", index)
		light.set_meta("window_bay", bay)
		light.set_meta("window_target", target)
		arena._sanctuary_lights.append(light)
		# Отражённый цвет вокруг самого стекла делает источник заметным с уровня поля.
		var bounce := OmniLight3D.new()
		bounce.position = radial * 96 + Vector3.UP * 31
		bounce.light_color = color
		bounce.light_energy = 20
		bounce.omni_range = 29
		bounce.omni_attenuation = 1.1
		arena._decor.add_child(bounce)
		arena._sanctuary_lights.append(bounce)
		_shaft(arena, origin, target, color, index)

static func apply_quality(light: SpotLight3D, high: bool) -> void:
	var bay := int(light.get_meta("window_bay"))
	var color := VisualUtil.attr_color(bay / 4).lerp(Color(.80,.85,.9), .28)
	light.light_projector = _pattern(bay, color, 512 if high else 128)

static func _pattern(bay: int, tint: Color, resolution: int = 128) -> Texture2D:
	var key := Vector2i(bay, resolution)
	if _textures.has(key): return _textures[key]
	var prepared_key := ""
	if PreparationStore.enabled:
		prepared_key = str([PATTERN_VERSION, PATTERN_BASELINE, bay, tint, resolution]).sha256_text()
		var prepared: Variant = PreparationStore.read_cache("window-pattern",prepared_key)
		if prepared is PackedByteArray:
			var cached_image := Image.create_from_data(resolution,resolution,true,Image.FORMAT_RGBA8,prepared)
			var cached_texture := ImageTexture.create_from_image(cached_image)
			_textures[key] = cached_texture
			return cached_texture
	var soft := resolution > 128
	var image := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	for y in resolution:
		for x in resolution:
			var uv := Vector2((x + .5) / resolution, 1 - (y + .5) / resolution)
			var px := (uv.x - .5) / .43
			var arch := .70 + .26 * sqrt(maxf(0, 1 - px * px))
			var edge := minf(1 - absf(px), minf((arch - uv.y) * 3, (uv.y - .04) * 4))
			var mask := smoothstep(0, .12 if soft else .07, edge)
			var p := uv * Vector2(5, 11)
			var cell := Vector2(absf(fposmod(p.x + p.y * .5, 1) - .5), absf(fposmod(p.x - p.y * .5, 1) - .5))
			var lead := smoothstep(.005 if soft else .018, .095 if soft else .05, minf(cell.x, cell.y))
			# Три каменных импоста и перемычка, согласованные с видимым витражом.
			var mullion := 1.0
			for cross_x in [.27, .5, .73]:
				mullion *= smoothstep(.002 if soft else .009, .038 if soft else .023, absf(uv.x - cross_x))
			mullion *= smoothstep(.002 if soft else .009, .035 if soft else .02, absf(uv.y - .55))
			var rose := (uv - Vector2(.5,.79)) * Vector2(1,2.5)
			var r := rose.length()
			var petals := smoothstep(.018,.045,absf(sin(rose.angle()*6))) * smoothstep(.012,.035,absf(r-.16))
			lead *= lerpf(1, petals, 1-smoothstep(.20,.23,r))
			var pane := .55 + .45 * (.5 + .5 * sin(p.y * 1.7 + p.x * 1.2))
			var glass := tint.lerp(Color(1,.94,.78), (.5 + .5 * sin(p.x * 2.0 - p.y)) * .32)
			# Рассеянный свет не оставляет чёрных прямоугольных провалов между стёклами.
			var transmission := lerpf(.18, 1.0, lead * mullion) if soft else lead * mullion
			var strength := mask * transmission * pane
			image.set_pixel(x,y,Color(glass.r * strength, glass.g * strength, glass.b * strength,1))
	image.generate_mipmaps()
	PreparationStore.write_cache("window-pattern",prepared_key,image.get_data())
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture

static func _shaft(arena: Node3D, origin: Vector3, target: Vector3, tint: Color, index: int) -> void:
	if _shaft_mesh == null:
		_shaft_mesh = _build_shaft_mesh()
		var noise := FastNoiseLite.new()
		noise.seed = 9
		noise.frequency = .05
		_shaft_noise = ImageTexture.create_from_image(noise.get_seamless_image(64, 64))
	var material := ShaderMaterial.new()
	material.shader = SHAFT_SHADER
	material.set_shader_parameter("color", tint)
	material.set_shader_parameter("intensity", .070)
	material.set_shader_parameter("noise_texture", _shaft_noise)
	var mi: MeshInstance3D = arena._mi(_shaft_mesh, material, (origin + target) * .5)
	var axis := (origin - target).normalized()
	var tangent := Vector3.UP.cross(axis).normalized()
	mi.basis = Basis(tangent, axis, tangent.cross(axis)).scaled_local(Vector3(1, origin.distance_to(target), 1))
	mi.name = "WindowShaft%d" % index
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("window_shaft", true)
	mi.set_meta("window_projector", index)
	arena._sanctuary_shafts.append(mi)


static func _build_shaft_mesh() -> ArrayMesh:
	# Две расширяющиеся плоскости сохраняют объём с обзорной и низкой камер.
	var corners := [Vector2(-2.8, .5), Vector2(2.8, .5), Vector2(-10, -.5), Vector2(10, -.5)]
	var uvs := [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for direction: Vector3 in [Vector3.RIGHT, Vector3.BACK * .55]:
		var normal := direction.normalized().cross(Vector3.UP)
		for index in [0, 1, 2, 1, 3, 2]:
			var corner: Vector2 = corners[index]
			mesh.set_normal(normal)
			mesh.set_uv(uvs[index])
			mesh.add_vertex(direction * corner.x + Vector3.UP * corner.y)
	return mesh.commit()
