class_name DeviceMotion
extends Control
## Finite light passes inside one existing UI region. No assets, input or layout changes.
## A Node2D host preserves canvas transforms and is ignored by Container layout.

const DURATIONS := {"boot": 0.56, "scan": 0.62, "power": 0.52, "activation": 0.62, "turn": 0.55}
const REGISTRY := "orbstrike_device_motion"

var kind := "scan"
var color := UiTheme.DEVICE_ACCENT
var direction := 1.0
var progress := 0.0
var duration := 0.62
var delay := 0.0
var motion_tween: Tween
var _target: Control
var _host: Node
var _stopped := false
var _revealing := false
var reveal_offset := Vector2(36,0)
var render_offset := Vector2.ZERO
var render_alpha := 1.0


static func play_on(target: Control, effect_kind: String, effect_color: Color = UiTheme.DEVICE_ACCENT, start_delay: float = 0.0) -> Control:
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.is_visible_in_tree(): return null
	if DeviceSettings.reduce_motion(): return null
	if not DURATIONS.has(effect_kind) or target.size.x < 2.0 or target.size.y < 2.0: return null
	var registry: Dictionary = target.get_meta(REGISTRY, {})
	var previous: WeakRef = registry.get(effect_kind)
	if previous != null and is_instance_valid(previous.get_ref()):
		previous.get_ref().call("stop")
	# Dynamic self-load is already cached and also works before a new class-name import.
	var overlay: Control = load("res://scenes/ui/device_motion.gd").new()
	overlay.name = "DeviceMotion_" + effect_kind
	overlay.set("kind",effect_kind)
	overlay.set("color",effect_color)
	overlay.set("duration",float(DURATIONS[effect_kind]))
	overlay.set("delay",clampf(start_delay,0.0,0.28))
	overlay.set("_target",target)
	var host := Node2D.new()
	host.name = "DeviceMotionHost_" + effect_kind
	overlay.set("_host",host)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.focus_mode = Control.FOCUS_NONE
	overlay.position = Vector2.ZERO
	overlay.size = target.size
	overlay.z_index = 120
	target.add_child(host)
	# Re-read: stopping the prior overlay may have removed its registry entry.
	registry = target.get_meta(REGISTRY,{})
	registry[effect_kind] = weakref(overlay)
	target.set_meta(REGISTRY,registry)
	host.add_child(overlay)
	return overlay


## Render-only movement: Control geometry and hit testing retain their final layout.
static func reveal_on(target: Control, start_delay: float = 0.0, slide: Vector2 = Vector2(36,0), effect_kind: String = "boot") -> Control:
	if is_instance_valid(target):
		var registry: Dictionary = target.get_meta(REGISTRY,{})
		for reference: WeakRef in registry.values():
			if reference != null and is_instance_valid(reference.get_ref()) and bool(reference.get_ref().get("_revealing")):
				reference.get_ref().call("stop")
	var overlay := play_on(target,effect_kind,UiTheme.DEVICE_ACCENT,start_delay)
	if overlay != null: overlay.call("enable_reveal",slide)
	return overlay


static func watch_tree(root: Control, enabled: bool = true) -> Node:
	var existing := root.get_node_or_null("DeviceRevealWatcher")
	if existing != null:
		if enabled: existing.call("start")
		return existing
	var watcher := RevealWatcher.new()
	watcher.name = "DeviceRevealWatcher"
	watcher.root = root
	watcher.enabled = enabled
	root.add_child(watcher)
	return watcher


