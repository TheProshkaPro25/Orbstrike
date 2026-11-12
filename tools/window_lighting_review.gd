extends SceneTree
var main: Node
var out_dir := "user://window-lighting"
func _initialize() -> void: call_deferred("run")
func frames(n: int) -> void:
	for i in n: await process_frame
func shot(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	frame.save_png(path)
	return frame
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.max_fps=60
	GraphicsSettings.max_fps=60
	GraphicsSettings.level=GraphicsSettings.Level.MEDIUM
	root.size=Vector2i(1280,720)
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(3)
	main._preview_arena_location(0)
	main.team_menu.hide()
	main.ui_layer.visible=false
	main.arena._motes.emitting=false
	main.arena._motes.hide()
	main.cam.snap_overview()
	await frames(10)
	var on := await shot(out_dir.path_join("on.png"))
	var lights: Array=[]
	for l in main.arena._sanctuary_lights:
		if l.has_meta("window_projector"):
			lights.append(l)
			assert(l.light_projector!=null and l.shadow_enabled)
			l.visible=false
	await frames(8)
	var off := await shot(out_dir.path_join("off.png"))
	var changed:=0
	for y in range(240,700,2):
		for x in range(60,1220,2):
			var a:=on.get_pixel(x,y)
			var b:=off.get_pixel(x,y)
			if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()>.035: changed+=1
	print("WINDOW PROJECTION lights=",lights.size()," affected_samples=",changed)
	for l in lights:l.visible=true
	main.cam._set_static(Vector3(0,8,38),Vector3(0,12,-45),{"fov":64.0,"smooth":4.0,"hand":0.0})
	main.cam.cut()
	await frames(8)
	await shot(out_dir.path_join("ground.png"))
	var shafts: Array = main.arena._sanctuary_shafts
	assert(shafts.size() == lights.size())
	var shaft_noise: Texture2D
	for index in shafts.size():
		var shaft: MeshInstance3D = shafts[index]
		var material := shaft.material_override as ShaderMaterial
		assert(shaft.visible and shaft.get_meta("window_projector") == index)
		assert(material.shader.resource_path == "res://assets/vfx_vendor/effects_lab/shaft.gdshader")
		assert(shaft.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		var noise := material.get_shader_parameter("noise_texture") as Texture2D
		if shaft_noise == null:
			shaft_noise = noise
		assert(noise != null and noise == shaft_noise)
		shaft.hide()
	await frames(8)
	await shot(out_dir.path_join("ground-no-shafts.png"))
	GraphicsSettings.level=GraphicsSettings.Level.LOW
	main.apply_graphics()
	var low_count := 0
	for light in lights:
		if light.visible:
			low_count += 1
			assert(light.shadow_enabled and light.shadow_caster_mask == 0)
	assert(low_count == 2)
	var low_shafts := 0
	for index in shafts.size():
		assert(shafts[index].visible == lights[index].visible)
		if shafts[index].visible:
			low_shafts += 1
	assert(low_shafts == 2)
	print("WINDOW SHAFTS effects_lab=", shafts.size(), " low=", low_shafts)
	await frames(8)
	await shot(out_dir.path_join("low.png"))
	main.queue_free()
	await frames(4)
	if is_instance_valid(SoundFx._inst):SoundFx._inst.queue_free()
	await create_timer(.15,true,false,true).timeout
	quit(0 if lights.size()==4 and changed>1000 else 1)
