extends SceneTree
## Real 2D panel + Main presentation calls on procedural actors; no GLB loading.
var checks := 0
var failures := 0
var output := "res://build/checks/presentation/opponent-panel"
var game: Node
var hud: HudUI
var battle: BattleHud
var abilities: AbilityPanel
var field: Node3D
var actor: CreatureBall
var other: CreatureBall
var own_actor: CreatureBall
var own_panel: OpponentPanel

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
func frames(count: int = 2) -> void:
	for i in count: await process_frame

func _run() -> void:
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	AudioServer.set_bus_mute(0,true)
	DeviceSettings.settings_path = "user://opponent-panel-test.cfg"
	DeviceSettings.reload_settings()
	DeviceSettings.set_style(DeviceSettings.DEVICE)
	DeviceSettings.set_reduce_motion(true)
	CardDB.load_all()
	game = load("res://scenes/main.gd").new()
	hud = HudUI.new()
	battle = BattleHud.new()
	abilities = AbilityPanel.new()
	root.add_child(hud)
	root.add_child(battle)
	root.add_child(abilities)
	game.hud = hud
	game.battle_hud = battle
	game.ability_panel = abilities
	game._duel_menu = Button.new()
	game._duel_menu.text = "В меню"
	root.add_child(game._duel_menu)
	game.ctrl = MatchController.new(CardDB.preset_deck(0),CardDB.preset_deck(1),47)
	game._index_creatures()
	field = Node3D.new()
	root.add_child(field)
	actor = _make_actor(3)
	other = _make_actor(4)
	own_actor = _make_actor(0)
	game.balls = {0:own_actor,3:actor,4:other}
	hud.setup_plates([Color.RED],[Color.BLUE])
	await frames()
	game._place_duel_menu(false)
	var panel: OpponentPanel = hud.opponent_panel
	own_panel = hud.own_panel
	check(not panel.visible and panel._uid == -1 and panel._portrait._viewport == null and panel._portrait._definition == null and panel._power.text.is_empty(),"unselected opponent is genuinely unknown")
	check(not own_panel.visible and own_panel._uid == -1 and own_panel._portrait._definition == null and own_panel._power.text.is_empty(),"unselected own creature also leaves no empty panel")
	own_actor._open = false
	game._public_creature_opened(0)
	check(not own_panel.visible and own_panel._definition == null and own_panel._power.text.is_empty(),"closed own sphere does not open a contextual block")
	actor._open = false
	game._public_creature_opened(3)
	check(not panel.visible and panel._definition == null and panel._portrait._viewport == null and panel._power.text.is_empty(),"closed sphere does not reveal roster identity or G")
	actor._open = true
	game._public_creature_opened(3)
	check(panel._uid == 3 and panel._definition.id == actor.def.id and panel._current_power == PowerCalc.base_power(game.ctrl.get_view(0),3),"revealed current actor uses public PowerCalc base")
	own_actor._open = true
	game._public_creature_opened(0)
	check(own_panel.visible and own_panel._uid == 0 and own_panel._definition.id == own_actor.def.id and own_panel._current_power == PowerCalc.base_power(game.ctrl.get_view(0),0),"own public reveal uses same actual actor and PowerCalc base")
	game._present_battle_opponent(0,3,[400,610])
	battle.open(["Своя","Чужая"],[0,1],[400,610])
	check(panel._power.text == "610 G" and own_panel._power.text == "400 G" and battle.opponent_side == 1 and not battle._plates[0].visible and not battle._plates[1].visible,"both exact battle powers replace duplicate plates")
	check(battle._power_anchors[0] == own_panel and battle._power_anchors[1] == panel,"defending opponent maps external anchors by actual battle sides")
	game._present_battle_opponent(3,0,[720,400])
	check(panel._power.text == "720 G" and own_panel._power.text == "400 G" and battle.opponent_side == 0 and not battle._plates[0].visible and not battle._plates[1].visible,"attacking opponent uses index0 while own defender remains left")
	check(battle._power_anchors[0] == panel and battle._power_anchors[1] == own_panel,"swapped attack order reverses battle anchors without swapping screen ownership")
	game._battle_uids.assign([0,4])
	game._present_battle_powers([420,510])
	check(panel._uid == 4 and panel._power.text == "510 G" and own_panel._uid == 0 and own_panel._power.text == "420 G","swapped opponent replaces stale actor and both G values remain exact")
	game._finish_opponent_battle()
	check(not panel.visible and not own_panel.visible and panel._uid == -1 and own_panel._uid == -1 and panel._portrait._actor == null and own_panel._portrait._actor == null,"leaving battle removes both contextual blocks and actor bindings")
	game._present_battle_opponent(0,4,[420,510])
	battle.open(["Своя","Чужая"],[0,1],[420,510])
	game._focus_labels([])
	check(not actor._label_allowed and not other._label_allowed and not own_actor._label_allowed,"world labels of both owners are suppressed in electronic mode")
	await _check_layout(panel)
	await _check_portrait(panel)
	await _check_power_events(panel)
	DeviceSettings.set_reduce_motion(false)
	panel.set_power(710)
	check(panel._power_tween != null,"finite power response starts")
	root.size.x -= 1
	await frames()
	check(panel._power.text == "710 G" and panel.modulate.a == 1 and panel._power_tween == null,"resize settles latest G and opacity")
	panel.feedback("activation",1)
	DeviceSettings.set_reduce_motion(true)
	check(panel._accent_tween == null and panel.modulate.a == 1,"reduced motion cancels effects and settles")
	DeviceSettings.set_style(DeviceSettings.CLASSIC)
	game._opponent_style_changed(DeviceSettings.CLASSIC)
	await frames()
	check(not panel.visible and not own_panel.visible and battle._plates[0].visible and battle._plates[1].visible,"classic hides both context panels and restores original fight plates")
	check(actor._label_allowed and other._label_allowed and own_actor._label_allowed,"classic restores world labels for both owners")
	check(battle._counts[0].get_parent() == battle._plate_contents[0] and battle._counts[1].get_parent() == battle._plate_contents[1],"classic returns both ability counters to their original plates")
	DeviceSettings.set_style(DeviceSettings.DEVICE)
	game._opponent_style_changed(DeviceSettings.DEVICE)
	await frames()
	check(panel.visible and panel._uid == 4 and own_panel.visible and own_panel._uid == 0,"theme toggle restores both actual public battle creatures")
	var parking := Control.new()
	root.add_child(parking)
	hud.reparent(parking)
	hud.reparent(root)
	await frames()
	DeviceSettings.set_style(DeviceSettings.CLASSIC)
	await frames()
	check(not panel.visible and not own_panel.visible,"resident reparent retains preference lifecycle for both panels")
	DeviceSettings.set_style(DeviceSettings.DEVICE)
	game._opponent_style_changed(DeviceSettings.DEVICE)
	await frames()
	game._clear_opponent_panel()
	game._clear_own_panel()
	check(not panel.visible and panel._uid == -1 and panel._power.text.is_empty() and panel._portrait._actor == null,"reset/release forgets actor and private stale state")
	check(not own_panel.visible and own_panel._uid == -1 and own_panel._power.text.is_empty() and own_panel._portrait._actor == null,"reset/release clears own panel too")
	await _check_context_and_motion(panel)
	await _check_sound_contract()
	game._finish_opponent_battle()
	battle.close()
	await frames()
	check(battle._floating_numbers.is_empty() and battle._feedback_tweens.is_empty(),"closing battle frees every signed notice and feedback tween")
	check(not panel.visible and not own_panel.visible and battle._power_anchors == [null,null],"teardown clears external anchors and both public identities")
	var panel_ref: WeakRef = weakref(panel)
	var own_ref: WeakRef = weakref(own_panel)
	var field_ref: WeakRef = weakref(field)
	for object in [hud,battle,abilities,game._duel_menu,field,parking]: object.queue_free()
	game.hud = null
	game.balls.clear()
	game.free()
	await frames(5)
	check(panel_ref.get_ref() == null and own_ref.get_ref() == null and field_ref.get_ref() == null,"teardown releases both portrait trees and all procedural actors")
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(3)
	print("OPPONENT PANEL: %d checks, %d failures"%[checks,failures])
	var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"display":DisplayServer.get_name(),"GLB_loaded":false,"portrait_catalog":49,"dual_public_panels":true,"signed_power_events":true,"audio_listened":false}))
	quit(1 if failures else 0)

