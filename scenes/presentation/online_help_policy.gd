extends RefCounted
## Seat/redaction policy for a network view; no reference to the application root.
const Presentation := preload("res://scenes/presentation/match_presentation.gd")
var presentation: Presentation
var local_side := -1
var snapshot: Dictionary = {}

func _init(visible: Presentation) -> void:
	presentation = visible

func set_view(data: Dictionary, side: int) -> void:
	snapshot = data
	local_side = side
	presentation.invalidate_tooltips()

func slot_tip(i: int, sl: SlotState, view: MatchState) -> Array:
	if not sl.has_card:
		if view.phase == MatchController.Phase.SETUP and view.active_player == local_side and snapshot.get("legal",{}).get("setup_slots",[]).has(i):
			return ["Свободное место","Выкладка ворот",UiTheme.GOLD,"Сюда можно положить карту ворот: рядом с уже лежащими картами.","Бросок на пустое место — промах.","",""]
		return []
	var mine := sl.card_owner == local_side
	var occ := ""
	if sl.occupant_uid >= 0:
		occ = "На воротах стоит: %s (%s)."%[presentation.cname(sl.occupant_uid),"ваше" if presentation.owner_of(sl.occupant_uid) == local_side else "существо соперника"]
	var definition := CardDB.card(sl.card_id)
	if definition == null:
		return ["Закрытые ворота соперника","Ворота · рубашкой вверх",UiTheme.GOLD_DIM,"Владелец может открыть карту во время боя. Пока ворота закрыты, их бонусы и ловушки не действуют.","Закрытая карта соперника.","",occ]
	var lines: Array = UiTheme.card_help(definition)
	if not sl.revealed and mine:
		lines[1] = "%s · ваша закрытая карта"%lines[1]
		lines[5] = "Соперник не видит эту карту до боя. "+str(lines[5])
	if occ != "": lines[6] = (str(lines[6])+"\n"+occ).strip_edges()
	return lines

func creature_tip(uid: int, view: MatchState) -> Array:
	var lines: Array = presentation.creature_tip(uid,view)
	var mine := presentation.owner_of(uid) == local_side
	var detail := str(lines[1]).trim_suffix(" · ваше существо").trim_suffix(" · существо соперника")
	lines[1] = "%s · %s"%[detail,"ваше существо" if mine else "существо соперника"]
	# The base helper's final prethrow line assumes seat zero.
	if view.creature(uid).slot < 0:
		var text := str(lines[6])
		text = text.replace("Выберите подсвеченные ворота для броска сферы", "Шар соперника") if not mine else text.replace("Шар соперника","Выберите подсвеченные ворота для броска сферы")
		lines[6] = text
	return lines


