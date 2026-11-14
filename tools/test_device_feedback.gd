extends SceneTree
## Targeted runtime feedback: real buttons/deck cards and the whole 2D match HUD.
## Run via check.py, with its minimized/unfocusable60FPS wrapper and isolated user dir.
class UiOnlyTeam extends TeamMenu:
	func _show_preview(_id: StringName, _pose: bool) -> void:
		if _preview != null: _preview.show_hint("2D UI check")

var checks := 0
var failures := 0
var output := "res://build/checks/presentation/device-feedback"
var sound: SoundFx

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func frames(count: int = 2) -> void:
	for i in count: await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("PNG skipped (headless; no visual acceptance): " + label)
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+".png")) == OK, "PNG " + label)

func _run() -> void:
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	AudioServer.set_bus_mute(0,true)
	DeviceSettings.settings_path = "user://device-feedback.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DeviceSettings.settings_path))
	DeviceSettings.reload_settings()
	AudioSettings.interface_muted = false
	AudioSettings.interface_volume = 1.0
	sound = SoundFx.i()
	await frames()
	CardDB.load_all()
	await _test_buttons_and_deck()
	await _test_render_reveal()
	await _test_match_hud()
	if is_instance_valid(sound): sound.queue_free()
	await frames(3)
	print("DEVICE FEEDBACK: %d checks, %d failures" % [checks,failures])
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"display":DisplayServer.get_name(),"visual_acceptance":DisplayServer.get_name()!="headless"}))
	quit(1 if failures else 0)

func _test_buttons_and_deck() -> void:
	var buttons: Array[Button] = []
	var stream: AudioStream
	for i in 5:
		var b := Button.new()
		root.add_child(b)
		buttons.append(b)
		sound._last_play.clear()
		var before := sound._next
		b.pressed.emit()
		check(sound._next == (before+1)%SoundFx.POOL,"one cue per ordinary button")
		var player: AudioStreamPlayer = sound._pool[before]
		if stream == null: stream = player.stream
		check(player.stream == stream and player.pitch_scale == 1.0 and player.volume_db == -4.0 and player.bus == "Interface","identical digital button stream/pitch/gain/bus")
		sound._on_node_added(b)
		check(b.pressed.get_connections().size() == 1,"one automatic hook after repeated registration")
	var before := sound._next
	buttons[0].pressed.emit()
	check(sound._next == before,"same-frame duplicate is suppressed")
	var team := UiOnlyTeam.new()
	root.add_child(team)
	await frames()
	team._team = [&"creature_gorgul_fire",&"creature_rogozhuk_fire",&"creature_klykar_fire"]
	for step in [0,1,2]:
		team._show_step(step)
		await frames()
		check(not team._cards.is_empty(),"real deck page contains cards")
		for id in team._cards:
			var card: CardView = team._cards[id]
			before = sound._next
			card.mouse_entered.emit()
			check(sound._next == before,"deck hover is silent")
			check(team._hover_id == StringName(id),"preview hover handlers remain connected")
			card.mouse_exited.emit()
		var first: CardView = team._cards.values()[0]
		sound._last_play.clear()
		before = sound._next
		first.pressed.emit()
		check(sound._next == (before+1)%SoundFx.POOL and sound._pool[before].stream == stream and sound._pool[before].pitch_scale == 1.0,"card selection uses same single fixed click")
	var outside := CardView.new().for_card(CardDB.card(&"arena_field_fire"))
	root.add_child(outside)
	sound._last_play.clear()
	before = sound._next
	outside.mouse_entered.emit()
	check(sound._next == (before+1)%SoundFx.POOL,"hover outside deck still works")
	team.queue_free()
	outside.queue_free()
	for b in buttons: b.queue_free()
	await frames()


