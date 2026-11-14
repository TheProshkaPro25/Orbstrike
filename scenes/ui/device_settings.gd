class_name DeviceSettings
extends RefCounted
## Настройка анимации наручного прибора.
const SECTION := "interface"

class SettingsEvents extends RefCounted:
	signal motion_changed(reduced: bool)

static var settings_path := GraphicsSettings.PATH
static var _events := SettingsEvents.new()
static var _loaded := false
static var _reduce_motion := false


static func events() -> SettingsEvents:
	return _events


## Re-read after an external settings change; also supports isolated review fixtures.
static func reload_settings() -> void:
	var previous := reduce_motion()
	_loaded = false
	var next := reduce_motion()
	if next != previous:
		_events.motion_changed.emit(next)


static func reduce_motion() -> bool:
	if not _loaded:
		var cfg := ConfigFile.new()
		cfg.load(settings_path)
		var motion: Variant = cfg.get_value(SECTION, "reduce_motion", false)
		_reduce_motion = motion if motion is bool else false
		_loaded = true
	return _reduce_motion


static func set_reduce_motion(value: bool) -> Error:
	if reduce_motion() == value: return OK
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value(SECTION, "reduce_motion", value)
	var error := cfg.save(settings_path)
	if error != OK: return error
	_reduce_motion = value
	_events.motion_changed.emit(value)
	return OK
