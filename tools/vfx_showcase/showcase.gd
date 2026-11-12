extends Node3D

const Effects := preload("res://tools/vfx_showcase/preview_effects.gd")
const ElementalTrail := preload("res://assets/vfx/trails/elemental_trail.gd")
const PACKS := ["Effects Lab", "REEBOO", "Elemental Impact", "Vefects Trails", "Kenney", "Шлейфы Orbstrike"]
const TITLES := ["Свет из витражей", "Искра удара, взмах и подбор", "Огненный удар", "Шлейф сферы", "Искры захвата", "Стихийные шлейфы Orbstrike"]
const TRAIL_TINTS := [
	Color("ffb160"), Color("a486ff"), Color("e2b281"), Color("91e2ff"), Color("ff945e"),
	Color("c4eeff"), Color("acdf77"), Color("efd9ff"), Color("e8bdff"), Color("6ec6ff"),
]

var capture_mode := false
var _effect_layer: Node3D
var _architecture: Node3D
var _camera: Camera3D
var _side_pedestals: Node3D
var _title: Label
var _subtitle: Label
var _trail_controls: HBoxContainer
var _buttons: Array[Button] = []
var _trail_head: Node3D
var _trail_effect: Node3D
var _section := 0
var _variant := 0
var _clock := 0.0
var _replay_at := 0.0
var _pickup: VFXEffect


func _ready() -> void:
	_build_stage()
	_build_ui()
	show_sample(0)


func show_sample(section: int, variant: int = 0) -> void:
	for child in _effect_layer.get_children():
		_effect_layer.remove_child(child)
		child.queue_free()
	_section = section
	_variant = variant
	_clock = 0.0
	_replay_at = 1.8
	_trail_head = null
	_trail_effect = null
	_pickup = null
	_architecture.visible = section == 0
	_side_pedestals.visible = section == 1
	_camera.position = Vector3(0.8, 2.45, 8.2) if section == 0 else Vector3(0.0, 2.8, 8.2)
	_camera.look_at(Vector3(0.0, 2.24, 0.0) if section == 0 else Vector3(0.0, 1.25, 0.0))
	_camera.size = 5.55 if section == 0 else 4.4
	for index in _buttons.size():
		_buttons[index].set_pressed_no_signal(index == section)
	_trail_controls.visible = section in [3, 5]
	_title.text = TITLES[section]
	_subtitle.text = ""
	match section:
		0:
			Effects.shafts(_effect_layer)
			_subtitle.text = "Три мягких луча для витражей Святилища"
		1:
			_reeboo()
		2:
			Effects.fire_impact(_effect_layer, Vector3(0.0, 0.82, 0.0))
			_subtitle.text = "Огненная вспышка, кольцо, искры и дым"
		3, 5:
			_start_trail()
		4:
			Effects.kenney(_effect_layer, Vector3(0.0, 0.95, 0.0))
			_subtitle.text = "Частицы из текстур flare_01 и spark_05"

	_subtitle.visible = not _subtitle.text.is_empty()


func trail_has_geometry() -> bool:
	if not is_instance_valid(_trail_effect):
		return false
	if _trail_effect is ElementalTrail:
		return _trail_effect._mesh_visible
	for ribbon: MeshInstance3D in _trail_effect.find_children("*", "MeshInstance3D", true, false):
		if ribbon.mesh != null and ribbon.mesh.get_surface_count() > 0:
			return true
	return false


func trail_has_audio() -> bool:
	if not is_instance_valid(_trail_effect):
		return false
	for sound: AudioStreamPlayer3D in _trail_effect.find_children("*", "AudioStreamPlayer3D", true, false):
		if sound.stream is AudioStreamPlaylist and sound.stream.loop:
			return true
	return false


func _process(delta: float) -> void:
	_clock += delta
	if is_instance_valid(_trail_head):
		_move_trail_head()
	if capture_mode or _clock < _replay_at:
		return
	_replay_at += 1.8
	match _section:
		1: _reeboo()
		2: Effects.fire_impact(_effect_layer, Vector3(0.0, 0.82, 0.0))
		4: Effects.kenney(_effect_layer, Vector3(0.0, 0.95, 0.0))


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6: show_sample(event.keycode - KEY_1)
		KEY_LEFT: _cycle_trail(-1)
		KEY_RIGHT: _cycle_trail(1)
		KEY_SPACE: show_sample(_section, _variant)


func _cycle_trail(step: int) -> void:
	if _section in [3, 5]:
		show_sample(_section, posmod(_variant + step, Effects.TRAIL_NAMES.size()))


func _reeboo() -> void:
	Effects.reeboo(_effect_layer, 0, Vector3(-2.36, 0.88, 0.0))
	Effects.reeboo(_effect_layer, 1, Vector3(-0.28, 0.78, 0.12))
	if not is_instance_valid(_pickup):
		_pickup = Effects.reeboo(_effect_layer, 2, Vector3(2.36, 0.85, 0.0))


