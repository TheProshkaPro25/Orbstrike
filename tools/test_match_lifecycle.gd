extends SceneTree
## Real resident Boot, failed checkout rollback/retry, intro cancellation, restart/exit.
const Lifecycle := preload("res://scenes/match_lifecycle.gd")
const Resources := preload("res://scenes/match_resources.gd")
class PreparationProbe extends Node:
	var done := false
	var result: RefCounted
	func start(resources: Resources, definitions: Dictionary, owners: Dictionary, profiles: Array[Dictionary], origins: Array[Vector3]) -> void:
		result = await resources.prepare(definitions,owners,profiles,origins,origins)
		done = true
var checks := 0
var failures := 0
var loader: GameLoading
var main: Node
var out := "res://build/checks/gameplay/match-lifecycle"
var catalog_counts: Array = []
var catalog_actors: Dictionary = {}
var cancelled_controller: MatchController

func _initialize() -> void: run.call_deferred()
func frames(n: int = 3) -> void:
	for i in n: await process_frame
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",text)
func until(test: Callable, seconds: float = 20.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if test.call(): return true
	return false
func counts() -> Array:
	return [loader.preparation_count,loader.actor_build_count,loader.arena_build_count,loader.fighter_build_count,SoundFx.i().catalog_load_count]
func available_fighters() -> int:
	var n := 0
	for pair in loader._fighters.values(): n += pair.size()
	return n
func choose() -> void:
	main.rng.seed = 424242
	main.team_menu._rng.seed = 771
	main.team_menu.pick_random()
	main.team_menu._show_step(1)
	main.team_menu._on_go()
func stop_pump() -> void:
	if main.events.drained.is_connected(main._pump): main.events.drained.disconnect(main._pump)
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(out.path_join(name+".png")) == OK,"save "+name)
func returned() -> void:
	check(loader._leased.is_empty(),"no actor leases remain")
	check(available_fighters() == 4,"all four resident fighters returned")
	check(counts() == catalog_counts,"resident counts unchanged; no late setup/load")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	if not OS.get_environment("XDG_DATA_HOME").begins_with(ProjectSettings.globalize_path("res://build/checks/")):
		check(false,"save integration requires isolated check.py user data")
		await finish(); return
	DeviceSettings.settings_path = out.path_join("settings.cfg")
	DeviceSettings.reload_settings()
	DeviceSettings.set_reduce_motion(false)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	Engine.time_scale = 1.0
	change_scene_to_file("res://scenes/loading/boot.tscn")
	if not await until(func(): return current_scene != null and current_scene.scene_file_path == "res://scenes/menu/main_menu.tscn",180):
		check(false,"Boot completes")
		await finish(); return
	loader = GameLoading.i()
	catalog_counts = counts()
	check(loader.ready_to_play and catalog_counts[1] == CreatureModels.catalog_defs().size() * 2 and catalog_counts[2] == 3,"two resident actors per definition and three arenas before menu")
	current_scene._on_play()
	if not await until(func(): return current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn"):
		check(false,"team scene opens"); await finish(); return
	main = current_scene
	# Force real catalog exhaustion at fighter checkout; do not build substitutes.
	main.team_menu._preview.release()
	for pair in loader._balls.values():
		for ball: CreatureBall in pair: catalog_actors[ball.get_instance_id()] = ball.def.id
	var saved_fighters: Dictionary = {}
	for model in loader._fighters:
		saved_fighters[model] = loader._fighters[model].duplicate()
		loader._fighters[model].clear()
	var saved_profile := PlayerProfile.new()
	saved_profile.load_from()
	var player_model: int = PlayerProfile.normalized(saved_profile.value).vrm_model
	loader._fighters[player_model].append(saved_fighters[player_model][0])
	choose()
	var rejected: MatchController = main.ctrl
	check(await until(func(): return not main._preparing),"fighter failure completes")
	check(main.ctrl == null and not rejected._started and main._lifecycle.stage == Lifecycle.Stage.SELECTING,"explicit failure returns to selection without controller start")
	check(main.team_menu.visible and main.hud.visible and main.team_menu._preview._status.text.contains("нет свободного героя"),"failure restores interface and visible explanation")
	check(main.fighters.is_empty() and main._prepared_balls.is_empty() and loader._leased.is_empty(),"fighter failure leaves no partial leases")
	check(available_fighters() == 1,"second-fighter failure returns the first partial fighter lease")
	for model in saved_fighters: loader._fighters[model].assign(saved_fighters[model])
	await shot("fighter-failure")
	# Exhaust the last creature definition after earlier checkouts succeeded.
	choose()
	rejected = main.ctrl
	var ids: Array = main._defs.keys()
	var missing: CreatureDef = main._defs[ids.back()]
	var saved_balls: Array = loader._balls[missing.id].duplicate()
	loader._balls[missing.id].clear()
	check(await until(func(): return not main._preparing),"actor failure completes")
	check(main.ctrl == null and not rejected._started and main._prepared_balls.is_empty() and main.balls.is_empty(),"partial actor transaction rolls back")
	check(loader._leased.is_empty() and available_fighters() == 4,"actor failure returns earlier actors and both fighters")
	check(main.team_menu.visible and main.hud.visible and not main._duel_menu.visible,"no hidden/dead match UI after rollback")
	loader._balls[missing.id].append_array(saved_balls)
	check(counts() == catalog_counts,"failed checkout never substitutes a new model")
	await shot("actor-failure")
	# Atomic arena replacement: unavailable target preserves the selected arena.
	var old_arena: Arena = main.arena
	var old_location := ArenaLocations.current()
	var missing_location: int = (old_arena.location_id+1)%3
	var saved_arena: Arena = loader._arenas[missing_location]
	loader._arenas.erase(missing_location)
	main.team_menu._arena_picker.chosen.emit(missing_location)
	check(main.team_menu._arena_btn.text == "Арена: " + str(ArenaLocations.definition(old_location).name),"failed actual picker restores the selected arena label")
	check(main.arena == old_arena and ArenaLocations.current() == old_location,"failed arena selection preserves lease and persisted choice")
	loader._arenas[missing_location] = saved_arena
	# Retry the same scene: no duplicated input/controller callbacks.
	choose()
	stop_pump()
	check(await until(func(): return is_instance_valid(main._location_intro)),"retry reaches actual intro")
	check(not main.ctrl._started and not main.hud.visible and not main.setup_panel.visible,"prepare/intro keeps controller and interface locked")
	check(main._prepared_balls.size() == 6 and main.fighters.size() == 2,"retry acquired exactly six actors and two fighters")
	check(main.hud.creature_chosen.get_connections().size() == 1 and main.setup_panel.placed.get_connections().size() == 1,"failed retries do not duplicate interface bindings")
	await shot("retry-intro")
	cancelled_controller = main.ctrl
	var transfer: Resources.ActorResult = main._resources.activate(0,main._defs[0],main._start_pos(0))
	var late_retirement: Resources.Retirement = main._resources.begin_retire(0)
	transfer.actor.vanish(false)
	check(transfer.actor._open_tween != null,"release interrupts a real running vanish")
	main._release_game_resources()
	await frames()
	var leased_again: CreatureBall = loader.take_ball(transfer.actor.def.id,7777,Vector3(2,.36,4))
	check(leased_again == transfer.actor and leased_again.visible,"returned vanishing actor can be leased again")
	check(not main._resources.finish_retire(late_retirement) and leased_again.visible and leased_again.uid == 7777 and leased_again.process_mode == Node.PROCESS_MODE_INHERIT,"old vanish continuation cannot hide or disable a new lease")
	loader.return_ball(leased_again)
	check(not cancelled_controller._started and main._lifecycle.stage == Lifecycle.Stage.RELEASED and not is_instance_valid(main._location_intro),"release cancels awaiting intro without late controller start")
	returned()
	check(loader._arenas.size() == 3,"cancel returns all three arenas")
	main._release_game_resources()
	returned()
	# A new scene can use the returned catalog and the normal intro completion.
	loader.show_game()
	await frames()
	main = current_scene
	main._lifecycle.prepared.connect(main._release_game_resources,CONNECT_ONE_SHOT)
	choose()
	var signal_cancelled: MatchController = main.ctrl
	check(await until(func(): return main._lifecycle.stage == Lifecycle.Stage.RELEASED),"prepared subscriber can synchronously cancel")
	check(not signal_cancelled._started and not is_instance_valid(main._location_intro),"prepared cancellation creates no intro or late controller start")
	returned()
	loader.show_game()
	await frames()
	main = current_scene
	main.team_menu._preview.release()
	# Tournament uses the same start transaction and a visible hub on failure.
	main.tournament = Tournament.create(CardDB.preset_deck(1),1,771,"Fixture")
	var fixture: Dictionary = main.tournament.next_match()
	while int(fixture.a) != 0 and int(fixture.b) != 0:
		main.tournament.simulate_next_npc()
		fixture = main.tournament.next_match()
	main._show_tournament()
	main._preview_arena_location(0,false)
	old_arena = main.arena
	saved_arena = loader._arenas[1] # First human group match uses Canyon.
	loader._arenas.erase(1)
	main._play_tournament_match()
	check(main.ctrl == null and not main._preparing and main.arena == old_arena,"unavailable tournament arena never starts on the previous arena")
	check(main.tournament_panel.visible and main.tournament_panel._notice.visible and main.tournament_panel._notice.text.contains("Арена матча") and not is_instance_valid(main._tournament_exit),"arena failure keeps visible tournament hub and notice")
	loader._arenas[1] = saved_arena
	main._play_tournament_match()
	rejected = main.ctrl
	var in_progress: String = main.tournament.state.in_progress
	missing = main._defs[main._defs.keys().back()]
	saved_balls = loader._balls[missing.id].duplicate()
	loader._balls[missing.id].clear()
	check(await until(func(): return not main._preparing),"tournament actor failure completes")
	check(main.ctrl == null and not rejected._started and main.tournament_panel.visible and not is_instance_valid(main._tournament_exit),"tournament failure restores hub instead of hidden match")
	check(main.tournament.state.in_progress == in_progress,"failed start keeps the same resumable tournament fixture")
	loader._balls[missing.id].append_array(saved_balls)
	returned()
	await shot("tournament-failure")
	main._play_tournament_match()
	stop_pump()
	check(await until(func(): return is_instance_valid(main._location_intro)),"tournament retry reaches intro")
	main._location_intro.finish()
	check(await until(func(): return not main._preparing),"tournament retry plays")
	check(main.ctrl._started and main._tournament_match.id == fixture.id and main.arena.location_id == 1,"tournament retry uses same fixture and correct arena")
	check(main._spawn_ball(9999) == null,"invalid live activation is a handled scene error")
	await frames()
	check(main._lifecycle.stage == Lifecycle.Stage.FAILED and main.game_over_ui._panel.visible and main.game_over_ui._title.text == "МАТЧ ОСТАНОВЛЕН","live resource failure displays explicit retry UI")
	check(main._accept_tournament_result() == ERR_UNAVAILABLE and main.tournament.next_match().id == fixture.id and main.tournament.state.in_progress == in_progress and main.ctrl.winner == -2,"resource failure never records a false draw/result")
	var failed_scene: int = main.get_instance_id()
	main.game_over_ui._restart_button.pressed.emit()
	check(await until(func(): return current_scene != null and current_scene.get_instance_id() != failed_scene),"failed tournament can use the real retry button")
	main = current_scene
	await frames()
	check(main.tournament_panel.visible and main.tournament.next_match().id == fixture.id and main.tournament.state.in_progress == in_progress,"retry reloads the same unfinished tournament fixture")
	main._release_game_resources()
	loader.show_game()
	await frames()
	main = current_scene
	choose()
	stop_pump()
	check(await until(func(): return is_instance_valid(main._location_intro)),"new scene starts after cancellation")
	main._location_intro.finish()
	check(await until(func(): return not main._preparing),"skip completes normal start")
	check(main.ctrl._started and main._lifecycle.stage == Lifecycle.Stage.PLAYING and main.hud.visible,"intro completion starts controller once and restores interface")
	await transfers()
	var actor_ids: Dictionary = {}
	for uid in main._prepared_balls:
		var ball: CreatureBall = main._prepared_balls[uid]
		actor_ids[uid] = ball.def.id
		check(ball.uid == uid and not ball._shape.disabled and not ball.visible and ball.process_mode == Node.PROCESS_MODE_DISABLED,"reserve uid/collider/disabled pose")
	main._lifecycle.begin_finish()
	check(not main._lifecycle.input_allowed() and not main._game_over,"logical finish blocks play while presentation can still drain")
	main._lifecycle.finish()
	check(main._game_over and not main._human_field_input_allowed() and not main.setup_panel._panel.visible and not main.ability_panel._panel.visible,"coordinator finish controls gameover and closes actions")
	check(main._lifecycle.stage == Lifecycle.Stage.FINISHED,"finish is explicit and retains resources for result presentation")
	var old_instance: int = main.get_instance_id()
	main.game_over_ui.restart_requested.emit()
	check(await until(func(): return current_scene != null and current_scene.get_instance_id() != old_instance),"real restart button replaces scene")
	main = current_scene
	check(main.team_menu.visible,"restart returns to team selection")
	choose()
	stop_pump()
	check(await until(func(): return is_instance_valid(main._location_intro)),"restart reaches intro")
	main._location_intro.finish()
	check(await until(func(): return not main._preparing),"restart plays")
	for uid in actor_ids:
		check(catalog_actors.has(main._prepared_balls[uid].get_instance_id()) and main._prepared_balls[uid].def.id == actor_ids[uid],"restart reuses catalog actor/definition uid="+str(uid))
	check(counts() == catalog_counts,"start/restart did not prepare resources again")
	await shot("restart-ready")
	check(main._spawn_ball(9999) == null,"ordinary missing resident activation does not load a model")
	await frames()
	check(main._game_over and not main._lifecycle.input_allowed() and main.game_over_ui._panel.visible,"ordinary actor failure stops input and exposes retry/menu")
	returned()
	await shot("activation-failure")
	old_instance = main.get_instance_id()
	main.game_over_ui._restart_button.pressed.emit()
	check(await until(func(): return current_scene != null and current_scene.get_instance_id() != old_instance),"ordinary failure retry replaces scene")
	main = current_scene
	choose()
	stop_pump()
	check(await until(func(): return is_instance_valid(main._location_intro)),"ordinary failure retry reaches intro")
	main._location_intro.finish()
	check(await until(func(): return not main._preparing) and main.ctrl._started,"ordinary failure retry starts normally")
	main._leave_duel_to_menu()
	check(await until(func(): return current_scene != null and current_scene.scene_file_path == "res://scenes/menu/main_menu.tscn"),"normal exit returns to menu")
	await frames()
	returned()
	check(loader._arenas.size() == 3 and Engine.max_fps == 60,"exit returns arena and keeps60FPS wrapper")
	await fallback_cancel()
	await finish()

func transfers() -> void:
	var original: CreatureBall = main._prepared_balls[0]
	var initial := original.get_instance_id()
	var animator := original._anim.get_instance_id()
	var origin: Vector3 = main._start_pos(0)
	original.global_position = origin + Vector3(10,0,0)
	var children_before: int = main.world.get_child_count()
	var first: Resources.ActorResult = main._resources.activate(0,main._defs[0],origin)
	var flash: Node3D = main.world.get_child(main.world.get_child_count()-1)
	check(main.world.get_child_count() > children_before and flash.global_position.is_equal_approx(first.actor._shell_center()),"activation close flash uses the restored launch position")
	check(first.is_ok() and first.actor.get_instance_id() == initial and first.actor._anim.get_instance_id() == animator,"activation reuses exact prepared actor and animator")
	check(main.balls.get(0) == first.actor and not main._prepared_balls.has(0) and not first.actor._shape.disabled and first.actor.slot == -1 and first.actor.visible,"activation belongs to resource owner and resets collider/slot/visibility")
	var ticket: Resources.Retirement = main._resources.begin_retire(0)
	check(main._prepared_balls.get(0) == first.actor and not main.balls.has(0),"retirement is registered before awaiting presentation")
	var again: Resources.ActorResult = main._resources.activate(0,main._defs[0],origin)
	check(again.actor == first.actor and not main._resources.finish_retire(ticket) and again.actor.visible,"reactivation invalidates old retirement")
	var replacement: Resources.Retirement = main._resources.begin_retire(0)
	check(not main._resources.finish_retire(ticket) and main._resources.finish_retire(replacement),"only current retirement serial can settle the same actor")
	check(not main._resources.finish_retire(replacement) and not original.visible and original.process_mode == Node.PROCESS_MODE_DISABLED,"retirement settles exactly once and disables reserve")
	var refused: Resources.ActorResult = main._resources.activate(9999,main._defs[0],origin)
	check(refused.error == ERR_DOES_NOT_EXIST and refused.actor == null and counts() == catalog_counts and main._prepared_balls.size() == 6,"missing resident UID returns an error without fallback setup")
	await frames()


func fallback_cancel() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var isolated := GameLoading.new() # Not a singleton/Boot catalog.
	var resources := Resources.new(world,isolated,load("res://scenes/creature_ball.tscn"),load("res://scenes/arena.tscn"))
	var reserve: Dictionary = resources.reserve
	var fighters: Array[VrmFighter] = resources.fighters
	resources.arena = Arena.new() # Valid arena handle; no procedural build needed.
	var deck := CardDB.preset_deck(1)
	var controller := MatchController.new(deck,deck,771)
	var definitions: Dictionary = {}
	var owners: Dictionary = {}
	for creature in controller.state.creatures.values():
		definitions[creature.uid] = CardDB.creature(creature.def_id)
		owners[creature.uid] = creature.owner
	var profile := PlayerProfile.npc_profile(2)
	var profiles: Array[Dictionary] = [profile,profile]
	var origins: Array[Vector3] = [Vector3(0,.36,12),Vector3(0,.36,-12)]
	var isolated_actor := resources.activate(2001,definitions[0],origins[0])
	check(isolated_actor.is_ok() and resources.active.get(2001) == isolated_actor.actor,"explicit isolated activation fallback is owned by resources")
	var retired := resources.begin_retire(2001)
	check(resources.finish_retire(retired),"isolated actor can return to reserve")
	resources.release_match()
	await frames()
	check(resources.active.is_empty() and resources.reserve.is_empty() and not is_instance_valid(isolated_actor.actor),"isolated fallback actor is released through ModelLifetime")
	var probe := PreparationProbe.new()
	root.add_child(probe)
	probe.start(resources,definitions,owners,profiles,origins)
	check(not probe.done and reserve.is_empty() and fighters.size() == 2,"isolated preparation reaches its first frame boundary before any ball setup")
	resources.release()
	await frames(5)
	check(probe.done and probe.result.error == ERR_SKIP and reserve.is_empty() and fighters.is_empty(),"fallback cancellation returns explicit outcome without late ball setup")
	check(world.get_child_count() == 0,"fallback fighters are freed after cancellation")
	check(counts() == catalog_counts,"isolated cancellation leaves resident catalog untouched")
	var late := resources.activate(2002,definitions[0],origins[0])
	check(late.error == ERR_UNAVAILABLE and late.actor == null and world.get_child_count() == 0,"terminal release rejects late fallback activation")
	check(not resources.select_arena(0).is_ok(),"terminal release cannot build another arena")
	var after_release := await resources.prepare(definitions,owners,profiles,origins,origins)
	check(after_release.error == ERR_UNAVAILABLE and world.get_child_count() == 0,"terminal release cannot prepare again")
	probe.queue_free()
	world.queue_free()
	isolated.free()
	await frames()

func finish() -> void:
	if is_instance_valid(current_scene): current_scene.queue_free()
	await frames()
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	await frames()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames()
	var result := {"checks":checks,"failures":failures,"catalog_counts":catalog_counts,"scope":"resident lifecycle failure/rollback/retry/intro cancellation/start/restart/menu exit; no full match"}
	var file := FileAccess.open(out.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	print("LIFECYCLE ",JSON.stringify(result))
	quit(1 if failures else 0)
