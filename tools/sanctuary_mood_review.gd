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
	for id in [&"creature_dragnar_fire", &"creature_klykar_shadow", &"creature_kolossar_light",
			&"creature_gorgul_shadow", &"creature_ratnik_shadow", &"creature_levian_shadow"]:
		var index := actors.size()
		var side := 1.0 if index < 3 else -1.0
		var ball := CreatureBall.new()
		main.world.add_child(ball)
		ball.setup(CardDB.creature(id), index)
		ball.freeze_at(Vector3((index % 3 - 1) * Arena.STEP_X, .36, side * Arena.STEP_Z * .5))
		ball._figure.rotation.y = 0.0 if side > 0.0 else PI
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
	var fills: Array[Light3D] = []
	for light: Light3D in main.arena._sanctuary_lights:
		if light.light_cull_mask == CreatureBall.FIGURE_LIGHT_LAYER:
			fills.append(light)
			check(not light.shadow_enabled and light.light_volumetric_fog_energy == 0.0,
				"figure fill leaves sanctuary shadows and shafts to the fixtures")
	check(fills.size() == 2, "both facing directions have a figure fill")
	for level in [GraphicsSettings.Level.LOW, GraphicsSettings.Level.MEDIUM, GraphicsSettings.Level.HIGH]:
		GraphicsSettings.level = level
		main.apply_graphics()
		main.cam.snap_overview()
		main.cam.set_process(false)
		await frames(15)
		await capture("%s-%s-wide" % [variant, level])
		for fill: Light3D in fills:
			check(fill.visible, "figure fill active at quality %s" % level)
		for row in 2:
			await review_row(level, row, fills)
		for actor in actors: actor._figure.show()
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


func review_row(level: int, row: int, fills: Array[Light3D]) -> void:
	var side := 1.0 if row == 0 else -1.0
	for index in actors.size():
		actors[index]._figure.visible = (index < 3) == (row == 0)
	main.cam._set_static(Vector3(8 * side, 22, 78 * side), Vector3(0, 7, Arena.STEP_Z * .5 * side),
		{"fov":58.0,"smooth":4.0,"hand":0.0})
	main.cam.cut()
	var caption := "%s-%s-row%d" % [variant, level, row]
	var lit := await capture(caption + "-creature")
	for fill: Light3D in fills: fill.hide()
	var unfilled := await capture(caption + "-no-fill")
	for actor in actors: actor._figure.hide()
	var empty := await capture(caption + "-architecture")
	for fill: Light3D in fills: fill.show()
	var empty_lit := await capture(caption + "-architecture-fill")
	var samples: Array = []
	for index in range(row * 3, row * 3 + 3):
		var result := sample_figure(actors[index], lit, unfilled, empty)
		samples.append(result)
		check(result.samples > 100 and result.body_mean_luma > .12 and result.contrast > .04,
			"readable creature %s at quality %s (%s)" % [result.id, level, result])
		check(result.body_mean_luma > result.without_fill + .02,
			"visible figure fill on %s at quality %s (%s)" % [result.id, level, result])
	var architecture_rect := Rect2i(40, 50, 1200, 450)
	var architecture_luma := mean_luma(empty_lit, architecture_rect)
	var architecture_delta := absf(architecture_luma - mean_luma(empty, architecture_rect))
	check(architecture_luma < .29 and architecture_delta < .006,
		"subdued sanctuary architecture at quality %s, row %s (%s, delta %s)" % [level, row, architecture_luma, architecture_delta])
	report.append({"level":level,"row":row,"architecture_luma":architecture_luma,
		"architecture_delta":architecture_delta,"creatures":samples})


func sample_figure(actor: CreatureBall, lit: Image, unfilled: Image, empty: Image) -> Dictionary:
	var base := actor.global_position - Vector3.UP * CreatureBall.RADIUS
	var a: Vector2 = main.cam.unproject_position(base + Vector3.UP * actor.figure_height() * .90)
	var b: Vector2 = main.cam.unproject_position(base + Vector3.UP * actor.figure_height() * .20)
	var rect := Rect2i(Vector2i(minf(a.x,b.x) - 100, minf(a.y,b.y)), Vector2i(200, maxf(absf(a.y-b.y),1)))
	rect = rect.intersection(Rect2i(0,0,lit.get_width(),lit.get_height()))
	var count := 0
	var total := 0.0
	var total_unfilled := 0.0
	var contrast := 0.0
	for y in range(rect.position.y, rect.end.y, 2):
		for x in range(rect.position.x, rect.end.x, 2):
			var c := lit.get_pixel(x,y)
			var unlit := unfilled.get_pixel(x,y)
			var bg := empty.get_pixel(x,y)
			if Vector3(c.r-bg.r,c.g-bg.g,c.b-bg.b).length() < .10 and Vector3(unlit.r-bg.r,unlit.g-bg.g,unlit.b-bg.b).length() < .10: continue
			count += 1
			total += luminance(c)
			total_unfilled += luminance(unlit)
			contrast += absf(luminance(c)-luminance(bg))
	return {"id":String(actor.def.id),"samples":count,"body_mean_luma":total / maxi(count, 1),
		"without_fill":total_unfilled / maxi(count, 1),"contrast":contrast / maxi(count, 1)}
