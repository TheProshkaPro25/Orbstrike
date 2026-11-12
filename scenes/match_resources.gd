extends RefCounted
## Per-scene lease owner. GameLoading owns the resident catalog, never this lease.
## Registries are shared with presentation; active/reserve transfers keep ownership.
const Result := preload("res://scenes/match_start_result.gd")
const Lifetime := preload("res://scenes/model_lifetime.gd")
var arena: Arena
class ActorResult extends "res://scenes/match_start_result.gd":
	var actor: CreatureBall
class Retirement extends RefCounted:
	var actor: CreatureBall
	var uid: int
	var revision: int
	var serial: int
var active: Dictionary[int,CreatureBall] = {}
var reserve: Dictionary[int,CreatureBall] = {}
var fighters: Array[VrmFighter] = []
var preparation_times_ms: Dictionary = {}
var _world: Node3D
var _tree: SceneTree
var _catalog: GameLoading
var _ball_scene: PackedScene
var _arena_scene: PackedScene
var _revision := 0
var _released := false
var _retire_serial := 0
var _retiring: Dictionary = {}

func _init(world: Node3D, catalog: GameLoading, ball_scene: PackedScene, arena_scene: PackedScene) -> void:
	_world = world
	_tree = world.get_tree() if world != null else Engine.get_main_loop() as SceneTree
	_catalog = catalog
	_ball_scene = ball_scene
	_arena_scene = arena_scene

func resident() -> bool:
	return is_instance_valid(_catalog) and _catalog.has_prepared_catalog()

## Take the replacement before returning the current arena: failure is atomic.
func select_arena(index: int) -> Result:
	if _released or not is_instance_valid(_world): return Result.new(ERR_UNAVAILABLE,"Ресурсы матча уже освобождены.")
	if is_instance_valid(arena) and arena.location_id == index: return Result.new()
	var replacement: Arena
	if resident(): replacement = _catalog.take_arena(index)
	else:
		replacement = _arena_scene.instantiate() as Arena
		replacement.location_id = index
		_world.add_child(replacement)
	if replacement == null:
		return Result.new(ERR_UNAVAILABLE,"Выбранная арена сейчас недоступна. Попробуйте другую.")
	if replacement.get_parent() != _world: replacement.reparent(_world,false)
	if is_instance_valid(arena):
		if resident(): _catalog.return_arena(arena)
		else: arena.queue_free()
	arena = replacement
	return Result.new()

## A failed/cancelled acquisition returns every partial actor/fighter lease.
## Only isolated scenes without Boot may construct models here.
func prepare(definitions: Dictionary, owners: Dictionary, profiles: Array[Dictionary], origins: Array[Vector3], fighter_origins: Array[Vector3]) -> Result:
	if _released or not is_instance_valid(_world): return Result.new(ERR_UNAVAILABLE,"Ресурсы матча уже освобождены.")
	if not active.is_empty() or not reserve.is_empty() or not fighters.is_empty():
		return Result.new(ERR_ALREADY_IN_USE,"Ресурсы предыдущего матча ещё используются.")
	if not is_instance_valid(arena) or definitions.size() != 6 or profiles.size() != 2 or origins.size() != 2 or fighter_origins.size() != 2:
		return Result.new(ERR_INVALID_DATA,"Не удалось подготовить состав матча.")
	var revision := _revision
	preparation_times_ms.clear()
	for side in 2:
		var fighter := _catalog.take_fighter(profiles[side]) if resident() else null
		if fighter == null:
			if resident(): return _failed("В каталоге нет свободного героя для матча.")
			fighter = VrmFighter.new()
			_world.add_child(fighter)
			fighter.apply_profile(profiles[side])
		elif fighter.get_parent() != _world: fighter.reparent(_world,false)
		fighter.position = fighter_origins[side]
		fighter.rotation.y = PI if side == 0 else 0.0
		fighters.append(fighter)
	if not resident(): CreatureModels.preload_match(definitions.values())
	for uid in definitions:
		var definition: CreatureDef = definitions[uid]
		var side := int(owners.get(uid,-1))
		if definition == null or side not in [0,1]: return _failed("Некорректное существо в составе матча.")
		var ball: CreatureBall
		if resident():
			ball = _catalog.take_ball(definition.id,uid,origins[side])
			if ball == null: return _failed("В каталоге нет свободного существа: " + definition.display_name)
			preparation_times_ms[uid] = _catalog.preparation_times_ms.get(definition.id,0.0)
			ball.set_presentation_definition(definition)
			ball.reparent(_world,false)
		else:
			await _world.get_tree().process_frame
			if revision != _revision: return Result.new(ERR_SKIP,"Подготовка отменена.")
			var begin := Time.get_ticks_usec()
			ball = _ball_scene.instantiate() as CreatureBall
			ball.visible = false
			_world.add_child(ball)
			ball.setup(definition,uid)
			ball.freeze_at(origins[side])
			preparation_times_ms[uid] = (Time.get_ticks_usec()-begin)/1000.0
		ball.visible = false
		ball.process_mode = Node.PROCESS_MODE_DISABLED
		reserve[uid] = ball
	return Result.new()