func _make_actor(uid: int) -> CreatureBall:
	var ball := CreatureBall.new()
	ball.uid = uid
	ball.def = game._creature_def(uid)
	field.add_child(ball)
	ball._open = true
	ball._figure.visible = true
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.layers = 3
	ball._figure.add_child(mesh)
	return ball

func _check_layout(panel: OpponentPanel) -> void:
	for dimensions in [Vector2i(960,540),Vector2i(1280,720)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await frames()
		print("LAYOUT full ",dimensions," panel=",panel.get_global_rect())
		for current in [own_panel,panel]:
			check(root.get_visible_rect().encloses(current.get_global_rect()),"public portrait panel fits viewport")
			check(current.size.x >= 148 and current.size.x <= 160 and current.size.y >= 148 and current.size.y <= 160,"both public panels retain compact approximately156square geometry")
			check(current.get_global_rect().end.y <= dimensions.y-70,"compact public block stays clear of bottom hands")
			check(current._portrait._fallback.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,"real 2D artwork preserves proportions")
			check(not current._name.text.is_empty() and not current._element.text.is_empty() and not current._power.text.is_empty(),"visible context contains real name element and G")
		check(panel.get_global_rect().position.x > dimensions.x*0.70 and own_panel.get_global_rect().end.x < dimensions.x*0.30,"own creature stays left and opponent stays right at both resolutions")
		check(not own_panel.get_global_rect().intersects(panel.get_global_rect()),"compact public panels never overlap")
		for side in range(2):
			var anchor: Control = battle._power_anchors[side]
			var count: Label = battle._counts[side]
			check(count.get_parent() == battle and count.is_visible_in_tree(),"hidden duplicate plate does not hide ability count")
			check(count.get_global_rect().position.y >= anchor.get_global_rect().end.y and root.get_visible_rect().encloses(count.get_global_rect()),"actual ability count stays below correct compact anchor and inside viewport")
			check(not count.get_global_rect().intersects(anchor.get_global_rect()),"ability count cannot cover portrait or current G")
		abilities._info = {"moment":&"after_landing"}
		abilities._place_panel()
		abilities._panel.show()
		game._opponent_panel_layout()
		await frames()
		print("LAYOUT compact ",dimensions," panel=",panel.get_global_rect()," actions=",abilities._panel.get_global_rect())
		check(panel._compact and not panel.visible and panel._portrait._viewport == null,"right prompt suppresses whole panel with no chip or viewport")
		for control: Control in [hud._help_btn,hud._tempo,game._duel_menu]:
			check(not panel.visible,"no context block covers toolbar while prompt is open")
			check(not own_panel.visible or not own_panel.get_global_rect().intersects(control.get_global_rect()),"left public panel stays clear of toolbar")
		abilities._panel.hide()
		game._opponent_panel_layout()
		await frames()
		check(not panel._compact and panel.visible and own_panel.visible,"both compact public contexts remain usable when prompt closes")
		if DisplayServer.get_name() == "headless": print("PNG skipped (headless, no visual acceptance): opponent-%d"%dimensions.x)
		else:
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(output.path_join("opponent-%d.png"%dimensions.x))==OK,"saved panel PNG")

