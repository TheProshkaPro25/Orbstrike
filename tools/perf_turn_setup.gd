extends SceneTree
## Изолированные CPU-замеры подготовки существ и решения ИИ (не средний FPS).
var rows: Array = []
var output := "user://turn_setup.json"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	CardDB.load_all()
	Engine.max_fps = 60
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]
	var defs: Array = []
	for id in [&"creature_dragnar_fire", &"creature_ratnik_light", &"creature_kolossar_stone", &"creature_rogozhuk_stone", &"creature_klykar_shadow", &"creature_levian_tide"]:
		var d := CardDB.creature(id)
		if d != null: defs.append(d)
	var begin := Time.get_ticks_usec()
	CreatureModels.preload_match(defs)
	print("PRELOAD ms=", (Time.get_ticks_usec() - begin)/1000.0)
	for repeat in 2:
		for d in defs:
			var t := Time.get_ticks_usec()
			var model := CreatureModels.build(d)
			var build_ms := (Time.get_ticks_usec() - t) / 1000.0
			var actor := CreatureAnim.new()
			root.add_child(actor)
			t = Time.get_ticks_usec()
			actor.set_model(model, d)
			var setup_ms := (Time.get_ticks_usec() - t) / 1000.0
			t = Time.get_ticks_usec()
			await process_frame
			var draw_wait_ms := (Time.get_ticks_usec() - t) / 1000.0
			var row := {"id":String(d.id), "repeat":repeat,"build_ms":build_ms,"setup_ms":setup_ms,"draw_wait_ms":draw_wait_ms,"preparation":actor.preparation_ms}
			rows.append(row)
			print("SETUP ", JSON.stringify(row))
			load("res://scenes/model_lifetime.gd").release(actor, self)
			await process_frame
			await process_frame
	var ctrl := MatchController.new(CardDB.preset_deck(0),CardDB.preset_deck(1),271828)
	ctrl.start()
	var ai := AIPlayer.new(0,271829,-1,AIPlayer.Difficulty.HARD)
	var t := Time.get_ticks_usec()
	for i in 50: ai.choose_setup(ctrl.get_view(0),ctrl.legal_setup_slots(),ctrl.can_skip_gate())
	print("AI setup average ms=",(Time.get_ticks_usec()-t)/50000.0)
	var result := {"rows":rows,"renderer":RenderingServer.get_video_adapter_name()}
	var f := FileAccess.open(output,FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"  "))
	CreatureModels.clear()
	await process_frame
	quit()
