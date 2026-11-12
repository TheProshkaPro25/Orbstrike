class_name BallFx
extends RefCounted
## Эффекты сферы существа: частицы стихий (след полёта, качение, раскрытие, нокаут), вспышки, кольцо
## ускорения броска, знак стихии на карте, короткая подсветка. Все материалы, меши, градиенты — в статическом
## кэше (общие для всех шаров); частиц — по уровню графики (GraphicsSettings: Низкие ×0.35, Средние ×0.7).
## Источник света — только OmniLight3D без теней, один на эффект, на доли секунды и не на «Низких».

const FLASH_SHADER: Shader = preload("res://scenes/shaders/fx_flash.gdshader")
const SIGIL_SHADER: Shader = preload("res://scenes/shaders/fx_sigil.gdshader")
const KENNEY_SPARK := preload("res://assets/vfx_vendor/kenney/spark_05.png")
const KENNEY_FLARE := preload("res://assets/vfx_vendor/kenney/flare_01.png")

## Стихии (порядок VisualUtil.ATTR_NAMES).
enum { FIRE, STORM, LIGHT, STONE, SHADOW, TIDE }

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}
static var _grads: Dictionary = {}
static var _tex: Dictionary = {}
static var _flash_mat: ShaderMaterial
static var _sigil_mat: ShaderMaterial
static var _quad1: QuadMesh
static var _plane1: PlaneMesh
static var _torus: TorusMesh


## Множитель числа частиц по уровню графики.
static func level_k() -> float:
	match GraphicsSettings.current():
		GraphicsSettings.Level.LOW:
			return 0.35
		GraphicsSettings.Level.MEDIUM:
			return 0.7
	return 1.0


static func _n(base: int) -> int:
	return maxi(2, int(round(base * level_k())))


## Яркий цвет стихии для света и частиц (цвета существ в VisualUtil приглушённые).
static func elem_color(el: int) -> Color:
	match el:
		FIRE: return Color(1.0, 0.45, 0.12)
		STORM: return Color(0.35, 0.95, 0.78)
		LIGHT: return Color(1.0, 0.86, 0.45)
		STONE: return Color(0.95, 0.62, 0.3)
		SHADOW: return Color(0.62, 0.32, 1.0)
		TIDE: return Color(0.3, 0.68, 1.0)
	return Color(0.9, 0.9, 0.9)


# ------------------------------------------------------------------ текстуры

## Четырёхлучевая блёстка (Свет).
static func _sparkle() -> Texture2D:
	if not _tex.has("sparkle"):
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var u := (x + 0.5) / n * 2.0 - 1.0
				var v := (y + 0.5) / n * 2.0 - 1.0
				var r := sqrt(u * u + v * v)
				var a := maxf(pow(maxf(0.0, 1.0 - absf(u) * 9.0), 2.0) * (1.0 - absf(v)), pow(maxf(0.0, 1.0 - absf(v) * 9.0), 2.0) * (1.0 - absf(u)))
				a = maxf(a, pow(maxf(0.0, 1.0 - r * 2.2), 2.0))
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
		_tex["sparkle"] = ImageTexture.create_from_image(img)
	return _tex["sparkle"]


## Клуб дыма с рваным краем (Тень, пыль).
static func _puff() -> Texture2D:
	if not _tex.has("puff"):
		var n := 64
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.frequency = 0.09
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var u := (x + 0.5) / n * 2.0 - 1.0
				var v := (y + 0.5) / n * 2.0 - 1.0
				var r := sqrt(u * u + v * v)
				var a := clampf(1.0 - r, 0.0, 1.0)
				a = clampf(a * (0.7 + 0.8 * noise.get_noise_2d(x, y)) * 1.6, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a))
		_tex["puff"] = ImageTexture.create_from_image(img)
	return _tex["puff"]


## Удлинённая искра (Пламя, Буря).
static func _streak_tex() -> Texture2D:
	if not _tex.has("streak"):
		var n := 32
		var img := Image.create(n, n * 2, false, Image.FORMAT_RGBA8)
		for y in n * 2:
			for x in n:
				var u := (x + 0.5) / n * 2.0 - 1.0
				var v := (y + 0.5) / (n * 2) * 2.0 - 1.0
				var a := pow(maxf(0.0, 1.0 - absf(u)), 3.0) * pow(maxf(0.0, 1.0 - absf(v)), 1.5)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_tex["streak"] = ImageTexture.create_from_image(img)
	return _tex["streak"]