class RevealWatcher extends Node:
	var root: Control
	var enabled := false
	var _targets: Dictionary = {}
	var _pending: Dictionary = {}
	var _timer: Timer
	var _scan_queued := false

	func _enter_tree() -> void:
		if not get_tree().node_added.is_connected(_added): get_tree().node_added.connect(_added)
		if not DeviceSettings.events().motion_changed.is_connected(_motion): DeviceSettings.events().motion_changed.connect(_motion)
		_scan.call_deferred()
		if enabled: start.call_deferred()

	func _ready() -> void:
		_timer = Timer.new()
		_timer.one_shot = true
		_timer.wait_time = .045
		_timer.ignore_time_scale = true
		_timer.timeout.connect(_flush)
		add_child(_timer)

	func _exit_tree() -> void:
		_settle()
		if get_tree().node_added.is_connected(_added): get_tree().node_added.disconnect(_added)
		if DeviceSettings.events().motion_changed.is_connected(_motion): DeviceSettings.events().motion_changed.disconnect(_motion)

	func _added(node: Node) -> void:
		if root.is_ancestor_of(node) and not String(node.name).begins_with("DeviceMotion") and not _scan_queued:
			_scan_queued = true
			_scan.call_deferred()

	func _scan() -> void:
		_scan_queued = false
		if not is_inside_tree(): return
		_collect(root)

	func _collect(node: Node) -> void:
		if node == self or node is OpponentPanel or node.name == "DeviceFrame" or String(node.name).begins_with("DeviceMotion"): return
		if node is Control and (node is BaseButton or node is PanelContainer or node is Label or bool(node.get_meta("device_reveal_region",false))):
			_register(node)
			return
		for child in node.get_children(): _collect(child)

	func _register(target: Control) -> void:
		var id := target.get_instance_id()
		if _targets.has(id): return
		var reference: WeakRef = weakref(target)
		_targets[id] = {"ref":reference,"shown":false}
		target.visibility_changed.connect(_visibility.bind(id))
		target.item_rect_changed.connect(_rect_changed.bind(id))
		target.tree_exiting.connect(_removed.bind(id))
		_visibility(id)

	func _visibility(id: int) -> void:
		if not _targets.has(id): return
		var target: Control = _targets[id].ref.get_ref()
		if not is_instance_valid(target): return
		var shown := target.is_visible_in_tree()
		var previous: bool = _targets[id].shown
		_targets[id].shown = shown
		if not shown:
			_pending.erase(id)
			_motion_script().call("stop_on",target)
		elif not previous and enabled:
			_pending[id] = _targets[id].ref
			_timer.start()

	func _rect_changed(id: int) -> void:
		if _pending.has(id) and enabled: _timer.start()

	func _removed(id: int) -> void:
		if _targets.has(id):
			var target: Control = _targets[id].ref.get_ref()
			if is_instance_valid(target):
				if target.visibility_changed.is_connected(_visibility.bind(id)): target.visibility_changed.disconnect(_visibility.bind(id))
				if target.item_rect_changed.is_connected(_rect_changed.bind(id)): target.item_rect_changed.disconnect(_rect_changed.bind(id))
				if target.tree_exiting.is_connected(_removed.bind(id)): target.tree_exiting.disconnect(_removed.bind(id))
		_targets.erase(id)
		_pending.erase(id)

	func request(target: Control) -> void:
		_register(target)
		if enabled and target.is_visible_in_tree():
			_pending[target.get_instance_id()] = weakref(target)
			_timer.start()

	func start() -> void:
		enabled = true
		_scan()
		for id in _targets:
			var target: Control = _targets[id].ref.get_ref()
			if is_instance_valid(target) and target.is_visible_in_tree(): _pending[id] = _targets[id].ref
		if not _pending.is_empty(): _timer.start()

	func _flush() -> void:
		if not enabled or DeviceSettings.reduce_motion():
			_pending.clear()
			return
		var pending := _pending.duplicate()
		_pending.clear()
		var stage := 0
		for id in pending:
			var target: Control = pending[id].get_ref()
			if not is_instance_valid(target) or not target.is_visible_in_tree(): continue
			if target.size.x < 2 or target.size.y < 2:
				_pending[id] = pending[id]
				continue
			var slide := Vector2(-36 if target.get_global_rect().get_center().x < root.get_viewport_rect().size.x*.5 else 36,16)
			_motion_script().call("reveal_on",target,float(stage%6)*.045,slide)
			stage += 1

	func _settle() -> void:
		if _timer != null: _timer.stop()
		_pending.clear()
		for entry: Dictionary in _targets.values():
			var target: Control = entry.ref.get_ref()
			if is_instance_valid(target): _motion_script().call("stop_on",target)

	func _motion(_value: bool) -> void:
		_settle()

	func _motion_script() -> Script:
		return load("res://scenes/ui/device_motion.gd")


