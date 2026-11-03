extends SceneTree
## Один плащ: точное совпадение CPU/GPU входов и результата cold/memory/disk.
const Solver := preload("res://scenes/resident_cloth_solver.gd")
const Store := preload("res://scenes/loading/preparation_store.gd")
const WindowTest := preload("res://tools/test_window.gd")
var failures := 0
var checks := 0
var balls: Array[CreatureBall] = []
var timings: Array = []
var readbacks: Dictionary = {}

func _initialize() -> void:
	if not has_meta("sfery_background_draw"): WindowTest.background(self)
	call_deferred("run")

func _finalize() -> void:
	WindowTest.finish(self)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for frame in count: await process_frame

func read_gpu(solver: Node, label: String) -> Dictionary:
	var fields := ["_constraints_buffer","_vert_tri_counts_buffer","_vert_tri_offsets_buffer","_vert_tri_list_buffer","_peer_proxy_indices_buffer","_rest_positions_buffer","_bone_indices_buffer","_bone_weights_skin_buffer","_cloth_weights_buffer","_indices_gpu_buffer","_positions_buffer"]
	var buffers: Dictionary = {}
	for field in fields: buffers[field] = solver.get(field)
	RenderingServer.call_on_render_thread(func() -> void:
		var device := RenderingServer.get_rendering_device()
		var result: Dictionary = {}
		for field in buffers:
			var rid: RID = buffers[field]
			result[field] = device.buffer_get_data(rid) if rid.is_valid() else PackedByteArray()
		readbacks[label] = result)
	while not readbacks.has(label): await process_frame
	return readbacks[label]

func physical_parameters(solver: Node) -> Dictionary:
	var result: Dictionary = {}
	for property in solver.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_EDITOR) or not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var value: Variant = solver.get(property.name)
		if typeof(value) in [TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_VECTOR3]:
			result[String(property.name)] = value
	return result

func prepare(label: String, cache: bool) -> Dictionary:
	Solver.canonical_cache_enabled = cache
	var ball := CreatureBall.new()
	root.add_child(ball)
	ball.setup(CardDB.creature(&"creature_ratnik_tide"),balls.size())
	ball.freeze_at(Vector3(0,CreatureBall.RADIUS,0))
	ball.set_process(false)
	ball._anim.set_process(false)
	ball._anim._phase = 0
	ball._anim._clock = 0
	ball._anim.reset()
	if ball._anim._player != null: ball._anim._player.advance(0.0)
	var solver: Node = ball._anim._cloth
	check(solver != null,"real Ratnik cape has its solver")
	solver.set_process(false)
	solver.wind_frequency = 0.0 # Одинаковый момент порыва, без зависимости от времени запуска.
	for frame in 60:
		if solver._gpu_init_done: break
		await process_frame
	check(solver._gpu_init_done,"GPU initialized: "+label)
	check(ball.is_ancestor_of(solver._mesh_instance_node) and ball.is_ancestor_of(solver._skeleton_node),"paths resolve to this actor's own mesh and skeleton")
	ball._figure.visible = true
	solver._process(1.0/60.0) # warm-start из одинаковой зафиксированной позы
	await frames(2)
	for frame in 8:
		solver._process(1.0/60.0)
		await process_frame
	var data := {
		"constraints":solver._constraint_count,
		"groups":solver._constraint_groups.duplicate(true),
		"particles":solver._particle_count,
		"colliders":solver._collider_tris.duplicate(true),
		"proxy":solver._peer_proxy_indices.duplicate(),
		"source_inputs":[solver._src_vertices,solver._src_uvs,solver._src_colors,solver._src_indices,solver._src_bones,solver._src_weights,solver._welded_positions,solver._original_to_welded].duplicate(true),
		"parameters":physical_parameters(solver),
		"gpu":await read_gpu(solver,label),
	}
	timings.append({"stage":label,"cloth_cpu_ms":ball._anim.preparation_ms.cloth,"hits":Solver.canonical_cache_hits.duplicate(),"misses":Solver.canonical_cache_misses.duplicate()})
	ball.visible = false
	ball.process_mode = Node.PROCESS_MODE_DISABLED
	balls.append(ball)
	return data

