class_name ArenaDirector
extends Node
## Последовательная постановка. Решения правил остаются в MatchController.

const Resources := preload("res://scenes/match_resources.gd")
const State := preload("res://scenes/presentation/match_presentation_state.gd")
const MatchEffects := preload("res://scenes/presentation/match_effects.gd")
const CARD_SCENE: PackedScene = preload("res://scenes/arena_card_node.tscn")
const HUMAN := 0
const BALL_Y := 0.36
const THROW_Z := Arena.STEP_Z * 0.5 + Arena.CARD_H * 0.5 + 0.8 * Arena.WORLD
signal labels_requested(uids: Array)
signal creature_opened(uid: int)
signal battle_presented(attacker: int, defender: int, powers: Array)
signal battle_cleared
signal landing_ready(uid: int, slot: int)
var resources: Resources
var state: State
var controller: MatchController
var world: Node3D
var cam: CameraRig
var hud: HudUI
var battle_hud: BattleHud
var ability_panel: AbilityPanel
var battle_overlay: BattleOverlay
var rng: RandomNumberGenerator
var effects: MatchEffects
var semifinal_music := false
var arena: Arena:
	get: return resources.arena if resources != null else null
var balls: Dictionary:
	get: return resources.active if resources != null else {}
var fighters: Array[VrmFighter]:
	get: return resources.fighters if resources != null else []
var flying := false
var fighter_shots := {0:{"throw":0,"card_throw":0,"command":0,"gate":0},1:{"throw":0,"card_throw":0,"command":0,"gate":0}}

## Same synchronous reveal entry for landing, battle arrival and replacement.
func open_creature(ball: CreatureBall, pose: bool = true) -> Signal:
	if not ball._open and ball.def != null and ball.def.attribute == Attr.A.LIGHT and is_instance_valid(hud):
		hud.screen_flash(Color(1.0,.96,.78,.10))
	return ball.open_animated(pose)


func ability_action(player: int,card_id: StringName,uid: int = -1) -> void:
	var def: CardDef = CardDB.card(card_id)
	var elements := UiTheme.card_elements(def) if def != null else []
	var element: int = int(elements[0]) if not elements.is_empty() else -1
	if element < 0:
		if uid < 0:
			for candidate in state.battle_uids:
				if owner_of(candidate) == player:
					uid = candidate
					break
		if uid >= 0: element = creature_def(uid).attribute
	await fighter_action(player,"command",def,element)

func fighter_action(player: int,action: String,card: CardDef = null,element: int = -1) -> void:
	if fighters.size() != 2 or player < 0 or player > 1: return
	var fighter: VrmFighter = fighters[player]
	fighter_shots[player][action] += 1
	var battle_visible: bool = battle_hud.visible
	battle_hud.hide()
	fighter.play_motion(action)
	if card != null: fighter.prepare_ability(card,element)
	cam.fighter_view(fighter,action)
	if action == "command" and card != null:
		SoundFx.i().play("card_swoosh",-7.0)
		await wait(fighter.ability_ignition_time())
		SoundFx.i().play(SoundFx.activation_sfx(card,element))
		await wait(VrmFighter.DURATIONS[action]-fighter.ability_ignition_time())
	else:
		await wait(VrmFighter.DURATIONS[action])
	fighter.ability_card.clear()
	battle_hud.visible = battle_visible

func _match_theme() -> String:
	var location_id := arena.location_id if is_instance_valid(arena) else -1
	return SoundFx.i().match_theme(location_id, semifinal_music)


func play_match_music() -> void:
	var sound := SoundFx.i()
	var theme := _match_theme()
	sound.play_music(sound.turn_music() if theme.is_empty() else theme)


func _resume_turn_music() -> void:
	if _match_theme().is_empty():
		var sound := SoundFx.i()
		sound.play_music(sound.turn_music())


