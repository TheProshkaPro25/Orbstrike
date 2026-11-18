extends SceneTree
## The real client Boot and match use two ready copies of every elemental Ratnik.

const STEP := 1.0 / 60.0
const MatchSpec := preload("res://scenes/modes/match_spec.gd")
const RATNIK_PREFIX := "creature_ratnik_"
var checks := 0
var failures := 0
var out_dir := "user://ratnik-trellis"
var rows: Dictionary = {}
var visual := false
var solver_ids: Dictionary = {}
var cloth_samples: Dictionary = {}
var guard_samples: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)


func wait_scene(path: String, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if current_scene != null and current_scene.scene_file_path == path:
			return true
		await process_frame
	return false


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	visual = DisplayServer.get_name() != "headless"
	if visual: root.size = Vector2i(1100, 680)
	var started := Time.get_ticks_msec()
	change_scene_to_file("res://scenes/loading/boot.tscn")
	if not await wait_scene("res://scenes/menu/main_menu.tscn", 180.0):
		check(false, "Boot reaches the ordinary main menu")
		await finish({})
		return
	var loader := GameLoading.i()
	var boot_ms := Time.get_ticks_msec() - started
	print("Ratnik Boot reached menu in ", boot_ms, " ms")
	check(loader.ready_to_play and loader.actor_build_count == 134 and loader.arena_build_count == ArenaLocations.LOCATIONS.size(),
		"resident catalog holds 67 × 2 actors and all arenas")
	var counts := [loader.preparation_count, loader.actor_build_count, loader.arena_build_count]
	var shared_meshes: Dictionary = {}
	var atlases: Dictionary = {}
	var libraries: Dictionary = {}
	var actor_ids: Dictionary = {}
	var simulations: Dictionary = {}
	var ids: Array[StringName] = []
	for element in GameData.ATTR_KEYS:
		var id := StringName(RATNIK_PREFIX + element)
		ids.append(id)
		var parked: Array = loader._balls.get(id, [])
		var copies := parked.duplicate()
		for reference: WeakRef in loader._leased.values():
			var borrower := reference.get_ref() as CreatureBall
			if borrower != null and borrower.def.id == id:
				copies.append(borrower)
		check(copies.size() == 2, "two preloaded copies including an active preview " + element)
		for ball: CreatureBall in copies:
			actor_ids[ball.get_instance_id()] = true
			var actor := ball._anim
			var model := actor.get_child(0)
			check(actor._authored_fullset and actor._authored_grounded and actor._tempo == 1.0, "native grounded set " + element)
			check(model.get_meta("preparation_source").resource_path == CreatureModels.RATNIK_MODEL, "new GLB " + element)
			check(actor._meshes.size() == 2, "only the two authored display meshes " + element)
			var solver: Node = actor._cloth
			if RenderingServer.get_rendering_device() == null:
				check(solver == null, "native cape without compute renderer " + element)
			elif solver != null:
				check(solver._gpu_init_done and solver.output_skin_delta and solver._particle_count == 567,
					"GPU correction follows the native skin on the simulation grid " + element)
				check(solver._collider_count == 1 and not solver._collider_tris.is_empty(),
					"active floor and skinned body collision " + element)
				var bind_names := PackedStringArray()
				for bind: int in CreatureCloth.GRID_DATA.get_meta("binds"):
					bind_names.append(solver._skeleton_node.get_bone_name(solver._bind_to_bone[bind]))
				check(bind_names == PackedStringArray(["chest", "cape1", "cape2", "cape3"]),
					"proxy binds resolve to the four original joints " + element)
				check(solver._positions_buffer.is_valid() and not simulations.has(solver._positions_buffer),
					"independent mutable state per actor " + element)
				simulations[solver._positions_buffer] = true
				solver_ids[ball.get_instance_id()] = solver_identity(solver)
			else:
				check(false, "loaded GPU solver " + element)
			check(actor._player.get_animation_list() == PackedStringArray(["attack", "hit", "idle", "roar", "stance"]), "five native clips " + element)
			libraries[actor._player.get_animation_library(&"")] = true
			for mesh in actor._meshes:
				shared_meshes[mesh.mesh] = true
				for surface in mesh.mesh.get_surface_count():
					var material := mesh.get_active_material(surface) as ShaderMaterial
					if solver != null and mesh.name == &"RatnikCape":
						check(material.get_shader_parameter("positions_tex") == solver._positions_tex,
							"both cape materials get the correction texture " + element)
					var atlas := material.get_shader_parameter("color_map") as Texture2D
					if atlas == null: continue
					atlases[atlas] = true
					check(atlas.resource_path.ends_with("/" + element + ".png"), "authored atlas " + element)
			if ball in parked:
				check(not ball.visible and ball.process_mode == Node.PROCESS_MODE_DISABLED, "parked without processing " + element)
			else:
				check(loader._game.team_menu.is_ancestor_of(ball), "leased to the prewarmed team preview " + element)
	check(actor_ids.size() == 12 and shared_meshes.size() == 2 and libraries.size() == 1 and atlases.size() == 6,
		"twelve live actors share rig/mesh/curves and use six atlases")
	var video_bytes := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	print("Ratnik resident source/curve/atlas check complete")
	current_scene._on_play()
	if not await wait_scene("res://scenes/main.tscn", 15.0):
		check(false, "ordinary menu opens the prepared game scene")
		await finish({})
		return
	var main := current_scene
	var spec := MatchSpec.new()
	var profile := PlayerProfile.new()
	profile.load_from()
	spec.profiles = [profile.value.duplicate(true), PlayerProfile.npc_profile(2)]
	spec.names = [String(spec.profiles[0].name), String(spec.profiles[1].name)]
	spec.decks = [
		CardDB.build_deck(ids.slice(0, 3), [&"arena_field_light", &"arena_den_ratnik", &"arena_funnel"],
			[&"ability_fire_drain", &"ability_fire_assault", &"ability_ratnik_oath"]),
		CardDB.build_deck(ids.slice(3, 6), [&"arena_field_tide", &"arena_den_ratnik", &"arena_mirror"],
			[&"ability_tide_hush", &"ability_tide_surf", &"ability_ratnik_oath"]),
	]
	spec.seed = 151126
	spec.arena_id = 1
	if main.events.drained.is_connected(main._pump): main.events.drained.disconnect(main._pump)
	main.modes._request(spec)
	var lease_started := Time.get_ticks_msec()
	var deadline := lease_started + 15000
	while main._prepared_balls.size() < 6 and Time.get_ticks_msec() < deadline:
		await process_frame
	var lease_ms := Time.get_ticks_msec() - lease_started
	check(main._prepared_balls.size() == 6, "match preparation leases all six elemental Ratnik actors")
	var reserved: Dictionary = main._prepared_balls.duplicate()
	for uid: int in reserved:
		var ball: CreatureBall = reserved[uid]
		check(actor_ids.has(ball.get_instance_id()) and ball.uid == uid and ball.get_parent() == main.world,
			"original actor, assigned uid and match reparent " + String(ball.def.id))
		check(not ball.visible and ball.process_mode == Node.PROCESS_MODE_DISABLED, "inactive match reserve " + String(ball.def.id))
		check_solver(ball, "leased")
	check([loader.preparation_count, loader.actor_build_count, loader.arena_build_count] == counts, "no second preparation after menu")
	while (main.ctrl == null or not main.ctrl._started) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(main.ctrl != null and main.ctrl._started, "ordinary match lifecycle starts")
	main.events.stop()
	main.cam.set_process(false)
	main.hud.visible = false
	Engine.time_scale = 1.0
	for uid: int in reserved:
		await verify_actor(main, uid, reserved[uid])
	var battle := await verify_battle(main)
	main._release_game_resources()
	for element in GameData.ATTR_KEYS:
		var id := StringName(RATNIK_PREFIX + element)
		check(loader._balls[id].size() == 2, "match release returns both copies " + element)
		for ball: CreatureBall in loader._balls[id]:
			check_solver(ball, "returned")
	await finish({"boot_ms": boot_ms, "lease_ms": lease_ms, "resident_video_bytes": video_bytes,
		"actor_count": loader.actor_build_count, "arena_count": loader.arena_build_count,
		"distinct_meshes": shared_meshes.size(), "distinct_atlases": atlases.size(), "distinct_libraries": libraries.size(),
		"battle": battle, "cloth_samples": cloth_samples})


func solver_identity(solver: Node) -> Array:
	return [solver.get_instance_id(), solver._positions_buffer, solver._positions_img_rid]


func check_solver(ball: CreatureBall, phase: String) -> void:
	if RenderingServer.get_rendering_device() == null:
		return
	var solver: Node = ball._anim._cloth
	check(solver != null and solver._gpu_init_done and solver_ids.get(ball.get_instance_id()) == solver_identity(solver),
		"same solver and GPU buffers " + String(ball.def.id) + " " + phase)


func read_vector(bytes: PackedByteArray, offset: int) -> Vector3:
	return Vector3(bytes.decode_float(offset), bytes.decode_float(offset + 4), bytes.decode_float(offset + 8))


func sample_cloth(ball: CreatureBall, phase: String) -> void:
	var solver: Node = ball._anim._cloth
	if solver == null or not solver._gpu_init_done:
		return
	var world: Transform3D = solver._ref_node.global_transform
	var readback := []
	RenderingServer.call_on_render_thread(func() -> void:
		readback.append(solver._rd.buffer_get_data(solver._positions_buffer))
		readback.append(solver._rd.buffer_get_data(solver._skinned_targets_buffer))
		readback.append(solver._rd.texture_get_data(solver._positions_img_rid, 0))
		readback.append(solver._rd.buffer_get_data(solver._collider_tri_buffer)))
	while readback.size() != 4: await process_frame
	var positions: PackedByteArray = readback[0]
	var targets: PackedByteArray = readback[1]
	var offsets: PackedByteArray = readback[2]
	var body: PackedByteArray = readback[3]
	check(positions.size() == solver._particle_count * 16 and targets.size() == positions.size()
		and offsets.size() == positions.size(), "GPU positions, targets and sampled offsets populated " + phase)
	if offsets.size() != positions.size():
		return
	var max_delta := 0.0
	var max_pin_error := 0.0
	var max_output_error := 0.0
	var min_world_y := INF
	var pins := 0
	var crossings := 0
	var max_crossing := 0.0
	var triangles := PackedVector3Array()
	for offset in range(0, body.size(), 16):
		triangles.append(read_vector(body, offset))
	for i: int in solver._particle_count:
		var idx := i * 16
		var position := read_vector(positions, idx)
		var target := read_vector(targets, idx)
		var delta := position - target
		max_delta = maxf(max_delta, delta.length())
		max_output_error = maxf(max_output_error, delta.distance_to(read_vector(offsets, idx)))
		min_world_y = minf(min_world_y, (world * position).y)
		if positions.decode_float(idx + 12) == 0.0:
			pins += 1
			max_pin_error = maxf(max_pin_error, delta.length())
		elif delta.length_squared() > .000004:
			for j in range(0, triangles.size(), 3):
				var contact: Variant = Geometry3D.segment_intersects_triangle(target, position,
					triangles[j], triangles[j + 1], triangles[j + 2])
				if contact is Vector3:
					crossings += 1
					max_crossing = maxf(max_crossing, position.distance_to(contact))
	check(pins > 60 and max_pin_error < .00001, "attached edge matches the skinned pose " + phase)
	check(max_delta > .002 and max_delta <= .0551 and max_output_error < .000001,
		"sampled texture holds only bounded nonzero simulation offsets " + phase)
	check(min_world_y > -.001, "simulated cloth clears the floor " + phase)
	check(crossings == 0, "correction stays on the native side of the body collision proxy " + phase
		+ ": " + str(max_crossing))
	cloth_samples[phase] = {"max_delta": max_delta, "pinned_particles": pins, "max_pin_error": max_pin_error,
		"max_output_error": max_output_error, "min_world_y": min_world_y,
		"collider_triangles": solver._collider_tris.size(), "position_bytes": positions.size(),
		"proxy_crossings": crossings, "max_segment_past_proxy": max_crossing}


func capture_cape(ball: CreatureBall, camera: Camera3D, floor: Vector3, label: String) -> void:
	var actor := ball._anim
	var solver: Node = actor._cloth
	if not visual or solver == null:
		return
	var process := actor.is_processing()
	var previous := camera.global_transform
	var fov := camera.fov
	var hud: CanvasLayer = current_scene.ui_layer
	var hud_was_visible := hud.visible
	var facing := ball._figure.global_basis.z.normalized()
	actor.set_process(false)
	solver.set_process(false)
	hud.hide()
	camera.fov = 36
	camera.look_at_from_position(floor - facing * 29.0 + Vector3(9.0, 11.0, 0), floor + Vector3.UP * 7.1)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(label + "-gpu.png"))
	for material: ShaderMaterial in solver.deformation_materials:
		material.set_shader_parameter("gpu_driven", false)
		var rim := material.next_pass as ShaderMaterial
		if rim != null: rim.set_shader_parameter("gpu_driven", false)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(label + "-native.png"))
	for material: ShaderMaterial in solver.deformation_materials:
		material.set_shader_parameter("gpu_driven", true)
		var rim := material.next_pass as ShaderMaterial
		if rim != null: rim.set_shader_parameter("gpu_driven", true)
	camera.global_transform = previous
	camera.fov = fov
	hud.visible = hud_was_visible
	solver.set_process(true)
	actor.set_process(process)


