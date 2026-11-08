extends "res://tests/card_readability_tests.gd"
## Четыре изменённые цены: полный текст, минус в числе, прежний прямоугольник.
const PRICE_IDS := [&"ability_light_revive", &"ability_gale_gust", &"ability_gale_leap", &"ability_gale_swap"]
const EXPECTED_BADGES := ["−100", "+80", "+120", "+200"]

func _run() -> void:
	CardDB.load_all()
	var sure_only := OS.get_cmdline_user_args().has("sure-only")
	var leap_only := OS.get_cmdline_user_args().has("leap-only")
	var pact_only := OS.get_cmdline_user_args().has("pact-only")
	var ids: Array = [&"ability_light_glint", &"ability_fire_spark"] if sure_only else PRICE_IDS
	var badges: Array = ["+30", "+30"] if sure_only else EXPECTED_BADGES
	out_dir = "res://build/checks/presentation/selected-card-sure-price-ui/card-sure-price-ui" if sure_only else "res://build/checks/presentation/selected-card-price-ui/card-price-ui"
	if leap_only:
		ids = [&"ability_gale_leap", &"ability_gale_gust"]
		badges = ["+120", "+80"]
		out_dir = "res://build/checks/presentation/selected-card-leap-price-ui/card-leap-price-ui"
	if pact_only:
		ids = [&"ability_shadow_pact", &"ability_light_crown"]
		badges = ["+40 / −40", "+50 / −50"]
		out_dir = "res://build/checks/presentation/selected-card-pact-price-ui/card-pact-price-ui"
	var power_labels: Array = ["±40", "±50"] if pact_only else badges
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.theme = UiTheme.get_theme()
	RenderingServer.set_default_clear_color(Color(.025, .035, .06))
	host = Control.new()
	root.add_child(host)
	for i in ids.size():
		var definition := CardDB.card(ids[i])
		check(UiTheme.card_badge(definition) == badges[i], "числовой badge соответствует цене: " + String(ids[i]))
		check(CardView.power_text(UiTheme.card_badge(definition)) == power_labels[i], "числовая оболочка сохраняет знак")
		var text := definition.full_text()
		if pact_only:
			var amount: int = 40 if i == 0 else 50
			check(int(definition.params.amount) == amount, "цена Пакта40 и контроль Венца50")
			check(text.contains("+%d" % amount) and text.contains("−%d" % amount), "оба мгновенных изменения указаны")
			check(text.count("+%d" % amount) == (2 if i == 0 else 1) and text.count("−%d" % amount) == (1 if i == 0 else 2), "мгновенный эффект и последующие метки используют одну цену")
			if i == 0: check(not text.contains("50"), "старой цены50 в тексте Пакта нет")
			check(text.contains("Остальные твои") if i == 0 else text.contains("Остальные его"), "адресат следующих меток сохранён")
			check(text.contains("следующем бою"), "срок меток указан полностью")
		elif sure_only:
			check(text.contains("+30") and not text.contains("+50") and bool(definition.params.sure), "единая цена30 и защита от отмены указаны")
		elif leap_only:
			check(text.contains("+180") if i == 0 else text.contains("+60"), "базовая цена и прежний условный бонус отражены")
			check(int(definition.params.vs_adv) == 60, "условная доплата осталась60G")
		elif i == 0:
			check(text.contains("−100"), "новая отрицательная цена присутствует в эффекте")
			check(text.contains("своему бойцу") and text.contains("включая только что проигравшего"), "цена и спасение текущего проигравшего объяснены")
		else:
			check(text.contains(["", "+60", "+180", "+260"][i]), "новая условная цена присутствует в эффекте")
			check(int(definition.params.vs_adv) == 60, "общая условная прибавка60G")
	if sure_only: check(UiTheme.card_badge(CardDB.card(&"ability_shadow_haze")) == "+30", "неизменённая Дымка сохраняет тот же стандарт")
	for extent in [Vector2i(960,540), Vector2i(1280,720)]:
		root.size = extent
		root.content_scale_size = extent
		var expected_w := minf(360, floorf((extent.y - 64) / 1.4))
		var expected_size := Vector2(expected_w, roundf(expected_w * 1.4))
		for pair in int(ids.size() / 2):
			clear()
			for i in 2:
				var idx: int = pair * 2 + i
				var cv := UiTheme.full_card_panel(UiTheme.card_help(CardDB.card(ids[idx]))) as CardView
				cv.position = Vector2((extent.x - expected_w * 2 - 28) * .5 + i * (expected_w + 28), 20)
				host.add_child(cv)
			await process_frame
			for cv in host.get_children():
				inspect_card(cv, true)
				check(cv._card_size == expected_size and cv.size == expected_size, "общая фиксированная геометрия полного раскрытия")
				check(cv._power.text == power_labels[ids.find(cv.card_id)], "отображаемое число и знак совпадают")
			check(Engine.max_fps == 60 and root.unfocusable and root.mode == Window.MODE_MINIMIZED, "60FPS minimized nonfocusable")
			await capture("price-%d-%d" % [extent.x, pair])
	clear()
	for width in [96,150]:
		for i in ids.size():
			var cv := CardView.new().for_card(CardDB.card(ids[i]), Vector2(width, roundf(width * 1.4)))
			host.add_child(cv)
			await process_frame
			inspect_card(cv, false)
			check(cv._power.text == power_labels[i] and cv._card_size == Vector2(width, roundf(width * 1.4)), "компактная цена и прямоугольник сохранены")
			clear()
	var output := FileAccess.open(out_dir.path_join("summary.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "sure_only": sure_only, "leap_only": leap_only, "pact_only": pact_only, "scope": "Только выбранная пара/цены: настоящее full раскрытие960/1280, compact96/150, badge/знак/текст/фиксированная геометрия. Режимы only не повторяют остальные карты. Без полного каталога/матча/3D."}, "\t"))
	print("CARD PRICE UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
