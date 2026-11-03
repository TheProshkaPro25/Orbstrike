extends RefCounted
## Закрытая ротонда: архитектура построена вокруг свободного игрового круга.
const RADIUS := 106.0
const WALL_TOP := 65.0
const CROWN := 108.0
const BAYS := 24
const Icon := preload("res://scenes/element_icon.gd")

static func build(arena: Node3D) -> void:
	var stone := _material(Color(.19, .25, .29), .82)
	var recess := _material(Color(.035, .065, .09), .9)
	var ivory := _material(Color(.45, .47, .41), .7)
	var bronze := _material(Color(.49, .31, .105), .38, .48)
	var dark_gold := _material(Color(.16, .105, .05), .5, .65)
	var light: Material = arena._glow_mat(Color(.65, .79, .9), .6)
	var box := BoxMesh.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 1.0
	shaft.bottom_radius = 1.08
	shaft.height = 1.0
	shaft.radial_segments = 20
	var rod := CylinderMesh.new()
	rod.top_radius = 1
	rod.bottom_radius = 1
	rod.height = 1
	rod.radial_segments = 8
	var aperture := _arch(14, 27, 8)
	var backing := _arch(18, 27, 10)
	# Сплошная оболочка стен. Все ниши и проёмы закрыты стеклом или дверью.
	for i in BAYS:
		var angle := TAU * i / BAYS
		var center := Vector3(cos(angle) * RADIUS, 0, sin(angle) * RADIUS)
		var yaw := -angle - PI * .5
		var width := 2 * RADIUS * tan(PI / BAYS) + .2
		_piece(arena, box, stone, center, yaw, Vector3(0, WALL_TOP * .5, -2), Vector3(width, WALL_TOP, 4))
		var wall := StaticBody3D.new()
		wall.position = center
		wall.rotation.y = yaw
		var shape := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = Vector3(width, WALL_TOP, 4)
		shape.shape = bounds
		shape.position = Vector3(0, WALL_TOP * .5, -2)
		wall.add_child(shape)
		arena._decor.add_child(wall)
		for molding in [[2.0, 3.8, 3.2], [9.0, 1.0, 1.4], [59.0, 2.0, 2.8], [63.0, 4.0, 6.0]]:
			_piece(arena, box, ivory if molding[0] < 4 else bronze, center, yaw,
				Vector3(0, molding[0], .4), Vector3(width + .4, molding[1], molding[2]))
		# Неглубокие нижние кессоны вместо пустой стены.
		_piece(arena, box, recess, center, yaw, Vector3(0, 9, .2), Vector3(19, 10, .6))
		for x in [-9.7, 9.7]:
			_piece(arena, box, dark_gold, center, yaw, Vector3(x, 9, .65), Vector3(.22, 9.5, .3))
		for y in [4.3, 13.7]:
			_piece(arena, box, dark_gold, center, yaw, Vector3(0, y, .65), Vector3(19.5, .22, .3))
		if i == 18:
			_door(arena, center, yaw, box, rod, recess, bronze, ivory)
		else:
			_piece(arena, backing, recess, center, yaw, Vector3(0, 18, .3), Vector3.ONE)
			var color := Color(.32, .51, .64)
			if i % 4 == 0: color = VisualUtil.attr_color(i / 4).lerp(Color(.7, .8, .85), .25)
			_piece(arena, aperture, _glass(color), center, yaw, Vector3(0, 19, .55), Vector3.ONE)
			_arch_trim(arena, center, yaw, rod, bronze, 15, 27, 8.7, 18.5)
			# Высокие каменные импосты, тонкие металлические переплёты.
			for x in [-3.7, 0.0, 3.7]:
				_piece(arena, box, bronze, center, yaw, Vector3(x, 32, .85), Vector3(.16, 25, .25))
			_piece(arena, box, bronze, center, yaw, Vector3(0, 38, .85), Vector3(14, .18, .25))
		# Пучки колонн между пролётами с общей базой и развитой капителью.
		var edge_angle := angle + PI / BAYS
		var p := Vector3(cos(edge_angle) * 101, 0, sin(edge_angle) * 101)
		var eyaw := -edge_angle - PI * .5
		_piece(arena, box, ivory, p, eyaw, Vector3(0, 1.5, 0), Vector3(6.2, 3, 5.8))
		for x in [-1.5, 0.0, 1.5]:
			_piece(arena, shaft, ivory, p, eyaw, Vector3(x, 29, 0 if x != 0 else 1), Vector3(.75 if x != 0 else 1.15, 52, .75 if x != 0 else 1.15))
		for y in [4.0, 53.8, 56.0]:
			_piece(arena, box, bronze if y < 55 else ivory, p, eyaw, Vector3(0, y, 0), Vector3(5.6, .6 if y < 55 else 2.5, 5.4))
		# Парные светильники, встроенные в архитектуру, а не висящие таблички.
		for x in [-10.5, 10.5]:
			_piece(arena, box, bronze, center, yaw, Vector3(x, 16, 1.5), Vector3(1.2, 4.2, 1.3))
			_piece(arena, box, light, center, yaw, Vector3(x, 16.4, 2.2), Vector3(.48, 2.2, .2))
	# Замкнутый свод, ребра и пояса: камера всегда находится под его поверхностью.
	var vault_mat := _material(Color(.045, .08, .125), .86)
	vault_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arena._mi(_vault(), vault_mat, Vector3.ZERO)
	for i in BAYS:
		var angle := TAU * (i + .5) / BAYS
		for k in 14:
			var a := _vault_point(angle, (PI * .5) * k / 14.0)
			var b := _vault_point(angle, (PI * .5) * (k + 1) / 14.0)
			_beam(arena, rod, bronze, a - Vector3.UP * .3, b - Vector3.UP * .3, .28)
	for latitude in [.18, .42, .68, .91, 1.27]:
		_ring(arena, bronze, cos(latitude) * RADIUS, WALL_TOP + sin(latitude) * (CROWN - WALL_TOP) - .5, .3)
	# Звёздчатые бронзовые розетки в каждом кессоне, ориентированы по своду.
	var rosette := _rosette()
	var rosette_mat := bronze.duplicate() as StandardMaterial3D
	rosette_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for latitude in [.29, .56, .85, 1.13]:
		for i in BAYS:
			var angle := TAU * i / BAYS
			var p := _vault_point(angle, latitude) - Vector3.UP * .65
			var normal := -Vector3(p.x / pow(RADIUS,2), (p.y - WALL_TOP) / pow(CROWN - WALL_TOP,2), p.z / pow(RADIUS,2)).normalized()
			var rotation := Basis(Quaternion(Vector3.UP, normal)).get_euler()
			arena._static(rosette, rosette_mat, p, Vector3.ONE * 2.2, rotation)
	# Резная розетка под вершиной купола и подвесной венец света.
	_ring(arena, bronze, 13, 104.5, .9)
	var oculus := CylinderMesh.new()
	oculus.top_radius = 12
	oculus.bottom_radius = 12
	oculus.height = .3
	oculus.radial_segments = 64
	arena._mi(oculus, arena._glow_mat(Color(.25, .5, .65), .7), Vector3(0, 104.3, 0))
	_ring(arena, bronze, 15, 58, .45)
	_ring(arena, dark_gold, 14, 56.5, .4)
	for i in 12:
		var angle := TAU * i / 12.0
		var p := Vector3(cos(angle) * 15, 58, sin(angle) * 15)
		_beam(arena, rod, bronze, p, Vector3(p.x * .45, 103, p.z * .45), .10)
		arena._static(box, light, p - Vector3.UP * 1.0, Vector3(.4, 1.6, .4), Vector3.ZERO)
	# Шесть настенных святилищ: символы вписаны в камень и металлическую оправу.
	for el in 6:
		_shrine(arena, el, box, shaft, rod, ivory, bronze, recess)
	for radius in [52.0, 55.0, 79.0, 96.0]:
		_ring(arena, bronze, radius, .025, .10)
	# Отражённый свет большого зала, без отдельных теневых карт на каждом алтаре.
	for i in 6:
		var angle := TAU * i / 6.0
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(cos(angle) * 69, 30, sin(angle) * 69)
		lamp.light_color = Color(.6, .73, .85).lerp(VisualUtil.attr_color(i), .13)
		lamp.light_energy = .85
		lamp.omni_range = 58
		lamp.omni_attenuation = 1.1
		lamp.shadow_enabled = false
		arena._decor.add_child(lamp)
		arena._crystal_lights.append(lamp)
	_lighting(arena)
	arena._decor.set_meta("closed_sanctuary", true)
	arena._decor.set_meta("interior_radius", RADIUS)