func _test_render_reveal() -> void:
	var motion := preload("res://scenes/ui/device_motion.gd")
	DeviceSettings.set_reduce_motion(false)
	var host := Control.new()
	host.size = Vector2(400,200)
	root.add_child(host)
	var watcher := motion.watch_tree(host)
	var button := Button.new()
	button.position = Vector2(70,40)
	button.size = Vector2(160,40)
	host.add_child(button)
	await create_timer(.12,true,false,true).timeout
	var registry: Dictionary = button.get_meta(motion.REGISTRY,{})
	check(registry.has("boot"),"late added button receives staged reveal")
	if registry.has("boot"):
		var overlay: Control = registry.boot.get_ref()
		check(overlay != null and bool(overlay.get("_revealing")),"startup moves the existing target render, beyond light overlay")
		check(overlay.get("render_offset").length() > 1.0 and float(overlay.get("render_alpha")) < 1.0,"reveal has actual slide and staged brightness")
		check(button.position == Vector2(70,40) and button.size == Vector2(160,40),"render reveal preserves input geometry")
		button.position = Vector2(92,55)
		check(bool(overlay.get("_stopped")) and overlay.get("render_offset") == Vector2.ZERO,"layout movement cancels and settles render reveal")
		check(button.position == Vector2(92,55) and button.modulate == Color.WHITE,"settle keeps current layout and semantic opacity")
	button.hide()
	button.show()
	await create_timer(.12,true,false,true).timeout
	check(button.has_meta(motion.REGISTRY),"later show replays an existing region")
	DeviceSettings.set_reduce_motion(true)
	check(not button.has_meta(motion.REGISTRY) and button.modulate.a == 1.0,"reduced motion immediately settles an active reveal")
	DeviceSettings.set_reduce_motion(false)
	var second_host := Control.new()
	root.add_child(second_host)
	host.reparent(second_host)
	await frames()
	button.hide()
	button.show()
	await create_timer(.12,true,false,true).timeout
	check(button.has_meta(motion.REGISTRY),"reparented reveal watcher reconnects")
	check(watcher.get("_timer") != null,"event driven watcher retains its single layout debounce timer")
	second_host.queue_free()
	await frames(3)

