extends SceneTree
## Exact shadow-only batching probe. Normal color batches and settings stay intact.
var out := "res://build/checks/presentation/menu-shadows"
class AuditCity extends MenuCity:
	var inputs: Dictionary = {}
	func _make_mm(mesh: Mesh, items: Array, mat: Material, custom: bool, shadows: bool) -> MultiMeshInstance3D:
		var result := super._make_mm(mesh,items,mat,custom,shadows)
		inputs[result.multimesh] = items.duplicate()
		return result
var city: AuditCity
var checks := 0
var failures := 0
var report: Dictionary = {"proof": [], "captures": [], "sources": {}}
var visual := false
var close_only := false
var source_buffers: Dictionary = {}
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await process_frame
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)
func records(mm: MultiMesh) -> Array:
	var result: Array = []
	for i in mm.instance_count:
		var item: Array = city.inputs[mm][i] if DisplayServer.get_name() == "headless" else [mm.get_instance_transform(i), mm.get_instance_custom_data(i) if mm.use_custom_data else mm.get_instance_color(i)]
		result.append(var_to_bytes(item).hex_encode())
	result.sort()
	return result
func verify_geometry() -> void:
	for entry in city._shadow_sets:
		var source: MultiMeshInstance3D = entry.source
		var mm := source.multimesh
		var original := records(mm)
		var copies: Array = []
		for batch: MultiMeshInstance3D in entry.batches:
			check(batch.multimesh.mesh == mm.mesh and batch.material_override == source.material_override,"exact mesh/material identity")
			check(batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and batch.gi_mode == GeometryInstance3D.GI_MODE_DISABLED,"shadow-only no duplicate GI")
			check(batch.multimesh.use_custom_data == mm.use_custom_data and batch.multimesh.use_colors == mm.use_colors,"same per-instance format")
			check(batch.transform == source.transform,"same parent transform")
			copies.append_array(records(batch.multimesh))
		copies.sort()
		check(original == copies,"exact transform/color/custom multiset")
		check(source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"source remains color-only")
		report.proof.append({"source":str(source.get_path()),"instances":mm.instance_count,"batches":entry.batches.size(),"tree":entry.tree,"before_sha256":JSON.stringify(original).sha256_text(),"after_sha256":JSON.stringify(copies).sha256_text(),"color_buffer_sha256":mm.buffer.to_byte_array().hex_encode().sha256_text(),"mesh_id":mm.mesh.get_instance_id(),"material_id":source.material_override.get_instance_id()})
	check(city._shadow_sets.size() > 0,"production creates shadow partitions")
func toggle(enabled: bool) -> void:
	for entry in city._shadow_sets:
		entry.source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for batch: MultiMeshInstance3D in entry.batches: batch.visible = enabled
func effective() -> Dictionary:
	var result := {"phase":city.phase,"anim_t":city.anim_t,"level":GraphicsSettings.current(),"options":GraphicsSettings.custom_options.duplicate(),"size":str(root.size),"scale":root.scaling_3d_scale,"msaa":root.msaa_3d,"camera":str(city.cam.transform),"fov":city.cam.fov}
	for name in ["shadow_enabled","shadow_blur","shadow_bias","shadow_normal_bias","light_angular_distance","directional_shadow_mode","directional_shadow_max_distance","directional_shadow_blend_splits","directional_shadow_split_1","directional_shadow_split_2","directional_shadow_split_3","transform","light_energy","light_color"]: result[name] = str(city.sun.get(name))
	for name in ["shadow_size","shadow_filter","splits","shadow_dist"]: result[name] = GraphicsSettings.param(name)
	return result
func mark(label: String) -> void:
	if EngineDebugger.is_active(): EngineDebugger.send_message("orbstrike:mark",[label])
	print("MENU_SHADOW_MARK ",label)
