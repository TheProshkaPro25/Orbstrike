extends Node
## Scene-side match transaction. No dependency on Main or its private methods.
const Resources := preload("res://scenes/match_resources.gd")
const Result := preload("res://scenes/match_start_result.gd")
enum Stage { SELECTING, PREPARING, INTRO, PLAYING, FINISHING, FINISHED, FAILED, RELEASED }
signal prepared
signal started
signal finishing
signal finished
signal released
signal failed(message: String)
var stage := Stage.SELECTING
var intro: LocationIntro
var _resources: Resources
var _camera: CameraRig
var _interface: CanvasLayer
var _hidden: Array[Control] = []
var _generation := 0

func configure(resources: Resources, camera: CameraRig, interface: CanvasLayer) -> void:
	_resources = resources
	_camera = camera
	_interface = interface

func request_start() -> bool:
	if stage != Stage.SELECTING: return false
	stage = Stage.PREPARING
	return true

func preparing() -> bool:
	return stage in [Stage.PREPARING,Stage.INTRO]

func input_allowed() -> bool:
	return stage == Stage.PLAYING

func is_finished() -> bool:
	return stage in [Stage.FINISHED,Stage.FAILED]

func start(controller: MatchController, definitions: Dictionary, owners: Dictionary, profiles: Array[Dictionary], origins: Array[Vector3], fighter_origins: Array[Vector3], first_side: int) -> Result:
	if stage != Stage.PREPARING: return Result.new(ERR_BUSY,"Матч уже запускается.")
	var generation := _generation
	for control in _interface.get_children():
		if control is Control and control.visible:
			_hidden.append(control)
			control.hide()
	var result := await _resources.prepare(definitions,owners,profiles,origins,fighter_origins)
	if generation != _generation: return Result.new(ERR_SKIP,"Запуск отменён.")
	if not result.is_ok():
		_restore_interface()
		stage = Stage.SELECTING
		return result
	prepared.emit()
	if generation != _generation: return Result.new(ERR_SKIP,"Запуск отменён.")
	stage = Stage.INTRO
	intro = LocationIntro.new()
	_interface.add_child(intro)
	intro.play(_camera,_resources.arena.location_id)
	await intro.completed
	intro = null
	if generation != _generation: return Result.new(ERR_SKIP,"Запуск отменён.")
	_restore_interface()
	stage = Stage.PLAYING
	controller.start(first_side)
	started.emit()
	return Result.new()

func begin_finish() -> void:
	if stage != Stage.PLAYING: return
	stage = Stage.FINISHING
	finishing.emit()

func finish() -> void:
	if stage not in [Stage.PLAYING,Stage.FINISHING]: return
	stage = Stage.FINISHED
	finished.emit()

## An invalid live lease stops presentation without inventing a domain result.
func fail(message: String) -> void:
	if stage in [Stage.RELEASED,Stage.FAILED]: return
	_generation += 1
	stage = Stage.FAILED
	if is_instance_valid(intro): intro.finish()
	intro = null
	_restore_interface()
	failed.emit(message) # Consumers stop their queue before actors are returned.
	_resources.release_match()

## Set cancellation before completing intro: its awaiting start must not play.
func release() -> void:
	if stage == Stage.RELEASED: return
	_generation += 1
	stage = Stage.RELEASED
	if is_instance_valid(intro): intro.finish()
	intro = null
	_restore_interface()
	_resources.release()
	released.emit()

func _restore_interface() -> void:
	for control in _hidden:
		if is_instance_valid(control): control.show()
	_hidden.clear()
