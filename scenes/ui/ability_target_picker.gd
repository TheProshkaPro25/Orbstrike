class_name AbilityTargetPicker
extends Control
## Explicit target choice is reversible until a card or creature is selected.
## Receives only targets approved by MatchController (or by the online server).
signal chosen(target: Dictionary)
signal cancelled
var _panel: PanelContainer
var _title: Label
var _choices: HBoxContainer
var _cancel: Button

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.022, 0.04, 0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	_panel.add_child(body)
	_title = VisualUtil.label("Выберите цель", 20)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_title)
	_choices = HBoxContainer.new()
	_choices.alignment = BoxContainer.ALIGNMENT_CENTER
	_choices.add_theme_constant_override("separation", 16)
	body.add_child(_choices)
	_cancel = Button.new()
	_cancel.text = "Назад · карта не потрачена"
	_cancel.custom_minimum_size = Vector2(280, 44)
	_cancel.pressed.connect(_on_cancel)
	body.add_child(_cancel)
	hide()

func show_targets(card_id: StringName, targets: Array, view: MatchState) -> void:
	VisualUtil.clear_children(_choices)
	var def := CardDB.card(card_id)
	_title.text = def.display_name + ": выберите " + ("союзника" if def.effect_id == &"gale_call" else "карту")
	var vp := get_viewport_rect().size
	var w := clampf((vp.x - 100.0) / maxf(1.0, targets.size()) - 16.0, 96.0, 230.0)
	w = minf(w, maxf(96.0, (vp.y - 200.0) / 1.4))
	for target in targets:
		var cv := CardView.new()
		if target.has("target_uid"):
			var uid := int(target.target_uid)
			cv.for_creature(CardDB.creature(view.creature(uid).def_id), uid, "", Vector2(w, w * 1.4))
		else:
			cv.for_card(CardDB.card(StringName(target.target_card)), Vector2(w, w * 1.4), true)
		cv.pressed.connect(_select.bind(target.duplicate(true)))
		_choices.add_child(cv)
	show()

func _select(target: Dictionary) -> void:
	hide()
	var command_target := {"target_uid":int(target.target_uid)} if target.has("target_uid") else {"target_card":StringName(target.target_card)}
	chosen.emit(command_target)

func _on_cancel() -> void:
	hide()
	cancelled.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_cancel()
