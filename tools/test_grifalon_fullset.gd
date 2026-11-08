extends SceneTree
## Six real source meshes + accepted per-rest libraries, through CreatureAnim.
const Motion := preload("res://scenes/grifalon_motion.gd")
const GaleSkin := preload("res://scenes/grifalon_gale_skin.gd")
const ReviewState := preload("res://tools/model_review_state.gd")
var checks := 0
var failures := 0
var visual := false
var light_only := false
var only_element := ""
var out := "res://build/checks/grifalon-fullset"
var camera: Camera3D
var floor_node: MeshInstance3D
var reports: Array = []
var capture_actor: CreatureAnim
var capture_states: Dictionary = {}
var accepted_signature: Array = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + why)

func start_action(a: CreatureAnim, clip: StringName) -> void:
	match clip:
		&"idle": a.reset()
		&"stance": a.appear()
		&"roar": a.roar()
		&"attack": a.lunge(a.get_height() * .22)
		&"hit": a.hit(Color.WHITE, a.get_height() * .075)

func capture(name: String) -> void:
	if not visual: return
	var before := capture_state()
	# The offscreen force_draw callback runs before deferred Skeleton3D uploads.
	# One frame can capture the previous phase despite correct CPU bone matrices.
	for settle in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	capture_states[name] = {"before": before, "after": capture_state()}
	root.get_texture().get_image().save_png(out + "/" + name + ".png")

func capture_state() -> Dictionary:
	var a := capture_actor
	var sk := Motion._skeleton(a)
	var hips := sk.get_bone_global_pose(sk.find_bone("hips"))
	var chest := sk.get_bone_global_pose(sk.find_bone("chest"))
	return {"animation": a._player.current_animation, "time": a._player.current_animation_position, "hips": str(hips), "chest": str(chest), "hips_q": str(sk.get_bone_pose_rotation(sk.find_bone("hips"))), "body_angle": rad_to_deg((chest.origin - hips.origin).angle_to(Vector3.UP)), "rest_only": sk.show_rest_only, "actor_processing": a.is_processing(), "player_callback": a._player.callback_mode_process}

func matrix(tr: Transform3D) -> Array:
	var rows: Array = []
	for axis in 3: rows.append([tr.basis.x[axis], tr.basis.y[axis], tr.basis.z[axis], tr.origin[axis]])
	return rows

func skin_inputs(model: Node3D, sk: Skeleton3D, id: String) -> Array:
	var result: Array = []
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if not node is MeshInstance3D or node.skin == null: continue
		var mesh := node as MeshInstance3D
		var slots: Array[int] = []
		for slot in mesh.skin.get_bind_count():
			var bone := mesh.skin.get_bind_bone(slot)
			if bone < 0: bone = sk.find_bone(mesh.skin.get_bind_name(slot))
			slots.append(bone)
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var prefix := id + "-surface" + str(result.size())
			for item in [["vertices", vertices.to_byte_array()], ["joints", joints.to_byte_array()], ["weights", weights.to_byte_array()]]:
				var file := FileAccess.open(out + "/" + prefix + "-" + item[0] + ".bin", FileAccess.WRITE)
				file.store_buffer(item[1])
				file.close()
			result.append({"mesh": mesh, "bones": slots, "prefix": prefix, "vertices": vertices.size(), "stride": weights.size() / vertices.size(), "world": matrix(mesh.global_transform)})
	return result

