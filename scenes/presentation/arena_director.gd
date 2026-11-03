class_name ArenaDirector
extends Node
## Последовательная постановка. Решения правил остаются в MatchController.

var game: Node
var flying := false
var fighter_shots := {0:{"throw":0,"card_throw":0,"command":0,"gate":0},1:{"throw":0,"card_throw":0,"command":0,"gate":0}}

func ability_action(player: int,card_id: StringName,uid: int = -1) -> void:
	var def: CardDef = CardDB.card(card_id)
	var elements := UiTheme.card_elements(def) if def != null else []
	var element: int = int(elements[0]) if not elements.is_empty() else -1
	if element < 0:
		if uid < 0:
			for candidate in game._battle_uids:
				if game._owner_of(candidate) == player:
					uid = candidate
					break
		if uid >= 0: element = game._creature_def(uid).attribute
	await fighter_action(player,"command",def,element)

func fighter_action(player: int,action: String,card: CardDef = null,element: int = -1) -> void:
	if game.fighters.size() != 2 or player < 0 or player > 1: return
	var fighter: VrmFighter = game.fighters[player]
	fighter_shots[player][action] += 1
	var battle_visible: bool = game.battle_hud.visible
	game.battle_hud.hide()
	fighter.play_motion(action)
	if card != null: fighter.prepare_ability(card,element)
	game.cam.fighter_view(fighter,action)
	if action == "command" and card != null:
		SoundFx.i().play("card_swoosh",-7.0)
		await game._wait(fighter.ability_ignition_time())
		SoundFx.i().play(SoundFx.activation_sfx(card,element))
		await game._wait(VrmFighter.DURATIONS[action]-fighter.ability_ignition_time())
	else:
		await game._wait(VrmFighter.DURATIONS[action])
	fighter.ability_card.clear()
	game.battle_hud.visible = battle_visible

