class_name LocationIntro
extends Control
## Three location-specific establishing shots before any match input or HUD.
const SHOT_SECONDS := 2.4
const SHOTS := [
	# Stay inside the sanctuary's 106 m wall / 108 m crown.
	[[Vector3(-58,34,57),Vector3(-42,30,60),Vector3(0,25,-24)],
	 [Vector3(54,17,30),Vector3(48,20,17),Vector3(-23,29,-28)],
	 [Vector3(0,64,53),Vector3(0,52,63),Vector3(0,0,-4)]],
	[[Vector3(-66,24,64),Vector3(-49,27,57),Vector3(12,26,-67)],
	 [Vector3(48,17,34),Vector3(39,20,23),Vector3(-37,29,-63)],
	 [Vector3(7,62,66),Vector3(0,52,63),Vector3(0,0,-4)]],
	[[Vector3(-65,26,60),Vector3(-49,29,52),Vector3(22,22,-90)],
	 [Vector3(56,16,38),Vector3(43,21,27),Vector3(-43,25,-76)],
	 [Vector3(-8,60,66),Vector3(0,52,63),Vector3(0,0,-4)]],
]
var title: Label
var shot_index := -1
var _camera: CameraRig
var _tween: Tween
var _finished := false
signal completed

func _ready() -> void:
	name = "LocationIntro"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	for bottom in [false, true]:
		var bar := ColorRect.new()
		bar.color = Color(.004,.009,.018,.94)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
		bar.offset_top = -52 if bottom else 0
		bar.offset_bottom = 0 if bottom else 52
	title = VisualUtil.label("", 44)
	title.name = "LocationTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color",Color(.96,.94,.85))
	title.add_theme_color_override("font_shadow_color",Color(0,0,0,.95))
	title.add_theme_constant_override("shadow_offset_y",3)
	title.add_theme_constant_override("outline_size",8)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.offset_left = 24
	title.offset_right = -24
	resized.connect(_resize_title)
	var skip := Button.new()
	skip.text = "Пропустить"
	skip.flat = true
	skip.theme = UiTheme.get_theme()
	skip.pressed.connect(finish)
	add_child(skip)
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.offset_left = -150
	skip.offset_top = -46
	skip.offset_right = -18
	skip.offset_bottom = -8

func _resize_title() -> void:
	title.add_theme_font_size_override("font_size",clampi(int(size.x / 25),24,48))

func play(camera: CameraRig, location: int) -> void:
	_camera = camera
	title.text = ArenaLocations.definition(location).name
	_resize_title()
	# Reduced motion retains the title and sequence order, with a still overview.
	_tween = create_tween().set_ignore_time_scale(true)
	if DeviceSettings.reduce_motion():
		camera.snap_overview()
		shot_index = 2
		_tween.tween_interval(1.8)
	else:
		for index in 3:
			_tween.tween_callback(func() -> void: shot_index = index)
			_tween.tween_method(_frame.bind(SHOTS[clampi(location,0,2)][index]),0.0,1.0,SHOT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(finish)

func _frame(t: float, shot: Array) -> void:
	_camera.location_frame((shot[0] as Vector3).lerp(shot[1],t),shot[2],52.0)

func finish() -> void:
	if _finished: return
	_finished = true
	if _tween != null and _tween.is_valid(): _tween.kill()
	_camera.snap_overview()
	hide()
	completed.emit()
	queue_free()
