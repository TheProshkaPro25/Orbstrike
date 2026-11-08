extends SceneTree
## Read-only layout evidence for the 2026-11-06 audit; not a visual acceptance test.
const WINDOW := preload("res://tools/test_window.gd")
var rows: Array = []

class MenuFixture extends MainMenu:
	func _ready() -> void:
		_build_ui()
		get_viewport().size_changed.connect(_fit_column)
		_fit_column()
	func _process(_delta: float) -> void: pass

func _initialize() -> void:
	WINDOW.background(self)
	_run.call_deferred()

func _finalize() -> void: WINDOW.finish(self)

func frames(n: int = 4) -> void:
	for i in n: await process_frame

func rect(control: Control) -> Array:
	var r := control.get_global_rect()
	return [r.position.x,r.position.y,r.size.x,r.size.y]

func _run() -> void:
	var out := "res://build/checks/ui-model-audit-2026-11-06"
	DirAccess.make_dir_recursive_absolute(out)
	DeviceSettings.settings_path = out.path_join("flow-settings.cfg")
	DeviceSettings.reload_settings()
	DeviceSettings.set_style(DeviceSettings.CLASSIC)
	AudioServer.set_bus_mute(0,true)
	CardDB.load_all()
	var menu := MenuFixture.new()
	root.add_child(menu)
	await frames()
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await frames()
		menu._fit_column()
		await frames()
		var row := {"scenario":"menu","resolution":[dimensions.x,dimensions.y],"scale":menu._column.scale.x,"first":rect(menu._buttons[0]),"last":rect(menu._buttons[-1]),"font_effective":menu._buttons[0].get_theme_font_size("font_size")*menu._column.scale.x,"button_count":menu._buttons.size()}
		rows.append(row)
		menu._settings.open()
		await frames()
		rows.append({"scenario":"settings","resolution":[dimensions.x,dimensions.y],"rect":rect(menu._settings._panel),"scale":menu._settings._panel.scale.x})
		menu._settings.close()
	menu.queue_free()
	await frames()
	menu = MenuFixture.new()
	root.add_child(menu)
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = Vector2i(1280,720)
		await frames()
		menu._fit_column()
		await frames()
		rows.append({"scenario":"production-menu","physical_resolution":[dimensions.x,dimensions.y],"logical_size":str(root.get_visible_rect().size),"scale":menu._column.scale.x,"button_logical":rect(menu._buttons[0]),"font_physical":menu._buttons[0].get_theme_font_size("font_size")*menu._column.scale.x*dimensions.y/720.0})
	menu.queue_free()
	await frames()
	var result := GameOverUI.new()
	root.add_child(result)
	var history: Array = []
	for i in 6:
		history.append({"turn":100+i,"winner":"Грифалон Прилива","loser":"Грифалон Пламени","wp":1000,"lp":900,"mine":true})
	var stats := {"turns":106,"alive":[1,0],"captures":[3,0],"wins":[6,1],"abilities":[18,15],"traps":2,"battles":history}
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		result.show_result(0,"Все существа соперника выбыли",stats)
		await create_timer(.65).timeout
		await frames()
		rows.append({"scenario":"game-over-six-battles","resolution":[dimensions.x,dimensions.y],"panel":rect(result._panel),"restart":rect(result._restart_button),"inside":root.get_visible_rect().encloses(result._panel.get_global_rect()),"focus_owner":str(root.gui_get_focus_owner())})
	result.queue_free()
	await frames()
	var orb := OrbButton.new()
	root.add_child(orb)
	await frames()
	for definition in CreatureModels.catalog_defs():
		orb.for_creature(definition,0)
		var font: Font = orb.get_theme_default_font()
		var fs := 17 if font.get_string_size(orb.title,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x <= orb.size.x else 14
		var width := font.get_string_size(orb.title,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		if width > orb.size.x:
			rows.append({"scenario":"orb-name-overflow","id":String(definition.id),"name":orb.title,"font":fs,"text_width":width,"button_width":orb.size.x,"overflow_each_side":(width-orb.size.x)*.5})
	orb.queue_free()
	await frames()
	var file := FileAccess.open(out.path_join("ui-flow-layout.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"display":DisplayServer.get_name(),"visual_acceptance":false,"rows":rows},"\t"))
	file.close()
	for row in rows: print("AUDIT_LAYOUT ",JSON.stringify(row))
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames()
	quit()
