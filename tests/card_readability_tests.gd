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

func ink_box(label: Label) -> Rect2:
	var fs := label.get_theme_font_size("font_size")
	var line_height := label.get_theme_font("font").get_height(fs)
	var height := label.get_line_count() * line_height + maxi(0, label.get_line_count() - 1) * label.get_theme_constant("line_spacing")
	return Rect2(label.position + Vector2(0, (label.size.y - height) * 0.5), Vector2(label.size.x, height))

func _run() -> void:
	CardDB.load_all()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.theme = UiTheme.get_theme()
	RenderingServer.set_default_clear_color(Color(0.025, 0.035, 0.06))
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
			changed.append(c)
		for offset in range(0, changed.size(), 8):
			for c in changed.slice(offset, offset + 8):
				grid.add_child(CardView.new().for_card(c, Vector2(150, 210)))
			for frame in 4: await process_frame
			for cv in grid.get_children():
				var label: Label = cv._text
				var needed := label.get_line_count() * label.get_line_height() - maxi(0, label.get_line_count() - 1)
				check(needed <= label.size.y + 2, "краткий текст помещается: %s %s" % [cv.card_id, viewport_size])
				check(label.get_theme_font_size("font_size") >= 10, "эффект читается без кегля ниже 10: %s" % cv.card_id)
				check(cv._role.visible and cv._role.text != "ЭФФЕКТ", "механическая роль определена: %s" % cv.card_id)
				check(cv._role.position.y + cv._role.size.y <= ink_box(label).position.y + 1, "роль не перекрывает строки эффекта: %s" % cv.card_id)
				check(ink_box(cv._title).end.y <= ink_box(cv._kind).position.y + 1, "название не перекрывает строку совместимости: %s" % cv.card_id)
				check(cv._help[4] == CardDB.card(cv.card_id).full_text(), "полные условия доступны при наведении")
			if viewport_size.x == 1280:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out_dir + "/cards-%d.png" % offset)
			for cv in grid.get_children():
				grid.remove_child(cv)
				cv.queue_free()
		if viewport_size.x == 1280:
			var showcase := GridContainer.new()
			showcase.columns = 3
			showcase.add_theme_constant_override("h_separation", 16)
			showcase.add_theme_constant_override("v_separation", 16)
			showcase.position = Vector2(303, 62)
			host.add_child(showcase)
			var caption := VisualUtil.label("ШЕСТЬ СТИХИЙ · ОТВЕТНАЯ ОТМЕНА", 20)
			caption.position = Vector2(303, 18)
			host.add_child(caption)
			for cid in [&"ability_fire_counter", &"ability_gale_rebuttal", &"ability_light_counter", &"ability_stone_counter", &"ability_shadow_counter", &"ability_tide_counter"]:
				var c := CardDB.card(cid)
				check(c != null, "все шесть новых ответов представлены")
				if c == null: continue
				var cv := CardView.new().for_card(c, Vector2(214, 300))
				showcase.add_child(cv)
				check(cv._role.text == "ОТВЕТНАЯ ОТМЕНА" and cv._rule.text == "ТОЛЬКО В БОЮ", "реакция ясно отличима от усиления")
				check(not cv._power.visible, "отмена не обещает прибавку силы")
			for frame in 4: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out_dir + "/counter-showcase-1280.png")
			host.remove_child(showcase)
			showcase.queue_free()
			host.remove_child(caption)
			caption.queue_free()
		for cid in [&"ability_stone_copy", &"ability_light_revive"]:
			check(str(UiTheme.card_help(CardDB.card(cid))[5]).contains("даже у последнего"), "UI объясняет обычный отдых последнего: %s" % cid)
		# Реальные крайние размеры рук: компактные ворота и способности на 540p / 1080p.
		for card_size in [Vector2(96, 134), Vector2(136, 190), Vector2(187, 262)]:
			for cid in [&"arena_limit", &"arena_mute", &"ability_gale_swap", &"ability_kolossar_reset", &"ability_fire_counter"]:
				var c := CardDB.card(cid)
				if c == null: continue
				var cv := CardView.new().for_card(c, card_size)
				grid.add_child(cv)
			for frame in 3: await process_frame
			for cv in grid.get_children():
				check(cv._role.visible, "роль видна в руке: %s %s" % [cv.card_id, card_size])
				check(cv._role.position.y + cv._role.size.y <= card_size.y, "роль внутри компактной карты")
				if card_size.x < 112:
					var title: Label = cv._title
					var plaque: Rect2 = cv._lay["title"]
					plaque = Rect2(plaque.position * card_size.x, plaque.size * card_size.x)
					check(title.position.x >= plaque.position.x and title.position.x + title.size.x <= plaque.end.x + 1, "компактное название строго внутри плашки: %s" % cv.card_id)
					check(title.scale == Vector2.ONE and title.get_theme_font_size("font_size") >= 10, "компактное имя без микрошрифта и ужатия")
					check(title.clip_text and title.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "длинное имя сокращается с многоточием")
					check(str(cv._help[0]) == CardDB.card(cv.card_id).display_name, "полное имя компактной карты доступно в hover")
				if cv._text.visible:
					var needed: float = cv._text.get_line_count() * cv._text.get_line_height() - maxi(0, cv._text.get_line_count() - 1)
					check(needed <= cv._text.size.y + 2, "эффект помещается в руку: %s %s" % [cv.card_id, card_size])
			if viewport_size.x == 1280:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out_dir + "/hand-width-%d.png" % card_size.x)
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
			if c.id == &"arena_mute" or c.id == &"ability_dragnar_rush" or c.id == &"ability_fire_counter":
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
