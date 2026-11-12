extends SceneTree
## Targeted real editor palette changes on sport/bomber, both bases.
# Reproduce the previous material policy only in this fixture for before PNGs.
class BaselineFighter extends VrmFighter:
	func _apply_denim(index: int) -> void:
		for surface in body_part.mesh.get_surface_count():
			var original := VrmParts.material_for(body_part.mesh,surface)
			if original == null or not "Bottoms_" in original.resource_name: continue
			var mat := body_part.get_surface_override_material(surface) as ShaderMaterial
			mat.set_shader_parameter("_MainTex",DenimWardrobe.TEXTURES[index-1] if index > 0 else original.get_shader_parameter("_MainTex"))
			mat.set_shader_parameter("_ShadeTexture",DenimWardrobe.TEXTURES[index-1] if index > 0 else original.get_shader_parameter("_ShadeTexture"))
			mat.set_shader_parameter("_Color",Color.WHITE if index > 0 else original.get_shader_parameter("_Color"))
			mat.set_shader_parameter("_ShadeColor",Color("b4b4b4") if index > 0 else original.get_shader_parameter("_ShadeColor"))
	func _localize_materials() -> void:
		palette_materials.clear()
		local_materials.clear()
		var copies: Dictionary = {}
		for mesh in meshes:
			for surface in mesh.mesh.get_surface_count():
				var original := mesh.mesh.surface_get_material(surface) as ShaderMaterial
				if mesh.mesh.has_meta("part_source"): original = VrmParts.material_for(mesh.mesh,surface)
				if original == null: continue
				var id := original.get_instance_id()
				if not copies.has(id): copies[id] = _copy_material(original)
				mesh.set_surface_override_material(surface,copies[id])
	func _copy_material(original: ShaderMaterial, _assigned_role: String = "") -> ShaderMaterial:
		var copy := original.duplicate(false) as ShaderMaterial
		local_materials.append(copy)
		var name := original.resource_name
		var role := ""
		if "_HAIR" in name or "FaceBrow" in name: role = "hair"
		elif "EyeIris" in name: role = "eyes"
		elif "_SKIN" in name: role = "skin"
		elif "Tops_" in name or "AccessoryNeck_" in name: role = "outfit"
		var key := original.shader.resource_path.get_file()
		if VrmPaletteShaders.SHADERS.has(key):
			copy.shader = VrmPaletteShaders.SHADERS[key]
			if not role.is_empty():
				palette_materials.append({"material":copy,"role":role,"base_color":original.get_shader_parameter("_Color"),"shade_color":original.get_shader_parameter("_ShadeColor")})
		if original.next_pass is ShaderMaterial: copy.next_pass = _copy_material(original.next_pass)
		return copy
class BaselineEditor extends CharacterEditor:
	func _create_avatar() -> VrmAvatar:
		var fighter := BaselineFighter.new()
		fighter.set_process(false)
		return fighter
var checks := 0
var failures := 0
var baseline := OS.get_environment("SFERY_WARDROBE_BASELINE") == "1"
var out := "res://build/checks/wardrobe-palette"
var editor: CharacterEditor
var rows: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",message)
func frames() -> void:
	for i in 4: await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
func select_color(index: int) -> void:
	editor.selectors.vrm_outfit.item_selected.emit(index)
	editor._set_playing(false)
	await frames()
func capture(name: String) -> PackedByteArray:
	if DisplayServer.get_name() == "headless": return PackedByteArray()
	var shot := editor.viewport.get_texture().get_image()
	check(shot.save_png(out.path_join(name+".png")) == OK,"capture "+name)
	return shot.get_data()
func cloth_materials() -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	for surface in editor.avatar.body_part.mesh.get_surface_count():
		var source := VrmParts.material_for(editor.avatar.body_part.mesh,surface)
		if "_CLOTH" in source.resource_name:
			materials.append(editor.avatar.body_part.get_surface_override_material(surface))
	return materials
func protected_materials(avatar: VrmAvatar, include_outfit: bool = false) -> Array:
	var snapshot: Array = []
	for entry in avatar.palette_materials:
		if include_outfit or entry.role != "outfit":
			snapshot.append([entry.material.get_shader_parameter("_MainTex"),entry.material.get_shader_parameter("_Color"),entry.material.get_shader_parameter("palette_enabled"),entry.material.get_shader_parameter("palette_color")])
	for surface in avatar.case_part.mesh.get_surface_count():
		var material := avatar.case_part.get_surface_override_material(surface) as ShaderMaterial
		snapshot.append([material.get_shader_parameter("_MainTex"),material.get_shader_parameter("_Color"),material.get_shader_parameter("palette_enabled")])
	return snapshot