func battle_started(slot: int, attacker_uid: int, defender_uid: int, powers: Array = [], momentum: Array = [0, 0]) -> void:
	SoundFx.i().play_music(SoundFx.MUSIC_CLASH, 1.5, false)  # бой — тема схватки с начала
	game.arena.set_highlight([slot])
	var atk: CreatureBall = game.balls.get(attacker_uid)
	var dfn: CreatureBall = game.balls.get(defender_uid)
	var base: Vector3 = game.arena.slot_position(slot)
	# короткий наезд после приземления атакующего, затем кат на общий план боя
	if game.cam.mode == CameraRig.Mode.STATIC and not game.cam.is_overview():
		await game._wait(0.4)
	# Новоприбывший раскрывается крупно и в бою, а не сразу исчезает в общем плане.
	if atk != null and not atk._open:
		var start: Vector3 = atk.global_position
		atk.face_toward(dfn.global_position if dfn != null else base)
		game._focus_labels([attacker_uid])
		var reveal_time: float = game.cam.reveal_orbit(start - Vector3(0, game.BALL_Y, 0), atk.figure_height(), Vector3.FORWARD, atk.figure_size())
		SoundFx.i().play("capsule_open", -3.0)
		game._cry(attacker_uid, "appear", .35)
		atk.open_animated()
		await game._wait(reveal_time)
	var h: float = maxf(atk.figure_height() if atk != null else 0.0, dfn.figure_height() if dfn != null else 0.0)
	game.cam.battle_view(base, h, true, maxf(atk.figure_size() if atk != null else 0.0, dfn.figure_size() if dfn != null else 0.0))
	game.hud.set_battle_mode(true)
	game._battle_uids.assign([attacker_uid, defender_uid])
	if powers.size() == 2:
		game.battle_hud.open([game._cname(attacker_uid), game._cname(defender_uid)], [game._creature_def(attacker_uid).attribute, game._creature_def(defender_uid).attribute], powers, momentum)
	game._focus_labels([attacker_uid, defender_uid])
	# Атакующий и защитник стоят на карте лицом к лицу: по трети масштаба существ (Arena.FIG_H) от центра.
	# Камера боя смотрит с +X, поэтому +Z на экране слева: атакующий всегда слева, под плашкой «АТАКА».
	var dz: float = Arena.FIG_H / 3.0
	var y := Vector3(0.0, game.BALL_Y + 0.02, 0.0)
	if atk != null:
		atk.stage_at(base + y + Vector3(0.0, 0.0, dz), base - Vector3(0.0, 0.0, dz))
		atk.set_label_shift(-110.0 * signf(dz))
		atk.open_animated(false)
	if dfn != null:
		dfn.stage_at(base + y - Vector3(0.0, 0.0, dz), base + Vector3(0.0, 0.0, dz))
		dfn.set_label_shift(110.0 * signf(dz))
		dfn.open_animated(false)
	game.hud.set_hint("Бой: %s против %s" % [game._cname(attacker_uid), game._cname(defender_uid)])
	SoundFx.i().play("battle_start")
	# общий план лицом к лицу → кат на крупный план каждого при рёве → снова общий план
	game._cry(attacker_uid, "attack", 0.85)
	game._cry(defender_uid, "attack", 1.65, -4.0)
	if atk != null:
		atk.roar(0.85)
	if dfn != null:
		dfn.roar(1.65)
	get_tree().create_timer(0.95).timeout.connect(func() -> void: game.cam.shake(0.3, 0.2))
	get_tree().create_timer(1.75).timeout.connect(func() -> void: game.cam.shake(0.25, 0.2))
	await game._wait(0.7)
	if atk != null and is_instance_valid(atk):
		game.cam.close_up(atk.global_position - Vector3(0, CreatureBall.RADIUS, 0), -Vector3(0, 0, dz), atk.figure_height(), atk.figure_size())
	await game._wait(0.8)
	if dfn != null and is_instance_valid(dfn):
		game.cam.close_up(dfn.global_position - Vector3(0, CreatureBall.RADIUS, 0), Vector3(0, 0, dz), dfn.figure_height(), dfn.figure_size())
	await game._wait(0.8)
	game.cam.battle_wide(true)
	await game._wait(0.35)

func battle_resolved(result: BattleResult) -> void:
	game.hud.set_phase(MatchController.Phase.RESOLVING)
	game.arena.set_highlight([])
	game.battle_hud.set_powers([result.powers[0], result.powers[1]])
	game.cam.battle_wide()
	await game._wait(0.22)
	if result.winner_uid < 0:
		await no_winner(result)
		return
	# удар: победитель бросается на соперника, вспышка, тряска, проигравший рассыпается
	var wb: CreatureBall = game.balls.get(result.winner_uid)
	var lb: CreatureBall = game.balls.get(result.loser_uid)
	game._cry(result.winner_uid, "attack", 0.0)
	var wh: float = wb.figure_height() if wb != null else 10.0
	if wb != null and lb != null:
		# Замах виден на общем плане, наезд — только в момент контакта.
		lb.brace()
		await wb.lunge(lb.global_position)
		wb.hold_impact()
		game.cam.impact((wb.global_position + lb.global_position) * 0.5 + Vector3(0, wh * 0.45, 0))
		lb.take_hit(VisualUtil.attr_color(game._creature_def(result.winner_uid).attribute).lightened(0.2))
		game.AttackFx.play(game.world, game._creature_def(result.winner_uid).attribute, wb.global_position - Vector3(0, CreatureBall.RADIUS, 0),
				lb.global_position - Vector3(0, CreatureBall.RADIUS, 0), lb.figure_height(), lb.figure_size(), wh)
		var mid: Vector3 = (wb.global_position + lb.global_position) * 0.5 + Vector3(0, Arena.FIG_H * 0.25, 0)
		var wc: Color = VisualUtil.attr_color(game._creature_def(result.winner_uid).attribute)
		VisualUtil.burst(game.world, mid, wc.lightened(0.3), Arena.WORLD)
		VisualUtil.light_pillar(lb, Vector3(0, -CreatureBall.RADIUS, 0), wc, Arena.FIG_H * 1.2, Arena.FIG_W * 0.3, 0.5)
	SoundFx.i().play("clash")
	game.cam.shake(1.0, 0.45)
	game.hud.screen_flash(Color(1, 1, 1, 0.55))
	game.battle_hud.resolve(0 if result.winner_uid == result.attacker_uid else 1)
	SoundFx.i().play_later("battle_win" if game._owner_of(result.winner_uid) == game.HUMAN else "battle_lose", 0.35, -2.0)
	await game._wait(0.5)
	# Короткая победная пауза; полный облёт оставляем раскрытию существ.
	if wb != null and is_instance_valid(wb):
		var facing: Vector3 = lb.global_position - wb.global_position if lb != null else Vector3.FORWARD
		game.cam.close_up(wb.global_position - Vector3(0, CreatureBall.RADIUS, 0), facing, wh, wb.figure_size())
	await game._wait(0.65)
	game.battle_hud.close()
	SoundFx.i().play_music(SoundFx.i().turn_music())  # после боя — музыка хода с того же места
	game.hud.set_battle_mode(false)
	game.cam.overview()  # кат на общий план после боя
	game._focus_labels([])
	game._battle_uids.clear()
	await game.battle_overlay.show_result(result, game._names_for(result))


