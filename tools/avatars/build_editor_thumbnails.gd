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
	for model in 2:
		var atlas := Image.create(800,768,false,Image.FORMAT_RGBA8)
		atlas.fill(Color("354356"))
		for item in VrmParts.HAIR_STYLE_COUNT+VrmParts.BODY[model].size():
			var p := PlayerProfile.DEFAULT.duplicate(true)
			p.vrm_model = model
			p.vrm_style = item if item < VrmParts.HAIR_STYLE_COUNT else 0
			p.vrm_clothes = 0 if item < VrmParts.HAIR_STYLE_COUNT else item-VrmParts.HAIR_STYLE_COUNT
			view.avatar.apply_profile(p)
			view.set_face_view(item < VrmParts.HAIR_STYLE_COUNT)
			view.avatar.rotation.y = .85 if item == 9 else .20
			if item < VrmParts.HAIR_STYLE_COUNT: view.camera.position.z *= 1.18
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var shot := view.viewport.get_texture().get_image()
			var width := mini(shot.get_width(),int(shot.get_height()*5.0/6.0))
			shot = shot.get_region(Rect2i((shot.get_width()-width)/2,0,width,shot.get_height()))
			shot.resize(160,192,Image.INTERPOLATE_LANCZOS)
			shot.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(shot,Rect2i(0,0,160,192),Vector2i(item%5*160,item/5*192))
		atlas.save_png(OUT+"catalog_%d.png" % model)
	view.queue_free()
	for frame in 5: await process_frame
	print("Editor thumbnails: %d choices rendered" % (2*VrmParts.HAIR_STYLE_COUNT + VrmParts.BODY[0].size() + VrmParts.BODY[1].size()))
	quit()
