extends CanvasLayer
## Единственный экран загрузки — до главного меню.
var _progress: ProgressBar
var _status: Label


func _ready() -> void:
	layer = 100
	var bg := ColorRect.new()
	bg.color = Color(.018, .026, .042)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.theme = UiTheme.get_theme()
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 500
	column.add_theme_constant_override("separation", 22)
	center.add_child(column)
	var title := VisualUtil.label("Orbstrike", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	column.add_child(title)
	var label := VisualUtil.label("Загрузка игры", 23)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 18
	_progress.max_value = 100
	column.add_child(_progress)
	_status = VisualUtil.label("Подготовка…", 16)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)
	call_deferred("_load_game")


func _load_game() -> void:
	await get_tree().process_frame
	await GameLoading.i().prepare(func(value: float, text: String) -> void:
		_progress.value = value * 100
		_status.text = text)
	await get_tree().process_frame
	GameLoading.i().show_menu()
