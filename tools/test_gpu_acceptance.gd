extends SceneTree
## Opt-in: actual hardware GPU, ordinary imported CreatureBall, SubViewport PNGs.
## A successful machine run still requires Sol visual review of the saved PNGs.
const WINDOW := preload("res://tools/test_window.gd")
const INPUTS := "res://docs/audits/2026-11-06-gpu-acceptance/accepted-sources.json"
const A04_SHA := "d51ab2dc59b810d39e2b7346fab0101256f44f421fdaa8ed4a538eb97cbf5a70"
var output := "res://build/checks/models/gpu-acceptance"
var checks := 0
var failures := 0
var report := {"hardware_gpu_accepted": false, "visual_review": "OPEN: saved PNGs require Sol review", "models": [], "captures": [], "gpu_samples": []}
var viewport: SubViewport
signal buffers_ready(positions: PackedByteArray, targets: PackedByteArray)

func _initialize() -> void:
	# Direct runs and check.py wrappers obey the same window contract.
	if not has_meta("sfery_background_draw"): WINDOW.background(self)
	_run.call_deferred()

func _finalize() -> void:
	WINDOW.finish(self)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func frames(count: int) -> void:
	for _i in count: await process_frame

func geometry(node: Node) -> Array:
	var result: Array = []
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		pending.append_array(current.get_children())
		if not current is MeshInstance3D: continue
		var mesh := current as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var keys: Array[String] = []
			for vertex in vertices: keys.append(var_to_bytes(vertex).hex_encode())
			var faces: Array[String] = []
			for face in indices.size() / 3:
				var corners: Array[String] = [keys[indices[face*3]], keys[indices[face*3+1]], keys[indices[face*3+2]]]
				var first := 0
				if corners[1] < corners[first]: first = 1
				if corners[2] < corners[first]: first = 2
				faces.append(corners[first] + corners[(first+1)%3] + corners[(first+2)%3])
			faces.sort()
			result.append({"mesh": String(mesh.name), "surface": surface, "triangles": indices.size()/3, "oriented_geometry_sha256": "\n".join(faces).sha256_text()})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["mesh"] + str(a["surface"]) < b["mesh"] + str(b["surface"]))
	return result

func finish(status: String, code: int) -> void:
	report["status"] = status
	report["checks"] = checks
	report["failures"] = failures
	report["source_manifest_sha256"] = FileAccess.get_sha256(INPUTS)
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("GPU acceptance: ", status, "; ", checks, "/", failures, "; visual review OPEN")
	quit(code)

