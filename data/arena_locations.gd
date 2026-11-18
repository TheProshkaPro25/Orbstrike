class_name ArenaLocations
extends RefCounted
## Локации меняют окружение, но не правила, размеры и позиции ворот.
const HARBOR_MOON := Vector3(-350, 89, -114)
const CANYON := 1
const CoastalStyle := preload("res://scenes/locations/coastal_style.gd")

const LOCATIONS := [
	{"name": "Святилище стихий", "description": "Закрытый храмовый зал: ребристый купол, высокие витражи и шесть священных реликвий.",
		"stone": Color(0.065, 0.09, 0.105), "far": Color(0.045, 0.065, 0.078), "trim": Color(0.40, 0.28, 0.12),
		"zenith": Color(0.075, 0.15, 0.22), "horizon": Color(0.27, 0.38, 0.39), "mist": Color(0.11, 0.035, 0.13),
		"fog": Color(0.18, 0.28, 0.30), "sun": Color(1.0, 0.9, 0.76), "sun_energy": 2.6,
		"ambient": Color(0.48, 0.59, 0.7), "accent": Color(0.4, 0.8, 1.0)},
	{"name": "Янтарный каньон", "description": "Амфитеатр в скальном ущелье: резные галереи, высокие уступы и дорога за древним порталом.",
		"stone": Color(0.105, 0.064, 0.035), "far": Color(0.075, 0.047, 0.030), "trim": Color(0.72, 0.44, 0.17),
		"zenith": Color(0.10, 0.17, 0.24), "horizon": Color(0.45, 0.23, 0.11), "mist": Color(0.26, 0.12, 0.06),
		"fog": Color(0.29, 0.18, 0.10), "sun": Color(1.0, 0.83, 0.66), "sun_energy": 1.86,
		"ambient": Color(0.56, 0.61, 0.69), "accent": Color(1.0, 0.66, 0.25)},
	{"name": "Лунная гавань", "description": "Портовый город вокруг бухты: арочная набережная, морской дворец, обсерватория и парусники.",
		"stone": Color(0.028, 0.055, 0.071), "far": Color(0.012, 0.032, 0.055), "trim": Color(0.20, 0.49, 0.61),
		"zenith": Color(0.005, 0.012, 0.036), "horizon": Color(0.035, 0.085, 0.14), "mist": Color(0.035, 0.065, 0.15),
		"fog": Color(0.035, 0.075, 0.12), "sun": Color(0.57, 0.75, 1.0), "sun_energy": 2.2,
		"ambient": Color(0.40, 0.52, 0.65), "accent": Color(0.3, 0.8, 1.0)},
	{"name": CoastalStyle.NAME, "description": CoastalStyle.DESCRIPTION,
		"stone": Color(.24,.28,.28), "far": Color(.15,.21,.23), "trim": Color(.43,.40,.28),
		"zenith": Color(.055,.12,.18), "horizon": Color(.29,.39,.43), "mist": Color(.24,.34,.37),
		"fog": Color(.30,.40,.43), "sun": Color(1,.90,.75), "sun_energy": 1.24,
		"ambient": Color(.55,.65,.72), "accent": Color(.67,.71,.60)},
]
static var _current := -1
static func current() -> int:
	if _current < 0:
		var cfg := ConfigFile.new()
		cfg.load(GraphicsSettings.PATH)
		_current = clampi(int(cfg.get_value("arena", "location", 0)), 0, LOCATIONS.size() - 1)
	return _current

static func choose(index: int) -> Error:
	var selected := clampi(index, 0, LOCATIONS.size() - 1)
	var cfg := ConfigFile.new()
	cfg.load(GraphicsSettings.PATH)
	cfg.set_value("arena", "location", selected)
	var result := cfg.save(GraphicsSettings.PATH)
	if result == OK:
		_current = selected
	return result

static func definition(index: int) -> Dictionary:
	var data: Dictionary = LOCATIONS[clampi(index, 0, LOCATIONS.size() - 1)]
	return data