## Painted soft volume, not a new light or a volumetric renderer.
static func _wind_cloud() -> Texture2D:
	if not _tex.has("wind_cloud"):
		var image := _puff().get_image()
		for y in 64:
			for x in 64:
				var u := (x+.5)/32.0-1.0
				var v := (y+.5)/32.0-1.0
				var z := sqrt(maxf(0.0,1.0-u*u-v*v))
				var shade := .48+.52*clampf(-.3*u-.5*v+.8*z,0.0,1.0)
				image.set_pixel(x,y,Color(shade,shade,shade,image.get_pixel(x,y).a))
		_tex["wind_cloud"] = ImageTexture.create_from_image(image)
	return _tex["wind_cloud"]


static func _shadow_cloud() -> Texture2D:
	if not _tex.has("shadow_cloud"):
		var image := _puff().get_image()
		for y in 64:
			for x in 64:
				var a := image.get_pixel(x,y).a
				var rim := smoothstep(.015,.07,a)*(1.0-smoothstep(.15,.35,a))
				var color := Color(.035,.012,.07).lerp(Color(.65,.12,1.0),rim)
				image.set_pixel(x,y,Color(color,maxf(a*.8,rim*.45)))
		_tex["shadow_cloud"] = ImageTexture.create_from_image(image)
	return _tex["shadow_cloud"]


## Directed points in the figure-sized volume; +Z is the normal axis of this API.
static func _open_volume(p: CPUParticles3D, el: int, s: float) -> void:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	for level in 3:
		for i in 12:
			var a := TAU*float(i)/12.0+level*.23
			var outward := Vector3(cos(a),0,sin(a))
			var radius := .8 if el == STORM else .65+level*.08
			var height := .8+level*(.9 if el == STORM else .7)
			points.append((outward*radius+Vector3.UP*height)*s)
			var rise := .12 if el == STORM else .65
			if el == FIRE: rise = .45
			elif el == STONE: rise = .75
			elif el == SHADOW: rise = .8
			normals.append((outward+Vector3.UP*rise).normalized())
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
	p.emission_points = points
	p.emission_normals = normals
	p.direction = Vector3.BACK


# ------------------------------------------------------------------ материалы и меши частиц

## Материал частиц: add — аддитивный, alpha — обычная прозрачность (дым, пыль), shard — освещённый осколок.
static func _mat(kind: String, tex: String) -> Material:
	var key := kind + ":" + tex
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	if kind == "water":
		m.roughness = .2
		m.metallic_specular = .8
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color(.005,.012,.028) # Small blue floor, not a white additive glow.
	elif kind == "shard" or kind == "rock":
		m.roughness = .85 if kind == "rock" else .8
		if kind == "rock":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.emission_enabled = true
			m.emission = Color(.018,.012,.006)
	else:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.disable_receive_shadows = true
		if kind in ["add", "open_add"]:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			if kind == "open_add": m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(1.6, 1.6, 1.6)
		else:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		match tex:
			"sparkle": m.albedo_texture = _sparkle()
			"puff": m.albedo_texture = _puff()
			"wind_cloud": m.albedo_texture = _wind_cloud()
			"shadow_cloud": m.albedo_texture = _shadow_cloud()
			"streak": m.albedo_texture = _streak_tex()
			"kenney_spark": m.albedo_texture = KENNEY_SPARK
			"kenney_flare": m.albedo_texture = KENNEY_FLARE
			_: m.albedo_texture = VisualUtil.soft_dot()
	_mats[key] = m
	return m


## Меш частицы (общий): квад заданного размера с материалом, для осколков — коробочка.
static func _mesh(kind: String, tex: String, size: Vector2) -> Mesh:
	var key := "%s:%s:%.3f:%.3f" % [kind, tex, size.x, size.y]
	if _meshes.has(key):
		return _meshes[key]
	if kind == "water":
		var drop := _water_mesh(size)
		drop.surface_set_material(0,_mat(kind,tex))
		_meshes[key] = drop
		return drop
	if kind == "rock":
		var rock := _rock_mesh(size)
		rock.surface_set_material(0,_mat(kind,tex))
		_meshes[key] = rock
		return rock
	var m: PrimitiveMesh
	if kind == "shard":
		var b := BoxMesh.new()
		b.size = Vector3(size.x, size.y, size.x * 0.6)
		m = b
	else:
		var q := QuadMesh.new()
		q.size = size
		m = q
	m.material = _mat(kind, tex)
	_meshes[key] = m
	return m


