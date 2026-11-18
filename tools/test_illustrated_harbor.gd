extends "res://tools/autoplay.gd"
## Historical runner name retained; verifies the rebuilt ID3 coastal arena.
## Boots the client, plays the coastal flyby, and uses actual match entry points
## to reach a landed sphere and a visible battle.

var _out: String
var _failures := 0
var _shot_requests := {}
var _rendered_frames := 0


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_lock_fps()
	DeviceSettings.settings_path = _out.path_join("illustrated-interface.cfg")
	DeviceSettings.set_reduce_motion(false)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	_new_match.call_deferred()


func _new_match() -> void:
	_loading = true
	_check(ArenaLocations.CoastalStyle.applies(3) and ArenaLocations.definition(3).name == "Каменная бухта", "ordinary client exposes the rebuilt saved arena 3")
	ArenaLocations.choose(0)
	change_scene_to_file("res://scenes/loading/boot.tscn")
	if not await _wait_for_scene("res://scenes/menu/main_menu.tscn", 180.0):
		_check(false, "Boot opens the main menu")
		_finish(1)
		return
	var catalog := GameLoading.i()
	_check(catalog.ready_to_play and catalog.arena_build_count == 4, "all four arenas are ready before the menu")
	startup_counts = _preparation_counts()
	current_scene._show_modes()
	current_scene._on_play()
	if not await _wait_for_scene("res://scenes/main.tscn", 15.0):
		_check(false, "main menu opens the standard duel")
		_finish(1)
		return
	main = current_scene
	_check(main.team_menu.visible and main.arena.location_id == 0, "ordinary duel keeps the saved Sanctuary")
	main.team_menu._open_arena_picker()
	main.team_menu._arena_picker.select(3)
	_check(main.arena.location_id == 3 and main.arena._decor.has_node("CoastalLandscape/ClearCoastalWater") and main._env.background_mode == Environment.BG_SKY, "fourth arena has resident 3D coast, clear water and real sky")
	_check(main.get_node_or_null("IllustratedHarborCanvas") == null, "painted canvas and flight ink are not instantiated")
	_verify_coast()
	await _capture("picker-1280")
	root.size = Vector2i(960, 540)
	root.content_scale_size = root.size
	await process_frame
	await process_frame
	await _capture("picker-960")
	for button: Button in main.team_menu._arena_picker._buttons:
		_check(button.get_global_rect().end.x <= root.size.x and button.get_global_rect().end.y <= root.size.y, "arena button remains inside the small viewport")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	main.team_menu._arena_picker.select(2)
	_check(main.arena.location_id == 2 and main._env.background_mode == Environment.BG_SKY, "Lunar Harbor retains the standard night environment")
	await _capture("lunar-harbor")
	main.team_menu._arena_picker.cancel()
	_check(main.arena.location_id == 0 and ArenaLocations.current() == 0, "cancel restores saved Sanctuary")
	main.team_menu._open_arena_picker()
	main.team_menu._arena_picker.select(3)
	main.team_menu._arena_picker.confirm()
	ArenaLocations._current = -1
	_check(ArenaLocations.current() == 3 and main.arena.location_id == 3, "confirmed fourth arena survives settings reload")
	main.team_menu._open_arena_picker()
	main.team_menu._arena_picker.select(2)
	main.team_menu._arena_picker.cancel()
	_check(main.arena.location_id == 3 and main.arena._decor.has_node("CoastalLandscape/ClearCoastalWater"), "cancel from night Harbor restores the saved coastal arena")
	var online_script := load("res://scenes/online/online_game.gd")
	var online := Node3D.new()
	online.set_script(online_script)
	_check(online._initial_arena_location() == 0, "online entry chooses Sanctuary despite saved local arena")
	online.free()
	bot = AIPlayer.new(0, 12345)
	main.rng.seed = 551007
	main.team_menu.pick_random_and_start()
	await process_frame
	main.ctrl.creature_selected.connect(func(side: int, uid: int, _recall: bool) -> void:
		throws[side] += 1
		pending_launches[uid] = true)
	main.ctrl.creature_returned.connect(func(uid, reason): _ret(uid, reason))
	main.ctrl.creature_stood.connect(func(uid, _slot) -> void:
		_land(uid, true))
	main.ctrl.battle_started.connect(func(_slot, a, _d) -> void:
		battles += 1
		_land(a, true))
	var intro: LocationIntro = main._location_intro
	if not is_instance_valid(intro):
		_check(false, "the normal match lifecycle starts the Harbor flyby")
		_finish(1)
		return
	while is_instance_valid(intro) and intro.shot_index < 0:
		await process_frame
	_check(not main.ctrl._started and CameraRig.Mode.STATIC == main.cam.mode, "the flyby precedes match control")
	var first_view: Vector3 = main.cam.global_position
	for sample in 2:
		await create_timer(.62, true, false, true).timeout
		await _capture("flyby-%d" % sample)
	_check(main.cam.global_position.distance_to(first_view) > 35.0 and absf(main.cam._roll) > .02 and absf(main.cam._roll) < .07, "camera travels with a gentle bank during the flyby")
	await create_timer(2.1, true, false, true).timeout
	await _capture("flyby-low")
	while is_instance_valid(intro) and intro.shot_index < 2:
		await process_frame
	if is_instance_valid(intro):
		await create_timer(.9, true, false, true).timeout
		_check(is_instance_valid(intro) and intro.title.text == ArenaLocations.definition(3).name and intro.title.modulate.a > .5,
			"arrival shows a readable location title before gameplay")
		await _capture("flyby-arrival")
	if is_instance_valid(intro):
		await intro.completed
	await process_frame
	_check(main.ctrl._started and main.cam.is_overview() and main.hud.visible, "camera returns and the standard duel receives input")
	await create_timer(.8, true, false, true).timeout
	await _capture("arena")
	_loading = false