func _start_trail() -> void:
	var element: String = Effects.TRAIL_NAMES[_variant]
	_trail_head = Node3D.new()
	_effect_layer.add_child(_trail_head)
	_move_trail_head()
	if _section == 5:
		var trail := ElementalTrail.new()
		trail.configure(_variant)
		_trail_head.add_child(trail)
		trail.set_airborne(true, 0.13)
		_trail_effect = trail
	else:
		_trail_effect = Effects.trail(_trail_head, element)
	_subtitle.text = "%s  ·  %d / %d" % [element, _variant + 1, Effects.TRAIL_NAMES.size()]
	if _trail_effect == null:
		_subtitle.text = "Локальный пакет Vefects не установлен"
		return
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.13
	head_mesh.height = 0.26
	_mesh(_trail_head, head_mesh, Vector3.ZERO, TRAIL_TINTS[_variant], 0.35)


func _move_trail_head() -> void:
	var angle := _clock * 2.5 - 1.4
	_trail_head.position = Vector3(cos(angle) * 2.05, 1.25 + sin(angle) * 0.7, sin(angle * 0.6) * 0.72)


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("121927")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9aafce")
	environment.ambient_light_energy = 0.43
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	environment.glow_enabled = true
	environment.glow_hdr_threshold = 1.1
	environment.glow_intensity = 0.8
	environment.glow_strength = 1.1
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(_camera)
	_camera.make_current()

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -28, 0)
	key.light_color = Color("ffe2c6")
	key.light_energy = 0.72
	key.shadow_enabled = true
	add_child(key)

	_box(self, Vector3(18.0, 0.2, 11.0), Vector3(0, -0.14, -1.8), Color("293143"))
	_side_pedestals = Node3D.new()
	add_child(_side_pedestals)
	for x in [-2.36, 0.0, 2.36]:
		var parent := self if is_zero_approx(x) else _side_pedestals
		var pedestal := CylinderMesh.new()
		pedestal.top_radius = 0.75
		pedestal.bottom_radius = 0.88
		pedestal.height = 0.2
		pedestal.radial_segments = 8
		_mesh(parent, pedestal, Vector3(x, 0.06, 0.0), Color("49536a"))
		var inset := CylinderMesh.new()
		inset.top_radius = 0.62
		inset.bottom_radius = 0.66
		inset.height = 0.02
		inset.radial_segments = 8
		_mesh(parent, inset, Vector3(x, 0.167, 0.0), Color("68718a"))

	_architecture = Node3D.new()
	add_child(_architecture)
	_box(_architecture, Vector3(10.0, 4.5, 0.24), Vector3(0.0, 2.2, -2.25), Color("2f3446"))
	for x in [-3.35, -2.55, -1.75, 0.2, 2.15]:
		var tint := Color("b08d6b").lerp(Color("6d9bad"), clampf((x + 3.35) * 0.4, 0.0, 1.0))
		_box(_architecture, Vector3(0.58, 2.25, 0.09), Vector3(x, 2.63, -2.08), Color("655b61"))
		_box(_architecture, Vector3(0.45, 2.04, 0.10), Vector3(x, 2.63, -2.02), tint, 0.55)
		for y in [2.15, 2.65, 3.15]:
			_box(_architecture, Vector3(0.46, 0.04, 0.11), Vector3(x, y, -1.99), Color("4d4f63"))
		_box(_architecture, Vector3(0.055, 2.04, 0.11), Vector3(x, 2.63, -1.99), Color("4d4f63"))
	_effect_layer = Node3D.new()
	add_child(_effect_layer)


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, emission: float = 0.0) -> void:
	var box := BoxMesh.new()
	box.size = size
	_mesh(parent, box, at, color, emission)


func _mesh(parent: Node3D, primitive: PrimitiveMesh, at: Vector3, color: Color, emission: float = 0.0) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	primitive.material = material
	var item := MeshInstance3D.new()
	item.mesh = primitive
	item.position = at
	parent.add_child(item)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var theme := Theme.new()
	theme.default_font_size = 16
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.042, 0.061, 0.10, 0.94)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 14
	style.content_margin_bottom = 15
	panel.add_theme_stylebox_override("panel", style)
	panel.theme = theme
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	layer.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	panel.add_child(stack)
	var menu := HBoxContainer.new()
	menu.add_theme_constant_override("separation", 8)
	stack.add_child(menu)
	for index in PACKS.size():
		var button := Button.new()
		button.text = PACKS[index]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(show_sample.bind(index, 0))
		menu.add_child(button)
		_buttons.append(button)
	var info := HBoxContainer.new()
	stack.add_child(info)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 25)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_title)
	_trail_controls = HBoxContainer.new()
	info.add_child(_trail_controls)
	for step in [-1, 1]:
		var button := Button.new()
		button.text = "←" if step < 0 else "→"
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_cycle_trail.bind(step))
		_trail_controls.add_child(button)
	_subtitle = Label.new()
	_subtitle.modulate = Color("b2c2df")
	stack.add_child(_subtitle)
	_subtitle.hide()