## Six irregular corners, eight flat faces. No model asset or per-particle mesh build.
static func _rock_mesh(size: Vector2) -> ArrayMesh:
	var points := [Vector3(.11,.57,-.08),Vector3(-.13,-.42,.12),Vector3(.53,-.03,.08),Vector3(-.06,-.07,.46),Vector3(-.48,.10,-.04),Vector3(.02,.06,-.52)]
	var scale := Vector3(size.x,size.y,size.x*.85)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var current := 2+i
		var next := 2+(i+1)%4
		for face in [[0,current,next],[1,next,current]]:
			var a: Vector3=points[face[0]]*scale
			var b: Vector3=points[face[1]]*scale
			var c: Vector3=points[face[2]]*scale
			st.set_normal((c-a).cross(b-a).normalized()) # Godot clockwise front faces.
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
	return st.commit()


## 8 meridians x 6 rings; a rounded +Y nose and tapered -Y wake.
static func _water_mesh(size: Vector2) -> ArrayMesh:
	var ys := [-1.0,-.55,0.0,.35,.6,.75]
	var rs := [0.0,.2,.42,.5,.35,0.0]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for j in 6:
		for i in 8:
			var a := TAU*float(i)/8.0
			vertices.append(Vector3(cos(a)*rs[j]*size.x,ys[j]*size.y/1.75,sin(a)*rs[j]*size.x))
			var low := maxi(0,j-1)
			var high := mini(5,j+1)
			var dy: float=(ys[high]-ys[low])*size.y/1.75
			var dr: float=(rs[high]-rs[low])*size.x
			normals.append(Vector3.DOWN if j == 0 else (Vector3.UP if j == 5 else Vector3(cos(a)*dy,-dr,sin(a)*dy).normalized()))
	for j in 5:
		for i in 8:
			var a:=j*8+i
			var b:=j*8+(i+1)%8
			var c:=b+8
			var d:=a+8
			if j > 0: indices.append_array(PackedInt32Array([a,b,c]))
			if j < 4: indices.append_array(PackedInt32Array([a,c,d]))
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh


static func _grad(key: String, stops: Array) -> Gradient:
	if _grads.has(key):
		return _grads[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for s in stops:
		g.add_point(float(s[0]), s[1])
	_grads[key] = g
	return g


static func _curve_grow() -> Curve:
	if not _grads.has("curve_grow"):
		var c := Curve.new()
		c.add_point(Vector2(0.0, 0.4))
		c.add_point(Vector2(1.0, 1.6))
		_grads["curve_grow"] = c
	return _grads["curve_grow"]


static func _curve_shrink() -> Curve:
	if not _grads.has("curve_shrink"):
		var c := Curve.new()
		c.add_point(Vector2(0.0, 1.0))
		c.add_point(Vector2(1.0, 0.1))
		_grads["curve_shrink"] = c
	return _grads["curve_shrink"]


## Частицы стихии. role: trail — хвост полёта, roll — от контакта с полом при качении,
## open — вихрь раскрытия, burst — разлёт (нокаут, захлопывание). s — размер шара (м).
static func particles(el: int, role: String, s: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var c := elem_color(el)
	var hot := c.lightened(0.55)
	var clear := Color(c.r, c.g, c.b, 0.0)
	p.local_coords = false
	p.emitting = false
	p.draw_order = CPUParticles3D.DRAW_ORDER_INDEX
	var tex := "dot"
	var kind := "add"
	var size := Vector2(0.18, 0.18) * s
	var ramp := _grad("def%d" % el, [[0.0, Color(1, 1, 1, 1)], [0.3, hot], [1.0, clear]])
	match el:
		FIRE:  # искры и угли: летят вверх, мерцают
			tex = "streak"
			size = Vector2(0.09, 0.2) * s
			ramp = _grad("fire", [[0.0, Color(1, 0.95, 0.7, 1)], [0.35, Color(1, 0.55, 0.15, 1)], [0.75, Color(0.8, 0.15, 0.05, 0.8)], [1.0, Color(0.3, 0.05, 0, 0)]])
			p.gravity = Vector3(0, 2.5 * s, 0)
		STORM:  # завихрения
			tex = "streak"
			size = Vector2(0.06, 0.24) * s
			ramp = _grad("storm", [[0.0, Color(0.9, 1, 1, 0)], [0.2, Color(0.75, 1, 0.95, 1)], [1.0, Color(0.3, 0.9, 0.75, 0)]])
			p.gravity = Vector3.ZERO
			p.tangential_accel_min = 6.0 * s
			p.tangential_accel_max = 12.0 * s
		LIGHT:  # блёстки
			tex = "sparkle"
			size = Vector2(0.2, 0.2) * s
			ramp = _grad("light", [[0.0, Color(1, 1, 1, 1)], [0.25, Color(1, 0.9, 0.5, 0.3)], [0.45, Color(1, 0.95, 0.7, 1)], [0.7, Color(1, 0.85, 0.4, 0.2)], [1.0, Color(1, 0.8, 0.3, 0)]])
			p.gravity = Vector3(0, 0.3 * s, 0)
		STONE:  # осколки
			kind = "shard"
			tex = ""
			size = Vector2(0.09, 0.07) * s
			ramp = _grad("stone", [[0.0, Color(0.55, 0.48, 0.4, 1)], [0.8, Color(0.4, 0.34, 0.28, 1)], [1.0, Color(0.3, 0.26, 0.22, 1)]])
			p.gravity = Vector3(0, -18.0, 0)
			p.angular_velocity_min = -720.0
			p.angular_velocity_max = 720.0
			p.scale_amount_curve = _curve_shrink()
			p.particle_flag_rotate_y = true
		SHADOW:  # дымные хлопья
			kind = "alpha"
			tex = "puff"
			size = Vector2(0.4, 0.4) * s
			ramp = _grad("shadow", [[0.0, Color(0.35, 0.15, 0.55, 0)], [0.15, Color(0.22, 0.08, 0.35, 0.85)], [1.0, Color(0.05, 0.02, 0.08, 0)]])
			p.gravity = Vector3(0, 0.6 * s, 0)
			p.scale_amount_curve = _curve_grow()
		TIDE:  # брызги
			size = Vector2(0.12, 0.12) * s
			ramp = _grad("tide", [[0.0, Color(0.9, 0.97, 1, 1)], [0.4, Color(0.45, 0.75, 1, 0.9)], [1.0, Color(0.2, 0.5, 1, 0)]])
			p.gravity = Vector3(0, -14.0, 0)
	p.color_ramp = ramp
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.15
	match role:
		"trail":
			if el in [FIRE, STORM, LIGHT]:
				tex = "kenney_spark"
			p.amount = _n(26)
			p.lifetime = 0.55
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.45 * s
			p.direction = Vector3.UP
			p.spread = 180.0
			p.initial_velocity_min = 0.1 * s
			p.initial_velocity_max = 0.8 * s
			if el == TIDE or el == STONE:
				p.gravity *= 0.35
		"roll":
			if el == FIRE:
				tex = "kenney_flare"
			p.amount = _n(30)
			p.lifetime = 0.5
			p.direction = Vector3.UP
			p.spread = 50.0
			p.initial_velocity_min = 1.5 * s
			p.initial_velocity_max = 4.5 * s
			if el != STONE and el != TIDE:
				p.gravity += Vector3(0, -6.0 * s, 0)
		"open":
			p.amount = _n(36)
			p.lifetime = 0.9
			p.one_shot = true
			p.explosiveness = 0.55
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			p.emission_ring_axis = Vector3.UP
			p.emission_ring_radius = 1.2 * s
			p.emission_ring_inner_radius = 0.7 * s
			p.emission_ring_height = 0.1 * s
			p.direction = Vector3.UP
			p.spread = 12.0
			p.initial_velocity_min = 4.0 * s
			p.initial_velocity_max = 8.0 * s
			p.tangential_accel_min = 14.0 * s
			p.tangential_accel_max = 22.0 * s
			p.radial_accel_min = -3.0 * s
			p.radial_accel_max = 1.0 * s
			p.damping_min = 0.5 * s
			p.damping_max = 1.5 * s
			if el == STONE or el == TIDE:
				p.gravity = Vector3(0, -6.0 * s, 0)
			size *= 0.6  # частиц много и они крупного масштаба: мельче, чтобы вихрь не сливался в пятно
		"burst":
			p.amount = _n(36)
			p.lifetime = 0.8
			p.one_shot = true
			p.explosiveness = 0.95
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.6 * s
			p.direction = Vector3.UP
			p.spread = 180.0
			p.initial_velocity_min = 1.5 * s
			p.initial_velocity_max = 5.0 * s
			p.damping_min = 1.0 * s
			p.damping_max = 2.5 * s
	# Author's reveal language: outward wind clubs and blue water from the body.
	if role == "open" and el in [STORM,TIDE]:
		_open_volume(p,el,s)
		kind = "alpha"
		p.radial_accel_min = 0.0
		p.radial_accel_max = 0.0
		p.spread = 15.0
		if el == STORM:
			tex = "wind_cloud"
			size = Vector2(1.1,.8)*s
			p.color_ramp = _grad("storm_cloud",[[0.0,Color(.7,.85,.86,0)],[.12,Color(.8,.9,.9,.65)],[.65,Color(.6,.8,.78,.5)],[1.0,Color(.5,.7,.7,0)]])
			p.scale_amount_min = .65
			p.scale_amount_max = 1.25
			p.angle_min = -90.0
			p.angle_max = 90.0
			p.explosiveness = .85
			p.initial_velocity_min = 3.5*s
			p.initial_velocity_max = 4.5*s
			p.damping_min = 2.5*s
			p.damping_max = 4.0*s
			p.tangential_accel_min = 2.0*s
			p.tangential_accel_max = 4.0*s
		else:
			kind = "water"
			tex = "drop3d"
			size = Vector2(.4,.65)*s
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.color_ramp = _grad("tide_water",[[0.0,Color(.04,.28,.9,0)],[.08,Color(.06,.32,1,.95)],[.7,Color(.02,.2,.85,.9)],[1.0,Color(.01,.1,.5,0)]])
			p.scale_amount_min = .55
			p.scale_amount_max = 1.0
			p.particle_flag_align_y = true
			p.initial_velocity_min = 3.0*s
			p.initial_velocity_max = 5.0*s
			p.tangential_accel_min = 0.0
			p.tangential_accel_max = 0.0
			p.gravity = Vector3(0,-10.0*s,0)
	elif role == "open":
		_open_volume(p,el,s)
		p.radial_accel_min = 0.0
		p.radial_accel_max = 0.0
		p.tangential_accel_min = 0.0
		p.tangential_accel_max = 0.0
		if el == FIRE:
			p.amount = _n(72)
			size = Vector2(.035,.10)*s
			p.spread = 30.0
			p.initial_velocity_min = 3.5*s
			p.initial_velocity_max = 5.5*s
			p.gravity = Vector3.UP*.6*s
			p.angle_min = -180.0
			p.angle_max = 180.0
			p.explosiveness = .7
		elif el == LIGHT:
			p.color_ramp = _grad("light_open",[[0.0,Color(1,.95,.72,0)],[.1,Color(.95,.85,.5,.7)],[.7,Color(.9,.75,.35,.25)],[1.0,Color(.8,.65,.3,0)]])
			p.initial_velocity_min = 1.0*s
			p.initial_velocity_max = 2.0*s
			p.gravity = Vector3.UP*.1*s
		elif el == STONE:
			kind = "rock"
			size = Vector2(.32,.42)*s
			p.color_ramp = _grad("stone_open",[[0.0,Color(.65,.58,.46,0)],[.05,Color(.65,.58,.46,1)],[.75,Color(.42,.34,.26,1)],[1.0,Color(.3,.25,.2,0)]])
			p.initial_velocity_min = 2.5*s
			p.initial_velocity_max = 4.0*s
			p.gravity = Vector3(0,-12.0*s,0)
			p.angular_velocity_min = -420.0
			p.angular_velocity_max = 420.0
			p.angle_min = -180.0
			p.angle_max = 180.0
			p.scale_amount_curve = null
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif el == SHADOW:
			kind = "alpha"
			tex = "shadow_cloud"
			size = Vector2(.9,1.1)*s
			p.color_ramp = _grad("shadow_open",[[0.0,Color(1,1,1,0)],[.12,Color(.8,.8,1,.9)],[.7,Color(.65,.65,.9,.6)],[1.0,Color(.5,.5,.8,0)]])
			p.initial_velocity_min = .4*s
			p.initial_velocity_max = 1.0*s
			p.gravity = Vector3.UP*.3*s
			p.tangential_accel_min = 2.0*s
			p.tangential_accel_max = 4.0*s
			p.angle_min = -45.0
			p.angle_max = 45.0
			p.angular_velocity_min = -60.0
			p.angular_velocity_max = 60.0
	if role == "open" and kind == "add": kind = "open_add"
	p.mesh = _mesh(kind, tex, size)
	return p


## Одноразовые частицы в мире: сами удаляются.
static func one_shot(parent: Node, world_pos: Vector3, el: int, role: String, s: float) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var p := particles(el, role, s)
	parent.add_child(p)
	p.global_position = world_pos
	if el == TIDE and role == "open":
		# Bound to the emitter: early parent release cancels this delayed start too.
		p.create_tween().tween_interval(.18).finished.connect(_emit_one_shot.bind(p))
	else:
		_emit_one_shot(p)
	return p


static func _emit_one_shot(p: CPUParticles3D) -> void:
	if not is_instance_valid(p) or not p.is_inside_tree(): return
	p.restart()
	p.emitting = true
	p.get_tree().create_timer(p.lifetime + 0.4).timeout.connect(p.queue_free)


# ------------------------------------------------------------------ вспышки и кольца

static func _flash_material() -> ShaderMaterial:
	if _flash_mat == null:
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = FLASH_SHADER
	return _flash_mat


## Вспышка-ореол (билборд): раздувается до size и гаснет за dur секунд.
static func flash(parent: Node, world_pos: Vector3, c: Color, size: float, dur: float = 0.35) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _quad1 == null:
		_quad1 = QuadMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _quad1
	mi.material_override = _flash_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = world_pos
	mi.set_instance_shader_parameter("col", c)
	mi.set_instance_shader_parameter("mode", 0)
	mi.scale = Vector3.ONE * size * 0.3
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Кольцо ускорения: плоское кольцо поперёк направления dir, быстро расширяется (бросок).
static func speed_ring(parent: Node, world_pos: Vector3, dir: Vector3, c: Color, radius: float, dur: float = 0.3) -> void:
	if parent == null or not parent.is_inside_tree() or dir.length() < 0.01:
		return
	if _plane1 == null:
		_plane1 = PlaneMesh.new()
		_plane1.size = Vector2(2, 2)
	var mi := MeshInstance3D.new()
	mi.mesh = _plane1
	mi.material_override = _flash_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var y := dir.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var basis := Basis(x, y, x.cross(y))
	mi.global_transform = Transform3D(basis.scaled(Vector3.ONE * radius * 0.25), world_pos)
	mi.set_instance_shader_parameter("col", c)
	mi.set_instance_shader_parameter("mode", 1)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void:
		mi.global_transform = Transform3D(basis.scaled(Vector3.ONE * radius * v), world_pos + y * radius * (v - 0.25) * 0.6), 0.25, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)


## Знак стихии вспыхивает на карте (плоский квад на полу).
static func sigil_flash(parent: Node, floor_pos: Vector3, el: int, size: float, dur: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _sigil_mat == null:
		_sigil_mat = ShaderMaterial.new()
		_sigil_mat.shader = SIGIL_SHADER
	if _plane1 == null:
		_plane1 = PlaneMesh.new()
		_plane1.size = Vector2(2, 2)
	var mi := MeshInstance3D.new()
	mi.mesh = _plane1
	mi.material_override = _sigil_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = floor_pos
	mi.set_instance_shader_parameter("element", el)
	mi.set_instance_shader_parameter("col", elem_color(el))
	mi.scale = Vector3.ONE * size * 0.35
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 0.5, dur * 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "rotation:y", 0.6, dur)
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, dur * 0.6).set_delay(dur * 0.4)
	tw.chain().tween_callback(mi.queue_free)


## Короткая подсветка без теней (не на «Низких»): energy → 0 за dur.
static func light_flash(parent: Node, world_pos: Vector3, c: Color, energy: float, rng: float, dur: float = 0.4) -> void:
	if parent == null or not parent.is_inside_tree() or GraphicsSettings.current() == GraphicsSettings.Level.LOW:
		return
	var l := OmniLight3D.new()
	l.shadow_enabled = false
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.light_specular = 0.6
	parent.add_child(l)
	l.global_position = world_pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)
