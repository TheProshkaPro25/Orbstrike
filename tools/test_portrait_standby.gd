extends SceneTree

const BATTLE_GAPS := preload("res://scenes/ui/portrait_background_regions.gd").BATTLE_REGIONS
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
	# All49 real panels keep the whole prepared image, with no resource regeneration.
	await CreaturePortrait.preload_catalog_async(self)
	DeviceSettings.set_style(DeviceSettings.DEVICE)
	var generations := preload("res://scenes/ui/portrait_matte.gd").generation_count
	var ids := CreaturePortrait.REFERENCE_TEXTURES.keys()
	var portrait_regions: Array = []
	for sheet in 3:
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
			var battle_texture := CreaturePortrait.presentation_texture(ids[index], true)
			check(not panel._portrait._hud_crop_enabled and panel._portrait._fallback.texture == battle_texture, "full silhouette " + str(ids[index]))
			check(panel._portrait._viewport == null, "known creature stays static without live animation")
			check(panel._portrait._backdrop.material == panel._portrait._battle_backdrop and panel._portrait._fallback.material == CreaturePortrait._battle_art, "battle matte and edge filter use the prepared silhouette")
			var portrait: CreaturePortrait = panel._portrait
			check(portrait._battle_frame.is_visible_in_tree() and portrait._battle_frame.size == portrait.size and portrait._battle_backdrop.get_shader_parameter("element") == CardDB.creature(ids[index]).attribute, "framed portrait fills its own rectangle with the matching element")
			check(portrait.clip_children == CanvasItem.CLIP_CHILDREN_ONLY and portrait._fallback.get_rect().position == Vector2.ONE * CreaturePortrait.BATTLE_ART_INSET, "rounded mask covers all layers and art stays inside the frame")
			if index == 1:
				panel.show_context("reveal")
				check(not portrait._battle_frame.visible and portrait._fallback.material == null and portrait.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED, "ordinary reveal keeps its own unframed style")
				check(portrait._fallback.texture == CreaturePortrait.presentation_texture(ids[index]) and portrait._fallback.texture != battle_texture, "ordinary reveal retains the original prepared mask")
				panel.show_context("battle")
			panel.position = Vector2(24 + (cell % 6) * 208, 12 + (cell / 6) * 235)
			if DisplayServer.get_name() != "headless":
				var source := battle_texture.get_image()
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
	_check_reviewed_battle_gaps()
	await _check_opaque_edge_filter()
	await _check_screen_edge_filter()
	check(Engine.max_fps == 60, "test wrapper holds 60 FPS")
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(4)
	print("PORTRAIT STANDBY ", checks, "/", failures)
	quit(1 if failures else 0)


func _check_reviewed_battle_gaps() -> void:
	for id: StringName in BATTLE_GAPS:
		var standard := CreaturePortrait.presentation_texture(id).get_image()
		var battle := CreaturePortrait.presentation_texture(id, true).get_image()
		var before := standard.get_data()
		var after := battle.get_data()
		var expected := 0
		for region: Dictionary in BATTLE_GAPS[id].components:
			expected += int(region.pixels)
			check(standard.get_pixelv(region.seed).a == 1.0 and battle.get_pixelv(region.seed).a == 0.0, "battle removes the reviewed gap " + str(id) + " " + str(region.seed))
		var removed := 0
		var unexpected := 0
		for offset in range(0, before.size(), 4):
			if before[offset] != after[offset] or before[offset + 1] != after[offset + 1] or before[offset + 2] != after[offset + 2]:
				unexpected += 1
			if before[offset + 3] == after[offset + 3]:
				continue
			var minimum := mini(before[offset], mini(before[offset + 1], before[offset + 2]))
			var maximum := maxi(before[offset], maxi(before[offset + 1], before[offset + 2]))
			if before[offset + 3] == 255 and after[offset + 3] == 0 and minimum >= 244 and maximum - minimum <= 10:
				removed += 1
			else:
				unexpected += 1
		check(removed == expected and unexpected == 0, "only the reviewed opaque neutral pixels changed coverage " + str(id))


