extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ",message)
func frames(count: int) -> void:
	for frame in count: await process_frame
	await RenderingServer.frame_post_draw
func cell(view: CharacterEditor,atlas: Image,position: Vector2i,size: Vector2i) -> void:
	await frames(4)
	var shot := view.viewport.get_texture().get_image()
	var height := shot.get_height()
	var width := height if size.x == size.y else height/2
	shot = shot.get_region(Rect2i((shot.get_width()-width)/2,0,width,height))
	shot.resize(size.x,size.y,Image.INTERPOLATE_LANCZOS)
	shot.convert(Image.FORMAT_RGBA8)
	atlas.blit_rect(shot,Rect2i(Vector2i.ZERO,size),position)
func run() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_size(root.get_viewport_rid(),1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/checks/vrm-parts")
	var view := CharacterEditor.new()
	root.add_child(view)
	await frames(5)
	view._set_playing(false)
	var hair_atlas := Image.create(PlayerProfile.LIMITS.vrm_style*300,600,false,Image.FORMAT_RGBA8)
	var body_atlas := Image.create((VrmParts.BODY[0].size()+VrmParts.BODY[1].size())*300,600,false,Image.FORMAT_RGBA8)
	var body_cell := 0
	for model in 2:
		view._apply(PlayerProfile.DEFAULT)
		view.select_model(model)
		view.set_face_view(true)
		for style in PlayerProfile.LIMITS.vrm_style:
			view._select(style,"vrm_style")
			await cell(view,hair_atlas,Vector2i(style*300,model*300),Vector2i(300,300))
			check(view.avatar.hair_part.mesh != null,"hair exists %d/%d" % [model,style])
			check(view.avatar.hair_part.mesh.get_surface_count() <= 4,"hair surfaces merged offline")
			check(view.avatar.get_child_count() == 2,"hair switch keeps one actor and card prop")
			if style == 1 or style >= 5:
				view.rotate_model(.65)
				await frames(4)
				root.get_texture().get_image().save_png("res://build/checks/vrm-parts/style-%d-%d-angle.png" % [model,style])
				view.rotate_model(-.65)
				if style >= 5:
					view.rotate_model(PI)
					await frames(3)
					root.get_texture().get_image().save_png("res://build/checks/vrm-parts/style-%d-%d-back.png" % [model,style])
					view.rotate_model(-PI)
		view._select(1,"vrm_style")
		view.set_face_view(false)
		for outfit in VrmParts.BODY[model].size():
			view._select(outfit,"vrm_clothes")
			await cell(view,body_atlas,Vector2i(body_cell*300,0),Vector2i(300,600))
			var head := view.avatar.skeleton.get_bone_global_rest(view.avatar.skeleton.find_bone("Head")).origin.y
			check(view.avatar.body_part.get_aabb().end.y < head+.27,"costume arms stay below head")
			check(view.avatar.body_part.mesh.get_surface_count() <= 6,"costume surfaces merged")
			if outfit >= (2 if model == 0 else 3):
				for angle in [.65,PI]:
					view.rotate_model(angle)
					await frames(3)
					var label := "angle" if angle < 1 else "back"
					view.viewport.get_texture().get_image().save_png("res://build/checks/vrm-parts/costume-%d-%d-%s.png" % [model,outfit,label])
					view.rotate_model(-angle)
			body_cell += 1
		view._select(1 if model == 0 else 3,"vrm_clothes")
		view._select(14,"vrm_denim")
		await frames(3)
		var denim := view.viewport.get_texture().get_image().get_data()
		view._select(0,"vrm_denim")
		await frames(3)
		check(denim != view.viewport.get_texture().get_image().get_data(),"denim changes render and restores original")
		var denim_atlas := Image.create(2100,1200,false,Image.FORMAT_RGBA8)
		for index in 14:
			view._select(index+1,"vrm_denim")
			await cell(view,denim_atlas,Vector2i((index%7)*300,(index/7)*600),Vector2i(300,600))
		denim_atlas.save_png("res://build/checks/vrm-parts/denim-%d.png" % model)
		view._select(0,"vrm_denim")
		view.set_face_view(true)
		for key in ["vrm_eye_shape","vrm_brows","vrm_mouth"]:
			await frames(4)
			var before := view.viewport.get_texture().get_image().get_data()
			view._select(1,key)
			await frames(4)
			check(view.viewport.get_texture().get_image().get_data() != before,key+" changes face render")
		view.save_profile()
		var saved := PlayerProfile.new()
		saved.load_from()
		check(saved.value.vrm_style == 1 and saved.value.vrm_eye_shape == 1 and saved.value.vrm_brows == 1 and saved.value.vrm_mouth == 1,"parts and facial choices persist")
	# Stress the renderer lifetime path without adding a new resource import.
	for index in 10:
		view._select(index%PlayerProfile.LIMITS.vrm_style,"vrm_style")
		view._select(index%VrmParts.BODY[view.draft.vrm_model].size(),"vrm_clothes")
	await frames(5)
	check(view.avatar.get_child_count() == 2,"rapid part changes keep one actor and card prop")
	var warm_parent := Node3D.new()
	view.avatar.get_parent().add_child(warm_parent)
	await StartupCatalog.warm_avatar_parts(warm_parent)
	await frames(3)
	check(warm_parent.get_child_count() == 2,"startup prepares both bases and all part variants")
	warm_parent.queue_free()
	await frames(4)
	hair_atlas.save_png("res://build/checks/vrm-parts/hair-grid.png")
	body_atlas.save_png("res://build/checks/vrm-parts/costume-grid.png")
	view.queue_free()
	await frames(6)
	print("VRM parts: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