func verify_actor(main: Node, uid: int, reserved: CreatureBall) -> void:
	var ball: CreatureBall = main._spawn_ball(uid)
	if ball == null:
		check(false, "activate reserved Ratnik " + String(reserved.def.id))
		return
	var actor := ball._anim
	var element := String(ball.def.id).trim_prefix(RATNIK_PREFIX)
	var skeleton := actor._strike_skeleton
	var hand := skeleton.find_bone("hand.R")
	var sword := skeleton.find_bone("sword")
	var foot := skeleton.find_bone("foot.R")
	var cape := skeleton.find_bone("cape3")
	var support = actor._support
	var floor: Vector3 = main.arena.slot_position(2)
	floor.y = 0.0
	ball.freeze_at(floor + Vector3.UP * CreatureBall.RADIUS)
	ball.global_basis = Basis.from_euler(Vector3(.43, .61, -.27))
	var landing := ball._shell.global_transform
	ball.hold_landing_pose()
	check(ball._shell.global_transform.is_equal_approx(landing) and ball.global_basis.is_equal_approx(Basis.IDENTITY),
		"physical shell orientation retained while figure stands upright " + element)
	ball._figure.rotation.y = 0.65
	ball._label_allowed = false
	ball.open_animated()
	check(ball == reserved and ball._figure.visible and ball._figure.scale.x < .02, "activation and growth use leased instance " + element)
	var opening_deadline := Time.get_ticks_msec() + 5000
	var opening_frames := 0
	var opening_started := Time.get_ticks_usec()
	while ball._shell.visible and Time.get_ticks_msec() < opening_deadline:
		await process_frame
		opening_frames += 1
	var reveal_ms := (Time.get_ticks_usec() - opening_started) / 1000.0
	check(ball.is_figure_shown() and ball._figure.scale.is_equal_approx(Vector3.ONE) and not ball._shell.visible,
		"fully revealed at nominal scale " + element)
	check_solver(ball, "opened")
	if actor._cloth != null:
		for material: ShaderMaterial in actor._cloth.deformation_materials:
			var rim := material.next_pass as ShaderMaterial
			check(rim != null and rim.get_shader_parameter("positions_tex") == actor._cloth._positions_tex,
				"match owner rim follows each cape material " + element)
	if element == "light" and actor._cloth != null:
		await sample_cloth(ball, "opened")
		await capture_cape(ball, main.cam, floor, "cape-open")
	check(skeleton.get_bone_parent(sword) == hand and cape >= 0, "sword in right hand and animated cape " + element)
	check(actor.get_height() >= CreatureModels.MIN_HEIGHT and actor.get_height() <= CreatureModels.MAX_HEIGHT * 1.001,
		"normalized height in arena envelope " + element)
	check(support.limbs.size() == 2 and not support.limbs[1].sole.is_empty() and support.limbs[1].side == "R",
		"both soles found under live skinned meshes " + element)

	actor.set_process(false)
	if element == "light":
		await verify_guard(ball, main, floor)
	actor._clock = 0.0
	actor._phase = 0.0
	actor.reset()
	actor._player.advance(0.0)
	var contacts: Array[float] = []
	var contact_pose: Array[Vector3] = []
	var resolved: Array[bool] = []
	var on_contact := func() -> void:
		contacts.append(actor._player.current_animation_position)
		contact_pose.append(skeleton.to_global(skeleton.get_bone_global_pose(foot).origin))
	var on_resolution := func(landed: bool) -> void: resolved.append(landed)
	actor.strike_contact.connect(on_contact)
	actor.strike_resolved.connect(on_resolution)
	var forward := ball._figure.global_basis.z.normalized()
	ball.lunge(floor + forward * 16.0, .46 if element == "shadow" else 0.0)
	actor._process(0.0)
	var start := skeleton.to_global(skeleton.get_bone_global_pose(foot).origin)
	var grip := skeleton.get_bone_global_pose(hand).affine_inverse() * skeleton.get_bone_global_pose(sword)
	var start_cape := skeleton.get_bone_pose_rotation(cape)
	var contact_time := actor._contact_time
	for frame in floori(contact_time / STEP):
		actor._process(STEP)
	if contacts.is_empty(): actor._process(contact_time - actor._elapsed)
	if contacts.is_empty(): actor._process(.000001)
	check(contacts.size() == 1 and resolved == [true], "one contact and resolution " + element)
	if contacts.is_empty():
		ball.close_up()
		return
	var moved := (contact_pose[0] - start).dot(forward)
	var model := actor.get_child(0)
	var normalized_step: float = moved / float(model.get_meta("normalization_scale"))
	var ground_error: float = absf(support._sole_height(support.limbs[1]) - floor.y)
	check(absf(contacts[0] - .4) < .017 and absf(normalized_step - .292) < .03,
		"native contact phase and forward step " + element + ": %s / %s" % [contacts[0], normalized_step])
	check(ground_error < actor.get_height() * .006, "right sole planted at contact after reparent " + element + ": " + str(ground_error))
	check(grip.is_equal_approx(skeleton.get_bone_global_pose(hand).affine_inverse() * skeleton.get_bone_global_pose(sword)),
		"rigid right-hand grip through swing " + element)
	var cape_turn := start_cape.angle_to(skeleton.get_bone_pose_rotation(cape))
	check(cape_turn > .01, "cape has rotated at contact " + element)
	if visual:
		main.cam.fov = 46
		main.cam.look_at_from_position(floor + forward * 30.0 + Vector3(-16, 13, 0), floor + Vector3.UP * 7.5)
		await process_frame
		await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(out_dir.path_join(element + "-contact.png"))

	actor.hold_impact(.055)
	var stopped := actor._player.current_animation_position
	actor._process(STEP)
	check(is_equal_approx(actor._player.current_animation_position, stopped), "hitstop freezes the posed swing " + element)
	var max_cape_turn := cape_turn
	for frame in 22:
		actor._process(STEP)
		max_cape_turn = maxf(max_cape_turn, start_cape.angle_to(skeleton.get_bone_pose_rotation(cape)))
	check(actor._player.current_animation_position > .50, "native swing continues after contact " + element)
	check(max_cape_turn > cape_turn + .015, "cape continues the authored swing after contact " + element)
	for frame in 60: actor._process(STEP)
	check(contacts.size() == 1 and resolved == [true], "no repeated contact " + element)
	actor.strike_contact.disconnect(on_contact)
	actor.strike_resolved.disconnect(on_resolution)
	ball.close_up()
	check(not ball._figure.visible and ball._shell.visible and not ball._landing_shell_held, "ball folds into closed shell " + element)
	var repeat_reveal_ms := 0.0
	if element == "light":
		await process_frame
		var repeat_started := Time.get_ticks_usec()
		var reopened := ball.open_animated()
		check(ball._anim == actor and ball._figure.visible and ball._figure.scale.x < .02, "second reveal reuses the model")
		await reopened
		repeat_reveal_ms = (Time.get_ticks_usec() - repeat_started) / 1000.0
		check_solver(ball, "reopened")
		ball.close_up()
	rows[element] = {"height": actor.get_height(), "normalized_step": normalized_step, "right_sole_world_error": ground_error,
		"contact_time": contact_time, "clip_contact_time": contacts[0], "cape_turn_radians": cape_turn,
		"reveal_frames": opening_frames, "reveal_elapsed_ms": reveal_ms,
		"reveal_mean_frame_ms": reveal_ms / maxf(opening_frames, 1)}
	if repeat_reveal_ms > 0.0: rows[element].repeat_reveal_ms = repeat_reveal_ms
	print("Ratnik ", element, " ", rows[element])


