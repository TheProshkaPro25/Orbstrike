extends "res://tests/run_tests.gd"
## Реальные события мыши: открытие ворот и три доступные карты подряд.
var panel: AbilityPanel
var controller: MatchController
var results: Array = []
func _initialize() -> void:
	call_deferred("run_input")
func run_input() -> void:
	CardDB.load_all()
	_add_test_creatures()
	root.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	controller = _battle_ctrl([PLUS, MINUS, &"ability_fire_assault"], [PLUS], NEUTRAL, -1, 0, 725)
	controller.state.manual_gates = true
	_set_card(controller, 1, &"arena_field_fire", 0)
	_stand(controller, 3, 1)
	_throw(controller, 0, 0, 1)
	panel = AbilityPanel.new()
	root.add_child(panel)
	panel.reason_for_card = func(cid: StringName) -> String: return controller.ability_unavailable_reason(0, cid)
	panel.ability_chosen.connect(func(cid: StringName) -> void: results.append(controller.play_ability(0, cid)))
	panel.gate_open_requested.connect(func() -> void: results.append(controller.reveal_gate(0)))
	show_options()
	await process_frame
	await process_frame
	_check(panel._gate_btn.visible, "кнопка своих ворот видна в бою")
	await click_at(panel._gate_btn.get_global_rect().get_center())
	_check(controller.state.slots[1].revealed and results.size() == 1 and results[0] == OK, "щелчок открывает ворота через контроллер")
	for number in 3:
		show_options()
		await process_frame
		_check(not panel._gate_btn.visible, "кнопка исчезла после открытия")
		var card: CardView = panel._cards[0]
		_check(panel._legal.has(card.card_id), "проверяем подсвеченную карту")
		await click_at(card.get_global_rect().get_center())
		_check(results.size() == number + 2 and results.back() == OK, "щелчок по доступной карте принят: %d" % number)
		_check(controller._b_count[0] == number + 1, "сыгранная карта учтена: %d" % number)
		controller.pass_ability(1)
		await create_timer(.4).timeout
	_check(controller.get_phase() != MatchController.Phase.ABILITY_WINDOW, "три карты применены, бой завершился")
	panel.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await process_frame
	await process_frame
	print("Ввод способностей: %d проверок, %d ошибок" % [_checks, _failures])
	quit(1 if _failures else 0)
func show_options() -> void:
	panel.set_hand(controller.state.players[0].ability_hand)
	var entries: Array = []
	for id in controller.legal_abilities(0): entries.append({"id": id})
	panel.show_options(entries, "Проверка доступных карт", {"moment": &"battle", "can_open_gate": controller.can_reveal_gate(0)})
func click_at(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	Input.parse_input_event(motion)
	await process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
