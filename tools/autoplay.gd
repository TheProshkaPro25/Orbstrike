extends SceneTree
## Автоигра: человек управляется AIPlayer(0), реальная физика и UI. Считаем матчи, броски, попадания.

const MATCHES := 2
var main: Node
var bot: AIPlayer
var target := -1
var done := 0
var throws := {0: 0, 1: 0}
var hits := {0: 0, 1: 0}
var misses := {0: 0, 1: 0}
var pending_launches: Dictionary = {}
var frames := 0
var battles := 0
var battle_reveals := 0
var _was_battle_reveal := false
var reasons := {}
var match_frames := 0
var acted_key := ""
var _loading := false
var _finishing := false
var startup_counts: Array[int] = []
var startup_seconds := 0.0
var fighter_instances: Array[int] = []
var avatar_shot := false
var action_shots: Dictionary = {}
var glowing_card_shots: Dictionary = {}
var ability_sound_shots: Dictionary = {}
var prethrow_attachment_requested := false
var prethrow_attachment_seen := false

func _initialize() -> void:
	_lock_fps()
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	_new_match()

## Проверки (кроме замеров производительности) идут с лимитом 60 fps — без записи в settings.cfg.
## perf.gd снимает лимит после super._initialize().
func _lock_fps() -> void:
	GraphicsSettings.max_fps = 60
	Engine.max_fps = 60


func _new_match() -> void:
	_loading = true
	pending_launches.clear()
	_was_battle_reveal = false
	if done == 0:
		var begin := Time.get_ticks_msec()
		change_scene_to_file("res://scenes/loading/boot.tscn")
		if not await _wait_for_scene("res://scenes/menu/main_menu.tscn", 180.0):
			printerr("FAIL: начальная загрузка → главное меню за 180 с")
			_finish(1)
			return
		startup_seconds = (Time.get_ticks_msec() - begin) / 1000.0
		var loader := GameLoading.i()
		if not loader.ready_to_play:
			printerr("FAIL: главное меню открыто до подготовки каталога")
			_finish(1)
			return
		startup_counts = _preparation_counts()
		current_scene._on_play()
		if not await _wait_for_scene("res://scenes/main.tscn", 15.0):
			printerr("FAIL: главное меню → выбор команды")
			_finish(1)
			return
	else:
		# Настоящая кнопка «Ещё раз»: возврат подготовленных сфер и арен в общий резерв.
		var previous := main
		main.game_over_ui.restart_requested.emit()
		main = null
		if not await _wait_for_scene("res://scenes/main.tscn", 15.0, previous):
			printerr("FAIL: повтор → выбор команды")
			_finish(1)
			return
	main = current_scene
	if main == null or main.scene_file_path != "res://scenes/main.tscn" or not main.team_menu.visible:
		printerr("FAIL: меню → выбор команды / повтор")
		_finish(1)
		return
	bot = AIPlayer.new(0, 12345 + done)
	match_frames = 0
	main.team_menu._open_arena_picker()
	main.team_menu._arena_picker.select(1 if done == 0 else 2)
	main.team_menu._close_arena_picker()
	main.team_menu.pick_random_and_start()
	await process_frame
	var profile := PlayerProfile.new()
	profile.load_from()
	if main.fighters.size() != 2 or main.fighters[0].appearance_profile != profile.value:
		printerr("FAIL: сохранённый герой не перенесён в матч")
		_finish(1)
		return
	var rival_profile := PlayerProfile.npc_profile(2)
	if main.fighters[1].appearance_profile != rival_profile or main.fighter_portraits.size() != 2:
		printerr("FAIL: профиль соперника или портреты не восстановлены после аренды")
		_finish(1)
		return
	for side in 2:
		var fighter: VrmFighter = main.fighters[side]
		var expected_profile: Dictionary = profile.value if side == 0 else rival_profile
		var expected_position := Vector3(-2.3 if side == 0 else 2.3,0,(main.THROW_Z+1.4)*(1 if side == 0 else -1))
		var expected_basis := Basis(Vector3.UP,PI if side == 0 else 0.0)
		var portrait: FighterPortrait = main.fighter_portraits[side]
		var side_layer := 1 << (18+side)
		if fighter.selected != int(expected_profile.vrm_model) or fighter.get_parent() != main.world or not fighter.position.is_equal_approx(expected_position) or not fighter.basis.is_equal_approx(expected_basis):
			printerr("FAIL: боец привязан к неверной стороне после аренды: ",side)
			_finish(1)
			return
		if portrait.fighter != fighter or portrait.camera.cull_mask != side_layer:
			printerr("FAIL: портрет привязан к чужому бойцу после аренды: ",side)
			_finish(1)
			return
		for mesh: MeshInstance3D in fighter.meshes:
			if mesh.layers != side_layer:
				printerr("FAIL: слой портрета бойца не соответствует стороне: ",side)
				_finish(1)
				return
	var leased: Array[int] = []
	for fighter: VrmFighter in main.fighters: leased.append(fighter.get_instance_id())
	print("Fighter roles match ",done+1,": IDs=",leased," profiles=",main.fighters[0].appearance_profile.name," / ",main.fighters[1].appearance_profile.name)
	# Одна основа на обе стороны: LIFO-каталог может поменять тех же актёров местами.
	leased.sort()
	if done == 0: fighter_instances = leased
	elif leased != fighter_instances:
		printerr("FAIL: бойцы пересозданы при повторной игре")
		_finish(1)
		return
	if _preparation_counts() != startup_counts:
		printerr("FAIL: после меню повторно подготавливаются модели или арены")
		_finish(1)
		return
	main.ctrl.creature_selected.connect(func(p: int, uid: int, _recall: bool) -> void:
		throws[p] += 1
		pending_launches[uid] = true)
	main.ctrl.creature_returned.connect(func(uid, reason): _ret(uid, reason))
	main.ctrl.creature_stood.connect(func(uid, slot): _land(uid, true))
	main.ctrl.battle_started.connect(func(s, a, d): battles += 1; _land(a, true))
	_loading = false


