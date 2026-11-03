class_name GraphicsSettings
extends RefCounted
## Настройки графики «Низкие / Средние / Высокие»: тени, SSAO, сглаживание, детализация моделей, искры и декор.
## Хранятся в user://settings.cfg ([graphics] level). При первом запуске уровень выбирается по видеокарте
## (RenderingServer.get_video_adapter_name()): GTX 1060 и слабее — «Средние», встроенная графика — «Низкие».
## Применение: apply_world(viewport, env, sun) — рендер; Arena.apply_quality() — искры/декор.

enum Level { LOW, MEDIUM, HIGH }
const NAMES := ["Низкие", "Средние", "Высокие"]
const PATH := "user://settings.cfg"

## Параметры уровней (индекс — Level). Тени солнца: размер атласа и число каскадов; фильтр мягких теней
## 0..5 (RenderingServer.ShadowQuality); ssao: 0 — выкл., иначе 1 + RenderingServer.EnvironmentSSAOQuality (2 — низкое, 3 — среднее, как было);
## msaa — Viewport.MSAA_*, fxaa — сглаживание по экрану; lod — порог смены детализации мешей (пиксели);
## motes — частиц-искр над полем; lights — подсветка кристаллов (6 omni); floaters — парящие осколки двигаются.
const PRESETS := [
	{"shadow_size": 2048, "splits": 2, "shadow_filter": 1, "shadow_dist": 60.0, "ssao": 0, "msaa": Viewport.MSAA_DISABLED,
		"fxaa": false, "lod": 4.0, "motes": 70, "lights": false, "floaters": false},
	{"shadow_size": 4096, "splits": 2, "shadow_filter": 2, "shadow_dist": 77.0, "ssao": 2, "msaa": Viewport.MSAA_DISABLED,
		"fxaa": false, "lod": 2.0, "motes": 160, "lights": true, "floaters": true},
	{"shadow_size": 8192, "splits": 4, "shadow_filter": 4, "shadow_dist": 120.0, "ssao": 4, "msaa": Viewport.MSAA_4X,
		"fxaa": false, "lod": 1.0, "motes": 260, "lights": true, "floaters": true},
]

static var level: int = -1
## Ограничитель кадров: 0 — без лимита (Engine.max_fps). По умолчанию 60.
const FPS_OPTIONS := [60, 90, 120, 144, 0]
const FPS_DEFAULT := 60
static var max_fps: int = -1
## Подмена отдельных параметров (замеры tools/perf.gd: ключ=значение поверх уровня).
static var overrides: Dictionary = {}


## Текущий уровень (загружается при первом обращении).
static func current() -> int:
	if level < 0:
		load_settings()
	return level


## Текущий лимит fps (загружается вместе с качеством).
static func fps_limit() -> int:
	if max_fps < 0:
		load_settings()
	return max_fps


static func fps_name(v: int = -1) -> String:
	var f: int = fps_limit() if v < 0 else v
	return "без лимита" if f == 0 else str(f)


## Выставить лимит fps, применить сразу и сохранить.
static func set_fps(v: int) -> void:
	max_fps = v if FPS_OPTIONS.has(v) else FPS_DEFAULT
	Engine.max_fps = max_fps
	save()


## Следующий вариант лимита по кругу 60 → 90 → 120 → 144 → без лимита.
static func next_fps() -> void:
	set_fps(FPS_OPTIONS[(FPS_OPTIONS.find(fps_limit()) + 1) % FPS_OPTIONS.size()])


static func param(key: String) -> Variant:
	if overrides.has(key):
		return overrides[key]
	return PRESETS[current()][key]


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok: bool = cfg.load(PATH) == OK
	var fps: int = int(cfg.get_value("graphics", "max_fps", FPS_DEFAULT)) if ok else FPS_DEFAULT
	max_fps = fps if FPS_OPTIONS.has(fps) else FPS_DEFAULT
	if ok and cfg.has_section_key("graphics", "level"):
		level = clampi(int(cfg.get_value("graphics", "level")), Level.LOW, Level.HIGH)
	else:
		level = auto_level(RenderingServer.get_video_adapter_name())
		save()


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # сохранить другие разделы, если есть
	cfg.set_value("graphics", "level", level)
	if max_fps >= 0:
		cfg.set_value("graphics", "max_fps", max_fps)
	cfg.save(PATH)


