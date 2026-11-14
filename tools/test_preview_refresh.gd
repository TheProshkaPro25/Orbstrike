extends SceneTree
## Real deck-menu pointer/focus/selection events; no Boot or creature setup.
const Metrics := preload("res://scenes/performance_metrics.gd")
class CardMenu extends TeamMenu:
	var baseline_mode := false
	func _show_preview(id: StringName, pose: bool) -> void:
		if _step != 0:
			# Reproduce the measured old unconditional-build policy, without editing
			# production source or adding a diagnostic switch to the game.
			if baseline_mode and is_instance_valid(_preview): _preview._full_card_definition = null
			super._show_preview(id,pose)
class CardPreview extends CreaturePreview:
	func _request(_definition: CreatureDef) -> void: pass
var checks := 0
var failures := 0
var baseline := OS.get_environment("SFERY_PREVIEW_BASELINE") == "1"
var out := "res://build/checks/presentation/preview-refresh"
var menu: CardMenu
var rows: Array = []
var input_usec := 0
func _initialize() -> void: _run.call_deferred()
func frames(count: int = 3) -> void:
	for i in count: await process_frame
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: " + why)
func send(event: InputEvent) -> void:
	var begin := Time.get_ticks_usec()
	root.push_input(event,true)
	input_usec += Time.get_ticks_usec()-begin
func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	send(event)
	await frames(1)
func click(card: CardView) -> void:
	menu._page.ensure_control_visible(card)
	await frames(1)
	await move(card.get_global_rect().get_center())
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = card.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = pressed
		send(event)
		await frames(1)
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	out = out.path_join("baseline" if baseline else "after")
	DirAccess.make_dir_recursive_absolute(out)
	DeviceSettings.settings_path = out.path_join("isolated-settings.cfg")
	DeviceSettings.reload_settings()
	DeviceSettings.set_reduce_motion(true)
	CardDB.load_all()
	Metrics.install()
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	menu = CardMenu.new()
	menu.baseline_mode = baseline
	root.add_child(menu)
	menu._rng.seed = 771
	menu.pick_random()
	menu._show_step(1)
	await frames(5)
	var cards: Array = menu._cards.values()
	check(cards.size() >= 2,"real gate catalog visible")
	var before := Metrics.value("preview_card_builds")
	for step in 6:
		await move(Vector2(10,360))
		var card: CardView = cards[step % 2]
		var builds := Metrics.value("preview_card_builds")
		var start := input_usec
		await click(card)
		check(menu._preview._full_card.card_id == card.card_id,"real click presents requested card")
		check(menu._focus_id == card.card_id,"actual card focus enters menu")
		var delta := Metrics.value("preview_card_builds")-builds
		rows.append({"step":step,"id":String(card.card_id),"preview_builds":delta,"input_cpu_usec":input_usec-start})
		if not baseline: check(delta <= 1,"hover/focus/selection reuse one full card")
	var current: CardView = menu._preview._full_card
	var begin := Time.get_ticks_usec()
	for i in 30: menu._show_preview(menu._focus_id,false)
	var repeated_usec := Time.get_ticks_usec()-begin
	await frames(3)
	if not baseline: check(menu._preview._full_card == current,"repeated same-card requests retain the visible node")
	var interaction_builds := Metrics.value("preview_card_builds")-before
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(out.path_join("gate-menu.png")) == OK,"real card-menu PNG")
	if not baseline: await boundaries()
	var report := {"baseline":baseline,"baseline_policy":"force previous unconditional face build in test subclass" if baseline else "production same-card reuse","checks":checks,"failures":failures,"seed":771,"click_rows":rows,"preview_builds_total":interaction_builds,"input_cpu_usec":input_usec,"repeated_30_usec":repeated_usec,"fps_cap":Engine.max_fps,"scope":"real TeamMenu card UI; input CPU excludes await/render, not overall FPS or a match"}
	var file := FileAccess.open(out.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	menu.queue_free()
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(5)
	print("PREVIEW REFRESH ",checks,"/",failures," ",JSON.stringify(report))
	quit(1 if failures else 0)

func boundaries() -> void:
	menu.hide()
	var preview := CardPreview.new()
	preview.position = Vector2(400,20)
	preview.size = Vector2(420,300)
	root.add_child(preview)
	var definition := CardDB.card(CardDB.arena_ids()[0])
	preview.show_card(definition)
	await frames()
	var card := preview._full_card
	preview._full_card_scroll.scroll_vertical = 40
	await frames()
	var reading := preview._full_card_scroll.scroll_vertical
	check(reading > 0,"boundary fixture has an actual scrolling card")
	preview.show_card(definition,true,"Выбрана fixture")
	await frames()
	check(preview._full_card == card and preview._full_card_scroll.scroll_vertical == reading,"selection refresh keeps node and reading position")
	check(preview._status.text.begins_with("Выбрана fixture") and preview._status.text.count("Наведите") == 1,"selected note updates without duplicating disclosure hint")
	preview.show_card(definition,false,"Можно выбрать fixture")
	check(preview._status.get_theme_color("font_color").is_equal_approx(Color(1,.85,.5)),"unselected status updates on reuse")
	var previous := card.get_instance_id()
	var alternate := definition.duplicate() as CardDef
	alternate.details += "\nИзменённое определение fixture"
	preview.show_card(alternate)
	check(preview._full_card.get_instance_id() != previous and str(preview._full_card.get_meta("face_body")).contains("Изменённое определение fixture"),"same ID with a new Resource never keeps stale face")
	await frames()
	card = preview._full_card
	preview.size.x = 480
	await frames()
	preview.show_card(alternate)
	check(preview._full_card == card and is_equal_approx(card._card_size.x,440) and str(card.get_meta("face_body")).contains("Изменённое определение fixture"),"resize updates stored definition without replacing the node")
	await move(Vector2(10,360))
	card.grab_focus()
	await frames()
	var disclosure := card._focus_disclosure
	check(is_instance_valid(disclosure),"retained full card opens keyboard disclosure")
	preview.show_card(alternate,true,"keyboard fixture")
	await frames()
	check(card._focus_disclosure == disclosure,"status refresh keeps one existing disclosure")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	send(escape)
	await frames()
	check(not is_instance_valid(disclosure),"Esc closes disclosure on retained full card")
	card.release_focus()
	card.grab_focus()
	await frames()
	check(is_instance_valid(card._focus_disclosure),"retained full card can reopen after Esc")
	previous = preview._full_card.get_instance_id()
	preview.show_hint("fixture hint")
	preview.show_card(definition)
	check(preview._full_card.get_instance_id() != previous and preview._full_card_scroll.scroll_vertical == 0,"return from hint resets preview context")
	previous = preview._full_card.get_instance_id()
	preview.show_creature(CardDB.creature(CardDB.creature_ids()[0]))
	preview.show_card(definition)
	check(preview._full_card.get_instance_id() != previous and preview._want == null,"return from creature resets context without setup in fixture")
	var next := CardDB.card(CardDB.ability_ids()[0])
	preview.show_card(next)
	check(preview._full_card.card_id == next.id and preview._full_card_scroll.scroll_vertical == 0,"different card changes face and resets scroll")
	await frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(out.path_join("resized-card.png")) == OK,"boundary card PNG")
	preview.queue_free()
	await frames()
