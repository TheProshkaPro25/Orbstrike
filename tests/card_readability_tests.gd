extends SceneTree
## Изолированная GPU-проверка коротких карт и полных подсказок без загрузки моделей.
var failures := 0
var checks := 0
var out_dir := "user://cards-ui"

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	CardDB.load_all()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.theme = UiTheme.get_theme()
	var host := Control.new()
	root.add_child(host)
	for viewport_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		var grid := GridContainer.new()
		grid.columns = 4
		grid.position = Vector2(12, 12)
		host.add_child(grid)
		var changed: Array[CardDef] = []
		for id in CardDB.arena_ids() + CardDB.ability_ids():
			var c := CardDB.card(id)
			if not c.details.is_empty(): changed.append(c)
		for offset in range(0, changed.size(), 8):
			for c in changed.slice(offset, offset + 8):
				grid.add_child(CardView.new().for_card(c, Vector2(150, 210)))
			for frame in 4: await process_frame
			for cv in grid.get_children():
				var label: Label = cv._text
				var needed := label.get_line_count() * label.get_line_height() - 2 * maxi(0, label.get_line_count() - 1)
				check(needed <= label.size.y + 2, "краткий текст помещается: %s %s" % [cv.card_id, viewport_size])
				check(cv._help[4] == CardDB.card(cv.card_id).full_text(), "полные условия доступны при наведении")
			if viewport_size.x == 1280:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out_dir + "/cards-%d.png" % offset)
			for cv in grid.get_children():
				grid.remove_child(cv)
				cv.queue_free()
		for c in changed:
			var panel: Control = UiTheme.help_panel(UiTheme.card_help(c))
			panel.position = Vector2(16, 16)
			host.add_child(panel)
			for frame in 4: await process_frame
			check(panel.size.y <= viewport_size.y - 24, "подсказка помещается по высоте: %s %s %.0f" % [c.id, viewport_size, panel.size.y])
			check(panel.size.x <= viewport_size.x - 24, "подсказка помещается по ширине")
			if c.id == &"arena_mute" or c.id == &"ability_dragnar_rush":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out_dir + "/%s-%d.png" % [c.id, viewport_size.x])
			host.remove_child(panel)
			panel.queue_free()
		var preview := CreaturePreview.new()
		preview.position = Vector2(650, 12)
		preview.size = Vector2(295, viewport_size.y - 24)
		host.add_child(preview)
		for c in changed:
			preview.show_card(c)
			for frame in 4: await process_frame
			var explanation: ScrollContainer = preview._lines.get_parent()
			check(explanation.scroll_vertical == 0, "новая карта открывает описание с начала")
			check(preview._lines.get_child(0).text == c.full_text(), "полные условия видны в выборе колоды")
			check(preview.size.y <= viewport_size.y - 24, "предпросмотр не растягивает экран")
			var bar := explanation.get_v_scroll_bar()
			if bar.max_value > bar.page:
				explanation.scroll_vertical = int(bar.max_value)
				await process_frame
				check(explanation.scroll_vertical > 0, "длинное объяснение прокручивается")
			if c.id == &"arena_mute" and viewport_size.x == 960:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out_dir + "/deck-details-960.png")
		preview.release()
		host.remove_child(preview)
		preview.queue_free()
		host.remove_child(grid)
		grid.queue_free()
	host.queue_free()
	for frame in 3: await process_frame
	print("Читаемость карт: %d проверок, %d ошибок" % [checks, failures])
	quit(1 if failures else 0)