func battle_started(slot: int, attacker_uid: int, defender_uid: int, powers: Array = [], momentum: Array = [0, 0]) -> void:
	if _match_theme().is_empty():
		SoundFx.i().play_music(SoundFx.MUSIC_CLASH, 1.5, false)
	arena.set_highlight([slot])
	var atk: CreatureBall = balls.get(attacker_uid)
	var dfn: CreatureBall = balls.get(defender_uid)
	var base: Vector3 = arena.slot_position(slot)
	# короткий наезд после приземления атакующего, затем кат на общий план боя
	if cam.mode == CameraRig.Mode.STATIC and not cam.is_overview():
		await wait(0.4)
	# Новоприбывший раскрывается крупно и в бою, а не сразу исчезает в общем плане.
	if atk != null and not atk._open:
		var start: Vector3 = atk.global_position
		atk.face_toward(dfn.global_position if dfn != null else base)
		labels_requested.emit([attacker_uid])
		var reveal_time: float = cam.reveal_orbit(start - Vector3(0, BALL_Y, 0), atk.figure_height(), Vector3.FORWARD, atk.figure_size())
		SoundFx.i().play("capsule_open", -3.0)
		cry(attacker_uid, "appear", .35)
		open_creature(atk)
		creature_opened.emit(attacker_uid)
		await wait(reveal_time)
	var h: float = maxf(atk.figure_height() if atk != null else 0.0, dfn.figure_height() if dfn != null else 0.0)
	cam.battle_view(base, h, true, maxf(atk.figure_size() if atk != null else 0.0, dfn.figure_size() if dfn != null else 0.0))
	hud.set_battle_mode(true)
	state.battle_uids.assign([attacker_uid, defender_uid])
	battle_presented.emit(attacker_uid,defender_uid,powers)
	if powers.size() == 2:
		battle_hud.open([creature_name(attacker_uid), creature_name(defender_uid)], [creature_def(attacker_uid).attribute, creature_def(defender_uid).attribute], powers, momentum)
	labels_requested.emit([attacker_uid, defender_uid])
	# Атакующий и защитник стоят на карте лицом к лицу: по трети масштаба существ (Arena.FIG_H) от центра.
	# Камера боя смотрит с +X, поэтому +Z на экране слева: атакующий всегда слева, под плашкой «АТАКА».
	var dz: float = Arena.FIG_H / 3.0
	var y := Vector3(0.0, BALL_Y + 0.02, 0.0)
	if atk != null:
		atk.stage_at(base + y + Vector3(0.0, 0.0, dz), base - Vector3(0.0, 0.0, dz))
		atk.set_label_shift(-110.0 * signf(dz))
		atk.open_animated(false)
	if dfn != null:
		dfn.stage_at(base + y - Vector3(0.0, 0.0, dz), base + Vector3(0.0, 0.0, dz))
		dfn.set_label_shift(110.0 * signf(dz))
		dfn.open_animated(false)
	hud.set_hint("Бой: %s против %s" % [creature_name(attacker_uid), creature_name(defender_uid)])
	SoundFx.i().play("battle_start")
	# общий план лицом к лицу → кат на крупный план каждого при рёве → снова общий план
	cry(attacker_uid, "attack", 0.85)
	cry(defender_uid, "attack", 1.65, -4.0)
	if atk != null:
		atk.roar(0.85)
	if dfn != null:
		dfn.roar(1.65)
	get_tree().create_timer(0.95).timeout.connect(func() -> void: cam.shake(0.3, 0.2))
	get_tree().create_timer(1.75).timeout.connect(func() -> void: cam.shake(0.25, 0.2))
	await wait(0.7)
	if atk != null and is_instance_valid(atk):
		cam.close_up(atk.global_position - Vector3(0, CreatureBall.RADIUS, 0), -Vector3(0, 0, dz), atk.figure_height(), atk.figure_size())
	await wait(0.8)
	if dfn != null and is_instance_valid(dfn):
		cam.close_up(dfn.global_position - Vector3(0, CreatureBall.RADIUS, 0), Vector3(0, 0, dz), dfn.figure_height(), dfn.figure_size())
	await wait(0.8)
	cam.battle_wide(true)
	await wait(0.35)

