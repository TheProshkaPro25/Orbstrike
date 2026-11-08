class_name UiTheme
extends RefCounted
## Общая тема интерфейса: тёмные полупрозрачные панели с золотой каймой, кнопки в том же стиле.

const ElementIcon := preload("res://scenes/element_icon.gd")

const GOLD := Color(0.95, 0.80, 0.45)
const GOLD_DIM := Color(0.62, 0.50, 0.28)
const INK := Color(0.035, 0.055, 0.095, 0.96)
const TEXT := Color(0.96, 0.93, 0.86)
const TEXT_DIM := Color(0.73, 0.78, 0.85)
const ABILITY_BASE := Color(0.30, 0.16, 0.46)
const ABILITY_GLOW := Color(1.0, 0.80, 0.45)
const ARENA_NEUTRAL := Color(0.55, 0.47, 0.33)

static var _theme: Theme
static var _body_font: FontFile
static var _heading_font: FontFile
const DEVICE_ACCENT := Color(0.40, 0.94, 0.93)
const DEVICE_DIM := Color(0.20, 0.48, 0.53)
const DEVICE_INK := Color(0.018, 0.045, 0.065, 0.97)


static func accent() -> Color:
	return DEVICE_ACCENT if DeviceSettings.is_device() else GOLD


static func accent_dim() -> Color:
	return DEVICE_DIM if DeviceSettings.is_device() else GOLD_DIM


static func panel_color() -> Color:
	return DEVICE_INK if DeviceSettings.is_device() else INK


static func _refresh_theme(_style: int) -> void:
	# Keep the shared Theme identity: Boot's resident screens already reference it.
	_theme.clear()
	_theme.merge_with(_make_device() if DeviceSettings.is_device() else _make())
	_theme.default_font = body_font()
	_theme.default_font_size = 18


static func _make_device() -> Theme:
	var t := _make()
	var panel := box(DEVICE_INK, DEVICE_DIM, 1, 3, 16)
	panel.border_width_top = 3
	panel.shadow_color = Color(0.05, 0.50, 0.56, 0.12)
	panel.shadow_size = 6
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "TooltipPanel", box(DEVICE_INK, DEVICE_ACCENT, 1, 3, 10))
	var states := {
		"normal": [Color(0.035, 0.09, 0.12, 0.98), DEVICE_DIM],
		"hover": [Color(0.055, 0.18, 0.22), DEVICE_ACCENT],
		"pressed": [Color(0.065, 0.28, 0.31), DEVICE_ACCENT],
		"hover_pressed": [Color(0.065, 0.28, 0.31), DEVICE_ACCENT],
		"disabled": [Color(0.04, 0.065, 0.08, 0.80), Color(0.18, 0.26, 0.29)],
	}
	for state: String in states:
		var style := box(states[state][0], states[state][1], 1, 3, 10)
		style.border_width_left = 3
		t.set_stylebox(state, "Button", style)
	var focus := box(Color.TRANSPARENT, DEVICE_ACCENT.lightened(0.25), 2, 3, 10)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	for type: String in ["Button", "OptionButton", "CheckButton", "CheckBox"]:
		t.set_color("font_color", type, Color(0.86, 0.96, 0.97))
		t.set_color("font_pressed_color", type, DEVICE_ACCENT)
		t.set_color("font_hover_color", type, Color.WHITE)
	t.set_color("font_color", "Label", Color(0.86, 0.96, 0.97))
	t.set_stylebox("slider", "HSlider", box(Color(0.04, 0.11, 0.14), DEVICE_DIM, 1, 2, 0))
	t.set_stylebox("grabber_area", "HSlider", box(DEVICE_DIM, DEVICE_ACCENT, 0, 2, 0))
	return t


## Shared style/lifecycle helper. It never draws decoration or covers input.
static func apply_device_frame(root: Control, caption: String = "ORBSTRIKE", decoration: bool = true) -> void:
	if root.has_node("DeviceFrame"):
		return
	root.theme = get_theme()
	var frame := DeviceFrame.new()
	frame.name = "DeviceFrame"
	frame.caption = caption
	frame.decoration = decoration
	root.add_child(frame)