func _check_portrait(panel: OpponentPanel) -> void:
	var portrait: CreaturePortrait = panel._portrait
	check(portrait._viewport == null and portrait._camera == null and not portrait._image.visible,"real2D portrait needs no render viewport or live camera")
	check(portrait._image.mouse_filter == Control.MOUSE_FILTER_IGNORE and panel.mouse_filter == Control.MOUSE_FILTER_IGNORE,"portrait never blocks input")
	var mesh: MeshInstance3D = other._figure.get_child(other._figure.get_child_count()-1)
	var original := mesh.layers
	var identity := mesh.get_instance_id()
	var transform := mesh.global_transform
	portrait._sync()
	check(mesh.layers == original and portrait._layers.is_empty(),"reference portrait never borrows actor render layers")
	panel.stop()
	check(mesh.layers == original and mesh.get_instance_id() == identity and mesh.global_transform == transform,"stop restores exact layers without replacing or moving model")
	check(portrait._viewport == null and not portrait.is_processing(),"hidden portrait renders/processes nothing")
	panel.present(CardDB.creature(CardDB.RARE_SHADOW_ID),77,370)
	check(portrait._fallback.texture == CreaturePortrait.reference_texture(CardDB.RARE_SHADOW_ID),"rare known species uses its exact original 2D reference")
	check(CreaturePortrait.preload_catalog() == 49 and CreatureModels.catalog_defs().size() == 49,"all49 original creature portraits are resident")
	for definition: CreatureDef in CreatureModels.catalog_defs():
		var id: StringName = definition.id
		var texture := CreaturePortrait.reference_texture(id)
		var expected_path := "res://assets/portraits/creatures/" + String(id).trim_prefix("creature_") + ".png"
		check(texture != null and texture.resource_path == expected_path,"portrait catalog maps exact definition id " + String(id))
		check(texture != null and texture.get_width() > 0 and texture.get_height() > 0,"portrait resource has real pixels " + String(id))
		panel.present(definition,77,370)
		check(portrait._fallback.texture == CreaturePortrait.hud_reference_texture(id) and portrait._viewport == null and portrait._camera == null,"present selects exact2D HUD composition without graphics setup " + String(id))
	check(mesh.layers == original and mesh.global_transform == transform,"complete49portrait iteration preserves resident actor")
	game._present_battle_opponent(0,4,[420,510])


