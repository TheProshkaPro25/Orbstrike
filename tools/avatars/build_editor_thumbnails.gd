extends SceneTree
## Offline contact sheets: the editor uses PNGs, never live thumbnail actors.
const OUT := "res://assets/avatars/editor/"
const Editor := preload("res://scenes/ui/character_editor.gd")
const BACKGROUND := Color("354356")
var staged_hair: Array[ArrayMesh] = []
func _initialize() -> void:
	preload("res://tools/test_window.gd").background(self)
	call_deferred("run")
func _finalize() -> void:
	preload("res://tools/test_window.gd").finish(self)
func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Editor thumbnails require rendering in the background test window.")
		quit(1)
		return
	root.size = Vector2i(960,720)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_size(root.get_viewport_rid(),960,720)
	var args := OS.get_cmdline_user_args()
	var output_dir := OUT
	for arg in args:
		if arg.begins_with("--output-dir="): output_dir = arg.trim_prefix("--output-dir=")
		if arg.begins_with("--staged-hair-dir="):
			if not load_staged_hair(arg.trim_prefix("--staged-hair-dir=")):
				quit(1)
				return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)) != OK:
		printerr("Could not create thumbnail output directory: ", output_dir)
		quit(1)
		return
	var view := VrmPreview.new()
	root.add_child(view)
	var new_hair_only := "--new-hair-only" in args
	var sport_model := 0 if "--sakurada-sport" in args else (1 if "--vita-sport" in args else -1)
	var additions_only := "--booth-outfits" in args
	var vita_hair_fit_only := "--vita-hair-fit" in args
	var side_part_only := "--side-part" in args
	var tousled_only := "--tousled" in args
	var vita_asymmetric_only := "--vita-asymmetric" in args
	var selected_hair_only := tousled_only or vita_asymmetric_only
	var models := [sport_model] if sport_model >= 0 else ([1] if vita_hair_fit_only else [0, 1])
	if selected_hair_only:
		models = [0, 1] if tousled_only else [1]
	var rendered := 0
	var outfit_start := Editor.thumbnail_tile("vrm_clothes", 0)
	var new_hair_start := Editor.NEW_HAIR_TILE_START
	var new_hair := HairCatalog.available_additions()
	var preserve_existing := sport_model >= 0 or additions_only or vita_hair_fit_only or side_part_only or selected_hair_only or new_hair_only
	for model in models:
		var filename := "catalog_%d.png" % model
		var slots := WardrobeCatalog.available_ids(model)
		var items := range(HairCatalog.LEGACY_COUNT) if not additions_only else []
		for id in slots:
			if not additions_only or WardrobeCatalog.is_addition(model, id):
				items.append(Editor.thumbnail_tile("vrm_clothes", id))
		if not additions_only:
			for id in new_hair:
				items.append(Editor.thumbnail_tile("vrm_style", id))
		if sport_model >= 0:
			items = [Editor.thumbnail_tile("vrm_clothes", VrmParts.SPORT_IDS[model])]
		if vita_hair_fit_only:
			items = [1, 7]
		if side_part_only:
			items = [10]
		if selected_hair_only:
			items = []
			if tousled_only:
				items.append(5)
			if vita_asymmetric_only and model == 1:
				items.append(6)
		if new_hair_only:
			items = []
			for id in new_hair:
				items.append(Editor.thumbnail_tile("vrm_style", id))
		if items.is_empty(): continue
		var width := Editor.THUMBNAIL_COLUMNS * Editor.THUMBNAIL_SIZE.x
		var height := maxi(768, Editor.thumbnail_region(items.max()).end.y)
		var original: Image
		if preserve_existing:
			original = Image.load_from_file(ProjectSettings.globalize_path(OUT.path_join(filename)))
			if original == null or original.get_width() != width:
				printerr("Could not read existing atlas: ", filename)
				quit(1)
				return
			height = maxi(height, original.get_height())
		var atlas := Image.create(width, height, false, Image.FORMAT_RGBA8)
		atlas.fill(BACKGROUND)
		if original != null:
			original.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(original,Rect2i(Vector2i.ZERO,original.get_size()),Vector2i.ZERO)
		if additions_only and not selected_hair_only and not new_hair_only:
			for id in range(WardrobeCatalog.LEGACY_COUNTS[model], WardrobeCatalog.SLOT_COUNT):
				var region := Editor.thumbnail_region(Editor.thumbnail_tile("vrm_clothes", id))
				if region.position.y < height:
					atlas.fill_rect(region, BACKGROUND)
		for item in items:
			var is_new_hair: bool = item >= new_hair_start
			var is_hair: bool = item < outfit_start or is_new_hair
			var p := PlayerProfile.DEFAULT.duplicate(true)
			p.vrm_model = model
			if is_new_hair: p.vrm_style = HairCatalog.LEGACY_COUNT + item - new_hair_start
			elif is_hair: p.vrm_style = item
			else: p.vrm_clothes = item - outfit_start
			view.avatar.apply_profile(p)
			view.set_face_view(is_hair)
			view.avatar.rotation.y = .64 if sport_model >= 0 else (.85 if item == 9 else (.35 if p.vrm_clothes >= WardrobeCatalog.LEGACY_COUNTS[model] else .20))
			if is_new_hair:
				frame_new_hair(view)
			elif is_hair:
				view.camera.position.z *= 1.18
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var shot := view.viewport.get_texture().get_image()
			var crop_width := mini(shot.get_width(),int(shot.get_height()*5.0/6.0))
			shot = shot.get_region(Rect2i((shot.get_width()-crop_width)/2,0,crop_width,shot.get_height()))
			shot.resize(Editor.THUMBNAIL_SIZE.x, Editor.THUMBNAIL_SIZE.y, Image.INTERPOLATE_LANCZOS)
			shot.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(shot, Rect2i(Vector2i.ZERO, Editor.THUMBNAIL_SIZE), Editor.thumbnail_region(item).position)
			rendered += 1
		if atlas.save_png(output_dir.path_join(filename)) != OK:
			printerr("Could not save editor atlas: ", filename)
			quit(1)
			return
	view.queue_free()
	for frame in 5: await process_frame
	print("Editor thumbnails: %d choices rendered" % rendered)
	quit(int(new_hair_only and rendered == 0))

