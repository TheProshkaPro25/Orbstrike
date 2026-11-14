extends SceneTree
## Read-only production UI diagnosis. No GLB, user saves, or screenshots.
const BACKGROUND := preload("res://tools/test_window.gd")
class UiOnlyTeam extends TeamMenu:
	func _show_preview(_id: StringName, _pose: bool) -> void:
		if _preview != null: _preview.show_hint("UI geometry audit")

var output := "res://build/checks/ui-model-audit-2026-11-06"
var observations: Array = []
var initial_scale_mode: int

func _initialize() -> void:
	initial_scale_mode = root.content_scale_mode
	BACKGROUND.background(self)
	_run.call_deferred()

func frames(n: int = 4) -> void:
	for i in n: await process_frame

func record(kind: String, data: Dictionary) -> void:
	data["kind"] = kind
	observations.append(data)
	print("UI_AUDIT ", JSON.stringify(data))

func rect(control: Control) -> Array:
	var r := control.get_global_rect()
	return [r.position.x, r.position.y, r.size.x, r.size.y]

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	AudioServer.set_bus_mute(0, true)
	DeviceSettings.settings_path = output.path_join("audit-device.cfg")
	DeviceSettings.reload_settings()
	DeviceSettings.set_reduce_motion(true)
	CardDB.load_all()
	if OS.get_cmdline_user_args().has("--production-window"):
		for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
			root.content_scale_mode = initial_scale_mode
			root.content_scale_size = Vector2i(1280,720)
			root.size = dimensions
			await frames()
			record("production_viewport",{"window":str(dimensions),"visible_rect":str(root.get_visible_rect()),"scale_mode":initial_scale_mode,"scale_size":str(root.content_scale_size)})
			await diagnose_team(dimensions)
		var production_file := FileAccess.open(output.path_join("ui-production-window.json"),FileAccess.WRITE)
		production_file.store_string(JSON.stringify(observations,"\t"))
		if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
		await frames()
		BACKGROUND.finish(self)
		quit(0)
		return
	for dimensions in [Vector2i(960,540), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await frames()
		await diagnose_team(dimensions)
		await diagnose_battle(dimensions)
	await diagnose_career()
	var file := FileAccess.open(output.path_join("ui-geometry.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"display":DisplayServer.get_name(), "GLB_loaded":false, "visual_acceptance":false, "observations":observations}, "\t"))
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames()
	BACKGROUND.finish(self)
	quit(0)

func diagnose_team(dimensions: Vector2i) -> void:
	var team := UiOnlyTeam.new()
	root.add_child(team)
	await frames()
	for step in [0,1,2]:
		team._show_step(step)
		await frames()
		var head: Control = team._steps[0].get_parent()
		var outside: Array = []
		for child in head.get_children():
			if child is Control and child.visible and not root.get_visible_rect().encloses(child.get_global_rect()):
				outside.append({"name":child.name,"text":child.get("text"),"rect":rect(child)})
		record("team_geometry", {"dimensions":str(dimensions),"step":step,"header":rect(head),"outside_header_controls":outside,"preview":rect(team._preview),"page":rect(team._page),"go":rect(team._go_btn)})
	team.queue_free()
	await frames()

func diagnose_battle(dimensions: Vector2i) -> void:
	var hud := HudUI.new()
	var battle := BattleHud.new()
	root.add_child(battle)
	root.add_child(hud)
	hud.setup_plates([Color.RED,Color.RED,Color.RED],[Color.BLUE,Color.BLUE,Color.BLUE])
	hud.set_names("Игрок","Соперник")
	var definition := CardDB.creature(&"creature_gorgul_fire")
	hud.own_panel.present(definition,0,420)
	hud.opponent_panel.present(definition,3,510)
	hud.own_panel.show_context("battle")
	hud.opponent_panel.show_context("battle")
	hud.set_battle_mode(true)
	battle.set_external_panels(hud.own_panel,hud.opponent_panel,1)
	battle.open(["Своя","Чужая"],[0,0],[420,510])
	var plays: Array = []
	var ids := CardDB.ability_ids()
	for i in range(6): plays.append([i%2,ids[i]])
	battle.set_chain(plays,[false,false],0,[],[3,3])
	await frames()
	var collisions: Array = []
	for chip in battle._chain.get_children():
		for pair in [["own",hud.own_panel],["enemy",hud.opponent_panel]]:
			var panel: OpponentPanel = pair[1]
			if chip.get_global_rect().intersects(panel.get_global_rect()):
				collisions.append({"side":pair[0],"chip":rect(chip),"panel":rect(panel),"power":rect(panel._power),"power_overlap":chip.get_global_rect().intersects(panel._power.get_global_rect())})
	record("battle_chain_overlap",{"dimensions":str(dimensions),"chain":rect(battle._chain),"collisions":collisions})
	hud.set_battle_mode(false)
	hud.own_panel.hide_context()
	hud.opponent_panel.hide_context()
	await frames()
	record("opponent_summary",{"dimensions":str(dimensions),"own_summary_visible":hud._plates[0].is_visible_in_tree(),"enemy_summary_visible":hud._plates[1].is_visible_in_tree(),"enemy_context_visible":hud.opponent_panel.is_visible_in_tree()})
	battle.set_external_panels(null,null,-1)
	hud.queue_free()
	battle.queue_free()
	await frames()

func diagnose_career() -> void:
	var career := Career.create("fire",1,773,"Audit","")
	var panel := CareerPanel.new()
	root.add_child(panel)
	panel.display(career)
	var started := career.start_cup(CardDB.build_deck(panel._team,panel._ids(CardDB.GATE_CLASSES),panel._ids(CardDB.ABILITY_CLASSES)),panel._levels)
	panel.display(career)
	panel._shop_kind = 1
	panel._switch_tab(2)
	await frames()
	var offered: Array = []
	for button in panel.find_children("CareerBuy_*","Button",true,false):
		if not button.disabled:
			offered.append({"text":button.text,"id":button.name})
	var rejection := ""
	if not offered.is_empty():
		var item := String(offered[0].id).trim_prefix("CareerBuy_")
		career.purchase(item)
		rejection = career.last_error
	record("career_locked_shop",{"started":started,"cup_active":career.cup!=null,"enabled_offers":offered,"rejection":rejection})
	panel.queue_free()
	await frames()