func _failed(message: String) -> Result:
	release_match()
	return Result.new(ERR_UNAVAILABLE,message)

## Activation never repairs a broken resident lease by loading another model.
func activate(uid: int, definition: CreatureDef, origin: Vector3) -> ActorResult:
	var result := ActorResult.new()
	if _released or not is_instance_valid(_world):
		result.error = ERR_UNAVAILABLE
		result.message = "Ресурсы матча уже освобождены."
		return result
	if active.has(uid):
		result.actor = active[uid]
		return result
	var ball: CreatureBall = reserve.get(uid)
	var reused := is_instance_valid(ball)
	if not is_instance_valid(ball):
		if resident() or definition == null:
			result.error = ERR_DOES_NOT_EXIST
			result.message = "В подготовленной команде нет существа для этого действия."
			return result
		# Explicit isolated-scene path; production always has six reserved actors.
		ball = _ball_scene.instantiate() as CreatureBall
		_world.add_child(ball)
		ball.setup(definition,uid)
	else:
		reserve.erase(uid)
	ball.process_mode = Node.PROCESS_MODE_INHERIT
	ball.freeze_at(origin)
	if reused: ball.close_up()
	ball._shape.disabled = false
	ball.slot = -1
	ball._figure.rotation = Vector3.ZERO
	ball.visible = true
	_retiring.erase(uid)
	active[uid] = ball
	result.actor = ball
	return result

## Ownership changes before presentation awaits vanish, so release can see it.
func begin_retire(uid: int) -> Retirement:
	var ball: CreatureBall = active.get(uid)
	if not is_instance_valid(ball): return null
	active.erase(uid)
	reserve[uid] = ball
	var ticket := Retirement.new()
	ticket.actor = ball
	ticket.uid = uid
	ticket.revision = _revision
	_retire_serial += 1
	ticket.serial = _retire_serial
	_retiring[uid] = ticket.serial
	return ticket

## A stale continuation cannot park a released or newly activated actor.
func finish_retire(ticket: Retirement) -> bool:
	if ticket == null or ticket.revision != _revision or _retiring.get(ticket.uid) != ticket.serial or not is_instance_valid(ticket.actor) or reserve.get(ticket.uid) != ticket.actor:
		return false
	_retiring.erase(ticket.uid)
	ticket.actor.visible = false
	ticket.actor.process_mode = Node.PROCESS_MODE_DISABLED
	return true

## Does not return the arena: a failed start can retry the same selection.
func release_match() -> void:
	_revision += 1
	_retiring.clear()
	var returned: Dictionary = {}
	for ball: CreatureBall in active.values()+reserve.values():
		if not is_instance_valid(ball) or returned.has(ball.get_instance_id()): continue
		returned[ball.get_instance_id()] = true
		if resident(): _catalog.return_ball(ball)
		else: Lifetime.release(ball,_tree)
	active.clear()
	reserve.clear()
	preparation_times_ms.clear()
	for fighter in fighters:
		if resident(): _catalog.return_fighter(fighter)
		elif is_instance_valid(fighter): fighter.queue_free()
	fighters.clear()

func release() -> void:
	if _released: return
	_released = true
	release_match()
	if is_instance_valid(arena):
		if resident(): _catalog.return_arena(arena)
		else: arena.queue_free()
	arena = null
