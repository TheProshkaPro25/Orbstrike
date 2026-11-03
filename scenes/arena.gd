class_name Arena
extends Node3D
const Locations := preload("res://data/arena_locations.gd")
const Landscape := preload("res://scenes/arena_landscape.gd")
@export_range(0, 2) var location_id := 0
const ElementIcon := preload("res://scenes/element_icon.gd")
## Арена: бескрайнее поле боя (пол уходит за горизонт), 6 слотов ворот (сетка 2x3) в освещённом центре,
## дальние ориентиры для масштаба. Слоты 0..2 дальний ряд (z<0), 3..5 ближний.
## Карты крупные и портретные (как карты ворот): в бою на одной карте помещаются два существа
## по трети её длины с третью пустоты между ними.

## Масштаб мира относительно шара: карты и поле огромные, шар маленький (как в Бакуганах).
const WORLD := 3.5
## Масштаб существ на бескрайнем поле (существа 0.85–1.0 длины FIG_H).
const CARD_SCALE := 1.25
## Единица узоров зоны ворот (рисунок карт) и масштаба существ.
const UNIT := WORLD * CARD_SCALE
## Масштаб существ: прежний размер карты ворот. От него считаются модели (CreatureModels), эффекты шара
## и расстановка двух существ в бою — сферы и фигуры не растут вместе с картами.
const FIG_W := 2.5 * UNIT
const FIG_H := 3.5 * UNIT
## Карты ворот почти вдвое больше существ (по стороне): поле — огромные плиты, существа и сферы прежние.
const GATE_SCALE := 1.9
## Зона попадания = карта: прямоугольник CARD_W x CARD_H. Между картами просторно (~1.2·UNIT).
const CARD_W := FIG_W * GATE_SCALE
const CARD_H := FIG_H * GATE_SCALE
const GAP := 1.2 * UNIT
const STEP_X := CARD_W + GAP
const STEP_Z := CARD_H + GAP
## Единица узора пола (круг призыва, плиты, освещённая зона): раздвинута под крупную сетку ворот.
## Ближний край ворот (z ≈ 31.7) остаётся перед точкой броска main.THROW_Z.
const FIELD := UNIT * 1.8
## Размер освещённой зоны ворот (бывший пол-коробка): по нему считаются частицы и подсветка центра.
const FLOOR_SIZE := Vector3(13.4 * FIELD, 0.2, 13.6 * FIELD)
## Видимый пол: огромная плоскость, края тонут в тумане.
const GROUND_SIZE := 5000.0
## Физический пол и невидимый бортик далеко за слотами: промах укатывается в даль, но не бесконечно.
const PHYS_HALF := 130.0
const WALL_HEIGHT := 6.0

var _floor_mat: ShaderMaterial
var _wave_tw: Tween
var _decor: Node3D
## Парящие осколки: [узел, базовая высота, фаза, скорость вращения].
var _floaters: Array = []

var _motes: GPUParticles3D
var _crystal_lights: Array[OmniLight3D] = []
var _sanctuary_lights: Array[Light3D] = []
var _sanctuary_shafts: Array[MeshInstance3D] = []
var _floaters_on := true

signal slot_clicked(slot: int)
signal invalid_pick

var markers: Array[Marker3D] = []
## Силуэты мест под ворота (по слоту), видны только при выборе места.
var _highlights: Array[MeshInstance3D] = []
var _ghost_tw: Array = []
var _lit: Array = []
var _hover := -1
var _pick := false
var _built := false


func _ready() -> void:
	_build()


