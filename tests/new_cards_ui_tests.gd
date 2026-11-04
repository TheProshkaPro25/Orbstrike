extends SceneTree
## Narrow v0.3.3 rendered cards, target picker and wire-contract regression.
const IDS := [&"ability_fire_toll", &"ability_gale_call", &"ability_light_reserve", &"ability_stone_ceiling", &"ability_shadow_triumph", &"ability_tide_wash", &"arena_valor"]
var failures := 0
var checks := 0
var out_dir := "user://cards033-ui"
var selected: Dictionary = {}
var was_cancelled := false

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func capture(label: String) -> void:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(label + ".png"))

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func run() -> void:
	CardDB.load_all()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.theme = UiTheme.get_theme()
	root.size = Vector2i(1600, 960)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color(.025, .035, .06))
	var host := Control.new()
	root.add_child(host)
	for i in IDS.size():
		var def := CardDB.card(IDS[i])
		check(def != null, "card present: " + str(IDS[i]))
		check(CardDB.card_class(def) == (&"bronze" if i == 6 else &"red"), "card class: " + str(IDS[i]))
		var cv := CardView.new().for_card(def, Vector2(210, 294), true)
		cv.position = Vector2(25 + i * 225, 52)
		host.add_child(cv)
		await process_frame
		check(cv._artwork.texture != null, "illustration: " + str(IDS[i]))
		check(cv._text.text.contains(def.full_text()), "full text: " + str(IDS[i]))
		check(cv._text.get_visible_line_count() == cv._text.get_line_count(), "text fits: " + str(IDS[i]))
		check(UiTheme.card_role(def) != "Эффект", "specific role: " + str(IDS[i]))
		if i < 6:
			check(CardEffects.moment(def) == &"battle", "battle only: " + str(IDS[i]))
			check(UiTheme.card_help(def)[5].contains("До 3") and UiTheme.card_help(def)[5].contains("Отдых: 2"), "limit and recovery explained: " + str(IDS[i]))
			check(UiTheme.card_help(def)[5].contains("даже у последнего"), "strict two-battle rest: " + str(IDS[i]))
	check(UiTheme.card_badge(CardDB.card(&"ability_fire_toll")).is_empty(), "conditional toll has no misleading initial power badge")
	await capture("seven-new-cards-full")
	var ctrl := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(1), 22)
	var picker := AbilityTargetPicker.new()
	root.add_child(picker)
	picker.chosen.connect(func(value: Dictionary) -> void: selected = value)
	picker.cancelled.connect(func() -> void: was_cancelled = true)
	await process_frame
	for vp in [Vector2i(1600,960), Vector2i(960,540)]:
		root.size = vp
		root.content_scale_size = vp
		picker.show_targets(&"ability_gale_call", [{"target_uid":1},{"target_uid":2}], ctrl.state)
		await capture("ally-target-%d" % vp.x)
		check(picker.visible and picker._choices.get_child_count() == 2, "ally options shown")
		check(Rect2(Vector2.ZERO, Vector2(vp)).encloses(picker._panel.get_global_rect()), "ally picker fits viewport")
		await click(picker._choices.get_child(1))
		check(selected == {"target_uid":2} and not picker.visible, "explicit ally selection")
		picker.show_targets(&"ability_light_reserve", [{"target_card":&"ability_light_guard"}], ctrl.state)
		await capture("reserve-target-%d" % vp.x)
		check(Rect2(Vector2.ZERO, Vector2(vp)).encloses(picker._panel.get_global_rect()), "reserve picker fits viewport")
		var choice: CardView = picker._choices.get_child(0)
		check(choice.card_id == &"ability_light_guard" and choice._text.text.contains(CardDB.card(choice.card_id).full_text()), "resting card full effect shown")
		await click(picker._cancel)
		check(was_cancelled and not picker.visible, "cancel without committing")
	var protocol := preload("res://network/online_protocol.gd")
	var codec := preload("res://network/state_codec.gd")
	var battle := PowerCalc.compute_seq(ctrl.state,0,3,0,[[0,&"ability_gale_call",{"target_uid":1}]])
	var wire: Dictionary = JSON.parse_string(JSON.stringify(codec.preview(battle)))
	check(codec.valid_battle(wire), "targeted battle wire is valid")
	check(codec.decode_battle(wire).battle_plays[0][2] == {"target_uid":1}, "battle target survives roundtrip")
	wire.ordinary = 1
	check(not codec.valid_battle(wire), "ordinary field must be bool")
	for target in [{"target_uid":2},{"target_card":"ability_light_guard"}]:
		check(protocol.validate({"t":"action","command":"ability","args":{"card":"ability_light_reserve","target":target}}).is_empty(), "target command accepted")
	for target in [{"target_uid":6},{"target_card":"missing"},{"target_uid":2,"power":900},{"target_uid":2,"target_card":"ability_light_guard"}]:
		check(not protocol.validate({"t":"action","command":"ability","args":{"card":"ability_light_reserve","target":target}}).is_empty(), "malformed target command rejected")
	host.queue_free()
	picker.queue_free()
	for frame in 3: await process_frame
	print("Cards 0.3.3 UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
