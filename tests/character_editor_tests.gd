extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
func frames(count: int) -> void:
	for frame in count: await process_frame
	await RenderingServer.frame_post_draw
func write(path: String,content: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(content)
	file.close()
func capture(name: String) -> void:
	await frames(3)
	root.get_texture().get_image().save_png("res://build/checks/editor-vrm-"+name+".png")
func run() -> void:
	for model in 2:
		check(StartupCatalog.resource_paths().has("res://assets/avatars/editor/catalog_%d.png" % model),"editor atlas included in startup catalog")
	var profile := PlayerProfile.new()
	var path := "user://profile-test.json"
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(path+suffix)
	profile.load_from(path)
	check(profile.value == PlayerProfile.DEFAULT,"default without file")
	var legacy := '{"version":1,"name":"Акира","hair":2,"body":2,"skin":4}'
	write(path,legacy)
	profile.load_from(path)
	check(profile.writable and profile.value.version == 2 and profile.value.name == "Акира","v1 migration keeps name")
	check(profile.value.hair == 2 and profile.value.body == 2 and profile.value.skin == 4,"legacy appearance fields retained")
	check(profile.value.vrm_model == 0 and profile.value.vrm_height == 1,"v1 gets safe VRM defaults")
	check(FileAccess.get_file_as_string(path) == legacy,"migration does not write before save")
	var draft := profile.value.duplicate(true)
	draft.vrm_model = 1
	draft.vrm_hair = 3
	check(profile.save_to(draft,path) == OK,"save migrated profile")
	check(FileAccess.get_file_as_string(path+".bak") == legacy,"first save backs up original v1 bytes")
	profile.load_from(path)
	check(profile.value.vrm_model == 1 and profile.value.vrm_hair == 3,"new fields persist")
	write(path,'{"version":99,"name":"future"}')
	profile.load_from(path)
	check(not profile.writable and profile.save_to(draft,path) == ERR_UNAVAILABLE,"future schema guarded")
	check(FileAccess.get_file_as_string(path).contains("future"),"future bytes retained")
	write(path,'broken')
	profile.load_from(path)
	check(not profile.writable and profile.save_to(draft,path) == ERR_UNAVAILABLE,"corrupt profile guarded")
	var clean := PlayerProfile.normalized({"name":"\n ","vrm_model":999,"vrm_hair":"bad","vrm_height":-1})
	check(clean.name == PlayerProfile.DEFAULT.name and clean.vrm_model == 0 and clean.vrm_hair == 0 and clean.vrm_height == 1,"invalid fields normalized")
	var expanded := PlayerProfile.new()
	for model in 2:
		var newest := PlayerProfile.DEFAULT.duplicate(true)
		newest.vrm_model = model
		newest.vrm_style = 9
		newest.vrm_case = 1
		newest.vrm_clothes = 5 if model == 0 else 6
		newest.vrm_denim = 14
		check(expanded.save_to(newest,path+"-wardrobe") == OK,"new wardrobe choices save")
		expanded.load_from(path+"-wardrobe")
		check(expanded.value.vrm_case == 1 and expanded.value.vrm_style == 9 and expanded.value.vrm_clothes == newest.vrm_clothes and expanded.value.vrm_denim == 14,"new wardrobe and denim choices survive reload")
	check(PlayerProfile.normalized({"vrm_model":0,"vrm_clothes":WardrobeCatalog.SLOT_COUNT}).vrm_clothes == 0,"out-of-range costume falls back on male base")
	for retired in [9, 10]:
		var old_wardrobe := JSON.stringify({"version": 2, "name": "Хару", "vrm_model": 0, "vrm_clothes": retired, "vrm_style": 8, "vrm_outfit_color": "6683c1"})
		write(path, old_wardrobe)
		profile.load_from(path)
		check(profile.writable and profile.value.vrm_model == 0 and profile.value.vrm_clothes == 0,"retired costume falls back without changing the character base")
		check(profile.value.name == "Хару" and profile.value.vrm_style == 8 and profile.value.vrm_outfit_color == "6683c1","retired costume preserves character appearance and color")
		check(not profile.notice.is_empty() and FileAccess.get_file_as_string(path) == old_wardrobe,"migration shows a notice and leaves the file intact until Save")
		check(profile.save_to(profile.value, path) == OK and FileAccess.get_file_as_string(path+".bak") == old_wardrobe,"saving migration preserves the original profile backup")
		profile.load_from(path)
		check(profile.value.vrm_model == 0 and profile.value.vrm_clothes == 0 and profile.notice.is_empty(),"migrated profile reopens without repeating the migration")
	check(PlayerProfile.normalized({"vrm_model":1,"vrm_clothes":0,"vrm_denim":14}).vrm_denim == 14 and not VrmParts.supports_denim(1,0),"denim preference survives an incompatible outfit")
	check(PlayerProfile.normalized({"vrm_style":4,"vrm_clothes":1}).vrm_style == 4,"existing hair IDs stay stable")
	for model in 2:
		var sport := PlayerProfile.DEFAULT.duplicate(true)
		sport.vrm_model = model
		sport.vrm_style = 10
		sport.vrm_clothes = VrmParts.SPORT_IDS[model]
		sport.vrm_denim = 14
		sport.vrm_case = 1
		check(expanded.save_to(sport,path+"-wardrobe") == OK,"sport choices save")
		expanded.load_from(path+"-wardrobe")
		check(expanded.value.vrm_style == 10 and expanded.value.vrm_clothes == sport.vrm_clothes and expanded.value.vrm_denim == 14 and expanded.value.vrm_case == 1,"sport choices and remembered details survive reload")
		check(not VrmParts.supports_denim(model,sport.vrm_clothes) and not VrmParts.supports_case(model,sport.vrm_clothes),"sport hides incompatible denim and case")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(path+"-wardrobe"+suffix)
	profile.writable = true
	check(profile.save_to(draft,"user://missing-dir/profile.json") != OK,"write failure surfaced")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(path+suffix)
	DirAccess.remove_absolute(PlayerProfile.PATH)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	for size in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.size = size
		root.content_scale_size = size
		RenderingServer.viewport_set_size(root.get_viewport_rid(),size.x,size.y)
		var editor := CharacterEditor.new()
		host.add_child(editor)
		await frames(5)
		editor._set_playing(false)
		check(editor.avatar.has_method("sample_motion") and not editor.avatar.is_processing(),"editor drives real fighter preview")
		for key in editor.categories:
			editor._show_category(key)
			if key in ["hair", "face"]: check(editor.face_view,"face and hair categories frame face")
			if key in ["clothes", "motions"]: check(not editor.face_view,"clothes and motion categories frame body")
			for other_key in editor.categories:
				check(editor.categories[other_key].visible == (key == other_key),"only selected category visible")
		for model in 2:
			editor.select_model(model)
			for key in ["vrm_style", "vrm_clothes"]:
				var last: int = VrmParts.HAIR_STYLE_COUNT-1 if key == "vrm_style" else VrmParts.BODY[model].size()-1
				editor.gallery_buttons[key][last].pressed.emit()
				check(editor.draft[key] == last and editor.gallery_buttons[key][last].button_pressed,"gallery selects ID for base %d" % model)
		editor._show_category("hair")
		await frames(2)
		var tabs_top: float = editor.category_buttons.hair.global_position.y
		editor.options_scroll.scroll_vertical = int(editor.options_scroll.get_v_scroll_bar().max_value)
		await frames(2)
		if size.y <= 720:
			check(editor.options_scroll.scroll_vertical > 0 and is_equal_approx(editor.category_buttons.hair.global_position.y,tabs_top),"category tabs stay fixed while gallery scrolls")
		else:
			check(editor.category_buttons.hair.is_visible_in_tree(),"category tabs visible with full-height gallery")
		editor.options_scroll.scroll_vertical = 0
		var before_motion: Dictionary = editor.draft.duplicate(true)
		editor._start_motion(3)
		check(editor.avatar.motion == "command" and editor.avatar.ability_card != null,"ability motion uses fighter and card")
		editor.timeline.value = 1.0
		check(is_equal_approx(editor.preview_time,1.0) and not editor.preview_playing,"timeline scrubs and pauses")
		var paused := editor.preview_time
		await frames(3)
		check(is_equal_approx(editor.preview_time,paused),"pause freezes preview")
		editor.speed_select.item_selected.emit(2)
		check(is_equal_approx(editor.preview_speed,1.5),"speed changes")
		editor.repeat_button.toggled.emit(false)
		editor.preview_time = editor._motion_duration() - 0.01
		editor._set_playing(true)
		editor._process(0.1)
		check(not editor.preview_playing and is_equal_approx(editor.preview_time,editor._motion_duration()),"non repeating motion stops at end")
		editor.repeat_button.toggled.emit(true)
		editor._set_playing(true)
		editor._process(0.1)
		check(editor.preview_playing and editor.preview_time < editor._motion_duration(),"repeat wraps motion")
		check(editor.draft == before_motion,"motion controls do not alter profile")
		editor._set_playing(false)
		editor._start_motion(0)
		editor._show_category("image")
		check(editor.size.x <= size.x and editor.size.y <= size.y,"editor fits %s / %s" % [editor.size,size])
		check(editor.save_button.get_global_rect().end.y <= size.y and editor.save_button.get_global_rect().end.x <= size.x,"save fits %s" % size)
		check(editor.model_select.get_global_rect().end.x <= size.x,"options fit width")
		editor.name_field.text = "Хару"
		editor.name_field.text_changed.emit("Хару")
		editor.model_select.item_selected.emit(1)
		editor.selectors.vrm_hair.item_selected.emit(4)
		editor.save_button.pressed.emit()
		check(editor.saved.vrm_model == 1 and editor.saved.vrm_hair == 4 and editor.saved.name == "Хару","save via UI")
		editor._street_preset()
		check(editor.draft.name == "Хару" and editor.draft.vrm_style == 9 and editor.avatar.case_part.visible,"street preset keeps name and fits current base")
		for sport_model in 2:
			editor.select_model(sport_model)
			editor._select(4,"vrm_style")
			editor._select(VrmParts.BOMBER_IDS[sport_model],"vrm_clothes")
			editor._select(14,"vrm_denim")
			editor._select(1,"vrm_case")
			var chosen_hair: Mesh = editor.avatar.hair_part.mesh
			editor._sport_preset()
			check(editor.draft.name == "Хару" and editor.draft.vrm_model == sport_model and editor.draft.vrm_style == 4 and editor.draft.vrm_clothes == VrmParts.SPORT_IDS[sport_model],"sport preset preserves name, base and chosen hair")
			check(editor.avatar.hair_part.mesh == chosen_hair and editor.avatar.body_part.mesh == VrmParts.BODY[sport_model][VrmParts.SPORT_IDS[sport_model]],"sport clothes selected without replacing hair mesh")
			check(editor.selectors.vrm_denim.disabled and not editor.avatar.case_part.visible and editor.draft.vrm_denim == 14 and editor.draft.vrm_case == 1,"sport hides incompatible accessories but remembers choices")
			var other_model := 1-sport_model
			editor.select_model(other_model)
			check(editor.draft.vrm_model == other_model and editor.draft.vrm_clothes == VrmParts.SPORT_IDS[other_model] and editor.draft.vrm_style == 4 and editor.draft.name == "Хару" and editor.draft.vrm_denim == 14,"switching base preserves sport appearance and chosen hair")
			editor.select_model(sport_model)
			check(editor.draft.vrm_clothes == VrmParts.SPORT_IDS[sport_model] and editor.draft.vrm_style == 4 and editor.draft.vrm_denim == 14,"switching back preserves sport appearance and chosen hair")
			for key in ["vrm_style", "vrm_clothes"]:
				var id: int = editor.draft[key]
				var icon: AtlasTexture = editor.gallery_buttons[key][id].icon
				var tile: int = id + (VrmParts.HAIR_STYLE_COUNT if key == "vrm_clothes" else 0)
				check(icon.atlas == CharacterEditor.CATALOGS[sport_model] and icon.region == Rect2((tile%5)*160,(tile/5)*192,160,192),"sport thumbnail uses correct atlas cell")
			if size.x == 1280:
				editor._show_category("image")
				await capture("sport-%d" % sport_model)
			editor._select(VrmParts.BOMBER_IDS[sport_model],"vrm_clothes")
			check(not editor.selectors.vrm_denim.disabled and editor.draft.vrm_denim == 14 and editor.avatar.case_part.visible,"returning to bomber restores details")
		editor._apply(editor.saved)
		editor._select(2,"vrm_eyes")
		editor.request_close()
		check(editor.confirm.visible,"unsaved exit asks")
		editor.confirm.hide()
		editor._apply(editor.saved)
		check(editor.draft == editor.saved,"cancel restores saved draft")
		if size.x == 1280:
			# One small fresh sheet covers the editor's seven runtime motion mappings.
			var motion_sheet := Image.create(1960,800,false,Image.FORMAT_RGBA8)
			for motion_model in 2:
				editor._apply(PlayerProfile.DEFAULT)
				editor.select_model(motion_model)
				editor._show_category("motions")
				var motion_profile: Dictionary = editor.draft.duplicate(true)
				for motion_index in CharacterEditor.MOTIONS.size():
					editor._start_motion(motion_index)
					editor._set_playing(false)
					editor.preview_time = minf(.85,editor._motion_duration()*.5)
					editor._sample_preview()
					check(editor.preview_motion == CharacterEditor.MOTIONS[motion_index],"motion selector maps to runtime motion")
					check(editor.avatar.motion == CharacterEditor.MOTIONS[motion_index],"fighter receives editor motion")
					check(editor.draft == motion_profile,"sampling each motion preserves profile")
					for bone in editor.avatar.skeleton.get_bone_count():
						check(editor.avatar.skeleton.get_bone_global_pose(bone).is_finite(),"motion skeleton pose finite")
					await frames(2)
					var tile := editor.viewport.get_texture().get_image()
					var tile_width := mini(tile.get_width(),roundi(tile.get_height()*.7))
					tile = tile.get_region(Rect2i((tile.get_width()-tile_width)/2,0,tile_width,tile.get_height()))
					tile.resize(280,400,Image.INTERPOLATE_LANCZOS)
					tile.convert(Image.FORMAT_RGBA8)
					motion_sheet.blit_rect(tile,Rect2i(Vector2i.ZERO,tile.get_size()),Vector2i(motion_index*280,motion_model*400))
			motion_sheet.save_png("res://build/checks/editor-vrm-seven-motions.png")
			# Manual/legacy ID10 remains compatible, but automatic choices exclude it.
			check(CharacterEditor.RANDOM_HAIR_STYLES == [0,1,2,3,4,5,6,7,8,9],"random hair pool includes accepted IDs only")
			for legacy_model in 2:
				editor.select_model(legacy_model)
				editor.gallery_buttons.vrm_style[10].pressed.emit()
				editor._sport_preset()
				check(editor.draft.vrm_style == 10 and editor.avatar.hair_part.mesh == VrmParts.HAIR[legacy_model][10],"manual legacy hair survives sport preset")
				check(expanded.save_to(editor.draft,path+"-legacy-hair") == OK,"legacy hair profile saves")
				expanded.load_from(path+"-legacy-hair")
				check(expanded.value.vrm_style == 10 and expanded.value.vrm_model == legacy_model,"legacy hair survives reload")
			seed(20261103)
			for random_sample in 6:
				editor._randomize()
				check(editor.draft.vrm_style in CharacterEditor.RANDOM_HAIR_STYLES and editor.draft.vrm_style != 10,"random preset excludes criticised hair")
			for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(path+"-legacy-hair"+suffix)
			editor.select_model(0)
			editor._apply(PlayerProfile.DEFAULT)
			for category in ["hair", "clothes", "motions"]:
				editor._show_category(category)
				await capture("category-" + category)
			editor._show_category("image")
			editor.set_face_view(true)
			await capture("male-original")
			var actor_id := editor.avatar.actor.get_instance_id()
			editor.avatar.actor.process_mode = Node.PROCESS_MODE_DISABLED
			await frames(4)
			var other := VrmAvatar.new()
			editor.avatar.get_parent().add_child(other)
			other.apply_profile(PlayerProfile.DEFAULT)
			other.hide()
			check(editor.avatar.meshes[0].mesh == other.meshes[0].mesh,"immutable geometry shared")
			var original_colors := editor.viewport.get_texture().get_image().get_data()
			for key in ["vrm_hair","vrm_eyes","vrm_skin"]:
				var before := editor.viewport.get_texture().get_image().get_data()
				editor._select(2,key)
				await frames(4)
				check(editor.viewport.get_texture().get_image().get_data() != before,key+" changes real render")
				await capture(key)
			check(editor.avatar.actor.get_instance_id() == actor_id,"palettes reuse actor")
			for entry in other.palette_materials:
				if entry.role == "hair" or entry.role == "eyes": check(not entry.material.get_shader_parameter("palette_enabled"),"other actor material isolated")
			for mesh in editor.avatar.meshes:
				for surface in mesh.mesh.get_surface_count():
					var source := mesh.mesh.surface_get_material(surface) as ShaderMaterial
					if source != null: check(source.shader.resource_path.begins_with("res://addons/"),"source shader not mutated")
			for entry in other.palette_materials:
				if entry.role == "skin": check(entry.material.get_shader_parameter("_Color") == entry.base_color,"other actor skin isolated")
			editor._apply(PlayerProfile.DEFAULT)
			await frames(4)
			check(editor.viewport.get_texture().get_image().get_data() == original_colors,"reset restores original rendered colors exactly")
			other.queue_free()
			editor.set_face_view(false)
			await frames(4)
			var before := editor.viewport.get_texture().get_image().get_data()
			editor._select(1,"vrm_outfit")
			await frames(4)
			check(editor.viewport.get_texture().get_image().get_data() != before,"costume palette changes render")
			editor._select(2,"vrm_height")
			check(is_equal_approx(editor.avatar.actor.scale.y,1.08),"height changes uniformly")
			await capture("male-custom-full")
			for model_index in [1,0,1]: editor.select_model(model_index)
			await frames(5)
			check(editor.avatar.get_child_count() == 2,"old models released on switches; card prop retained")
			editor._select(3,"vrm_hair")
			editor._select(3,"vrm_eyes")
			editor._select(3,"vrm_outfit")
			editor.set_face_view(true)
			await capture("female-custom-face")
			var hair_poses: Dictionary = {}
			for bone in editor.avatar.skeleton.get_bone_count():
				if "Hair" in editor.avatar.skeleton.get_bone_name(bone): hair_poses[bone] = editor.avatar.skeleton.get_bone_global_pose(bone)
			await frames(25)
			var stable_hair := not hair_poses.is_empty()
			for bone in hair_poses:
				stable_hair = stable_hair and editor.avatar.skeleton.get_bone_global_pose(bone).is_equal_approx(hair_poses[bone])
			check(stable_hair,"hair stays in imported pose at changed height")
			editor.set_face_view(false)
			await capture("female-custom-full")
			var previous_name: String = editor.draft.name
			editor._randomize()
			check(editor.draft.name == previous_name,"random appearance keeps name")
			editor._apply(editor.saved)
		editor.request_close()
		await frames(5)
		check(not is_instance_valid(editor),"editor released")
		var reloaded := CharacterEditor.new()
		host.add_child(reloaded)
		await frames(4)
		check(reloaded.draft.vrm_model == 1 and reloaded.draft.vrm_hair == 4 and reloaded.draft.name == "Хару","new editor restores saved model/colors/name")
		reloaded.request_close()
		await frames(4)
	var menu := MainMenu.new()
	root.add_child(menu)
	await frames(3)
	menu._on_character()
	await frames(4)
	check(menu._character_editor.avatar is VrmAvatar and not menu._column.visible,"menu opens new VRM editor")
	check_shared_outfits(menu._character_editor)
	await check_remembered_denim(menu)
	menu._character_editor.request_close()
	await frames(3)
	check(menu._column.visible and root.gui_get_focus_owner() is Button and (root.gui_get_focus_owner() as Button).text == "Мой персонаж","return restores menu focus")
	menu._on_settings()
	menu._settings.close()
	await frames(2)
	check(root.gui_get_focus_owner() is Button and (root.gui_get_focus_owner() as Button).text == "Настройки","settings focus retained")
	menu._on_help()
	menu._help.queue_free()
	await frames(2)
	check(root.gui_get_focus_owner() is Button and (root.gui_get_focus_owner() as Button).text == "Как играть","help focus retained")
	var sound := SoundFx.i()
	if sound._music_tw != null: sound._music_tw.kill()
	for player in sound.find_children("*","AudioStreamPlayer",true,false):
		player.stop()
		player.stream = null
	await create_timer(.1).timeout
	menu.queue_free()
	host.queue_free()
	await frames(6)
	print("Character editor: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check_shared_outfits(editor: CharacterEditor) -> void:
	editor.category_buttons.clothes.pressed.emit()
	editor.model_select.item_selected.emit(0)
	editor.selectors.vrm_denim.item_selected.emit(14)
	editor.selectors.vrm_case.item_selected.emit(1)
	editor.outfit_color.color_changed.emit(Color("12a5fc"))
	for pair in [[2, 3], [3, 4], [4, 5], [5, 6], [6, 7]]:
		editor.gallery_buttons.vrm_clothes[pair[0]].pressed.emit()
		editor.model_select.item_selected.emit(1)
		check(editor.draft.vrm_clothes == pair[1] and editor.avatar.body_part.mesh == VrmParts.BODY[1][pair[1]],"Vita keeps shared outfit %d" % pair[0])
		if pair[1] == VrmParts.BOMBER_IDS[1]:
			check(editor.avatar.case_part.visible and uses_saved_denim(editor.avatar),"Vita's bomber keeps visible case and denim")
		editor.model_select.item_selected.emit(0)
		check(editor.draft.vrm_clothes == pair[0] and editor.avatar.body_part.mesh == VrmParts.BODY[0][pair[0]],"Sakurada keeps shared outfit %d" % pair[0])
		if pair[0] == VrmParts.BOMBER_IDS[0]:
			check(editor.avatar.case_part.visible and uses_saved_denim(editor.avatar),"Sakurada's bomber keeps visible case and denim")
	check(editor.draft.vrm_denim == 14 and editor.draft.vrm_case == 1 and editor.draft.vrm_outfit_color == "12a5fc","base switch preserves wardrobe preferences")
	for unique in [[0, 1], [1, 2]]:
		editor.model_select.item_selected.emit(unique[0])
		editor.gallery_buttons.vrm_clothes[unique[1]].pressed.emit()
		editor.model_select.item_selected.emit(1 - unique[0])
		check(editor.draft.vrm_clothes == 0 and editor.avatar.selected == 1 - unique[0],"base-exclusive outfit uses the destination default")

func check_remembered_denim(menu: MainMenu) -> void:
	var editor: CharacterEditor = menu._character_editor
	editor.category_buttons.clothes.pressed.emit()
	editor.model_select.item_selected.emit(0)
	editor.gallery_buttons.vrm_clothes[5].pressed.emit()
	editor.selectors.vrm_denim.item_selected.emit(14)
	editor.selectors.vrm_case.item_selected.emit(1)
	editor.outfit_color.color_changed.emit(Color("12a5fc"))
	check(uses_saved_denim(editor.avatar) and editor.avatar.case_part.visible,"bomber shows selected denim and case")
	editor.gallery_buttons.vrm_clothes[7].pressed.emit()
	check(editor.draft.vrm_denim == 14 and editor.selectors.vrm_denim.disabled and not uses_saved_denim(editor.avatar),"kimono keeps the denim preference without applying it")
	editor.model_select.item_selected.emit(1)
	check(editor.draft.vrm_model == 1 and editor.draft.vrm_clothes == 0 and editor.draft.vrm_denim == 14 and not uses_saved_denim(editor.avatar),"Vita's default outfit keeps the preference hidden")
	editor.save_button.pressed.emit()
	editor.request_close()
	await frames(4)
	menu._on_character()
	await frames(4)
	editor = menu._character_editor
	check(editor.draft.vrm_model == 1 and editor.draft.vrm_clothes == 0 and editor.draft.vrm_denim == 14 and editor.draft.vrm_outfit_color == "12a5fc","reopening Vita restores the profile and hidden denim")
	editor.model_select.item_selected.emit(0)
	editor.gallery_buttons.vrm_clothes[5].pressed.emit()
	check(uses_saved_denim(editor.avatar) and editor.avatar.case_part.visible and editor.draft.vrm_outfit_color == "12a5fc","returning to Sakurada's bomber restores denim, custom color and case")
	editor.save_button.pressed.emit()

func uses_saved_denim(avatar: VrmAvatar) -> bool:
	var body := avatar.body_part
	for slot in body.mesh.get_surface_count():
		var material := body.get_surface_override_material(slot) as ShaderMaterial
		if material != null and material.get_shader_parameter("_MainTex") == DenimWardrobe.TEXTURES[13]: return true
	return false