## Бой без победителя: «Отлив» (бой прерван) или выбывают оба (удар обоих, вспышка).

func no_winner(result: BattleResult) -> void:
	var ab: CreatureBall = game.balls.get(result.attacker_uid)
	var db: CreatureBall = game.balls.get(result.defender_uid)
	if result.both_lose:
		if ab != null and db != null:
			game.cam.impact((ab.global_position + db.global_position) * 0.5 + Vector3(0, ab.figure_height() * 0.45, 0))
			var contact: Signal = ab.lunge(db.global_position, 0.46)
			db.lunge(ab.global_position, 0.46)
			await contact
			ab.take_hit(Color(1.0, 0.4, 0.3))
			db.take_hit(Color(1.0, 0.4, 0.3))
			var floor_off := Vector3(0, CreatureBall.RADIUS, 0)
			game.AttackFx.play(game.world, game._creature_def(result.attacker_uid).attribute, ab.global_position - floor_off,
					db.global_position - floor_off, db.figure_height(), db.figure_size(), ab.figure_height())
			game.AttackFx.play(game.world, game._creature_def(result.defender_uid).attribute, db.global_position - floor_off,
					ab.global_position - floor_off, ab.figure_height(), ab.figure_size(), db.figure_height())
		SoundFx.i().play("clash")
		game.cam.shake(1.0, 0.5)
		game.hud.screen_flash(Color(1.0, 0.35, 0.25, 0.5))
		game.battle_hud.resolve(-1)
		await game.hud.banner("ВЫБЫВАЮТ ОБА", "Ворота сгорают", Color(1.0, 0.45, 0.3), 0.8)
	else:
		SoundFx.i().play("miss", -2.0)
		game.cam.shake(0.4, 0.3)
		game.battle_hud.resolve(-1)
		await game.hud.banner("БОЙ ПРЕРВАН", "Отлив уносит соперника на другие ворота", Color(0.45, 0.75, 1.0), 0.8)
	game.battle_hud.close()
	SoundFx.i().play_music(SoundFx.i().turn_music())  # после боя — музыка хода с того же места
	game.hud.set_battle_mode(false)
	game.cam.overview()
	game._focus_labels([])
	game._battle_uids.clear()
	await game.battle_overlay.show_result(result, game._names_for(result))

