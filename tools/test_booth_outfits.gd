extends "res://tools/test_wardrobe_fit.gd"
## Normal editor, per-base availability, thumbnails, saved profile and throw samples.
var boot_paths: Array[String]

func run() -> void:
	out = "res://build/checks/booth-outfits"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 900)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_size(root.get_viewport_rid(), 1280, 900)
	parts = load("res://scenes/avatar/vrm_parts.gd")
	var startup_catalog = load("res://scenes/loading/startup_catalog.gd")
	boot_paths = startup_catalog.resource_paths()
	startup_catalog = null
	editor = CharacterEditor.new()
	root.add_child(editor)
	editor._set_playing(false)
	check(Engine.max_fps == 60, "wrapper limits 60 FPS")
	var requested := OS.get_cmdline_user_args()
	if requested.is_empty():
		check(WardrobeCatalog.available_ids(0) == [0,1,2,3,4,5,6,7,8,11,12,13], "Sakurada retains existing IDs and retires the two incorrect slots")
		check(WardrobeCatalog.available_ids(1) == range(13), "Vita keeps existing IDs and receives two additional slots")
		check(WardrobeCatalog.asset_path(1,11).ends_with("/jacket_pants_1.res") and WardrobeCatalog.asset_path(1,12).ends_with("/dreamy_angel_1.res"), "the two corrected slots use the prepared Vita assets")
	var checked := 0
	for model in 2:
		var profile := PlayerProfile.DEFAULT.duplicate()
		profile.vrm_model = model
		editor._apply(profile)
		editor.category_buttons.clothes.pressed.emit()
		var available := WardrobeCatalog.available_ids(model)
		for id in WardrobeCatalog.SLOT_COUNT:
			check(editor.gallery_buttons.vrm_clothes[id].visible == (id in available), "gallery availability %d/%d" % [model,id])
		for id in available:
			if not WardrobeCatalog.is_addition(model,id): continue
			if not requested.is_empty() and "%d/%d" % [model,id] not in requested: continue
			await inspect_outfit(profile, model, id)
			checked += 1
	var expected: int = WardrobeCatalog.ADDITIONS[0].size() + WardrobeCatalog.ADDITIONS[1].size() if requested.is_empty() else requested.size()
	check(checked == expected, "every requested outfit exercised")
	check(parts.outfit_mesh(0,6) == parts.BODY[0][6] and parts.outfit_mesh(1,7) == parts.BODY[1][7], "sports numbers remain stable")
	editor._close()
	var sound_script = load("res://scenes/audio/sound.gd")
	if is_instance_valid(sound_script._inst): sound_script._inst.queue_free()
	sound_script = null
	parts.materials.clear()
	parts = null
	await frames()
	print("BOOTH OUTFITS ", checked, " outfits, ", checks, "/", failures)
	quit.call_deferred(1 if failures else 0)

func inspect_outfit(profile: Dictionary, model: int, id: int) -> void:
	editor._apply(profile)
	editor._set_playing(false)
	var original_actor := editor.avatar.actor
	var original_skeleton := editor.avatar.skeleton
	var original_hair := editor.avatar.hair_part.mesh
	var tile: Button = editor.gallery_buttons.vrm_clothes[id]
	tile.pressed.emit()
	editor._set_playing(false)
	var label := "%d-%02d" % [model,id+1]
	var path := WardrobeCatalog.asset_path(model,id)
	check(editor.draft.vrm_model == model and editor.draft.vrm_clothes == id and tile.button_pressed, label + " gallery selects correct base/outfit")
	check(editor.avatar.actor == original_actor and editor.avatar.skeleton == original_skeleton and editor.avatar.hair_part.mesh == original_hair, label + " original actor, skeleton and hairstyle stay in place")
	check(editor.avatar.body_part.mesh.resource_path == path and editor.avatar.body_part.mesh.get_meta("part_source") == model, label + " prepared mesh targets correct skin")
	check(editor.avatar.hair_part.visible == not path.ends_with("/orchid_armor_0.res"), label + " full helmet hides hair without changing the style")
	check(editor.selectors.vrm_denim.disabled and not editor.avatar.case_part.visible, label + " incompatible overlays are hidden")
	check(boot_paths.has(path), label + " Boot preloads this costume")
	var thumbnail := tile.icon as AtlasTexture
	var atlas := thumbnail.atlas.get_image()
	var region := Rect2i(thumbnail.region)
	check(Rect2i(Vector2i.ZERO,atlas.get_size()).encloses(region), label + " thumbnail fits in atlas")
	var pixels := atlas.get_region(region)
	check(pixels.get_pixel(80,60) != pixels.get_pixel(0,0), label + " thumbnail displays the outfit")
	check(validate_geometry(editor.avatar.body_part.mesh, original_skeleton.get_bone_count()), label + " finite skinned geometry and valid weights")
	await capture(label+"-front",false,0.0,.88)
	await capture(label+"-quarter",false,.72,.88)
	await capture(label+"-back",false,PI,.88)
	var color := Color("6683c1")
	editor.outfit_color.color_changed.emit(color)
	check(editor.draft.vrm_outfit_color == "6683c1" and editor.avatar.appearance_profile.vrm_outfit_color == "6683c1", label + " custom color applies to the profile")
	var dyed := 0
	for entry in editor.avatar.palette_materials:
		if entry.role == "outfit" and entry.material.get_shader_parameter("palette_enabled") == true: dyed += 1
	check(dyed > 0, label + " textile uses the custom color")
	var mesh := editor.avatar.body_part.mesh
	var originals_are_neutral := true
	for surface in mesh.get_surface_count():
		var material: ShaderMaterial = parts.material_for(mesh, surface)
		if material.get_shader_parameter("palette_enabled") == true: originals_are_neutral = false
	check(originals_are_neutral, label + " color does not affect shared materials")
	await capture(label+"-dye",false,.72,.88)
	var file := "user://booth-outfit-test.json"
	var store := PlayerProfile.new()
	check(store.save_to(editor.draft,file) == OK, label + " profile saves")
	store.load_from(file)
	check(store.value.vrm_clothes == id and store.value.vrm_model == model and store.value.vrm_outfit_color == "6683c1", label + " exact outfit, base and color survive reload")
	for suffix in ["",".tmp",".bak"]: DirAccess.remove_absolute(file + suffix)
	editor.selectors.vrm_outfit.item_selected.emit(0)
	editor._start_motion(1)
	editor._set_playing(false)
	for time in [.48, .86]:
		editor.preview_time = time
		editor._sample_preview()
		await capture("%s-throw-%d" % [label, int(time*100)],false,.54,.88)
	editor.select_model(1-model)
	check(editor.draft.vrm_clothes == 0 and editor.avatar.selected == 1-model, label + " new outfit never moves to the other base")
	check(editor.avatar.hair_part.visible, label + " hairstyle is visible again in a compatible outfit")

func validate_geometry(mesh: ArrayMesh, bone_count: int) -> bool:
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty(): return false
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if weights.size() != bones.size(): return false
		var stride := weights.size()/vertices.size()
		if stride not in [4,8]: return false
		for vertex in vertices.size():
			if not vertices[vertex].is_finite(): return false
			var sum := 0.0
			for k in stride:
				var index := vertex*stride+k
				if bones[index] < 0 or bones[index] >= bone_count or not is_finite(weights[index]) or weights[index] < 0.0: return false
				sum += weights[index]
			if absf(sum-1.0) > .014: return false
	return true