func battle_resolved(result: BattleResult) -> void:
	var revision := resources._revision
	hud.set_phase(MatchController.Phase.RESOLVING)
	hud.set_hint("")
	arena.set_highlight([])
	battle_hud.set_powers([result.powers[0], result.powers[1]])
	cam.battle_wide()
	await wait(0.22)
	if revision != resources._revision: return
	if result.winner_uid < 0:
		await no_winner(result)
		return
	# удар: победитель бросается на соперника, вспышка, тряска, проигравший рассыпается
	var wb: CreatureBall = balls.get(result.winner_uid)
	var lb: CreatureBall = balls.get(result.loser_uid)
	cry(result.winner_uid, "attack", 0.0)
	var wh: float = wb.figure_height() if wb != null else 10.0
	var impact_hold := 0.5
	if _has_strike_pair(wb, lb):
		# Замах виден на общем плане, наезд — только в момент контакта.
		lb.brace()
		wb.lunge(lb.global_position)
		var landed := await wait_for_strike(wb, lb)
		if revision != resources._revision: return
		if landed:
			wb.hold_impact()
			cam.impact((wb.global_position + hit_anchor(lb)) * 0.5 + Vector3.UP * wh * 0.15)
			play_strike(wb, lb)
			lb.take_hit(VisualUtil.attr_color(wb.def.attribute).lightened(0.2))
			if wb.def.attribute in [Attr.A.STONE, Attr.A.TIDE]: impact_hold = 0.86
	cam.shake(1.0, 0.45)
	hud.screen_flash(Color(1, 1, 1, 0.18))
	battle_hud.resolve(0 if result.winner_uid == result.attacker_uid else 1)
	SoundFx.i().play_later("battle_win" if owner_of(result.winner_uid) == HUMAN else "battle_lose", 0.35, -2.0)
	await wait(impact_hold)
	if revision != resources._revision: return
	# Короткая победная пауза; полный облёт оставляем раскрытию существ.
	if is_instance_valid(wb) and wb.is_figure_shown():
		var facing: Vector3 = lb.global_position - wb.global_position if is_instance_valid(lb) else Vector3.FORWARD
		cam.close_up(wb.global_position - Vector3(0, CreatureBall.RADIUS, 0), facing, wh, wb.figure_size())
	await wait(1.15 - impact_hold)
	if revision != resources._revision: return
	battle_hud.close()
	_resume_turn_music()
	hud.set_battle_mode(false)
	cam.overview()  # кат на общий план после боя
	labels_requested.emit([])
	state.battle_uids.clear()
	battle_cleared.emit()
	await battle_overlay.show_result(result, names_for(result))


## Бой без победителя: «Отлив» (бой прерван) или выбывают оба (удар обоих, вспышка).

func no_winner(result: BattleResult) -> void:
	var revision := resources._revision
	var ab: CreatureBall = balls.get(result.attacker_uid)
	var db: CreatureBall = balls.get(result.defender_uid)
	if result.both_lose:
		if _has_strike_pair(ab, db):
			cam.impact((ab.global_position + db.global_position) * 0.5 + Vector3(0, ab.figure_height() * 0.45, 0))
			var first := _start_trade(ab, db)
			var second := _start_trade(db, ab)
			if not first.done: await first.finished
			if not second.done: await second.finished
			if revision != resources._revision: return
			if _has_strike_pair(ab, db):
				if second.landed: ab.take_hit(Color(1.0, 0.4, 0.3))
				if first.landed: db.take_hit(Color(1.0, 0.4, 0.3))
		cam.shake(1.0, 0.5)
		hud.screen_flash(Color(1.0, 0.35, 0.25, 0.2))
		battle_hud.resolve(-1)
		await hud.banner("ВЫБЫВАЮТ ОБА", "Ворота сгорают", Color(1.0, 0.45, 0.3), 0.8, true)
	else:
		SoundFx.i().play("miss", -2.0)
		cam.shake(0.4, 0.3)
		battle_hud.resolve(-1)
		await hud.banner("БОЙ ПРЕРВАН", "Отлив уносит соперника на другие ворота", Color(0.45, 0.75, 1.0), 0.8, true)
	if revision != resources._revision: return
	battle_hud.close()
	_resume_turn_music()
	hud.set_battle_mode(false)
	cam.overview()
	labels_requested.emit([])
	state.battle_uids.clear()
	battle_cleared.emit()
	await battle_overlay.show_result(result, names_for(result))