## Выбирается карта-цель. Начальная скорость рассчитана заранее; дальше действуют
## настоящие столкновения, отскоки и трение. Учитывается фактическая точка остановки.
func launch_to(slot: int) -> void:
	if flying or game._active_ball == null or not game._gate_slots().has(slot):
		return
	flying = true
	var ball: CreatureBall = game._active_ball
	var start: Vector3 = ball.global_position
	var target: Vector3 = game.arena.slot_position(slot)
	target += Vector3(game.rng.randf_range(-.20, .20) * Arena.CARD_W, 0, game.rng.randf_range(-.18, .18) * Arena.CARD_H)
	game.arena.set_highlight([])
	game.ability_panel.hide_panel()
	game.hud.dismiss_coach("throw")
	game.hud.dismiss_coach("prethrow")
	game.hud.set_hint("Бросок на ворота %d…" % (slot + 1))
	var bounce_feedback := func(_point: Vector3, impact: float) -> void:
		if flying and game.cam.mode == CameraRig.Mode.FOLLOW:
			game.cam.shake(clampf(impact / 80.0, .06, .18), .11)
	if game.fighters.size() == 2:
		var fighter: VrmFighter = game.fighters[game._owner_of(ball.uid)]
		fighter.play_motion("throw")
		fighter_shots[game._owner_of(ball.uid)]["throw"] += 1
		game.cam.fighter_view(fighter,"throw")
		# Palm-sized shell keeps the same visible scale through release.
		var held_scale := 1.0
		# Suspend the floor offset while holding the visible center in the palm.
		var was_processing := ball.is_processing()
		ball.set_process(false)
		ball._visual.scale = Vector3.ONE*held_scale
		ball._visual.position = -ball._shell.position*held_scale
		# Hold the actual frozen sphere at the hand; launch from the release
		# point with the existing ballistic solver, then keep real physics.
		while fighter.motion_time < fighter.ball_release_time():
			ball.global_position = fighter.ball_hold_position()
			await get_tree().process_frame
		ball.global_position = fighter.ball_hold_position()+Vector3.UP*(CreatureBall.RADIUS-CreatureBall._shell_r())
		start = ball.global_position
		ball._visual.scale = Vector3.ONE
		ball._visual.position = Vector3.ZERO
		ball.set_process(was_processing)
	ball.surface_bounced.connect(bounce_feedback)
	SoundFx.i().play("ball_throw", -3.0)
	ball.launch_towards(target)
	# Первый реальный кадр скорости задаёт направление погони.
	game.cam.follow(ball, Vector3.ZERO)
	game.cam._follow_dir = Vector3(target.x - start.x, 0, target.z - start.z).normalized()
	game.cam._smooth = 7.0
	game.cam._update_follow(1.0 / 60.0)
	game.cam.cut()
	game.cam.shake(.10, .12)
	var landing: Array = await ball.settled
	var actual: Vector3 = landing[1]
	ball.surface_bounced.disconnect(bounce_feedback)
	game._active_ball = null
	var landed_slot: int = game.arena.slot_at(actual)
	ball.hold_landing_pose()
	if landed_slot < 0 or not game._gate_slots().has(landed_slot):
		game.cam.zoom_slot(actual)
		await game._wait(.12)
	# Попадание сразу передаётся раскрытию: один непрерывный облёт без серии катов.
	flying = false
	game._report(ball.uid, landed_slot)


## Маленькая карта летит до самого пола. Волна и рост начинаются только после касания.
const CARD_FLIGHT_SCALE := .12 / Arena.CARD_W
const CARD_FLIGHT_TIME := 0.95
const CARD_GROW_TIME := 0.68

