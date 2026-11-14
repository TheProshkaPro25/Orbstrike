extends CanvasLayer
## Крупное раскрытие для клавиатурного фокуса. Не участвует во вводе и Tab-порядке.

static var _active: WeakRef
var _last_rect := Rect2()
var _last_viewport := Vector2.ZERO
var _panel: Control
var _source: Control


static func open_on(source: Control, lines: Array) -> CanvasLayer:
	if lines.is_empty() or not source.is_inside_tree(): return null
	if _active != null and is_instance_valid(_active.get_ref()):
		var previous = _active.get_ref()
		if not previous.is_queued_for_deletion() and previous._source == source: return previous
	close_active()
	var disclosure := load("res://scenes/ui/card_hover.gd").new() as CanvasLayer
	_active = weakref(disclosure)
	disclosure._source = source
	disclosure.layer = 120
	source.add_child(disclosure)
	disclosure._panel = UiTheme.help_panel(lines)
	disclosure._passive(disclosure._panel)
	disclosure.add_child(disclosure._panel)
	disclosure._place.call_deferred()
	return disclosure


static func close_active() -> void:
	if _active != null and is_instance_valid(_active.get_ref()): _active.get_ref().queue_free()
	_active = null


func _input(event: InputEvent) -> void:
	# Focus may have been restored during a hand rebuild while the pointer was
	# already outside this card. Its local mouse_exited signal will never fire.
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_instance_valid(_source) or not _source.has_focus(): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			queue_free()
			return # Let the hand/Main process the same cancellation as before.
		elif event.keycode in [KEY_PAGEDOWN, KEY_PAGEUP] and _panel.has_method("scroll_page"):
			_panel.scroll_page(1 if event.keycode == KEY_PAGEDOWN else -1)
		else: return
		get_viewport().set_input_as_handled()


func _passive(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.focus_mode = Control.FOCUS_NONE
		node.tooltip_text = ""
	for child in node.get_children(): _passive(child)


func _process(_delta: float) -> void:
	if not is_instance_valid(_source) or not _source.is_visible_in_tree() or not _source.has_focus():
		queue_free()
		return
	var rect := _source.get_global_rect()
	var viewport := _source.get_viewport_rect().size
	if rect != _last_rect or viewport != _last_viewport: _place()


func _place() -> void:
	if not is_instance_valid(_panel) or not is_instance_valid(_source) or not _source.is_inside_tree(): return
	var viewport := _source.get_viewport_rect().size
	_last_viewport = viewport
	_last_rect = _source.get_global_rect()
	var dock_card := _source.has_meta("device_hand_card")
	var available := Vector2(viewport.x, maxf(170.0, _last_rect.position.y - 120.0)) if dock_card else viewport
	if _panel.has_method("fit_viewport"): _panel.fit_viewport(available)
	var extent := _panel.get_combined_minimum_size().max(_panel.size)
	var factor := minf(1.0, minf((viewport.x - 24.0) / maxf(1.0, extent.x), (viewport.y - 24.0) / maxf(1.0, extent.y)))
	if _source.has_meta("ability_target_card"):
		var room := maxf(_last_rect.position.x, viewport.x - _last_rect.end.x) - 28.0
		factor = minf(factor, maxf(0.72, room / maxf(1.0, extent.x)))
	_panel.scale = Vector2.ONE * factor
	extent *= factor
	var rect := _source.get_global_rect()
	if dock_card:
		var left := rect.get_center().x < viewport.x * 0.5
		_panel.position = Vector2(14.0 if left else viewport.x - extent.x - 14.0, maxf(12.0, rect.position.y - extent.y - 14.0))
		return
	var x := rect.end.x + 16.0
	if x + extent.x > viewport.x - 12.0: x = rect.position.x - extent.x - 16.0
	_panel.position = Vector2(clampf(x, 12.0, maxf(12.0, viewport.x - extent.x - 12.0)), clampf(rect.get_center().y - extent.y * .5, 12.0, maxf(12.0, viewport.y - extent.y - 12.0)))
