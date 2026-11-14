extends SceneTree
## Reproducible resident catalogue measurement; source GLB and graphics quality stay intact.
var failures := 0
var checks := 0
var out_dir := "user://memory-catalog"
var phase := "current"
var texture_slots: Dictionary = {}
var seen_resources: Dictionary = {}
var source_materials: Array[BaseMaterial3D] = []
var texture_ids: Dictionary = {}
var library_ids: Dictionary = {}
var animation_ids: Dictionary = {}
var unique_keys := 0
var fingerprints: Dictionary = {}
var sample_poses: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func walk(value: Variant) -> void:
	if value is Resource:
		var id: int = value.get_instance_id()
		if seen_resources.has(id): return
		seen_resources[id] = true
		if value is BaseMaterial3D:
			source_materials.append(value)
			for property in value.get_property_list():
				if property.type == TYPE_OBJECT:
					var texture = value.get(property.name)
					if texture is Texture2D:
						texture_slots[property.name] = int(texture_slots.get(property.name, 0)) + 1
						texture_ids[texture.get_instance_id()] = true
		if value is PackedScene:
			var state: SceneState = value.get_state()
			for index in state.get_node_count():
				for property in state.get_node_property_count(index): walk(state.get_node_property_value(index, property))
		if value is Mesh:
			for index in value.get_surface_count(): walk(value.surface_get_material(index))
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.type in [TYPE_OBJECT, TYPE_ARRAY, TYPE_DICTIONARY]: walk(value.get(property.name))
	elif value is Array:
		for child in value: walk(child)
	elif value is Dictionary:
		for child in value.values(): walk(child)

func animation_fingerprint(player: AnimationPlayer) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	for name in player.get_animation_library_list():
		var library := player.get_animation_library(name)
		library_ids[library.get_instance_id()] = true
		for clip in library.get_animation_list():
			var animation := library.get_animation(clip)
			var fresh := not animation_ids.has(animation.get_instance_id())
			animation_ids[animation.get_instance_id()] = true
			hash.update(var_to_bytes([name, clip, animation.length, animation.loop_mode]))
			for track in animation.get_track_count():
				hash.update(var_to_bytes([animation.track_get_type(track), animation.track_get_path(track), animation.track_get_interpolation_type(track), animation.track_get_interpolation_loop_wrap(track)]))
				if fresh: unique_keys += animation.track_get_key_count(track)
				for key in animation.track_get_key_count(track):
					hash.update(var_to_bytes([animation.track_get_key_time(track, key), animation.track_get_key_value(track, key), animation.track_get_key_transition(track, key)]))
	return hash.finish().hex_encode()