func frame_new_hair(view: VrmPreview) -> void:
	view.avatar.rotation.y = 0.64
	var hair := view.avatar.hair_part
	var bounds := hair.global_transform * hair.mesh.get_aabb()
	var base_height := view.camera.position.y
	var bottom := minf(base_height - 0.23, bounds.position.y - 0.035)
	var top := maxf(base_height + 0.18, bounds.end.y + 0.035)
	var target := Vector3(bounds.get_center().x, (top + bottom) * 0.5, 0)
	var span := maxf(top - bottom, bounds.size.x * 1.2 + 0.07)
	var distance := maxf(1.13, span * 0.5 / tan(deg_to_rad(view.camera.fov * 0.5)) + bounds.end.z)
	view.camera.position = target + Vector3(0, 0, distance)
	view.camera.look_at(target)

func load_staged_hair(directory: String) -> bool:
	for id in HairCatalog.ADDITIONS:
		var first := directory.path_join(HairCatalog.asset_path(0, id).get_file())
		var second := directory.path_join(HairCatalog.asset_path(1, id).get_file())
		if not FileAccess.file_exists(first) and not FileAccess.file_exists(second): continue
		for model in 2:
			var path: String = [first, second][model]
			var mesh := load(path) as ArrayMesh
			if mesh == null:
				printerr("Could not load staged hair: ", path)
				return false
			mesh.take_over_path(HairCatalog.asset_path(model, id))
			staged_hair.append(mesh)
	return true