func verify_guard(ball: CreatureBall, main: Node, floor: Vector3) -> void:
	var actor := ball._anim
	var camera: Camera3D = main.cam
	var ui_was_visible: bool = main.ui_layer.visible
	if visual:
		var forward := ball._figure.global_basis.z.normalized()
		camera.fov = 48
		camera.look_at_from_position(floor + forward * 33.0 + Vector3(-15, 11, 0), floor + Vector3.UP * 7.0)
		main.ui_layer.hide()
	var skeleton := actor._strike_skeleton
	var sword := skeleton.find_bone("sword")
	var feet := [skeleton.find_bone("foot.R"), skeleton.find_bone("foot.L")]
	var model_scale: float = actor.get_child(0).get_meta("normalization_scale")
	for clip in [&"stance", &"idle"]:
		actor._clock = 0.0
		actor._phase = 0.0
		actor.reset()
		actor._player.advance(0.0)
		if clip == &"stance":
			actor.appear()
			actor._process(0.0)
		var first := skeleton.get_bone_global_pose(sword).basis.get_rotation_quaternion()
		var previous := first
		var start_feet: Array[Vector3] = []
		for foot: int in feet:
			start_feet.append(skeleton.get_bone_global_pose(foot).origin)
		var max_swing := 0.0
		var max_frame_turn := 0.0
		var max_foot_slide := 0.0
		var max_sole_error := 0.0
		var length := actor._player.get_animation(clip).length
		var count := roundi(length / STEP)
		for frame in range(1, count + 1):
			actor._process(STEP)
			var next := skeleton.get_bone_global_pose(sword).basis.get_rotation_quaternion()
			max_swing = maxf(next.angle_to(first), max_swing)
			max_frame_turn = maxf(next.angle_to(previous), max_frame_turn)
			previous = next
			for index in feet.size():
				var ankle := skeleton.get_bone_global_pose(feet[index]).origin
				max_foot_slide = maxf(ankle.distance_to(start_feet[index]), max_foot_slide)
			for limb in actor._support.limbs:
				max_sole_error = maxf(absf(actor._support._sole_height(limb) - floor.y), max_sole_error)
			if visual and frame in ([15, 27, 46] if clip == &"stance" else [72, 143, 144]):
				await process_frame
				await process_frame
				RenderingServer.force_draw(false)
				root.get_texture().get_image().save_png(out_dir.path_join("light-%s-%03d.png" % [clip, frame]))
		var swing := rad_to_deg(max_swing)
		var frame_turn := rad_to_deg(max_frame_turn)
		var swing_range := Vector2(15.0, 39.0) if clip == &"stance" else Vector2(1.0, 7.0)
		check(swing > swing_range.x and swing < swing_range.y, "controlled sword arc during %s (%s degrees)" % [clip, swing])
		check(frame_turn < (4.0 if clip == &"stance" else .7), "smooth sword swing during %s (%s degrees/frame)" % [clip, frame_turn])
		check(max_foot_slide < .008 and max_sole_error / model_scale < .012,
			"both feet stay planted during %s (%s / %s)" % [clip, max_foot_slide, max_sole_error / model_scale])
		if clip == &"idle":
			check(rad_to_deg(first.angle_to(previous)) < .1, "idle returns to its initial pose at the loop seam")
		guard_samples[clip] = {"max_sword_degrees": swing, "max_frame_degrees": frame_turn,
			"max_ankle_excursion_model_m": max_foot_slide, "max_sole_error_model_m": max_sole_error / model_scale}
	if visual: main.ui_layer.visible = ui_was_visible


