extends SceneTree
## Scoped rollback injection. Production files/assets stay untouched.
class IncompatibleBall extends CreatureBall:
	func setup(definition: CreatureDef, owner_uid: int) -> void:
		super.setup(definition, owner_uid)
		if definition.species == &"grifalon": _anim._authored_fullset = false
class FailureLoader extends GameLoading:
	var fixture_resources: Dictionary = {}
	var fail_at := ""
	var captured: Array[WeakRef] = []
	func _load_startup_resources(_progress: Callable) -> StartupCatalog.LoadResult:
		await get_tree().process_frame
		var result := StartupCatalog.LoadResult.new()
		result.resources = fixture_resources.duplicate()
		if fail_at == "missing": result.resources.erase("res://scenes/main.tscn")
		return result
	func _preload_creature_catalog() -> String:
		if fail_at == "animation":
			var node := IncompatibleBall.new()
			var scene := PackedScene.new()
			scene.pack(node)
			node.free()
			resources["res://scenes/creature_ball.tscn"] = scene
		return ""
	func _catalog_definitions() -> Array[CreatureDef]:
		var definitions: Array[CreatureDef] = [CardDB.creature(&"creature_dragnar_fire")]
		if fail_at == "animation": definitions.append(CardDB.creature(&"creature_grifalon_fire"))
		return definitions
	func _instantiate_startup_scene(path: String) -> Node:
		if (fail_at == "main" and path.ends_with("main.tscn")) or (fail_at == "menu" and path.ends_with("main_menu.tscn")):
			return null
		return super._instantiate_startup_scene(path)
	func _fail_preparation(progress: Callable, message: String) -> void:
		_capture(self)
		super._fail_preparation(progress,message)
	func _capture(node: Node) -> void:
		for child in node.get_children():
			captured.append(weakref(child))
			_capture(child)
var checks := 0
var failures := 0
var observed_interface := false
func _initialize() -> void: run.call_deferred()
func frames() -> void:
	for i in 3: await process_frame
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",label)
func clean(loader: FailureLoader, stage: String) -> void:
	check(not loader.preparing and not loader.ready_to_play and not loader.has_prepared_catalog(),stage+": flags rolled back")
	check(not loader.last_error.is_empty(),stage+": visible error retained")
	check(loader._viewport == null and loader._storage == null and loader._game == null and loader._menu == null,stage+": owners reset")
	check(loader.get_child_count() == 0,stage+": all partial node roots removed")
	check(loader._balls.is_empty() and loader._fighters.is_empty() and loader._arenas.is_empty() and loader._leased.is_empty(),stage+": registries cleared")
	check(loader.resources.is_empty() and loader.preparation_times_ms.is_empty(),stage+": resource/measurement references cleared")
	check(not CreatureModels.resident_catalog and CreatureModels._scenes.is_empty() and CreatureModels.preparation_cache.is_empty(),stage+": resident cache reset")
	check(not loader._warm_draw.is_valid(),stage+": warm draw disconnected")
	check(loader.actor_build_count == 0 and loader.arena_build_count == 0 and loader.fighter_build_count == 0,stage+": partial counts reset")
	var all_freed := true
	for reference in loader.captured:
		if reference.get_ref() != null: all_freed = false
	check(all_freed,stage+": parked/unparked actors and viewports freed")
	loader.captured.clear()
func run() -> void:
	CardDB.load_all()
	check(Engine.max_fps == 60,"test wrapper keeps60FPS")
	var paths := StartupCatalog.resource_paths()
	for path in StartupCatalog.REQUIRED_SCENES:
		check(paths.has(path),"explicit required root: "+path)
	var missing := await StartupCatalog.load_paths(["res://missing-required-fixture.tscn"])
	check(missing.resources.is_empty() and missing.error.contains("missing-required-fixture"),"missing listed resource fails with exact path")
	var loaded := await StartupCatalog.preload_resources()
	check(loaded.error.is_empty(),"real resource catalog valid: "+loaded.error)
	var wrong := loaded.resources.duplicate()
	wrong["res://scenes/main.tscn"] = Texture2D.new()
	check(not StartupCatalog.required_error(wrong).is_empty(),"wrong required resource type rejected")
	wrong["res://scenes/main.tscn"] = loaded.resources["res://scenes/arena.tscn"]
	check(not StartupCatalog.required_error(wrong).is_empty(),"wrong root script rejected before _ready")
	wrong.clear()
	var loader := FailureLoader.new()
	loader.fixture_resources = loaded.resources
	root.add_child(loader)
	GameLoading._inst = loader
	for stage in ["missing","animation","main","menu"]:
		loader.fail_at = stage
		var messages: Array[String] = []
		await loader.prepare(func(_value: float, text: String) -> void: messages.append(text))
		check(not messages.is_empty() and messages[-1] == loader.last_error,stage+": Boot receives failure text")
		clean(loader,stage)
		await frames()
	check(loader.preparation_count == 4,"failed loader allows repeated attempts")
	loader.queue_free()
	await frames()
	loaded.resources.clear()
	if OS.get_environment("SFERY_STARTUP_FAILURES_ONLY") != "1":
		# One real49x2/3-arena Boot verifies publication of readiness and prepared Main.
		var real := GameLoading.i()
		await real.prepare(func(value: float, _text: String) -> void:
			if value >= .96 and value < 1.0:
				observed_interface = true
				check(not real.ready_to_play and real.preparing and real.has_prepared_catalog(),"interface warmup keeps Boot pending with resident leases"))
		check(observed_interface,"actual interface phase observed")
		check(real.last_error.is_empty() and real.ready_to_play and not real.preparing,"ready published only after full successful preparation")
		check(real.actor_build_count == 98 and real.arena_build_count == 3 and real.fighter_build_count == 4,"normal Boot keeps98actors/3arenas/4fighters")
		check(real._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"successful viewport parked")
		check(is_instance_valid(real._game) and is_instance_valid(real._menu),"both interfaces prepared before ready")
		var preview: CreaturePreview = real._game.team_menu._preview
		check(preview._borrowed_ball != null and preview._anim != null,"hidden Main uses prepared preview without fallback")
		var counts := [real.preparation_count,real.actor_build_count,real.arena_build_count,real.fighter_build_count]
		await real.prepare()
		check([real.preparation_count,real.actor_build_count,real.arena_build_count,real.fighter_build_count] == counts,"repeat prepare after success does no additional work")
		# Clean the real prepared tree through the same rollback while leases are live.
		real._fail_preparation(Callable(),"test teardown")
		real.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames()
	print("STARTUP FAILURE ",checks,"/",failures)
	quit(1 if failures else 0)
