extends SceneTree
## Review the fitted Shadow Gorgul through the ordinary Boot and match pool.

const MENU := "res://scenes/menu/main_menu.tscn"
const MATCH := "res://scenes/main.tscn"
const SUBJECT := &"creature_gorgul_shadow"
const STEP := 1.0 / 60.0
const MatchSpec := preload("res://scenes/modes/match_spec.gd")

var checks := 0
var failures := 0
var out_dir := ""
var rendered := false


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		printerr("FAIL: ", label)
		failures += 1


func until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if condition.call():
			return true
	return false


func run() -> void:
	out_dir = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	rendered = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1100, 680)
	var started := Time.get_ticks_msec()
	change_scene_to_file("res://scenes/loading/boot.tscn")
	if not await until(func() -> bool: return current_scene != null and current_scene.scene_file_path == MENU, 180):
		check(false, "Boot reaches the ordinary menu: " + GameLoading.i().last_error)
		await finish({})
		return
	var boot_ms := Time.get_ticks_msec() - started
	var loader := GameLoading.i()
	var counts := [loader.preparation_count, loader.actor_build_count, loader.arena_build_count]
	check(loader.ready_to_play and counts.slice(1) == [134, 3], "complete resident catalog")
	check(not rendered or (Engine.max_fps == 60 and root.unfocusable and root.mode == Window.MODE_MINIMIZED),
		"background 60 FPS window")
	var parked: Array = loader._balls.get(SUBJECT, []).duplicate()
	check(parked.size() == 2, "two Shadow copies before the menu")
	if parked.size() != 2:
		await finish({})
		return
	for element: String in GameData.ATTR_KEYS:
		var id := StringName("creature_gorgul_" + element)
		var path := CreatureModels.GORGUL_SHADOW_MODEL if id == SUBJECT else CreatureModels.HD_DIR % ("gorgul_" + element)
		for copy: CreatureBall in loader._balls[id]:
			check(copy._anim.get_child(0).get_meta("preparation_source").resource_path == path,
				"expected model source for " + element)
	var first: CreatureAnim = parked[0]._anim
	var second: CreatureAnim = parked[1]._anim
	check(first._meshes.size() == 1 and first._meshes[0].mesh.get_surface_count() == 5,
		"one fitted skin with five vertex-colored surfaces")
	check(first._meshes[0].mesh == second._meshes[0].mesh and
		first._player.get_animation_library(&"") == second._player.get_animation_library(&"") and
		first._strike_skeleton != second._strike_skeleton, "shared immutable model and clips, independent pose")
	check(first._flyer and first._support.limbs.size() == 2 and first.get_hover_height() > 0,
		"flyer support and height")
	check(first._strike_skeleton.get_bone_count() == 25 and first._player.get_animation_list() ==
		PackedStringArray(["attack", "hit", "idle", "roar", "stance"]), "25 joints and five legacy clip names")
	var material := first._meshes[0].get_active_material(0) as ShaderMaterial
	check(material.get_shader_parameter("use_vertex_color") and not material.get_shader_parameter("has_texture"),
		"runtime anime shader reads authored vertex colors")
	for ball: CreatureBall in parked:
		check(not ball.visible and ball.process_mode == Node.PROCESS_MODE_DISABLED, "parked actor inactive")

	current_scene._on_play()
	if not await until(func() -> bool: return current_scene != null and current_scene.scene_file_path == MATCH, 15):
		check(false, "ordinary menu opens the match scene")
		await finish({})
		return
	var main := current_scene
	var spec := MatchSpec.new()
	var profile := PlayerProfile.new()
	profile.load_from()
	spec.profiles = [profile.value.duplicate(true), PlayerProfile.npc_profile(2)]
	spec.names = [String(spec.profiles[0].name), String(spec.profiles[1].name)]
	spec.decks = [
		CardDB.build_deck([SUBJECT, &"creature_gorgul_fire", &"creature_gorgul_gale"],
			[&"arena_field_light", &"arena_den_gorgul", &"arena_funnel"],
			[&"ability_fire_drain", &"ability_fire_assault", &"ability_gorgul_gaze"]),
		CardDB.build_deck([SUBJECT, &"creature_gorgul_stone", &"creature_gorgul_tide"],
			[&"arena_field_tide", &"arena_den_gorgul", &"arena_mirror"],
			[&"ability_tide_hush", &"ability_tide_surf", &"ability_gorgul_night"]),
	]
	spec.seed = 151126
	spec.arena_id = 1
	if main.events.drained.is_connected(main._pump):
		main.events.drained.disconnect(main._pump)
	started = Time.get_ticks_msec()
	main.modes._request(spec)
	if not await until(func() -> bool: return main._prepared_balls.size() == 6 and main.ctrl != null and main.ctrl._started, 15):
		check(false, "ordinary match leases both decks")
		await finish({})
		return
	var match_ms := Time.get_ticks_msec() - started
	check([loader.preparation_count, loader.actor_build_count, loader.arena_build_count] == counts,
		"no preparation after Boot")
	var shadows: Array[CreatureBall] = []
	for uid: int in main._prepared_balls:
		var ball: CreatureBall = main._prepared_balls[uid]
		if ball.def.id == SUBJECT:
			shadows.append(ball)
			check(ball in parked and ball.uid == uid and ball.get_parent() == main.world and not ball.visible,
				"original parked Shadow reparented by match with the correct uid")
	check(shadows.size() == 2 and loader._balls[SUBJECT].is_empty(), "both Shadow copies are leased")

	var contact_count := 0
	if not shadows.is_empty():
		main.events.stop()
		main.hud.visible = false
		main.cam.set_process(false)
		Engine.time_scale = 1.0
		contact_count = await verify_reveal(main, shadows[0])
	main._release_game_resources()
	check(loader._balls[SUBJECT].size() == 2 and loader._balls[SUBJECT].all(func(ball): return ball in parked),
		"both original actors returned")
	await finish({"boot_ms": boot_ms, "match_start_ms": match_ms, "contact_count": contact_count})


