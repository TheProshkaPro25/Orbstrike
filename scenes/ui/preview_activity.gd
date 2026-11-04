extends RefCounted
## Visibility of the actual texture consumer controls rendering and animation work.
## Keep processing flags on descendants intact (the editor samples its fighter manually).
signal resumed
var _viewport: SubViewport
var _consumer: CanvasItem
var _processor: Node
var _viewport_mode: Node.ProcessMode
var _processor_mode: Node.ProcessMode
var _running := true
var _covered := false
var _closed := false
var _layers: Array[CanvasLayer] = []

func _init(viewport: SubViewport, consumer: CanvasItem, processor: Node = null) -> void:
	_viewport = viewport
	_consumer = consumer
	_processor = processor if processor != null else viewport
	_viewport_mode = viewport.process_mode
	_processor_mode = _processor.process_mode
	consumer.visibility_changed.connect(sync)
	consumer.tree_exiting.connect(stop)
	# CanvasLayer visibility is separate from CanvasItem ancestry.
	var parent := consumer.get_parent()
	while parent != null:
		if parent is CanvasLayer:
			_layers.append(parent)
			parent.visibility_changed.connect(sync)
		parent = parent.get_parent()
	sync()

func set_covered(value: bool) -> void:
	_covered = value
	sync()

func sync() -> void:
	if not is_instance_valid(_viewport) or not is_instance_valid(_processor): return
	var active := not _closed and not _covered and is_instance_valid(_consumer) and _consumer.is_visible_in_tree()
	for layer in _layers:
		if is_instance_valid(layer) and not layer.visible: active = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if active == _running: return
	_running = active
	_viewport.process_mode = _viewport_mode if active else Node.PROCESS_MODE_DISABLED
	_processor.process_mode = _processor_mode if active else Node.PROCESS_MODE_DISABLED
	if active: resumed.emit()

func stop() -> void:
	_closed = true
	sync()
