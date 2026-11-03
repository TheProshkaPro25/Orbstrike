extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Укажите путь к записи JSON после --")
		quit(1)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not data is Dictionary:
		quit(1)
		return
	var result := MatchReplay.restore(data)
	if not result.error.is_empty():
		printerr(result.error, " · действие ", result.get("index", -1))
		quit(1)
		return
	var ctrl: MatchController = result.controller
	print("Воспроизведено %d действий; ход %d, фаза %d, победитель %d" % [result.actions, ctrl.get_turn(), ctrl.get_phase(), ctrl.winner])
	quit()
