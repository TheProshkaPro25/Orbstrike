extends SceneTree
## Меню использует уже подготовленный actor и возвращает его без потери позы/опоры.
const ResidentSolver := preload("res://scenes/resident_cloth_solver.gd")
const WindowTest := preload("res://tools/test_window.gd")
var failures := 0
var checks := 0
var cloth_materials: Array[ShaderMaterial] = []
var cloth_textures: Array[Texture2DRD] = []

func _initialize() -> void:
	if not has_meta("sfery_background_draw"):
		WindowTest.background(self)
	call_deferred("run")

func _finalize() -> void:
	WindowTest.finish(self)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func canonical_pose(actor: CreatureAnim) -> Array[Transform3D]:
	actor._phase = 0.0
	actor._clock = 0.0
	actor.idle_on = false
	actor.reset()
	var poses: Array[Transform3D] = []
	var skeleton: Skeleton3D = actor._support.skeleton
	for bone in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_global_pose(bone))
	return poses

func run() -> void:
	CardDB.load_all()
	CreatureModels.resident_catalog = true
	var pool := GameLoading.i()
	pool._storage = Node3D.new()
	pool.add_child(pool._storage)
	var expected: Dictionary = {}
	var ball_scene := load("res://scenes/creature_ball.tscn") as PackedScene
	# Настоящая cloth-модель и летающее существо: тяжёлый setup делается только здесь.
	for id in [&"creature_ratnik_light", &"creature_dragnar_fire"]:
		var ball := ball_scene.instantiate() as CreatureBall
		pool._storage.add_child(ball)
		ball.setup(CardDB.creature(id), -1)
		ball._apply_owner_marks()
		if is_instance_valid(ball._anim._cloth):
			check(ball._anim._cloth.get_script() == ResidentSolver, "catalog cloth uses resident lifecycle")
			for frame in 120:
				await process_frame
				if ball._anim._cloth._gpu_init_done:
					break
			check(ball._anim._cloth._gpu_init_done, "resident cloth GPU initialization completes")
			cloth_materials.append(ball._anim._cloth._surf_mat)
			cloth_textures.append_array([ball._anim._cloth._positions_tex, ball._anim._cloth._normals_tex, ball._anim._cloth._welded_index_tex])
		pool._park_ball(ball)
		expected[id] = {"ball": ball, "actor": ball._anim, "support": ball._anim._support,
			"base": ball._anim._base, "poses": canonical_pose(ball._anim),
			"cloth": ball._anim._cloth, "buffer": ball._anim._cloth._positions_buffer if is_instance_valid(ball._anim._cloth) else RID(),
			"preparation": ball._anim.preparation_ms.duplicate(true)}
	pool.ready_to_play = true
	var preview := CreaturePreview.new()
	root.add_child(preview)
	for id in expected:
		var record: Dictionary = expected[id]
		var ball: CreatureBall = record.ball
		preview.show_creature(CardDB.creature(id), true)
		check(preview._borrowed_ball == ball and preview._anim == record.actor, "preview reuses exact prepared ball and actor: " + String(id))
		check(preview._anim._support == record.support and preview._anim.preparation_ms == record.preparation, "support/cloth preparation is reused: " + String(id))
		check(preview._pending.is_empty() and preview._cache.is_empty(), "preview does not load scenes: " + String(id))
		check(not ball.is_processing() and ball._anim.is_processing() and ball._shape.disabled, "preview runs only figure animation: " + String(id))
		check(ball._figure.visible and not ball._shell.visible and not ball._label.visible and not ball._foot_ring.visible, "preview hides sphere and game labels: " + String(id))
		check(ball._anim._base == record.base and ball.position == Vector3(0, CreatureBall.RADIUS, 0), "preview preserves canonical base and floor: " + String(id))
		var scale_expected := 1.0 / maxf(ball._anim.get_height(), ball._anim.get_extent() * 0.85)
		check(preview._norm.scale.is_equal_approx(Vector3.ONE * scale_expected), "original normalized camera framing: " + String(id))
		if is_instance_valid(record.cloth):
			check(record.cloth._gpu_init_done and record.cloth._positions_buffer == record.buffer, "preview retains prepared GPU buffers")
			check(record.cloth._surf_mat.get_shader_parameter("gpu_driven"), "preview cape uses GPU positions")
		var holder := Control.new()
		root.add_child(holder)
		pool.moving_scene = true
		preview.reparent(holder, false)
		pool.moving_scene = false
		check(preview._borrowed_ball == ball and preview._anim == record.actor, "moving prepared menu keeps its visible preview")
		for frame in 40:
			await process_frame
		preview.release()
		check(pool._balls[id].has(ball) and ball.get_parent() == pool._storage, "release returns whole ball to pool: " + String(id))
		check(not ball.visible and ball.process_mode == Node.PROCESS_MODE_DISABLED, "reserve is hidden and disabled: " + String(id))
		if is_instance_valid(record.cloth):
			check(record.cloth._gpu_init_done and record.cloth._positions_buffer == record.buffer, "return to pool retains prepared GPU buffers")
		var poses := canonical_pose(ball._anim)
		for bone in poses.size():
			check(poses[bone].is_equal_approx(record.poses[bone]), "canonical skeleton restored after preview: %s bone %d" % [id, bone])
		var game_ball := pool.take_ball(id, 73, Vector3(2, CreatureBall.RADIUS, 8))
		check(game_ball == ball and game_ball._anim == record.actor and game_ball.uid == 73, "same prepared actor is available to match with new uid: " + String(id))
		check(game_ball._home == Vector3(2, CreatureBall.RADIUS, 8) and not game_ball._shape.disabled and game_ball.is_processing(), "game restores home, collider and processing: " + String(id))
		if is_instance_valid(record.cloth):
			check(record.cloth._gpu_init_done and record.cloth._positions_buffer == record.buffer, "match reuses same initialized GPU cloth")
		pool.return_ball(game_ball)
	# Удаление меню без явного release тоже не должно удалять объект из каталога.
	var first: StringName = &"creature_ratnik_light"
	preview.show_creature(CardDB.creature(first))
	var parked: CreatureBall = preview._borrowed_ball
	preview.queue_free()
	await process_frame
	check(is_instance_valid(parked) and pool._balls[first].has(parked), "closing preview returns its live actor")
	# Занятый экземпляр не вызывает скрытый новый build/set_model.
	var busy := pool.take_ball(first, 88, Vector3(0, CreatureBall.RADIUS, 0))
	var unavailable := CreaturePreview.new()
	root.add_child(unavailable)
	unavailable.show_creature(CardDB.creature(first))
	check(unavailable._anim == null and unavailable._pending.is_empty() and unavailable._cache.is_empty(), "exhausted pool never starts lazy preparation")
	unavailable.queue_free()
	pool.return_ball(busy)
	# Смена настроек после предварительного построения TeamMenu не должна
	# оставлять старые названия на его кнопках. Пользовательский файл не меняем.
	var selector := TeamMenu.new()
	root.add_child(selector)
	var old_level := GraphicsSettings.current()
	var old_fps := GraphicsSettings.fps_limit()
	GraphicsSettings.level = (old_level + 1) % 3
	GraphicsSettings.max_fps = 144 if old_fps != 144 else 60
	selector.refresh_settings_labels()
	check(selector._graphics_button.text == "Графика: " + GraphicsSettings.level_name(), "prepared TeamMenu refreshes changed quality label")
	check(selector._fps_button.text == "FPS: " + GraphicsSettings.fps_name(), "prepared TeamMenu refreshes changed FPS label")
	GraphicsSettings.level = old_level
	GraphicsSettings.max_fps = old_fps
	selector.free()
	pool.queue_free()
	await process_frame
	await process_frame
	for material in cloth_materials:
		check(not material.get_shader_parameter("gpu_driven"), "actual free detaches cloth shader from GPU")
		for parameter in ["positions_tex", "normals_tex", "welded_index_tex"]:
			check(material.get_shader_parameter(parameter) == null, "actual free clears cloth shader texture: " + parameter)
	var retired_images: Array[RID] = []
	for texture in cloth_textures:
		# Godot's invalid-RID setter clears the renderer wrapper and its size,
		# but keeps the old RD id in the getter. RID.is_valid only tests nonzero.
		check(texture.get_width() == 0 and texture.get_height() == 0, "actual free detaches Texture2DRD wrapper")
		retired_images.append(texture.texture_rd_rid)
	if not retired_images.is_empty():
		var result := {"complete": false, "alive": 0}
		RenderingServer.call_on_render_thread(func() -> void:
			var device := RenderingServer.get_rendering_device()
			for image_rid in retired_images:
				if device.texture_is_valid(image_rid):
					result.alive += 1
			result.complete = true)
		for frame in 120:
			await process_frame
			if result.complete:
				break
		check(result.complete and result.alive == 0, "actual free releases all RD image storage on render thread")
	cloth_materials.clear()
	cloth_textures.clear()
	await process_frame
	print("Preview pool: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
