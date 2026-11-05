extends SceneTree
## Два внешних окружения в штатном свете/камерах. Никаких меню и подготовки каталога.
class Stage extends "res://scenes/main.gd":
	func _ready() -> void:
		_build_world()

var output := "res://build/checks/location-detail"
var failures := 0
var checks := 0
var report: Array = []
var baseline := false

func solid(mesh: ArrayMesh, label: String) -> void:
	# Совпадающие позиции объединяются, нормальные UV/normal разрывы допустимы.
	# У каждого настоящего ребра должны быть две противоположно направленные грани.
	var edges := {}
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for index in range(0,vertices.size(),3):
		var points: Array[Vector3i] = []
		for j in 3: points.append(Vector3i((vertices[index+j]*1000.0).round()))
		if points[0] == points[1] or points[1] == points[2] or points[0] == points[2]: continue
		for j in 3:
			var a := str(points[j])
			var b := str(points[(j+1)%3])
			var key := a+"/"+b if a < b else b+"/"+a
			var data: Vector2i = edges.get(key,Vector2i.ZERO)
			edges[key] = data+Vector2i(1,1 if a < b else -1)
	var open := 0
	var winding := 0
	for data: Vector2i in edges.values():
		if data.x != 2: open += 1
		if data.y != 0: winding += 1
	check(open == 0,"solid %s: %d open/nonmanifold edges" % [label,open])
	check(winding == 0,"solid %s: %d inconsistent winding edges" % [label,winding])

func effect_state(arena: Arena, enabled: bool, label: String) -> void:
	var budget := 0
	for particles in arena._landscape_effects:
		budget += particles.amount
		check(particles.emitting == enabled and is_equal_approx(particles.speed_scale,1.0 if enabled else 0.0),label+" GPU emitting and speed "+particles.name)
		check(not particles.is_processing() and not particles.is_physics_processing() and (particles.can_process() == enabled),label+" no CPU handler / inherited process "+particles.name)
	check(arena._landscape_effects.size() == 3 and budget <= 110,label+" bounded three local GPU emitters / <=110 particles")

func _initialize() -> void:
	if not has_meta("sfery_background_draw"):
		preload("res://tools/test_window.gd").background(self)
	_run.call_deferred()

func _finalize() -> void:
	preload("res://tools/test_window.gd").finish(self)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1
	print("PASS: " if condition else "FAIL: ", message)

func frames(n: int) -> void:
	for _i in n: await process_frame

func capture(name: String) -> Image:
	await frames(8)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(output.path_join(name + ".png")) == OK, name + " saved")
	check(root.mode == Window.MODE_MINIMIZED and root.unfocusable and Engine.max_fps == 60, name + " minimized unfocusable60FPS")
	var blank := 0
	for y in range(100, image.get_height()-100, 24):
		for x in range(100, image.get_width()-100, 24):
			var c := image.get_pixel(x,y)
			if c.r+c.g+c.b > .09: blank += 1
	check(blank > 60, name + " rendered texture")
	return image