func verify_accepted_contact(a: CreatureAnim, sk: Skeleton3D) -> void:
	# Independent reference: the author's accepted fullset GLB, not the .res
	# currently installed in this actor. Compare in root-relative source space.
	var path := "res://build/experiments/unirig-unimate-2026-11-08/fullset-grifalon-21/grifalon-fullset21.glb"
	check(FileAccess.get_sha256(path) == "f323ba537d5ca35b58d56c857de427111f9f729c19208f89b30ea099c26d342c", "accepted fullset identity")
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	check(document.append_from_file(path, state) == OK, "accepted GLB loaded directly")
	var native := document.generate_scene(state)
	native.visible = false
	root.add_child(native)
	var reference := Motion._skeleton(native)
	var player := native.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(&"attack", 0.0)
	player.seek(0.0, true)
	player.advance(0.0)
	var reference_origin := reference.to_global(reference.get_bone_global_pose(reference.find_bone("root")).origin)
	ReviewState.reset_actor(a)
	a.lunge(a.get_height() * .22)
	a._process(0.0)
	var actor_origin := sk.to_global(sk.get_bone_global_pose(sk.find_bone("root")).origin)
	var unit_scale := float(a.get_child(0).get_meta("normalization_scale"))
	for clip_time in [0.0, .3, .4, .5, 1.2]:
		var action_time: float = clip_time / .4 * a._contact_time if clip_time <= .4 else a._contact_time + .07 + (clip_time - .4) / .8 * (a._duration - a._contact_time - .07)
		action_time = minf(action_time, a._duration - .000001)
		while a._elapsed < action_time - .0000001: a._process(minf(1.0 / 120.0, action_time - a._elapsed))
		player.seek(clip_time, true)
		player.advance(0.0)
		var reference_root := reference.get_bone_global_pose(reference.find_bone("root")).origin
		var actor_root := sk.get_bone_global_pose(sk.find_bone("root")).origin
		# The native GLB has an animated object track; .res deliberately folds it
		# into root bone translation. Compare physical world displacement, then
		# remove the unchanged source model's normalization scale.
		var root_error := (reference.to_global(reference_root) - reference_origin).distance_to((sk.to_global(actor_root) - actor_origin) / unit_scale)
		check(root_error < .00003, "accepted root motion at " + str(clip_time))
		var max_error := 0.0
		for name in Motion.BONES:
			var expected := reference.get_bone_global_pose(reference.find_bone(name))
			var actual := sk.get_bone_global_pose(sk.find_bone(name))
			var error := (expected.origin - reference_root).distance_to(actual.origin - actor_root)
			for axis in 3: error = maxf(error, expected.basis[axis].distance_to(actual.basis[axis]))
			max_error = maxf(max_error, error)
			check(error < .00003, "accepted physical pose " + name + " at " + str(clip_time))
		var hips := sk.get_bone_global_pose(sk.find_bone("hips")).origin
		var chest := sk.get_bone_global_pose(sk.find_bone("chest")).origin
		accepted_signature.append({"clip_time": clip_time, "actual_time": a._player.current_animation_position, "root_world_displacement_error_source": root_error, "max_root_relative_error": max_error, "body_angle_from_up": rad_to_deg((chest - hips).angle_to(Vector3.UP)), "foot_L_forward_of_hips": sk.get_bone_global_pose(sk.find_bone("foot.L")).origin.z - hips.z, "foot_R_forward_of_hips": sk.get_bone_global_pose(sk.find_bone("foot.R")).origin.z - hips.z})
	ModelLifetime.release(native, self)
	await process_frame