func _check_opaque_edge_filter() -> void:
	if DisplayServer.get_name() == "headless": return
	var test_view := ColorRect.new()
	test_view.color = Color("111820")
	test_view.size = Vector2(94, 46)
	test_view.position = Vector2(20, 20)
	root.add_child(test_view)
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var pigment := Color(0.70, 0.43, 0.20)
	image.fill_rect(Rect2i(6, 4, 21, 24), pigment)
	var pale := Color(0.93, 0.96, 0.99)
	image.fill_rect(Rect2i(5, 9, 1, 14), pale)
	image.fill_rect(Rect2i(27, 9, 1, 14), Color(pale, 0.52))
	image.set_pixel(15, 9, pale)
	image.fill_rect(Rect2i(1, 1, 3, 3), pigment)
	image.set_pixel(1, 1, Color.TRANSPARENT)
	image.set_pixel(2, 2, pale)
	var art := ImageTexture.create_from_image(image)
	for index in 2:
		var portrait := TextureRect.new()
		portrait.texture = art
		portrait.position = Vector2(6 + index * 46, 6)
		if index == 1: portrait.material = CreaturePortrait._battle_art
		test_view.add_child(portrait)
	await frames()
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var origin := Vector2i(26, 26)
	var shifted := Vector2i(46, 0)
	for sample: Vector2i in [Vector2i(5, 16), Vector2i(27, 16), Vector2i(2, 2)]:
		var edge := origin + sample
		var filtered := picture.get_pixelv(edge + shifted)
		check(picture.get_pixelv(edge).g - filtered.g > 0.14, "opaque, translucent and diagonal rims lose their pale fringe")
		check(filtered.r > 0.20, "edge recolouring retains the silhouette sample")
	for sample: Vector2i in [Vector2i(15, 9), Vector2i(16, 16), Vector2i(0, 0)]:
		var a := picture.get_pixelv(origin + sample)
		var b := picture.get_pixelv(origin + shifted + sample)
		check(Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() < 0.02, "inside white, inside pigment and clear area keep their colour")
	test_view.queue_free()


func _check_screen_edge_filter() -> void:
	if DisplayServer.get_name() == "headless": return
	var background := Color("111820")
	var test_view := ColorRect.new()
	test_view.color = background
	test_view.size = Vector2(150, 158)
	test_view.position = Vector2(20, 20)
	root.add_child(test_view)
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var saturated_rim := Color(0.22, 0.86, 0.95)
	image.fill_rect(Rect2i(12, 12, 40, 40), Color(0.13, 0.43, 0.49))
	image.fill_rect(Rect2i(12, 20, 4, 24), saturated_rim)
	image.fill_rect(Rect2i(28, 26, 8, 12), Color.WHITE)
	image.fill_rect(Rect2i(35, 7, 18, 3), saturated_rim)
	var texture := ImageTexture.create_from_image(image)
	var sizes := [64, 32, 16]
	var origins: Array[Vector2i] = [Vector2i(24, 25), Vector2i(24, 96), Vector2i(24, 135)]
	for i in sizes.size():
		for side in 2:
			var portrait := TextureRect.new()
			portrait.texture = texture
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.size = Vector2.ONE * sizes[i]
			if side == 1: portrait.material = CreaturePortrait._battle_art
			test_view.add_child(portrait)
			portrait.global_position = Vector2(origins[i] + Vector2i(73 * side, 0))
	await frames()
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	for i in sizes.size():
		var scale: float = sizes[i] / 64.0
		var origin := origins[i]
		var offset := Vector2i(73, 0)
		var at := origin + Vector2i(Vector2(12, 34) * scale)
		var raw := picture.get_pixelv(at)
		var filtered := picture.get_pixelv(at + offset)
		check(raw.g - filtered.g >= 0.17, "saturated outer rim is subdued at %dpx" % sizes[i])
		check(filtered.b > filtered.r and filtered.g > background.g + 0.12, "filtered edge stays present and keeps its hue at %dpx" % sizes[i])
		at = origin + Vector2i(Vector2(32, 32) * scale)
		check(picture.get_pixelv(at).is_equal_approx(picture.get_pixelv(at + offset)), "interior white is unchanged at %dpx" % sizes[i])
		at = origin + Vector2i(Vector2(44, 8) * scale)
		var thin := picture.get_pixelv(at + offset)
		var raw_contrast := picture.get_pixelv(at).g - background.g
		var filtered_contrast := thin.g - background.g
		check(filtered_contrast >= maxf(0.12, 0.65 * raw_contrast) and thin.b > thin.r,
			"thin bright tip stays visible and keeps its contrast at %dpx" % sizes[i])
	test_view.queue_free()