func run() -> void:
	out = out.path_join("before" if baseline else "after")
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	editor = BaselineEditor.new() if baseline else CharacterEditor.new()
	root.add_child(editor)
	editor._set_playing(false)
	editor.set_face_view(false)
	await frames()
	check(Engine.max_fps == 60,"test wrapper limits60FPS")
	var other := VrmAvatar.new()
	root.add_child(other)
	other.hide()
	other.apply_profile(PlayerProfile.DEFAULT)
	var other_snapshot := protected_materials(other,true)
	for model in 2:
		for kind in ["sport","bomber"]:
			var profile := PlayerProfile.DEFAULT.duplicate(true)
			profile.vrm_model = model
			profile.vrm_clothes = VrmParts.SPORT_IDS[model] if kind == "sport" else VrmParts.BOMBER_IDS[model]
			profile.vrm_case = 1
			editor._apply(profile)
			editor._set_playing(false)
			await frames()
			var label := "%d-%s" % [model,kind]
			var original := capture(label+"-original")
			var protected := protected_materials(editor.avatar)
			var original_textures: Array = []
			for material in cloth_materials(): original_textures.append(material.get_shader_parameter("_MainTex"))
			await select_color(1)
			var painted := 0
			var materials := cloth_materials()
			for material in materials:
				if material.get_shader_parameter("palette_enabled") == true: painted += 1
				check(material.get_shader_parameter("palette_fabric_dye") != true,label+": ready-made color keeps the existing shader formula")
			rows.append({"model":model,"costume":kind,"cloth_surfaces":materials.size(),"colored_surfaces":painted})
			if baseline: check(painted == 1,label+": baseline recolors only original top")
			else: check(painted == materials.size(),label+": entire costume follows palette")
			check(protected_materials(editor.avatar) == protected,label+": skin/hair/eyes/case keep independent colors")
			check(editor.draft.vrm_outfit == 1,label+": real palette signal updates profile")
			var red := capture(label+"-burgundy")
			if DisplayServer.get_name() != "headless": check(red != original,label+": real render changes")
			await select_color(3)
			await select_color(1)
			if DisplayServer.get_name() != "headless": check(capture(label+"-repeat") == red,label+": repeated color is deterministic")
			await select_color(0)
			if DisplayServer.get_name() != "headless": check(capture(label+"-restored") == original,label+": original color restores exactly")
			var restored: Array = []
			for material in cloth_materials(): restored.append(material.get_shader_parameter("_MainTex"))
			check(restored == original_textures,label+": source textures are retained")
			if kind == "bomber": await denim(model)
		check(protected_materials(other,true) == other_snapshot,"second avatar materials stay isolated after base/color changes")
	if not baseline: await custom_color(other)
	other.queue_free()
	var report := {"checks":checks,"failures":failures,"baseline":baseline,"surface_rows":rows,"fps_cap":Engine.max_fps,"scope":"presets, custom RGB picker, profile round trip, denim and isolated materials"}
	var file := FileAccess.open(out.path_join("summary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	editor._close()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	VrmParts.materials.clear()
	await frames()
	print("WARDROBE PALETTE ",checks,"/",failures," ",JSON.stringify(report))
	quit.call_deferred(1 if failures else 0)
func denim(model: int) -> void:
	editor._select(14,"vrm_denim")
	editor._set_playing(false)
	await frames()
	var bottom: ShaderMaterial
	for surface in editor.avatar.body_part.mesh.get_surface_count():
		if "Bottoms_" in VrmParts.material_for(editor.avatar.body_part.mesh,surface).resource_name:
			bottom = editor.avatar.body_part.get_surface_override_material(surface)
	check(bottom != null,"denim target exists")
	var texture: Texture2D = bottom.get_shader_parameter("_MainTex")
	await select_color(2)
	check(bottom.get_shader_parameter("_MainTex") == texture and texture == DenimWardrobe.TEXTURES[13],"costume palette retains explicit denim texture")
	check(bottom.get_shader_parameter("palette_enabled") != true,"explicit denim keeps its selected color")
	capture("%d-bomber-denim" % model)
	editor._select(VrmParts.SPORT_IDS[model],"vrm_clothes")
	editor._set_playing(false)
	await frames()
	if not baseline:
		for material in cloth_materials(): check(material.get_shader_parameter("palette_enabled") == true,"sport hides denim and keeps costume palette")
	editor._select(VrmParts.BOMBER_IDS[model],"vrm_clothes")
	editor._set_playing(false)
	await frames()
	check(editor.draft.vrm_denim == 14,"costume switch retains independent denim selection")
	editor._select(0,"vrm_denim")
	editor._set_playing(false)
	await frames()
	if not baseline:
		for material in cloth_materials(): check(material.get_shader_parameter("palette_enabled") == true,"removing denim restores palette to whole costume")

func custom_color(other: VrmAvatar) -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = root.size
	var profile := PlayerProfile.DEFAULT.duplicate(true)
	profile.vrm_clothes = VrmParts.SPORT_IDS[0]
	editor._apply(profile)
	editor._show_category("clothes")
	editor._set_playing(false)
	editor.preview_time = .43
	editor._sample_preview()
	await frames()
	var original := capture("sakurada-sport-original")
	var actor_id := editor.avatar.actor.get_instance_id()
	var protected := protected_materials(editor.avatar)
	var other_snapshot := protected_materials(other, true)
	var green := Color("47c494")
	var orange := Color("e97a3d")
	if DisplayServer.get_name() != "headless":
		await click_color_picker()
		var popup := editor.outfit_color.get_popup()
		check(popup.visible, "the actual custom color button opens a popup")
		var hex_input := popup.gui_get_focus_owner() as LineEdit
		check(hex_input != null, "HEX field receives focus on open")
		if hex_input != null:
			hex_input.text = "#47C494"
			hex_input.text_submitted.emit(hex_input.text)
		await frames()
		var bounds := Rect2i(popup.position, popup.size)
		check(popup.visible and Rect2i(Vector2i.ZERO, root.size).encloses(bounds), "picker fits in %s while editing (%s)" % [root.size, bounds])
		check(root.get_texture().get_image().save_png(out.path_join("sakurada-custom-picker.png")) == OK, "capture the actual picker over the live preview")
		popup.hide()
	else:
		editor.outfit_color.color_changed.emit(green)
	check(editor.draft.vrm_outfit_color == "47c494", "entering a custom color updates the editor draft")
	check(editor.selectors.vrm_outfit.text == "Своя палитра", "selector indicates the active custom color")
	check(editor.avatar.actor.get_instance_id() == actor_id and is_equal_approx(editor.preview_time, .43), "color updates reuse the actor and keep the preview pose")
	check(protected_materials(editor.avatar) == protected, "custom color leaves non-outfit materials unchanged")
	check(protected_materials(other, true) == other_snapshot, "custom color stays local to this avatar")
	for material in cloth_materials():
		check(material.get_shader_parameter("palette_enabled") == true and material.get_shader_parameter("palette_fabric_dye") == true and material.get_shader_parameter("palette_color") == green, "custom RGB uses the fabric dye on every sport material")
	await frames()
	var green_pixels := capture("sakurada-sport-custom-green")
	editor.outfit_color.color_changed.emit(orange)
	await frames()
	var orange_pixels := capture("sakurada-sport-custom-orange")
	if DisplayServer.get_name() != "headless":
		check(original != green_pixels and green_pixels != orange_pixels and original != orange_pixels, "two arbitrary colors produce distinct rendered outfits")
	var file := "user://wardrobe-custom-color-test.json"
	var saved := PlayerProfile.new()
	check(saved.save_to(editor.draft, file) == OK, "custom color saves through the profile writer")
	var loaded := PlayerProfile.new()
	loaded.load_from(file)
	check(loaded.value.vrm_outfit_color == "e97a3d", "custom color survives a fresh profile read")
	for suffix in ["", ".tmp", ".bak"]: DirAccess.remove_absolute(file + suffix)
	other.apply_profile(loaded.value)
	var colored := 0
	for entry in other.palette_materials:
		if entry.role != "outfit": continue
		colored += 1
		check(entry.material.get_shader_parameter("palette_color") == orange, "a fresh runtime avatar uses the saved color")
	check(colored > 0, "runtime avatar has colorable outfit materials")
	editor.selectors.vrm_outfit.item_selected.emit(0)
	await frames()
	check(editor.draft.vrm_outfit_color.is_empty() and editor.selectors.vrm_outfit.selected == 0, "Original clears the custom color")
	if DisplayServer.get_name() != "headless":
		check(capture("sakurada-sport-custom-reset") == original, "Original restores the exact preview pixels")
	check(PlayerProfile.normalized({"vrm_outfit":2}).vrm_outfit_color.is_empty(), "older profiles retain their built-in palette")
	check(PlayerProfile.normalized({"vrm_outfit_color":"47C494"}).vrm_outfit_color == "47c494", "valid RGB normalizes")
	check(PlayerProfile.normalized({"vrm_outfit_color":"47c49400"}).vrm_outfit_color.is_empty(), "alpha in saved color is rejected")
	check(PlayerProfile.normalized({"vrm_outfit_color":"invalid"}).vrm_outfit_color.is_empty(), "invalid color falls back")

	editor._select(VrmParts.BOMBER_IDS[0], "vrm_clothes")
	editor._select(14, "vrm_denim")
	editor.outfit_color.color_changed.emit(green)
	for entry in editor.avatar.palette_materials:
		if not entry.get("denim", false): continue
		check(not entry.material.get_shader_parameter("palette_enabled") and entry.material.get_shader_parameter("_MainTex") == DenimWardrobe.TEXTURES[13], "custom dye preserves explicit denim on all passes")
	editor._select(0, "vrm_denim")
	for material in cloth_materials():
		check(material.get_shader_parameter("palette_enabled") == true, "clearing denim restores the custom dye")

func click_color_picker() -> void:
	var point := editor.outfit_color.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.position = point
		button.pressed = pressed
		root.push_input(button, true)
		await process_frame
