extends Node
## Два эффекта вступления идут по времени камеры и принадлежат её заставке.

const WIND_DB := -2.0
const ASCENT_DB := -1.0

var _wind: AudioStreamPlayer
var _ascent: AudioStreamPlayer


func _ready() -> void:
	var sound := SoundFx.i()
	_wind = sound.create_sfx_player("coastal_intro_wind", WIND_DB)
	_ascent = sound.create_sfx_player("coastal_intro_ascent", ASCENT_DB)
	add_child(_wind)
	add_child(_ascent)


func start() -> void:
	_wind.play()


func tilt() -> void:
	_ascent.play()


func stop() -> void:
	_wind.stop()
	_ascent.stop()


func _exit_tree() -> void:
	stop()
	_wind.stream = null
	_ascent.stream = null
