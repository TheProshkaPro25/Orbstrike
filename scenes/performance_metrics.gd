extends RefCounted
## Small built-in diagnostic counters; no overlay, external addon or frame polling.
const COUNTERS := ["hover_queries", "hover_cache_hits", "hover_snapshots", "hover_rebuilds", "hover_rebuild_usec", "portrait_camera_updates", "portrait_refreshes", "preview_card_builds", "preview_card_reuses"]
static var counters: Dictionary = {}
static var _installed := false

static func install() -> void:
	if _installed: return
	_installed = true
	for key in COUNTERS:
		var id := StringName("orbstrike/" + key)
		if not Performance.has_custom_monitor(id):
			Performance.add_custom_monitor(id, value.bind(key))

static func add(key: String, amount: int = 1) -> void:
	counters[key] = int(counters.get(key, 0)) + amount

static func value(key: String) -> int:
	return int(counters.get(key, 0))

static func snapshot(viewport: Viewport = null) -> Dictionary:
	var result := {"counters": counters.duplicate(), "engine": {}, "render_timing_enabled": false}
	for name in ClassDB.class_get_enum_constants("Performance", "Monitor"):
		if name.begins_with("PIPELINE_COMPILATIONS_") or name in ["TIME_PROCESS", "TIME_PHYSICS_PROCESS", "RENDER_TOTAL_DRAW_CALLS_IN_FRAME", "RENDER_TOTAL_PRIMITIVES_IN_FRAME", "RENDER_VIDEO_MEM_USED", "RENDER_TEXTURE_MEM_USED", "OBJECT_COUNT", "OBJECT_RESOURCE_COUNT", "OBJECT_NODE_COUNT", "OBJECT_ORPHAN_NODE_COUNT"]:
			result.engine[name] = Performance.get_monitor(ClassDB.class_get_integer_constant("Performance", name))
	# Explicit opt-in: timing queries themselves are not free on every device.
	if viewport != null and viewport.has_meta("orbstrike_measure_render_time"):
		var rid := viewport.get_viewport_rid()
		result.render_timing_enabled = true
		result.render_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(rid)
		result.render_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return result

static func measure_render_time(viewport: Viewport, enabled: bool) -> void:
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), enabled)
	if enabled: viewport.set_meta("orbstrike_measure_render_time", true)
	else: viewport.remove_meta("orbstrike_measure_render_time")