func card_placed(player: int, slot: int) -> void:
	var node: ArenaCardNode = game.CARD_SCENE.instantiate()
	game.world.add_child(node)
	var pos: Vector3 = game.arena.slot_position(slot)
	var start := Vector3(0, 5.5, game.THROW_Z if player == 0 else -game.THROW_Z)
	node.position = start
	node.scale = Vector3.ONE * CARD_FLIGHT_SCALE
	node.slot = slot
	node.set_meta("placement_stage", &"flight")
	node.set_meta("flight_scale",Vector3.ONE*CARD_FLIGHT_SCALE)
	var cdef: CardDef = CardDB.card(game.ctrl.get_view(game.HUMAN).slots[slot].card_id)
	var flight_scale := Vector3.ONE*CARD_FLIGHT_SCALE
	var release_basis := Basis.IDENTITY
	node.show_facedown(player, cdef)
	game.card_nodes[slot] = node
	if game.fighters.size() == 2:
		var fighter: VrmFighter = game.fighters[player]
		fighter_shots[player]["card_throw"] += 1
		fighter.play_motion("card_throw")
		game.cam.fighter_view(fighter,"card_throw")
		game.hud.set_hint("Бросок карты ворот")
		node.set_meta("placement_stage",&"held")
		while fighter.motion_time < fighter.card_release_time():
			node.global_transform = fighter.card_hand_transform("Right").scaled_local(Vector3.ONE*CARD_FLIGHT_SCALE)
			node.set_meta("flight_scale",node.scale)
			await get_tree().process_frame
		start = node.global_position
		flight_scale = node.scale
		release_basis = node.global_basis.orthonormalized()
		node.set_meta("placement_stage",&"flight")
	node.set_meta("flight_scale",flight_scale)
	var forward := Vector3(pos.x-start.x,0,pos.z-start.z).normalized()
	var curve := forward.cross(Vector3.UP)*minf(6.0,start.distance_to(pos)*.08)

	var uid: int = game.ctrl.get_view(game.HUMAN).players[player].creature_uids[0]
	var col: Color = VisualUtil.attr_color(game._creature_def(uid).attribute)
	var trail := BallTrail.new()
	trail.target = node
	trail.width = 0.10
	trail.color = col.lightened(0.20) * 0.75
	game.world.add_child(trail)
	trail.emitting = true
	game.cam.card_flight_view(start, true, 1.0 if player == 0 else -1.0)
	SoundFx.i().play("gate_flight_wind", -11.0, 0.015)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		node.position = start.lerp(pos,t)+curve*sin(PI*t)+Vector3.UP*sin(PI*t)*1.1
		# Плоский вращающийся диск, видимый с близкой камеры; масштаб в полёте неизменен.
		var flat := Basis.from_euler(Vector3(sin(PI*t)*.10,0,sin(PI*t)*-.08))
		var bank := release_basis.get_rotation_quaternion().slerp(flat.get_rotation_quaternion(),smoothstep(0,.18,t))
		node.basis = Basis(Quaternion(Vector3.UP,t*TAU*3.0))*Basis(bank)
		node.scale = flight_scale
		game.cam.card_flight_view(node.position, false, 1.0 if player == 0 else -1.0), 0.0, 1.0, CARD_FLIGHT_TIME)
	await tw.finished
	SoundFx.i().stop_sfx("gate_flight_wind")
	node.position = pos
	node.rotation = Vector3.ZERO
	node.set_meta("placement_stage", &"landed")
	trail.emitting = false
	get_tree().create_timer(0.45).timeout.connect(trail.queue_free)
	game.cam.card_expansion_view(pos)
	SoundFx.i().play("card_place", -17.0, 0.01)
	await game._wait(0.10)
	node.set_meta("placement_stage", &"expanding")
	game.arena.element_wave(pos, col, 0.80)
	SoundFx.i().play("gate_expand_wave", -4.0, 0.0)
	var grow := create_tween()
	grow.tween_property(node, "scale", Vector3.ONE, CARD_GROW_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await grow.finished
	node.set_meta("placement_stage", &"ready")
	node.set_field_surface(true)
	game.cam.overview()
	await game._wait(0.3)
