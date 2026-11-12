extends SceneTree
## Offline contact sheets: the editor uses PNGs, never live thumbnail actors.
const OUT := "res://assets/avatars/editor/"
func _initialize() -> void:
	preload("res://tools/test_window.gd").background(self)
	call_deferred("run")
func _finalize() -> void:
	preload("res://tools/test_window.gd").finish(self)
func run() -> void:
	root.size = Vector2i(960,720)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_size(root.get_viewport_rid(),960,720)
	DirAccess.make_dir_recursive_absolute(OUT)
	var view := VrmPreview.new()
	root.add_child(view)
	var args := OS.get_cmdline_user_args()
	var sport_model := 0 if "--sakurada-sport" in args else (1 if "--vita-sport" in args else -1)
	var additions_only := "--booth-outfits" in args
	var vita_hair_fit_only := "--vita-hair-fit" in args
	var models := [sport_model] if sport_model >= 0 else ([1] if vita_hair_fit_only else [0, 1])
	var rendered := 0
	for model in models:
		var path := OUT+"catalog_%d.png" % model
		var slots := WardrobeCatalog.available_ids(model)
		var items := range(VrmParts.HAIR_STYLE_COUNT) if not additions_only else []
		for id in slots:
			if not additions_only or WardrobeCatalog.is_addition(model, id):
				items.append(VrmParts.HAIR_STYLE_COUNT+id)
		if sport_model >= 0:
			items = [VrmParts.HAIR_STYLE_COUNT + VrmParts.SPORT_IDS[model]]
		if vita_hair_fit_only:
			items = [1, 7]
		if items.is_empty(): continue
		var last: int = items.max()
		var height := maxi(768, (last/5+1)*192)
		var atlas := Image.create(800,height,false,Image.FORMAT_RGBA8)
		atlas.fill(Color("354356"))
		if sport_model >= 0 or additions_only or vita_hair_fit_only:
			var original := Image.load_from_file(ProjectSettings.globalize_path(path))
			assert(original != null and original.get_width() == 800)
			if original.get_height() > height: atlas.resize(800,original.get_height())
			original.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(original,Rect2i(Vector2i.ZERO,original.get_size()),Vector2i.ZERO)
		if additions_only:
			for id in range(WardrobeCatalog.LEGACY_COUNTS[model], WardrobeCatalog.SLOT_COUNT):
				var tile := VrmParts.HAIR_STYLE_COUNT + id
				if tile/5*192 < atlas.get_height():
					atlas.fill_rect(Rect2i(tile%5*160,tile/5*192,160,192),Color("354356"))
		for item in items:
			var p := PlayerProfile.DEFAULT.duplicate(true)
			p.vrm_model = model
			p.vrm_style = item if item < VrmParts.HAIR_STYLE_COUNT else 0
			p.vrm_clothes = 0 if item < VrmParts.HAIR_STYLE_COUNT else item-VrmParts.HAIR_STYLE_COUNT
			view.avatar.apply_profile(p)
			view.set_face_view(item < VrmParts.HAIR_STYLE_COUNT)
			view.avatar.rotation.y = .64 if sport_model >= 0 else (.85 if item == 9 else (.35 if item >= VrmParts.HAIR_STYLE_COUNT + WardrobeCatalog.LEGACY_COUNTS[model] else .20))
			if item < VrmParts.HAIR_STYLE_COUNT: view.camera.position.z *= 1.18
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var shot := view.viewport.get_texture().get_image()
			var width := mini(shot.get_width(),int(shot.get_height()*5.0/6.0))
			shot = shot.get_region(Rect2i((shot.get_width()-width)/2,0,width,shot.get_height()))
			shot.resize(160,192,Image.INTERPOLATE_LANCZOS)
			shot.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(shot,Rect2i(0,0,160,192),Vector2i(item%5*160,item/5*192))
			rendered += 1
		assert(atlas.save_png(path) == OK)
	view.queue_free()
	for frame in 5: await process_frame
	print("Editor thumbnails: %d choices rendered" % rendered)
	quit()