func verify_actor(d: CreatureDef) -> void:
	var a := CreatureAnim.new()
	capture_actor = a
	root.add_child(a)
	a.set_process(false)
	var model := CreatureModels.build(d)
	var original_source: Resource = model.get_meta("preparation_source")
	a.set_model(model, d)
	a.idle_on = true
	a._phase = 0.0
	check(a._authored_fullset, String(d.id) + " authored set installed")
	check(a._support == null, String(d.id) + " legacy support/flight excluded")
	check(model.get_meta("preparation_source") == original_source, "original PackedScene kept")
	var sk := Motion._skeleton(model)
	check(sk.get_bone_count() == 21, String(d.id) + " unchanged source skeleton")
	var library: AnimationLibrary = Motion.libraries[d.id]
	var row := {"id": d.id, "height": a.get_height(), "visual_top": a.get_height() + a.get_hover_height(), "extent": a.get_extent(), "samples": []}
	var inputs := skin_inputs(model, sk, String(d.id))
	if d.id == &"creature_grifalon_gale":
		check(model.get_meta("grifalon_gale_skin_overlay", 0) == 1, "Gale uses explicit sparse skin overlay")
		check(GaleSkin.meshes.size() == 1, "one immutable mesh clone cached")
		var entry: Dictionary = GaleSkin.meshes.values()[0]
		check(entry.source != entry.mesh, "source mesh resource is not modified")
		var original: ArrayMesh = entry.source
		var updated: ArrayMesh = entry.mesh
		var old_raw: Dictionary = original.get("_surfaces")[0]
		var new_raw: Dictionary = updated.get("_surfaces")[0]
		for field in old_raw:
			if field not in ["skin_data", "bone_aabbs"]: check(old_raw[field] == new_raw[field], "Gale raw field preserved " + field)
		check(original.surface_get_format(0) == updated.surface_get_format(0), "8-bone format unchanged")
		var old_arrays := original.surface_get_arrays(0)
		var new_arrays := updated.surface_get_arrays(0)
		var patch: Dictionary = GaleSkin.overlay.get_meta("surfaces")[0]
		check(GaleSkin.digest(old_arrays[Mesh.ARRAY_BONES].to_byte_array()) == patch.source_bones_sha256 and GaleSkin.digest(old_arrays[Mesh.ARRAY_WEIGHTS].to_byte_array()) == patch.source_weights_sha256, "original skin buffers still match source")
		var changed: Dictionary = {}
		for vertex in patch.vertex_ids: changed[vertex] = true
		var outside_changed := 0
		var nonwing_changed := 0
		var bind_names: PackedStringArray = GaleSkin.overlay.get_meta("bind_bone_names")
		for vertex in old_arrays[Mesh.ARRAY_VERTEX].size():
			if not changed.has(vertex):
				for influence in 8:
					if old_arrays[Mesh.ARRAY_BONES][vertex * 8 + influence] != new_arrays[Mesh.ARRAY_BONES][vertex * 8 + influence] or old_arrays[Mesh.ARRAY_WEIGHTS][vertex * 8 + influence] != new_arrays[Mesh.ARRAY_WEIGHTS][vertex * 8 + influence]:
						outside_changed += 1
						break
			elif GaleSkin._other_weights(old_arrays[Mesh.ARRAY_BONES], old_arrays[Mesh.ARRAY_WEIGHTS], vertex * 8, bind_names) != GaleSkin._other_weights(new_arrays[Mesh.ARRAY_BONES], new_arrays[Mesh.ARRAY_WEIGHTS], vertex * 8, bind_names): nonwing_changed += 1
		check(outside_changed == 0 and nonwing_changed == 0, "encoded skin changes only declared right-wing region/influences")
		for value in entry.values(): check(not value is Node, "skin cache contains only resources")
		row.skin_overlay = {"payload_digest": GaleSkin.payload_digest(GaleSkin.overlay), "sparse_vertices": changed.size(), "outside_changed": outside_changed, "nonwing_changed": nonwing_changed, "source_original_buffers_match": true}
	row.meshes = []
	for item in inputs: row.meshes.append({"prefix": item.prefix, "vertices": item.vertices, "stride": item.stride, "world": item.world})
	if visual:
		var h: float = row.visual_top
		camera.look_at_from_position(Vector3(h * 1.4, h * .85, h * 2.2), Vector3(0, h * .5, 0))
		row.camera = {"world": matrix(camera.global_transform), "fov": camera.fov, "aspect": 1.0}
		(floor_node.mesh as PlaneMesh).size = Vector2(h * 6, h * 6)
	for clip in ([&"attack"] if light_only else Motion.CLIPS):
		var authored := library.get_animation(clip)
		var runtime := a._player.get_animation(clip)
		check(runtime.length == authored.length, String(d.id) + " duration " + String(clip))
		check(runtime.get_track_count() == authored.get_track_count(), "authored channel count")
		for track in authored.get_track_count():
			check(runtime.track_get_key_count(track) == authored.track_get_key_count(track), "no resampling")
			check(runtime.track_get_interpolation_type(track) == authored.track_get_interpolation_type(track), "authored interpolation")
			for key in [0, authored.track_get_key_count(track) / 2, authored.track_get_key_count(track) - 1]:
				check(runtime.track_get_key_value(track, key) == authored.track_get_key_value(track, key), "authored values preserved")
		for phase in [0.0, .2, 1.0 / 3.0, .6, 1.0]:
			ReviewState.reset_actor(a)
			start_action(a, clip)
			if clip == &"idle":
				var elapsed := 0.0
				var target: float = phase * authored.length / absf(a._player.get_playing_speed())
				while elapsed < target - .0000001:
					var step := minf(1.0 / 120.0, target - elapsed)
					a._process(step)
					elapsed += step
			else:
				# Primary evidence is genuine playback from a live idle through the
				# blend, not a one-shot jump whose clock can lead its mixed pose.
				var target: float = a._contact_time if clip == &"attack" and is_equal_approx(phase, 1.0 / 3.0) else a._duration * phase
				while a._elapsed < target - .0000001:
					a._process(minf(1.0 / 120.0, target - a._elapsed))
			check(a.position.is_equal_approx(a._base), "no double hover/lunge " + String(d.id))
			check(a.rotation.is_zero_approx(), "no additive rotation")
			for bone in sk.get_bone_count(): check(sk.get_bone_global_pose(bone).is_finite(), "finite posed source bone")
			var palettes: Array = []
			for item in inputs:
				var mesh: MeshInstance3D = item.mesh
				var palette: Array = []
				for slot in item.bones.size(): palette.append(matrix(sk.get_bone_global_pose(item.bones[slot]) * mesh.skin.get_bind_pose(slot)))
				palettes.append(palette)
			row.samples.append({"clip": clip, "phase": phase, "root_pose": str(sk.get_bone_pose(0)), "actor_position": str(a.position), "palettes": palettes})
			if is_equal_approx(phase, 1.0 / 3.0):
				await capture(String(d.id) + "-" + String(clip))
				if light_only and visual:
					var previous := camera.transform
					camera.look_at_from_position(Vector3(row.visual_top * 2.5, row.visual_top * .55, 0), Vector3(0, row.visual_top * .5, 0))
					await capture("light-contact-side")
					camera.transform = previous
	if d.id == &"creature_grifalon_light": await verify_accepted_contact(a, sk)
	var contacts := [0]
	a.strike_contact.connect(func() -> void:
		contacts[0] += 1
		check(absf(a._attack_progress(a._elapsed) - 1.0 / 3.0) < .00001, "contact phase is one third"))
	for fps in [30, 60, 120]:
		a.reset()
		a.lunge(a.get_height())
		for frame in range(fps * 2): a._process(1.0 / float(fps))
		check(a._action == &"" and a.fx_pos.is_zero_approx(), "action returns to continuing idle")
	check(contacts[0] == 3, "one contact at each timestep")
	a.lunge(1.0, .46)
	for frame in 31: a._process(1.0 / 60.0)
	check(contacts[0] == 4, "clash override contact")
	a.hold_impact(.06)
	var elapsed := a._elapsed
	a._process(.03)
	check(a._elapsed == elapsed, "hitstop keeps authored pose/time")
	a.roar(.4)
	a.hit(Color.WHITE, .5)
	for frame in 75: a._process(1.0 / 60.0)
	check(a._action == &"" and a._player.current_animation == &"idle", "hit interrupts delayed roar and recovers")
	# A warm second actor must share prepared curves, never playback state.
	var warm := CreatureAnim.new()
	root.add_child(warm)
	warm.set_process(false)
	warm.set_model(CreatureModels.build(d), d)
	check(a._player != warm._player, "independent players")
	check(a._player.get_animation_library(&"") == warm._player.get_animation_library(&""), "shared immutable prepared curves")
	if d.id == &"creature_grifalon_gale": check(GaleSkin.meshes.size() == 1, "warm actor reuses the same immutable overlay mesh")
	ModelLifetime.release(warm, self)
	ModelLifetime.release(a, self)
	reports.append(row)
	await process_frame