func verify_battle(main: Node) -> Dictionary:
	var active: Array[CreatureBall] = []
	for ball: CreatureBall in main._resources.active.values():
		if ball.def.attribute in [Attr.A.LIGHT, Attr.A.SHADOW]: active.append(ball)
	check(active.size() == 2, "previously leased Light and Shadow form the battle pair")
	if active.size() != 2: return {}
	var center: Vector3 = main.arena.slot_position(2)
	for side in 2:
		var ball := active[side]
		ball.freeze_at(center + Vector3(0.0, CreatureBall.RADIUS, (1 - side * 2) * Arena.FIG_H / 3.0))
		ball._figure.rotation.y = PI if side == 0 else 0.0
		ball._anim.set_process(true)
		main.director.open_creature(ball, false)
	await create_timer(.9).timeout
	var winner := active[0]
	var loser := active[1]
	var contacts: Array[float] = []
	var on_contact := func() -> void: contacts.append(winner._anim._player.current_animation_position)
	winner._anim.strike_contact.connect(on_contact)
	var battle := BattleResult.new()
	battle.attacker_uid = winner.uid
	battle.defender_uid = loser.uid
	battle.winner_uid = winner.uid
	battle.loser_uid = loser.uid
	battle.slot = 2
	battle.powers = [400, 340]
	main.cam.set_process(true)
	main.cam.battle_view(center, winner.figure_height(), true, winner.figure_size())
	main.presentation.state.battle_uids.assign([winner.uid, loser.uid])
	main.battle_hud.open([winner.def.display_name, loser.def.display_name],
		[winner.def.attribute, loser.def.attribute], battle.powers)
	var finished := [false]
	var play := func() -> void:
		await main.presentation.anim_battle_resolved(battle)
		finished[0] = true
	play.call()
	var stop_seen := false
	var hit_seen := false
	var slash_seen := false
	var sampled_strike := false
	var sampled_hit := false
	var deadline := Time.get_ticks_msec() + 6500
	while not finished[0] and Time.get_ticks_msec() < deadline:
		await process_frame
		stop_seen = stop_seen or winner._anim._pause_left > 0.0
		hit_seen = hit_seen or loser._anim._action == &"hit"
		slash_seen = slash_seen or main.director.effects.get_node_or_null("SwordSlash") != null
		if not sampled_strike and winner._anim._action == &"attack" and winner._anim._elapsed > .15:
			sampled_strike = true
			await sample_cloth(winner, "strike")
		if not sampled_hit and loser._anim._action == &"hit" and loser._anim._elapsed > .15:
			sampled_hit = true
			await sample_cloth(loser, "hit")
		if main.battle_overlay._open: main.battle_overlay._close()
	check(finished[0], "ordinary battle result reaches and closes its overlay")
	check(contacts.size() == 1 and absf(contacts[0] - .4) < .045, "director receives one native contact near frame 12")
	check(stop_seen and hit_seen and slash_seen, "director applies hitstop, hit animation and sword effect")
	check(winner._anim._action == &"" and loser._anim._action == &"", "both actors recover to idle after battle presentation")
	check_solver(winner, "attack complete")
	check_solver(loser, "hit complete")
	winner._anim.strike_contact.disconnect(on_contact)
	return {"contact_clip_times": contacts, "hitstop": stop_seen, "hit": hit_seen, "sword_effect": slash_seen,
		"result_closed": finished[0]}


func finish(result: Dictionary) -> void:
	result.merge({"checks": checks, "failures": failures, "rendered": visual, "elements": rows, "guard": guard_samples})
	var file := FileAccess.open(out_dir.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("RATNIK TRELLIS ", JSON.stringify(result))
	var loader := GameLoading.i()
	loader.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await process_frame
	quit(1 if failures else 0)
