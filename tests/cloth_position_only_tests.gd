extends "res://tests/cloth_preparation_cache_tests.gd"
## Paired actual Trellis display meshes, identical manual poses and GPU inputs.
class Actor extends Node3D:
	var _base := Vector3.ZERO

const OMITTED_BUFFERS := ["_face_normals_buffer", "_vert_tri_counts_buffer", "_vert_tri_offsets_buffer", "_vert_tri_list_buffer"]
const OMITTED_IMAGES := ["_normals_img_rid", "_welded_index_lookup_rid"]
const COMMON := ["_positions_buffer", "_predicted_buffer", "_velocities_buffer", "_skinned_targets_buffer", "_constraints_buffer", "_indices_gpu_buffer", "_peer_proxy_indices_buffer", "_rest_positions_buffer", "_cloth_weights_buffer", "_collider_tri_buffer"]
var out := "res://build/checks/cloth-position-only"
var pair: Array = []
var control: Dictionary = {}
var report := {"samples": [], "inventory": {}, "timestamps": []}

func collect(n: Node, type: String) -> Node:
	if n.is_class(type): return n
	for child in n.get_children():
		var found := collect(child,type)
		if found != null: return found
	return null

func make_actor(only: bool, element: String = "tide") -> Dictionary:
	var actor := Actor.new()
	root.add_child(actor)
	var model := CreatureModels.build(CardDB.creature(StringName("creature_ratnik_"+element)))
	actor.add_child(model)
	var player := collect(model,"AnimationPlayer") as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play("idle",0)
	player.seek(0.0,true)
	player.advance(0)
	var solver := CreatureCloth.attach(model,only)
	solver.set_process(false)
	solver.wind_frequency = 0.0
	while not solver._gpu_init_done: await process_frame
	var cape := model.find_child("RatnikCape",true,false) as MeshInstance3D
	return {"actor":actor,"model":model,"solver":solver,"player":player,"cape":cape}

func gpu_data(solver: Node, label: String) -> Dictionary:
	RenderingServer.call_on_render_thread(func() -> void:
		var rd := RenderingServer.get_rendering_device()
		var data := {}
		for field in COMMON + OMITTED_BUFFERS:
			var rid: RID = solver.get(field)
			data[field] = rd.buffer_get_data(rid) if rid.is_valid() else PackedByteArray()
		data.output = rd.texture_get_data(solver._positions_img_rid,0)
		readbacks[label] = data)
	while not readbacks.has(label): await process_frame
	return readbacks[label]

func stats(label: String) -> Dictionary:
	RenderingServer.call_on_render_thread(func() -> void: readbacks[label] = Solver.shared_gpu_stats())
	while not readbacks.has(label): await process_frame
	return readbacks[label]

func max_float_delta(a: PackedByteArray, b: PackedByteArray) -> float:
	if a.size() != b.size(): return INF
	var delta := 0.0
	for offset in range(0,a.size(),4):
		delta = maxf(delta,absf(a.decode_float(offset)-b.decode_float(offset)))
	return delta

func sample(label: String, picture: bool = true) -> void:
	var a := await gpu_data(pair[0].solver,label+"-full")
	var b := await gpu_data(pair[1].solver,label+"-only")
	var c := await gpu_data(control.solver,label+"-control") if not control.is_empty() else a
	var row := {"label":label,"bytes":{},"image_equal":null,"trace":{}}
	for field in COMMON:
		var dynamic: bool = field in ["_positions_buffer","_predicted_buffer","_velocities_buffer"]
		var delta := max_float_delta(a[field],b[field]) if dynamic else 0.0
		var control_delta := max_float_delta(a[field],c[field]) if dynamic else 0.0
		if dynamic:
			row.trace[field] = {"full_only_max_delta":delta,"full_full_max_delta":control_delta,"full_only_equal":a[field]==b[field],"full_full_equal":a[field]==c[field]}
			check(delta <= 0.00001 and control_delta <= 0.00001,"paired simulation trace sensitivity "+label+" "+field)
		else: check(a[field] == b[field],"exact simulation inputs "+label+" "+field)
		row.bytes[field] = {"full":FileAccess.get_sha256(save_bytes(a[field],label+"-full-"+field)),"only":FileAccess.get_sha256(save_bytes(b[field],label+"-only-"+field)),"bytes":a[field].size()}
	# Compare output paths with the SAME input buffers, not two independently
	# scheduled simulations. Neither output shader writes those buffers.
	RenderingServer.call_on_render_thread(func() -> void:
		var full: Node = pair[0].solver
		var only: Node = pair[1].solver
		var rd := RenderingServer.get_rendering_device()
		var original: RID = only._output_uniform_set
		var uniforms: Array[RDUniform] = [only._make_uniform(0,full._positions_buffer),only._make_image_uniform(5,only._positions_img_rid),only._make_uniform(7,full._skinned_targets_buffer)]
		var shared_inputs: RID = only._create_uniform_set(only._output_shader,uniforms)
		only._output_uniform_set = shared_inputs
		var cl := rd.compute_list_begin()
		only._dispatch_output_passes(cl,ceili(float(only._particle_count)/64.0),1.0)
		rd.compute_list_end()
		only._output_uniform_set = original
		readbacks[label+"-same-input"] = {"output":rd.texture_get_data(only._positions_img_rid,0),"positions":rd.buffer_get_data(full._positions_buffer)}
		rd.free_rid(shared_inputs))
	while not readbacks.has(label+"-same-input"): await process_frame
	var result: Dictionary = readbacks[label+"-same-input"]
	check(result.output == a.output,"bit-exact position output on identical GPU inputs "+label)
	check(result.positions == a._positions_buffer,"output paths leave simulation state untouched "+label)
	row.bytes.output = {"full":FileAccess.get_sha256(save_bytes(a.output,label+"-full-output")),"only":FileAccess.get_sha256(save_bytes(result.output,label+"-only-output")),"bytes":a.output.size()}
	if picture:
		var images: Array[Image] = []
		for i in 2:
			pair[0].actor.visible = i == 0
			pair[1].actor.visible = i == 1
			await frames(2)
			var im := root.get_texture().get_image()
			im.save_png(out+"/"+label+("-full.png" if i == 0 else "-only.png"))
			images.append(im)
		row.image_equal = images[0].get_data() == images[1].get_data()
		check(row.image_equal,"exact rendered pixels at identical input and TIME "+label)
		for item in pair: item.actor.visible = true
	report.samples.append(row)

