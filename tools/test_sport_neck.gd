extends "res://tools/test_wardrobe_fit.gd"
## Sport neckline only: actual preset, default/palette/reset/skin, both bases.
func run() -> void:
	stage = OS.get_environment("SFERY_SPORT_NECK_STAGE")
	if stage.is_empty(): stage = "after"
	out = "res://build/checks/sport-neck".path_join(stage)
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280,900)
	root.content_scale_size = root.size
	parts = load("res://scenes/avatar/vrm_parts.gd")
	editor = CharacterEditor.new()
	root.add_child(editor)
	editor._set_playing(false)
	check(Engine.max_fps == 60,"wrapper60FPS")
	for model in 2:
		var p := PlayerProfile.DEFAULT.duplicate(true)
		p.vrm_model = model
		editor._apply(p)
		await click_preset("Спортивный образ")
		check(editor.draft.vrm_clothes == parts.SPORT_IDS[model],"real sport button selects matching outfit")
		await capture("%d-sport-default" % model)
		await capture("%d-sport-neck" % model,true)
		await capture("%d-sport-neck-angle" % model,true,.60)
		editor._select(1,"vrm_skin")
		editor._set_playing(false)
		await capture("%d-sport-tone" % model,true)
		editor._select(0,"vrm_skin")
		editor.selectors.vrm_outfit.item_selected.emit(1)
		editor._set_playing(false)
		await capture("%d-sport-palette-neck" % model,true)
		editor.selectors.vrm_outfit.item_selected.emit(0)
		editor._set_playing(false)
		await capture("%d-sport-reset-neck" % model,true)
		await capture("%d-sport-far" % model,false,0,1.7)
		var colors := sport_colors()
		check(colors.size() == 2 and colors[0].base == colors[1].base and colors[0].shade == colors[1].shade,"accepted sport top and pants colors retained")
		var materials: Array = []
		for i in editor.avatar.body_part.mesh.get_surface_count():
			var source: ShaderMaterial = parts.material_for(editor.avatar.body_part.mesh,i)
			materials.append({"surface":i,"source":source.resource_name,"color":str(source.get_shader_parameter("_Color")),"shader":source.shader.resource_path})
		rows.append({"model":model,"index":editor.draft.vrm_clothes,"ui_label":editor.selectors.vrm_clothes.get_item_text(editor.draft.vrm_clothes),"materials":materials})
	var file := FileAccess.open(out.path_join("summary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"stage":stage,"checks":checks,"failures":failures,"rows":rows,"fps_cap":Engine.max_fps},"  "))
	file.close()
	editor._close()
	var sound_script = load("res://scenes/audio/sound.gd")
	if is_instance_valid(sound_script._inst): sound_script._inst.queue_free()
	sound_script = null
	parts.materials.clear()
	parts = null
	await frames()
	print("SPORT NECK ",checks,"/",failures)
	quit.call_deferred(1 if failures else 0)
