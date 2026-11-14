extends SceneTree
## Product UI render path, source bitmaps untouched; no models or match startup.
const PORTRAIT := preload("res://scenes/ui/creature_portrait.gd")
const MATTE := preload("res://scenes/ui/portrait_matte.gd")
const SAMPLE_IDS := ["dragnar_shadow", "levian_shadow"]
const FOCUSED_REVIEW := true
var _out := "res://build/checks/portrait-background"
var _checks := 0
var _failures := 0
var _rows: Array = []
var _canvas: Control
var _progress: Array = []
var _sources_before: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	CardDB.load_all()
	for id: StringName in PORTRAIT.REFERENCE_TEXTURES:
		var stem := String(id).trim_prefix("creature_")
		for folder in ["assets/portraits/creatures/", "tools/ai_models/concepts/"]:
			var path: String = "res://" + String(folder) + stem + ".png"
			if FileAccess.file_exists(path): _sources_before[path] = FileAccess.get_sha256(path)
	var begin := Time.get_ticks_usec()
	var loading_frames := [0]
	var count_frame: Callable = func() -> void: loading_frames[0] += 1
	process_frame.connect(count_frame)
	var count: int = await PORTRAIT.preload_catalog_async(self, func(done: int, total: int) -> void: _progress.append([done, total]))
	var preparation_ms := (Time.get_ticks_usec() - begin) / 1000.0
	process_frame.disconnect(count_frame)
	_check(count == 49 and PORTRAIT._presentation_textures.size() == 49, "all49 exact UI mattes prepared before display")
	_check(_progress.size() == 49 and _progress[-1] == [49, 49], "loader reports each portrait and completes49of49")
	_check(int(loading_frames[0]) >= 49, "async preparation yields to loading UI between49 bounded tasks")
	_check(MATTE.generation_count == 49, "exactly one segmentation per source")
	_check(PORTRAIT._hud_reference_textures.size() == 42 and PORTRAIT._background_materials.size() == 6, "reviewed42 crops and six portrait backdrops prepared")
	_new_canvas(Vector2i(1160, 720))
	_label("CHANGED2 · guarded negative-space fix · source / product matte / alpha / actual72px HUD", Vector2(16, 8), 18)
	for row in SAMPLE_IDS.size():
		var stem: String = SAMPLE_IDS[row]
		var id := StringName("creature_" + stem)
		var source := PORTRAIT.reference_texture(id)
		var presentation := PORTRAIT.presentation_texture(id)
		var stats: Dictionary = PORTRAIT._presentation_stats[id]
		var y := 48.0 + row * 318.0
		_label(stem, Vector2(16, y + 100), 15)
		_add_texture(source, Rect2(180, y, 256, 256))
		_add_portrait(id, Rect2(450, y, 256, 256), false)
		_add_texture(_alpha_mask(presentation), Rect2(720, y, 256, 256))
		_add_portrait(id, Rect2(1000, y + 44, 72, 72), true)
		_label("closed white: %d\nbackground holes: %dpx\nsoft edge: %d" % [stats.retained_closed_white_pixels, stats.interior_background_pixels, stats.softened_edge_pixels], Vector2(180, y + 262), 14)
		_rows.append({"id": String(id), "stats": stats})
		_check(presentation != source and presentation.get_size() == source.get_size(), "full source coordinate space preserved " + stem)
	await _shot("changed2-source-matte-alpha-hud")
	var ids: Array = PORTRAIT.REFERENCE_TEXTURES.keys()
	for sheet in range(0 if FOCUSED_REVIEW else 2):
		_new_canvas(Vector2i(1200, 800))
		_label("ALL49 · SOURCE / PRODUCT MATTE+ELEMENT · sheet%d · original PNGs unchanged" % [sheet + 1], Vector2(12, 8), 17)
		for cell in range(25):
			var index := sheet * 25 + cell
			if index >= ids.size(): break
			var id: StringName = ids[index]
			var x := 12.0 + (cell % 5) * 238.0
			var y := 46.0 + (cell / 5) * 145.0
			_label(String(id).trim_prefix("creature_"), Vector2(x, y), 13)
			_add_texture(PORTRAIT.reference_texture(id), Rect2(x, y + 23, 104, 104))
			_add_portrait(id, Rect2(x + 116, y + 23, 104, 104), false)
		await _shot("catalog49-full-%d" % [sheet + 1])
	if not FOCUSED_REVIEW:
		_new_canvas(Vector2i(1060, 920))
		_label("ALL49 · ACTUAL72px PRODUCT HUD CROPS · DEVICE · 42 reviewed crops / 7 fullbody", Vector2(12, 8), 17)
		for cell in ids.size():
			var id: StringName = ids[cell]
			var x := 12.0 + (cell % 7) * 149.0
			var y := 48.0 + (cell / 7) * 122.0
			_label(String(id).trim_prefix("creature_"), Vector2(x, y), 11)
			_add_portrait(id, Rect2(x + 20, y + 22, 72, 72), true)
		await _shot("catalog49-hud72-device")
	var generation_before := MATTE.generation_count
	var portrait := PORTRAIT.new()
	_canvas.add_child(portrait)
	for turn in range(4):
		for id: StringName in ids:
			portrait.set_definition(CardDB.creature(id), turn)
			portrait.set_hud_crop_enabled(turn % 2 == 0)
			portrait.size = Vector2(72 + turn, 100 + turn)
			_check(portrait._reference_texture == PORTRAIT.reference_texture(id), "original source identity unchanged on warm rebind " + String(id))
			_check(PORTRAIT.presentation_texture(id) == PORTRAIT._presentation_textures[id], "warm getter reuses exact prepared texture " + String(id))
	_check(MATTE.generation_count == generation_before and generation_before == 49, "present/resize/rebind never rerun segmentation")
	_check(PORTRAIT.preload_catalog() == 49 and MATTE.generation_count == 49, "repeat catalog preparation reuses all resources")
	for id: StringName in ids:
		var expected_holes := 2572 if id == &"creature_dragnar_shadow" else (920 if id == &"creature_levian_shadow" else 0)
		_check(int(PORTRAIT._presentation_stats[id].interior_background_pixels) == expected_holes, "only reviewed exact negative-space components removed " + String(id))
		var source := PORTRAIT.reference_texture(id).get_image()
		var prepared := PORTRAIT.presentation_texture(id).get_image()
		source.convert(Image.FORMAT_RGBA8)
		prepared.convert(Image.FORMAT_RGBA8)
		var old := source.get_data()
		var new := prepared.get_data()
		var protected := 0
		var core_changed := 0
		for at in range(source.get_width() * source.get_height()):
			var offset := at * 4
			if new[offset + 3] != 255: continue
			if old[offset] != new[offset] or old[offset + 1] != new[offset + 1] or old[offset + 2] != new[offset + 2]: core_changed += 1
			if old[offset] >= MATTE.WHITE_FLOOR and old[offset + 1] >= MATTE.WHITE_FLOOR and old[offset + 2] >= MATTE.WHITE_FLOOR: protected += 1
		_check(core_changed == 0, "opaque foreground RGB retained exactly " + String(id))
		_check(protected >= int(PORTRAIT._presentation_stats[id].retained_closed_white_pixels), "closed white details remain fully opaque " + String(id))
	for path in _sources_before:
		_check(FileAccess.get_sha256(path) == _sources_before[path], "source file untouched " + String(path))
	_check(Engine.max_fps == 60, "standard wrapper holds60FPS")
	_check(PORTRAIT._presentation_textures.values().all(func(value: Variant) -> bool: return value is Texture2D and not value is Node), "portrait cache holds resources without Node references")
	var report := {"checks": _checks, "failures": _failures, "sample_count": SAMPLE_IDS.size(), "catalog_count": ids.size(), "production_enabled": true, "generation_count": MATTE.generation_count, "preparation_ms": preparation_ms, "async_progress_count": _progress.size(), "loading_frame_signals": loading_frames[0], "samples": _rows, "catalog_stats": PORTRAIT._presentation_stats, "source_hashes_unchanged": _sources_before}
	FileAccess.open(_out.path_join("summary.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("portrait-background: %d checks, %d failures; all49 cached, warm generation stable, originals unchanged" % [_checks, _failures])
	quit(1 if _failures else 0)

func _new_canvas(dimensions: Vector2i) -> void:
	if is_instance_valid(_canvas):
		root.remove_child(_canvas)
		_canvas.queue_free()
	root.size = dimensions
	root.content_scale_size = dimensions
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_canvas)
	var base := ColorRect.new()
	base.color = Color("0c1119")
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(base)

func _add_portrait(id: StringName, rect: Rect2, crop: bool) -> void:
	var portrait := PORTRAIT.new()
	_canvas.add_child(portrait)
	portrait.position = rect.position
	portrait.size = rect.size
	portrait.set_hud_crop_enabled(crop)
	portrait.set_definition(CardDB.creature(id), 0)

func _add_texture(texture: Texture2D, rect: Rect2) -> void:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = texture
	image.position = rect.position
	image.size = rect.size
	_canvas.add_child(image)

func _alpha_mask(texture: Texture2D) -> Texture2D:
	var source := texture.get_image()
	source.convert(Image.FORMAT_RGBA8)
	var data := source.get_data()
	for at in range(source.get_width() * source.get_height()):
		var offset := at * 4
		for channel in range(3): data[offset + channel] = data[offset + 3]
		data[offset + 3] = 255
	return ImageTexture.create_from_image(Image.create_from_data(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8, data))

func _label(value: String, at: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	_canvas.add_child(label)

func _shot(filename: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("portrait-background: no PNG in headless mode " + filename)
		return
	RenderingServer.force_draw(false)
	_check(root.get_texture().get_image().save_png(_out.path_join(filename + ".png")) == OK, "PNG " + filename)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("FAIL: " + label)