class TradeContact extends RefCounted:
	signal finished
	var done := false
	var landed := false


func _start_trade(attacker: CreatureBall, target: CreatureBall) -> TradeContact:
	var contact := TradeContact.new()
	_play_trade(attacker, target, contact)
	return contact


func _play_trade(attacker: CreatureBall, target: CreatureBall, contact: TradeContact) -> void:
	attacker.lunge(target.global_position, 0.46)
	contact.landed = await wait_for_strike(attacker, target)
	if contact.landed: play_strike(attacker, target)
	contact.done = true
	contact.finished.emit()


func wait_for_strike(attacker: CreatureBall, target: CreatureBall) -> bool:
	if not _has_strike_pair(attacker, target):
		return false
	var revision := resources._revision
	var landed: bool
	if is_instance_valid(attacker._anim):
		landed = await attacker._anim.strike_resolved
	else:
		await get_tree().create_timer(0.42).timeout
		landed = true
	return landed and revision == resources._revision and _has_strike_pair(attacker, target)


func _has_strike_pair(attacker: CreatureBall, target: CreatureBall) -> bool:
	return is_instance_valid(attacker) and is_instance_valid(target) \
		and attacker.is_figure_shown() and target.is_figure_shown() \
		and balls.get(attacker.uid) == attacker and balls.get(target.uid) == target


func hit_anchor(target: CreatureBall) -> Vector3:
	return target._anim.strike_anchor() if target._anim != null else target.global_position + Vector3.UP * target.figure_height() * 0.46


func _strike_surface(at: Vector3) -> ArenaCardNode:
	var surface: ArenaCardNode
	var height := 0.0
	for candidate: ArenaCardNode in get_tree().get_nodes_in_group(&"gate_surfaces"):
		if candidate.get_world_3d() != world.get_world_3d() or not candidate.is_visible_in_tree(): continue
		var top := candidate.surface_height_at(at)
		if top > height:
			height = top
			surface = candidate
	return surface


func play_strike(attacker: CreatureBall, target: CreatureBall, strength: float = 1.0) -> void:
	var direction := (target.global_position - attacker.global_position).slide(Vector3.UP).normalized()
	var facing := Basis.looking_at(direction) if not direction.is_zero_approx() else Basis.IDENTITY
	var height := target.figure_height()
	var size := target.figure_size()
	var contact := hit_anchor(target) - direction * minf(size * 0.13, 1.7)
	var surface := _strike_surface(contact)
	effects.elemental_impact(attacker.def.attribute, contact, direction, clampf(height * 0.33, 2.1, 5.25), strength, surface)
	SoundFx.i().strike_impact(attacker.def.attribute, strength)
	# The universal contact spark must not drown out darker elements.
	if attacker.def.attribute in [Attr.A.FIRE, Attr.A.GALE, Attr.A.LIGHT] and strength >= 1.0:
		effects.hit(contact, facing, clampf(size * 0.044, 0.44, 0.85))
	if attacker.def.species != &"ratnik" or attacker._anim == null or attacker._anim._support == null:
		return
	var skeleton: Skeleton3D = attacker._anim._support.skeleton
	var sword := skeleton.find_bone("sword") if is_instance_valid(skeleton) else -1
	if sword >= 0:
		var sword_scale := clampf(attacker.figure_height() * 0.17, 1.15, 2.7)
		var hilt := skeleton.to_global(skeleton.get_bone_global_pose(sword).origin)
		effects.sword_slash(hilt - Vector3.UP * sword_scale, facing, sword_scale)

