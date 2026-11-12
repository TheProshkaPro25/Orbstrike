extends SceneTree
## Живой прогрев матча и возврат тех же шести узлов без повторного setup/cloth.
var failures := 0
var timings: Array = []
var startup_seconds := 0.0
var startup_counts: Array[int] = []
var grifalon := false
var kolossar := false
var grifalon_contacts := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error(label)
func run() -> void:
	Engine.max_fps = 60
	Engine.time_scale = 4
	grifalon = OS.get_cmdline_user_args().has("grifalon")
	kolossar = OS.get_cmdline_user_args().has("kolossar")
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
	var deck := CardDB.preset_deck(0 if grifalon else 1)
	if kolossar: deck = CardDB.deck_from_creatures([&"creature_kolossar_light", &"creature_klykar_light", &"creature_gorgul_light"], main.rng)
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
	var library_loads: int = CreatureModels.KolossarMotion.load_count if kolossar else CreatureModels.GrifalonMotion.load_count
	var overlay_loads: int = CreatureModels.KolossarLightSkin.load_count if kolossar else CreatureModels.GrifalonGaleSkin.load_count
	if grifalon or kolossar:
		check(overlay_loads == 1 and (CreatureModels.KolossarLightSkin.meshes.size() if kolossar else CreatureModels.GrifalonGaleSkin.meshes.size()) == 1, "overlay loaded and one immutable mesh built during Boot")
	if grifalon or kolossar:
		var attacker_uid := -1
		var defender_uid := -1
		for uid in main._defs:
			var d: CreatureDef = main._defs[uid]
			if d.id == (&"creature_kolossar_light" if kolossar else &"creature_grifalon_fire"): attacker_uid = uid
			elif defender_uid < 0: defender_uid = uid
		check(attacker_uid >= 0 and defender_uid >= 0, "real match has authored creature and opponent")
		if attacker_uid >= 0 and defender_uid >= 0:
			var attacker: CreatureBall = main._spawn_ball(attacker_uid)
			var defender: CreatureBall = main._spawn_ball(defender_uid)
			attacker.freeze_at(Vector3(-Arena.FIG_W*.45, CreatureBall.RADIUS, 0))
			defender.freeze_at(Vector3(Arena.FIG_W*.45, CreatureBall.RADIUS, 0))
			await attacker.open_animated(false)
			await defender.open_animated(false)
			if kolossar:
				await attacker.stage_at(attacker.global_position, defender.global_position)
				await defender.stage_at(defender.global_position, attacker.global_position)
			check(attacker._anim._authored_fullset, "borrowed match actor uses accepted new set")
			var on_contact := func() -> void:
				grifalon_contacts += 1
				check(absf(attacker._anim._attack_progress(attacker._anim._elapsed)-1.0/3.0)<.00001,"real CreatureBall contact is phase one third")
			attacker._anim.strike_contact.connect(on_contact)
			# Same Ball API as ArenaDirector: brace -> contact signal -> target hit.
			defender.brace()
			await attacker.lunge(defender.global_position)
			attacker.hold_impact()
			defender.take_hit(Color.WHITE)
			check(grifalon_contacts == 1, "one contact on real borrowed Grifalon")
			await create_timer(1.6).timeout
			check(attacker._anim._action == &"" and attacker._anim.fx_pos.is_zero_approx(), "new match attack returns without doubled lunge")
			attacker._anim.strike_contact.disconnect(on_contact)
			await main._anim_remove_ball(attacker_uid)
			await main._anim_remove_ball(defender_uid)
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
	main.interaction.clear_request()
	if grifalon or kolossar:
		check((CreatureModels.KolossarMotion.load_count if kolossar else CreatureModels.GrifalonMotion.load_count) == library_loads,"no animation-library loading after menu or during matches")
		check((CreatureModels.KolossarLightSkin.load_count if kolossar else CreatureModels.GrifalonGaleSkin.load_count) == overlay_loads and (CreatureModels.KolossarLightSkin.meshes.size() if kolossar else CreatureModels.GrifalonGaleSkin.meshes.size()) == 1,"no overlay loading or mesh rebuilding after menu")
		check([loader.preparation_count, loader.actor_build_count, loader.arena_build_count] == startup_counts,"no late setup after all borrow/return cycles")
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
		f.store_string(JSON.stringify({"failures":failures,"startup_seconds":startup_seconds,"timings":timings,"grifalon_contacts":grifalon_contacts,"kolossar_mode":kolossar},"  "))
	print("POOL ",JSON.stringify({"failures":failures,"startup_seconds":startup_seconds,"timings":timings,"grifalon_contacts":grifalon_contacts,"kolossar_mode":kolossar}))
	quit(1 if failures else 0)