func capture(label: String, enabled: bool) -> void:
	toggle(enabled)
	await frames(20)
	mark(label+"-begin")
	var samples: Array = []
	for i in 60:
		await process_frame
		samples.append({"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
	mark(label+"-end")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(out.path_join(label+".png")) == OK,"saved "+label)
	report.captures.append({"label":label,"samples":samples,"effective":effective(),"pixels_sha256":image.get_data().hex_encode().sha256_text()})
func visible_buffers() -> Dictionary:
	var result: Dictionary = {}
	var copies: Array = []
	for entry in city._shadow_sets: copies.append_array(entry.batches)
	for node in city.get_children():
		if not node is MultiMeshInstance3D or node in copies: continue
		var mm: MultiMesh = node.multimesh
		result[str(node.get_path())] = {"multimesh_id":mm.get_instance_id(),"mesh_id":mm.mesh.get_instance_id(),"material_id":node.material_override.get_instance_id(),"type":type_string(typeof(mm.buffer)),"floats":mm.buffer.size(),"bytes":mm.buffer.to_byte_array().size(),"sha256":mm.buffer.to_byte_array().hex_encode().sha256_text(),"instances":mm.instance_count,"custom":mm.use_custom_data,"colors":mm.use_colors}
	return result
func tree_close() -> void:
	var target := Vector3(-60,0,200)
	var nearest := Transform3D.IDENTITY
	var distance := INF
	for entry in city._shadow_sets:
		for item: Array in city.inputs[entry.source.multimesh]:
			var transform: Transform3D = item[0]
			var d := Vector2(transform.origin.x-target.x,transform.origin.z-target.z).length_squared()
			if d < distance:
				distance = d
				nearest = transform
	report.close_tree_transform = str(nearest)
	for wind in [0.0,1.31,3.2]:
		city.anim_t = wind
		city.phase = .66
		city._update(0.0)
		target = nearest.origin + Vector3.UP * nearest.basis.y.length() * .4
		city.cam.look_at_from_position(target+Vector3(28,18,32),target)
		await capture("tree-close-%.2f-original" % wind,false)
		await capture("tree-close-%.2f-partition" % wind,true)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	close_only = OS.get_environment("ORBSTRIKE_MENU_SHADOWS_TREE_CLOSE_ONLY") == "1"
	if close_only: out = out.path_join("tree-close")
	DirAccess.make_dir_recursive_absolute(out)
	GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
	GraphicsSettings.custom_options["vsync"] = false
	GraphicsSettings.custom_options["render_scale"] = 1.0
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	city = AuditCity.new()
	root.add_child(city)
	await frames(2)
	city.paused = true
	city.set_process(false)
	city.anim_t = 10.0
	city._parallax = Vector2.ZERO
	city._update(0.0)
	verify_geometry()
	source_buffers = visible_buffers()
	report.source_buffers_before = source_buffers
	var ids: Array = []
	for entry in city._shadow_sets:
		for batch: MultiMeshInstance3D in entry.batches: ids.append(batch.get_instance_id())
	GraphicsSettings.force_level(GraphicsSettings.Level.LOW)
	city.apply_quality(GraphicsSettings.Level.LOW)
	for entry in city._shadow_sets:
		check(entry.batches.all(func(n):return not n.visible),"LOW hides shadow-only batches")
	GraphicsSettings.custom_options["shadow_quality"] = 3
	city.apply_quality(GraphicsSettings.Level.LOW)
	for entry in city._shadow_sets:
		check(entry.batches.all(func(n):return n.visible == (not entry.tree)),"HIGH shadows plus LOW detail keeps old tree policy")
	GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
	city.apply_quality(GraphicsSettings.Level.HIGH)
	GraphicsSettings.custom_options["shadow_quality"] = 0
	city.apply_quality(GraphicsSettings.Level.HIGH)
	for entry in city._shadow_sets:
		check(entry.batches.all(func(n):return not n.visible),"runtime shadows OFF hides copies")
	GraphicsSettings.custom_options.erase("shadow_quality")
	city.apply_quality(GraphicsSettings.Level.HIGH)
	var now_ids: Array = []
	for entry in city._shadow_sets:
		check(entry.batches.all(func(n):return n.visible),"HIGH restores copies")
		for batch: MultiMeshInstance3D in entry.batches: now_ids.append(batch.get_instance_id())
	check(ids == now_ids,"quality changes reuse batches")
	visual = DisplayServer.get_name() != "headless"
	if visual:
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		await frames(90)
		mark("visual-enable")
		if close_only:
			await tree_close()
		for phase in ([] if close_only else [.33,.50,.66,.752,.0]):
			city.phase = phase
			city._update(0.0)
			var label := "overview-%.3f" % phase
			await capture(label+"-original",false)
			await capture(label+"-partition",true)
		if not close_only:
			city.phase = .66
			city._update(0.0)
			# Same receiving roofs at a closer fixed camera.
			city.cam.look_at_from_position(Vector3(-60,62,155),Vector3(0,14,-90))
			await capture("near-original",false)
			await capture("near-partition",true)
		mark("visual-disable")
		check(Engine.max_fps == 60 and root.unfocusable and root.mode == Window.MODE_MINIMIZED,"safe offscreen 60FPS")
	report.source_buffers_after = visible_buffers()
	check(source_buffers == report.source_buffers_after,"all visible source mesh/material identities and buffers remain exact")
	if visual:
		for path in source_buffers:
			var buffer: Dictionary = source_buffers[path]
			check(buffer.type == "PackedFloat32Array" and buffer.floats == buffer.instances*16 and buffer.bytes == buffer.floats*4,"actual visible GPU-side instance buffer length/type")
	for path in ["scenes/menu/menu_city.gd","tools/test_menu_shadows.gd","tools/check.py","tools/test_window.gd","scenes/graphics_settings.gd","scenes/menu/tree.gdshader","scenes/menu/building.gdshader"]: report.sources[path] = FileAccess.get_sha256("res://"+path)
	report.checks = checks
	report.failures = failures
	report.visual = visual
	FileAccess.open(out.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	city.queue_free()
	await frames(3)
	print("MENU SHADOWS ",checks,"/",failures)
	quit(1 if failures else 0)