static func _material(color: Color, roughness: float, metal: float = .05) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metal
	return material

static func _piece(arena: Node3D, mesh: Mesh, mat: Material, center: Vector3, yaw: float, p: Vector3, scale: Vector3, local_rotation: Vector3 = Vector3.ZERO) -> void:
	var basis := Basis(Vector3.UP, yaw)
	arena._static(mesh, mat, center + basis * p, scale, (basis * Basis.from_euler(local_rotation)).get_euler())

static func _beam(arena: Node3D, mesh: Mesh, mat: Material, a: Vector3, b: Vector3, radius: float) -> void:
	var delta := b - a
	if delta.length() < .001: return
	var rotation := Basis(Quaternion(Vector3.UP, delta.normalized())).get_euler()
	arena._static(mesh, mat, (a + b) * .5, Vector3(radius, delta.length(), radius), rotation)

static func _ring(arena: Node3D, mat: Material, radius: float, y: float, tube: float) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = radius - tube
	ring.outer_radius = radius + tube
	ring.rings = 96
	ring.ring_segments = 8
	arena._mi(ring, mat, Vector3(0, y, 0))

static func _arch(width: float, stem: float, rise: float) -> ArrayMesh:
	var points: Array[Vector2] = [Vector2(-width * .5, 0), Vector2(width * .5, 0)]
	for i in 25:
		var t := PI * i / 24.0
		points.append(Vector2(cos(t) * width * .5, stem + sin(t) * rise))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, points.size() - 1):
		for v in [points[0], points[i], points[i + 1]]:
			st.set_normal(Vector3(0, 0, 1))
			st.set_uv(Vector2(v.x / width + .5, v.y / (stem + rise)))
			st.add_vertex(Vector3(v.x, v.y, 0))
	return st.commit()

