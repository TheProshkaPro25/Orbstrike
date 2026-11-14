extends SceneTree
## Обе стороны жребия через очередь постановки и настоящий HUD, без Boot.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	CardDB.load_all()
	var output := "res://build/checks/presentation/selected-standoff-notice/standoff-notice"
	DirAccess.make_dir_recursive_absolute(output)
	var longest: CreatureDef
	for id in CardDB.creature_ids():
		var creature := CardDB.creature(id)
		if longest == null or creature.display_name.length() > longest.display_name.length():
			longest = creature
	var deck := CardDB.preset_deck(0)
	var controller := MatchController.new(deck, deck, 0)
	var attackers := [controller.state.players[0].creature_uids[0], controller.state.players[1].creature_uids[0]]
	var notices := [
		"Тупик. По жребию на другие ворота идёт %s из вашей команды." % longest.display_name,
		"Тупик. По жребию на другие ворота идёт %s из команды соперника." % longest.display_name,
	]
	var events := EventPlayer.new()
	root.add_child(events)
	var presentation := MatchPresentation.new()
	root.add_child(presentation)
	presentation.bind_controller(controller)
	presentation.events = events
	for uid in attackers:
		presentation.state.definitions[uid] = longest
	RenderingServer.set_default_clear_color(Color("151c2b"))
	for extent in [Vector2i(960, 540), Vector2i(1280, 720)]:
		root.size = extent
		root.content_scale_size = extent
		var hud := HudUI.new()
		root.add_child(hud)
		hud.setup_plates([Color.RED, Color.RED, Color.RED], [Color.BLUE, Color.BLUE, Color.BLUE])
		presentation.hud = hud
		for battle in [false, true]:
			hud.set_battle_mode(battle)
			for side in 2:
				presentation.on_standoff(attackers[side], attackers[1 - side])
				for frame in 3: await process_frame
				await RenderingServer.frame_post_draw
				var label: Label = hud._flash
				var rect := label.get_global_rect()
				check(label.visible and label.text == notices[side], "указана сторона атакующего")
				check(label.get_visible_line_count() == label.get_line_count(), "все строки доступны")
				check(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= extent.x and rect.end.y <= extent.y, "уведомление внутри экрана")
				check(Engine.max_fps == 60 and root.unfocusable and root.mode == Window.MODE_MINIMIZED, "60FPS, свёрнуто, без фокуса")
				var filename := "%dx%d-%s-%s.png" % [extent.x, extent.y, "battle" if battle else "field", "player" if side == 0 else "opponent"]
				check(root.get_texture().get_image().save_png(output.path_join(filename)) == OK, "свежий PNG сохранён")
				hud._skip_flag = true
				await events.drained
				check(not label.visible, "очередь убирает уведомление перед перемещением")
		hud.free()
	var report := FileAccess.open(output.path_join("summary.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "notices": notices, "scope": "Обе стороны жребия через обработчик локальной постановки и настоящий HUD в field/battle при 960×540 и 1280×720. Без запуска полного матча и Boot."}, "\t"))
	print("STANDOFF NOTICE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
