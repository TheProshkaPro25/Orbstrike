class_name DeviceSettings
extends RefCounted
## Saved presentation choice only. It never changes a mode, team, rules, or progression.

const CLASSIC := 0
const DEVICE := 1
const NAMES := ["Классический", "Наручный прибор"]
const SECTION := "interface"

class SettingsEvents extends RefCounted:
	signal changed(style: int)
	signal motion_changed(reduced: bool)

static var settings_path := GraphicsSettings.PATH
static var _events := SettingsEvents.new()
static var _loaded := false
static var _style := CLASSIC
static var _reduce_motion := false


static func events() -> SettingsEvents:
	return _events


static func current() -> int:
	if not _loaded:
		var cfg := ConfigFile.new()
		cfg.load(settings_path)
		var saved: Variant = cfg.get_value(SECTION, "style", CLASSIC)
		_style = DEVICE if saved is int and int(saved) == DEVICE else CLASSIC
		var motion: Variant = cfg.get_value(SECTION, "reduce_motion", false)
		_reduce_motion = motion if motion is bool else false
		_loaded = true
	return _style


static func is_device() -> bool:
	return current() == DEVICE


static func set_style(value: int) -> Error:
	var next := DEVICE if value == DEVICE else CLASSIC
	if next == current():
		return OK
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value(SECTION, "style", next)
	var error := cfg.save(settings_path)
	if error != OK:
		return error
	_style = next
	_events.changed.emit(_style)
	return OK


## Re-read after an external settings change; also supports isolated review fixtures.
static func reload_settings() -> void:
	var previous := current()
	var previous_motion := _reduce_motion
	_loaded = false
	var next := current()
	if next != previous:
		_events.changed.emit(next)
	if _reduce_motion != previous_motion:
		_events.motion_changed.emit(_reduce_motion)


static func reduce_motion() -> bool:
	current()
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
