extends SceneTree
## Адресный рендер длинного уведомления настоящим HUD, без Boot и матча.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	CardDB.load_all()
	var output := "res://build/checks/presentation/selected-standoff-notice/standoff-notice"
	DirAccess.make_dir_recursive_absolute(output)
	var longest := ""
	for id in CardDB.creature_ids():
		var name := CardDB.creature(id).display_name
		if name.length() > longest.length(): longest = name
	var notice := "Тупик: жребий выбрал атакующего — %s идёт на %s!" % [longest, longest]
	RenderingServer.set_default_clear_color(Color("151c2b"))
	for extent in [Vector2i(960, 540), Vector2i(1280, 720)]:
		root.size = extent
		root.content_scale_size = extent
		var hud := HudUI.new()
		root.add_child(hud)
		hud.setup_plates([Color.RED, Color.RED, Color.RED], [Color.BLUE, Color.BLUE, Color.BLUE])
		for battle in [false, true]:
			hud.set_battle_mode(battle)
			hud.flash(notice)
			await create_timer(0.45).timeout
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var label: Label = hud._flash
			var rect := label.get_global_rect()
			check(label.visible and label.text == notice, "уведомление показано целиком")
			check(label.get_visible_line_count() == label.get_line_count(), "все строки доступны")
			check(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= extent.x and rect.end.y <= extent.y, "уведомление внутри экрана")
			check(Engine.max_fps == 60 and root.unfocusable and root.mode == Window.MODE_MINIMIZED, "60FPS, свёрнуто, без фокуса")
			var filename := "%dx%d-%s.png" % [extent.x, extent.y, "battle" if battle else "field"]
			check(root.get_texture().get_image().save_png(output.path_join(filename)) == OK, "свежий PNG сохранён")
		hud.free()
	var report := FileAccess.open(output.path_join("summary.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "notice": notice, "scope": "Настоящий HUD и длинное уведомление в field/battle при960×540/1280×720. Без матча, Boot, online transport и проверки всех UI."}, "\t"))
	print("STANDOFF NOTICE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
