extends "res://tools/autoplay.gd"
## Start a normal client duel and stop at the first battle with two visible portraits.

const MATTE := preload("res://scenes/ui/portrait_matte.gd")
const EDGE := preload("res://scenes/ui/battle_portrait.gdshader")
const BACKDROP := preload("res://scenes/ui/battle_portrait_backdrop.gdshader")
var output: String
var checks := 0
var failures := 0
var preparations := 0


func _initialize() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	DeviceSettings.settings_path = output.path_join("interface-smoke.cfg")
	DeviceSettings.set_style(DeviceSettings.CLASSIC)
	super._initialize()


func _wait_for_scene(path: String, timeout_seconds: float, previous: Node = null) -> bool:
	if not await super._wait_for_scene(path, timeout_seconds, previous): return false
	if path == "res://scenes/menu/main_menu.tscn":
		var expected := CreaturePortrait.REFERENCE_TEXTURES.size()
		preparations = MATTE.generation_count
		_check(CreaturePortrait._presentation_textures.size() == expected and preparations == expected,
			"Boot cached all 49 base portraits before main menu")
		_check(CreaturePortrait._battle_textures.size() == 33, "Boot cached 33 corrected battle mattes")
		_check(DeviceSettings.current() == DeviceSettings.CLASSIC, "isolated client starts in classic style")
		current_scene._on_settings()
		var selector := _interface_selector(current_scene._settings)
		if selector == null:
			_check(false, "main menu contains the interface selector")
			return false
		selector.select(DeviceSettings.DEVICE)
		selector.item_selected.emit(DeviceSettings.DEVICE)
		DeviceSettings.reload_settings()
		_check(DeviceSettings.is_device(), "real menu selector saves Wrist Device and reloads it")
		current_scene._settings.close()
	return true


func _interface_selector(node: Node) -> OptionButton:
	if node is OptionButton and node.item_count == 2 and node.get_item_text(1) == DeviceSettings.NAMES[1]:
		return node as OptionButton
	for child in node.get_children():
		var found := _interface_selector(child)
		if found != null: return found
	return null


func _process(_delta: float) -> bool:
	if _loading or _finishing: return false
	match_frames += 1
	var hud: HudUI = main.hud
	if battles > 0 and hud.own_panel.is_visible_in_tree() and hud.opponent_panel.is_visible_in_tree() \
		and hud.own_panel._context_mode == "battle" and hud.opponent_panel._context_mode == "battle" \
		and not main.events.is_busy():
		_verify_battle(hud)
		return false
	if match_frames > 5400 or main._game_over:
		_check(false, "a normal landed throw reaches a visible battle within 5400 frames")
		_finish(1)
		return false
	if hud._reading > 0: hud._skip_flag = true
	if main.battle_overlay._open: main.battle_overlay._close()
	var view = main.ctrl.get_view(0)
	if main.setup_panel._panel.visible:
		var action: Dictionary = bot.choose_setup(view, main.ctrl.legal_setup_slots(), main.ctrl.can_skip_gate())
		main.setup_panel.hide_panel()
		if action.is_empty(): main._on_setup_skipped()
		else: main._on_setup_placed(action.card_id, int(action.slot))
	elif hud._creature_panel.visible:
		var action: Dictionary = bot.choose_throw(view)
		target = int(action.target_slot)
		main._on_creature_chosen(int(action.uid))
	elif main._active_ball != null and not main.director.flying and main.ctrl.get_active_player() == 0 and not main.events.is_busy():
		var slots: Array = main._gate_slots()
		if not slots.is_empty(): main._on_slot_picked(target if slots.has(target) else int(slots[0]))
	elif main.ability_panel._panel.visible and main.ctrl.get_ability_moment() == &"after_landing":
		main._on_ability_passed()
	return false


func _verify_battle(hud: HudUI) -> void:
	_finishing = true
	_check(hits[0] + hits[1] > 0, "physical throws reached a real arena slot")
	_check(MATTE.generation_count == preparations and _preparation_counts() == startup_counts, "battle reused the Boot caches")
	for panel: OpponentPanel in [hud.own_panel, hud.opponent_panel]:
		var portrait := panel._portrait
		var definition: StringName = portrait._definition.id
		_check(portrait._fallback.material is ShaderMaterial and portrait._fallback.material.shader == EDGE,
			"real battle portrait uses the final edge shader: " + str(definition))
		_check(portrait._fallback.texture == CreaturePortrait.presentation_texture(definition, true)
			and portrait._backdrop.material.shader == BACKDROP and portrait._battle_frame.visible,
			"real battle portrait uses the prepared matte and elemental frame: " + str(definition))
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join("portrait-client-device.png")) == OK, "save real device battle")
	DeviceSettings.set_style(DeviceSettings.CLASSIC)
	for panel: OpponentPanel in [hud.own_panel, hud.opponent_panel]:
		_check(panel._portrait._fallback.material == null and not panel._portrait._battle_frame.visible,
			"classic style detaches the battle shader and portrait frame")
	_check(Engine.max_fps == 60, "standard wrapper holds 60 FPS")
	print("PORTRAIT CLIENT ", checks, "/", failures, " landed=", hits[0] + hits[1], " battles=", battles)
	_finish(1 if failures else 0)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " + label) if ok else printerr("FAIL: " + label)
	if not ok: failures += 1