## Выбирается карта-цель. Начальная скорость рассчитана заранее; дальше действуют
## настоящие столкновения, отскоки и трение. Учитывается фактическая точка остановки.
func launch_to(slot: int) -> void:
	if flying or state.active_ball == null or not gate_slots().has(slot):
		return
	flying = true
	var ball: CreatureBall = state.active_ball
	var start: Vector3 = ball.global_position
	var target: Vector3 = arena.slot_position(slot)
	target += Vector3(rng.randf_range(-.20, .20) * Arena.CARD_W, 0, rng.randf_range(-.18, .18) * Arena.CARD_H)
	arena.set_highlight([])
	ability_panel.hide_panel()
	hud.dismiss_coach("throw")
	hud.dismiss_coach("prethrow")
	hud.set_hint("Бросок на ворота %d…" % (slot + 1))
	var bounce_feedback := func(_point: Vector3, impact: float) -> void:
		if flying and cam.mode == CameraRig.Mode.FOLLOW:
			cam.shake(clampf(impact / 80.0, .06, .18), .11)
	if fighters.size() == 2:
		var fighter: VrmFighter = fighters[owner_of(ball.uid)]
		fighter.play_motion("throw")
		fighter_shots[owner_of(ball.uid)]["throw"] += 1
		cam.fighter_view(fighter,"throw")
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
	cam.follow(ball, Vector3.ZERO)
	cam._follow_dir = Vector3(target.x - start.x, 0, target.z - start.z).normalized()
	cam._smooth = 7.0
	cam._update_follow(1.0 / 60.0)
	cam.cut()
	cam.shake(.10, .12)
	var landing: Array = await ball.settled
	var actual: Vector3 = landing[1]
	ball.surface_bounced.disconnect(bounce_feedback)
	state.active_ball = null
	var landed_slot: int = arena.slot_at(actual)
	ball.hold_landing_pose()
	if landed_slot < 0 or not gate_slots().has(landed_slot):
		cam.zoom_slot(actual)
		await wait(.12)
	# Попадание сразу передаётся раскрытию: один непрерывный облёт без серии катов.
	flying = false
	landing_ready.emit(ball.uid, landed_slot)


## Маленькая карта летит до самого пола. Волна и рост начинаются только после касания.
const CARD_FLIGHT_SCALE := .12 / Arena.CARD_W
const CARD_FLIGHT_TIME := 0.95
const CARD_GROW_TIME := 0.68