func _process(_delta: float) -> bool:
	if _loading or _finishing: return false
	match_frames += 1
	if match_frames > 6300:
		_check(false, "a landed throw and battle within the scoped test time")
		_finish(1)
		return false
	var hud: HudUI = main.hud
	if main.director.flying and is_instance_valid(main._active_ball) and main._active_ball.global_position.y > 3.0 and not _shot_requests.has("throw"):
		_check(main.director.flying, "capture samples a real airborne sphere")
		_capture_once("throw")
	if hits[0] + hits[1] > 0 and not main.director.flying and not _shot_requests.has("landed"):
		_capture_once("landed")
	if battles > 0 and hud.own_panel.is_visible_in_tree() and hud.opponent_panel.is_visible_in_tree() 		and hud.own_panel._context_mode == "battle" and hud.opponent_panel._context_mode == "battle" 		and not main.events.is_busy():
		_verify_battle()
		return false
	if hud._reading > 0: hud._skip_flag = true
	if main.battle_overlay._open: main.battle_overlay._close()
	if press_next_turn(main): return false
	var view = main.ctrl.get_view(0)
	if main.setup_panel._panel.visible:
		var action: Dictionary = bot.choose_setup(view, main.ctrl.legal_setup_slots(), main.ctrl.can_skip_gate())
		main.setup_panel.hide_panel()
		if action.is_empty(): main._on_setup_skipped()
		else: main._on_setup_placed(action.card_id, int(action.slot))
	elif hud._creature_panel.visible:
		var action: Dictionary = bot.choose_throw(view)
		target = int(action.target_slot)
		main._on_creature_chosen(int(action.uid))
	elif main._active_ball != null and not main.director.flying and main.ctrl.get_active_player() == 0 and not main.events.is_busy():
		var slots: Array = main._gate_slots()
		if not slots.is_empty(): main._on_slot_picked(target if slots.has(target) else int(slots[0]))
	elif main.ability_panel._panel.visible and main.ctrl.get_ability_moment() == &"after_landing":
		main._on_ability_passed()
	return false


func _verify_battle() -> void:
	_finishing = true
	await _capture("battle")
	_check(hits[0] + hits[1] > 0 and battles > 0, "the physical throw lands and enters battle")
	_check(_shot_requests.has("throw") and _shot_requests.has("landed"), "airborne and landing phases rendered")
	_check(_preparation_counts() == startup_counts, "match reuses Boot resources")
	_check(root.unfocusable and root.mode == Window.MODE_MINIMIZED and Engine.max_fps == 60, "the standard wrapper keeps rendering unfocused and capped at 60 FPS")
	var previous := main
	main.game_over_ui.restart_requested.emit()
	_check(await _wait_for_scene("res://scenes/main.tscn", 15.0, previous), "restart returns to the ordinary team menu")
	main = current_scene
	_check(main.team_menu.visible and main.arena.location_id == 3 and main.arena._decor.has_node("CoastalLandscape/ClearCoastalWater"), "restart preserves selected arena and 3D coast")
	_check(_preparation_counts() == startup_counts, "restart reuses all four prepared arenas and actors")
	main._leave_duel_to_menu()
	_check(await _wait_for_scene("res://scenes/menu/main_menu.tscn", 15.0), "return from duel reaches the main menu")
	_check(GameLoading.i()._arenas.size() == 4, "exit returns all four arenas to Boot catalog")
	print("COASTAL ARENA rendered=", _rendered_frames, " hits=", hits, " battles=", battles, " failures=", _failures)
	_finish(1 if _failures else 0)


func _capture_once(name: String) -> void:
	_shot_requests[name] = true
	_capture(name)


func _verify_coast() -> void:
	var landscape: Node3D = main.arena._decor.get_node("CoastalLandscape")
	var water: MeshInstance3D = landscape.get_node("ClearCoastalWater/RefractiveSea")
	var bed: MeshInstance3D = landscape.get_node("OpaqueSubmergedShelf")
	_check(water.position.y == -4.5 and bed.mesh != null and bed.material_override != null, "real opaque shelf shares coastal sea coordinates")
	var positions: PackedVector3Array = bed.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var shallow := 0
	var deep := 0
	for p in positions:
		if p.y < water.position.y and p.y > water.position.y-3.0: shallow += 1
		if p.y < water.position.y-10.0: deep += 1
	_check(shallow > 100 and deep > 100, "submerged shelf contains real shallow and deep 3D vertices")
	var floor_shape: BoxShape3D = main.arena.get_node("Floor").get_child(0).shape
	_check(floor_shape.size == Vector3(280,1,280) and main.arena.markers.size() == 6, "original physical floor and all six gate markers remain")


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame.save_png(_out.path_join(name + ".png")) == OK, "save rendered " + name)
	_rendered_frames += 1


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS " + label)
	else:
		_failures += 1
		printerr("FAIL: " + label)
