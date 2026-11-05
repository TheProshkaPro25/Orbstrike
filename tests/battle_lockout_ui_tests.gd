extends "res://tests/battle_lockout_tests.gd"
## Actual main.tscn layers, real mouse input, controller position, result at960/1280.
var out_dir := "res://build/checks/presentation/selected-battle-lockout-ui/battle-lockout-ui"

func _initialize() -> void:
	call_deferred("_run_ui")

func _run_ui() -> void:
	CardDB.load_all()
	_add_test_creatures()
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.theme = UiTheme.get_theme()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(.4).timeout
	game._build_logic()
	game.team_menu.hide()
	game.setup_panel.set_dock_visible(false)
	game.hud.set_battle_mode(true)
	for extent in [Vector2i(960,540), Vector2i(1280,720)]:
		root.size = extent
		root.content_scale_size = extent
		var c := reported_position(true)
		game.ctrl = c
		game._index_creatures()
		game.battle_hud.open(["Колоссар Тени", "Клыкарь Тени"], [4,4], [370,620])
		game._refresh_hand()
		game._do_ability(0)
		await create_timer(.6).timeout
		var reset_card: CardView
		for card in game.ability_panel._cards:
			if card.card_id == RESET: reset_card = card
		_check(reset_card != null, "reset in real ability hand")
		await _mouse(reset_card.get_global_rect().get_center())
		await create_timer(1.2).timeout
		_check(game.ability_panel._title.text.contains("запрет"), "warning visible before click")
		_check(reset_card._help[6].contains("меньше трёх") and reset_card._help[6].contains("Соперник"), "hover retains exact price")
		_check(c.state.players[0].ability_hand.has(RESET), "hover did not play card")
		await _capture("before-reset-%d" % extent.x)
		await _click(reset_card.get_global_rect().get_center())
		_check(c._b_count[0] == 2 and c.get_active_player() == 1, "actual click spends second own card")
		_check(c.play_ability(1,HUNT) == OK, "late opponent hunt")
		var r := c.get_battle_preview()
		game.battle_hud.set_chain(r.plays,r.passed,1,r.cancelled_plays,r.ability_counts,game._battle_blocks(r))
		game.battle_hud.set_powers(r.powers)
		await create_timer(.5).timeout
		var count: Label = game.battle_hud._counts[0]
		_check(count.text == "2/3 · КАРТЫ ЗАКРЫТЫ", "visible blocked count distinguishes unused capacity")
		_check(count.tooltip_text.contains("Великий сброс"), "counter has controller reason")
		await _mouse(count.get_global_rect().get_center())
		await create_timer(.9).timeout
		_check(root.gui_get_hovered_control() == count, "real mouse reaches counter reason")
		await _capture("after-reset-%d" % extent.x)
		var resolved: Array = []
		c.battle_resolved.connect(func(result: BattleResult) -> void: resolved.append(result))
		c.pass_ability(1)
		_check(resolved.size() == 1 and resolved[0].powers == [370,510], "actual result 370:510")
		await _mouse(Vector2(10,extent.y-15))
		game.battle_overlay.show_result(resolved[0],game._names_for(resolved[0]))
		await create_timer(.4).timeout
		_check(root.get_visible_rect().encloses(game.battle_overlay._panel.get_global_rect()), "result bounded by viewport")
		_check(game.battle_overlay._outcome_lines(resolved[0]).get(0).contains("Великий сброс"), "result names early close")
		await _capture("result-top-%d" % extent.x)
		game.battle_overlay._scroll.scroll_vertical = 10000
		await create_timer(.3).timeout
		await _capture("result-reason-%d" % extent.x)
		game.battle_overlay._close()
		# Worst longer reason: copied lockout on both sides, scrolling remains inside.
		var copied := _seq(_anime(),[[1,RESET],[0,COPY]])
		game.battle_overlay.show_result(copied,{0:"Колоссар Тени",1:"Клыкарь Тени"})
		await create_timer(.3).timeout
		_check(root.get_visible_rect().encloses(game.battle_overlay._panel.get_global_rect()), "long copied reason bounded")
		game.battle_overlay._scroll.scroll_vertical = 10000
		await create_timer(.2).timeout
		await _capture("copied-reason-%d" % extent.x)
		game.battle_overlay._close()
		game.battle_hud.close()
		# Новые цены сложных эффектов используют тот же реальный hover руки,
		# но не должны ошибочно называться запретом следующих карт.
		var warnings := [&"ability_gale_swap", &"ability_stone_shift", &"ability_tide_ebb"]
		game.ability_panel.set_hand(warnings)
		var entries: Array = []
		for id in warnings: entries.append({"id":id})
		game.ability_panel.show_options(entries,"Ваш ответ: способность или пас",{"moment":&"battle"})
		await create_timer(.4).timeout
		for card: CardView in game.ability_panel._cards:
			await _mouse(Vector2(8,extent.y-12))
			await create_timer(.2).timeout
			await _mouse(card.get_global_rect().get_center())
			await create_timer(.8).timeout
			_check(card._help[6].contains(MatchController.ability_play_warning(card.card_id)),"real hover keeps special effect warning " + String(card.card_id))
			_check(game.ability_panel._title.text.begins_with("Внимание:") and not game.ability_panel._title.text.contains("запрет"),"warning names this effect rather than lockout " + String(card.card_id))
			_check(root.get_visible_rect().encloses(game.ability_panel._panel.get_global_rect()),"warning panel remains inside viewport")
			await _capture("effect-warning-%s-%d" % [String(card.card_id),extent.x])
		_check(Engine.max_fps == 60 and root.unfocusable and root.mode == Window.MODE_MINIMIZED, "60FPS minimized unfocusable")
	game.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	await process_frame
	await process_frame
	print("BATTLE LOCKOUT UI: %d checks, %d failures" % [_checks,_failures])
	quit(1 if _failures else 0)

func _mouse(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	Input.parse_input_event(motion)
	await process_frame

func _click(pos: Vector2) -> void:
	await _mouse(pos)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func _capture(name0: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name0+".png"))
