extends RefCounted
## Свет идёт от конкретного витража; его цвет и переплёт проецируются на геометрию.
const RADIUS := 102.5
static var _textures: Dictionary = {}

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
	if PreparationStore.enabled and FileAccess.file_exists("res://scenes/sanctuary_window_light.gd"):
		prepared_key = str([1,FileAccess.get_sha256("res://scenes/sanctuary_window_light.gd"),bay,tint,resolution]).sha256_text()
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
	# Мягкий плоский сноп начинается в плоскости окна, а не из центра купола.
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.8
	mesh.bottom_radius = 12
	mesh.height = 1
	mesh.radial_segments = 32
	mesh.cap_top = false
	mesh.cap_bottom = false
	var material := ShaderMaterial.new()
	material.shader = SHAFT_SHADER
	material.set_shader_parameter("tint", tint)
	var mi: MeshInstance3D = arena._mi(mesh, material, (origin + target) * .5)
	mi.basis = Basis(Quaternion(Vector3.UP,(origin-target).normalized())) * Basis.from_scale(Vector3(1,origin.distance_to(target),.55))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("window_shaft", true)
	mi.set_meta("window_projector", index)
	arena._sanctuary_shafts.append(mi)

static var SHAFT_SHADER: Shader = _shaft_shader()
static func _shaft_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color;
void fragment() {
	float side=pow(abs(dot(normalize(NORMAL),normalize(VIEW))),2.1);
	float ends=smoothstep(0.0,.18,UV.y)*(1.0-smoothstep(.55,1.0,UV.y));
	float streak=.75+.25*sin(UV.x*32.0);
	ALBEDO=tint.rgb;
	ALPHA=side*ends*streak*.022;
}
"""
	return shader