func verify_reveal(main: Node, reserved: CreatureBall) -> int:
	var ball: CreatureBall = main._spawn_ball(reserved.uid)
	if ball == null:
		check(false, "activate the reserved actor")
		return 0
	var actor := ball._anim
	check(ball == reserved and not ball._shape.disabled and ball._shape.shape is SphereShape3D, "leased actor with its original collider")
	var floor: Vector3 = main.arena.slot_position(2)
	floor.y = 0
	ball.freeze_at(floor + Vector3.UP * CreatureBall.RADIUS)
	ball.global_basis = Basis.from_euler(Vector3(.43, .61, -.27))
	var landing := ball._shell.global_transform
	ball.hold_landing_pose()
	check(ball._shell.global_transform.is_equal_approx(landing) and ball.global_basis.is_equal_approx(Basis.IDENTITY),
		"landing shell retains the physical pose and figure is upright")
	ball._label_allowed = false
	ball.open_animated()
	check(ball._figure.visible and ball._figure.scale.x < .02, "figure grows from the actual landing point")
	var revealed := await until(func() -> bool: return not ball._shell.visible, 5)
	check(revealed and ball.is_figure_shown() and ball._figure.scale.is_equal_approx(Vector3.ONE), "fully revealed")
	check(actor.global_position.y > CreatureBall.RADIUS, "Gorgul hovers over the sphere")
	actor.set_process(false)
	var reveal_position := actor.position
	actor._clock = 0
	actor._phase = 0
	actor.reset()
	actor._player.advance(0.0)
	var player := actor._player
	var skeleton := actor._strike_skeleton
	var wing := skeleton.find_bone("wingtip.R")
	var hand := skeleton.find_bone("hand.R")
	var tail := skeleton.find_bone("tail2")

	if rendered:
		actor.position = reveal_position
		var camera_target := floor + Vector3.UP * actor.get_height() * .75
		main.cam.fov = 45
		var views := [Vector3(0, 0, 2.85), Vector3(2.85, 0, 0), Vector3(1.5, .30, 2.45)]
		var clips := [&"rest", &"idle", &"roar", &"stance", &"attack", &"hit"]
		for clip: StringName in clips:
			seek_clip(player, skeleton, clip, .35 if clip == &"attack" else .45)
			for view: int in views.size():
				var offset: Vector3 = views[view] * actor.get_height()
				main.cam.look_at_from_position(camera_target + offset, camera_target)
				await process_frame
				await process_frame
				save_frame(str(clip) + "-" + str(view))
		var rear := Vector3(1.35, .45, -2.5) * actor.get_height()
		for clip: StringName in [&"roar", &"stance"]:
			seek_clip(player, skeleton, clip, .45)
			main.cam.look_at_from_position(camera_target + rear, camera_target)
			await process_frame
			await process_frame
			save_frame(str(clip) + "-rear")
		var previous_hand := Quaternion.IDENTITY
		for phase: float in [.25, .55, .80]:
			seek_clip(player, skeleton, &"attack", phase)
			var hand_pose := skeleton.get_bone_pose_rotation(hand)
			check(previous_hand.angle_to(hand_pose) > .015, "distinct attack phase " + str(phase))
			previous_hand = hand_pose
			main.cam.look_at_from_position(camera_target + views[2] * actor.get_height(), camera_target)
			await process_frame
			await process_frame
			save_frame("attack-" + str(int(phase * 100)))
	for clip: StringName in [&"idle", &"roar", &"stance", &"attack", &"hit"]:
		seek_clip(player, skeleton, clip, 0.0)
		var beginning := [skeleton.get_bone_pose_rotation(wing), skeleton.get_bone_pose_rotation(hand),
			skeleton.get_bone_pose_rotation(tail)]
		player.seek(player.get_animation(clip).length * .40, true)
		var end := [skeleton.get_bone_pose_rotation(wing), skeleton.get_bone_pose_rotation(hand),
			skeleton.get_bone_pose_rotation(tail)]
		check(beginning[0].angle_to(end[0]) > .01 and beginning[2].angle_to(end[2]) > .01,
			"wing and tail deformations in " + str(clip))
		if clip == &"attack":
			check(beginning[1].angle_to(end[1]) > .02, "claws follow the attack hand")

	actor.reset()
	var contacts: Array[float] = []
	var resolutions: Array[bool] = []
	var on_contact := func() -> void: contacts.append(player.current_animation_position)
	var on_resolution := func(landed: bool) -> void: resolutions.append(landed)
	actor.strike_contact.connect(on_contact)
	actor.strike_resolved.connect(on_resolution)
	ball.lunge(floor + Vector3.FORWARD * 12.0)
	for frame in 120:
		actor._process(STEP)
	check(contacts.size() == 1 and resolutions == [true] and actor._action == &"", "attack contacts once and returns to idle")
	actor.strike_contact.disconnect(on_contact)
	actor.strike_resolved.disconnect(on_resolution)
	ball.close_up()
	check(not ball.is_figure_shown() and ball._shell.visible, "figure closes into the same sphere")
	await ball.open_animated()
	check(ball._anim == actor and ball.is_figure_shown(), "subsequent reveal reuses the fitted actor")
	ball.close_up()
	return contacts.size()


func seek_clip(player: AnimationPlayer, skeleton: Skeleton3D, clip: StringName, phase: float) -> void:
	player.stop()
	player.clear_queue()
	skeleton.reset_bone_poses()
	if clip == &"rest":
		return
	player.play(clip, 0.0)
	player.advance(0.0)
	var time := player.get_animation(clip).length * phase
	player.seek(time, true)
	check(player.current_animation == clip and is_equal_approx(player.current_animation_position, time),
		"sampled requested clip and time " + str(clip) + ": " + str(time))


func save_frame(label: String) -> void:
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(out_dir.path_join(label + ".png")) == OK, "capture " + label)


func finish(result: Dictionary) -> void:
	result.merge({"checks": checks, "failures": failures, "rendered": rendered})
	var report := JSON.stringify(result)
	print("GORGUL TRELLIS ", report)
	var file := FileAccess.open(out_dir.path_join("gorgul-trellis.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(report + "\n")
		file.close()
	var scene := current_scene
	current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	var loader := GameLoading.i()
	loader.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(SoundFx._inst):
		SoundFx._inst.queue_free()
	await process_frame
	quit(1 if failures else 0)
