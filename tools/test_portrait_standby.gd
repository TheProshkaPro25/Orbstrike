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
		var metrics := preload("res://scenes/performance_metrics.gd")
		var camera_updates: int = metrics.value("portrait_camera_updates")
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
		check(not portrait.is_processing() and metrics.value("portrait_camera_updates") == camera_updates, "static camera does no per-frame work")
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
		check(portrait.render_target_update_mode in [SubViewport.UPDATE_ONCE, SubViewport.UPDATE_DISABLED] and not portrait.animated_materials, "visible static HUD uses one-shot rendering")
		if DisplayServer.get_name() != "headless":
			var cached := portrait.get_texture().get_image().get_data()
			var transform := portrait.camera.transform
			portrait.camera.position.x += 2.0
			await frames(5)
			check(portrait.get_texture().get_image().get_data() == cached, "one-shot viewport retains pixels despite camera change")
			portrait.camera.transform = transform
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
		var source_mesh: MeshInstance3D = fighter.meshes[0]
		var original_override := source_mesh.get_surface_override_material(0)
		var live := ShaderMaterial.new()
		live.shader = preload("res://scenes/avatar/mtoon_palette/mtoon.gdshader")
		live.set_shader_parameter("_UvAnimScrollX",.1)
		source_mesh.set_surface_override_material(0,live)
		portrait.bind(fighter,model)
		check(portrait.animated_materials and portrait.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "animated material rebind stays live")
		hud.hide()
		check(portrait.render_target_update_mode == SubViewport.UPDATE_DISABLED, "animated portrait still stops when hidden")
		hud.show()
		check(portrait.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "animated portrait resumes continuously")
		source_mesh.set_surface_override_material(0,original_override)
		portrait.bind(fighter,model)
		check(not portrait.animated_materials, "restoring static material returns one-shot policy")
		hud.set_portrait(model, null)
		portrait.queue_free()
		fighter.queue_free()
		await frames(3)
	# Unknown custom TIME remains live even when it imitates MToon's uniform names.
	var custom := ShaderMaterial.new()
	custom.shader = Shader.new()
	custom.shader.code = "shader_type spatial; uniform float _UvAnimScrollX=0.0; uniform float _UvAnimScrollY=0.0; uniform float _UvAnimRotation=0.0; void fragment(){ALBEDO=vec3(sin(TIME));}"
	check(FighterPortrait.material_animated(custom), "custom TIME shader never mistaken for static MToon")
	var mtoon := ShaderMaterial.new()
	mtoon.shader = preload("res://scenes/avatar/mtoon_palette/mtoon.gdshader")
	check(not FighterPortrait.material_animated(mtoon), "known MToon zero UV speeds are static")
	mtoon.set_shader_parameter("_UvAnimScrollX",.1)
	check(FighterPortrait.material_animated(mtoon), "animated MToon UV remains live")
	var plain := StandardMaterial3D.new()
	plain.next_pass = custom
	check(FighterPortrait.material_animated(plain), "animated next pass remains live")
	hud.queue_free()
	world.queue_free()
	await frames()
	# Real panels keep the same complete model render without segmentation.
	CreaturePortrait.preload_catalog()
	var generations := preload("res://scenes/ui/portrait_matte.gd").generation_count
	var ids := CreaturePortrait.RENDERED_TEXTURES.keys()
	var portrait_regions: Array = []
	for sheet in ceili(float(ids.size()) / 18.0):
		gallery = Control.new()
		root.add_child(gallery)
		var bg := ColorRect.new()
		bg.color = Color("111820")
		bg.size = Vector2(1280, 720)
		gallery.add_child(bg)
		var source_atlas := Image.create(6 * 256, 3 * 256, false, Image.FORMAT_RGBA8)
		for cell in 18:
			var index := sheet * 18 + cell
			if index >= ids.size(): break
			var panel := OpponentPanel.new()
			gallery.add_child(panel)
			panel.present(CardDB.creature(ids[index]), index, 420)
			panel.show_context("battle")
			await frames(1)
			var battle_texture := CreaturePortrait.presentation_texture(ids[index])
			check(panel._portrait._fallback.texture == battle_texture, "full silhouette " + str(ids[index]))
			check(panel._portrait._viewport == null, "known creature stays static without live animation")
			check(panel._portrait._backdrop.material == panel._portrait._battle_backdrop
				and panel._portrait._fallback.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
				"battle backdrop and mipmap filtering use the model silhouette")
			var portrait: CreaturePortrait = panel._portrait
			check(portrait._battle_frame.is_visible_in_tree() and portrait._battle_frame.size == portrait.size and portrait._battle_backdrop.get_shader_parameter("element") == CardDB.creature(ids[index]).attribute, "framed portrait fills its own rectangle with the matching element")
			check(portrait.clip_children == CanvasItem.CLIP_CHILDREN_ONLY and portrait._fallback.get_rect().position == Vector2.ONE * CreaturePortrait.BATTLE_ART_INSET, "rounded mask covers all layers and art stays inside the frame")
			if index == 1:
				panel.show_context("reveal")
				check(not portrait._battle_frame.visible and portrait.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED, "ordinary reveal keeps its own unframed style")
				check(portrait._fallback.texture == battle_texture, "ordinary reveal retains the full model render")
				panel.show_context("battle")
			panel.position = Vector2(24 + (cell % 6) * 208, 12 + (cell / 6) * 235)
			if DisplayServer.get_name() != "headless":
				var source := battle_texture.get_image()
				source.resize(256, 256, Image.INTERPOLATE_LANCZOS)
				var source_origin := Vector2i((cell % 6) * 256, (cell / 6) * 256)
				source_atlas.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), source_origin)
				var target := portrait._fallback.get_global_rect()
				var art_extent := minf(target.size.x, target.size.y)
				var art_start := target.get_center() - Vector2.ONE * art_extent * 0.5
				portrait_regions.append({"id": ids[index], "sheet": sheet, "source": [source_origin.x, source_origin.y],
					"render": [art_start.x, art_start.y, art_extent]})
		await shot("creatures-full-panel-" + str(sheet))
		if DisplayServer.get_name() != "headless":
			check(source_atlas.save_png(output.path_join("rim-source-%d.png" % sheet)) == OK, "save source alpha for rendered edge audit")
		gallery.queue_free()
		await frames()
	if DisplayServer.get_name() != "headless":
		var layout_file := FileAccess.open(output.path_join("rim-layout.json"), FileAccess.WRITE)
		layout_file.store_string(JSON.stringify(portrait_regions))
		layout_file.close()
	check(preload("res://scenes/ui/portrait_matte.gd").generation_count == generations, "panel reuse does not recompute masks")
	check(Engine.max_fps == 60, "test wrapper holds 60 FPS")
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(4)
	print("PORTRAIT STANDBY ", checks, "/", failures)
	quit(1 if failures else 0)
