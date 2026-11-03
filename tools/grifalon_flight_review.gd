extends SceneTree
## Narrow Grifalon flight review: fixed samples, side and rear, minimized.
const WindowTest := preload("res://tools/test_window.gd")
const ReviewState := preload("res://tools/model_review_state.gd")
var out_dir := "res://build/checks/grifalon-flight/before"
func _initialize() -> void:
	WindowTest.background(self)
	call_deferred("run")
func _finalize() -> void: WindowTest.finish(self)
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir=args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size=Vector2i(900,900)
	Engine.max_fps=60
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("172231")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE
	env.environment.ambient_light_energy=.6
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-35,-28,0)
	light.light_energy=1.25
	world.add_child(light)
	var def := CardDB.creature(&"creature_grifalon_gale")
	var actor := CreatureAnim.new()
	world.add_child(actor)
	actor.set_model(CreatureModels.build(def),def)
	actor.set_process(false)
	actor._phase=0
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current=true
	camera.fov=32
	var h := actor.get_height()
	var distance := maxf(h,actor.get_extent())*2.6
	var center := Vector3(0,h*.52+h*.24,0)
	var samples := [["idle",0.25],["idle",0.75],["idle",1.25],["attack",0.4]]
	for sample in samples:
		ReviewState.reset_actor(actor)
		actor.idle_on=true
		if sample[0]=="attack": actor.lunge(h*.22)
		for frame in roundi(float(sample[1])*60): actor._process(1.0/60)
		for side in 2:
			var angle := PI*(.42 if side==0 else 1.0)
			camera.look_at_from_position(center+Vector3(sin(angle),.12,cos(angle)).normalized()*distance,center)
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out_dir.path_join("%s-%.2f-%s.png"%[sample[0],sample[1],"side" if side==0 else "rear"]))
	world.queue_free()
	for frame in 3: await process_frame
	CreatureModels.clear()
	for frame in 3: await process_frame
	print("GRIFALON FLIGHT REVIEW: 4 poses x 2 angles; minimized")
	quit()
