extends SceneTree
## Client-side gate snapshots, replayed flight and reused actors, with Boot's real catalog.
const Online := preload("res://scenes/online/online_game.gd")
const REPLAY_SLOT := 4
const HARBOR := 2
const ELEMENTS := ["gale", "tide", "light", "stone"]

var checks := 0
var failures := 0
var output := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless" or not has_meta("sfery_background_draw"):
		_check(false, "requires the minimized graphical wrapper")
		quit(1)
		return
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	GraphicsSettings.force_level(GraphicsSettings.Level.MEDIUM)
	GraphicsSettings.max_fps = 60
	root.size = Vector2i(960, 540)
	change_scene_to_file("res://scenes/loading/boot.tscn")
	if not await _until(func() -> bool: return current_scene is MainMenu, 90.0):
		_check(false, "Boot completed: " + GameLoading.i().last_error)
		quit(1)
		return
	var catalog := GameLoading.i()
	catalog.show_game()
	await process_frame
	var local := current_scene
	local.team_menu._preview.release()
	local.team_menu.hide()
	local.ui_layer.hide()
	Engine.time_scale = 1.0
	_check_particle_budgets(local.world, catalog)
	await _capture_flights(local, catalog)
	local._release_game_resources()
	catalog.show_online()
	await process_frame
	var online := current_scene as Online
	var card := await _check_gate(online)
	if is_instance_valid(card):
		await _check_replay(online, card, catalog)
	_check(Engine.max_fps == 60 and root.mode == Window.MODE_MINIMIZED and root.unfocusable,
		"wrapped test remains minimized, unfocusable and limited to 60 FPS")
	online._return_to_lobby()
	online.queue_free()
	await process_frame
	catalog.queue_free()
	await process_frame
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	for frame in 5: await process_frame
	print("MATCH FX: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _check_particle_budgets(world: Node3D, catalog: GameLoading) -> void:
	var id := &"creature_dragnar_fire"
	var previous: CreatureBall
	for level: int in [GraphicsSettings.Level.LOW, GraphicsSettings.Level.HIGH,
			GraphicsSettings.Level.MEDIUM, GraphicsSettings.Level.LOW]:
		GraphicsSettings.force_level(level)
		var scale := BallFx.level_k()
		var expected := [roundi(30 * scale), maxi(24, int(90 * scale))]
		var ball := catalog.take_ball(id, 1000, Vector3(0.0, 1.18, 32.0))
		_check(previous == null or ball == previous, "same ball leased at quality %d" % level)
		ball.reparent(world, false)
		ball.launch_towards(Vector3.ZERO)
		print("FX quality %d: %d sparks and %d marks" % [level, ball._sparks.amount, ball._streak.amount])
		_check([ball._sparks.amount, ball._streak.amount] == expected, "current quality sets both emitter budgets")
		catalog.return_ball(ball)
		_check(not is_instance_valid(ball._flight_trail) and not ball._streak.emitting and not ball._sparks.emitting,
			"return to storage clears the trail and ground emissions")
		previous = ball
	GraphicsSettings.force_level(GraphicsSettings.Level.MEDIUM)


func _capture_flights(game: Node, catalog: GameLoading) -> void:
	for location in [ArenaLocations.CANYON, HARBOR]:
		game._preview_arena_location(location, false)
		for frame in 4: await process_frame
		for element: String in ELEMENTS:
			var start := Vector3(0, 1.18, 32.0)
			var target: Vector3 = game.arena.slot_position(0)
			var ball := catalog.take_ball(StringName("creature_dragnar_" + element), 1000, start)
			ball.reparent(game.world, false)
			ball.launch_towards(target)
			game.cam.follow_throw(ball, target - start)
			var sampled := await _until(func() -> bool: return ball._t >= .433, 2.0)
			_check(sampled and ball._flight_trail._mesh_visible and game.cam.is_position_in_frustum(ball._shell_center()),
				"%s flight arc visible at the comparison phase in arena %d" % [element, location])
			await _capture("flight-%d-%s" % [location, element])
			catalog.return_ball(ball)
			for frame in 3: await process_frame


func _check_gate(game: Online) -> ArenaCardNode:
	var view: MatchState = game.ctrl.state.duplicate_full()
	view.phase = MatchController.Phase.SETUP
	view.active_player = 1
	var gate := view.slots[REPLAY_SLOT]
	gate.has_card = true
	gate.card_owner = 0
	gate.card_id = &"arena_field_fire"
	_send_state(game, view)
	if not await _until(func() -> bool: return not game.events.is_busy(), 12.0):
		_check(false, "closed gate placement completed")
		return null
	var card: ArenaCardNode = game.card_nodes[REPLAY_SLOT]
	var position_on_field := card.global_position
	gate.revealed = true
	_send_state(game, view)
	await create_timer(.16).timeout
	var flip := card._reveal_tw
	_check(flip != null and flip.is_running() and absf(card._visuals.rotation.z) > .1, "first opening flips the gate")
	_check(_gate_surface_is_fixed(card, position_on_field), "first opening keeps the fixed surface")
	view.turn += 1
	_send_state(game, view)
	_send_state(game, view)
	await process_frame
	_check(card._reveal_tw == flip, "same gate snapshots during the flip keep one animation")
	_check(_gate_surface_is_fixed(card, position_on_field), "repeated snapshot during opening retains collision")
	await create_timer(.45).timeout
	_check(card._visuals.transform.is_equal_approx(Transform3D.IDENTITY), "first opening restores the visual rest pose")
	await create_timer(.90).timeout
	view.turn += 1
	_send_state(game, view)
	await create_timer(.26).timeout
	_check(card._reveal_tw == flip and card._visuals.transform.is_equal_approx(Transform3D.IDENTITY),
		"later turn for the same open gate stays flat")
	_check(_gate_surface_is_fixed(card, position_on_field), "later turn retains the surface and collider")
	await _capture("online-open-gate-later-turn")
	gate.revealed = false
	gate.card_id = &"arena_field_tide"
	_send_state(game, view)
	gate.revealed = true
	_send_state(game, view)
	await create_timer(.30).timeout
	_check(card._reveal_tw != flip and card._revealed_card_id == gate.card_id and is_instance_valid(card._reveal_fx),
		"a new gate id can open and play its own effect")
	gate.revealed = false
	_send_state(game, view)
	await process_frame
	_check(card._revealed_card_id == &"" and card._visuals.transform.is_equal_approx(Transform3D.IDENTITY) \
		and int(card._mat.get_shader_parameter("frame")) == CardView.Frame.BACK and not is_instance_valid(card._reveal_fx),
		"authoritative facedown snapshot cancels the old flip, face and light")
	_check(_gate_surface_is_fixed(card, position_on_field), "closing a replaced gate leaves a usable raised surface")
	return card


func _gate_surface_is_fixed(card: ArenaCardNode, field_position: Vector3) -> bool:
	return card.global_position.is_equal_approx(field_position) and card.is_in_group("gate_surfaces") \
		and card._field_body.collision_layer == 1 and is_equal_approx(card.surface_height_at(field_position),
			field_position.y + ArenaCardNode.SURFACE_Y)


func _send_state(game: Online, view: MatchState) -> void:
	game._message({"t": "state", "player": 0, "view": OnlineStateCodec.encode_view(view.duplicate_view(0)),
		"battle_serial": 0, "selected_uid": -1, "busy": false, "preview": {},
		"winner": -2, "legal": {}, "reason": ""})


func _check_replay(game: Online, card: ArenaCardNode, catalog: GameLoading) -> void:
	var ball: CreatureBall = game.balls[0]
	var points := _flight_samples(card.global_position)
	var flight := {"t": "flight", "uid": 0, "owner": 0, "slot": -1, "duration": float(points.size() - 1) / 60.0, "samples": points,
		"position": points[-1].slice(0, 3), "quaternion": points[-1].slice(3, 7),
		"bounces": 1, "timed_out": false, "target_slot": REPLAY_SLOT}
	var contacts: Array[Vector3] = []
	ball.surface_bounced.connect(func(point: Vector3, _speed: float) -> void: contacts.append(point))
	game._message(flight)
	await create_timer(.41).timeout
	var trail := ball._flight_trail
	_check(is_instance_valid(trail) and trail.get_parent() == ball._shell and trail._mesh_visible,
		"recorded shot attaches and samples the resident ribbon")
	_check(ball.freeze and not ball.physical_shot and ball.linear_velocity.is_zero_approx(),
		"replay leaves physics frozen")
	_check(game.cam.is_position_in_frustum(ball._shell_center()), "the replay pursuit keeps the moving shell in frame")
	await _capture("online-flight-airborne")
	_check(await _until(func() -> bool: return ball._streak.emitting, 1.2), "roll marks emit on the recorded ground segment")
	_check(contacts.size() == 1, "the path produces one impact at the recorded bounce")
	_check(not trail._active and not trail.visible, "resident flight trail switches off during rolling")
	_check(ball._sparks.emitting and ball._streak.global_position.y > card.surface_height_at(ball.global_position),
		"recorded movement emits sparks and puts marks above the card")
	var mark := ball._streak.mesh as PlaneMesh
	var material := mark.material as StandardMaterial3D
	_check(mark.size.is_equal_approx(Vector2.ONE * CreatureBall._shell_r() * 3.2),
		"roll marks use the size of the visible shell")
	_check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
		and material.blend_mode == BaseMaterial3D.BLEND_MODE_MIX,
		"roll marks keep their soft edges and color when they overlap")
	await _capture("online-flight-rolling")
	_check(await _until(func() -> bool: return not game.events.is_busy(), 3.0), "flight queue drains after miss")
	var last: Array = points[-1]
	var last_rotation := Quaternion(last[3], last[4], last[5], last[6])
	_check(not is_instance_valid(ball._flight_trail) and not ball._sparks.emitting and not ball._streak.emitting \
		and trail.get_parent() == catalog._flight_trails and trail._history_count == 0,
		"stopping returns the resident trail and stops ground emission")
	_check(ball.global_position.is_equal_approx(Vector3(last[0], last[1], last[2])) \
		and ball._shell.global_basis.orthonormalized().get_rotation_quaternion().angle_to(last_rotation) < .001,
		"last recorded position and shell orientation are preserved")
	_send_state(game, game.ctrl.state)
	_check(await _until(game.cam.is_overview, 1.0), "the next gameplay snapshot restores the overview camera")
	game._message(flight)
	var resumed := await _until(func() -> bool: return ball._flight_trail == trail and trail._mesh_visible, 1.0)
	_check(resumed, "the next replay samples the same resident trail")
	game._disconnected("Local test disconnect")
	_check(await _until(func() -> bool: return not game._cleaning_match, 3.0), "disconnect drains the active replay")
	_check(trail.get_parent() == catalog._flight_trails and not trail._active and trail._history_count == 0 \
		and not ball._replaying_shot and not ball._streak.emitting and game.balls.is_empty(),
		"disconnect parks the actor and clears the trail")


func _flight_samples(center: Vector3) -> Array:
	var points: Array = []
	for i in 97:
		var y := center.y + ArenaCardNode.SURFACE_Y + CreatureBall.RADIUS
		if i <= 45:
			y += (45 - i) * (.0173 + i * .006)
		elif i < 68:
			y += .0039 * (i - 45) * (68 - i)
		var air_frames := float(mini(i, 68))
		var roll_frames := float(maxi(i - 68, 0))
		var z := center.z + 16.0 - .26 * air_frames - (.24 * roll_frames - .0042 * roll_frames * roll_frames)
		var q := Quaternion(Vector3.RIGHT, float(i) * .03)
		points.append([center.x, y, z, q.x, q.y, q.z, q.w])
	return points


func _until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return predicate.call()


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "saved " + name)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
