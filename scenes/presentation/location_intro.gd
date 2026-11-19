class_name LocationIntro
extends Control
## Location establishing sequence before any match input or HUD.
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
const WATER_START := Vector3(106, -2.45, -540)
const PLATFORM_RIM := Vector3(0, 11, -142)
const APPROACH_SECONDS := 3.12
const TILT_SECONDS := .46
const RIM_COAST_METERS := 34.4
const LETTERBOX_HEIGHT := 52.0
const ARRIVAL_EXPOSURE := .72
const GLINT_RECOVERY_SECONDS := .76
const CoastalIntroAudio := preload("res://scenes/audio/coastal_intro_audio.gd")
var title: Label
var shot_index := -1
var _camera: CameraRig
var _tween: Tween
var _wind: ColorRect
var _sun_glint: ColorRect
var _flight_audio: CoastalIntroAudio
var _resume_camera := false
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
		bar.offset_top = -LETTERBOX_HEIGHT if bottom else 0.0
		bar.offset_bottom = 0.0 if bottom else LETTERBOX_HEIGHT
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
	skip.focus_next = NodePath(".")
	skip.focus_previous = NodePath(".")
	skip.grab_focus()

func _input(event: InputEvent) -> void:
	if not _finished and _camera != null and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		finish()

func _resize_title() -> void:
	title.add_theme_font_size_override("font_size",clampi(int(size.x / 25),24,48))

func play(camera: CameraRig, location: int) -> void:
	_camera = camera
	title.text = ArenaLocations.definition(location).name
	_resize_title()
	var coastal := ArenaLocations.CoastalStyle.applies(location)
	if coastal:
		# The tween owns the sea-level path. The normal rig resumes before play.
		_resume_camera = camera.is_processing()
		camera.set_process(false)
	# Reduced motion retains the title and sequence order, with a still overview.
	_tween = create_tween().set_ignore_time_scale(true)
	if DeviceSettings.reduce_motion():
		camera.snap_overview()
		shot_index = 2
		_tween.tween_interval(1.8)
	elif coastal:
		_play_coastal_flight()
	else:
		for index in 3:
			_tween.tween_callback(func() -> void: shot_index = index)
			var draw_frame := _frame.bind(SHOTS[clampi(location,0,2)][index])
			_tween.tween_method(draw_frame,0.0,1.0,SHOT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(finish)

func _frame(t: float, shot: Array) -> void:
	_camera.location_frame((shot[0] as Vector3).lerp(shot[1],t),shot[2],52.0)

func _play_coastal_flight() -> void:
	_wind = ColorRect.new()
	_wind.name = "CoastalWind"
	_wind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wind_material := ShaderMaterial.new()
	wind_material.shader = preload("res://scenes/shaders/coastal_flight_wind.gdshader")
	_wind.material = wind_material
	add_child(_wind)
	move_child(_wind, 0)
	_wind.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sun_glint = ColorRect.new()
	_sun_glint.name = "CoastalSunGlint"
	_sun_glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glint_material := ShaderMaterial.new()
	glint_material.shader = preload("res://scenes/shaders/coastal_sun_glint.gdshader")
	_sun_glint.material = glint_material
	add_child(_sun_glint)
	move_child(_sun_glint, 1)
	_sun_glint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sun_glint.offset_top = LETTERBOX_HEIGHT
	_sun_glint.offset_bottom = -LETTERBOX_HEIGHT
	_sun_glint.hide()
	_flight_audio = CoastalIntroAudio.new()
	add_child(_flight_audio)
	_flight_audio.start()
	title.modulate.a = 0.0
	shot_index = 0
	_coastal_approach(0.0)
	_tween.tween_method(_coastal_approach, 0.0, 1.0, APPROACH_SECONDS)
	_tween.tween_callback(func() -> void:
		shot_index = 1
		_sun_glint.show()
		_flight_audio.tilt())
	_tween.tween_method(_coastal_tilt, 0.0, 1.0, TILT_SECONDS)
	_tween.tween_callback(func() -> void:
		shot_index = 2
		_wind.hide())
	_tween.tween_method(_set_glint_recovery, 0.0, 1.0, GLINT_RECOVERY_SECONDS)
	_tween.parallel().tween_method(_set_exposure, ARRIVAL_EXPOSURE, 0.0, .21).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_sun_glint.hide)
	_tween.tween_interval(1.35 - GLINT_RECOVERY_SECONDS)
	_tween.tween_property(title, "modulate:a", 0.0, .25)