## Уровень графики (GraphicsSettings): число искр, подсветка кристаллов, движение парящих осколков.
func apply_quality() -> void:
	_build()
	var n: int = int(GraphicsSettings.param("motes"))
	if _motes != null and _motes.amount != n:
		_motes.amount = n
	for l in _crystal_lights:
		l.visible = bool(GraphicsSettings.param("lights"))
	var low := GraphicsSettings.current() == GraphicsSettings.Level.LOW
	var high := GraphicsSettings.current() == GraphicsSettings.Level.HIGH
	_floor_mat.set_shader_parameter("max_quality", 1.0 if high else 0.0)
	for l in _sanctuary_lights:
		l.visible = l is SpotLight3D or bool(GraphicsSettings.param("lights"))
		if l is SpotLight3D:
			if l.has_meta("window_projector"):
				l.visible = not low or int(l.get_meta("window_projector")) < 2
				l.shadow_enabled = true # Матрица проектора требует карту теней.
				l.shadow_caster_mask = 0 if low else 1
				l.shadow_bias = .018 if high else .03
				l.shadow_normal_bias = .18 if high else .35
				l.shadow_blur = 1.2 if high else .8
				l.light_size = .6 if high else 0.0
				preload("res://scenes/sanctuary_window_light.gd").apply_quality(l, high)
			else:
				l.shadow_enabled = bool(l.get_meta("moon_shadow", false)) and not low
				l.light_size = 1.2 if high else 0.0
	for shaft in _sanctuary_shafts:
		shaft.visible = not low or int(shaft.get_meta("window_projector", 0)) < 2
	_floaters_on = bool(GraphicsSettings.param("floaters"))
	set_process(_floaters_on and not _floaters.is_empty())


func _process(_delta: float) -> void:
	if _floaters.is_empty() or not _floaters_on:
		return
	var t := Time.get_ticks_msec() * 0.001
	for f in _floaters:
		var n: Node3D = f[0]
		n.position.y = float(f[1]) + sin(t * 0.35 + float(f[2])) * 2.5
		n.rotation.y = t * float(f[3]) + float(f[2])


func _build() -> void:
	if _built:
		return
	_built = true
	_decor = Node3D.new()
	_decor.name = "Decor"
	add_child(_decor)

	var mat := PhysicsMaterial.new()
	mat.friction = 0.6
	mat.bounce = 0.0

	# Физический пол (верх на y = 0) и невидимые стены за горизонтом слотов
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.physics_material_override = mat
	add_child(floor_body)
	var fcs := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(PHYS_HALF * 2.0 + 20.0, 1.0, PHYS_HALF * 2.0 + 20.0)
	fcs.shape = fshape
	fcs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fcs)
	for w in [[Vector3(PHYS_HALF * 2.0, WALL_HEIGHT, 2.0), Vector3(0, WALL_HEIGHT * 0.5, -PHYS_HALF)],
			[Vector3(PHYS_HALF * 2.0, WALL_HEIGHT, 2.0), Vector3(0, WALL_HEIGHT * 0.5, PHYS_HALF)],
			[Vector3(2.0, WALL_HEIGHT, PHYS_HALF * 2.0), Vector3(-PHYS_HALF, WALL_HEIGHT * 0.5, 0)],
			[Vector3(2.0, WALL_HEIGHT, PHYS_HALF * 2.0), Vector3(PHYS_HALF, WALL_HEIGHT * 0.5, 0)]]:
		var wcs := CollisionShape3D.new()
		var ws := BoxShape3D.new()
		ws.size = w[0]
		wcs.shape = ws
		wcs.position = w[1]
		floor_body.add_child(wcs)

	# Видимый пол до горизонта: линии силы, круг призыва в центре, туман к краям
	var fmesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	fmesh.mesh = plane
	var fsm := ShaderMaterial.new()
	fsm.shader = Shader.new()
	fsm.shader.code = FLOOR_SHADER
	fsm.set_shader_parameter("world", FIELD)
	var location := Locations.definition(location_id)
	fsm.set_shader_parameter("stone_color", Color(location.stone).linear_to_srgb())
	fsm.set_shader_parameter("far_color", Color(location.far).linear_to_srgb())
	fsm.set_shader_parameter("trim_color", Color(location.trim).linear_to_srgb())
	fsm.set_shader_parameter("location_style", location_id)
	_floor_mat = fsm
	fmesh.material_override = fsm
	fmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fmesh)

	# Маркеры слотов и скрытые места под ворота: пустые слоты не видны, контур-силуэт карты
	# проявляется только при выборе места (set_highlight) и ярче — под курсором (set_hover)
	for i in range(6):
		var m := Marker3D.new()
		m.name = "Slot%d" % i
		m.position = _local_slot_pos(i)
		add_child(m)
		markers.append(m)
		_highlights.append(_make_ghost(i, m.position))
	Landscape.build(self, location_id)
	_build_element_seals()
	_build_motes()


