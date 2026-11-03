extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ",message)
func frames(count: int) -> void:
	for frame in count: await process_frame
	await RenderingServer.frame_post_draw
func screenshot(name: String) -> void:
	await frames(3)
	root.get_texture().get_image().save_png("res://build/checks/vrm-"+name+".png")
func run() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_size(root.get_viewport_rid(),1280,720)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var editor := LegacyCharacterEditor.new()
	host.add_child(editor)
	await frames(4)
	var original_draft := editor.draft.duplicate(true)
	editor._open_vrm_preview()
	await frames(5)
	var view := editor.vrm_preview
	check(view != null and not editor.visible,"editor opens ready-model preview")
	for model_index in VrmAvatar.MODELS.size():
		view.select_model(model_index)
		await frames(15)
		check(view.avatar.actor.get("vrm_meta").license_name == "CC0","imported CC0 metadata")
		check(view.avatar.skeleton != null,"humanoid skeleton exists")
		check(view.avatar.meshes.size()>0,"textured meshes exist")
		var toon_count := 0
		for mesh in view.avatar.meshes:
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.mesh.surface_get_material(surface)
				if material is ShaderMaterial: toon_count += 1
		check(toon_count>0,"MToon materials survive import")
		print("VRM_MODEL ",model_index," bones=",view.avatar.skeleton.get_bone_count()," meshes=",view.avatar.meshes.size()," shaders=",toon_count," expressions=",view.avatar.expression_names())
		view.set_face_view(false)
		await screenshot("%d-full" % model_index)
		view.rotate_model(.55)
		await screenshot("%d-angle" % model_index)
		view.rotate_model(-.55)
		view.set_face_view(true)
		view.set_lighting(0)
		await screenshot("%d-face" % model_index)
		var original_frame := view.viewport.get_texture().get_image().get_data()
		for light_index in [1,2]:
			view.set_lighting(light_index)
			await screenshot("%d-light-%d" % [model_index,light_index])
		check(view.viewport.get_texture().get_image().get_data() != original_frame,"lighting changes actual rendered model")
		view.set_lighting(0)
		var expressions := view.avatar.expression_names()
		check("blink" in expressions,"blink expression imported")
		if "blink" in expressions:
			view.avatar.set_expression("blink")
			await screenshot("%d-blink" % model_index)
			var blink_frame := view.viewport.get_texture().get_image().get_data()
			view.avatar.set_expression("RESET")
			await frames(3)
			check(view.viewport.get_texture().get_image().get_data() != blink_frame,"blink/reset changes rendered eyes")
		for expression in ["happy","angry"]:
			if expression in expressions:
				view.avatar.set_expression(expression)
				await screenshot("%d-%s" % [model_index,expression])
		view.avatar.set_expression("RESET")
	view.select_model(0)
	await frames(3)
	check(view.avatar.get_child_count() == 1,"model switches release old actors")
	view.close()
	await frames(5)
	check(editor.visible and editor.draft == original_draft,"return preserves original profile draft")
	check(not is_instance_valid(view),"preview and models released")
	for size in [Vector2i(960,540),Vector2i(1920,1080)]:
		root.size = size
		root.content_scale_size = size
		RenderingServer.viewport_set_size(root.get_viewport_rid(),size.x,size.y)
		editor._open_vrm_preview()
		await frames(4)
		view = editor.vrm_preview
		check(view.size.x <= size.x and view.size.y <= size.y,"preview fits %s" % size)
		check(view.light_select.get_global_rect().end.x <= size.x,"controls fit %s" % size)
		view.close()
		await frames(4)
	editor.queue_free()
	host.queue_free()
	await frames(6)
	print("VRM preview: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