static func stop_on(target: Control, effect_kind: String = "") -> void:
	if not is_instance_valid(target): return
	var registry: Dictionary = target.get_meta(REGISTRY,{})
	for key in registry.keys():
		if not effect_kind.is_empty() and key != effect_kind: continue
		var reference: WeakRef = registry[key]
		if reference != null and is_instance_valid(reference.get_ref()):
			reference.get_ref().call("stop")


func _ready() -> void:
	_target.visibility_changed.connect(_visibility_changed)
	_target.tree_exiting.connect(stop)
	_target.resized.connect(stop)
	visibility_changed.connect(_visibility_changed)
	DeviceSettings.events().motion_changed.connect(_motion_changed)
	motion_tween = create_tween().set_ignore_time_scale(true)
	if delay > 0.0: motion_tween.tween_interval(delay)
	motion_tween.tween_method(_advance,0.0,1.0,duration).set_trans(Tween.TRANS_LINEAR)
	motion_tween.tween_callback(stop)


func _advance(value: float) -> void:
	if _stopped: return
	if not is_instance_valid(_target) or not _target.is_visible_in_tree():
		stop()
		return
	progress = value
	if _revealing: _apply_reveal(value)
	queue_redraw()


func enable_reveal(slide: Vector2) -> void:
	_revealing = true
	reveal_offset = slide
	if not _target.item_rect_changed.is_connected(stop): _target.item_rect_changed.connect(stop)
	_apply_reveal(progress)


func _apply_reveal(value: float) -> void:
	var eased := 1.0-pow(1.0-value,3.0)
	render_offset = reveal_offset*(1.0-eased)
	render_alpha = lerpf(.12,1.0,eased)
	var transform := _target.get_transform()*Transform2D(0.0,render_offset)
	RenderingServer.canvas_item_set_transform(_target.get_canvas_item(),transform)
	var tint := _target.modulate
	tint.a *= render_alpha
	RenderingServer.canvas_item_set_modulate(_target.get_canvas_item(),tint)


func _restore_reveal() -> void:
	if not _revealing or not is_instance_valid(_target): return
	render_offset = Vector2.ZERO
	render_alpha = 1.0
	# Always restore the live Control transform, never an origin captured before layout.
	RenderingServer.canvas_item_set_transform(_target.get_canvas_item(),_target.get_transform())
	RenderingServer.canvas_item_set_modulate(_target.get_canvas_item(),_target.modulate)
	_target.queue_redraw()
	_revealing = false


func _visibility_changed() -> void:
	if not _stopped and (not is_visible_in_tree() or not _target.is_visible_in_tree()): stop()


func _motion_changed(reduced: bool) -> void:
	if reduced: stop()


func stop() -> void:
	if _stopped: return
	_stopped = true
	_restore_reveal()
	if motion_tween != null and motion_tween.is_valid(): motion_tween.kill()
	motion_tween = null
	visible = false
	_unregister()
	if is_instance_valid(_host) and not _host.is_queued_for_deletion(): _host.queue_free()


func _unregister() -> void:
	if not is_instance_valid(_target): return
	var registry: Dictionary = _target.get_meta(REGISTRY,{})
	var reference: WeakRef = registry.get(kind)
	if reference != null and reference.get_ref() == self: registry.erase(kind)
	if registry.is_empty():
		if _target.has_meta(REGISTRY): _target.remove_meta(REGISTRY)
	else: _target.set_meta(REGISTRY,registry)


func _exit_tree() -> void:
	_restore_reveal()
	if motion_tween != null and motion_tween.is_valid(): motion_tween.kill()
	motion_tween = null
	_unregister()
	if DeviceSettings.events().motion_changed.is_connected(_motion_changed): DeviceSettings.events().motion_changed.disconnect(_motion_changed)
	if is_instance_valid(_target):
		if _target.visibility_changed.is_connected(_visibility_changed): _target.visibility_changed.disconnect(_visibility_changed)
		if _target.tree_exiting.is_connected(stop): _target.tree_exiting.disconnect(stop)
		if _target.resized.is_connected(stop): _target.resized.disconnect(stop)
		if _target.item_rect_changed.is_connected(stop): _target.item_rect_changed.disconnect(stop)