## Волна идёт по самой поверхности; карты, существа и интерфейс остаются читаемыми.
func element_wave(origin: Vector3, color: Color, strength: float = 1.0) -> void:
	if _wave_tw != null and _wave_tw.is_valid():
		_wave_tw.kill()
	_floor_mat.set_shader_parameter("wave_origin", Vector2(origin.x, origin.z))
	_floor_mat.set_shader_parameter("wave_color", color)
	_wave_tw = create_tween()
	_wave_tw.tween_method(func(t: float) -> void:
		_floor_mat.set_shader_parameter("wave_radius", t * 155.0)
		_floor_mat.set_shader_parameter("wave_strength", (1.0 - t) * strength), 0.0, 1.0, 1.8)


func _local_slot_pos(i: int) -> Vector3:
	var col: int = i % 3
	var row: int = floori(i / 3.0)
	return Vector3((col - 1) * STEP_X, 0.0, (row - 0.5) * STEP_Z)


## Мировая позиция центра слота (y = 0, уровень пола).
func slot_position(i: int) -> Vector3:
	if i < 0 or i > 5:
		return global_position
	if is_inside_tree():
		return to_global(_local_slot_pos(i))
	return position + _local_slot_pos(i)


## Слот, в чей прямоугольник (размер карты) попадает точка по XZ; иначе -1. y < -1 даёт -1.
func slot_at(world_pos: Vector3) -> int:
	if world_pos.y < -1.0:
		return -1
	var best := -1
	var best_d := INF
	for i in range(6):
		var c := slot_position(i)
		var dx := absf(world_pos.x - c.x)
		var dz := absf(world_pos.z - c.z)
		if dx <= CARD_W * 0.5 and dz <= CARD_H * 0.5:
			var d := dx * dx + dz * dz
			if d < best_d:
				best_d = d
				best = i
	return best


## Подсветить места slots (пустые — полупрозрачный светящийся силуэт карты, занятые — контур вокруг карты).
## pick — места выбираются мышью прямо на поле (наведение подсвечивает, щелчок → slot_clicked).
func set_highlight(slots: Array, pick: bool = false) -> void:
	_build()
	_lit = slots.duplicate()
	_pick = pick and not slots.is_empty()
	if not _lit.has(_hover):
		_hover = -1
	for i in range(_highlights.size()):
		_fade_ghost(i)


## Место под курсором (из панели выбора или мыши над полем): контур ярче. -1 — ни одного.
func set_hover(slot: int) -> void:
	_build()
	slot = slot if _lit.has(slot) else -1
	if slot == _hover:
		return
	_hover = slot
	for i in range(_highlights.size()):
		_fade_ghost(i)


## Видна ли подсветка места (для подсказок и снимков).
func is_highlighted(slot: int) -> bool:
	return _lit.has(slot)


func _fade_ghost(i: int) -> void:
	var g: MeshInstance3D = _highlights[i]
	var sm := g.material_override as ShaderMaterial
	var on: bool = _lit.has(i)
	var hv: float = 1.0 if i == _hover else 0.0
	if _ghost_tw.size() > i and _ghost_tw[i] != null and _ghost_tw[i].is_valid():
		_ghost_tw[i].kill()
	if on:
		g.visible = true
	if not is_inside_tree():
		_ghost_vis(1.0 if on else 0.0, g)
		sm.set_shader_parameter("hover", hv)
		g.visible = on
		return
	var vis0: Variant = sm.get_shader_parameter("vis")  # null, пока параметр ни разу не задан
	var hov0: Variant = sm.get_shader_parameter("hover")
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_ghost_vis.bind(g), float(vis0) if vis0 != null else 0.0, 1.0 if on else 0.0, 0.25 if on else 0.35)
	tw.tween_method(func(v: float) -> void: sm.set_shader_parameter("hover", v), float(hov0) if hov0 != null else 0.0, hv, 0.15)
	if not on:
		tw.chain().tween_callback(func() -> void: g.visible = _lit.has(i))
	while _ghost_tw.size() <= i:
		_ghost_tw.append(null)
	_ghost_tw[i] = tw


