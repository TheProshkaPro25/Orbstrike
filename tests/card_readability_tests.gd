extends SceneTree
## Сверяем исходный текст, диапазоны shaped строк и доступность последней строки.
## Проверка границы Label сама по себе не доказывает отсутствие обрезки букв.
var failures := 0
var checks := 0
var out_dir := "user://cards-ui"
var host: Control
var font_ranges := {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("_run")

func inspect_text(l: Label, expected: String, context: String, minimum: int = 3) -> void:
	if not l.visible: return
	check(l.text == expected, "текст сохранён целиком: " + context)
	check(l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and l.max_lines_visible == -1 and l.visible_ratio == 1, "нет скрытых букв/строк/ellipsis: " + context)
	var fs := l.get_theme_font_size("font_size")
	var group := ("полное описание" if l.get_parent().get_parent().get_meta("complete_card",false) else "краткий эффект") if context.contains("правила") else ("имя" if context.contains("название") or context.contains("существо") else "метаданные")
	if not font_ranges.has(group): font_ranges[group] = Vector2i(fs,fs)
	font_ranges[group] = Vector2i(mini(font_ranges[group].x,fs),maxi(font_ranges[group].y,fs))
	check(fs >= minimum and l.scale == Vector2.ONE, "подобранный кегль без сжатия: " + context)
	var paragraph := TextParagraph.new()
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.width = maxf(1,l.size.x - l.get_theme_constant("outline_size") * 2)
	paragraph.add_string(expected, l.get_theme_font("font"), fs)
	var last_end := 0
	for i in paragraph.get_line_count():
		var span := paragraph.get_line_range(i)
		last_end = maxi(last_end, span.y)
		check(paragraph.get_line_size(i).x <= l.size.x + 1, "shaped строка внутри ширины: %s #%d" % [context, i])
	check(last_end == expected.length(), "shaped диапазоны доходят до последней буквы: " + context)
	check(paragraph.get_size().y <= l.size.y + 1, "вся высота shaped текста: " + context)
	check(l.get_visible_line_count() == l.get_line_count(), "последняя строка Label видна: %s fs%d lines%d visible%d lineheight%d box%s" % [context,fs,l.get_line_count(),l.get_visible_line_count(),l.get_line_height(),l.size])

func inspect_card(cv: CardView, full: bool) -> void:
	var def := CardDB.card(cv.card_id)
	var context := "%s %s" % [cv.card_id, cv._card_size]
	inspect_text(cv._title, def.display_name, "название " + context, 3)
	inspect_text(cv._kind, str(UiTheme.card_help(def)[1]) if full else UiTheme.card_kind(def), "тип " + context)
	inspect_text(cv._role, UiTheme.card_role(def).to_upper(), "роль " + context)
	if cv._rule.visible: inspect_text(cv._rule,"Все условия ↗","ссылка " + context)
	inspect_text(cv._text, str(cv.get_meta("face_body")), "правила " + context, 3)
	check(not cv._title.get_rect().intersects(cv._kind.get_rect()), "название отдельно от типа: " + context)
	check(not cv._role.get_rect().intersects(cv._text.get_rect()), "роль отдельно от эффекта: " + context)
	check(not cv._artwork.get_rect().intersects(cv._role.get_rect()), "эмаль отдельно от роли: " + context)
	for l in [cv._title, cv._kind, cv._role, cv._text]:
		if not l.visible: continue
		check(Rect2(Vector2.ZERO, cv._card_size).grow(.5).encloses(l.get_rect()), "область текста в рамке: %s text=%s rect=%s" % [context,l.text,l.get_rect()])
	if cv._power.visible:
		check(not cv._artwork.get_rect().intersects(cv._power.get_rect()), "эмаль отдельно от числа: " + context)
	if full:
		var body := cv._text.text
		check(body.contains(def.full_text()), "полный эффект и исключения на лице: " + context)
		check(body.contains(str(UiTheme.card_help(def)[5])), "все сроки/лимиты/возврат на лице: " + context)
		check(cv._text.get_theme_font_size("font_size") >= 3, "полный текст подобран без обрезки: " + context)

func capture(name: String) -> void:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))

func clear() -> void:
	for c in host.get_children():
		host.remove_child(c)
		c.queue_free()