func _polygon(points: PackedVector2Array, tint: Color) -> void:
	var bounds := PackedVector2Array([Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)])
	for clipped in Geometry2D.intersect_polygons(points,bounds):
		if clipped.size() >= 3 and Geometry2D.triangulate_polygon(clipped).size() >= 3:
			draw_colored_polygon(clipped,tint)


func _band(center: float, width: float, tint: Color, slant: float = 0.16) -> void:
	var skew := size.y*slant
	_polygon(PackedVector2Array([Vector2(center-width*.5+skew,0),Vector2(center+width*.5+skew,0),Vector2(center+width*.5-skew,size.y),Vector2(center-width*.5-skew,size.y)]),tint)


func _safe_rect(rect: Rect2, tint: Color) -> void:
	var clipped := rect.intersection(Rect2(Vector2.ZERO,size))
	if clipped.has_area(): draw_rect(clipped,tint)


func _draw() -> void:
	if _stopped or progress <= 0.0 or progress >= 1.0: return
	var envelope := minf(1.0,progress*10.0)*minf(1.0,(1.0-progress)*7.0)
	var travel := progress if direction >= 0.0 else 1.0-progress
	var front := lerpf(-size.y*.2-30.0,size.x+size.y*.2+30.0,travel)
	var tail_sign := -1.0 if direction >= 0.0 else 1.0
	var white := Color(0.92,1.0,1.0,0.90*envelope)
	match kind:
		"power":
			# The counter is the focal content: charge only its perimeter, never its glyphs.
			var y := lerpf(size.y + 6.0, -6.0, progress)
			for x in [0.0, maxf(0.0, size.x - 2.0)]:
				_safe_rect(Rect2(x, y, 2.0, maxf(8.0, size.y * .30)), white)
			var charge := size.x * sin(progress * PI)
			_safe_rect(Rect2((size.x - charge) * .5, size.y - 2.0, charge, 2.0), Color(color, .85 * envelope))
		"activation":
			# Two crossing luminous ribbons, followed by a single broad confirmation ray.
			_band(front,maxf(24,size.x*.18),Color(color,.36*envelope),.36)
			_band(size.x-front,maxf(14,size.x*.10),Color(color.lightened(.4),.46*envelope),-.36)
			_band(front,5,white,.36)
			_band(size.x-front,3,white,-.36)
			var spread := size.x*clampf((progress-.25)*2.0,0,1)
			_safe_rect(Rect2((size.x-spread)*.5,size.y*.52-3,spread,6),Color(color,.7*envelope))
		"scan":
			_band(front+tail_sign*size.x*.13,maxf(32,size.x*.30),Color(color,.25*envelope))
			_band(front,9,white)
			for i in range(12):
				var y := (float(i)+.5)*size.y/12.0
				_safe_rect(Rect2(front+tail_sign*16.0-28,y,56,2),Color(color,.85*envelope))
		"boot":
			_band(front+tail_sign*size.x*.16,maxf(40,size.x*.35),Color(color,.27*envelope))
			_band(front,maxf(12,size.x*.035),white)
			for row in range(3):
				var y := size.y*(.24+float(row)*.24)
				for segment in range(4):
					var x := front+tail_sign*(24.0+float(segment)*22.0)
					_safe_rect(Rect2(x,y,14,3),Color(color,envelope*(.85-float(segment)*.16)))
		"turn":
			_band(front+tail_sign*size.x*.17,maxf(54,size.x*.38),Color(color,.40*envelope),.28)
			_band(front,12,white,.28)
			_band(front-tail_sign*20,3,Color(color,.9*envelope),.28)
			_safe_rect(Rect2(0,size.y-4,size.x*progress,4),Color(color,.85*envelope))