func check_memory_data(solver: Node, baseline: Dictionary) -> void:
	var extracted: Dictionary = solver._prepare_mesh_data(solver._mesh_instance_node.mesh)
	check(extracted.vertices == baseline.source_inputs[0] and extracted.indices == baseline.source_inputs[3],"memory ingestion matches original single-surface cape")
	check(extracted.bones == baseline.source_inputs[4] and extracted.weights == baseline.source_inputs[5],"memory ingestion preserves bone weights")
	var welded: Dictionary = solver._prepare_weld(solver._src_vertices,solver.weld_epsilon)
	check(welded.welded_positions == baseline.source_inputs[6] and welded.original_to_welded == baseline.source_inputs[7],"memory weld preserves exact points and index mapping")
	var transform: Transform3D = solver._ref_node.global_transform.affine_inverse()*solver._mesh_instance_node.global_transform
	var constraints: PackedFloat32Array = solver._build_mesh_constraints(transform)
	check(constraints.to_byte_array() == baseline.gpu._constraints_buffer,"memory constraints exactly match uploaded cold bytes")
	check(solver._constraint_groups == baseline.groups,"memory restores the same constraint groups")
	solver._build_collider_mesh()
	check(solver._collider_tris == baseline.colliders,"memory restores same collider triangles")
	var adjacency: Dictionary = solver._build_adjacency()
	check(adjacency.counts.to_byte_array() == baseline.gpu._vert_tri_counts_buffer,"memory adjacency counts match GPU")
	check(adjacency.offsets.to_byte_array() == baseline.gpu._vert_tri_offsets_buffer,"memory adjacency offsets match GPU")
	check(adjacency.list.to_byte_array() == baseline.gpu._vert_tri_list_buffer,"memory adjacency list matches GPU")
	check(solver._build_peer_proxy_indices() == baseline.proxy,"memory peer proxy matches cold")
	var key: String = solver._cache_key("cloth-constraints",[transform,solver.stiffness,solver.bend_stiffness,solver.bending_from_topology])
	check(key != solver._cache_key("cloth-constraints",[transform,solver.stiffness*.9,solver.bend_stiffness,solver.bending_from_topology]),"different stiffness invalidates derived constraints")

func run() -> void:
	check(RenderingServer.get_rendering_device() != null,"GPU test requires Vulkan")
	if failures:
		quit(1)
		return
	Engine.max_fps = 60
	CreatureModels.resident_catalog = true
	var previous_directory: String = Store.cache_directory
	Store.cache_directory = "res://build/checks/cloth-preparation-cache/data-%d" % int(Time.get_unix_time_from_system()*1000)
	Store.clear()
	Solver.clear_canonical_cache()
	# Builder-режим разрешён только этому тесту, как и штатному offline-генератору.
	Store.writing_enabled = true
	var baseline := await prepare("cold-generated",true)
	check(Solver.canonical_cache_hits.is_empty(),"fresh fixture computes all CPU structures through original code")
	Store.writing_enabled = false
	check_memory_data(balls[0]._anim._cloth,baseline)
	Solver.clear_canonical_cache()
	Store.clear()
	var disk := await prepare("disk",true)
	for item in [disk]:
		check(item.constraints == baseline.constraints and item.groups == baseline.groups,"constraint count/group order unchanged")
		check(item.particles == baseline.particles,"welded particle count unchanged")
		check(item.colliders == baseline.colliders,"same body collider triangles/bones/local offsets")
		check(item.proxy == baseline.proxy,"same peer proxy indices")
		check(item.source_inputs == baseline.source_inputs,"same ingestion/filter/weld arrays")
		check(item.parameters == baseline.parameters,"runtime physical parameters unchanged")
		for field in baseline.gpu:
			check(item.gpu[field] == baseline.gpu[field],"same uploaded data and deterministic simulated positions: "+field)
	var rids: Dictionary = {}
	var materials: Dictionary = {}
	for ball in balls:
		var solver: Node = ball._anim._cloth
		check(not rids.has(solver._positions_buffer),"each actor owns independent mutable GPU positions")
		check(not materials.has(solver._surf_mat.get_instance_id()),"each actor owns its own live cloth material")
		rids[solver._positions_buffer] = true
		materials[solver._surf_mat.get_instance_id()] = true
		ball.queue_free()
	balls.clear()
	readbacks.clear()
	await frames(4)
	CreatureModels.resident_catalog = false
	CreatureModels.clear()
	Store.clear()
	Solver.clear_canonical_cache()
	Store.cache_directory = previous_directory
	await frames(2)
	print("CLOTH PREPARATION CACHE ",JSON.stringify({"checks":checks,"failures":failures,"timings":timings}))
	quit(1 if failures else 0)