func run() -> void:
	CardDB.load_all()
	light_only = OS.get_cmdline_user_args().has("light-only")
	if light_only: out += "/light-contact-proof"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("element="): only_element = arg.trim_prefix("element=")
	if not only_element.is_empty(): out += "/" + only_element + "-correction"
	DirAccess.make_dir_recursive_absolute(out)
	visual = DisplayServer.get_name() != "headless"
	if visual:
		root.size = Vector2i(640, 640)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(.07, .085, .11)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = .8
		root.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -30, 0)
		light.light_energy = 1.5
		light.shadow_enabled = true
		root.add_child(light)
		camera = Camera3D.new()
		camera.fov = 35.0
		camera.current = true
		root.add_child(camera)
		floor_node = MeshInstance3D.new()
		floor_node.mesh = PlaneMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(.14, .17, .21)
		floor_node.material_override = material
		floor_node.position.y = -.02
		root.add_child(floor_node)
	var defs: Array[CreatureDef] = []
	for element in Motion.ELEMENTS: defs.append(CardDB.creature(StringName("creature_grifalon_" + element)))
	CreatureModels.preload_match(defs)
	check(Motion.preload_required(), "six libraries ready before actors")
	var loaded := Motion.load_count
	check(loaded == 6, "exactly six source-rest libraries")
	var valid: AnimationLibrary = Motion.libraries[&"creature_grifalon_light"]
	check(Motion.validation_error(valid, &"creature_grifalon_light").is_empty(), "valid library")
	check(not Motion.validation_error(null, &"creature_grifalon_light").is_empty(), "reject missing library")
	check(not Motion.validation_error(valid, &"creature_grifalon_fire").is_empty(), "reject wrong target")
	var incomplete := valid.duplicate(true) as AnimationLibrary
	incomplete.remove_animation(&"hit")
	check(not Motion.validation_error(incomplete, &"creature_grifalon_light").is_empty(), "reject incomplete library")
	var empty := valid.duplicate(true) as AnimationLibrary
	empty.remove_animation(&"hit")
	empty.add_animation(&"hit", Animation.new())
	check(not Motion.validation_error(empty, &"creature_grifalon_light").is_empty(), "reject empty named clip")
	var missing_root := valid.duplicate(true) as AnimationLibrary
	var broken_attack := missing_root.get_animation(&"attack")
	for track in broken_attack.get_track_count():
		if broken_attack.track_get_type(track) == Animation.TYPE_POSITION_3D and broken_attack.track_get_path(track).get_subname(0) == &"root":
			broken_attack.remove_track(track)
			break
	check(not Motion.validation_error(missing_root, &"creature_grifalon_light").is_empty(), "reject missing authored root channel")
	# Exercise the same readiness decision used before Boot can publish any actors.
	Motion.libraries[&"creature_grifalon_light"] = null
	check(not Motion.preload_required(), "incomplete six-way catalog cannot become ready")
	Motion.libraries[&"creature_grifalon_light"] = valid
	check(Motion.preload_required(), "complete six-way catalog can become ready")
	for d in defs:
		if not only_element.is_empty() and String(d.id) != "creature_grifalon_" + only_element: continue
		if not light_only or d.id == &"creature_grifalon_light": await verify_actor(d)
	check(Motion.load_count == loaded, "no library loads during playback/warm actors")
	# One unaffected flyer and the accepted sword/cape path keep legacy preparation.
	for id in [&"creature_gorgul_shadow", &"creature_ratnik_light"]:
		if not only_element.is_empty(): continue
		var control := CreatureAnim.new()
		root.add_child(control)
		control.set_process(false)
		control.set_model(CreatureModels.build(CardDB.creature(id)), CardDB.creature(id))
		check(not control._authored_fullset and control._support != null, "legacy control intact " + String(id))
		if id == &"creature_ratnik_light": check(control._cloth != null, "Ratnik GPU cape retained")
		ModelLifetime.release(control, self)
		await process_frame
	CreatureModels.clear()
	await process_frame
	var file := FileAccess.open(out + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "visual": visual, "variants": reports, "capture_states": capture_states, "accepted_native_signature": accepted_signature, "sampling": "fixed _process 1/120 from live idle; former one-shot blended snapshots invalid"}, "  "))
	file.close()
	print("GRIFALON_FULLSET checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
