extends SceneTree
## Only the edited Grifalon: before/candidate, rest/idle/attack, front/rear side.
const WindowTest := preload("res://tools/test_window.gd")
const ReviewState := preload("res://tools/model_review_state.gd")
var actors: Array[CreatureAnim] = []
var sources: Array[PackedScene] = []
var out_dir := "res://build/checks/grifalon-wind/gpu"

func _initialize() -> void:
	WindowTest.background(self)
	call_deferred("run")

func _finalize() -> void:
	WindowTest.finish(self)

func frames(count: int) -> void:
	for frame in count: await process_frame

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir=args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.max_fps=60
	root.size=Vector2i(900,900)
	root.unfocusable=true
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
	for variant in ["base","candidate"]:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file("res://build/checks/grifalon-wind/%s/grifalon_gale.glb" % variant,state)==OK)
		var original := document.generate_scene(state)
		var packed := PackedScene.new()
		assert(packed.pack(original)==OK)
		original.free()
		sources.append(packed)
		CreatureModels._scenes["hd:grifalon_gale"]=packed
		var actor := CreatureAnim.new()
		world.add_child(actor)
		actor.set_model(CreatureModels.build(def),def)
		actor.set_process(false)
		actor.visible=false
		actors.append(actor)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current=true
	camera.fov=32
	var height := maxf(actors[0].get_height(),actors[1].get_height())
	var extent := maxf(actors[0].get_extent(),actors[1].get_extent())
	var distance := maxf(height,extent)*2.9
	var center := Vector3(0,height*.52+height*.24,0)
	for index in actors.size():
		var actor := actors[index]
		actor.visible=true
		for pose in ["rest","idle","attack"]:
			ReviewState.reset_actor(actor)
			actor.idle_on=pose!="rest"
			if pose=="rest":
				actor._support.skeleton.reset_bone_poses()
			elif pose=="attack":
				actor.lunge(actor.get_height()*.22)
				for frame in 24:actor._process(1.0/60)
			else:
				for frame in 120:actor._process(1.0/60)
			for side in 2:
				var angle := PI*.125+side*PI*.625
				camera.look_at_from_position(center+Vector3(sin(angle),.12,cos(angle)).normalized()*distance,center)
				await frames(3)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out_dir.path_join("%s-%s-%s.png" % ["before" if index==0 else "after",pose,side]))
		actor.visible=false
	world.queue_free()
	await frames(3)
	sources.clear()
	CreatureModels.clear()
	await frames(3)
	print("GRIFALON WIND: 2 sources, 3 poses, 2 angles; completed minimized")
	quit()
