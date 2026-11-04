extends "res://tests/card_readability_tests.gd"
## Only changed recovery text and representative rendered cards; no full catalogue run.
func _run() -> void:
	CardDB.load_all()
	out_dir = "res://build/checks/presentation/selected-last-rush-ui/last-rush-ui"
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.theme = UiTheme.get_theme()
	RenderingServer.set_default_clear_color(Color(.025, .035, .06))
	host = Control.new()
	root.add_child(host)
	for id in CardDB.ability_ids():
		var card := CardDB.card(id)
		var text: String = UiTheme.card_help(card)[5]
		if CardEffects.returns_to_hand(card):
			check(text.contains("После боя — в руку."), "explicit return remains: " + String(id))
		elif MatchRules.last_rush_returns(card):
			check(CardDB.card_class(card) == &"blue" and text.contains("у последнего существа — в руку"), "only blue rush text: " + String(id))
		else:
			check(text.contains("даже у последнего существа"), "full recovery explained: " + String(id))
	var selected := [&"ability_tide_hush", &"ability_levian_coil", &"ability_fire_last", &"ability_gale_swap", &"ability_klykar_bite", &"ability_stone_footing"]
	for extent in [Vector2i(1280,720), Vector2i(960,540)]:
		root.size = extent
		root.content_scale_size = extent
		var size_px := Vector2(360,504) if extent.x == 1280 else Vector2(280,392)
		for row in 2:
			clear()
			for i in 3:
				var cv := CardView.new().for_card(CardDB.card(selected[row*3+i]), size_px, true)
				cv.position = Vector2(24 + i*(size_px.x+20), 20)
				host.add_child(cv)
			await process_frame
			for cv in host.get_children(): inspect_card(cv, true)
			check(Engine.max_fps == 60 and root.unfocusable and root.mode == Window.MODE_MINIMIZED, "60FPS minimized nonfocusable")
			await capture("last-rush-%d-%d" % [extent.x, row])
	clear()
	var panel := AbilityPanel.new()
	host.add_child(panel)
	panel.show_options([], "Бой", {"moment": &"battle"})
	check(panel._panel.tooltip_text.contains("только синие") and panel._panel.tooltip_text.contains("даже после отмены"), "battle panel recovery matches rules")
	var help_text := ""
	for section in HelpOverlay.SECTIONS:
		if section[0] == "Способности": help_text = section[1]
	check(help_text.contains("только синие"), "help explains recovery rule")
	var f := FileAccess.open(out_dir.path_join("summary.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failures": failures, "scope": "60 tooltip contracts, six representative complete cards at960/1280, battle tooltip/help; no match or entire catalogue visual audit"}, "\t"))
	print("LAST RUSH UI: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
