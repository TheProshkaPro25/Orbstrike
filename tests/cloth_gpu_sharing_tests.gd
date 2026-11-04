extends "res://tests/cloth_preparation_cache_tests.gd"
## Real identical Ratnik actors: immutable content, independent state and lifetime.
const IMMUTABLE := ["_constraints_buffer","_rest_positions_buffer","_bone_indices_buffer","_bone_weights_skin_buffer","_cloth_weights_buffer","_indices_gpu_buffer","_peer_proxy_indices_buffer","_vert_tri_counts_buffer","_vert_tri_offsets_buffer","_vert_tri_list_buffer","_bindings_buffer"]
const MUTABLE := ["_positions_buffer","_predicted_buffer","_velocities_buffer","_lambda_buffer","_bone_transforms_buffer","_skinned_targets_buffer","_colliders_buffer","_collider_tri_buffer","_face_normals_buffer","_pin_overrides_buffer"]
var out := "res://build/checks/cloth-sharing"
var report: Dictionary = {}

func read_gpu(solver: Node, label: String) -> Dictionary:
	var buffers: Dictionary = {}
	for field in IMMUTABLE + MUTABLE: buffers[field] = solver.get(field)
	RenderingServer.call_on_render_thread(func() -> void:
		var device := RenderingServer.get_rendering_device()
		var result: Dictionary = {}
		for field in buffers:
			var rid: RID = buffers[field]
			result[field] = device.buffer_get_data(rid) if rid.is_valid() else PackedByteArray()
		readbacks[label] = result)
	while not readbacks.has(label): await process_frame
	return readbacks[label]

func shared_stats(label: String) -> Dictionary:
	RenderingServer.call_on_render_thread(func() -> void:
		readbacks[label] = Solver.shared_gpu_stats())
	while not readbacks.has(label): await process_frame
	return readbacks[label]

func inventory(solver: Node, data: Dictionary) -> Dictionary:
	var result := {"immutable_bytes":0,"mutable_bytes":0,"fields":{}}
	for field in IMMUTABLE + MUTABLE:
		var rid: RID = solver.get(field)
		var size: int = data[field].size()
		result.fields[field] = {"rid":rid.get_id(),"bytes":size,"sha256":Solver._digest(data[field])}
		result["immutable_bytes" if field in IMMUTABLE else "mutable_bytes"] += size
	return result

func picture(ball: CreatureBall, label: String) -> void:
	for b in balls: b.visible = b == ball
	ball._shell.visible = false
	var height := ball._anim.get_height() * ball._anim.global_basis.get_scale().y
	var distance := maxf(height,ball._anim.get_extent()) * 2.5
	var origin := ball._anim.global_position
	root.get_camera_3d().look_at_from_position(origin+Vector3(-distance*0.6,height*0.7,-distance),origin+Vector3(0,height*0.5,0))
	await frames(2)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(out+"/"+label+".png")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	check(RenderingServer.get_rendering_device() != null,"Vulkan required")
	if failures: quit(1); return
	CreatureModels.resident_catalog = true
	root.size = Vector2i(800,800)
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-35,-35,0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("242a35")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.look_at_from_position(Vector3(-1.1,1.0,-1.8),Vector3(0,0.7,0))
	Solver.clear_canonical_cache()
	var first := await prepare("first",true)
	report.disk_hits = Solver.canonical_cache_hits.duplicate()
	report.disk_misses = Solver.canonical_cache_misses.duplicate()
	check(Solver.canonical_cache_hits.get("cloth-extract",0) > 0 and Solver.canonical_cache_hits.get("cloth-constraints",0) > 0,"shipped canonical disk caches survive allocator-only vendor edit")
	var second := await prepare("second",true)
	var a: Node = balls[0]._anim._cloth
	var b: Node = balls[1]._anim._cloth
	report.before = [inventory(a,first.gpu),inventory(b,second.gpu)]
	report.shared_two = await shared_stats("stats-two")
	check(report.shared_two.references == report.shared_two.buffers*2,"two live references per immutable allocation")
	for field in IMMUTABLE:
		check(first.gpu[field] == second.gpu[field],"identical immutable input "+field)
		if (a.get(field) as RID).is_valid(): check(a.get(field) == b.get(field),"same immutable RID "+field)
	for field in MUTABLE:
		if (a.get(field) as RID).is_valid(): check(a.get(field) != b.get(field),"independent state "+field)
	check(a._positions_img_rid != b._positions_img_rid and a._normals_img_rid != b._normals_img_rid,"independent output textures")
	await picture(balls[0],"rest")
	# Move only the second actor, manually step only its solver.
	balls[1].visible = true
	balls[1].process_mode = Node.PROCESS_MODE_INHERIT
	b._ref_node.rotation.y += 0.5
	b._ref_node.position.x += 0.1
	for i in 8:
		b._process(1.0/60.0)
		await process_frame
	var moved := await read_gpu(b,"moved")
	report.moved = inventory(b,moved)
	var unchanged := await read_gpu(a,"unchanged")
	check(unchanged._positions_buffer == first.gpu._positions_buffer,"other actor positions untouched")
	check(moved._positions_buffer != second.gpu._positions_buffer,"movement changes own simulation")
	for field in IMMUTABLE: check(moved[field] == first.gpu[field],"immutable after movement "+field)
	await picture(balls[1],"moved")
	var parent := Node3D.new()
	root.add_child(parent)
	var previous: RID = b._positions_buffer
	balls[1].reparent(parent)
	check(b._positions_buffer == previous and b._gpu_init_done,"reparent retains live GPU resources")
	check(await shared_stats("stats-reparent") == report.shared_two,"reparent leaves shared refcounts unchanged")
	b.reset_simulation()
	b._process(1.0/60.0)
	await frames(2)
	balls[0].queue_free()
	await frames(4)
	b._process(1.0/60.0)
	await frames(2)
	report.shared_one = await shared_stats("stats-one")
	check(report.shared_one.references == report.shared_one.buffers,"first free retains one reference")
	var survivor := await read_gpu(b,"survivor")
	for field in IMMUTABLE: check(survivor[field] == second.gpu[field],"surviving reference after first free "+field)
	balls[1].queue_free()
	balls.clear()
	await frames(4)
	report.shared_zero = await shared_stats("stats-zero")
	check(report.shared_zero.buffers == 0 and report.shared_zero.bytes == 0,"last free releases every pooled allocation")
	parent.queue_free()
	CreatureModels.resident_catalog = false
	CreatureModels.clear()
	report.checks = checks
	report.failures = failures
	var file := FileAccess.open(out+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("CLOTH GPU SHARING ",JSON.stringify(report))
	quit(1 if failures else 0)