func _coastal_approach(t: float) -> void:
	# Pick up speed early over the water, then carry it into the turn.
	var travel := .70 * t + .40 * t * t - .10 * t * t * t
	var eye := WATER_START.lerp(PLATFORM_RIM, travel)
	eye.y = lerpf(WATER_START.y, PLATFORM_RIM.y, smoothstep(.71, 1.0, travel))
	var heading := (PLATFORM_RIM - WATER_START).slide(Vector3.UP).normalized()
	var pitch := lerpf(.11, .17, smoothstep(.70, 1.0, travel))
	var bank := -.034 * sin(t * PI)
	_camera.location_frame(eye, eye + heading + Vector3.DOWN * pitch, lerpf(62.0, 69.0, t), bank, WATER_START.y)
	_wind.modulate.a = smoothstep(0.0, .20, t)
	(_wind.material as ShaderMaterial).set_shader_parameter("flight_time", t * APPROACH_SECONDS)

func _coastal_tilt(t: float) -> void:
	var course := (PLATFORM_RIM - WATER_START).slide(Vector3.UP)
	var heading := course.normalized()
	# Carry forward momentum across the rim, braking to rest as the camera tilts.
	var arrival_speed := course.length() * 1.2 / APPROACH_SECONDS
	var braking := arrival_speed * TILT_SECONDS / RIM_COAST_METERS
	var coast := RIM_COAST_METERS * (1.0 - pow(1.0 - t, braking))
	var turn := 1.0 - pow(1.0 - t, 1.7)
	var eye := PLATFORM_RIM + heading * coast + Vector3.UP * 4.0 * turn
	var low := (heading + Vector3.DOWN * .17).normalized()
	# Frame the visible sun above the centered title, with a little room on its left.
	var sun := ArenaLocations.CoastalStyle.direction_to_sun()
	var high := (sun + Vector3(.13, -.14, 0)).normalized()
	var sight := low.slerp(high, turn)
	_camera.location_frame(eye, eye + sight, lerpf(69.0, 54.0, turn))
	var screen_sun := _camera.unproject_position(eye + sun * 1000.0)
	var film_sun := _sun_glint.get_global_transform_with_canvas().affine_inverse() * screen_sun
	var lens_scale := maxf(1.0, .45 * size.y * lerpf(.76, 1.0, turn))
	var glint := _sun_glint.material as ShaderMaterial
	glint.set_shader_parameter("sun_uv", film_sun / _sun_glint.size.max(Vector2.ONE))
	glint.set_shader_parameter("lens_extent", _sun_glint.size / lens_scale)
	# Glare builds as the disk enters view. Adaptation continues briefly after the camera settles.
	var facing_sun := smoothstep(cos(deg_to_rad(41.0)), cos(deg_to_rad(15.0)), sight.dot(sun))
	_set_exposure(facing_sun * lerpf(1.0, ARRIVAL_EXPOSURE, smoothstep(.80, 1.0, t)))
	_sun_glint.modulate.a = smoothstep(.08, .56, t) * lerpf(1.0, .58, smoothstep(.62, 1.0, t))
	_wind.modulate.a = 1.0 - smoothstep(0.0, .58, t)
	(_wind.material as ShaderMaterial).set_shader_parameter("flight_time", APPROACH_SECONDS + t * TILT_SECONDS)
	title.modulate.a = smoothstep(.60, 1.0, t)

func _set_exposure(strength: float) -> void:
	(_sun_glint.material as ShaderMaterial).set_shader_parameter("exposure_pulse", strength)

func _set_glint_recovery(progress: float) -> void:
	(_sun_glint.material as ShaderMaterial).set_shader_parameter("recovery", progress)

func finish() -> void:
	if _finished: return
	_finished = true
	if _tween != null and _tween.is_valid(): _tween.kill()
	if _flight_audio != null: _flight_audio.stop()
	if _resume_camera: _camera.set_process(true)
	_camera.snap_overview()
	hide()
	completed.emit()
	queue_free()
