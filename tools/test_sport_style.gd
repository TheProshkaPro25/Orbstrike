extends "res://tools/test_wardrobe_fit.gd"
## Matched angles for one sports costume and a dyed motion sample.
var model := int(OS.get_environment("SFERY_SPORT_STYLE_MODEL") == "1")
var fit_scale := 1.0

func run() -> void:
	stage = OS.get_environment("SFERY_SPORT_STYLE_STAGE")
	if stage.is_empty(): stage = "after"
	out = "res://build/checks/sport-style".path_join(stage)
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 900)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_size(root.get_viewport_rid(), 1280, 900)
	parts = load("res://scenes/avatar/vrm_parts.gd")
	editor = CharacterEditor.new()
	root.add_child(editor)
	var profile := PlayerProfile.DEFAULT.duplicate(true)
	profile.vrm_model = model
	editor._apply(profile)
	editor.category_buttons.clothes.pressed.emit()
	var outfit_id: int = VrmParts.SPORT_IDS[model]
	editor.gallery_buttons.vrm_clothes[outfit_id].pressed.emit()
	var neck := editor.avatar.skeleton.find_bone("Neck")
	fit_scale = VrmParts.SKINS[model].get_bind_pose(neck).affine_inverse().origin.y/1.59513
	var original_mesh_path := out.path_join("tracksuit_%d.res" % model)
	if stage == "before" and ResourceLoader.exists(original_mesh_path):
		editor.avatar._hold_materials_until_draw()
		editor.avatar.body_part.mesh = load(original_mesh_path)
		editor.avatar._localize_materials()
		editor.avatar.apply_profile(editor.draft)
		editor._start_motion(0)
	editor._set_playing(false)
	check(Engine.max_fps == 60, "test wrapper limits the client to 60 FPS")
	check(editor.draft.vrm_model == model and editor.draft.vrm_clothes == outfit_id, "gallery selects this base's sports outfit")
	if stage != "before": check_details()
	for view in [["front", 0.0], ["left", PI/2], ["right", -PI/2], ["back", PI], ["three-quarter", .66]]:
		await capture(view[0], false, view[1], .88)
	await detail("jacket", .30, 1.35, 1.12)
	await detail("shoes", .55, .17, 1.36)
	var original := editor.viewport.get_texture().get_image().get_data()
	editor.outfit_color.color_changed.emit(Color("c94a35"))
	await detail("shoes-dyed", .55, .17, 1.36)
	check(editor.draft.vrm_outfit_color == "c94a35" and editor.viewport.get_texture().get_image().get_data() != original, "custom RGB changes the rendered costume")
	if stage != "before":
		var body := editor.avatar.body_part
		for slot in range(1, body.mesh.get_surface_count()):
			var material := body.get_surface_override_material(slot) as ShaderMaterial
			var expected := "_CLOTH" in material.resource_name
			check((material.get_shader_parameter("palette_enabled") == true) == expected, "only textile is dyed: " + material.resource_name)
	editor._start_motion(1)
	editor._set_playing(false)
	editor.preview_time = .73
	editor._sample_preview()
	await capture("throw-dyed", false, .94, .88)
	await capture("throw-dyed-opposite", false, -1.25, .88)
	editor._start_motion(0)
	editor._set_playing(false)
	editor.selectors.vrm_outfit.item_selected.emit(0)
	await detail("shoes-reset", .55, .17, 1.36)
	check(editor.viewport.get_texture().get_image().get_data() == original, "original colors return pixel for pixel")
	editor._close()
	var sound_script = load("res://scenes/audio/sound.gd")
	if is_instance_valid(sound_script._inst): sound_script._inst.queue_free()
	sound_script = null
	parts.materials.clear()
	parts = null
	await frames()
	print("SPORT STYLE ", checks, "/", failures)
	quit.call_deferred(1 if failures else 0)

func detail(name: String, angle: float, height: float, distance: float) -> void:
	editor.avatar.rotation.y = angle
	editor.camera.position = Vector3(0, height, distance)*fit_scale
	editor.camera.look_at(Vector3(0, height*fit_scale, 0))
	await frames()
	check(editor.viewport.get_texture().get_image().save_png(out.path_join(name + ".png")) == OK, "capture " + name)

func check_details() -> void:
	var body := editor.avatar.body_part.mesh
	var names: PackedStringArray = body.get_meta("surface_materials")
	check(names.size() == body.get_surface_count(), "every sport surface has a material")
	var stripe_slot := names.find("Sport_Accent_CLOTH")
	check(stripe_slot >= 0, "side stripe surface exists")
	if stripe_slot < 0: return
	var stripes := body.surface_get_arrays(stripe_slot)
	var ribbons := islands(stripes)
	check(ribbons.size() == 8, "eight complete ribbons with no loose pieces")
	var counts := {}
	for ribbon in ribbons:
		var side := 1 if ribbon[0].x > 0.0 else -1
		var min_y := INF
		var max_y := -INF
		for vertex: Vector3 in ribbon:
			min_y = minf(min_y, vertex.y)
			max_y = maxf(max_y, vertex.y)
		var sleeve := min_y > fit_scale
		var key := Vector2i(side, int(sleeve))
		counts[key] = counts.get(key, 0) + 1
		var lateral := true
		var garment := body.surface_get_arrays(1 if sleeve else 2)
		for vertex: Vector3 in ribbon:
			lateral = lateral and side * vertex.x > outer_x(garment, side, vertex.y) - .023*fit_scale
		check(lateral, "strip occupies the outward side of its limb")
		check(max_y - min_y > (.34 if sleeve else .88)*fit_scale, "each stripe spans its limb")
	check(counts.size() == 4 and counts.values().all(func(count: int) -> bool: return count == 2), "two stripes on each sleeve and each trouser leg")

func islands(arrays: Array) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var adjacency: Array[Array] = []
	for index in vertices.size(): adjacency.append([])
	for tri in indices.size()/3:
		for corner in 3:
			var a := indices[tri*3+corner]
			var b := indices[tri*3+(corner+1)%3]
			adjacency[a].append(b)
			adjacency[b].append(a)
	var seen := {}
	var groups := []
	for index in vertices.size():
		if seen.has(index): continue
		var pending := [index]
		var group := []
		seen[index] = true
		while not pending.is_empty():
			var next: int = pending.pop_back()
			group.append(vertices[next])
			for neighbor in adjacency[next]:
				if seen.has(neighbor): continue
				seen[neighbor] = true
				pending.append(neighbor)
		groups.append(group)
	return groups

func outer_x(arrays: Array, side: int, y: float) -> float:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var edge := -INF
	for tri in indices.size()/3:
		for corner in 3:
			var a := vertices[indices[tri*3+corner]]
			var b := vertices[indices[tri*3+(corner+1)%3]]
			if (a.y < y) == (b.y < y): continue
			edge = maxf(edge, side * lerpf(a.x, b.x, (y-a.y)/(b.y-a.y)))
	return edge
