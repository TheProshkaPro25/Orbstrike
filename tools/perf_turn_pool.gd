extends SceneTree
## Живой прогрев матча и возврат тех же шести узлов без повторного setup/cloth.
var failures := 0
var timings: Array = []
var startup_seconds := 0.0
var startup_counts: Array[int] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error(label)
func run() -> void:
	Engine.max_fps = 60
	Engine.time_scale = 4
	var loader := GameLoading.i()
	var begin := Time.get_ticks_msec()
	await loader.prepare()
	startup_seconds = (Time.get_ticks_msec() - begin) / 1000.0
	startup_counts = [loader.preparation_count, loader.actor_build_count, loader.arena_build_count]
	loader.show_game()
	await process_frame
	var main = current_scene
	main.rng.seed = 271828
	main.team_menu.hide()
	var deck := CardDB.preset_deck(1)
	var creatures: Array[StringName] = []
	var gates: Array[StringName] = []
	var abilities: Array[StringName] = []
	for def in deck.creatures: creatures.append(def.id)
	for def in deck.arena: gates.append(def.id)
	for def in deck.abilities: abilities.append(def.id)
	main._on_deck_chosen(creatures,gates,abilities)
	main.events.drained.disconnect(main._pump)
	for frame in 1800:
		await process_frame
		if not main._preparing: break
	check(not main._preparing and main.ctrl._started,"match starts from initial catalogue")
	check([loader.preparation_count, loader.actor_build_count, loader.arena_build_count] == startup_counts,"no model or arena preparation after initial loading")
	check(main._prepared_balls.size()==6 and main.balls.is_empty(),"exactly six hidden prepared creatures")
	for uid in main._defs:
		var original: CreatureBall = main._prepared_balls[uid]
		var instance := original.get_instance_id()
		var animator := original._anim.get_instance_id()
		for repeat in 2:
			var t := Time.get_ticks_usec()
			var ball: CreatureBall = main._spawn_ball(uid)
			var elapsed := (Time.get_ticks_usec()-t)/1000.0
			check(ball.get_instance_id()==instance and ball._anim.get_instance_id()==animator,"reuse exact model and animator uid=%s"%uid)
			check(ball.uid==uid and ball.slot==-1 and not ball._shape.disabled,"restored identity/slot/collider uid=%s"%uid)
			check(not ball._open and ball._figure.rotation==Vector3.ZERO and ball._visual.scale==Vector3.ONE,"restored closed pose")
			timings.append({"uid":uid,"repeat":repeat,"activate_ms":elapsed,"prepare_ms":main.preparation_times_ms[uid]})
			ball.slot = 4
			ball._figure.rotation = Vector3(.2,.8,.4)
			await ball.open_animated(false)
			await main._anim_remove_ball(uid)
			check(main._prepared_balls[uid]==ball and not ball.visible and ball.process_mode==Node.PROCESS_MODE_DISABLED,"reserve has no simulation or visible model")
		main._focus_labels([])
		check(not original.visible,"focus does not reveal reserve")
	main._pending.clear()
	if main.has_method("_release_game_resources"):
		main._release_game_resources()
	main.queue_free()
	await process_frame
	loader.queue_free()
	await process_frame
	await create_timer(3).timeout
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await process_frame
	var output := OS.get_cmdline_user_args()
	if not output.is_empty():
		var f := FileAccess.open(output[0],FileAccess.WRITE)
		f.store_string(JSON.stringify({"failures":failures,"startup_seconds":startup_seconds,"timings":timings},"  "))
	print("POOL ",JSON.stringify({"failures":failures,"startup_seconds":startup_seconds,"timings":timings}))
	quit(1 if failures else 0)
