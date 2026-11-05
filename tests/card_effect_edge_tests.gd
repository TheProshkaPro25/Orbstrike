extends "res://tests/cards033_tests.gd"
## Узкие пробелы аудита каталога: фактическая основа слияния и пояснения сложных карт.

const HEART_EDGE := &"ability_dragnar_heart"
const DRAIN_EDGE := &"ability_fire_drain"
const EdgeServer = preload("res://network/online_server.gd")

class CaptureEdgeServer extends EdgeServer:
	var messages: Array = []
	func _send(_id: int, message: Dictionary) -> void:
		messages.append(message.duplicate(true))

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	_add_test_creatures()
	_test_card_db()
	_test_cancelled_latest_fusion_base()
	print("CARD EFFECT EDGES: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)

func _test_cancelled_latest_fusion_base() -> void:
	for player in [0, 1]:
		var ctrl := _c033(player, 0, [PLUS, DRAIN_EDGE, HEART_EDGE, &"ability_fire_spark"])
		_p033(ctrl, player, PLUS)
		_p033(ctrl, 1 - player, PLUS)
		_p033(ctrl, player, DRAIN_EDGE)
		_p033(ctrl, 1 - player, SHIELD)
		var pre := ctrl.get_battle_preview()
		_check(pre.cancelled_plays.has([player, DRAIN_EDGE]) and not pre.cancelled_plays.has([player, PLUS]), "отменена последняя основа; ранняя всё ещё действует")
		_check(ctrl.abilities_left(player) == 1 and ctrl.legal_abilities(player).has(&"ability_fire_spark"), "после отмены осталось одно настоящее действие")
		_check(not ctrl.legal_abilities(player).has(HEART_EDGE), "слияние не подменяет отменённую последнюю основу ранней")
		_check(ctrl.ability_unavailable_reason(player, HEART_EDGE).contains("отменена"), "слияние объясняет отмену своей последней основы")
		var hand := ctrl.state.players[player].ability_hand.duplicate()
		var server := CaptureEdgeServer.new()
		server._action(1, {"ctrl": ctrl, "busy": false}, player, "ability", {"card": String(HEART_EDGE)})
		_check(server.messages.size() == 1 and server.messages[0].t == "error" and server.messages[0].code == "illegal_action", "сервер отклоняет то же бесполезное слияние")
		_check(ctrl.state.players[player].ability_hand == hand and ctrl.abilities_left(player) == 1, "сетевая команда не тратит карту и действие")
		server.free()
		_check(ctrl.play_ability(player, HEART_EDGE) == ERR_UNAVAILABLE, "бесполезное слияние отклонено контроллером")
		_check(ctrl.state.players[player].ability_hand == hand and ctrl.abilities_left(player) == 1, "отклонение слияния не тратит карту и действие")
		var positive := _c033(player, 0, [PLUS, HEART_EDGE])
		_p033(positive, player, PLUS)
		_p033(positive, 1 - player, PLUS)
		var power := positive.get_battle_preview().powers[player]
		_p033(positive, player, HEART_EDGE)
		_check(positive.get_battle_preview().powers[player] == power + 200, "действующая последняя основа по-прежнему принимает слияние")
