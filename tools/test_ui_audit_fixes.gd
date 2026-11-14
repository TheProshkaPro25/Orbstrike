extends SceneTree
## UI-only regression of D01/D02/D03/D05 under the project's real window stretch.
var checks := 0
var failures := 0
var evidence: Array = []
const OUT := "res://build/checks/ui-audit-fixes-2026-11-06"

func _initialize() -> void:
	_run.call_deferred()

func frames(n: int = 4) -> void:
	for i in n: await process_frame

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)

func rect(c: Control) -> Array:
	var r := c.get_global_rect()
	return [r.position.x,r.position.y,r.size.x,r.size.y]

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	AudioServer.set_bus_mute(0,true)
	DeviceSettings.settings_path = OUT.path_join("settings.cfg")
	DeviceSettings.reload_settings()
	DeviceSettings.set_reduce_motion(true)
	CardDB.load_all()
	check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,"production canvas_items")
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND,"production aspect expand")
	root.content_scale_size = Vector2i(1280,720)
	var battle := BattleHud.new()
	var hud := HudUI.new()
	# Same draw order as Main.
	root.add_child(battle)
	root.add_child(hud)
	hud.setup_plates([Color.RED,Color.RED,Color.RED],[Color.BLUE,Color.BLUE,Color.BLUE])
	hud.set_names("Игрок","Длинное публичное имя соперника")
	var texture := GradientTexture2D.new()
	hud.set_portrait(0,texture)
	hud.set_portrait(1,texture)
	hud.set_captures(2,3)
	var menu := Button.new()
	menu.text = "В меню"
	menu.custom_minimum_size = Vector2(100,38)
	root.add_child(menu)
	VisualUtil.place(menu,1,0,-16,60)
	var plays: Array = [[0,&"ability_fire_drain"],[1,&"ability_klykar_bite"],[0,&"ability_dragnar_heart"],[1,&"ability_light_purge"],[0,&"ability_rogozhuk_shell"],[1,&"ability_stone_copy"]]
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size = dimensions
		await frames()
		# The window manager may clamp 1080p to its work area while minimized.
		# Test EXPAND against the actual physical client area, not the request.
		var physical := Vector2(root.size)
		var stretch := minf(physical.x / 1280.0, physical.y / 720.0)
		var expected := physical / stretch
		check(root.get_visible_rect().size.distance_to(expected) <= 1.5,"real logical viewport requested %s / physical %s: actual %s expected %s" % [dimensions,root.size,root.get_visible_rect().size,expected])
		for side in [0,1]:
			hud.own_panel.present(CardDB.creature(&"creature_gorgul_fire"),0,420)
			hud.opponent_panel.present(CardDB.creature(&"creature_gorgul_fire"),3,510)
			hud.own_panel.show_context("battle")
			hud.opponent_panel.show_context("battle")
			hud.set_battle_mode(true)
			battle.set_external_panels(hud.own_panel,hud.opponent_panel,side)
			battle.open(["Своя","Чужая"],[0,0],[420,510])
			battle.set_chain(plays,[true,true],0,[plays[0]],[3,3],["Закрыто способностью",""])
			await frames()
			var chip_rects: Array = []
			for chip in battle._chain.get_children():
				chip_rects.append(rect(chip))
				check(root.get_visible_rect().encloses(chip.get_global_rect()),"chip stays in viewport")
				for blocker in [hud.own_panel,hud.opponent_panel,battle._counts[0],battle._counts[1]]:
					check(not chip.get_global_rect().intersects(blocker.get_global_rect()),"chip avoids portrait/G/counter")
				if chip.help.is_empty(): continue
				var motion := InputEventMouseMotion.new()
				motion.position = chip.get_global_rect().get_center()
				root.push_input(motion,true)
				await process_frame
				check(root.gui_get_hovered_control() == chip,"real hover reaches each chip: %s at %s got %s" % [chip.name,chip.get_global_rect(),root.gui_get_hovered_control()])
				chip.grab_focus()
				await create_timer(.36).timeout
				check(is_instance_valid(battle._chain_help) and battle._help_chip == chip,"focus opens full effect/cancel state")
				if is_instance_valid(battle._chain_help):
					check(root.get_visible_rect().encloses(battle._chain_help.get_global_rect()),"full disclosure inside viewport")
				chip.release_focus()
				battle._clear_chain_help()
				await frames(2)
			evidence.append({"physical":str(dimensions),"logical":str(expected),"opponent_battle_side":side,"chain":rect(battle._chain),"chips":chip_rects,"enemy_summary":rect(hud._plates[1])})
			hud.own_panel.hide_context()
			hud.opponent_panel.hide_context()
			hud.set_battle_mode(false)
			await frames()
			check(hud._plates[1].is_visible_in_tree(),"public opponent summary persists outside reveal/battle")
			check(not hud.opponent_panel.is_visible_in_tree(),"creature context stays hidden")
			check(hud._plates[1]._gates.text == "Ворота: 3","captured gates remain public")
			for toolbar in [hud._help_btn,hud._tempo,menu,hud._turn_clip]:
				check(not hud._plates[1].get_global_rect().intersects(toolbar.get_global_rect()),"public summary avoids %s: %s vs %s" % [toolbar.name,hud._plates[1].get_global_rect(),toolbar.get_global_rect()])
			check(root.get_visible_rect().encloses(hud._plates[1].get_global_rect()),"long-name summary fits")
	# Normal motion and late-show startup must settle at the same hit rectangles.
	DeviceSettings.set_reduce_motion(false)
	hud.begin_match_interface()
	hud.own_panel.present(CardDB.creature(&"creature_gorgul_fire"),0,420)
	hud.opponent_panel.present(CardDB.creature(&"creature_gorgul_fire"),3,510)
	hud.own_panel.show_context("battle")
	hud.opponent_panel.show_context("battle")
	battle.open(["Своя","Чужая"],[0,0],[420,510])
	battle.set_chain(plays,[false,false],0,[],[3,3])
	await frames()
	var before: Array = []
	for chip in battle._chain.get_children(): before.append(chip.get_global_rect())
	await create_timer(1.0).timeout
	for i in battle._chain.get_child_count():
		var chip: Control = battle._chain.get_child(i)
		check(chip.get_global_rect() == before[i] and is_equal_approx(chip.modulate.a,1.0),"normal-motion chip settles: %s → %s alpha%s" % [before[i],chip.get_global_rect(),chip.modulate.a])
		var motion := InputEventMouseMotion.new()
		motion.position = chip.get_global_rect().get_center()
		root.push_input(motion,true)
		await process_frame
		check(root.gui_get_hovered_control() == chip,"startup overlays leave chip input reachable")
	check(hud._plates[1].is_visible_in_tree() and is_equal_approx(hud._plates[1].modulate.a,1.0),"late-show public summary settles visible")
	var kept := battle._chain.get_child(0)
	battle.set_chain(plays,[false,false],1,[],[3,3])
	check(battle._chain.get_child(0) == kept,"same network snapshot preserves hovered/focused control: lane%s cached%s" % [battle._chain.size.x,battle._chain_width])
	battle.set_external_panels(null,null,-1)
	battle.queue_free()
	hud.queue_free()
	menu.queue_free()
	await frames()
	await shop()
	var text := ""
	for section in HelpOverlay.SECTIONS: text += section[1]
	check(not text.contains("всегда попадает") and not text.contains("сама долетит"),"help does not promise guaranteed landing")
	check(not FileAccess.get_file_as_string("res://scenes/main.gd").contains("Сфера сама долетит"),"live coach does not promise guaranteed landing")
	check(text.contains("промах") and text.contains("фактическая точка остановки"),"help explains actual landing/miss")
	var file := FileAccess.open(OUT.path_join("regression.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"display":DisplayServer.get_name(),"visual_acceptance":false,"observations":evidence},"\t"))
	file.close()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames()
	print("UI audit fixes: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func shop() -> void:
	var career := Career.create("fire",1,773,"Audit fixes","")
	var panel := CareerPanel.new()
	root.add_child(panel)
	panel.display(career)
	var deck := CardDB.build_deck(panel._team,panel._ids(CardDB.GATE_CLASSES),panel._ids(CardDB.ABILITY_CLASSES))
	check(career.start_cup(deck,panel._levels) == OK,"fixture registers cup")
	panel.display(career)
	panel._shop_kind = 1
	panel._switch_tab(2)
	await frames()
	var offers := panel.find_children("CareerBuy_*","Button",true,false)
	check(not offers.is_empty(),"shop items remain browsable")
	var unowned := 0
	for buy in offers:
		check(buy.disabled,"all active-cup purchases disabled")
		if buy.text != "Куплено":
			unowned += 1
			check(buy.tooltip_text.contains("завершения кубка"),"disabled offer explains cup lock")
	check(unowned > 0 and panel.find_child("CareerShopLocked",true,false) != null,"lock explained before clicking")
	# Completion opens shop immediately; the roster remains a saved cup snapshot.
	career.cup.state.completed = true
	panel._redraw()
	await frames()
	var enabled := 0
	for buy in panel.find_children("CareerBuy_*","Button",true,false):
		if not buy.disabled: enabled += 1
	check(enabled > 0 and panel.find_child("CareerShopLocked",true,false) == null,"completed cup unlocks affordable purchases")
	panel.queue_free()
	await frames()