func _run() -> void:
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	baseline = OS.get_environment("ORBSTRIKE_LOCATION_BASELINE") == "1"
	var capture_set := OS.get_environment("ORBSTRIKE_LOCATION_CAPTURE_SET")
	output = output.path_join(capture_set if not capture_set.is_empty() else ("before" if baseline else "full-location-20261105"))
	DirAccess.make_dir_recursive_absolute(output)
	GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
	GraphicsSettings.max_fps = 60
	if not baseline:
		var detail := preload("res://scenes/landscape_detail.gd")
		var canyon := preload("res://scenes/canyon_landscape.gd")
		var harbor := preload("res://scenes/harbor_landscape.gd")
		solid(detail.arch(7,1,4),"arch")
		solid(detail.hull(),"boat shell")
		solid(canyon._wall(-1.26,1.27,139,96,0),"canyon wall")
		solid(canyon._terrace(),"canyon terrace")
		solid(canyon._outcrop(7),"canyon outcrop")
		solid(harbor._roof(),"hip roof")
		solid(harbor._gable(),"gable roof")
		solid(harbor._dome(),"dome")
		solid(harbor._rock(),"island")
		solid(harbor._spandrel(),"bridge spandrel")
	root.size = Vector2i(1280,720)
	var locations := [1,2]
	var only := OS.get_environment("ORBSTRIKE_LOCATION_ONLY")
	if only in ["1","2"]: locations = [int(only)]
	for location in locations:
		ArenaLocations._current = location
		var stage := Stage.new()
		root.add_child(stage)
		await frames(6)
		stage.cam.set_process(false)
		stage.arena._motes.emitting = false
		var static_nodes := stage.arena._decor.find_children("*","MultiMeshInstance3D",true,false)
		var instances := 0
		for node in static_nodes:
			instances += node.multimesh.instance_count
		check(stage.arena.markers.size() == 6,"six unchanged slots in location%d" % location)
		for slot in 6:
			check(stage.arena.slot_at(stage.arena.slot_position(slot)) == slot,"slot%d maps in location%d" % [slot,location])
		check(stage.arena.get_node("Floor").get_child_count() == 5,"unchanged floor and four physics walls")
		check(stage.arena._decor.find_children("*","CollisionObject3D",true,false).is_empty(),"landscape creates no physical obstacles")
		if not baseline:
			check(stage.arena._decor.get_meta("detailed_location", -1) == location,"detailed landscape built%d" % location)
		check(static_nodes.size() < 85,"bounded static batches location%d: %d" % [location,static_nodes.size()])
		check(instances < 5000,"bounded static instances location%d: %d" % [location,instances])
		if location == 1:
			var clearance := INF
			for node in static_nodes:
				var mesh: Mesh = node.multimesh.mesh
				if not mesh.get_meta("canyon_far_ridge",false): continue
				var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				for instance in node.multimesh.instance_count:
					var placement: Transform3D = node.transform*node.multimesh.get_instance_transform(instance)
					for vertex in vertices:
						var world := placement*vertex
						clearance = minf(clearance,Vector2(world.x,world.z).length())
			check(clearance > 200 and clearance < INF,"all far ridge vertices outside r200: %.2f" % clearance)
		var actors: Array[CreatureBall] = []
		for i in 2:
			var ball := CreatureBall.new()
			stage.world.add_child(ball)
			ball.setup(CardDB.creature([&"creature_klykar_shadow",&"creature_kolossar_light"][i]),i)
			ball.freeze_at(Vector3((i*2-1)*Arena.STEP_X,.36,Arena.STEP_Z*.5))
			ball.set_label_allowed(false)
			ball.open_animated(false)
			actors.append(ball)
			var card := ArenaCardNode.new()
			stage.world.add_child(card)
			card.position = Vector3(ball.position.x,0,ball.position.z)
			card.show_facedown(i,CardDB.card(CardDB.arena_ids()[i]))
		await create_timer(1.5).timeout
		for actor in actors:
			actor.set_process(false)
			actor._anim.set_process(false)
		for size in [Vector2i(1280,720),Vector2i(960,540)]:
			root.size = size
			stage.cam.location_preview_view()
			stage.cam.cut()
			await capture("location%d-%d-preview" % [location,size.x])
			stage.cam.snap_overview()
			await capture("location%d-%d-gameplay" % [location,size.x])
		root.size = Vector2i(1280,720)
		stage.cam._set_static(Vector3(8,22,78),Vector3(0,7,0),{"fov":58.0,"smooth":4.0,"hand":0.0})
		stage.cam.cut()
		await capture("location%d-architecture" % location)
		# Обратный и боковой ракурсы выявляют декорацию только за одной камерой.
		stage.cam._set_static(Vector3(-64,36,-57),Vector3(0,6,10),{"fov":62.0,"smooth":4.0,"hand":0.0})
		stage.cam.cut()
		await capture("location%d-reverse" % location)
		stage.cam._set_static(Vector3(-74,27,44),Vector3(5,8,-25),{"fov":62.0,"smooth":4.0,"hand":0.0})
		stage.cam.cut()
		await capture("location%d-side" % location)
		# Крупнее источник эффекта вместе с архитектурой: поле с анимированными
		# картами не попадает в область сравнения и не может подменить движение FX.
		if location == 1:
			stage.cam._set_static(Vector3(-60,21,-8),Vector3(-78,12,-55),{"fov":58.0,"smooth":4.0,"hand":0.0})
		else:
			stage.cam._set_static(Vector3(121,77,-84),Vector3(99,73,-145),{"fov":52.0,"smooth":4.0,"hand":0.0})
		stage.cam.cut()
		var phases: Array[Image] = []
		for phase in 3:
			await frames(36)
			phases.append(await capture("location%d-effects-%d" % [location,phase]))
		var moving := 0
		for y in range(270,450):
			for x in range(470,810):
				var a := phases[0].get_pixel(x,y)
				var b := phases[2].get_pixel(x,y)
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > .018: moving += 1
		check(moving > 30,"visible GPU atmosphere motion location%d: %d changed source pixels" % [location,moving])
		effect_state(stage.arena,true,"active%d" % location)
		GraphicsSettings.force_level(GraphicsSettings.Level.LOW)
		stage.apply_graphics()
		stage.cam.snap_overview()
		await capture("location%d-low" % location)
		GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
		# Реальные методы аренды; изолированное хранилище не вызывает Boot/prepare.
		var pool := GameLoading.i()
		if pool._storage == null:
			pool._storage = Node3D.new()
			pool._storage.visible = false
			pool._storage.process_mode = Node.PROCESS_MODE_DISABLED
			pool.add_child(pool._storage)
		var original_id: int = stage.arena.get_instance_id()
		var individual_meshes: Array = []
		for node in stage.arena._decor.find_children("*","MeshInstance3D",true,false):
			individual_meshes.append([node.get_instance_id(),node.mesh.get_instance_id(),node.transform])
		var mesh_ids: Array = []
		for node in static_nodes: mesh_ids.append(node.multimesh.get_instance_id())
		pool.return_arena(stage.arena)
		var effect_ids: Array = []
		for particles in stage.arena._landscape_effects: effect_ids.append(particles.get_instance_id())
		await frames(8)
		effect_state(stage.arena,false,"pooled%d" % location)
		check(not stage.arena.visible and stage.arena.process_mode == Node.PROCESS_MODE_DISABLED and not stage.arena._motes.emitting,"pooled landscape hidden and disabled%d" % location)
		var leased: Arena = pool.take_arena(location)
		check(leased.get_instance_id() == original_id and leased._built,"same prepared arena leased%d" % location)
		leased.reparent(stage.world,false)
		var restored_effect_ids: Array = []
		for particles in leased._landscape_effects: restored_effect_ids.append(particles.get_instance_id())
		check(restored_effect_ids == effect_ids,"GPU emitters reused through pool%d" % location)
		effect_state(leased,true,"restored%d" % location)
		var returned_nodes := leased._decor.find_children("*","MultiMeshInstance3D",true,false)
		var returned_ids: Array = []
		for node in returned_nodes: returned_ids.append(node.multimesh.get_instance_id())
		check(returned_ids == mesh_ids,"static meshes survive resident round trip%d" % location)
		var restored_meshes: Array = []
		for node in leased._decor.find_children("*","MeshInstance3D",true,false):
			restored_meshes.append([node.get_instance_id(),node.mesh.get_instance_id(),node.transform])
		check(restored_meshes == individual_meshes,"individual landscape mesh identity and pose survive round trip%d" % location)
		check(leased.visible and leased.process_mode == Node.PROCESS_MODE_INHERIT and leased._motes.emitting,"leased landscape restored%d" % location)
		check(pool.preparation_count == 0 and pool.arena_build_count == 0,"resident round trip starts no catalog preparation%d" % location)
		report.append({"location":location,"static_batches":static_nodes.size(),"instances":instances,"resident_roundtrip":true})
		stage.queue_free()
		await frames(5)
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(4)
	var result := {"checks":checks,"failures":failures,"baseline":baseline,"locations":report,"limitations":["isolated landscape fixture; not full match or Boot timing","muted sound; no Windows run","static batching budget is not a frame rate benchmark"]}
	var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	print("LOCATION DETAIL ",JSON.stringify(result))
	quit(1 if failures else 0)
