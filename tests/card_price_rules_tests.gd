extends "res://tests/run_tests.gd"
## Только затронутые числовые/фазовые сценарии; без _test_simulation и 200 матчей.
func _initialize() -> void:
	Engine.max_fps = 60
	AudioServer.set_bus_mute(0, true)
	CardDB.load_all()
	_add_test_creatures()
	_test_element_abilities()
	_test_ladder()
	_test_gust()
	_test_swap_fighter()
	_test_revive()
	print("CARD PRICE RULES: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)
