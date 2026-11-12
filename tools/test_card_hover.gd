extends SceneTree
## Real card/hand, focus, battle-chip, HUD and tournament theme regression. No models/Boot.
class TeamFixture extends TeamMenu:
	func _show_preview(_id: StringName, _pose: bool) -> void: pass

var out := "res://build/checks/presentation/card-hover"
var checks := 0
var failures := 0
var report := {"focus_batches":[],"layouts":[],"scope":"source UI only, no Boot/models/match/permanent-hang claim"}
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1;printerr("FAIL: "+why)
func frames(n: int=3) -> void:
	for i in n: await process_frame
func mouse(at: Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=at;event.global_position=at;root.push_input(event,true)
	await frames()
func layers(card: CardView) -> int:
	var count:=0
	for child in card.get_children():
		if child is CanvasLayer and not child.is_queued_for_deletion():count+=1
	return count
func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(out.path_join(name+".png"))==OK,"PNG "+name)
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	DeviceSettings.settings_path=out.path_join("isolated-settings.cfg");DeviceSettings.reload_settings()
	CardDB.load_all();root.content_scale_size=Vector2i(1280,720)
	root.gui_embed_subwindows = true # Keep real dialogs/tooltips inside the offscreen test viewport.
	var bg:=ColorRect.new();bg.color=Color("171c29");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(bg)
	var setup:=SetupPanel.new();root.add_child(setup)
	var defs:Array=[]
	for id in CardDB.arena_ids():defs.append(CardDB.card(id))
	setup.begin(defs,[0,1],true)
	var outside:=Button.new();outside.text="Вне карты";outside.position=Vector2(25,150);root.add_child(outside)
	await frames()
	var card:CardView=setup._card_buttons.values()[0]
	for batch in 3:
		var start:=Time.get_ticks_usec()
		for i in 30:card.grab_focus();outside.grab_focus()
		card.grab_focus();await frames(2)
		var count:=layers(card);check(count==1,"bounded focus layer batch%d got%d"%[batch,count])
		report.focus_batches.append({"batch":batch,"layers":count,"elapsed_ms":(Time.get_ticks_usec()-start)/1000.0})
	outside.grab_focus();await frames();check(layers(card)==0,"blur clears all disclosures")
	await mouse(card.get_global_rect().get_center());check(card.is_hovered(),"real pointer enters hand card")
	card.grab_focus();await frames();check(layers(card)==0,"mouse focus does not add keyboard disclosure")
	await mouse(Vector2(30,150));check(layers(card)==0,"pointer exit cannot pin focused popup")
	for i in 30:
		await mouse(card.get_global_rect().get_center())
		await mouse(Vector2(30,150))
	check(layers(card)==0,"thirty pointer enter/exit cycles retain no layer")
	var hint_script=preload("res://scenes/ui/card_hint.gd")
	var before_native:int=hint_script.build_count
	await mouse(card.get_global_rect().get_center())
	await create_timer(.4).timeout
	check(hint_script.build_count==before_native+1,"one native tooltip after real pointer dwell")
	await frames(12)
	check(hint_script.build_count==before_native+1,"stationary hover does not rebuild")
	await mouse(Vector2(30,150))
	check(layers(card)==0,"real pointer leave clears any focus duplicate")
	# Pending focus callback cannot resurrect a removed/hidden card.
	card.grab_focus();card.hide();await frames();check(layers(card)==0,"hide with pending focus callback")
	card.show();outside.grab_focus();await frames()

	# A native tooltip is plain text; constructing it does not recursively build CardViews.
	var start:=Time.get_ticks_usec();var max_height:=0.0;var max_width:=0.0
	for id in CardDB.arena_ids()+CardDB.ability_ids():
		var lines:=UiTheme.card_help(CardDB.card(id));var hint:=UiTheme.help_panel(lines)
		check(not hint is CardView,"no nested shader card for "+str(id))
		check(hint._body.text.contains(CardDB.card(id).full_text()),"full effect preserved "+str(id))
		check(hint._body.text.contains(str(lines[5])),"timing preserved "+str(id))
		max_height=maxf(max_height,hint.get_combined_minimum_size().y);max_width=maxf(max_width,hint.get_combined_minimum_size().x)
		hint.free()
	report.catalog_build_ms=(Time.get_ticks_usec()-start)/1000.0;report.max_hint_minimum=Vector2(max_width,max_height)
	check(max_width<=340 and max_height<=340,"compact catalog hints")
	var hud:=HudUI.new();root.add_child(hud);hud.setup_plates([Color.RED],[Color.BLUE]);var texture:=GradientTexture2D.new();hud.set_portrait(0,texture);hud.set_portrait(1,texture)
	var game:Node=load("res://scenes/main.gd").new();var canvas:=CanvasLayer.new();root.add_child(canvas);game.ui_layer=canvas
	for style in [DeviceSettings.CLASSIC,DeviceSettings.DEVICE]:
		DeviceSettings.set_style(style)
		for reduced in [false,true]:
			DeviceSettings.set_reduce_motion(reduced)
			for dimensions in [Vector2i(960,540),Vector2i(1280,720)]:
				root.size=dimensions;await frames()
				hud.set_names("Игрок","Очень длинное имя соперника Рэн Кадзэхара")
				for phase in ["появляется","бросает сферу на дальние ворота","приземляется","начинает бой"]:
					hud.set_hint("Очень длинное имя соперника Рэн Кадзэхара "+phase+". Выберите карту и дождитесь завершения действия.")
					await frames()
					var rect:=hud._hint_plate.get_global_rect()
					for plate in hud._plates:check(not rect.intersects(plate.get_global_rect()),"announcement avoids fighter portrait "+str(dimensions)+phase)
					check(root.get_visible_rect().encloses(rect),"announcement stays in viewport")
				var lines:=UiTheme.card_help(defs[0]);var hint:=UiTheme.help_panel(lines);root.add_child(hint);hint.position=Vector2(360,240);await frames()
				check(hint.size.x<=340 and hint.size.y<=340,"hint rendered bound")
				var label:=("device" if style==DeviceSettings.DEVICE else "classic")+"-%d-"%dimensions.x+str(reduced)
				report.layouts.append({"label":label,"hint":hud._hint_plate.get_global_rect(),"tooltip":hint.size})
				await shot(label);hint.queue_free();await frames()
	# Overflow in the actual played-card chain: PgDn remains available and exit cannot stick.
	hud.hide();setup.hide()
	var battle:=BattleHud.new();root.add_child(battle)
	battle.open(["Своя","Чужая"],[0,1],[420,510])
	battle.set_chain([[0,&"ability_fire_drain"]],[false,false],0,[],[1,1])
	await frames()
	var chip= battle._chain.get_child(0)
	chip.help[4] = str(chip.help[4]) + (" Дополнительные условия для проверки прокрутки полного текста.").repeat(50)
	chip.grab_focus();await create_timer(.35).timeout;await frames()
	check(is_instance_valid(battle._chain_help),"real focused chain disclosure opens")
	var overflow=battle._chain_help.get_child(0)
	var value_before:float=overflow._scroll.get_v_scroll_bar().value
	var page:=InputEventKey.new();page.keycode=KEY_PAGEDOWN;page.pressed=true;root.push_input(page,true)
	await frames()
	check(overflow._scroll.get_v_scroll_bar().value>value_before,"chain PgDn exposes overflowing full conditions")
	await shot("chain-overflow-pagedown")
	await mouse(chip.get_global_rect().get_center());await create_timer(.35).timeout
	var old_rect:Rect2=battle._chain_help.get_global_rect()
	await mouse(old_rect.get_center());await create_timer(.2).timeout;await frames()
	check(not is_instance_valid(battle._chain_help),"mouse leave source onto disclosure cannot pin chain popup")
	battle.queue_free();await frames()
	# Actual Main registration/exit handlers, cancel only: no save/match/model creation.
	var team:=TeamFixture.new();root.add_child(team);game.team_menu=team;await frames()
	game.modes.configure(team,hud,canvas,game.rng)
	var deck:=CardDB.preset_deck(0);var ids:=Tournament.deck_ids(deck)
	var creature_ids:Array[StringName]=[];var gate_ids:Array[StringName]=[];var ability_ids:Array[StringName]=[]
	for id in ids[0]:creature_ids.append(StringName(id))
	for id in ids[1]:gate_ids.append(StringName(id))
	for id in ids[2]:ability_ids.append(StringName(id))
	for style in [DeviceSettings.CLASSIC,DeviceSettings.DEVICE]:
		DeviceSettings.set_style(style);await frames()
		game._register_tournament(creature_ids,gate_ids,ability_ids);await frames()
		var dialog:ConfirmationDialog=canvas.get_child(canvas.get_child_count()-1)
		check(dialog.theme==UiTheme.get_theme(),"registration shares current theme")
		check(dialog.get_ok_button().get_theme_stylebox("normal")==UiTheme.get_theme().get_stylebox("normal","Button"),"real tournament entry button theme")
		await shot("tournament-entry-"+str(style))
		dialog.get_cancel_button().pressed.emit();await frames()
		var exit:Button=game._make_tournament_exit_button();canvas.add_child(exit)
		check(exit.theme==UiTheme.get_theme(),"real tournament exit button theme")
		exit.pressed.emit();await frames()
		dialog=canvas.get_child(canvas.get_child_count()-1)
		check(dialog.theme==UiTheme.get_theme(),"exit confirmation shares theme")
		await shot("tournament-exit-"+str(style))
		dialog.get_cancel_button().pressed.emit();exit.queue_free();await frames()
		check(game.tournament==null,"cancel never creates/changes tournament")
	await _post_ui_checks()
	team.queue_free();hud.queue_free();setup.queue_free();outside.queue_free();bg.queue_free();canvas.queue_free();game.free();await frames()

	if is_instance_valid(GameLoading._inst):GameLoading._inst.queue_free()
	await frames(5)
	if is_instance_valid(SoundFx._inst):SoundFx._inst.queue_free()
	await frames();report.checks=checks;report.failures=failures
	var file:=FileAccess.open(out.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n");file.close()
	print("CARD HOVER ",checks,"/",failures);quit(1 if failures else 0)


func _post_ui_checks() -> void:
	pass
