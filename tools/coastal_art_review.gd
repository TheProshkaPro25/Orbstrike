extends SceneTree
const BACKGROUND := preload("res://tools/test_window.gd")
const OUT := "res://build/checks/presentation/coastal-archipelago-20261117"
class Stage extends "res://scenes/main.gd":
	func _ready() -> void: _build_world()
	func _initial_arena_location() -> int: return 3
func _initialize() -> void:
	BACKGROUND.background(self)
	_run.call_deferred()
func _finalize() -> void:
	BACKGROUND.finish(self)
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
	var game := Stage.new()
	root.add_child(game)
	var samples := [
		[Vector3(-434,285,503),Vector3(-96,-8,-96),-.15,"flyby-wide"],
		[Vector3(262,143,365),Vector3(-128,-19,-232),.23,"flyby-coast"],
		[Vector3(0,52,63),Vector3(0,0,4),0.0,"gameplay"],
		[Vector3(19,8,29),Vector3(0,3,-17),0.0,"low-gameplay"],
		[Vector3(-205,15,123),Vector3(-160,-4,96),0.0,"shore"],
		[Vector3(214,12,267),Vector3(239,-6,235),0.0,"clear-shallows"],
		[Vector3(-227,45,-119),Vector3(-410,15,-255),0.0,"lighthouse"],
	]
	for s in samples:
		game.cam.location_frame(s[0],s[1],52.0,s[2])
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT.path_join(s[3]+".png"))
		if s[3] == "clear-shallows":
			await create_timer(1.2).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUT.path_join("clear-shallows-motion.png"))
	GraphicsSettings.force_level(GraphicsSettings.Level.LOW)
	game.apply_graphics()
	for sample in [samples[2],samples[5]]:
		game.cam.location_frame(sample[0],sample[1],52.0,0.0)
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT.path_join(sample[3]+"-low.png"))
	print("COAST ART PASS minimized=",root.mode==Window.MODE_MINIMIZED," unfocused=",root.unfocusable," fps=",Engine.max_fps)
	game.queue_free()
	await process_frame
	GameLoading._inst.queue_free()
	await process_frame
	quit()