func _finish(code: int) -> void:
	_finishing = true
	if is_instance_valid(main):
		if main.has_method("_release_game_resources"):
			main._release_game_resources()
		main.queue_free()
	main = null
	await process_frame
	await process_frame
	var loader := root.get_node_or_null("GameLoading")
	if loader != null:
		loader.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(SoundFx._inst):
		SoundFx._inst.queue_free()
	await process_frame
	await process_frame
	Engine.time_scale = 1.0
	quit(code)

func _wait_for_scene(path: String, timeout_seconds: float, previous: Node = null) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene != previous and current_scene.scene_file_path == path:
			return true
	return false

func _preparation_counts() -> Array[int]:
	var loader := GameLoading.i()
	return [loader.preparation_count, loader.actor_build_count, loader.arena_build_count, SoundFx.i().catalog_load_count,loader.fighter_build_count]

func _owner(uid): return main._owner_of(uid)
func _land(uid, ok):
	if pending_launches.has(uid):
		hits[_owner(uid)] += 1
		pending_launches.erase(uid)
func _ret(uid, reason):
	var p = _owner(uid)
	reasons[reason] = reasons.get(reason, 0) + 1
	if reason == &"miss":
		misses[p] += 1
		pending_launches.erase(uid)

func _process(_d: float) -> bool:
	if _loading or _finishing:
		return false
	frames += 1
	match_frames += 1
	if main == null or main.ctrl == null:
		return false
	if not avatar_shot and main.fighters.size() == 2 and main.fighters[0].motion == "throw" and main.fighters[0].motion_time > .25:
		avatar_shot = true
		root.get_texture().get_image().save_png("res://build/checks/vrm-fighter/match-throw.png")
	for side in main.fighters.size():
		var fighter: VrmFighter = main.fighters[side]
		var key := "%d-%s" % [side,fighter.motion]
		if fighter.motion == "command" and fighter.motion_time > fighter.ability_ignition_time()+.22 and fighter.motion_time < fighter.ability_ignition_time()+.60 and not glowing_card_shots.has(side):
			var cue := SoundFx.activation_sfx(CardDB.card(fighter.ability_card.card_id),fighter.ability_card.element)
			var played_at: int = SoundFx.i()._last_play.get(cue,-100000)
			var elapsed := Time.get_ticks_msec()-played_at
			var expected := (fighter.motion_time-fighter.ability_ignition_time())*1000.0/Engine.time_scale
			var camera_direction: Vector3 = (main.cam.global_position-fighter.ability_card.global_position).normalized()
			if fighter.ability_card.global_basis.y.normalized().dot(camera_direction) < .45:
				printerr("FAIL: ability card shows its back to the match camera on side ",side)
			if absf(elapsed-expected) > 150:
				printerr("FAIL: ability sound not synchronized with card ignition: ",side," ",cue)
			else:
				ability_sound_shots[side] = cue
			for x in [-.06,.06]:
				for z in [-.084,.084]:
					var screen: Vector2 = main.cam.unproject_position(fighter.ability_card.to_global(Vector3(x,0,z)))
					if screen.y < 116 or screen.y > root.size.y or screen.x < 0 or screen.x > root.size.x:
						printerr("FAIL: ability card outside clear camera frame on side ",side)
			if not fighter.ability_card.visible or fighter.ability_card.strength < .9:
				printerr("FAIL: ability card missing or unlit on side ",side)
			else:
				glowing_card_shots[side] = true
				root.get_texture().get_image().save_png("res://build/checks/vrm-fighter/ability-card-side-%d.png" % side)
		if fighter.motion == "idle" and fighter.ability_card.visible:
			printerr("FAIL: ability card leaked into idle")
		if fighter.motion in ["throw","card_throw","command","gate"] and fighter.motion_time > .30 and fighter.motion_time < .60 and not action_shots.has(key):
			if main.cam.global_position.distance_to(fighter.global_position) > 6.0:
				printerr("FAIL: camera not focused on acting fighter "+key)
			else:
				action_shots[key] = true
				root.get_texture().get_image().save_png("res://build/checks/vrm-fighter/action-"+key+".png")
	if main.fighters.size() == 2 and main.fighters[0].motion == "command" and main.ctrl.get_ability_moment() == &"pre_throw":
		prethrow_attachment_seen = true
	var reveal: bool = main.cam.mode == CameraRig.Mode.ORBIT and main.ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and main._battle_uids.is_empty()
	if reveal and not _was_battle_reveal:
		battle_reveals += 1
	_was_battle_reveal = reveal
	if main._game_over:
		done += 1
		print("Матч %d: победитель %d, ход %d, захваты %s" % [done, main.ctrl.winner, main.ctrl.get_turn(), str(main.captures)])
		if done >= MATCHES:
			_report()
			if battles > 0 and battle_reveals == 0:
				printerr("FAIL: нет крупных раскрытий перед боем")
				_finish(1)
			else:
				_finish(0)
			return false
		_new_match(); return false
	if match_frames > 60 * 60 * 6:
		print("ЗАВИСАНИЕ: фаза %d, pending %s, busy %s" % [main.ctrl.get_phase(), str(main._pending), str(main.events.is_busy())])
		main.ctrl.save_debug_trace("user://replays/autoplay_failure.json")
		_report(); _finish(1); return false
	if main.hud._reading > 0:
		main.hud._skip_flag = true  # эквивалент Enter: время чтения проверяет отдельный experience_review
	if main.battle_overlay._open:
		main.battle_overlay._close()
	var view = main.ctrl.get_view(0)
	if main.setup_panel._panel.visible:
		var c = bot.choose_setup(view, main.ctrl.legal_setup_slots(), main.ctrl.can_skip_gate())
		main.setup_panel.hide_panel()
		if c.is_empty():
			main._on_setup_skipped()
		else:
			main._on_setup_placed(c["card_id"], int(c["slot"]))
	elif main.hud._creature_panel.visible:
		var c = bot.choose_throw(view)
		target = int(c["target_slot"])
		main._on_creature_chosen(int(c["uid"]))
	elif main._active_ball != null and not main.director.flying and main.ctrl.get_active_player() == 0 and not main.events.is_busy():
		var legal: Array = main.ctrl.legal_abilities(0)
		if not prethrow_attachment_requested and not legal.is_empty():
			prethrow_attachment_requested = true
			main._on_ability_chosen(legal[0])
			return false
		var slots: Array = main._gate_slots()
		main._on_slot_picked(target if slots.has(target) else int(slots[0]))
	elif main.ability_panel._panel.visible:
		var cid: StringName = &""
		if main.ctrl.get_ability_moment() == &"battle":
			if main.ctrl.can_reveal_gate(0) and bot.should_open_gate(view, main.ctrl.get_battle_preview()):
				main._on_gate_open_requested()
				return false
			cid = bot.choose_ability(view, main.ctrl.get_battle_preview(), main.ctrl.legal_abilities(0))
		elif main.ctrl.get_ability_moment() == &"after_landing":
			cid = bot.choose_attach(view, main.ctrl.get_landed_uid(), main.ctrl.legal_abilities(0))
		else:
			return false  # до броска окно только подсказка
		if cid == &"": main._on_ability_passed()
		else: main._on_ability_chosen(cid)
	return false