func skeleton_of(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var skeleton := skeleton_of(child)
		if skeleton != null: return skeleton
	return null

func pose(skeleton: Skeleton3D) -> Array:
	var result: Array = []
	for bone in skeleton.get_bone_count(): result.append(str(skeleton.get_bone_pose(bone)))
	return result

func memory() -> Dictionary:
	var rss := "unavailable"
	if OS.get_name() == "Linux":
		# procfs reports size zero: read through cat instead of get_as_text().
		var process_status: Array = []
		OS.execute("/usr/bin/cat", ["/proc/" + str(OS.get_process_id()) + "/status"], process_status)
		for text in process_status:
			for line in String(text).split("\n"):
				if line.begins_with("VmRSS:"): rss = line.trim_prefix("VmRSS:").strip_edges()
	return {"rss":rss, "static_bytes":OS.get_static_memory_usage(),
		"texture_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"buffer_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
		"video_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"objects":Performance.get_monitor(Performance.OBJECT_COUNT), "resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)}

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir = args[0]
	phase = OS.get_environment("SFERY_MEMORY_PHASE")
	if phase.is_empty(): phase = "current"
	DirAccess.make_dir_recursive_absolute(out_dir)
	seed(20261104)
	var loader := GameLoading.i()
	var before := memory()
	var start := Time.get_ticks_usec()
	await loader.prepare()
	var startup_ms := (Time.get_ticks_usec() - start) / 1000.0
	loader._game.team_menu._preview.release()
	await process_frame
	var loaded := memory()
	var catalog := CreatureModels.catalog_defs()
	check(loader.ready_to_play and loader.actor_build_count == catalog.size() * 2 and loader.arena_build_count == 3, "two copies of every definition and three arenas before menu")
	for source in CreatureModels._scenes.values(): walk(source)
	var original_counts := [loader.actor_build_count, loader.arena_build_count, loader.preparation_count]
	var activation: Array[float] = []
	for d in catalog:
		var first: CreatureBall = loader._balls[d.id][0]
		var second: CreatureBall = loader._balls[d.id][1]
		var a := first._anim._player
		var b := second._anim._player
		check(a != null and b != null and a != b, "separate players " + String(d.id))
		var left := animation_fingerprint(a)
		var right := animation_fingerprint(b)
		check(left == right, "same prepared animation contents " + String(d.id))
		fingerprints[d.id] = left
		var skeleton := skeleton_of(first._anim)
		var other := skeleton_of(second._anim)
		skeleton.reset_bone_poses()
		a.stop()
		a.play(&"idle", 0.0)
		a.advance(0.0)
		a.seek(a.get_animation(&"idle").length * .37, true)
		var snapshot := pose(skeleton)
		other.reset_bone_poses()
		b.stop()
		b.play(&"attack", 0.0)
		b.advance(0.0)
		b.seek(b.get_animation(&"attack").length * .63, true)
		check(snapshot == pose(skeleton), "second player cannot change first pose " + String(d.id))
		sample_poses[d.id] = snapshot
		var began := Time.get_ticks_usec()
		var ball := loader.take_ball(d.id, 1001, Vector3(0, CreatureBall.RADIUS, 0))
		activation.append((Time.get_ticks_usec()-began)/1000.0)
		loader.return_ball(ball)
	check(original_counts == [loader.actor_build_count, loader.arena_build_count, loader.preparation_count], "no setup/load after menu on full catalogue checkout/return")
	# Same dormant catalogue, 60 FPS background rendering, 90 settled samples.
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var process_ms := 0.0
	var cpu_ms := 0.0
	var gpu_ms := 0.0
	for frame in 180:
		await process_frame
		if frame < 90: continue
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	var result := {"measurement_schema":2,"phase":phase,"checks":checks,"failures":failures,"fps_cap":Engine.max_fps,
		"startup_ms":startup_ms,"before":before,"loaded":loaded,"settled":memory(),
		"preparation_store":PreparationStore.statistics(),"actors":loader.actor_build_count,"arenas":loader.arena_build_count,"source_materials":source_materials.size(),
		"source_texture_slots":texture_slots,"unique_source_textures":texture_ids.size(),
		"prepared_libraries":library_ids.size(),"prepared_animations":animation_ids.size(),"prepared_unique_keys":unique_keys,
		"animation_sha256":fingerprints,"sample_poses":sample_poses,"checkout_ms":activation,
		"dormant_process_ms":process_ms/90,"dormant_render_cpu_ms":cpu_ms/90,"dormant_render_gpu_ms":gpu_ms/90}
	if phase in ["after", "current"]:
		var gpu_shared: Dictionary = {}
		RenderingServer.call_on_render_thread(func() -> void:
			var solver_script: GDScript = load("res://scenes/resident_cloth_solver.gd")
			gpu_shared.merge(solver_script.call("shared_gpu_stats")))
		while not gpu_shared.has("buffers"): await process_frame
		result.shared_cloth = gpu_shared
		var baseline_path := out_dir.path_join("baseline.json")
		if phase == "after": check(FileAccess.file_exists(baseline_path), "baseline exists for exact curve/pose comparison")
		if FileAccess.file_exists(baseline_path):
			var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
			for id in baseline.animation_sha256:
				check(baseline.animation_sha256[id] == fingerprints.get(id), "dense curves match baseline " + id)
			for id in baseline.sample_poses:
				check(baseline.sample_poses[id] == sample_poses.get(id), "skeleton poses match baseline " + id)
		check(library_ids.size() == catalog.size() and animation_ids.size() == catalog.size() * 5, "one immutable library and five animations per source")
		check(texture_slots == {"albedo_texture":85}, "only albedo texture slots remain in all HD source scenes")
		var model_script: GDScript = load("res://scenes/creature_models.gd")
		var animation_cache: Dictionary = model_script.get("animation_library_cache")
		check(animation_cache.size() == catalog.size(), "bounded catalogue animation cache has no actor entries")
		result.checks = checks
		result.failures = failures
	var path := out_dir.path_join(phase + ".json")
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"  "))
	output.close()
	print("MEMORY_CATALOG ", phase, " checks=",checks," failures=",failures," startup_ms=",startup_ms," libraries=",library_ids.size()," animations=",animation_ids.size()," keys=",unique_keys," source_textures=",texture_ids.size()," memory=",loaded)
	loader.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await process_frame
	quit(1 if failures else 0)
