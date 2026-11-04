extends SceneTree
## Выбор Шквала: настоящий контроллер, публичный прогноз и безопасная альтернатива.
const GUST := &"ability_gale_leap"
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func position(player: int, gate: StringName, strong: bool = false, revealed: bool = false, replies: bool = false) -> MatchController:
	var ctrl := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(1), 8841)
	ctrl._draw_pools = [[[], []], [[], []]]
	ctrl.start(player)
	for sl in ctrl.state.slots:
		sl.has_card = false
		sl.card_id = &""
		sl.occupant_uid = -1
	for p in [0, 1]:
		ctrl.state.players[p].ability_hand.clear()
		for uid in ctrl.state.players[p].creature_uids:
			ctrl.state.creatures[uid].slot = -1
			ctrl.state.creatures[uid].used = true
			ctrl.state.creatures[uid].def_id = &"creature_dragnar_gale" if p == player else &"creature_dragnar_tide"
	var own := player * 3
	var foe := (1 - player) * 3
	ctrl.state.creatures[own].def_id = &"gust_test_strong" if strong else &"gust_test_own"
	ctrl.state.creatures[foe].def_id = &"gust_test_small" if strong else &"gust_test_foe"
	for tuple in [[player * 3, own, player, &"arena_field_gale"], [(1 - player) * 3, foe, 1 - player, gate]]:
		var sl := ctrl.state.slots[int(tuple[0])]
		sl.has_card = true
		sl.card_id = tuple[3]
		sl.card_owner = tuple[2]
		sl.occupant_uid = tuple[1]
		sl.revealed = revealed if int(tuple[2]) != player else false
		ctrl.state.creatures[int(tuple[1])].slot = int(tuple[0])
		ctrl.state.creatures[int(tuple[1])].used = false
	ctrl.state.players[player].ability_hand.assign([GUST])
	if replies:
		ctrl.state.players[1 - player].ability_hand.assign([&"ability_tide_hush", &"ability_tide_surf", &"ability_tide_ninth"])
	ctrl.state.phase = MatchController.Phase.AFTER_LANDING
	ctrl.state.active_player = player
	ctrl._pending_uid = own
	ctrl._landed_uid = own
	ctrl._turn_player = player
	return ctrl

func _initialize() -> void:
	Engine.max_fps = 60
	AudioServer.set_bus_mute(0, true)
	CardDB.load_all()
	for tuple in [[&"gust_test_own", 1, 340], [&"gust_test_foe", 5, 360], [&"gust_test_strong", 1, 620], [&"gust_test_small", 5, 200], [&"gust_test_foe470", 5, 470]]:
		var definition := CreatureDef.make(tuple[0], String(tuple[0]), tuple[1], tuple[2], Color.WHITE)
		definition.species = &"rogozhuk" if int(tuple[1]) == 1 else &"klykar"
		CardDB._creatures[String(tuple[0])] = definition
	for player in [0, 1]:
		var masked := ""
		for gate in [&"arena_funnel", &"arena_field_tide", &"arena_den_klykar"]:
			var ctrl := position(player, gate)
			var view := ctrl.get_view(player)
			var own: int = player * 3
			var foe: int = (1 - player) * 3
			var ai := AIPlayer.new(player, 91, -1.0, AIPlayer.Difficulty.HARD)
			var encoded := JSON.stringify(OnlineStateCodec.encode_view(view))
			if masked == "": masked = encoded
			check(encoded == masked, "скрытые ID трёх ворот дают одинаковый публичный вид")
			check(ai.choose_attach(view, own, [GUST]) == &"", "Шквал не начинает бой по одному нейтральному перевесу: " + String(gate))
			check(JSON.stringify(OnlineStateCodec.encode_view(view)) == encoded, "решение не меняет публичное состояние")
			var ready := view.duplicate_full()
			ready.slots[ready.creatures[own].slot].occupant_uid = -1
			ready.creatures[own].slot = -1
			var pick := ai.choose_throw(ready)
			check(int(pick.target_slot) != view.creatures[foe].slot, "обычный бросок уже предпочитает безопасные свои ворота")
			var results: Array = []
			ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
			check(ctrl.play_ability(player, GUST) == OK, "контрольный прежний прыжок разрешён правилами")
			check(ctrl.get_active_player() == 1 - player and ctrl.can_reveal_gate(1 - player), "защитник получает настоящее окно ворот")
			check(ctrl.reveal_gate(1 - player) == OK, "защитник открывает свои ворота")
			check(results.size() == 1 and results[0].loser_uid == own, "открытие действительно переворачивает ложный прыжок")
			check(not ctrl.state.creatures[own].alive, "контроллер реально выводит прыгнувшего бойца")
		var good := position(player, &"arena_field_tide", true)
		var good_ai := AIPlayer.new(player, 92, -1.0, AIPlayer.Difficulty.HARD)
		check(good_ai.choose_attach(good.get_view(player), player * 3, [GUST]) == GUST, "полезный сильный прыжок на закрытые ворота сохранён")
		var won: Array = []
		good.battle_resolved.connect(func(r: BattleResult) -> void: won.append(r))
		check(good.play_ability(player, GUST) == OK and good.reveal_gate(1 - player) == OK, "полезный прыжок и открытие реально выполнены")
		check(won.size() == 1 and won[0].winner_uid == player * 3 and won[0].powers[0] == 740, "полезный прыжок побеждает с одним настоящим +120")
		var answered := position(player, &"arena_field_fire", false, true, true)
		check(good_ai.choose_attach(answered.get_view(player), player * 3, [GUST]) == &"", "ответы соперника учитываются и на открытых нейтральных воротах")
		var doubled := position(player, &"arena_field_fire", false, true)
		doubled.state.creatures[(1 - player) * 3].def_id = &"gust_test_foe470"
		check(good_ai.choose_attach(doubled.get_view(player), player * 3, [GUST]) == &"", "потраченный Шквал не рассматривается второй бесплатной картой в руке")
		check(good_ai.choose_attach(answered.get_view(player), player * 3, [GUST], &"pre_throw") == &"", "до броска автоматического Шквала нет")
	print("AI GUST RISK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