## Выбор уровня по названию видеокарты. Сильные дискретные (RTX, Radeon RX 6000+, Arc) — «Высокие»;
## встроенные (Intel UHD/Iris, Radeon Graphics/Vega, llvmpipe) — «Низкие»; остальные (GTX 10xx/16xx, MX, RX 500…) — «Средние».
static func auto_level(adapter: String) -> int:
	var a := adapter.to_lower()
	if a.contains("llvmpipe") or a.contains("swiftshader") or a.contains("intel") and not a.contains("arc") \
			or a.contains("radeon graphics") or a.contains("vega") or a.contains("radeon(tm) graphics") or a.contains(" mx"):
		return Level.LOW
	if a.contains("rtx") or a.contains("arc"):
		return Level.HIGH
	var rx := RegEx.create_from_string("rx\\s*([0-9]{4})")
	var m := rx.search(a)
	if m != null and int(m.get_string(1)) >= 6600:
		return Level.HIGH
	return Level.MEDIUM


static func set_level(l: int) -> void:
	level = clampi(l, Level.LOW, Level.HIGH)
	save()


## Только для замеров: уровень без записи в settings.cfg.
static func force_level(l: int) -> void:
	level = clampi(l, Level.LOW, Level.HIGH)


static func level_from_name(s: String) -> int:
	match s.to_lower():
		"low", "низкие":
			return Level.LOW
		"medium", "средние":
			return Level.MEDIUM
	return Level.HIGH


static func level_name(l: int = -1) -> String:
	return NAMES[current() if l < 0 else l]


## Рендер: атлас и каскады теней солнца, фильтр теней, SSAO, сглаживание, детализация мешей.
static func apply_world(vp: Viewport, env: Environment, sun: DirectionalLight3D) -> void:
	var high := current() == Level.HIGH
	Engine.max_fps = fps_limit()
	RenderingServer.directional_shadow_atlas_set_size(int(param("shadow_size")), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(param("shadow_filter")))
	RenderingServer.positional_soft_shadow_filter_set_quality(int(param("shadow_filter")))
	if vp != null:
		vp.msaa_3d = int(param("msaa"))
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(param("fxaa")) else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.mesh_lod_threshold = float(param("lod"))
		# Проекторы витражей также используют карты теней: на HIGH каждому нужен
		# крупный слот, иначе край колонны превращается в заметные квадраты.
		vp.positional_shadow_atlas_size = 8192 if high else 1024
		vp.positional_shadow_atlas_16_bits = not high
		vp.positional_shadow_atlas_quad_0 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
		vp.positional_shadow_atlas_quad_1 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
		vp.positional_shadow_atlas_quad_2 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4 if high else Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16
		vp.positional_shadow_atlas_quad_3 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16 if high else Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64
	if sun != null:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(param("splits")) >= 4 \
			else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = float(param("shadow_dist"))
		sun.light_angular_distance = .65 if high else .4
		sun.shadow_blur = 1.1 if high else 1.0
		sun.shadow_normal_bias = .65 if high else 1.5
		sun.shadow_bias = .035 if high else .1
	if env != null:
		var q: int = int(param("ssao"))
		env.ssao_enabled = q > 0
		if q > 0:
			RenderingServer.environment_set_ssao_quality(q - 1 as RenderingServer.EnvironmentSSAOQuality, not high, 0.5, 4 if high else 2, 50.0, 300.0)
		env.ssao_radius = 1.2 if high else 1.5
		env.ssao_intensity = .8 if high else 1.0
		env.ssao_detail = .6 if high else .5
		env.ssil_enabled = high
		env.ssil_radius = 8.0
		env.ssil_intensity = .8
		env.ssil_sharpness = .85
		env.ssil_normal_rejection = 1.2
		if high:
			RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_HIGH, false, .5, 4, 50.0, 300.0)
		env.ssr_enabled = high
		env.ssr_max_steps = 96
		env.ssr_fade_in = .15
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = .5
	RenderingServer.light_projectors_set_filter(RenderingServer.LIGHT_PROJECTOR_FILTER_LINEAR_MIPMAPS_ANISOTROPIC if high else RenderingServer.LIGHT_PROJECTOR_FILTER_LINEAR_MIPMAPS)
