extends SceneTree
## Actual preset/selector paths, default outfits and neckline at close range.
var checks := 0
var failures := 0
var stage := OS.get_environment("SFERY_WARDROBE_FIT_STAGE")
var out := "res://build/checks/wardrobe-fit"
var editor: CharacterEditor
var rows: Array = []
var neck_only := OS.get_environment("SFERY_WARDROBE_FIT_NECK_ONLY") == "1"
var parts: Script
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",text)
func frames() -> void:
	for i in 4: await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
func capture(name: String, neck: bool = false, angle: float = 0, distance_scale: float = 1) -> void:
	editor.avatar.rotation.y = angle
	editor.set_face_view(false)
	if neck:
		var y: float = editor.avatar.skeleton.get_bone_global_rest(editor.avatar.skeleton.find_bone("Neck")).origin.y
		editor.camera.position = Vector3(0,y+.005,.48)
		editor.camera.look_at(Vector3(0,y-.008,0))
	if not neck: editor.camera.position.z *= distance_scale
	await frames()
	if DisplayServer.get_name() != "headless":
		check(editor.viewport.get_texture().get_image().save_png(out.path_join(name+".png")) == OK,"capture "+name)
func click_preset(text: String) -> void:
	for button in editor.find_children("*","Button",true,false):
		if button.text == text:
			button.pressed.emit()
			editor._set_playing(false)
			return
	check(false,"real preset button present "+text)
func sport_colors() -> Array:
	var colors: Array = []
	for i in editor.avatar.body_part.mesh.get_surface_count():
		var source: ShaderMaterial = parts.material_for(editor.avatar.body_part.mesh,i)
		if "Tops_" in source.resource_name or "Bottoms_" in source.resource_name:
			var material := editor.avatar.body_part.get_surface_override_material(i) as ShaderMaterial
			colors.append({"name":source.resource_name,"base":material.get_shader_parameter("_Color"),"shade":material.get_shader_parameter("_ShadeColor"),"texture":(material.get_shader_parameter("_MainTex") as Texture2D).get_instance_id(),"palette":material.get_shader_parameter("palette_enabled")})
	return colors
func run() -> void:
	if stage.is_empty(): stage = "after"
	out = out.path_join(stage)
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280,900)
	root.content_scale_size = root.size
	# Match the existing sport stand: avoid a compile-time VRM parts load cycle.
	parts = load("res://scenes/avatar/vrm_parts.gd")
	editor = CharacterEditor.new()
	root.add_child(editor)
	editor._set_playing(false)
	check(Engine.max_fps == 60,"wrapper60FPS")
	var models: Array[int] = [0,1]
	if neck_only or OS.get_environment("SFERY_WARDROBE_FIT_MODELS") == "0": models.resize(1)
	for model in models:
		var p := PlayerProfile.DEFAULT.duplicate(true)
		p.vrm_model = model
		editor._apply(p)
		# Record real one-based selector labels, then exercise both reported IDs.
		for number in ([6] if neck_only else [6,7]):
			var index: int = int(number)-1
			editor.selectors.vrm_clothes.item_selected.emit(index)
			editor._set_playing(false)
			rows.append({"model":model,"ui_number":number,"index":index,"label":editor.selectors.vrm_clothes.get_item_text(index)})
			check(editor.draft.vrm_clothes == index,"real numbered selection %d/%d" % [model,number])
			await capture("%d-selector-%d" % [model,number])
		for kind in (["street"] if neck_only else ["street","sport"]):
			editor._apply(p)
			await click_preset("Уличный образ" if kind == "street" else "Спортивный образ")
			check(editor.draft.vrm_clothes == (parts.BOMBER_IDS[model] if kind == "street" else parts.SPORT_IDS[model]),"preset matches correct base outfit")
			check(editor.draft.vrm_outfit == 0 and editor.selectors.vrm_outfit.selected == 0,"preset initial palette is original")
			await capture("%d-%s-default" % [model,kind])
			await capture("%d-%s-neck" % [model,kind],true)
			await capture("%d-%s-neck-angle" % [model,kind],true,.60)
			if kind == "street" and stage != "before":
				var skin_surfaces := 0
				for surface in editor.avatar.body_part.mesh.get_surface_count():
					var material: ShaderMaterial = parts.material_for(editor.avatar.body_part.mesh,surface)
					if "_SKIN" in material.resource_name: skin_surfaces += 1
				check(skin_surfaces == (1 if model == 0 else 2),"street skin uses the correct single donor owner or target lining")
				editor._select(1,"vrm_skin")
				editor._set_playing(false)
				await capture("%d-street-skin-neck" % model,true)
				editor._select(0,"vrm_skin")
				editor._set_playing(false)
			if kind == "sport":
				var colors := sport_colors()
				check(colors.size() == 2,"sport has top and pants")
				if stage != "before":
					check(colors[0].base == colors[1].base and colors[0].shade == colors[1].shade,"default sport top and pants share authored colors")
					check(colors[0].texture == colors[1].texture,"default sport uses matching fabric")
				rows.append({"model":model,"sport_default_top":str(colors[0].base),"sport_default_pants":str(colors[1].base),"same_fabric":colors[0].texture == colors[1].texture})
			editor.selectors.vrm_outfit.item_selected.emit(1)
			editor._set_playing(false)
			await capture("%d-%s-palette" % [model,kind])
			editor.selectors.vrm_outfit.item_selected.emit(0)
			editor._set_playing(false)
			await capture("%d-%s-reset-neck" % [model,kind],true)
			check(editor.draft.vrm_outfit == 0,"palette reset updates draft")
		if neck_only:
			await capture("%d-street-far" % model,false,0,1.7)
			continue
		# Saved denim must stay disabled in sports, then return on the street outfit.
		await click_preset("Уличный образ")
		editor._select(14,"vrm_denim")
		await click_preset("Спортивный образ")
		check(editor.draft.vrm_denim == 14 and editor.selectors.vrm_denim.disabled,"sport preserves disabled denim selection")
		await capture("%d-sport-after-denim" % model)
		await click_preset("Уличный образ")
		check(editor.draft.vrm_denim == 14 and not editor.selectors.vrm_denim.disabled,"street restores explicit denim selector")
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
	print("WARDROBE FIT ",checks,"/",failures," ",JSON.stringify(rows))
	quit.call_deferred(1 if failures else 0)