func _test_match_hud() -> void:
	DeviceSettings.set_reduce_motion(false)
	var hud := HudUI.new()
	var gates := SetupPanel.new()
	var abilities := AbilityPanel.new()
	var battle := BattleHud.new()
	root.add_child(hud)
	root.add_child(gates)
	root.add_child(abilities)
	root.add_child(battle)
	hud.setup_plates([Color.RED,Color.RED,Color.RED],[Color.BLUE,Color.BLUE,Color.BLUE])
	hud.set_names("Игрок","Соперник")
	hud.set_status(1,0,3,3)
	hud.set_hint("Выберите карту ворот")
	hud.log_event("Существо ждёт броска")
	hud.coach("device_context_test","Выберите карту ворот")
	await frames()
	var log_position := hud._log_box.position
	var coach_position := hud._coach.position
	hud.own_panel.present(CardDB.creature(&"creature_gorgul_fire"),0,200)
	hud.own_panel.show_context("reveal")
	await frames()
	check(not hud._log_box.get_global_rect().intersects(hud.own_panel.get_settled_global_rect()),"own public card leaves log unobscured")
	check(hud._coach.position.x >= hud.own_panel.position.x+hud.own_panel.size.x,"own public card leaves coach readable alongside")
	hud.own_panel.hide_context()
	check(hud._log_box.position.is_equal_approx(log_position) and is_equal_approx(hud._coach.position.x, coach_position.x),"context expiry restores log position and coach alignment")
	hud.dismiss_coach("device_context_test")
	hud.own_panel.show_context("battle")
	hud.set_battle_mode(true)
	hud.coach("device_battle_context_test","Выберите способность")
	await frames()
	check(not hud._coach.get_global_rect().intersects(hud.own_panel.get_global_rect()),"battle coach leaves own current G card unobscured")
	hud.dismiss_coach("device_battle_context_test")
	hud.own_panel.hide_context()
	hud.set_battle_mode(false)
	gates.set_hand([&"arena_field_fire",&"arena_den_gorgul",&"arena_mirror"])
	abilities.set_hand([&"ability_fire_counter",&"ability_fire_spark",&"ability_klykar_bite"])
	gates.set_dock_visible(true)
	abilities.set_dock_visible(true)
	await frames()
	for panel: Control in [hud,gates,abilities]:
		check(panel.has_node("DeviceFrame"),"whole match UI subscribes to electronic style")
	check(hud._hint_plate.get_theme_stylebox("panel").corner_radius_top_left == 3,"main HUD custom panel receives device style")
	var input_before := [hud.mouse_filter,gates.mouse_filter,abilities.mouse_filter,hud._help_btn.mouse_filter]
	sound._last_play.clear()
	var before := sound._next
	hud.begin_match_interface([gates,abilities])
	check(sound._next == (before+1)%SoundFx.POOL,"exactly one intentional startup cue")
	for panel: Control in [hud,gates,abilities]:
		check(panel.modulate.a > 0.0 and panel.modulate.a < 1.0,"visible panels begin fade")
		check(panel.get_node("DeviceFrame").intro_tween != null,"one active intro tween per root")
	check(input_before == [hud.mouse_filter,gates.mouse_filter,abilities.mouse_filter,hud._help_btn.mouse_filter],"appearance never changes input filters")
	hud.begin_match_interface([gates,abilities])
	check(sound._next == (before+1)%SoundFx.POOL,"repeated startup does not restart or replay")
	await create_timer(.12,true,false,true).timeout
	var motion := preload("res://scenes/ui/device_motion.gd")
	check(hud._plates[0].has_meta(motion.REGISTRY),"HUD start dispatches actual boot light pass")
	hud.set_status(2,1,3,3)
	await frames()
	var turn_registry: Dictionary = hud._turn_clip.get_meta(motion.REGISTRY,{})
	check(turn_registry.has("turn"),"turn change dispatches actual directional wipe")
	await capture("device-entry")
	hud.show_creatures([{"uid":0,"text":"Первое существо"}])
	await create_timer(.14,true,false,true).timeout
	check(hud._creature_panel.has_meta(motion.REGISTRY),"creature selection reveals as a whole region")
	hud.show_creatures([{"uid":1,"text":"Другое существо"}])
	await create_timer(.14,true,false,true).timeout
	check(hud._creature_panel.has_meta(motion.REGISTRY),"already visible creature selection rebuild gets one fresh reveal")
	hud.hide_creatures()
	await create_timer(0.6,true,false,true).timeout
	for panel: Control in [hud,gates,abilities]: check(is_equal_approx(panel.modulate.a,1.0) and panel.get_node("DeviceFrame").intro_tween == null,"intro finishes fully visible")
	for size in [Vector2i(960,540),Vector2i(1280,720)]:
		root.size = size
		root.content_scale_size = size
		battle.open(["Горгул","Ратник"],[0,3],[200,280])
		await frames()
		battle.set_chain([[0,&"ability_fire_counter"]],[false,false])
		DeviceSettings.set_reduce_motion(true)
		for chip in battle._chain.get_children(): check(chip.modulate.a == 1.0,"cancelling played-card fade restores visibility")
		DeviceSettings.set_reduce_motion(false)
		root.size.x -= 40
		await frames()
		DeviceSettings.set_reduce_motion(true)
		await frames()
		check(hud.modulate.a == 1.0 and gates.modulate.a == 1.0 and abilities.modulate.a == 1.0,"reduced motion leaves match controls visible")
		DeviceSettings.set_reduce_motion(false)
		await frames()
		check(battle._powers[0].text != "" and battle._plates[0].modulate.a == 1.0,"combat panel remains visible after resize and motion change")
		await capture("device-battle-%d"%size.x)
		battle.resolve(0)
		root.size.x -= 1
		await frames()
		check(not battle._chain.visible,"resolved played-card chain stays hidden on resize")
		battle.close()
	var settings := MenuSettings.new()
	root.add_child(settings)
	await frames()
	var reduction: CheckButton = settings.find_child("ReduceInterfaceMotion",true,false)
	check(reduction != null,"reduced-motion control is available in actual Settings UI")
	if reduction != null: reduction.button_pressed = true
	DeviceSettings.reload_settings()
	check(DeviceSettings.reduce_motion(),"reduced motion saves and reloads")
	var reduced := HudUI.new()
	root.add_child(reduced)
	await frames()
	reduced.begin_match_interface()
	check(reduced.modulate.a == 1.0 and reduced.get_node("DeviceFrame").intro_tween == null,"reduced motion appears immediately")
	battle.open(["Горгул","Ратник"],[0,3],[200,280])
	check(battle._powers[0].text == "200" and battle._powers[1].text == "280","reduced motion shows actual G immediately")
	battle.close()
	for panel in [hud,gates,abilities,battle,reduced,settings]: panel.queue_free()
	await frames(4)