func _report() -> void:
	for side in 2:
		if not ability_sound_shots.has(side): printerr("FAIL: missing actor ability sound on side ",side)
	print("Ability ignition sounds: ",ability_sound_shots)
	for side in 2:
		if not glowing_card_shots.has(side): printerr("FAIL: no glowing ability card for side ",side)
	print("Glowing ability cards: ",glowing_card_shots.keys())
	if not prethrow_attachment_seen: printerr("FAIL: prethrow ability did not animate fighter")
	print("Prethrow attachment animation: ",prethrow_attachment_seen)
	print("Actor action camera shots: ",action_shots.keys())
	for side in 2:
		for action in ["throw","card_throw","command","gate"]:
			if not action_shots.has("%d-%s" % [side,action]): printerr("FAIL: missing actor shot %d/%s" % [side,action])
	if not avatar_shot: printerr("FAIL: нет анимации броска бойца")
	print("Герой из профиля и повторное использование двух бойцов: проверены")
	print("Начальная загрузка до меню: %.2f с; подготовка после меню: %s" % [startup_seconds, str(_preparation_counts() == startup_counts)])
	print("Крупных раскрытий перед боем: %d" % battle_reveals)
	print("боёв %d, возвраты %s" % [battles, str(reasons)])
	for p in [0, 1]:
		print("Игрок %d: бросков %d, приземлений в слот %d (%.0f%%), промахов %d" % [p, throws[p], hits[p], 100.0 * hits[p] / maxf(1, throws[p]), misses[p]])

