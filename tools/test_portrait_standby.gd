extends SceneTree
## Standby HUD replicas and full creature silhouettes; no Boot or match.
var checks := 0
var failures := 0
var output := "res://build/checks/presentation/portrait-standby"
var gallery: Control

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(n: int = 3) -> void:
	for i in n: await process_frame
func poses(skeleton: Skeleton3D) -> Array:
	var result: Array = []
	for bone in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose(bone))
	return result
func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "PNG " + name)
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	DeviceSettings.settings_path = output.path_join("isolated-settings.cfg")
	DeviceSettings.reload_settings()
	DeviceSettings.set_reduce_motion(true)
	CardDB.load_all()
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var world := Node3D.new()
	root.add_child(world)
	var hud := HudUI.new()
	root.add_child(hud)
	hud.setup_plates([Color.RED], [Color.BLUE])
	hud.set_names("Герой standby", "Соперник standby")
	for model in 2:
		var fighter := VrmFighter.new()
		world.add_child(fighter)
		var profile := PlayerProfile.DEFAULT.duplicate(true)
		profile.vrm_model = model
		fighter.apply_profile(profile)
		fighter.set_process(false)
		fighter.play_motion("command")
		fighter.sample_motion(.6, .4)
		var before := poses(fighter.skeleton)
		var source_position := fighter.actor.position
		var portrait := FighterPortrait.new()
		root.add_child(portrait)
		portrait.bind(fighter, model)
		hud.set_portrait(model, portrait.get_texture())
		portrait.watch_consumer(hud.portrait_consumer(model), hud)
		check(fighter.motion == "command" and poses(fighter.skeleton) == before and fighter.actor.position == source_position, "binding does not change arena action or pose")
		check(portrait.world_3d != fighter.get_world_3d(), "portrait world is independent")
		check(portrait._standby_actor.process_mode == Node.PROCESS_MODE_DISABLED, "replica has no animation or script processing")
		for source in fighter.meshes:
			var copy: MeshInstance3D = portrait.replica_node(source)
			check(copy != source and copy.mesh == source.mesh and copy.skin == source.skin, "replica reuses mesh/skin resources")
			check(source.layers == 1 << (18 + model) and copy.layers == 1, "arena lighting layers stay separate from portrait")
		var expected := poses(portrait._standby_skeleton)
		var idle := Skeleton3D.new()
		for bone in fighter.skeleton.get_bone_count(): idle.add_bone(fighter.skeleton.get_bone_name(bone))
		for bone in fighter.skeleton.get_bone_count():
			idle.set_bone_parent(bone, fighter.skeleton.get_bone_parent(bone))
			idle.set_bone_rest(bone, fighter.skeleton.get_bone_rest(bone))
		world.add_child(idle)
		fighter.sample_standby_skeleton(idle)
		check(poses(idle) == expected, "portrait uses canonical standby sample")
		idle.queue_free()
		await frames(5)
		var pixels := PackedByteArray()
		if DisplayServer.get_name() != "headless": pixels = portrait.get_texture().get_image().get_data()
		for action in VrmFighter.DURATIONS:
			fighter.play_motion(action)
			for phase in [.2, .6, 1.1]:
				fighter.sample_motion(phase, phase)
				await frames(2)
				check(poses(portrait._standby_skeleton) == expected, "standby independent of " + str(action))
				if not pixels.is_empty(): check(portrait.get_texture().get_image().get_data() == pixels, "portrait pixels remain standby during " + str(action))
		hud.hide()
		await frames()
		check(portrait.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden HUD stops portrait rendering")
		hud.show()
		await frames()
		check(portrait.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "visible HUD resumes portrait")
		hud.set_battle_mode(true)
		check(portrait.render_target_update_mode == SubViewport.UPDATE_DISABLED, "battle-covered HUD stops portrait")
		hud.set_battle_mode(false)
		await shot("hero-original-" + str(model))
		if DisplayServer.get_name() != "headless":
			portrait.get_texture().get_image().save_png(output.path_join("hero-portrait-%d.png" % model))
		var old: WeakRef = weakref(portrait._standby_actor)
		fighter.apply_profile(PlayerProfile.npc_profile(3 if model == 0 else 5))
		portrait.bind(fighter, model)
		await frames()
		check(old.get_ref() == null, "rebind releases previous replica")
		check(portrait._standby_skeleton != fighter.skeleton, "rebound profile keeps independent skeleton")
		await shot("hero-standby-" + str(model))
		hud.set_portrait(model, null)
		portrait.queue_free()
		fighter.queue_free()
		await frames(3)
	hud.queue_free()
	world.queue_free()
	await frames()
	# All49 real panels keep the whole prepared image, with no resource regeneration.
	await CreaturePortrait.preload_catalog_async(self)
	DeviceSettings.set_style(DeviceSettings.DEVICE)
	var generations := preload("res://scenes/ui/portrait_matte.gd").generation_count
	var ids := CreaturePortrait.REFERENCE_TEXTURES.keys()
	for sheet in 3:
		gallery = Control.new()
		root.add_child(gallery)
		var bg := ColorRect.new()
		bg.color = Color("111820")
		bg.size = Vector2(1280, 720)
		gallery.add_child(bg)
		for cell in 18:
			var index := sheet * 18 + cell
			if index >= ids.size(): break
			var panel := OpponentPanel.new()
			gallery.add_child(panel)
			panel.present(CardDB.creature(ids[index]), index, 420)
			panel.show_context("battle")
			await frames(1)
			panel.position = Vector2(24 + (cell % 6) * 208, 32 + (cell / 6) * 220)
			check(not panel._portrait._hud_crop_enabled and panel._portrait._fallback.texture == CreaturePortrait.presentation_texture(ids[index]), "full silhouette " + str(ids[index]))
			check(panel._portrait._viewport == null, "known creature stays static without live animation")
			check(panel._portrait._backdrop.material == CreaturePortrait._background_material(CardDB.creature(ids[index]).attribute, true), "cached soft element backdrop")
		await shot("creatures-full-panel-" + str(sheet))
		gallery.queue_free()
		await frames()
	check(preload("res://scenes/ui/portrait_matte.gd").generation_count == generations, "panel reuse does not recompute masks")
	check(Engine.max_fps == 60, "test wrapper holds 60 FPS")
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(4)
	print("PORTRAIT STANDBY ", checks, "/", failures)
	quit(1 if failures else 0)
