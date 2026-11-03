class_name BattleTempo
extends RefCounted
## Скорость постановки без таймера на принятие решения. Чтение HUD идёт по реальным секундам.
const SPEEDS := [0.75, 1.0, 1.5, 2.0]
const NAMES := ["Размеренно ×0.75", "Обычно ×1", "Быстро ×1.5", "Динамично ×2"]
static var selected := 1
static var loaded := false

static func load_settings() -> void:
	if loaded:
		return
	loaded = true
	var cfg := ConfigFile.new()
	cfg.load(GraphicsSettings.PATH)
	selected = clampi(int(cfg.get_value("presentation", "tempo", 1)), 0, SPEEDS.size() - 1)

static func apply() -> void:
	Engine.time_scale = SPEEDS[selected]

static func set_tempo(value: int) -> void:
	selected = clampi(value, 0, SPEEDS.size() - 1)
	apply()
	var cfg := ConfigFile.new()
	cfg.load(GraphicsSettings.PATH)
	cfg.set_value("presentation", "tempo", selected)
	cfg.save(GraphicsSettings.PATH)
