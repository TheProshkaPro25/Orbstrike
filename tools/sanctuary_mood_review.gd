extends SceneTree
## Сравнение настроения зала и читаемости тёмного/яркого существ без показа окна.
var main: Node
var actors: Array[CreatureBall] = []
var failures := 0
var out_dir := "user://sanctuary-mood"
var variant := "after"
var report: Array = []

func _initialize() -> void:
	if not has_meta("sfery_background_draw"):
		preload("res://tools/test_window.gd").background(self)
	call_deferred("run")

func _finalize() -> void:
	preload("res://tools/test_window.gd").finish(self)

func frames(n: int) -> void:
	for i in n: await process_frame

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func capture(name: String) -> Image:
	await frames(3)
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.save_png(out_dir.path_join(name + ".png"))
	return result

func luminance(c: Color) -> float:
	return c.r * .2126 + c.g * .7152 + c.b * .0722

func mean_luma(image: Image, area: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(area.position.y, area.end.y, 3):
		for x in range(area.position.x, area.end.x, 3):
			total += luminance(image.get_pixel(x, y))
			count += 1
	return total / maxi(count, 1)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir = args[0]
	if args.size() > 1: variant = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.max_fps = 60
	GraphicsSettings.max_fps = 60
	GraphicsSettings.level = GraphicsSettings.Level.HIGH
	ArenaLocations._current = 0
	root.size = Vector2i(1280, 720)
	root.unfocusable = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(4)
	main.team_menu._preview.release()
	main.team_menu.hide()
	main.ui_layer.visible = false
	main.arena._motes.emitting = false
	for id in [&"creature_dragnar_fire", &"creature_klykar_shadow", &"creature_kolossar_light"]:
		var index := actors.size()
		var ball := CreatureBall.new()
		main.world.add_child(ball)
		ball.setup(CardDB.creature(id), index)
		ball.freeze_at(Vector3((index - 1) * Arena.STEP_X, .36, Arena.STEP_Z * .5))
		ball.set_label_allowed(false)
		ball.open_animated(false)
		actors.append(ball)
		var card := ArenaCardNode.new()
		main.world.add_child(card)
		card.position = Vector3(ball.position.x, 0, ball.position.z)
		card.show_facedown(0, CardDB.card(CardDB.arena_ids()[index]))
	await create_timer(1.8).timeout
	for actor in actors:
		actor.set_process(false)
		actor._anim.idle_on = false
		actor._anim._clock = 0
		actor._anim._phase = 0
		actor._anim.reset()
		actor._anim.set_process(false)
	for level in [GraphicsSettings.Level.LOW, GraphicsSettings.Level.MEDIUM, GraphicsSettings.Level.HIGH]:
		GraphicsSettings.level = level
		main.apply_graphics()
		main.cam.snap_overview()
		main.cam.set_process(false)
		await frames(15)
		await capture("%s-%s-wide" % [variant, level])
		main.cam._set_static(Vector3(8, 22, 78), Vector3(0, 7, Arena.STEP_Z * .5), {"fov":58.0,"smooth":4.0,"hand":0.0})
		main.cam.cut()
		var lit := await capture("%s-%s-creature" % [variant, level])
		for actor in actors: actor._figure.visible = false
		var empty := await capture("%s-%s-architecture" % [variant, level])
		for actor in actors: actor._figure.visible = true
		var samples: Array = []
		for actor in actors:
			var base: Vector3 = actor.global_position - Vector3.UP * CreatureBall.RADIUS
			var a: Vector2 = main.cam.unproject_position(base + Vector3.UP * actor.figure_height() * .90)
			var b: Vector2 = main.cam.unproject_position(base + Vector3.UP * actor.figure_height() * .20)
			var rect := Rect2i(Vector2i(minf(a.x,b.x) - 100, minf(a.y,b.y)), Vector2i(200, maxf(absf(a.y-b.y),1)))
			rect = rect.intersection(Rect2i(0,0,lit.get_width(),lit.get_height()))
			var count := 0
			var total := 0.0
			var contrast := 0.0
			for y in range(rect.position.y, rect.end.y, 2):
				for x in range(rect.position.x, rect.end.x, 2):
					var c := lit.get_pixel(x,y)
					var bg := empty.get_pixel(x,y)
					if Vector3(c.r-bg.r,c.g-bg.g,c.b-bg.b).length() < .10: continue
					count += 1
					total += luminance(c)
					contrast += absf(luminance(c)-luminance(bg))
			var mean := total / maxi(count,1)
			var delta := contrast / maxi(count,1)
			samples.append({"id":String(actor.def.id),"samples":count,"body_mean_luma":mean,"contrast":delta})
			check(count > 100 and mean > .07 and delta > .04, "readable creature %s at quality %s" % [actor.def.id,level])
		var architecture_luma := mean_luma(empty,Rect2i(40,50,1200,450))
		if variant != "before":
			check(architecture_luma < .27, "subdued sanctuary architecture at quality %s" % level)
		report.append({"level":level,"architecture_luma":architecture_luma,"creatures":samples})
	main.queue_free()
	await frames(5)
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(3)
	await create_timer(.2,true,false,true).timeout
	var file := FileAccess.open(out_dir.path_join(variant+"-result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"variant":variant,"report":report},"  "))
	print("SANCTUARY MOOD ",JSON.stringify({"failures":failures,"report":report}))
	quit(1 if failures else 0)