func _notice(side: int, text: String) -> Label:
	for label in battle._floating_numbers:
		if is_instance_valid(label) and int(label.get_meta("battle_side",-1)) == side and label.text == text:
			return label
	return null


func _check_power_events(panel: OpponentPanel) -> void:
	DeviceSettings.set_reduce_motion(true)
	var fx := SoundFx.i()
	await frames()
	fx._last_play.clear()
	var initial_audio := fx._next
	game._battle_uids.assign([0,4])
	game._present_battle_powers([0,0])
	battle.open(["Своя","Чужая"],[0,1],[0,0])
	check(panel._power.text == "0 G" and own_panel._power.text == "0 G" and battle._shown == [0.0,0.0],"zero is an exact public power for both sides")
	check(battle._floating_numbers.is_empty() and fx._next == initial_audio,"initial battle snapshot creates neither power popup nor power sound")
	game._present_battle_powers([100,0])
	battle.set_powers([100,0])
	check(_notice(0,"+100 G") != null and _notice(1,"+100 G") == null,"zero-to-positive creates correctly signed own-side notice")
	check(own_panel._power.text == "100 G" and panel._power.text == "0 G","notice does not replace either exact current G")
	var notices := battle._floating_numbers.size()
	var audio := fx._next
	game._present_battle_powers([100,0])
	battle.set_external_panels(own_panel,panel,1)
	battle.set_powers([100,0])
	check(battle._floating_numbers.size() == notices and fx._next == audio,"same Main repaint and repeated anchor binding create no duplicate popup or sound")
	game._present_battle_powers([0,150])
	battle.set_powers([0,150])
	check(_notice(0,"−100 G") != null and _notice(1,"+150 G") != null,"positive-to-zero and enemy increase preserve both signed deltas")
	check(own_panel._power.text == "0 G" and panel._power.text == "150 G","both zero and positive current totals remain exact after change")
	var static_notice := _notice(1,"+150 G")
	if static_notice != null:
		var position_before := static_notice.position
		await create_timer(.15,true,false,true).timeout
		check(is_instance_valid(static_notice) and static_notice.position == position_before and static_notice.scale == Vector2.ONE and static_notice.modulate.a == 1.0,"reduced motion keeps an accessible static signed notice")
		check(static_notice.mouse_filter == Control.MOUSE_FILTER_IGNORE and root.get_visible_rect().encloses(static_notice.get_global_rect()),"static delta cannot steal input or leave the viewport")
	else:
		check(false,"reduced-motion static notice exists for inspection")
	DeviceSettings.set_reduce_motion(false)
	game._present_battle_powers([3200,0])
	battle.set_powers([3200,0])
	check(_notice(0,"+3200 G") != null and _notice(1,"−150 G") != null,"large positive and negative actual changes retain full amount and G unit")
	check(own_panel._current_power == 3200 and panel._current_power == 0 and battle._target == [3200,0],"counter targets keep exact large G and zero without clipping")
	await create_timer(1.15,true,false,true).timeout
	check(battle._floating_numbers.is_empty(),"finite power notices disappear without leaving permanent chips")
	check(own_panel._power.text == "3200 G" and panel._power.text == "0 G","animated counters settle on exact latest captured totals")
	DeviceSettings.set_reduce_motion(true)
	game._battle_uids.assign([4,0])
	game._present_battle_powers([0,3200])
	battle.open(["Чужая","Своя"],[1,0],[0,3200])
	game._present_battle_powers([11,3189])
	battle.set_powers([11,3189])
	var enemy_notice := _notice(0,"+11 G")
	var own_notice := _notice(1,"−11 G")
	check(enemy_notice != null and own_notice != null,"attacking opponent and defending own creature receive correct signed amounts")
	if enemy_notice != null and own_notice != null:
		check(enemy_notice.get_global_rect().get_center().x > root.size.x*.70 and own_notice.get_global_rect().get_center().x < root.size.x*.30,"battle-side0 notice follows actual right enemy anchor rather than assumed left")
		check(enemy_notice.position.y >= panel.get_global_rect().end.y and own_notice.position.y >= own_panel.get_global_rect().end.y,"signed notices sit below their actual contextual panels")
	game._battle_uids.assign([0,4])
	game._present_battle_powers([420,510])
	battle.open(["Своя","Чужая"],[0,1],[420,510])