## Reuses the resident UI with one short opacity fade.
## Controls keep their layout, input and processing for the entire animation.
static func begin_hud_intro(root: Control) -> void:
	if root.has_node("DeviceFrame"):
		(root.get_node("DeviceFrame") as DeviceFrame).play_intro()


class DeviceFrame extends Control:
	var caption := "ORBSTRIKE"
	var decoration := true
	var intro_tween: Tween
	var _pending := false

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 15
		resized.connect(_stop_intro)

	func _enter_tree() -> void:
		# Resident menus leave and re-enter the tree when GameLoading parks them.
		# _ready runs only once, so subscriptions belong to the enter/exit pair.
		if not DeviceSettings.events().changed.is_connected(_changed):
			DeviceSettings.events().changed.connect(_changed)
		if not get_tree().node_added.is_connected(_node_added):
			get_tree().node_added.connect(_node_added)
		if not DeviceSettings.events().motion_changed.is_connected(_motion_changed):
			DeviceSettings.events().motion_changed.connect(_motion_changed)
		_changed(DeviceSettings.current())

	func _exit_tree() -> void:
		_stop_intro()
		if DeviceSettings.events().motion_changed.is_connected(_motion_changed):
			DeviceSettings.events().motion_changed.disconnect(_motion_changed)
		if DeviceSettings.events().changed.is_connected(_changed):
			DeviceSettings.events().changed.disconnect(_changed)
		if get_tree().node_added.is_connected(_node_added):
			get_tree().node_added.disconnect(_node_added)

	func _node_added(node: Node) -> void:
		if get_parent().is_ancestor_of(node) and not _pending:
			_pending = true
			_refresh.call_deferred()

	func _changed(_style: int) -> void:
		_stop_intro()
		visible = DeviceSettings.is_device()
		_refresh.call_deferred()

	func _refresh() -> void:
		_pending = false
		if is_inside_tree():
			_restyle(get_parent())

	func _restyle(node: Node) -> void:
		# Accepted card artwork, fonts and proportions remain their own presentation.
		if node is CardView or node == self:
			return
		if node is Control:
			var control := node as Control
			for key: String in ["panel", "normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
				if not control.has_theme_stylebox_override(key):
					continue
				var current_style := control.get_theme_stylebox(key)
				if not current_style is StyleBoxFlat:
					continue
				var original: StyleBoxFlat = current_style.get_meta("device_original", current_style)
				if not DeviceSettings.is_device():
					control.add_theme_stylebox_override(key, original)
					continue
				var style: StyleBoxFlat = original.duplicate()
				style.set_meta("device_original", original)
				style.set_corner_radius_all(3)
				style.skew = Vector2.ZERO
				if original.bg_color.get_luminance() < 0.10:
					style.bg_color = Color(DEVICE_INK, original.bg_color.a)
				if original.border_color.is_equal_approx(GOLD) or original.border_color.is_equal_approx(GOLD_DIM):
					style.border_color = DEVICE_ACCENT if original.border_color.is_equal_approx(GOLD) else DEVICE_DIM
				control.add_theme_stylebox_override(key, style)
			if control.has_theme_color_override("font_color"):
				var color := control.get_theme_color("font_color")
				if DeviceSettings.is_device():
					if color.is_equal_approx(GOLD): control.add_theme_color_override("font_color", DEVICE_ACCENT)
					elif color.is_equal_approx(GOLD_DIM): control.add_theme_color_override("font_color", DEVICE_DIM)
				else:
					if color.is_equal_approx(DEVICE_ACCENT): control.add_theme_color_override("font_color", GOLD)
					elif color.is_equal_approx(DEVICE_DIM): control.add_theme_color_override("font_color", GOLD_DIM)
		for child in node.get_children():
			_restyle(child)

	func _motion_changed(reduced: bool) -> void:
		if reduced: _stop_intro()

	func _stop_intro() -> void:
		if intro_tween != null and intro_tween.is_valid(): intro_tween.kill()
		intro_tween = null
		if is_instance_valid(get_parent()): get_parent().modulate.a = 1.0

	func play_intro() -> void:
		_stop_intro()
		if not DeviceSettings.is_device() or DeviceSettings.reduce_motion(): return
		get_parent().modulate.a = 0.18
		intro_tween = create_tween().set_parallel(true).set_ignore_time_scale(true)
		intro_tween.tween_property(get_parent(), "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		intro_tween.finished.connect(func() -> void: intro_tween = null)



static func body_font() -> Font:
	if _body_font == null:
		_body_font = load("res://assets/fonts/FiraSans-Regular.ttf")
	return _body_font


static func heading_font() -> Font:
	if _heading_font == null:
		_heading_font = load("res://assets/fonts/FiraSans-SemiBold.ttf")
	return _heading_font


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _make_device() if DeviceSettings.is_device() else _make()
		DeviceSettings.events().changed.connect(_refresh_theme)
	return _theme


## Плашка: фон, кайма, скругление, внутренние отступы.
static func box(bg: Color, border: Color, bw: int = 2, radius: int = 10, pad: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func _make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.default_font = body_font()
	t.set_font("font", "Button", heading_font())

	var panel := box(INK, Color(0.28, 0.38, 0.49), 1, 8, 16)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 8
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var tip := box(Color(0.05, 0.05, 0.08, 0.96), GOLD_DIM, 2, 8, 8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 15)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 1)

	var bn := box(Color(0.09, 0.14, 0.21, 0.98), GOLD_DIM, 2, 8, 10)
	var bh := box(Color(0.15, 0.24, 0.32, 1.0), GOLD, 2, 8, 10)
	var bp := box(Color(0.36, 0.27, 0.14, 0.97), GOLD, 2, 8, 10)
	var bd := box(Color(0.12, 0.12, 0.14, 0.75), Color(0.3, 0.3, 0.32), 2, 8, 10)
	var bf := box(Color(0, 0, 0, 0), GOLD, 2, 8, 10)
	bf.draw_center = false
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("hover_pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", bf)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_hover_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Button", 0)
	return t


const FUSION_BASE := Color(0.10, 0.30, 0.34)
const FUSION_GLOW := Color(0.70, 1.0, 0.92)
const SPECIES_BASE := Color(0.24, 0.30, 0.14)
const SPECIES_GLOW := Color(0.78, 1.0, 0.55)


## Цвета карты способности/ворот: (основа, свечение).
## Стихийные и усиления — в цвете своей стихии, видовые — болотно-зелёные, слияние — бирюзовое.
static func card_colors(def: CardDef) -> Array:
	if def == null:
		return [ARENA_NEUTRAL, GOLD]
	if def.kind == CardDef.Kind.ABILITY:
		if CardEffects.is_fusion(def):
			return [FUSION_BASE, FUSION_GLOW]
		if CardEffects.species_lock(def) != &"":
			return [SPECIES_BASE, SPECIES_GLOW]
		var lock: int = CardEffects.lock_attr(def)
		if lock >= 0:
			var lc: Color = VisualUtil.attr_color(lock)
			if def.effect_id == &"boost":
				return [lc.darkened(0.6), lc.lightened(0.15)]
			return [lc.darkened(0.45), lc.lightened(0.35)]
		return [ABILITY_BASE, ABILITY_GLOW]
	var a: int = int(def.params.get("attribute", def.params.get("attr", -1)))
	if a >= 0:
		var c: Color = VisualUtil.attr_color(a)
		return [c.darkened(0.25), c.lightened(0.45)]
	if def.effect_id == &"species_double":
		return [SPECIES_BASE, SPECIES_GLOW]
	if CardEffects.is_gate_trap(def):
		return [Color(0.42, 0.16, 0.12), Color(1.0, 0.55, 0.4)]
	return [ARENA_NEUTRAL, GOLD]


## Подпись типа под названием.
static func card_kind(def: CardDef) -> String:
	var sp: StringName = CardEffects.species_lock(def)
	if def.kind != CardDef.Kind.ABILITY:
		match CardDB.card_class(def):
			&"gold":
				return "Ворота стихии"
			&"silver":
				return "Ворота вида · %s" % CardDB.species_name(sp)
		return "Ловушка" if CardEffects.is_gate_trap(def) else "Командные ворота"
	if sp != &"":
		return "%s · %s" % ["Слияние" if CardEffects.is_fusion(def) else "Вид", CardDB.species_name(sp)]
	var lock: int = CardEffects.lock_attr(def)
	if lock >= 0:
		return "%s · %s" % ["Усиление" if def.effect_id == &"boost" else "Стихия", VisualUtil.attr_name(lock)]
	return "Способность"


## Тип рамки карты (CardView.Frame): тип читается с одного взгляда — форма окна, металл, накладки.
static func card_frame(def: CardDef) -> int:
	if def == null:
		return CardView.Frame.ELEMENT
	match CardDB.card_class(def):
		&"gold":
			return CardView.Frame.FIELD
		&"silver":
			return CardView.Frame.SPECIES_GATE
		&"bronze":
			return CardView.Frame.TRAP if CardEffects.is_gate_trap(def) else CardView.Frame.COMMAND
		&"blue":
			return CardView.Frame.BOOST
		&"green":
			return CardView.Frame.FUSION if CardEffects.is_fusion(def) else CardView.Frame.SPECIES
	return CardView.Frame.ELEMENT


## Ступени силы у медальона (усиления и видовые прибавки): 1 — до +50, 2 — до +150, 3 — больше.
static func card_tier(def: CardDef) -> int:
	if def == null or def.kind != CardDef.Kind.ABILITY or not (def.effect_id in [&"boost", &"boost_fix", &"fusion_boost"]):
		return 0
	var n: int = int(def.params.get("amount", 0))
	return 1 if n <= 50 else (2 if n <= 150 else 3)


## Знак вида (21..28 в card_face.gdshaderinc) по порядку GameData.SPECIES; -1 — нет такого вида.
static func species_sigil(sp: StringName) -> int:
	for i in range(GameData.SPECIES.size()):
		if StringName(GameData.SPECIES[i]["id"]) == sp:
			return 21 + i
	return -1


## Символ в центре карты (см. card_face.gdshaderinc, cf_sigil: 1..6 стихии, 7 слияние, 8 щит, 9/10 стрелки, 11 обмен, 12 запрет,
## 13 плюс, 14 перенос, 15 бездна, 16 возрождение, 17 копия, 18 когти, 19 ×2, 20 флаг, 21..28 виды, 0 эмблема).
static func card_sigil(def: CardDef) -> int:
	if CardEffects.is_fusion(def):
		return 7
	# ворота вида — знак своего вида; усиление стихии — знак стихии (ступени силы — ромбы у медальона)
	if def.effect_id == &"species_double" and species_sigil(CardEffects.species_lock(def)) > 0:
		return species_sigil(CardEffects.species_lock(def))
	if def.effect_id == &"boost" and CardEffects.species_lock(def) == &"" and CardEffects.lock_attr(def) >= 0:
		return CardEffects.lock_attr(def) + 1
	match String(def.effect_id):
		"negate", "cap_own_base":
			return 8
		"boost", "boost_fix", "owner_power":
			return 9 if CardEffects.species_lock(def) == &"" or def.effect_id != &"boost" else 18
		"scorch", "weaken_mark", "weaken", "funnel", "weight":
			return 10
		"drain", "siphon", "shift_gate", "mirror":
			return 11
		"purge_gate", "eclipse", "silence", "nullify_gate", "strip", "mute", "limit":
			return 12
		"reset_base", "web":
			return 13
		"gust", "swap_fighter", "ebb", "aloft":
			return 14
		"doom", "clash":
			return 15
		"revive", "recall", "fallen_call":
			return 16
		"copy":
			return 17
		"species_double":
			return 19
		"hold":
			return 20
		"radiance":
			return 3
		"pact", "dusk_throne":
			return 5
	var a: int = int(def.params.get("attr", -1))
	if def.kind == CardDef.Kind.ARENA and a >= 0:
		return a + 1
	return 0


## Короткий значок силы карты.
static func card_badge(def: CardDef) -> String:
	var n: int = int(def.params.get("amount", 0))
	match String(def.effect_id):
		"flame_toll":
			return ""
		"drain", "radiance", "pact", "funnel":
			return "+%d / −%d" % [n, n]
		"scorch", "eclipse", "weaken_mark", "weaken", "weight":
			return "−%d" % n
		"negate":
			return "−%d" % n if n > 0 else ""
		"species_double":
			return "×2"
		"limit":
			return "%d" % n
		"attr_bonus":
			var g: Array = def.params.get("g", [])
			var a: int = int(def.params.get("attr", 0))
			return "+%d" % (int(g[a]) if a < g.size() else n)
	if n > 0:
		return "+%d" % n
	if n < 0:
		return "−%d" % -n
	return ""


## Какие кружки стихий подсветить на карте.
static func card_elements(def: CardDef) -> Array:
	var lock: int = CardEffects.lock_attr(def)
	if lock >= 0:
		return [lock]
	var a: int = int(def.params.get("attr", -1))
	if a >= 0:
		return [a]
	if def.effect_id == &"dusk_throne":
		return [4]
	return []


## Короткая роль дополняет цвет стихии и форму рамки: что карта делает в бою.
static func card_role(def: CardDef) -> String:
	match String(def.effect_id):
		"negate": return "Ответная отмена" if bool(def.params.get("reactive", false)) else "Отмена"
		"boost", "fusion_boost", "owner_power", "attr_bonus": return "Усиление"
		"boost_fix": return "Сила и метка"
		"species_double": return "База ×2"
		"drain", "siphon", "funnel", "radiance", "pact": return "Перекачка силы"
		"scorch", "weaken_mark": return "Ослабление и метка"
		"weaken", "weight": return "Ослабление"
		"purge_gate", "eclipse", "nullify_gate", "aloft": return "Подавление ворот"
		"silence", "mute": return "Подавление карт"
		"strip": return "Снятие бонусов"
		"cap_own_base", "reset_base": return "Сброс силы"
		"copy": return "Копирование"
		"gust", "ebb": return "Перелёт"
		"swap_fighter": return "Замена бойца"
		"shift_gate": return "Смена ворот"
		"revive", "fallen_call", "recall": return "Возвращение"
		"doom", "clash": return "Обоюдная гибель"
		"limit": return "Порог поражения"
		"mirror": return "Обмен силой"
		"hold": return "Удержание"
		"web": return "Сила за ворота"
		"flame_toll": return "Плата за ответ"
		"gale_call": return "Возврат союзника"
		"light_reserve": return "Возврат усиления"
		"stone_ceiling": return "Предел прибавок"
		"shadow_triumph": return "Перехват хода"
		"tide_wash": return "Восстановление силы"
		"valor": return "Спасение слабейшего"
		"dusk_throne": return "Победа Тени"
	return "Эффект"


## На лице — действие и цена; исключения и последовательность раскрывает наведение.
## Не уплотнять длинные правила до микротекста на карточке руки.
static func card_face_text(def: CardDef) -> String:
	return def.text


## Самое важное условие видно без наведения. Полный набор остаётся в тексте.
static func card_rule_tag(def: CardDef) -> String:
	if def.kind == CardDef.Kind.ARENA:
		return "После открытия"
	var tags: PackedStringArray = []
	match String(def.params.get("cond", "")):
		"attack": tags.append("В атаке")
		"defense": tags.append("В защите")
		"own_gate": tags.append("Свои ворота")
		"weaker": tags.append("Слабее по базе")
		"underdog": tags.append("Слабее база / стихия")
		"fallen": tags.append("Есть выбывшие")
		"behind": tags.append("Меньше существ")
		"last": tags.append("Последний боец")
	if bool(def.params.get("lockout", false)):
		tags.append("Больше не играть")
	elif bool(def.params.get("sure", false)):
		tags.append("Без отмены")
	elif bool(def.params.get("returns", false)):
		tags.append("Возврат")
	elif CardEffects.is_fusion(def):
		tags.append("Поверх своей карты")
	elif str(def.params.get("moment", "")) == "battle":
		tags.append("Только в бою")
	return " · ".join(tags)


static func card_role_color(def: CardDef) -> Color:
	match String(def.effect_id):
		"negate", "doom", "clash", "limit": return Color(1.0, 0.46, 0.38)
		"purge_gate", "eclipse", "nullify_gate", "aloft", "silence", "mute": return Color(0.76, 0.61, 1.0)
		"gust", "ebb", "swap_fighter", "shift_gate", "copy": return Color(0.4, 0.83, 1.0)
		"revive", "fallen_call", "recall": return Color(0.49, 0.95, 0.69)
	return GOLD


# ---------------------------------------------------------------- подсказки для новичка

const CLASS_HELP := {
	&"gold": ["Ворота стихии", "Карта поля боя. Кладётся рубашкой вверх и открывается в бою. «Поле» даёт силу только существу своей стихии (у каждой стихии своё число), «Алтарь силы» — +300 защитнику-владельцу."],
	&"silver": ["Ворота вида", "Существо этого вида на воротах удваивает базовую силу — у любой стороны, так что соперник тоже может ими воспользоваться."],
	&"bronze": ["Командные ворота", "Меняют правила боя: перекачка силы, предел силы, удержание, возврат выбывших. Закрытые ворота не действуют. Ловушки включаются после открытия; бой продолжается до итога обмена."],
	&"red": ["Стихийная способность", "Играет только существо своей стихии. У каждой стихии есть особые эффекты и ответная отмена: без прибавки силы, только против уже сыгранной карты."],
	&"blue": ["Усиление", "Прибавка силы своей стихии. Крупные усиления требуют условия; защита от отмены и возврат в руку указаны на самой карте."],
	&"green": ["Видовая способность", "Играет только существо своего вида любой стихии: отмена, сброс силы, перекачка бонусов, «нельзя отменить»."],
}
const GATE_WHEN := "До броска: одни ворота за ход, рядом с другими, ближе к сопернику. Открывай в свой ответ в бою. Закрытые не действуют."


## Строки подсказки для карты: [заголовок, тип, цвет типа, описание типа, эффект, когда играть].
static func card_help(def: CardDef) -> Array:
	var cls: StringName = CardDB.card_class(def)
	var info: Array = CLASS_HELP.get(cls, ["Карта", ""])
	var when: String = GATE_WHEN
	if def.kind == CardDef.Kind.ABILITY:
		when = "В бою / прикреплением до броска или после приземления. До 3 карт стороны на бой."
		if CardEffects.is_fusion(def):
			when = "В бою поверх своей способности. До 3 карт стороны на бой."
		elif CardEffects.moment(def) == &"battle":
			when = "В бою, в свой ответ. До 3 карт стороны на бой."
		elif CardEffects.moment(def) == &"landing":
			when = "Только после приземления."
		if CardEffects.returns_to_hand(def):
			when += " После боя — в руку."
		elif not MatchRules.last_rush_returns(def):
			when += " Отдых: 2 следующих боя, даже у последнего существа."
		else:
			when += " Отдых: 2 следующих боя; у последнего существа — в руку."
	# Исключения описаны самим эффектом; не повторяем их в общей строке сроков.
	var kind: String = card_kind(def)
	var cc := {&"gold": Color(1.0, 0.82, 0.35), &"silver": Color(0.82, 0.86, 0.92), &"bronze": Color(0.9, 0.58, 0.32),
		&"red": Color(1.0, 0.45, 0.4), &"blue": Color(0.5, 0.7, 1.0), &"green": Color(0.5, 0.92, 0.58)}
	var extra: String = ""
	if def.kind == CardDef.Kind.ARENA:
		var g: Array = def.params.get("g", [])
		var parts: PackedStringArray = []
		for a in range(mini(6, g.size())):
			if int(g[a]) != 0:
				parts.append("%s +%d" % [VisualUtil.attr_name(a), int(g[a])])
		if not parts.is_empty():
			extra = "Сила G по стихиям: " + ", ".join(parts)
	return [def.display_name, kind, cc.get(cls, GOLD), info[1], def.full_text(), when, extra,
		{"role": card_role(def), "rule": card_rule_tag(def), "color": card_role_color(def), "card_id": def.id}]


## Подсказка для существа: имя, стихия, сила и совместимость карт.
static func creature_help(d: CreatureDef) -> Array:
	return [d.display_name, "Существо · стихия %s" % VisualUtil.attr_name(d.attribute), VisualUtil.attr_color(d.attribute).lightened(0.3),
		"Сила G (базовая): %d. В бою к ней прибавляются сила ворот и способности." % d.base_power,
		"Стихия определяет совместимые способности и силу от ворот.",
		"Бросается на карту ворот. Проиграв бой, выбывает; победив — уходит в зону использованных.", "", d.attribute]


## Explicit full-card preview for catalog/readability checks; never used by passive hover.
static func full_card_panel(lines: Array) -> CardView:
	var def := CardDB.card(lines[7]["card_id"])
	var tree := Engine.get_main_loop() as SceneTree
	var available := Vector2(960, 540) if tree == null else tree.root.get_visible_rect().size
	var width := minf(360.0, floorf((available.y - 64.0) / 1.4))
	width = minf(width, available.x - 64.0)
	var card := CardView.new().for_card(def, Vector2(width, roundf(width * 1.4)), true, lines)
	card.tooltip_text = ""
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.focus_mode = Control.FOCUS_NONE
	return card


## Панель подсказки (используется в CardView._make_custom_tooltip).
static func help_panel(lines: Array) -> Control:
	if lines.size() > 7 and lines[7] is Dictionary and lines[7].has("card_id"):
		return preload("res://scenes/ui/card_hint.gd").new().configure(lines)

	var small_screen := false
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		small_screen = tree.root.size.y <= 600
	var body_width := 400.0 if small_screen else 340.0
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(0.05, 0.05, 0.08, 0.96), lines[2], 2, 10, 12))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.custom_minimum_size = Vector2(body_width, 0)
	p.add_child(vb)
	var t := VisualUtil.label(str(lines[0]), 20)
	t.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
	if lines.size() > 7 and typeof(lines[7]) == TYPE_INT and int(lines[7]) >= 0:
		# существо: значок стихии перед именем
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ic := TextureRect.new()
		ic.texture = ElementIcon.badge(int(lines[7]))
		ic.custom_minimum_size = Vector2(30, 30)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		row.add_child(t)
		vb.add_child(row)
	else:
		vb.add_child(t)
	var k := VisualUtil.label(str(lines[1]).to_upper(), 12)
	k.add_theme_color_override("font_color", lines[2])
	k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	k.custom_minimum_size.x = body_width
	vb.add_child(k)
	if lines.size() > 7 and lines[7] is Dictionary:
		var summary: Dictionary = lines[7]
		var role := VisualUtil.label(str(summary["role"]).to_upper(), 14)
		role.add_theme_color_override("font_color", summary["color"])
		vb.add_child(role)
		if not str(summary["rule"]).is_empty():
			var rule := VisualUtil.label(str(summary["rule"]), 13)
			rule.add_theme_color_override("font_color", GOLD)
			vb.add_child(rule)
	# Объяснение класса есть в выборе колоды. В наведении приоритет у эффекта и доступности.
	var sections := [4, 6, 5] if lines.size() > 7 and lines[7] is Dictionary else [3, 4, 6, 5]
	for i in sections:
		var txt: String = str(lines[i])
		if txt == "":
			continue
		var l := VisualUtil.label(txt, 15 if i == 4 else 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(body_width, 0)
		l.add_theme_color_override("font_color", TEXT if i == 4 else TEXT_DIM)
		vb.add_child(l)
	return p