static func _arch_trim(arena: Node3D, center: Vector3, yaw: float, rod: Mesh, mat: Material, width: float, stem: float, rise: float, base: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	for side in [-1.0, 1.0]:
		_beam(arena, rod, mat, center + basis * Vector3(side * width * .5, base, 1), center + basis * Vector3(side * width * .5, base + stem, 1), .3)
	for i in 24:
		var t := PI * i / 24.0
		var t2 := PI * (i + 1) / 24.0
		_beam(arena, rod, mat, center + basis * Vector3(cos(t) * width * .5, base + stem + sin(t) * rise, 1), center + basis * Vector3(cos(t2) * width * .5, base + stem + sin(t2) * rise, 1), .3)

static func _vault_point(angle: float, latitude: float) -> Vector3:
	return Vector3(cos(angle) * RADIUS * cos(latitude), WALL_TOP + sin(latitude) * (CROWN - WALL_TOP), sin(angle) * RADIUS * cos(latitude))

static func _vault() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in 20:
		for x in 96:
			var a := TAU * x / 96.0
			var b := TAU * (x + 1) / 96.0
			var t := PI * .5 * y / 20.0
			var u := PI * .5 * (y + 1) / 20.0
			for p in [_vault_point(a,t), _vault_point(b,t), _vault_point(a,u), _vault_point(b,t), _vault_point(b,u), _vault_point(a,u)]:
				st.set_normal(-Vector3(p.x / (RADIUS * RADIUS), (p.y - WALL_TOP) / pow(CROWN - WALL_TOP, 2), p.z / (RADIUS * RADIUS)).normalized())
				st.add_vertex(p)
	return st.commit()

static func _door(arena: Node3D, center: Vector3, yaw: float, box: Mesh, rod: Mesh, dark: Material, gold: Material, stone: Material) -> void:
	_piece(arena, box, dark, center, yaw, Vector3(0, 24, 1), Vector3(20, 45, 1))
	for side in [-1.0, 1.0]:
		_piece(arena, box, gold, center, yaw, Vector3(side * 5.4, 22, 1.7), Vector3(10.4, 42, .7))
		for y in [10.0, 22.0, 34.0]:
			_piece(arena, box, dark, center, yaw, Vector3(side * 5.4, y, 2.2), Vector3(7.5, 9.5, .6))
			_piece(arena, box, stone, center, yaw, Vector3(side * 5.4, y, 2.6), Vector3(3.7, 3.7, .3), Vector3(0, 0, PI * .25))
	_arch_trim(arena, center, yaw, rod, stone, 23, 43, 10, 1)
	_arch_trim(arena, center, yaw, rod, gold, 25, 43, 11, 1)

static func _shrine(arena: Node3D, el: int, box: Mesh, shaft: Mesh, rod: Mesh, stone: Material, gold: Material, dark: Material) -> void:
	var angle := TAU * el / 6.0
	var center := Vector3(cos(angle) * 91, 0, sin(angle) * 91)
	var yaw := -angle - PI * .5
	var color := VisualUtil.attr_color(el).lightened(.12)
	var glow: Material = arena._glow_mat(color, .65)
	for step in 3:
		_piece(arena, box, stone, center, yaw, Vector3(0, .4 + step * .7, 0), Vector3(17 - step * 1.8, .7, 12 - step * 1.4))
	_piece(arena, box, dark, center, yaw, Vector3(0, 4.5, 0), Vector3(10, 4, 6))
	_piece(arena, box, gold, center, yaw, Vector3(0, 6.8, 0), Vector3(11.2, .6, 7))
	_piece(arena, box, stone, center, yaw, Vector3(0, 17, -2), Vector3(10, 19, 2))
	_piece(arena, box, gold, center, yaw, Vector3(0, 19, -.7), Vector3(6.8, 6.8, .3), Vector3(0, 0, PI * .25))
	_piece(arena, box, dark, center, yaw, Vector3(0, 19, -.45), Vector3(5.9, 5.9, .3), Vector3(0, 0, PI * .25))
	var glyph := Sprite3D.new()
	glyph.texture = Icon.glyph(el)
	glyph.modulate = color
	glyph.pixel_size = .043
	glyph.position = center + Basis(Vector3.UP, yaw) * Vector3(0, 19, -.1)
	glyph.rotation.y = yaw
	arena._decor.add_child(glyph)
	# Невысокая реликвия в оправе: вытянутый октаэдр с металлическими рёбрами.
	var gem := SphereMesh.new()
	gem.radius = 1.2
	gem.height = 4.8
	gem.radial_segments = 6
	gem.rings = 2
	_piece(arena, gem, glow, center, yaw, Vector3(0, 9.7, 1), Vector3.ONE)
	for x in [-1.7, 1.7]:
		_piece(arena, shaft, gold, center, yaw, Vector3(x, 8.6, 1), Vector3(.16, 3.6, .16))

static func _glass(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLASS_SHADER
	material.set_shader_parameter("tint", color)
	return material

static var GLASS_SHADER: Shader = _glass_shader()
static func _glass_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 tint : source_color;
void fragment() {
	vec2 p = UV * vec2(5.0, 11.0);
	vec2 cell = abs(fract(vec2(p.x + p.y * .5, p.x - p.y * .5)) - .5);
	float lead = smoothstep(.008, .020, min(cell.x, cell.y));
	vec2 rose = (UV - vec2(.5,.79)) * vec2(1.0,2.5);
	float r = length(rose);
	float angle = atan(rose.y, rose.x);
	float petals = smoothstep(.015,.03,abs(sin(angle * 6.0))) * smoothstep(.012,.025,abs(r - .16));
	float rose_mask = 1.0 - smoothstep(.21,.23,r);
	vec3 stained = mix(tint.rgb * .5, tint.rgb * 1.25, .5 + .5 * sin(p.y * 1.7 + p.x * 1.2));
	stained = mix(stained, tint.rgb * 1.3 * petals, rose_mask);
	ALBEDO = mix(vec3(.018,.027,.035), stained, lead) * .55;
	EMISSION = stained * lead * .48;
}
"""
	return shader


static func _rosette() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 16:
		var a := TAU * i / 16.0
		var b := TAU * (i + 1) / 16.0
		var ra := 1.0 if i % 2 == 0 else .32
		var rb := 1.0 if (i + 1) % 2 == 0 else .32
		for v in [Vector3.ZERO, Vector3(cos(b)*rb,0,sin(b)*rb), Vector3(cos(a)*ra,0,sin(a)*ra)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


static func _lighting(arena: Node3D) -> void:
	preload("res://scenes/sanctuary_window_light.gd").build(arena)
	var moon := SpotLight3D.new()
	arena._decor.add_child(moon)
	moon.position = Vector3(0,98,0)
	moon.look_at(Vector3.ZERO, Vector3.FORWARD)
	moon.light_color = Color(.7,.82,1)
	moon.light_energy = 48
	moon.spot_angle = 31
	moon.spot_range = 155
	moon.spot_attenuation = 1.3
	moon.set_meta("moon_shadow", true)
	arena._sanctuary_lights.append(moon)
	# Тёплые пулы на камне отделены от холодного света поля.
	for el in 6:
		var a := TAU * el / 6.0
		var fire := OmniLight3D.new()
		fire.position = Vector3(cos(a) * 86, 12, sin(a) * 86)
		fire.light_color = Color(1.0,.58,.24)
		fire.light_energy = 8.0
		fire.omni_range = 24
		fire.omni_attenuation = 1.15
		fire.light_volumetric_fog_energy = .25
		arena._decor.add_child(fire)
		arena._sanctuary_lights.append(fire)
	# Малый заполняющий свет венца не бросает тень на игровое поле.
	var chandelier := OmniLight3D.new()
	chandelier.position = Vector3(0,54,0)
	chandelier.light_color = Color(1.0,.78,.48)
	chandelier.light_energy = 1.8
	chandelier.omni_range = 64
	chandelier.light_volumetric_fog_energy = .15
	arena._decor.add_child(chandelier)
	arena._sanctuary_lights.append(chandelier)