func _check_sound_contract() -> void:
	DeviceSettings.set_style(DeviceSettings.DEVICE)
	var fx := SoundFx.i()
	await frames()
	var previous_volume := AudioSettings.interface_volume
	var previous_muted := AudioSettings.interface_muted
	AudioSettings.interface_volume = 1.0
	AudioSettings.interface_muted = false
	fx._last_play.clear()
	var before := fx._next
	fx.play_device_power(120)
	check(fx._next == (before+1)%SoundFx.POOL,"positive real change consumes one audio pool entry")
	var up: AudioStreamPlayer = fx._pool[before]
	check(up.bus == "Interface" and is_equal_approx(up.pitch_scale,1.0),"positive cue uses Interface bus and fixed pitch1")
	check(up.stream != null and up.stream.resource_path.ends_with("device_power_up.wav"),"positive cue uses the dedicated cached rise recording")
	var after_up := fx._next
	fx.play_device_power(-120)
	check(fx._next == after_up,"simultaneous rise and fall share one160ms sound limiter")
	fx._last_play.clear()
	before = fx._next
	fx.play_device_power(-120)
	var down: AudioStreamPlayer = fx._pool[before]
	check(fx._next == (before+1)%SoundFx.POOL and down.bus == "Interface" and is_equal_approx(down.pitch_scale,1.0),"negative cue has same fixed pitch and Interface routing")
	check(down.stream != null and down.stream != up.stream and down.stream.resource_path.ends_with("device_power_down.wav"),"decrease uses a separate cached fall recording")
	if up.stream != null and down.stream != null:
		check(FileAccess.get_file_as_bytes(up.stream.resource_path) != FileAccess.get_file_as_bytes(down.stream.resource_path),"rise and fall recordings contain distinct waveform data")
	before = fx._next
	fx._last_play.clear()
	fx.play_device_power(0)
	check(fx._next == before and not fx._last_play.has("device_power"),"zero delta creates neither playback nor throttle stamp")
	AudioSettings.interface_muted = true
	fx.play_device_power(100)
	check(fx._next == before,"muted interface suppresses power cue before allocating a player")
	AudioSettings.interface_muted = false
	AudioSettings.interface_volume = 0.0
	fx.play_device_power(-100)
	check(fx._next == before,"zero interface volume suppresses power cue")
	AudioSettings.interface_volume = 1.0
	fx._last_play.clear()
	game._battle_uids.assign([0,4])
	game._present_battle_powers([0,0])
	battle.open(["Своя","Чужая"],[0,1],[0,0])
	before = fx._next
	check(battle._floating_numbers.is_empty(),"fresh open contains no change notices")
	game._present_battle_powers([80,90])
	battle.set_powers([80,90])
	check(fx._next == (before+1)%SoundFx.POOL and _notice(0,"+80 G") != null and _notice(1,"+90 G") != null,"two simultaneous battle changes show both notices but play one cue")
	before = fx._next
	var notices := battle._floating_numbers.size()
	game._present_battle_powers([80,90])
	battle.set_powers([80,90])
	check(fx._next == before and battle._floating_numbers.size() == notices,"unchanged actual snapshot cannot retrigger either cue or notice")
	AudioSettings.interface_volume = previous_volume
	AudioSettings.interface_muted = previous_muted
	fx.cancel_match_sfx()


