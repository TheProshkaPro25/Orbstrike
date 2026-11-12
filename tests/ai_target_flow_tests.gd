extends "res://tests/cards033_tests.gd"
## Настоящие main/sim входы ИИ, без Boot, моделей, графики и матчевых серий.
const Main = preload("res://scenes/main.gd")
const InputView := preload("res://scenes/interaction/interaction_view.gd")
const Sim = preload("res://tools/sim.gd")
const Autoplay = preload("res://tools/autoplay.gd")

class QuietHud extends HudUI:
	func set_hint(_text: String) -> void: pass

class QuietBattleHud extends BattleHud:
	func set_chain(_plays: Array, _passed: Array, _turn: int = -1, _cancelled: Array = [], _counts: Array = [], _blocks: Array = []) -> void: pass

class QuietAbilityPanel extends AbilityPanel:
	func hide_panel() -> void: pass

func _initialize() -> void:
	Engine.max_fps = 60
	AudioServer.set_bus_mute(0, true)
	CardDB.load_all()
	_add_test_creatures()
	call_deferred("_run_flows")

func _run_flows() -> void:
	for id in [CALL, RESERVE]:
		for difficulty in [AIPlayer.Difficulty.NORMAL, AIPlayer.Difficulty.HARD]:
			for player in [0, 1]:
				_run_target_flow(id, difficulty, player, false, false)
				_run_target_flow(id, difficulty, player, false, false, true)
			for attacks in [false, true]:
				_run_target_flow(id, difficulty, 1, true, attacks)
				_run_target_flow(id, difficulty, 0, false, attacks, false, true)
	print("AI TARGET FLOW: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)

func _run_target_flow(id: StringName, difficulty: int, player: int, live: bool, attacks: bool, npc: bool = false, human: bool = false) -> void:
	var ctrl := _c033(player, 1 if id == CALL else 2, [id], true)
	if (live and attacks) or (human and not attacks):
		ctrl.state.creatures[3].slot = -1
		ctrl.state.slots[1].occupant_uid = -1
		_stand(ctrl, 0, 1)
		ctrl._turn_player = 1
		ctrl._start_battle(3, 0, 1)
		if human:
			_check(ctrl.pass_ability(1) == OK, "передача ответа human-защитнику")
	var ally := player * 3 + 1
	if id == CALL:
		_stand(ctrl, ally, 4)
	else:
		ctrl.state.players[player].abilities_used.append(&"ability_light_guard")
		ctrl.state.players[player].ability_cooldown[&"ability_light_guard"] = 2
	ctrl.state.players[1 - player].ability_hand.clear()
	var ai := AIPlayer.new(player, 333, -1.0, difficulty)
	var path := "main" if live else ("npc" if npc else ("autoplay" if human else "sim"))
	var label := "%s/%s/player%d/attacks%s" % [path, id, player, attacks]
	var pick := ai.choose_ability(ctrl.get_view(player), ctrl.get_battle_preview(), ctrl.legal_abilities(player))
	_check(pick == id, label + ": настоящий ИИ выбирает карту")
	if live or human:
		# Узкий настоящий метод main; вывод интерфейса не является предметом проверки.
		var game := Main.new()
		game.ctrl = ctrl
		game.ai = ai
		game.hud = QuietHud.new()
		game.battle_hud = QuietBattleHud.new()
		game.add_child(game.hud)
		game.add_child(game.battle_hud)
		game._index_creatures()
		game.ability_panel = QuietAbilityPanel.new()
		game.add_child(game.ability_panel)
		var picker := ArenaSlotPicker.new()
		root.add_child(picker)
		var ports := InputView.new()
		ports.hud = game.hud
		ports.ability = game.ability_panel
		ports.arena_picker = picker
		ports.ability_picker = AbilityTargetPicker.new()
		root.add_child(ports.ability_picker)
		game.ability_target_picker = ports.ability_picker
		game.interaction.configure(ports,game.presentation,game._resources,null,null,null,null)
		game.interaction.bind_controller(ctrl,ai)
		if human:
			game.ability_target_picker.chosen.connect(game._on_ability_target_chosen)
			game._on_ability_chosen(id)
			_check(game.ability_target_picker.visible and ctrl.state.players[player].ability_hand.has(id), label + ": настоящий выбор открылся до траты карты")
			_check(Autoplay.choose_pending_target(game, ai), label + ": autoplay выбрал цель")
			_check(not game.ability_target_picker.visible and game._ability_target_card == &"", label + ": сигнал выбора завершил ожидание")
		else:
			game._do_ability(player)
		game.ability_target_picker.queue_free()
		picker.queue_free()
		game.queue_free()
	elif npc:
		_check(TournamentNpcSimulator.play_ai_ability(ctrl, ai, player, pick) == OK, label + ": команда принята")
	else:
		_check(Sim.play_ai_ability(ctrl, ai, player, pick) == OK, label + ": команда принята")
	_check(not ctrl.state.players[player].ability_hand.has(id), label + ": карта потрачена, окно не зависло")
	var last: Array = ctrl.action_trace.back()
	_check(last[0] == "play_ability" and last[1].size() == 3 and not last[1][2].is_empty(), label + ": команда содержит явную цель")
	var preview := ctrl.get_battle_preview()
	var side := 0 if ctrl.state.creatures[preview.attacker_uid].owner == player else 1
	_check(preview.called_uids[side] == ally if id == CALL else preview.reserve_cards[side] == &"ability_light_guard", label + ": правильная цель в расчёте")
	_pass_windows(ctrl)
	_check(ctrl.state.creatures[ally].slot == -1 if id == CALL else ctrl.state.players[player].ability_hand.has(&"ability_light_guard"), label + ": реальное последствие после исхода")