func capture(name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	check(Engine.max_fps == 60 and root.unfocusable and root.mode == Window.MODE_MINIMIZED, "window contract " + name)
	var image := viewport.get_texture().get_image()
	check(not image.is_empty() and image.get_size() == viewport.size, "real SubViewport image " + name)
	var path := output.path_join(name + ".png")
	check(image.save_png(path) == OK, "save " + name)
	report["captures"].append({"name": name, "sha256": FileAccess.get_sha256(path)})

func _accept_buffers(positions: PackedByteArray, targets: PackedByteArray) -> void:
	buffers_ready.emit(positions, targets)

func sample(solver: Node, label: String) -> void:
	RenderingServer.call_on_render_thread(func() -> void:
		var p: PackedByteArray = solver._rd.buffer_get_data(solver._positions_buffer)
		var t: PackedByteArray = solver._rd.buffer_get_data(solver._skinned_targets_buffer)
		_accept_buffers.call_deferred(p, t))
	var buffers: Array = await buffers_ready
	var p: PackedFloat32Array = buffers[0].to_float32_array()
	var t: PackedFloat32Array = buffers[1].to_float32_array()
	check(p.size() == t.size() and p.size() == solver._particle_count * 4, "actual GPU storage sizes " + label)
	var displacement := 0.0
	var pin_error := 0.0
	var minimum_world_y := INF
	for index in solver._particle_count:
		var i: int = index * 4
		var position := Vector3(p[i], p[i+1], p[i+2])
		var target := Vector3(t[i], t[i+1], t[i+2])
		check(position.is_finite() and target.is_finite(), "finite GPU particle " + label)
		displacement = maxf(displacement, position.distance_to(target))
		minimum_world_y = minf(minimum_world_y, (solver._ref_node.global_transform * position).y)
		if p[i+3] == 0.0: pin_error = maxf(pin_error, position.distance_to(target))
	check(displacement < 0.115 and pin_error < 0.0001, "bounded cloth and pinned seam " + label)
	check(minimum_world_y > -0.02 * Arena.FIG_H, "GPU cloth stays above floor " + label)
	for index in 2:
		var file := FileAccess.open(output.path_join(label + ("-positions.bin" if index == 0 else "-targets.bin")), FileAccess.WRITE)
		file.store_buffer(buffers[index])
		file.close()
	report["gpu_samples"].append({"label": label, "max_displacement": displacement, "pin_error": pin_error, "minimum_world_y": minimum_world_y, "particles": solver._particle_count})

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	report["engine"] = Engine.get_version_info()
	report["display"] = DisplayServer.get_name()
	var rd := RenderingServer.get_rendering_device()
	if rd == null or DisplayServer.get_name() == "headless":
		report["blocker"] = "No windowed hardware RenderingDevice; no models/PNG allocated"
		finish("BLOCKED_NO_HARDWARE_GPU", 2)
		return
	var adapter := RenderingServer.get_video_adapter_name()
	var vendor := RenderingServer.get_video_adapter_vendor()
	var device_type: int = RenderingServer.get_video_adapter_type()
	report["adapter"] = adapter
	report["vendor"] = vendor
	report["device_type"] = device_type
	var software := false
	for marker in ["llvmpipe", "lavapipe", "swiftshader", "software", "dummy", "virtual", "microsoft basic"]:
		software = software or (adapter + " " + vendor).to_lower().contains(marker)
	if software or device_type not in [RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_DISCRETE_GPU]:
		report["blocker"] = "Software/virtual/unknown device explicitly rejected"
		finish("BLOCKED_NO_HARDWARE_GPU", 2)
		return
	report["hardware_gpu_accepted"] = true
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INPUTS))
	for row: Dictionary in manifest["models"]:
		check(FileAccess.get_sha256(row["source"]) == row["sha256"], "reviewed source SHA " + row["key"])
		check(FileAccess.get_sha256(row["import_scene"]) == row["import_sha256"], "frozen ordinary SCN SHA " + row["key"])
		check(FileAccess.get_sha256(row["source"] + ".import") == row["sidecar_sha256"], "ordinary remap sidecar SHA " + row["key"])
		check(FileAccess.get_file_as_string(row["import_md5_path"]) == row["import_md5"], "live import md5 metadata " + row["key"])
		check(row["import_md5"].contains('source_md5="' + row["source_md5"] + '"'), "ordinary import matches source " + row["key"])
		if row["key"] == "ratnik_light": check(row["sha256"] == A04_SHA, "current A04 helmet d51 SHA")
	if failures > 0:
		finish("FAIL_INPUT_IDENTITY", 1)
		return
	CardDB.load_all()
	CreatureModels.resident_catalog = true
	DeviceSettings.settings_path = output.path_join("isolated-device.cfg")
	DeviceSettings.reload_settings()
	CreaturePortrait.preload_catalog()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.3
	light.light_cull_mask |= CreatureBall.FIGURE_LIGHT_LAYER
	world.add_child(light)
	var camera := Camera3D.new()
	camera.fov = 36
	camera.current = true
	world.add_child(camera)
	for row: Dictionary in manifest["models"]:
		CreatureModels.clear()
		# Reimport GLTF in memory and compare actual oriented triangles against
		# the ordinary editor-produced resource, independent of vertex order.
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		check(document.append_from_file(row["source"], state) == OK, "direct GLTF source " + row["key"])
		var direct := document.generate_scene(state)
		var direct_geometry := geometry(direct)
		direct.free()
		var packed := load(row["source"]) as PackedScene
		var ordinary := packed.instantiate()
		var ordinary_geometry := geometry(ordinary)
		ordinary.free()
		check(direct_geometry == ordinary_geometry, "ordinary oriented triangle fingerprints match source " + row["key"])
		var definition := CardDB.creature(StringName("creature_" + row["key"]))
		var ball := CreatureBall.new()
		world.add_child(ball)
		ball.setup(definition, 71106)
		ball.freeze = true
		ball.position.y = CreatureBall.RADIUS
		ball.open_animated(false)
		await frames(90)
		var animation := ball._anim
		check(animation != null and ball.is_figure_shown(), "ordinary CreatureBall disclosed " + row["key"])
		var meshes := animation._meshes
		var triangles := 0
		for mesh: MeshInstance3D in meshes:
			for surface in mesh.mesh.get_surface_count():
				triangles += mesh.mesh.surface_get_array_index_len(surface) / 3
		var actor_geometry := geometry(animation)
		check(actor_geometry == ordinary_geometry, "real CreatureBall geometry matches ordinary SCN " + row["key"])
		report["models"].append({"key": row["key"], "source_sha256": row["sha256"], "ordinary_scn_sha256": row["import_sha256"], "triangles": triangles, "surfaces": actor_geometry})
		var themes: Array = ["light", "dark"] if row["key"] == "ratnik_light" else ["dark"]
		var owners: Array = [0, 1] if row["key"] == "ratnik_light" else [0]
		var views: Array = [["side", Vector3(2.5, 0.65, 0)], ["back", Vector3(0, 0.65, -2.5)]] if row["key"] == "ratnik_light" else [["front", Vector3(0, 0.6, 2.5)], ["quarter", Vector3(1.6, 0.85, 2.1)], ["back", Vector3(0, 0.65, -2.5)]]
		for theme in themes:
			environment.environment.background_color = Color("c9c4bb") if theme == "light" else Color("141923")
			for side in owners:
				CreatureBall._set_rim(animation, CreatureBall._rim_mats[side])
				for view in views:
					var height := animation.get_height()
					var distance := maxf(height, animation.get_extent())
					camera.look_at_from_position(Vector3(view[1]) * distance, Vector3(0, height * 0.5, 0))
					await capture(row["key"] + "-" + theme + "-owner" + str(side) + "-idle-" + view[0])
		if row["key"] == "ratnik_light":
			var height := animation.get_height()
			camera.look_at_from_position(Vector3(0, height * 0.92, height * 1.45), Vector3(0, height * 0.8, 0))
			await capture("ratnik-light-head-closeup")
		for action in ["attack", "hit"]:
			if action == "attack": animation.lunge(animation.get_height() * 0.22)
			else: animation.hit(Color.WHITE, animation.get_height() * 0.075)
			await frames(24)
			var height := animation.get_height()
			camera.look_at_from_position(Vector3(1.6, 0.85, 2.1) * maxf(height, animation.get_extent()), Vector3(0, height * 0.5, 0))
			await capture(row["key"] + "-" + action + "-quarter")
		if row["key"] == "ratnik_light":
			var solver = animation._cloth
			check(solver != null and solver._gpu_init_done, "actual GPU cape initialized")
			if solver != null and solver._gpu_init_done:
				animation.reset()
				await frames(20)
				for mesh: MeshInstance3D in meshes:
					if not String(mesh.name).begins_with("CapeGPU"): continue
					var material := mesh.get_active_material(0) as ShaderMaterial
					var rim := material.next_pass as ShaderMaterial
					check(rim != null and rim.shader.code.contains(CreatureCloth.GPU_VERTEX), "actual cape rim uses identical GPU vertex hook")
					if rim != null:
						for parameter in CreatureCloth.GPU_PARAMETERS:
							check(rim.get_shader_parameter(parameter) == material.get_shader_parameter(parameter), "actual cape rim binding " + parameter)
				await sample(solver, "ratnik-idle")
				for action in ["attack", "hit"]:
					if action == "attack": animation.lunge(animation.get_height() * 0.22)
					else: animation.hit(Color.WHITE, animation.get_height() * 0.075)
					await frames(24)
					await sample(solver, "ratnik-" + action)
					var height := animation.get_height()
					camera.look_at_from_position(Vector3(0, 0.65, -2.5) * maxf(height, animation.get_extent()), Vector3(0, height * 0.5, 0))
					await capture("ratnik-rim-cloth-" + action + "-back")
				var solver_uid: int = solver.get_instance_id()
				var parked := Node3D.new()
				world.add_child(parked)
				ball.reparent(parked)
				await frames(3)
				ball.reparent(world)
				parked.queue_free()
				animation.hide()
				await frames(3)
				animation.show()
				animation.reset()
				await frames(12)
				check(solver.get_instance_id() == solver_uid and solver._gpu_init_done, "resident reparent/hide/reset preserves GPU solver")
				await sample(solver, "ratnik-pool-reuse")
				await capture("ratnik-pool-reuse-back")
				var maximum_motion := 0.0
				for metric: Dictionary in report["gpu_samples"]:
					maximum_motion = maxf(maximum_motion, float(metric["max_displacement"]))
				check(maximum_motion > 0.005, "actual cloth leaves native skinned target")
		ModelLifetime.release(ball, self)
		await frames(3)
	# Six representative real72px portraits: horns/halo, long shapes/fullbody.
	var panels: Array[OpponentPanel] = []
	for side in 2:
		var panel := OpponentPanel.new()
		panel.configure_side(side)
		viewport.add_child(panel)
		panels.append(panel)
	DeviceSettings.set_reduce_motion(true)
	var portraits: Array = [&"creature_ratnik_light", &"creature_klykar_gale", &"creature_levian_gale", &"creature_kolossar_shadow", &"creature_rogozhuk_light", &"creature_likorez_shadow"]
	for index in range(0, portraits.size(), 2):
		for side in 2:
			var definition := CardDB.creature(portraits[index + side])
			panels[side].present(definition, index + side, definition.base_power)
			panels[side].show_context("battle")
		await frames(24)
		await capture("hud-portraits-" + str(index))
	for panel in panels: panel.queue_free()
	await frames(3)
	var battle := BattleHud.new()
	var hud := HudUI.new()
	viewport.add_child(battle)
	viewport.add_child(hud)
	hud.setup_plates([Color.RED,Color.RED,Color.RED], [Color.BLUE,Color.BLUE,Color.BLUE])
	hud.set_names("Игрок", "Публичное имя соперника")
	hud.set_captures(2, 3)
	var plays: Array = [[0,&"ability_fire_drain"],[1,&"ability_klykar_bite"],[0,&"ability_dragnar_heart"],[1,&"ability_light_purge"],[0,&"ability_rogozhuk_shell"],[1,&"ability_stone_copy"]]
	for reduced in [false, true]:
		DeviceSettings.set_reduce_motion(reduced)
		viewport.size = Vector2i(1280,720)
		environment.environment.background_color = Color("c9c4bb") if reduced else Color("141923")
		hud.own_panel.present(CardDB.creature(&"creature_ratnik_light"), 0, 420)
		hud.opponent_panel.present(CardDB.creature(&"creature_kolossar_shadow"), 1, 510)
		hud.own_panel.show_context("battle")
		hud.opponent_panel.show_context("battle")
		hud.set_battle_mode(true)
		battle.set_external_panels(hud.own_panel, hud.opponent_panel, 0 if reduced else 1)
		battle.open(["Своя", "Чужая"], [0,0], [420,510])
		battle.set_chain(plays, [true,true], 0, [plays[0]], [3,3], ["Закрыто способностью", ""])
		await frames(45)
		var label: String = "hud-sixcards-reduced" + str(reduced)
		await capture(label)
		battle.set_powers([680, 390])
		# Main updates public panels separately after BattleHud.set_powers().
		hud.own_panel.set_power(390 if reduced else 680)
		hud.opponent_panel.set_power(680 if reduced else 390)
		await frames(8)
		await capture(label + "-simultaneous-gdelta")
		if reduced:
			viewport.size = Vector2i(1280,960)
			await capture("hud-sixcards-4x3-logical1280x960")
		battle.close()
		await frames(20)
	battle.queue_free()
	hud.queue_free()
	world.queue_free()
	await frames(3)
	CreatureModels.clear()
	viewport.queue_free()
	await frames(3)
	finish("MACHINE_PASS_VISUAL_OPEN" if failures == 0 else "FAIL", 1 if failures else 0)
