extends SceneTree
## Scoped production intro/reveal integration, all locations and six element profiles.
class EffectsStage extends "res://scenes/main.gd":
	func _ready() -> void:
		_build_world()
		_build_ui()
var checks := 0
var failures := 0
var out := "res://build/checks/presentation/location-reveal"
var game: Node
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(n: int = 3) -> void:
	for i in n: await process_frame
func shot(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(out.path_join(filename+".png")) == OK,"save " + filename)
func until(test: Callable, seconds: float = 35.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not test.call() and Time.get_ticks_msec() < deadline: await process_frame
	check(test.call(),"timed integration step")
	return test.call()
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	DeviceSettings.settings_path = out.path_join("settings.cfg")
	DeviceSettings.reload_settings()
	DeviceSettings.set_reduce_motion(false)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	CardDB.load_all()
	if OS.get_environment("LOCATION_REVEAL_ONLY") == "effects":
		GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
		ArenaLocations._current = 0
		game = EffectsStage.new()
		root.add_child(game)
		await frames()
		await _reveal_effects()
		game.queue_free()
		await frames(4)
		if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
		if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
		await frames(4)
		print("Effects-only checks=",checks," failures=",failures)
		quit(1 if failures else 0)
		return
	# All profiles/quality counts; no model assets are modified.
	for quality in [GraphicsSettings.Level.HIGH,GraphicsSettings.Level.MEDIUM,GraphicsSettings.Level.LOW]:
		GraphicsSettings.force_level(quality)
		for element in 6:
			var p := BallFx.particles(element,"open",1.0)
			check(p.amount == BallFx._n(72 if element == BallFx.FIRE else 36),"element quality budget")
			check(p.lifetime == .9 and p.one_shot,"reveal duration/cleanup contract")
			check(p.emission_points.size() == 36 and p.emission_normals.size() == 36,"body-sized directed emission")
			for i in p.emission_normals.size():
				check(Vector2(p.emission_points[i].x,p.emission_points[i].z).dot(Vector2(p.emission_normals[i].x,p.emission_normals[i].z)) > 0,"emission points away from body")
			# Free the temporary emitter used for cache comparison.
			var other := BallFx.particles(element,"open",1.0)
			check(other.mesh == p.mesh,"warm mesh identity")
			other.free()
			var material: StandardMaterial3D = p.mesh.surface_get_material(0)
			check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,"open uses alpha masks/fade")
			if element == BallFx.STONE:
				check(p.mesh is ArrayMesh and p.mesh.surface_get_array_len(0) == 24,"eight irregular rock faces")
			if element == BallFx.TIDE:
				check(p.mesh is ArrayMesh and p.gravity.y < 0 and p.particle_flag_align_y,"3D blue falling drops")
			p.free()
	check((BallFx._mat("add","streak") as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,"non-open additive material unchanged")
	check((BallFx._mat("shard","") as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,"non-open shards unchanged")
	GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
	# Real _start_game: before controller start every HUD/control stays hidden.
	for location in 3:
		ArenaLocations._current = location
		game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		await frames()
		game.team_menu.pick_random_and_start()
		if not await until(func(): return is_instance_valid(game._location_intro)): break
		var intro: LocationIntro = game._location_intro
		check(game._preparing and not game.ctrl._started,"no gameplay before establishing shots")
		check(not game.hud.visible and not game.setup_panel.visible and not game.ability_panel.visible,"real interface hidden during intro")
		check(intro.title.text == ArenaLocations.definition(location).name,"correct centered location title")
		await frames()
		check(intro.title.get_global_rect().get_center().is_equal_approx(Vector2(root.size)*.5),"title centered in viewport")
		for index in 3:
			if not await until(func(): return intro.shot_index == index,4): break
			await create_timer(.65,true,false,true).timeout
			check(not game.ctrl._started and not game.hud.visible,"shot keeps match UI/input locked")
			check(game.cam.global_position.is_finite() and game.cam.global_position.y >= CameraRig.MIN_Y,"intro camera finite above floor")
			if location == 0:
				check(Vector2(game.cam.global_position.x,game.cam.global_position.z).length()<102 and game.cam.global_position.y<108,"camera inside sanctuary")
			await shot("location-%d-shot-%d" % [location,index])
		if not await until(func(): return not game._preparing,5): break
		check(game.ctrl._started and game.hud.visible and game.hud._match_intro_started,"controller/HUD start after intro")
		check(game.cam.is_overview(),"camera returns to normal overview")
		await shot("location-%d-hud" % location)
		# Six real reveal entries on one actual arena, sampled at normal running time.
		if location == 0:
			await _reveal_effects()
		# Skip works and reduced-motion still presents the location first.
		var reduced := LocationIntro.new()
		game.ui_layer.add_child(reduced)
		DeviceSettings.set_reduce_motion(true)
		reduced.play(game.cam,location)
		check(reduced.shot_index == 2 and game.cam.is_overview(),"reduced-motion still overview")
		reduced.finish()
		await frames()
		check(not is_instance_valid(reduced),"skip frees intro and restores camera")
		DeviceSettings.set_reduce_motion(false)
		game.queue_free()
		await frames(4)
	game = null
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(4)
	print("Location/reveal checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func _reveal_effects() -> void:
	# Keep the real HudUI alive for Light's transient pulse, but hide unrelated UI.
	for control in game.ui_layer.get_children():
		if control is Control: control.hide()
	game.hud.show()
	for control in game.hud.get_children():
		if control is CanvasItem: control.hide()
	game.hover_tips.set_process(false)
	for element in 6:
		var id := StringName("creature_dragnar_" + ["fire","gale","light","stone","shadow","tide"][element])
		var ball: CreatureBall = load("res://scenes/creature_ball.tscn").instantiate()
		game.world.add_child(ball)
		ball.setup(CardDB.creature(id),900+element)
		ball.freeze_at(Vector3(0,CreatureBall.RADIUS,0))
		game.cam._set_static(Vector3(20,12,28),Vector3(0,8,0),{"fov":56.0,"hand":0.0})
		game.cam.cut()
		var before: int = game.hud.get_child_count()
		game.director.open_creature(ball)
		check(game.hud.get_child_count() == before+(1 if element == BallFx.LIGHT else 0),"only first Light entry flashes")
		game.director.open_creature(ball,false)
		check(game.hud.get_child_count() == before+(1 if element == BallFx.LIGHT else 0),"no duplicate Light flash")
		for phase in 3:
			await create_timer(.18).timeout
			await shot("reveal-%d-phase-%d" % [element,phase])
		ball.queue_free()
		await create_timer(1.2).timeout