func has_tooltip(node: Node) -> bool:
	if node is PopupPanel and node.visible: return true
	for child in node.get_children(true):
		if has_tooltip(child): return true
	return false

# Один и тот же стенд до/после редакторской правки: реальная геометрия 360×504.
func editorial_examples(stage: String) -> void:
	root.size = Vector2i(1600,720)
	root.content_scale_size = root.size
	var samples := [&"ability_stone_copy", &"arena_mute", &"ability_gale_swap", &"ability_fire_assault"]
	for i in samples.size():
		var cv := UiTheme.full_card_panel(UiTheme.card_help(CardDB.card(samples[i]))) as CardView
		cv.position = Vector2(22 + i * 394,95)
		host.add_child(cv)
		var caption := VisualUtil.label("%s · текст %dpx" % [CardDB.card(samples[i]).display_name, cv._text.get_theme_font_size("font_size")],14)
		caption.position = Vector2(22 + i * 394,55)
		host.add_child(caption)
		print("COPY_METRIC ", samples[i], " ", cv._text.get_theme_font_size("font_size"), "px chars=",cv._text.text.length())
	await capture("editorial-" + stage)

func _run() -> void:
	CardDB.load_all()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.theme = UiTheme.get_theme()
	RenderingServer.set_default_clear_color(Color(.025, .035, .06))
	host = Control.new()
	root.add_child(host)
	var ids := CardDB.arena_ids() + CardDB.ability_ids()
	if OS.get_environment("CARD_COPY_SNAPSHOT") != "":
		await editorial_examples(OS.get_environment("CARD_COPY_SNAPSHOT"))
		clear()
		for frame in 4: await process_frame
		quit()
		return
	if OS.get_environment("CARD_COPY_COMPACT") == "1":
		root.size = Vector2i(1600,1000)
		root.content_scale_size = root.size
		for row in 5:
			var sz: Vector2 = [Vector2(96,134),Vector2(110,154),Vector2(136,190),Vector2(150,210),Vector2(187,262)][row]
			for i in 2:
				var id = [&"ability_stone_copy", &"ability_gale_swap"][i]
				var cv := CardView.new().for_card(CardDB.card(id),sz)
				host.add_child(cv)
				cv.position = Vector2(32 + i * 290,20 + row * 160)
				await process_frame
				inspect_card(cv,false)
				check(cv._text.get_theme_font_size("font_size") >= 4,"краткий эффект не мельче прежних 4px: " + str(id))
				print("COMPACT_METRIC ",id," ",sz," ",cv._text.get_theme_font_size("font_size"),"px")
		await capture("editorial-compact")
		clear()
		await editorial_examples("after")
		clear()
		for frame in 4: await process_frame
		print("Краткие редакции: %d проверок, %d ошибок" % [checks,failures])
		quit(1 if failures else 0)
		return
	if OS.get_environment("CARD_LAYOUT_FOOTERS") == "1":
		for sz in [Vector2(96,134),Vector2(110,154),Vector2(136,190),Vector2(150,210),Vector2(187,262)]:
			for id in ids:
				var cv := CardView.new().for_card(CardDB.card(id),sz)
				host.add_child(cv)
				await process_frame
				inspect_text(cv._rule,"Все условия ↗","ссылка " + str(id))
				check(Rect2(Vector2.ZERO,sz).encloses(cv._rule.get_rect()),"ссылка внутри рамки")
				host.remove_child(cv)
				cv.queue_free()
		print("Ссылки раскрытия: %d проверок, %d ошибок" % [checks,failures])
		quit(1 if failures else 0)
		return

	var longest: Array = ids.duplicate()
	longest.sort_custom(func(a, b): return CardDB.card(a).full_text().length() > CardDB.card(b).full_text().length())
	print("Самые длинные эффекты: ", longest.slice(0, 6))
	# Весь каталог на фактических ширинах рук и полной карты; никаких массовых матчей.
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = root.size
	var sizes := [] if OS.get_environment("CARD_LAYOUT_FINAL") == "1" else [Vector2(96,134), Vector2(110,154), Vector2(136,190), Vector2(150,210), Vector2(187,262), Vector2(250,350)]
	for sz in sizes:
		for id in ids:
			var cv := CardView.new().for_card(CardDB.card(id), sz)
			host.add_child(cv)
			await process_frame
			inspect_card(cv, sz.x >= 224)
			check(cv._card_size == sz, "размер не зависит от текста: " + str(id))
			host.remove_child(cv)
			cv.queue_free()
	# Свежие контактные листы всех79 карт (150px), чтобы проверка была обозримой.
	for offset in range(0, ids.size(), 12):
		for i in mini(12, ids.size() - offset):
			var cv := CardView.new().for_card(CardDB.card(ids[offset + i]), Vector2(187,262))
			cv.position = Vector2(28 + (i % 6) * 224, 30 + (i / 6) * 315)
			host.add_child(cv)
		await capture("catalog-%02d" % offset)
		clear()
	for row in 3:
		var compact_size: Vector2 = [Vector2(96,134), Vector2(110,154), Vector2(136,190)][row]
		for i in 6:
			var id = [&"arena_den_grifalon", &"arena_mute", &"ability_gale_swap", &"ability_stone_copy", &"ability_kolossar_reset", &"ability_fire_counter"][i]
			var cv := CardView.new().for_card(CardDB.card(id), compact_size)
			cv.position = Vector2(32 + i * 235, 25 + row * 260)
			host.add_child(cv)
			await process_frame
			inspect_card(cv, false)
	await capture("compact-96-110-136")
	clear()
	# Общий helper заголовка затрагивает также имена49 существ; моделей не создаём.
	for sz in [Vector2(96,134), Vector2(150,210)]:
		for id in CardDB.creature_ids():
			var cv := CardView.new().for_creature(CardDB.creature(id), 0, "", sz)
			host.add_child(cv)
			await process_frame
			inspect_text(cv._title, CardDB.creature(id).display_name, "существо " + str(id), 3)
			host.remove_child(cv)
			cv.queue_free()
	var six := [&"ability_fire_assault", &"ability_gale_swap", &"ability_light_purge", &"ability_stone_copy", &"ability_shadow_doom", &"ability_tide_hush"]
	root.size = Vector2i(1600,1500)
	root.content_scale_size = root.size
	for i in six.size():
		var cv := CardView.new().for_card(CardDB.card(six[i]), Vector2(340,0), true)
		cv.position = Vector2(22 + (i % 3) * 515, 20 + (i / 3) * 720)
		host.add_child(cv)
	await capture("six-elements-full")
	clear()
	# Настоящие полные раскрытия на маленьком окне: каждый исходный эффект+условия.
	for vp in [Vector2i(960,540), Vector2i(1280,720)]:
		root.size = vp
		root.content_scale_size = vp
		var reference_size := Vector2.ZERO
		for id in ids:
			var cv := UiTheme.full_card_panel(UiTheme.card_help(CardDB.card(id))) as CardView
			host.add_child(cv)
			cv.position = Vector2(18, 14)
			await process_frame
			inspect_card(cv, true)
			if reference_size == Vector2.ZERO: reference_size = cv._card_size
			check(cv._card_size == reference_size, "все79полныхкартодинаковы: " + str(id))
			check(cv.size.x <= vp.x - 28 and cv.size.y <= vp.y - 28, "полное раскрытие в экран: %s %s %s" % [id,vp,cv.size])
			if id in longest.slice(0, 3) or id in [&"arena_mute", &"ability_stone_copy"]:
				await capture("full-%s-%d" % [id,vp.x])
			host.remove_child(cv)
			cv.queue_free()
		# Боевой статус и причина недоступности входят в подбор высоты до показа.
		for id in [&"ability_fire_counter", &"ability_stone_copy", &"arena_mute"]:
			var help := UiTheme.card_help(CardDB.card(id))
			help[6] = "Защитник. Карта отменена или подавлена; её эффект сейчас не действует. Нельзя сыграть: достигнут общий лимит трёх карт в этом бою."
			var cv := UiTheme.full_card_panel(help) as CardView
			host.add_child(cv)
			await process_frame
			inspect_card(cv, true)
			check(cv._card_size == reference_size, "боевой контекст не меняет размер карты")
			check(cv._text.text.contains(str(help[6])), "боевой контекст сохранён целиком")
			check(cv.size.y <= vp.y - 28, "полный боевой контекст помещается по высоте: %s %s %s" % [id,vp,cv.size])
			if id == &"ability_stone_copy" and vp.x == 960:
				cv.position = Vector2(18,14)
				await capture("full-dynamic-copy-960")
			host.remove_child(cv)
			cv.queue_free()
		var closed := UiTheme.card_help(CardDB.card(&"arena_field_fire"))
		closed[1] = "Ваша закрытая карта ворот"
		closed[5] = "Соперник не видит эту карту до боя."
		closed[6] = str(closed[6]) + "\nНа воротах: Драгнар Пламени."
		var closed_view := UiTheme.full_card_panel(closed) as CardView
		host.add_child(closed_view)
		await process_frame
		check(closed_view._kind.text == str(closed[1]), "закрытые ворота сохраняют особый заголовок")
		check(closed_view._text.text.contains(str(closed[5])) and closed_view._text.text.contains("На воротах:"), "видимость и обитатель сохранены")
		check(closed_view._text.text.count("Сила G по стихиям:") == 1, "G не дублируется при дополнении контекстом")
		host.remove_child(closed_view)
		closed_view.queue_free()
		# Реальное изменение ширины той же карты: цифра следует за новой геометрией.
		var resized := CardView.new().for_card(CardDB.card(&"ability_stone_copy"), Vector2(250,0),true)
		host.add_child(resized)
		for width in [360.0,224.0,300.0]:
			resized._compose_card(CardDB.card(resized.card_id),Vector2(width,0),true)
			await process_frame
			inspect_card(resized,true)
			check(absf(resized._power.get_rect().get_center().x - width * .73) < 1, "число следует за новой шириной")
		resized.queue_free()
		var preview := CreaturePreview.new()
		preview.size = Vector2(295, vp.y - 24)
		preview.position = Vector2(640,12)
		host.add_child(preview)
		await process_frame
		for id in ids:
			preview.show_card(CardDB.card(id))
			for frame in 2: await process_frame
			check(preview._full_card_scroll.visible, "колода показывает полную карту: " + str(id))
			inspect_card(preview._full_card, true)
			var bar := preview._full_card_scroll.get_v_scroll_bar()
			preview._full_card_scroll.scroll_vertical = int(bar.max_value)
			await process_frame
			check(bar.max_value <= bar.page or preview._full_card_scroll.scroll_vertical > 0, "конец полного текста достижим прокруткой")
			if id == longest[0] and vp.x == 960:
				check(not preview._full_card.tooltip_text.is_empty() and preview._full_card.mouse_filter == Control.MOUSE_FILTER_STOP,"узкая колода имеет доступное крупное раскрытие")
				var motion := InputEventMouseMotion.new()
				motion.position = preview._full_card.get_global_rect().get_center()
				Input.parse_input_event(motion)
				await create_timer(.8).timeout
				check(has_tooltip(root),"крупное раскрытие колоды показано настоящим наведением")
				await capture("deck-longest-enlarged-960")
				motion.position = Vector2(10,10)
				Input.parse_input_event(motion)
				await process_frame
				preview._full_card_scroll.scroll_vertical = 0
				await capture("deck-longest-top-960")
				preview._full_card_scroll.scroll_vertical = int(bar.max_value)
				await capture("deck-longest-bottom-960")
		preview.release()
		host.remove_child(preview)
		preview.queue_free()
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	for i in 3:
		var id = [&"arena_field_fire", &"ability_stone_copy", &"arena_mute"][i]
		var cv := UiTheme.full_card_panel(UiTheme.card_help(CardDB.card(id))) as CardView
		cv.position = Vector2(24 + i * 412, 64)
		host.add_child(cv)
		var caption := VisualUtil.label("%s · текст %dpx · %.0f×%.0f" % [id,cv._text.get_theme_font_size("font_size"),cv._card_size.x,cv._card_size.y],12)
		caption.position = Vector2(24 + i * 412, 24)
		host.add_child(caption)
	await capture("uniform-short-copy-mute-1280")
	clear()
	await editorial_examples("after")
	clear()
	print("Диапазоны фактического кегля: ",font_ranges)
	host.queue_free()
	for frame in 4: await process_frame
	print("Читаемость карт: %d проверок, %d ошибок" % [checks, failures])
	quit(1 if failures else 0)