func save_bytes(data: PackedByteArray, label: String) -> String:
	var path := out+"/"+label+".bin"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(data)
	return path

func pose(clip: String, time: float) -> void:
	for item in pair + ([control] if not control.is_empty() else []):
		item.player.play(clip,0.0)
		item.player.seek(time,true)
		item.player.advance(0)
	await frames(2)

func steps(count: int) -> void:
	for i in count:
		for item in pair + ([control] if not control.is_empty() else []):
			item.actor.visible = true
			item.solver._process(1.0/60.0)
		if not control.is_empty(): control.actor.visible = false
		await frames(2)

func time_outputs() -> void:
	# Only custom output compute, repeated to amortize tiny dispatches. Same
	# unchanged particle buffers; no viewport or other simulation work in scope.
	for trial in 4:
		var order := [0,1] if trial % 2 == 0 else [1,0]
		for index: int in order:
			var solver: Node = pair[index].solver
			var prefix := "cloth-output-%d-%d" % [trial,index]
			RenderingServer.call_on_render_thread(func() -> void:
				var rd := RenderingServer.get_rendering_device()
				rd.capture_timestamp(prefix+"-begin")
				for repeat in 100:
					var cl := rd.compute_list_begin()
					solver._dispatch_output_passes(cl,ceili(float(solver._particle_count)/64.0),1.0)
					rd.compute_list_end()
				rd.capture_timestamp(prefix+"-end"))
			var collected := []
			for frame in 6:
				await frames(1)
				var key := prefix+"-read-"+str(frame)
				RenderingServer.call_on_render_thread(func() -> void:
					var rd := RenderingServer.get_rendering_device()
					var records := []
					for i in rd.get_captured_timestamps_count():
						var name := rd.get_captured_timestamp_name(i)
						if name.begins_with(prefix): records.append({"name":name,"gpu_ns":rd.get_captured_timestamp_gpu_time(i),"cpu_us":rd.get_captured_timestamp_cpu_time(i)})
					readbacks[key] = records)
				while not readbacks.has(key): await process_frame
				if not readbacks[key].is_empty(): collected = readbacks[key]
			report.timestamps.append({"trial":trial,"only":index==1,"repeats":100,"records":collected})


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	create_timer(45.0).timeout.connect(func() -> void: check(false,"cloth fixture timeout"); quit(1))
	check(RenderingServer.get_rendering_device() != null,"Vulkan required")
	if failures: quit(1); return
	root.size = Vector2i(800,800)
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	root.msaa_3d = Viewport.MSAA_DISABLED
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.look_at_from_position(Vector3(-0.8,0.7,-1.0),Vector3(0,0.31,0))
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
	CreatureModels.resident_catalog = true
	pair = [await make_actor(false),await make_actor(true)]
	control = await make_actor(false)
	control.actor.visible = false
	var box := CreatureModels.world_aabb(pair[0].model)
	var center := box.get_center()
	var height := box.size.y
	var distance := maxf(height,maxf(box.size.x,box.size.z))*1.8
	camera.look_at_from_position(center+Vector3(-distance*.6,height*.15,-distance),center)
	report.bounds = {"position":str(box.position),"size":str(box.size),"meta_height":pair[0].model.get_meta("height")}
	check(not pair[0].solver.output_positions_only and pair[1].solver.output_positions_only,"separate explicit output modes")
	check(pair[1].solver._mesh_instance_node.layers == 0 and pair[1].solver._mesh_instance_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"proxy is never displayed or shadowed")
	var base := await gpu_data(pair[0].solver,"inventory-full")
	var opt := await gpu_data(pair[1].solver,"inventory-only")
	var saved := 0
	for field in OMITTED_BUFFERS:
		check((pair[0].solver.get(field) as RID).is_valid() and not (pair[1].solver.get(field) as RID).is_valid(),"omitted GPU buffer "+field)
		report.inventory[field] = {"full":base[field].size(),"only":opt[field].size()}
		saved += base[field].size()
	for field in OMITTED_IMAGES:
		check((pair[0].solver.get(field) as RID).is_valid() and not (pair[1].solver.get(field) as RID).is_valid(),"omitted GPU texture "+field)
		report.inventory[field] = {"full":567*16,"only":0}
		saved += 567*16
	for field in ["_normals_shader","_normals_pipeline","_normals_uniform_set"]:
		check((pair[0].solver.get(field) as RID).is_valid() and not (pair[1].solver.get(field) as RID).is_valid(),"omitted normals dispatch resource "+field)
	report.logical_payload_saved = saved
	report.retained_collision_indices_bytes = base._indices_gpu_buffer.size()
	await steps(1)
	await sample("warm-start")
	await steps(12)
	await sample("idle")
	for clip in ["stance","attack","hit","roar"]:
		for time in [0.15,0.45,0.8]:
			await pose(clip,time)
			await steps(3)
			await sample(clip+"-"+str(time),time==0.45)
	var rim := ShaderMaterial.new()
	rim.shader = Shader.new()
	rim.shader.code = CreatureBall.RIM_SHADER.replace("TIME", "1.25")
	rim.set_shader_parameter("col",CreatureBall.OWNER_GLOW[0])
	rim.set_shader_parameter("strength",CreatureBall.RIM_STRENGTH[0])
	for item in pair:
		CreatureBall._set_rim(item.model,rim)
		CreatureCloth.set_flash(item.cape,Color(1,0.4,0.1,0.7))
		var material := item.cape.get_active_material(0) as ShaderMaterial
		check(material.next_pass.get_shader_parameter("positions_tex") == item.solver._positions_tex,"owner rim consumes this actor's positions")
	await sample("rim-flash")
	# Rear viewpoint also displays the two-sided cape and its rim hook.
	camera.look_at_from_position(center+Vector3(distance*.6,height*.15,distance),center)
	await sample("rear-rim-flash")
	control.actor.queue_free()
	control = {}
	await frames(4)
	var refs_before := await stats("refs-before")
	var holder := Node3D.new()
	root.add_child(holder)
	for item in pair:
		var previous: RID = item.solver._positions_buffer
		item.actor.reparent(holder)
		item.actor.position = Vector3(.08,0,.03)
		item.actor.rotation.y = .4
		check(item.solver._positions_buffer == previous and item.solver._gpu_init_done and item.solver._needs_warm_start,"lease/reparent keeps GPU storage and resets warm start")
	await steps(1)
	await sample("reparent-warm")
	check(await stats("refs-after") == refs_before,"reparent leaves pooled references unchanged")
	for item in pair:
		item.actor.visible = false
		item.actor.process_mode = Node.PROCESS_MODE_DISABLED
	var parked := await gpu_data(pair[1].solver,"parked-start")
	await frames(4)
	check(parked._positions_buffer == (await gpu_data(pair[1].solver,"parked-end"))._positions_buffer,"parked actor has no cloth updates")
	for item in pair:
		item.actor.visible = true
		item.actor.process_mode = Node.PROCESS_MODE_INHERIT
	await time_outputs()
	pair[0].actor.queue_free()
	await frames(4)
	var surviving := await gpu_data(pair[1].solver,"survivor")
	check(not surviving._positions_buffer.is_empty(),"optimized output survives full actor disposal")
	pair[1].actor.queue_free()
	pair.clear()
	await frames(4)
	check((await stats("refs-zero")).buffers == 0,"last actor releases all pooled allocations")
	# The existing full mesh fixture is a different renderer and must still
	# allocate/read normal output without inheriting the grid optimization.
	var fallback := await prepare("non-grid-fallback",true)
	var normal: Node = balls[0]._anim._cloth
	check(not normal.output_positions_only and normal._normals_img_rid.is_valid() and normal._welded_index_lookup_rid.is_valid(),"non-grid keeps complete normal output")
	check(normal._normals_shader.is_valid() and normal._face_normals_buffer.is_valid(),"non-grid keeps normals dispatch")
	report.non_grid_particles = normal._particle_count
	balls[0].queue_free()
	balls.clear()
	await frames(4)
	check((await stats("refs-final")).buffers == 0,"full fallback also releases pooled allocations")
	holder.queue_free()
	CreatureModels.resident_catalog = false
	CreatureModels.clear()
	await frames(2)
	report.checks = checks
	report.failures = failures
	var file := FileAccess.open(out+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("CLOTH POSITION ONLY ",JSON.stringify({"checks":checks,"failures":failures,"saved":saved}))
	quit(1 if failures else 0)
