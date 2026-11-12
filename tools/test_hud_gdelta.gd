extends SceneTree
## UI only: actual advancing normal/reduced tweens and post-draw PNGs. No models.
var output := "res://build/checks/presentation/hud-gdelta"
var checks := 0
var failures := 0
var viewport: SubViewport
var hud: HudUI
var battle: BattleHud
var report := {"states": [], "captures": [], "scope": "UI only; no model or match run"}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func frames(count: int) -> void:
	for _i in count: await process_frame

func sample(label: String) -> void:
	var controls: Array[Control] = [hud.own_panel, hud.opponent_panel, battle._chain, hud._turn_clip, hud._phase_label]
	var values: Array = []
	for control in controls:
		var rect := control.get_global_rect()
		var alpha := control.modulate.a * control.self_modulate.a
		check(control.is_visible_in_tree() and alpha > .98, label + " visible/alpha " + String(control.name))
		check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(rect), label + " rect " + String(control.name))
		values.append({"node": String(control.name), "visible": control.is_visible_in_tree(), "alpha": alpha, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	check(battle._chain.get_child_count() == 8, label + " six cards and both pass chips retained")
	report["states"].append({"label": label, "controls": values, "own_power": hud.own_panel._power.text, "enemy_power": hud.opponent_panel._power.text})

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	# SceneTree.process_frame precedes processing/layout and is not a draw barrier.
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image.get_size() == viewport.size, label + " complete viewport")
	# Detect a black/incomplete render while the Controls still report visible.
	for panel in [hud.own_panel, hud.opponent_panel]:
		var rect: Rect2 = panel._portrait.get_global_rect()
		var maximum := 0.0
		for yy in range(4, int(rect.size.y)-4, 6):
			for xx in range(4, int(rect.size.x)-4, 6):
				maximum = maxf(maximum, image.get_pixel(int(rect.position.x)+xx, int(rect.position.y)+yy).get_luminance())
		check(maximum > .5, label + " rendered portrait anchor " + String(panel.name))
	var path := output.path_join(label + ".png")
	check(image.save_png(path) == OK, label + " save post-draw")
	report["captures"].append({"label": label, "sha256": FileAccess.get_sha256(path)})

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	DeviceSettings.settings_path = output.path_join("isolated-settings.cfg")
	DeviceSettings.reload_settings()
	DeviceSettings.set_style(DeviceSettings.DEVICE)
	CardDB.load_all()
	CreaturePortrait._prepare_reference(&"creature_ratnik_light")
	CreaturePortrait._prepare_reference(&"creature_kolossar_shadow")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(viewport.size)
	background.color = Color("171c24")
	viewport.add_child(background)
	battle = BattleHud.new()
	hud = HudUI.new()
	viewport.add_child(battle)
	viewport.add_child(hud)
	hud.setup_plates([Color.RED], [Color.BLUE])
	hud.set_phase(MatchController.Phase.ABILITY_WINDOW)
	hud.set_status(2, 0, 3, 3)
	var plays: Array = [[0,&"ability_fire_drain"],[1,&"ability_klykar_bite"],[0,&"ability_dragnar_heart"],[1,&"ability_light_purge"],[0,&"ability_rogozhuk_shell"],[1,&"ability_stone_copy"]]
	for reduced in [false,true]:
		DeviceSettings.set_reduce_motion(reduced)
		hud.own_panel.present(CardDB.creature(&"creature_ratnik_light"),0,420)
		hud.opponent_panel.present(CardDB.creature(&"creature_kolossar_shadow"),1,510)
		hud.own_panel.show_context("battle")
		hud.opponent_panel.show_context("battle")
		hud.set_battle_mode(true)
		battle.set_external_panels(hud.own_panel,hud.opponent_panel,1)
		battle.open(["Своя","Чужая"],[0,0],[420,510])
		battle.set_chain(plays,[true,true],0,[plays[0]],[3,3],["Закрыто способностью",""])
		await frames(48)
		var label := "reduced" + str(reduced)
		sample(label + "-settled")
		await capture(label + "-settled")
		# Same two presentation calls as Main._anim_ability_msg.
		battle.set_powers([680,390])
		hud.own_panel.set_power(680)
		hud.opponent_panel.set_power(390)
		for frame in 30:
			await process_frame
			if frame in [1,8,12,24]: sample(label + "-delta-frame" + str(frame))
			if frame == 8:
				check(battle._floating_numbers.size() == 2, label + " simultaneous deltas alive")
				check(battle._floating_numbers.map(func(number: Label) -> String: return number.text) == ["+260", "−120"], label + " signed deltas display numbers only")
				if not reduced:
					check(hud.own_panel._power_tween != null and hud.own_panel._power_tween.get_total_elapsed_time() > 0.0, "normal tween actually advances")
				await capture(label + "-delta")
		check(hud.own_panel._power.text == "680" and hud.opponent_panel._power.text == "390", label + " exact final public powers")
		battle.close()
		await frames(18)
	hud.queue_free()
	battle.queue_free()
	viewport.queue_free()
	await frames(3)
	report["checks"] = checks
	report["failures"] = failures
	report["display"] = DisplayServer.get_name()
	report["rendered"] = DisplayServer.get_name() != "headless"
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ") + "\n")
	file.close()
	print("HUD Gdelta: ",checks,"/",failures,"; rendered=",report["rendered"])
	quit(1 if failures else 0)