func card_placed(player: int, slot: int) -> void:
	var node: ArenaCardNode = CARD_SCENE.instantiate()
	world.add_child(node)
	var pos: Vector3 = arena.slot_position(slot)
	var start := Vector3(0, 5.5, THROW_Z if player == 0 else -THROW_Z)
	node.position = start
	node.scale = Vector3.ONE * CARD_FLIGHT_SCALE
	node.slot = slot
	node.set_meta("placement_stage", &"flight")
	node.set_meta("flight_scale",Vector3.ONE*CARD_FLIGHT_SCALE)
	var cdef: CardDef = CardDB.card(controller.get_view(HUMAN).slots[slot].card_id)
	var flight_scale := Vector3.ONE*CARD_FLIGHT_SCALE
	var release_basis := Basis.IDENTITY
	node.show_facedown(player, cdef)
	state.card_nodes[slot] = node
	if fighters.size() == 2:
		var fighter: VrmFighter = fighters[player]
		fighter_shots[player]["card_throw"] += 1
		fighter.play_motion("card_throw")
		cam.fighter_view(fighter,"card_throw")
		hud.set_hint("Бросок карты ворот")
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

	var uid: int = controller.get_view(HUMAN).players[player].creature_uids[0]
	var col: Color = VisualUtil.attr_color(creature_def(uid).attribute)
	var trail := BallTrail.new()
	trail.target = node
	trail.width = 0.10
	trail.color = col.lightened(0.20) * 0.75
	world.add_child(trail)
	trail.emitting = true
	cam.card_flight_view(start, true, 1.0 if player == 0 else -1.0)
	SoundFx.i().play("gate_flight_wind", -11.0, 0.015)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		node.position = start.lerp(pos,t)+curve*sin(PI*t)+Vector3.UP*sin(PI*t)*1.1
		# Плоский вращающийся диск, видимый с близкой камеры; масштаб в полёте неизменен.
		var flat := Basis.from_euler(Vector3(sin(PI*t)*.10,0,sin(PI*t)*-.08))
		var bank := release_basis.get_rotation_quaternion().slerp(flat.get_rotation_quaternion(),smoothstep(0,.18,t))
		node.basis = Basis(Quaternion(Vector3.UP,t*TAU*3.0))*Basis(bank)
		node.scale = flight_scale
		cam.card_flight_view(node.position, false, 1.0 if player == 0 else -1.0), 0.0, 1.0, CARD_FLIGHT_TIME)
	await tw.finished
	SoundFx.i().stop_sfx("gate_flight_wind")
	node.position = pos
	node.rotation = Vector3.ZERO
	node.set_meta("placement_stage", &"landed")
	trail.emitting = false
	get_tree().create_timer(0.45).timeout.connect(trail.queue_free)
	cam.card_expansion_view(pos)
	SoundFx.i().play("card_place", -17.0, 0.01)
	await wait(0.10)
	node.set_meta("placement_stage", &"expanding")
	arena.element_wave(pos, col, 0.80)
	SoundFx.i().play("gate_expand_wave", -4.0, 0.0)
	var grow := create_tween()
	grow.tween_property(node, "scale", Vector3.ONE, CARD_GROW_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await grow.finished
	node.set_meta("placement_stage", &"ready")
	node.set_field_surface(true)
	cam.overview()
	await wait(0.3)


func configure(match_resources: Resources, presentation_state: State, stage_world: Node3D,
		camera: CameraRig, match_hud: HudUI, powers_hud: BattleHud, abilities: AbilityPanel,
		results: BattleOverlay, random: RandomNumberGenerator) -> void:
	resources = match_resources
	state = presentation_state
	world = stage_world
	cam = camera
	hud = match_hud
	battle_hud = powers_hud
	ability_panel = abilities
	battle_overlay = results
	rng = random
	effects = MatchEffects.new()
	effects.name = &"MatchEffects"
	world.add_child(effects)

func bind_controller(value: MatchController) -> void:
	controller = value

func creature_def(uid: int) -> CreatureDef:
	return state.definitions.get(uid) as CreatureDef

func owner_of(uid: int) -> int:
	return int(state.owners.get(uid,-1))

func creature_name(uid: int) -> String:
	var definition := creature_def(uid)
	return definition.display_name if definition != null else "Существо #%d" % uid

func names_for(result: BattleResult) -> Dictionary:
	var names := {}
	for uid in [result.attacker_uid,result.defender_uid]:
		var definition := creature_def(uid)
		if definition != null:
			names[uid] = "%s (%s)" % [definition.display_name,VisualUtil.attr_name(definition.attribute)]
	return names

func gate_slots() -> Array:
	var slots: Array = []
	if controller == null: return slots
	var view: MatchState = controller.get_view(HUMAN)
	for index in view.slots.size():
		if view.slots[index].has_card: slots.append(index)
	return slots

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func cry(uid: int, kind: String, delay: float = 0.0, db: float = -1.0) -> void:
	var definition := creature_def(uid)
	if definition != null: SoundFx.i().cry(definition.id,kind,delay,db)