func _check_context_and_motion(panel: OpponentPanel) -> void:
	DeviceSettings.set_reduce_motion(true)
	game._public_creature_opened(4)
	game._public_creature_opened(0)
	check(panel.visible and panel._context_mode == "reveal" and own_panel.visible and own_panel._context_mode == "reveal","actual public reveals open temporary cards for both owners")
	await create_timer(2.4,true,false,true).timeout
	check(not panel.visible and not own_panel.visible and panel._context_mode.is_empty() and own_panel._context_mode.is_empty() and panel._portrait._viewport == null,"both reveals expire without leaving frame or viewport")
	DeviceSettings.set_style(DeviceSettings.CLASSIC)
	DeviceSettings.set_style(DeviceSettings.DEVICE)
	game._opponent_style_changed(DeviceSettings.DEVICE)
	check(not panel.visible and not own_panel.visible,"theme change never resurrects either expired card")
	game._public_creature_opened(4)
	panel.set_compact(true)
	await create_timer(2.4,true,false,true).timeout
	panel.set_compact(false)
	check(not panel.visible,"covered reveal expires rather than returning as persistent chip")
	game._present_battle_opponent(0,4,[420,510])
	await create_timer(.12,true,false,true).timeout
	check(panel.visible and panel._context_mode == "battle" and own_panel.visible and own_panel._context_mode == "battle","active battle retains both relevant compact cards")
	game._finish_opponent_battle()
	check(not panel.visible and not own_panel.visible and panel._uid == -1 and own_panel._uid == -1,"result closes both battle contexts immediately")
	DeviceSettings.set_reduce_motion(false)
	var target := Control.new()
	target.position = Vector2(260,160)
	target.size = Vector2(160,80)
	root.add_child(target)
	var motion_script := load("res://scenes/ui/device_motion.gd")
	for kind in ["boot","scan","power","activation","turn"]:
		var effect: Control = motion_script.play_on(target,kind)
		check(effect != null and effect.mouse_filter == Control.MOUSE_FILTER_IGNORE,"visible finite " + kind + " effect created")
		await frames()
		check(effect.global_position.is_equal_approx(target.global_position),"effect remains on actual target region")
		var replacement: Control = motion_script.play_on(target,kind)
		check(effect._stopped and replacement != null,"same event replaces prior effect without accumulation")
		motion_script.stop_on(target)
	await frames()
	var scan: Control = motion_script.play_on(target,"scan")
	target.hide()
	check(scan._stopped,"hidden target cancels scan immediately")
	target.show()
	var power: Control = motion_script.play_on(target,"power")
	DeviceSettings.set_reduce_motion(true)
	check(power._stopped and motion_script.play_on(target,"scan") == null,"reduced motion cancels and suppresses procedural effects")
	target.queue_free()
