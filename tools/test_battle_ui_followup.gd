extends SceneTree
## Author follow-up: dismiss battle hints and lay out the actual tournament exit.
var checks := 0
var failures := 0
var out := "res://build/checks/presentation/battle-ui-followup"

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + why)
func frames(n: int = 3) -> void:
	for i in n: await process_frame
func mouse(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)
	await frames()
func escape() -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_ESCAPE
	root.push_input(event, true)
	await frames()
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	DeviceSettings.settings_path = out.path_join("isolated-settings.cfg")
	DeviceSettings.reload_settings()
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	CardDB.load_all()
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	var hud := HudUI.new()
	canvas.add_child(hud)
	hud.setup_plates([Color.RED], [Color.BLUE])
	var portrait := GradientTexture2D.new()
	hud.set_portrait(0, portrait)
	hud.set_portrait(1, portrait)
	hud.set_names("Игрок", "Соперник")
	hud.set_status(1, 0, 3, 3)
	hud.log_event("Существо ждёт броска")
	var battle := BattleHud.new()
	canvas.add_child(battle)
	var game: Node = load("res://scenes/main.gd").new()
	game.ui_layer = canvas
	game.hud = hud
	game._duel_menu = Button.new()
	canvas.add_child(game._duel_menu)
	game._duel_menu.hide()
	var exit: Button = game._make_tournament_exit_button()
	game._tournament_exit = exit
	canvas.add_child(exit)
	hud.battle_mode_changed.connect(game._place_duel_menu)
	for style in [DeviceSettings.CLASSIC, DeviceSettings.DEVICE]:
		DeviceSettings.set_style(style)
		for dimensions in [Vector2i(960, 540), Vector2i(1280, 720)]:
			root.size = dimensions
			root.content_scale_size = dimensions
			for fighting in [false, true]:
				hud.set_battle_mode(fighting)
				if fighting: battle.open(["Атакующий", "Защитник"], [0, 1], [420, 390])
				else: battle.close()
				game._place_duel_menu(fighting)
				await frames(20)
				var rect := exit.get_global_rect()
				check(root.get_visible_rect().encloses(rect), "tournament exit stays in viewport")
				var obstacles: Array = [hud._help_btn, hud._tempo, hud._phase_label, hud._final_tag]
				obstacles.append_array(battle._plates if fighting else hud._plates)
				if not fighting: obstacles.append(hud._log_box)
				for control: Control in obstacles:
					if control.is_visible_in_tree():
						check(not rect.intersects(control.get_global_rect()), "tournament exit avoids " + str(control.name) + " style=" + str(style) + " battle=" + str(fighting) + " exit=" + str(rect) + " obstacle=" + str(control.get_global_rect()))
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(out.path_join("exit-%s-%s-%s.png" % [style, dimensions.x, fighting]))
	# Keyboard disclosure stays owned by focus only while using the keyboard.
	var card := CardView.new().for_card(CardDB.card(&"ability_fire_drain"))
	card.position = Vector2(400, 330)
	canvas.add_child(card)
	await mouse(Vector2(10, 500))
	card.grab_focus()
	await frames()
	check(is_instance_valid(card._focus_disclosure), "keyboard opens full card conditions")
	await mouse(Vector2(600, 500))
	check(not is_instance_valid(card._focus_disclosure), "switching to arena pointer dismisses keyboard disclosure")
	card.queue_free()
	await frames()
	# Hovered played-card help must stay dismissed after Esc until a new hover.
	battle.set_chain([[0, &"ability_fire_drain"]], [false, false], 0)
	await frames()
	var chip: Control = battle._chain.get_child(0)
	await mouse(chip.get_global_rect().get_center())
	await create_timer(.4).timeout
	check(is_instance_valid(battle._chain_help), "battle hover opens")
	await escape()
	await create_timer(.4).timeout
	check(not is_instance_valid(battle._chain_help), "Esc dismisses hovered battle help without immediate reopening")
	await mouse(Vector2(10, 500))
	await create_timer(.2).timeout
	await mouse(chip.get_global_rect().get_center())
	await create_timer(.4).timeout
	check(is_instance_valid(battle._chain_help), "fresh hover can reopen dismissed conditions")
	battle.close()
	check(not is_instance_valid(battle._chain_help), "battle close clears help")
	canvas.queue_free()
	game.free()
	await frames(5)
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames()
	print("BATTLE UI FOLLOWUP ", checks, "/", failures)
	quit(1 if failures else 0)
