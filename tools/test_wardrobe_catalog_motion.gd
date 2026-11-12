extends "res://tools/test_wardrobe_fit.gd"
## Capture gaps in the earlier front/throw pass through the real editor and motion sampler.

const VIEWS := [
	[0, 0.0, PI / 2.0, "side"], [0, 0.0, PI, "back"],
	[4, 0.62, -0.66, "gate-62"], [4, 0.98, 2.53, "gate-98"],
	[5, 0.68, 0.70, "victory-68"], [5, 1.00, -2.53, "victory-100"],
]

func run() -> void:
	var stage_name := OS.get_environment("SFERY_WARDROBE_CATALOG_STAGE")
	if stage_name.is_empty(): stage_name = "baseline"
	var requested := OS.get_environment("SFERY_WARDROBE_CATALOG_SLOTS").split(",", false)
	out = "res://build/checks/wardrobe-catalog-motion".path_join(stage_name)
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 900)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_size(root.get_viewport_rid(), 1280, 900)
	parts = load("res://scenes/avatar/vrm_parts.gd")
	editor = CharacterEditor.new()
	root.add_child(editor)
	editor.category_buttons.clothes.pressed.emit()
	editor._set_playing(false)
	check(Engine.max_fps == 60, "wrapper limits 60 FPS")
	for model in 2:
		var profile := PlayerProfile.DEFAULT.duplicate(true)
		profile.vrm_model = model
		for id in WardrobeCatalog.available_ids(model):
			var stem := "%d-%02d" % [model, id + 1]
			if not requested.is_empty() and stem not in requested: continue
			editor._apply(profile)
			editor.gallery_buttons.vrm_clothes[id].pressed.emit()
			check(editor.draft.vrm_clothes == id and editor.avatar.selected == model, "selected " + stem)
			check(editor.avatar.body_part.mesh == parts.outfit_mesh(model, id), "equipped " + stem)
			var last_motion := -1
			for view in VIEWS:
				var motion: int = view[0]
				if motion != last_motion:
					editor.motion_select.item_selected.emit(motion)
					editor._set_playing(false)
					last_motion = motion
				editor.timeline.value = view[1]
				await capture("%s-%s" % [stem, view[3]], false, view[2], 0.89)
			rows.append({"model": model, "slot": id + 1, "name": WardrobeCatalog.outfit_name(model, id)})
	check(rows.size() == (25 if requested.is_empty() else requested.size()), "all requested costumes captured")
	var report := FileAccess.open(out.path_join("summary.json"), FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"checks": checks, "failures": failures, "fps_cap": Engine.max_fps,
			"graphics": DisplayServer.get_name() != "headless", "views": VIEWS, "outfits": rows}, "  "))
		report.close()
	editor._close()
	var sound_script = load("res://scenes/audio/sound.gd")
	if is_instance_valid(sound_script._inst): sound_script._inst.queue_free()
	sound_script = null
	parts.materials.clear()
	parts = null
	await frames()
	print("WARDROBE CATALOG MOTION ", checks, "/", failures, " outfits=", rows.size())
	quit.call_deferred(int(failures > 0))