func _ghost_vis(v: float, g: MeshInstance3D) -> void:
	(g.material_override as ShaderMaterial).set_shader_parameter("vis", v)
	var n := g.get_child(0) as Label3D
	n.modulate.a = 0.45 * v


## Выбор места мышью прямо на поле, пока места подсвечены для выбора.
func _unhandled_input(event: InputEvent) -> void:
	if not _pick:
		return
	if event is InputEventMouseMotion:
		set_hover(_slot_under_mouse((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var s := _slot_under_mouse(mb.position)
			if _lit.has(s):
				get_viewport().set_input_as_handled()
				slot_clicked.emit(s)
			else:
				invalid_pick.emit()


## Подсвеченный слот под точкой экрана (луч камеры до пола), -1 — мимо.
func _slot_under_mouse(mp: Vector2) -> int:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return -1
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if absf(d.y) < 0.0001:
		return -1
	var t := (global_position.y - o.y) / d.y
	if t <= 0.0:
		return -1
	var s := slot_at(o + d * t)
	return s if _lit.has(s) else -1


# ------------------------------------------------------------ оформление

static var _noise_cache := {}


static func _noise_tex(freq: float, normal: bool, bump: float, ramp_lo: float, ramp_hi: float, ftype: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> NoiseTexture2D:
	var key := "%s%s%s%s%s%s" % [freq, normal, bump, ramp_lo, ramp_hi, ftype]
	if _noise_cache.has(key):
		return _noise_cache[key]
	var n := FastNoiseLite.new()
	n.noise_type = ftype
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 512
	t.height = 512
	t.seamless = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	else:
		var g := Gradient.new()
		g.set_color(0, Color(ramp_lo, ramp_lo, ramp_lo))
		g.set_color(1, Color(ramp_hi, ramp_hi, ramp_hi))
		t.color_ramp = g
	_noise_cache[key] = t
	return t


## Каменный материал: процедурный альбедо-шум + нормал-карта, триплпланар в мировых координатах.
static func _stone(tint: Color, rough: float = 0.8, scale: float = 0.6, bump: float = 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _noise_tex(0.012, false, 0.0, 0.35, 1.0, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	m.normal_enabled = true
	m.normal_texture = _noise_tex(0.03, true, 8.0 * bump, 0.0, 1.0)
	m.normal_scale = 1.2
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


## Пол до горизонта (координаты в единицах «поля» = мир / world): в центре — освещённая зона ворот
## с гравированным кругом призыва; от неё во все стороны расходятся линии силы (лучи и кольца),
## по которым бегут волны свечения. Мелкие детали и свечение гаснут с расстоянием, цвет уходит
## в цвет горизонта — края плоскости не видно (остальное прячет туман окружения).
const FLOOR_SHADER := """
shader_type spatial;
uniform float world = 7.875;
uniform vec4 stone_color : source_color = vec4(0.042, 0.064, 0.082, 1.0);
uniform vec4 far_color : source_color = vec4(0.023, 0.035, 0.052, 1.0);
uniform vec4 trim_color : source_color = vec4(0.45, 0.36, 0.21, 1.0);
uniform int location_style = 0;
uniform float max_quality = 0.0;
uniform vec2 wave_origin = vec2(0.0);
uniform vec4 wave_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float wave_radius = -20.0;
uniform float wave_strength = 0.0;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float line(float d, float w) { return 1.0 - smoothstep(w, w + max(fwidth(d), 0.001), abs(d)); }
vec3 element(float i) {
	if (i < 0.5) return vec3(0.95, 0.28, 0.10);
	if (i < 1.5) return vec3(0.20, 0.80, 0.65);
	if (i < 2.5) return vec3(1.0, 0.83, 0.38);
	if (i < 3.5) return vec3(0.72, 0.48, 0.24);
	if (i < 4.5) return vec3(0.64, 0.36, 0.85);
	return vec3(0.16, 0.57, 0.95);
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz / world;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float center = 1.0 - smoothstep(6.2, 8.8, r);
	vec2 tile = floor((p + 0.3) / 1.4);
	vec2 uv = abs(fract((p + 0.3) / 1.4) - 0.5);
	float seam = line(max(uv.x, uv.y) - 0.5, 0.005) * center;
	float grain = hash(tile) * 0.014;
	vec3 stone = mix(far_color.rgb, stone_color.rgb + grain * 0.4, center);
	stone *= 1.0 - seam * 0.30;
	float ring = line(r - 6.5, 0.025) + line(r - 6.68, 0.012) + line(r - 7.5, 0.025);
	float ticks = line(sin(angle * 48.0) * r, 0.026) * step(6.85, r) * step(r, 7.08);
	float sector = floor((angle + 3.141593) / 1.047198);
	vec3 accent = element(sector);
	float arcs = line(r - 7.2, 0.065) * smoothstep(0.1, 0.2, fract((angle + 3.141593) / 1.047198))
		* (1.0 - smoothstep(0.80, 0.90, fract((angle + 3.141593) / 1.047198)));
	// Небольшая центральная печать, свободная от карт.
	float seal = (line(r - 0.95, 0.016) + line(r - 1.15, 0.012)) * 0.35;
	float far = (line(r - 12.0, 0.018) + line(r - 18.0, 0.018)) * 0.10;
	vec3 brass = trim_color.rgb;
	float water = 0.0;
	float ripple = 0.0;
	if (location_style == 0) {
		float veins = pow(.5 + .5 * sin(wp.x * .19 + wp.z * .14 + sin(wp.z * .075) * 2.8), 16.0);
		stone = mix(far_color.rgb, stone_color.rgb * (.94 + hash(tile) * .10), center * .7 + .3);
		stone *= 1.0 - seam * .17 - veins * .045;
		float compass = line(length(wp.xz) - (10.0 + 2.4 * cos(angle * 8.0)), .07);
		compass += line(length(wp.xz) - 14.3, .08) + line(length(wp.xz) - 14.7, .035);
		stone = mix(stone, brass * .8, clamp(compass,0.0,1.0) * .8);
	}
	if (location_style == 2) {
		water = smoothstep(7.5, 8.1, r);
		ripple = pow(0.5 + 0.5 * sin(p.y * 2.4 + sin(p.x * 0.8 + TIME * 0.15) * 0.85 - TIME * 0.4), 18.0)
			* (0.3 + 0.7 * pow(0.5 + 0.5 * sin(p.x * 0.45 + p.y * .2), 2.0));
		ripple *= 1.0 - smoothstep(14.0, 55.0, r);
		stone = mix(stone, far_color.rgb + vec3(0.015, 0.035, 0.050) * ripple, water);
	}
	float d = length(wp.xz - wave_origin);
	float front = exp(-pow((d - wave_radius) / 2.6, 2.0)) * wave_strength;
	float wake = (1.0 - smoothstep(wave_radius - 9.0, wave_radius, d)) * exp(-abs(d - wave_radius) / 12.0) * wave_strength * 0.12;
	ALBEDO = stone + brass * (ring * 0.22 + seal + ticks * 0.15) + wave_color.rgb * (front * 0.18 + wake);
	EMISSION = brass * (ring * 0.25 + seal * 0.2 + ticks * 0.22 + far)
		+ accent * arcs * (0.95 + sin(TIME * 0.45) * 0.07) + wave_color.rgb * (front * 0.85 + wake) + vec3(0.018, 0.048, 0.065) * ripple * water;
	METALLIC = 0.25;
	ROUGHNESS = mix(mix(0.72, location_style == 0 ? 0.46 : 0.72, max_quality), mix(0.50, 0.28, max_quality), water);
}
"""

## Дальний ориентир-столб света: полупрозрачный, мягко гаснет кверху.
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0);
void fragment() {
	float v = UV.y;                        // 0 верх, 1 низ
	float edge = pow(abs(sin(UV.x * 3.14159)), 2.0);
	float flick = 0.85 + 0.15 * sin(TIME * 1.7 + UV.y * 9.0);
	ALBEDO = col.rgb * (0.6 + 1.4 * v * v) * flick;
	ALPHA = clamp(edge * smoothstep(0.0, 0.8, v) * 0.55, 0.0, 1.0);
}
"""

## Место под карту ворот: светящийся контур со скруглёнными углами чуть шире карты, уголки-скобы,
## полупрозрачный силуэт карты внутри и бегущий по контуру блик. vis — проявление, hover — под курсором.
## Занятое место: силуэт закрыт самой картой, виден только контур вокруг неё.
const GHOST_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform vec4 hover_col : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform vec2 size = vec2(24.0, 32.0);   // размер плоскости (м)
uniform vec2 card = vec2(20.8, 29.1);   // размер карты (м)
uniform float vis = 0.0;
uniform float hover = 0.0;
uniform float seed = 0.0;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	float d = sd_box(p, card * 0.5 + 0.35, 1.1);          // контур чуть шире карты
	float w = 0.16 + 0.1 * hover;
	float line = 1.0 - smoothstep(w, w + fwidth(d) * 1.5 + 0.02, abs(d));
	float glow = exp(-abs(d) * (1.4 - 0.5 * hover)) * step(0.0, d) * 0.55;
	// уголки-скобы снаружи контура
	vec2 q = card * 0.5 + 0.95 - abs(p);
	float brk = (1.0 - smoothstep(0.12, 0.2, abs(min(q.x, q.y)))) * step(max(q.x, q.y), 3.2) * step(-0.2, min(q.x, q.y));
	// силуэт карты: лёгкая заливка, внутренняя рамка и окно эмблемы
	float inside = 1.0 - smoothstep(-0.05, 0.05, d);
	float di = sd_box(p, card * 0.5 - 1.2, 0.7);
	float inner = 1.0 - smoothstep(0.06, 0.06 + fwidth(di) * 1.5 + 0.02, abs(di));
	float win = abs(length(p - vec2(0.0, card.y * 0.06)) - card.x * 0.26);
	float wline = 1.0 - smoothstep(0.08, 0.1 + fwidth(win) * 1.5, win);
	float t = TIME + seed;
	float breathe = 0.75 + 0.25 * sin(t * 2.4);
	// блик бежит по периметру
	float ang = atan(p.y * card.x / card.y, p.x) / 6.28318 + 0.5;
	float run = pow(0.5 + 0.5 * sin((ang - t * 0.22) * 6.28318 * 2.0), 16.0);
	vec3 c = mix(col.rgb, hover_col.rgb, hover);
	float a = line * (0.75 + 0.25 * hover) * breathe + line * run * 0.6 + glow * (0.5 + 0.6 * hover) + brk * (0.6 + 0.4 * hover)
		+ inside * (0.07 + 0.13 * hover + inner * (0.22 + 0.25 * hover) + wline * (0.14 + 0.2 * hover));
	ALBEDO = c * (0.72 + 0.6 * hover) + vec3(run * line * 0.6);
	ALPHA = clamp(a * vis, 0.0, 1.0);
}
"""

var _ghost_shader: Shader


func _make_ghost(i: int, pos: Vector3) -> MeshInstance3D:
	if _ghost_shader == null:
		_ghost_shader = Shader.new()
		_ghost_shader.code = GHOST_SHADER
	var pad := 3.0
	var g := MeshInstance3D.new()
	g.name = "Ghost%d" % i
	var pm := PlaneMesh.new()
	pm.size = Vector2(CARD_W + pad * 2.0, CARD_H + pad * 2.0)
	g.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = _ghost_shader
	sm.set_shader_parameter("size", pm.size)
	sm.set_shader_parameter("card", Vector2(CARD_W, CARD_H))
	sm.set_shader_parameter("seed", float(i) * 1.7)
	sm.set_shader_parameter("vis", 0.0)
	g.material_override = sm
	g.position = pos + Vector3(0, 0.015, 0)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visible = false
	add_child(g)
	# номер места (как на кнопках панели выбора) в центре силуэта
	var n := Label3D.new()
	n.text = str(i + 1)
	n.font_size = 160
	n.outline_size = 0
	n.pixel_size = CARD_W * 0.0016
	n.rotation_degrees = Vector3(-90, 0, 0)
	n.position = Vector3(0, 0.01, CARD_H * 0.06)
	n.modulate = Color(0.75, 0.92, 1.0, 0.5)
	n.shaded = false
	n.double_sided = false
	g.add_child(n)
	return g


func _glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.3)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.15
	m.metallic_specular = 0.8
	return m


func _mi(mesh: Mesh, mat: Material, pos: Vector3, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if location_id == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else (_decor if _decor != null else self)).add_child(mi)
	return mi


## Неподвижный декор (руины, горы) копится по парам «меш + материал» и рисуется одним MultiMesh
## на пару: вместо ~120 отдельных MeshInstance3D — 4 вызова отрисовки.
var _static_sets: Dictionary = {}


func _static(mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3, rot: Vector3) -> void:
	var key := [mesh, mat]
	if not _static_sets.has(key):
		_static_sets[key] = []
	_static_sets[key].append(Transform3D(Basis.from_euler(rot) * Basis.from_scale(scl), pos))


func _flush_static() -> void:
	for key in _static_sets.keys():
		var xs: Array = _static_sets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = key[0]
		mm.instance_count = xs.size()
		for i in range(xs.size()):
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = key[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if location_id == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_decor.add_child(mmi)
	_static_sets.clear()


func _crystal(pos: Vector3, c: Color, height: float, tilt_seed: int, light: bool = true) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = tilt_seed
	var root := Node3D.new()
	root.position = pos
	root.scale = Vector3.ONE * WORLD  # кристалл задан в единицах поля
	(_decor if _decor != null else self).add_child(root)
	var mat := _glow_mat(c, 2.2)
	for k in range(3):
		var h := height * (1.0 if k == 0 else rng.randf_range(0.45, 0.7))
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.16 * h / height + 0.06 if k == 0 else 0.1
		cm.height = h
		cm.radial_segments = 6
		cm.rings = 1
		var mi := _mi(cm, mat, Vector3.ZERO, root)
		if k > 0:
			var a := rng.randf() * TAU
			mi.position = Vector3(cos(a), 0, sin(a)) * 0.2
			mi.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
		mi.position.y += h * 0.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not light:
		return
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 1.4
	l.omni_range = 4.5 * WORLD
	l.position = Vector3(0, height * 0.6, 0)
	root.add_child(l)
	_crystal_lights.append(l)


## Медленно поднимающиеся искры над полем: пространство боя «живёт».
func _build_motes() -> void:
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.visibility_aabb = AABB(Vector3(-FLOOR_SIZE.x, -2, -FLOOR_SIZE.z), Vector3(FLOOR_SIZE.x * 2, 30, FLOOR_SIZE.z * 2))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(FLOOR_SIZE.x * 0.6, 0.5, FLOOR_SIZE.z * 0.6)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.15, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(0.5, 0.8, 1.0, 0.0))
	grad.add_point(0.2, Color(0.6, 0.85, 1.0, 1.0))
	grad.add_point(0.75, Color(0.8, 0.55, 1.0, 0.8))
	grad.set_color(grad.get_point_count() - 1, Color(0.8, 0.5, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(2.0, 2.0, 2.0)
	qm.albedo_texture = VisualUtil.soft_dot()
	q.material = qm
	p.draw_pass_1 = q
	p.position = Vector3(0, 0.5, 0)
	add_child(p)
	_motes = p


func _build_element_seals() -> void:
	for element in range(6):
		var angle := TAU * (element + 0.5) / 6.0
		var pos := Vector3(cos(angle) * 56.5, 0.06, sin(angle) * 56.5)
		var plane := PlaneMesh.new()
		plane.size = Vector2(4.8, 4.8)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_texture = ElementIcon.badge(element)
		material.albedo_color = Color(0.8, 0.8, 0.8, 0.75)
		_mi(plane, material, pos)
