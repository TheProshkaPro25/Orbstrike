extends CanvasLayer
## Крупное раскрытие для клавиатурного фокуса. Не участвует во вводе и Tab-порядке.

var _panel: Control
var _source: Control


static func open_on(source: Control, lines: Array) -> CanvasLayer:
	if lines.is_empty() or not source.is_inside_tree(): return null
	var disclosure := load("res://scenes/ui/card_hover.gd").new() as CanvasLayer
	disclosure._source = source
	disclosure.layer = 120
	source.add_child(disclosure)
	disclosure._panel = UiTheme.help_panel(lines)
	disclosure._passive(disclosure._panel)
	disclosure.add_child(disclosure._panel)
	disclosure._place.call_deferred()
	return disclosure


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
	_place()


func _place() -> void:
	if _panel == null: return
	var viewport := _source.get_viewport_rect().size
	var extent := _panel.get_combined_minimum_size().max(_panel.size)
	var factor := minf(1.0, minf((viewport.x - 24.0) / maxf(1.0, extent.x), (viewport.y - 24.0) / maxf(1.0, extent.y)))
	_panel.scale = Vector2.ONE * factor
	extent *= factor
	var rect := _source.get_global_rect()
	var x := rect.end.x + 16.0
	if x + extent.x > viewport.x - 12.0: x = rect.position.x - extent.x - 16.0
	_panel.position = Vector2(clampf(x, 12.0, maxf(12.0, viewport.x - extent.x - 12.0)), clampf(rect.get_center().y - extent.y * .5, 12.0, maxf(12.0, viewport.y - extent.y - 12.0)))
