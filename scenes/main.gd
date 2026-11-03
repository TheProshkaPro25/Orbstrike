extends Node
## Корень игры: владеет MatchController и AIPlayer, строит 3D-мир и UI, связывает сигналы.
## Все сигналы контроллера -> EventPlayer. Ввод/ход ИИ - только после drained (см. _pump).

const Locations := preload("res://data/arena_locations.gd")
const ARENA_SCENE: PackedScene = preload("res://scenes/arena.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/creature_ball.tscn")
const AttackFx := preload("res://scenes/attack_fx.gd")
const CARD_SCENE: PackedScene = preload("res://scenes/arena_card_node.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const SETUP_SCENE: PackedScene = preload("res://scenes/ui/setup_panel.tscn")
const ABILITY_SCENE: PackedScene = preload("res://scenes/ui/ability_panel.tscn")
const BATTLE_SCENE: PackedScene = preload("res://scenes/ui/battle_overlay.tscn")
const GAMEOVER_SCENE: PackedScene = preload("res://scenes/ui/game_over.tscn")
const TEAM_MENU_SCENE: PackedScene = preload("res://scenes/ui/team_menu.tscn")

const HUMAN := 0
const AI_PLAYER := 1
## Точка броска — перед ближним краем крупных ворот (Arena.STEP_Z * 0.5 + CARD_H * 0.5 ≈ 31.7).
const THROW_Z := Arena.STEP_Z * 0.5 + Arena.CARD_H * 0.5 + 0.8 * Arena.WORLD
const BALL_Y := 0.36

var ctrl: MatchController
var ai: AIPlayer
var rng := RandomNumberGenerator.new()

var world: Node3D
var arena: Arena
var cam: CameraRig
var events: EventPlayer
var director: ArenaDirector
var fighters: Array[VrmFighter] = []
var fighter_portraits: Array[FighterPortrait] = []
var _previous_time_scale := 1.0
var _time_scale_restored := false
var ui_layer: CanvasLayer
var hud: HudUI
var battle_hud: BattleHud
var setup_panel: SetupPanel
var ability_panel: AbilityPanel
var battle_overlay: BattleOverlay
var game_over_ui: GameOverUI
var team_menu: TeamMenu
var hover_tips: HoverTips
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _arena_sky: ShaderMaterial

var balls: Dictionary = {}
## Шесть существ матча арендованы из стартового каталога; скрытые узлы не обрабатываются.
var _preparing := false
var _prepared_balls: Dictionary = {}
var preparation_times_ms: Dictionary = {}  # uid -> миллисекунды CPU подготовки
var card_nodes: Dictionary = {}   # slot -> ArenaCardNode
var captures: Array[int] = [0, 0]
var _defs: Dictionary = {}        # uid -> CreatureDef (строится один раз из get_view)
var _owners: Dictionary = {}      # uid -> int (владелец)
var _pending: Dictionary = {}
var _active_ball: CreatureBall = null
var _ai_target_slot: int = -1
var _turn: int = 0
var _active: int = 0
var _game_over := false
var campaign: Campaign
var _campaign_registration := false
var tournament: Tournament
var tournament_panel: TournamentPanel
var _tournament_match: Dictionary = {}
var _tournament_registration := false
var _tournament_exit: Button
var _tournament_notice: Label
var _duel_menu: Button
var _duel_exit_confirm: ConfirmationDialog
var _leaving_duel := false
var _player_ids: Array[StringName] = []
var _player_deck: Array = []  # [существа, ворота, способности] из конструктора колоды
var _gate_pick: Dictionary = {}   # «ворота + бросок»: выбранные карта и слот, ждём выбора существа
var _pip_idx: Dictionary = {}     # uid -> номер шарика на плашке бойца
var _stats: Dictionary = {"wins": [0, 0], "abilities": [0, 0], "traps": 0, "battles": []}  # итоги для экрана результата


## Выход возвращает арендованные объекты; сам каталог живёт до закрытия игры.
func _exit_tree() -> void:
	if is_instance_valid(GameLoading._inst) and GameLoading._inst.moving_scene:
		return
	_release_game_resources()
	_restore_time_scale()
	CreatureModels.clear()


func _restore_time_scale() -> void:
	if not _time_scale_restored:
		Engine.time_scale = _previous_time_scale
		_time_scale_restored = true


func _ready() -> void:
	_previous_time_scale = Engine.time_scale
	BattleTempo.load_settings()
	if is_equal_approx(Engine.time_scale, 1.0):
		BattleTempo.apply()
	SoundFx.i()
	rng.randomize()
	_build_world()
	_build_ui()
	team_menu.deck_chosen.connect(_on_deck_chosen)
	if not GameLoading.i().preparing:
		SoundFx.i().play_music(SoundFx.MUSIC_TEAM)
		call_deferred("enter_requested_mode")


# ---------------------------------------------------------------- построение

## Небо статично (без TIME): иначе Godot пересчитывает кубическую карту отражений каждый кадр.
const SKY_SHADER := """
shader_type sky;
uniform vec4 sky_zenith : source_color = vec4(0.016, 0.033, 0.062, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.08, 0.14, 0.19, 1.0);
uniform vec4 sky_mist : source_color = vec4(0.11, 0.035, 0.13, 1.0);
// Непрерывные волны без floor/hash: нет клеток на гранях небесного куба.
void sky() {
	vec3 d = normalize(EYEDIR);
	float horizon = exp(-abs(d.y - 0.025) * 4.0);
	float w1 = sin(d.x * 3.6 + d.z * 2.4 + sin(d.y * 4.0) * 1.3);
	float w2 = sin(d.z * 5.2 - d.y * 3.1 + sin(d.x * 3.3));
	float mist = smoothstep(-0.7, 1.4, w1 + w2 * 0.45);
	vec3 zenith = sky_zenith.rgb;
	vec3 col = zenith + sky_horizon.rgb * horizon;
	col += mix(vec3(0.025, 0.055, 0.09), sky_mist.rgb, mist) * (0.3 + 0.7 * horizon);
	COLOR = col;
}
"""


## Экспозиция кадра (подобрана по контактным листам: средняя яркость ~0.25–0.35 без пересвета).
const LIGHT_EXPOSURE := 1.0


func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)

	# Небо-туманность: пространство боя вне обычного мира (по мотивам аниме)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = Shader.new()
	sky_mat.shader.code = SKY_SHADER
	_arena_sky = sky_mat
	var sky := Sky.new()
	sky.sky_material = sky_mat
	# без TIME в шейдере небо (и карта отражений) считается один раз, а не каждый кадр (режим REALTIME)
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 1.5
	# Ясный аниме-свет: заполняющий ambient — ровный холодно-лиловый цвет (тёмное небо почти не светит)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.52, 0.64)
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = LIGHT_EXPOSURE
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.0  # без общего «молочного» ореола на ярком кадре
	env.glow_hdr_threshold = 1.1
	env.glow_strength = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.5  # большой радиус чернил впадины на моделях
	env.ssao_intensity = 1.0
	# туман к горизонту: поле без краёв, дальние ориентиры тонут в дымке цвета неба
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.16, 0.21)
	env.fog_density = 0.0025
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -30.0, 0.0)
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 2.6
	sun.shadow_enabled = true
	# Чёткие тени под размер поля: мягкий PCSS (1.5°) на огромной арене давал шумные кляксы.
	sun.light_angular_distance = 0.4
	sun.shadow_blur = 1.0
	sun.shadow_normal_bias = 1.5
	sun.shadow_opacity = 0.6  # тень от крыльев на теле не чернит модель целиком
	# каскады и дальность теней, SSAO, сглаживание — по уровню графики (GraphicsSettings, apply_graphics)
	world.add_child(sun)
	_env = env
	_sun = sun

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, 150.0, 0.0)
	fill.light_color = Color(0.45, 0.6, 1.0)
	fill.light_energy = 0.9
	world.add_child(fill)
	_fill = fill

	cam = CameraRig.new()
	world.add_child(cam)
	cam.snap_overview()
	cam.current = true

	arena = GameLoading.i().take_arena(Locations.current()) if GameLoading.i().ready_to_play else null
	if arena == null:
		arena = ARENA_SCENE.instantiate() as Arena
		arena.location_id = Locations.current()
		world.add_child(arena)
	else:
		arena.reparent(world, false)
	_apply_arena_environment(arena.location_id)
	apply_graphics()

	events = EventPlayer.new()
	add_child(events)
	director = ArenaDirector.new()
	director.game = self
	add_child(director)


## Применить уровень графики (при старте и после смены в меню команды).
func apply_graphics() -> void:
	GraphicsSettings.apply_world(get_viewport(), _env, _sun)
	if arena != null:
		arena.apply_quality()
		_apply_arena_environment(arena.location_id)


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	# Тёмная виньетка по краям кадра (под интерфейсом)
	var vig := ColorRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vsh := Shader.new()
	vsh.code = "shader_type canvas_item;\nvoid fragment() { vec2 q = UV - 0.5; float v = smoothstep(0.35, 0.85, length(q * vec2(1.25, 1.0))); COLOR = vec4(0.0, 0.0, 0.02, v * 0.6); }"
	var vmat := ShaderMaterial.new()
	vmat.shader = vsh
	vig.material = vmat
	ui_layer.add_child(vig)
	battle_hud = BattleHud.new()
	ui_layer.add_child(battle_hud)
	hud = HUD_SCENE.instantiate() as HudUI
	ui_layer.add_child(hud)
	setup_panel = SETUP_SCENE.instantiate() as SetupPanel
	ui_layer.add_child(setup_panel)
	ability_panel = ABILITY_SCENE.instantiate() as AbilityPanel
	ui_layer.add_child(ability_panel)
	battle_overlay = BATTLE_SCENE.instantiate() as BattleOverlay
	ui_layer.add_child(battle_overlay)
	game_over_ui = GAMEOVER_SCENE.instantiate() as GameOverUI
	ui_layer.add_child(game_over_ui)
	team_menu = TEAM_MENU_SCENE.instantiate() as TeamMenu
	ui_layer.add_child(team_menu)
	team_menu.location_previewed.connect(_preview_arena_location)
	team_menu.location_preview_closed.connect(func() -> void: cam.snap_overview(); hud.visible = true)
	hover_tips = HoverTips.new()
	hover_tips.resolver = _tip_at
	ui_layer.add_child(hover_tips)
	ui_layer.move_child(hover_tips, ui_layer.get_child_count() - 2)  # под меню, над остальным интерфейсом
	# Отдельно от HUD: выход доступен и во время постановки/экрана результата.
	_duel_menu = Button.new()
	_duel_menu.text = "В меню"
	_duel_menu.tooltip_text = "Завершить обычную дуэль и вернуться в главное меню"
	_duel_menu.theme = UiTheme.get_theme()
	_duel_menu.custom_minimum_size = Vector2(112, 38)
	VisualUtil.place(_duel_menu, 1.0, 0.0, -16.0, 164.0)
	_duel_menu.hide()
	_duel_menu.pressed.connect(_request_duel_menu)
	ui_layer.add_child(_duel_menu)
	hud.battle_mode_changed.connect(_place_duel_menu)


func _place_duel_menu(battle: bool) -> void:
	# В бою верхняя полоса свободна; правую силу и руку способностей не закрываем.
	VisualUtil.place(_duel_menu, 0.5 if battle else 1.0, 0.0, 0.0 if battle else -16.0, 12.0 if battle else 164.0)


func _on_deck_chosen(creatures: Array[StringName], arena_ids: Array[StringName], abilities: Array[StringName]) -> void:
	if _tournament_registration:
		_register_tournament(creatures, arena_ids, abilities)
		return
	_preparing = true
	_player_ids = creatures
	_player_deck = [creatures, arena_ids, abilities]
	_build_logic()
	call_deferred("_start_game")


func _build_logic() -> void:
	CardDB.load_all()
	var decks: Array[DeckDef] = _build_decks()
	var seed_value: int = int(_tournament_match.seed) if not _tournament_match.is_empty() else int(rng.randi())
	if not _tournament_match.is_empty(): rng.seed = seed_value
	ctrl = MatchController.new(decks[0], decks[1], seed_value)
	ctrl.landing_window = true  # окно прикрепления способности после приземления на пустые ворота
	ai = AIPlayer.new(AI_PLAYER, seed_value + 1, -1.0, int(tournament.state.difficulty) if tournament != null else TeamMenu.difficulty)
	if tournament != null:
		ai.configure_personality(campaign.ai_preferences(_tournament_opponent()) if campaign != null else Tournament.personality(_tournament_opponent()))
	_index_creatures()

	ctrl.card_drawn.connect(_on_card_drawn)
	ctrl.phase_changed.connect(_on_phase_changed)
	ctrl.setup_requested.connect(_on_setup_requested)
	ctrl.arena_card_placed.connect(_on_arena_card_placed)
	ctrl.throw_requested.connect(_on_throw_requested)
	ctrl.creature_selected.connect(_on_creature_selected)
	ctrl.creature_returned.connect(_on_creature_returned)
	ctrl.creature_stood.connect(_on_creature_stood)
	ctrl.battle_started.connect(_on_battle_started)
	ctrl.card_revealed.connect(_on_card_revealed)
	ctrl.ability_window.connect(_on_ability_window)
	ctrl.ability_played.connect(_on_ability_played)
	ctrl.ability_cancelled.connect(_on_ability_cancelled)
	ctrl.battle_resolved.connect(_on_battle_resolved)
	ctrl.creature_eliminated.connect(_on_creature_eliminated)
	ctrl.card_captured.connect(_on_card_captured)
	ctrl.turn_started.connect(_on_turn_started)
	ctrl.game_over.connect(_on_game_over)
	ctrl.ability_attached.connect(_on_ability_attached)
	ctrl.attach_window.connect(_on_attach_window)
	ctrl.gate_thrown.connect(_on_gate_thrown)
	ctrl.gate_trap_triggered.connect(_on_gate_trap)
	ctrl.momentum_changed.connect(_on_momentum_changed)
	ctrl.final_round_started.connect(_on_final_round)

	events.drained.connect(_pump)
	hud.creature_chosen.connect(_on_creature_chosen)
	setup_panel.placed.connect(_on_setup_placed)
	setup_panel.skipped.connect(_on_setup_skipped)
	setup_panel.placed_throw.connect(_on_setup_placed_throw)
	setup_panel.slot_hovered.connect(arena.set_hover)
	arena.slot_clicked.connect(_on_slot_picked)
	arena.invalid_pick.connect(func() -> void: hud.reject_action("Выберите одно из подсвеченных мест на поле"))
	ability_panel.unavailable.connect(func(reason: String) -> void: hud.reject_action(reason))
	ability_panel.reason_for_card = func(cid: StringName) -> String: return ctrl.ability_unavailable_reason(HUMAN, cid)
	hud.creature_cancelled.connect(_on_gate_throw_cancelled)
	ctrl.creature_relocated.connect(func(uid: int, a: int, b: int) -> void:
		if a != b:
			_log("%s переходит на другие ворота" % _cname(uid))
		events.push(_anim_relocated.bind(uid, a, b)))
	ctrl.creature_revived.connect(_on_creature_revived)
	ctrl.creature_marked.connect(_on_creature_marked)
	ctrl.fighter_swapped.connect(_on_fighter_swapped)
	ctrl.gates_swapped.connect(_on_gates_swapped)
	ctrl.gate_discarded.connect(_on_gate_discarded)
	ctrl.abilities_recalled.connect(_on_abilities_recalled)
	ctrl.abilities_recharged.connect(_on_abilities_recharged)
	ctrl.gates_recycled.connect(func() -> void: events.push(func() -> void:
		hud.flash("Ворота кончились: выигранные карты вернулись в руки")
		await hud.wait_read(HudUI.read_time(1.2, "Ворота кончились: выигранные карты вернулись в руки"))
		hud.clear_flash()))
	ctrl.creatures_refilled.connect(func(p: int) -> void: events.push(_anim_refilled.bind(p)))
	ctrl.standoff.connect(func(a: int, d: int) -> void: events.push(func() -> void:
		var msg := "Бросать некому — %s идёт на %s!" % [_cname(a), _cname(d)]
		hud.flash(msg)
		await hud.wait_read(HudUI.read_time(1.4, msg))
		hud.clear_flash()))
	ctrl.turn_skipped.connect(func(p: int) -> void: events.push(func() -> void:
		var msg2 := "Все ваши существа на воротах — ход переходит сопернику" if p == HUMAN else "Все существа соперника на воротах — ваш ход"
		hud.flash(msg2)
		await hud.wait_read(HudUI.read_time(1.2, msg2))
		hud.clear_flash()))
	ability_panel.ability_chosen.connect(_on_ability_chosen)
	ability_panel.passed.connect(_on_ability_passed)
	ability_panel.gate_open_requested.connect(_on_gate_open_requested)
	game_over_ui.restart_requested.connect(_on_restart)


func _start_game() -> void:
	var pool := GameLoading.i()
	_prepare_match_fighters()
	if pool.ready_to_play:
		for uid in _defs:
			var def: CreatureDef = _creature_def(uid)
			var ball := pool.take_ball(def.id, uid, _start_pos(_owner_of(uid)))
			if ball == null:
				push_error("В стартовом каталоге нет свободного существа: " + String(def.id))
				return
			ball.reparent(world, false)
			ball.visible = false
			ball.process_mode = Node.PROCESS_MODE_DISABLED
			_prepared_balls[uid] = ball
			preparation_times_ms[uid] = pool.preparation_times_ms.get(def.id, 0.0)
	else:
		# Изолированные стенды могут запускать main.tscn без стартовой сцены.
		# Обычный вход игры проходит Boot и использует только резидентный каталог.
		CreatureModels.preload_match(_defs.values())
		for uid in _defs:
			await get_tree().process_frame
			var begin := Time.get_ticks_usec()
			var ball := BALL_SCENE.instantiate() as CreatureBall
			ball.visible = false
			world.add_child(ball)
			ball.setup(_creature_def(uid), uid)
			ball.freeze_at(_start_pos(_owner_of(uid)))
			ball.process_mode = Node.PROCESS_MODE_DISABLED
			_prepared_balls[uid] = ball
			preparation_times_ms[uid] = (Time.get_ticks_usec() - begin) / 1000.0
	hud.set_hint("Сферы Стихий")
	SoundFx.i().play_music(SoundFx.i().turn_music())  # матч начался — музыка ходов
	var view: MatchState = ctrl.get_view(HUMAN)
	var cols: Array = [[], []]
	var elems: Array = [[], []]
	for p in range(2):
		var idx := 0
		for uid in view.players[p].creature_uids:
			cols[p].append(VisualUtil.attr_color(_creature_def(uid).attribute))
			elems[p].append(_creature_def(uid).attribute)
			_pip_idx[uid] = idx
			idx += 1
	hud.setup_plates(cols[0], cols[1], elems)
	hud.set_names(tournament.participant_name(0) if tournament != null else fighters[0].appearance_profile.name, tournament.participant_name(_tournament_opponent()) if tournament != null else "Соперник · %s" % AIPlayer.difficulty_name(TeamMenu.difficulty))
	hud.set_captures(0, 0)
	_preparing = false
	ctrl.start(_tournament_first_side() if tournament != null else 0)
	_refresh_hand()
	ability_panel.set_dock_visible(true)
	setup_panel.set_dock_visible(true)
	_duel_menu.visible = tournament == null


func _request_duel_menu() -> void:
	if _leaving_duel or tournament != null or ctrl == null:
		return
	if _game_over:
		_leave_duel_to_menu()
		return
	if is_instance_valid(_duel_exit_confirm):
		_duel_exit_confirm.popup_centered()
		return
	_duel_exit_confirm = ConfirmationDialog.new()
	_duel_exit_confirm.theme = UiTheme.get_theme()
	_duel_exit_confirm.title = "Вернуться в главное меню?"
	_duel_exit_confirm.dialog_text = "Текущая дуэль завершится. Можно будет начать новую."
	_duel_exit_confirm.ok_button_text = "В меню"
	_duel_exit_confirm.cancel_button_text = "Продолжить дуэль"
	_duel_exit_confirm.confirmed.connect(_leave_duel_to_menu)
	ui_layer.add_child(_duel_exit_confirm)
	_duel_exit_confirm.popup_centered()


func _leave_duel_to_menu() -> void:
	if _leaving_duel or tournament != null:
		return
	_leaving_duel = true
	_pending.clear()
	_gate_pick.clear()
	events.stop()
	SoundFx.i().cancel_match_sfx()
	_duel_menu.disabled = true
	# Сначала удаляется вся сцена (включая владельцев await и твинов).
	# _exit_tree возвращает актёров/арену через _release_game_resources().
	# Не ждём drained: результат боя может ждать подтверждения бесконечно.
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


## Сохранённый образ применяется к готовой паре из стартового каталога.
func _prepare_match_fighters() -> void:
	var saved := PlayerProfile.new()
	saved.load_from()
	var rival := PlayerProfile.npc_profile(_tournament_opponent() if tournament != null else 2)
	if tournament != null: rival.name = tournament.participant_name(_tournament_opponent())
	for side in 2:
		var profile: Dictionary = saved.value if side == 0 else rival
		var fighter := GameLoading.i().take_fighter(profile)
		if fighter == null:
			assert(not GameLoading.i().ready_to_play,"Missing resident fighter")
			fighter = VrmFighter.new() # Isolated test scenes without Boot only.
			world.add_child(fighter)
			fighter.apply_profile(profile)
		else: fighter.reparent(world,false)
		fighter.position = Vector3(-2.3 if side == 0 else 2.3,0,(THROW_Z+1.4)*(1 if side == 0 else -1))
		fighter.rotation.y = PI if side == 0 else 0.0
		fighters.append(fighter)
		var portrait := FighterPortrait.new()
		add_child(portrait)
		portrait.bind(fighter,side)
		fighter_portraits.append(portrait)
		hud.set_portrait(side,portrait.get_texture())


## Подписи существ: только перечисленные uid (пустой список - все).
## В бою (два uid) остальные существа скрываются: бой изолирован, как в аниме.
func _focus_labels(uids: Array) -> void:
	for u in balls.keys():
		var b: CreatureBall = balls[u]
		b.set_label_allowed(uids.is_empty() or (uids.has(u) and uids.size() < 2))
		b.visible = uids.size() < 2 or uids.has(u)


## 3D-эффект способности у своего существа (и у соперника, если карта бьёт по нему).
func _ability_fx(player: int, def: CardDef) -> void:
	if def == null or _battle_uids.size() != 2:
		return
	var mine: int = _battle_uids[0] if _owner_of(_battle_uids[0]) == player else _battle_uids[1]
	var foe: int = _battle_uids[1] if mine == _battle_uids[0] else _battle_uids[0]
	var mb: CreatureBall = balls.get(mine)
	var fb: CreatureBall = balls.get(foe)
	if mb == null:
		return
	var h: float = Arena.FIG_H * 0.7
	var r: float = Arena.FIG_W * 0.32
	var base: Vector3 = mb.global_position - Vector3(0, CreatureBall.RADIUS, 0)
	var foe_base: Vector3 = fb.global_position - Vector3(0, CreatureBall.RADIUS, 0) if fb != null else base
	var cls: StringName = CardDB.card_class(def)
	var eff := String(def.effect_id)
	# Одна карта — один короткий обмен: движение, ответ, затем новое число силы.
	if eff in ["negate", "cap_own_base", "aloft"]:
		mb.ability_pulse()
	elif eff in ["siphon", "strip", "reset_base", "weaken_mark", "drain", "scorch", "radiance", "eclipse", "pact", "doom"]:
		if fb != null:
			await mb.counter_lunge(fb.global_position)
			if not is_instance_valid(mb) or not is_instance_valid(fb):
				return
			fb.take_hit(VisualUtil.attr_color(_creature_def(mine).attribute).lightened(0.2))
		else:
			mb.ability_pulse()
	else:
		mb.ability_pulse()
	if CardEffects.is_fusion(def):
		var tc := UiTheme.FUSION_GLOW
		VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), tc, r * 2.2, 0.6)
		get_tree().create_timer(0.2).timeout.connect(func() -> void: VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), tc, r * 3.0, 0.7))
		VisualUtil.spiral(world, base, tc, h, r, 1.0)
	elif cls == &"red":
		var lock: int = CardEffects.lock_attr(def)
		var ec: Color = VisualUtil.attr_color(lock if lock >= 0 else _creature_def(mine).attribute).lightened(0.25)
		VisualUtil.light_pillar(mb, Vector3(0, -CreatureBall.RADIUS, 0), ec, h * 1.8, r * 0.9, 0.9)
		VisualUtil.spiral(world, base, ec, h * 1.2, r * 1.2, 1.1)
		VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), ec, r * 3.0, 0.7)
		if eff in ["drain", "scorch", "radiance", "eclipse", "pact", "doom"]:
			VisualUtil.burst(world, foe_base + Vector3(0, h * 0.5, 0), Color(0.8, 0.15, 0.2), Arena.WORLD * 0.7)
		if eff in ["purge_gate", "eclipse", "shift_gate"]:
			_gate_fx(base, foe_base)
	elif cls == &"blue":
		var bc: Color = VisualUtil.attr_color(CardEffects.lock_attr(def)).lightened(0.3) if CardEffects.lock_attr(def) >= 0 else Color(1.0, 0.8, 0.35)
		VisualUtil.spiral(world, base, bc, h * 1.1, r, 1.0)
		VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), bc, r * 2.5, 0.6)
	else:
		var gc := UiTheme.SPECIES_GLOW
		match eff:
			"negate", "cap_own_base":
				VisualUtil.dome(world, base, gc, r * 1.9, 1.6)
			"nullify_gate", "aloft":
				_gate_fx(base, foe_base)
			"siphon", "strip", "reset_base", "weaken_mark", "scorch":
				VisualUtil.spiral(world, foe_base, Color(0.85, 0.15, 0.2), h, r, 1.0)
				VisualUtil.burst(world, foe_base + Vector3(0, h * 0.5, 0), Color(0.8, 0.1, 0.15), Arena.WORLD * 0.7)
				if eff == "reset_base":
					VisualUtil.spiral(world, base, gc, h, r, 1.0)
			_:
				VisualUtil.spiral(world, base, gc, h, r, 1.0)
				VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), gc, r * 2.5, 0.7)


## Вспышка на воротах между бойцами (отмена или сдвиг ворот).
func _gate_fx(base: Vector3, foe_base: Vector3) -> void:
	var cardpos: Vector3 = (base + foe_base) * 0.5
	VisualUtil.ring_wave(world, cardpos + Vector3(0, 0.1, 0), Color(0.9, 0.95, 1.0), Arena.CARD_H * 0.9, 0.8)
	VisualUtil.burst(world, cardpos + Vector3(0, 0.5, 0), Color(0.8, 0.9, 1.0), Arena.WORLD)


## Крик существа по uid (с задержкой, чтобы совпасть с анимацией).
func _cry(uid: int, kind: String, delay: float = 0.0, db: float = -1.0) -> void:
	var d: CreatureDef = _creature_def(uid)
	if d != null:
		SoundFx.i().cry(d.id, kind, delay, db)


## Рука способностей игрока внизу справа.
func _refresh_hand() -> void:
	if ctrl == null:
		return
	ability_panel.set_hand(ctrl.get_view(HUMAN).players[HUMAN].ability_hand)
	setup_panel.set_hand(ctrl.get_view(HUMAN).players[HUMAN].arena_hand)


func _on_restart() -> void:
	if tournament != null:
		_reload_tournament()
		return
	if GameLoading.i().ready_to_play:
		_release_game_resources()
		_restore_time_scale()
		GameLoading.i().show_game()
	else:
		get_tree().reload_current_scene()


## Возвращаем живые модели до освобождения сцены; каталог принадлежит загрузчику.
func _release_game_resources() -> void:
	var pool := GameLoading._inst
	for portrait in fighter_portraits:
		portrait.fighter = null
		portrait.render_target_update_mode = SubViewport.UPDATE_DISABLED
		portrait.queue_free()
	fighter_portraits.clear()
	if is_instance_valid(hud):
		for side in 2: hud.set_portrait(side,null)
	for fighter in fighters:
		if is_instance_valid(pool) and pool.ready_to_play: pool.return_fighter(fighter)
		else: fighter.queue_free()
	fighters.clear()
	if not is_instance_valid(pool) or not pool.ready_to_play:
		return
	process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(team_menu):
		team_menu._preview.release()
	for ball in balls.values() + _prepared_balls.values():
		pool.return_ball(ball)
	balls.clear()
	_prepared_balls.clear()
	if is_instance_valid(arena):
		pool.return_arena(arena)
		arena = null


# ---------------------------------------------------------------- колоды и справочник uid

## Колоды строит ядро: пресет игрока и случайная колода ИИ из общего пула (CardDB).
func _build_decks() -> Array[DeckDef]:
	if tournament != null and not _tournament_match.is_empty():
		return [tournament.participant_deck(0), tournament.participant_deck(_tournament_opponent())]
	var mine: DeckDef = null
	if _player_deck.size() == 3 and CardDB.deck_error(_player_deck[0], _player_deck[1], _player_deck[2]) == "":
		mine = CardDB.build_deck(_player_deck[0], _player_deck[1], _player_deck[2])
	if mine == null:
		push_warning("Недопустимая команда, берётся пресет")
		mine = CardDB.preset_deck(0)
	return [mine, CardDB.opponent_deck(rng)]


## uid -> определение и владелец. Существа в get_view не маскируются, uid не меняются за матч.
func _index_creatures() -> void:
	var view: MatchState = ctrl.get_view(HUMAN)
	for p in range(2):
		for uid in view.players[p].creature_uids:
			var cs: CreatureState = view.creature(uid)
			_defs[uid] = CardDB.creature(cs.def_id)
			_owners[uid] = cs.owner


func _creature_def(uid: int) -> CreatureDef:
	return _defs.get(uid) as CreatureDef


func _owner_of(uid: int) -> int:
	return int(_owners.get(uid, -1))


func _cname(uid: int) -> String:
	var d: CreatureDef = _creature_def(uid)
	if d == null:
		return "Существо #%d" % uid
	return d.display_name


func _names_for(r: BattleResult) -> Dictionary:
	var out: Dictionary = {}
	for u in [r.attacker_uid, r.defender_uid]:
		var d: CreatureDef = _creature_def(u)
		if d != null:
			out[u] = "%s (%s)" % [d.display_name, VisualUtil.attr_name(d.attribute)]
	return out


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


# ---------------------------------------------------------------- подсказки для 3D-объектов

## Что под мышью: существо/шар (ближайшее по проекции) или карта ворот. {} — ничего.
func _tip_at(mp: Vector2) -> Dictionary:
	if ctrl == null or _game_over or _preparing or hud._battle or team_menu.visible or cam == null or events.is_busy() or director.flying:
		return {}
	var view: MatchState = ctrl.get_view(HUMAN)
	# существа и шар перед броском
	var best_uid := -1
	var best_d := 1e9
	var best_rect := Rect2()
	for u in balls.keys():
		var b: CreatureBall = balls[u]
		if b == null or not is_instance_valid(b) or not b.visible:
			continue
		var base: Vector3 = b.global_position - Vector3(0, CreatureBall.RADIUS, 0)
		var on_field: bool = view.creature(u).slot >= 0
		var h: float = b.figure_height() if on_field else CreatureBall.RADIUS * 2.0
		var top: Vector3 = base + Vector3(0, h, 0)
		if cam.is_position_behind(base) or cam.is_position_behind(top):
			continue
		var p0: Vector2 = cam.unproject_position(base)
		var p1: Vector2 = cam.unproject_position(top)
		var rad: float = maxf(24.0, p0.distance_to(p1) * 0.22)
		var d: float = Geometry2D.get_closest_point_to_segment(mp, p0, p1).distance_to(mp)
		if d < rad and d / rad < best_d:
			best_d = d / rad
			best_uid = u
			best_rect = Rect2(p0, Vector2.ZERO).expand(p1).grow(rad)
	if best_uid >= 0:
		return {"key": "c%d" % best_uid, "lines": _creature_tip(best_uid, view), "rect": best_rect}
	# карты ворот: попадание в проекцию прямоугольника карты
	for i in range(view.slots.size()):
		var sl: SlotState = view.slots[i]
		var c: Vector3 = arena.slot_position(i)
		var hw: float = Arena.CARD_W * 0.5
		var hh: float = Arena.CARD_H * 0.5
		var poly := PackedVector2Array()
		var ok := true
		for corner in [Vector3(-hw, 0, -hh), Vector3(hw, 0, -hh), Vector3(hw, 0, hh), Vector3(-hw, 0, hh)]:
			var wp: Vector3 = c + corner
			if cam.is_position_behind(wp):
				ok = false
				break
			poly.append(cam.unproject_position(wp))
		if not ok or not Geometry2D.is_point_in_polygon(mp, poly):
			continue
		var lines: Array = _slot_tip(i, sl, view)
		if not lines.is_empty():
			var sr := Rect2(poly[0], Vector2.ZERO)
			for q in poly:
				sr = sr.expand(q)
			return {"key": "s%d:%s" % [i, str(sl.card_id) + str(sl.revealed)], "lines": lines, "rect": sr}
	return {}


func _slot_tip(i: int, sl: SlotState, view: MatchState) -> Array:
	if not sl.has_card:
		if ctrl.get_phase() == MatchController.Phase.SETUP and ctrl.get_active_player() == HUMAN and ctrl.legal_setup_slots().has(i):
			return ["Свободное место", "Выкладка ворот", UiTheme.GOLD, "Сюда можно положить карту ворот: рядом с уже лежащими картами.", "Бросок на пустое место — промах.", "", ""]
		return []
	var mine: bool = sl.card_owner == HUMAN
	var occ := ""
	if sl.occupant_uid >= 0:
		occ = "На воротах стоит: %s (%s)." % [_cname(sl.occupant_uid), "ваше" if _owner_of(sl.occupant_uid) == HUMAN else "существо соперника"]
	var def: CardDef = CardDB.card(sl.card_id)
	if def == null:
		return ["Закрытые ворота соперника", "Ворота · рубашкой вверх", UiTheme.GOLD_DIM,
			"Владелец может открыть карту во время боя. Пока ворота закрыты, их бонусы и ловушки не действуют.", "Закрытая карта соперника.", "", occ]
	var lines: Array = UiTheme.card_help(def)
	if not sl.revealed:
		lines[1] = "%s · ваша закрытая карта" % lines[1] if mine else lines[1]
		lines[5] = "Соперник не видит эту карту до боя. " + str(lines[5]) if mine else lines[5]
	lines[6] = (str(lines[6]) + "\n" + occ).strip_edges() if occ != "" else lines[6]
	return lines


func _creature_tip(uid: int, view: MatchState) -> Array:
	var d: CreatureDef = _creature_def(uid)
	var cs: CreatureState = view.creature(uid)
	var lines: Array = UiTheme.creature_help(d)
	var mine: bool = _owner_of(uid) == HUMAN
	lines[1] = "%s · %s" % [lines[1], "ваше существо" if mine else "существо соперника"]
	var power: int = d.base_power
	var extra: Array[String] = ["Базовая сила: %d" % power]
	if cs.slot >= 0:
		var sl: SlotState = view.slots[cs.slot]
		var cd: CardDef = CardDB.card(sl.card_id)
		# сила с воротами: бонус открытой карты (те же правила, что в PowerCalc, роль защитника)
		if sl.revealed and cd != null:
			var gate: int = PowerCalc.gate_bonus_for(view, uid, cs.slot)
			if gate != 0:
				extra.append("Сила %d %s %d ворота = %d" % [power, "+" if gate > 0 else "−", absi(gate), power + gate])
			else:
				extra.append("Сила %d (ворота бонуса не дают)" % power)
		else:
			extra.append("Сила %d (ворота закрыты)" % power)
		extra.append("Стоит на воротах №%d%s" % [cs.slot + 1, (": «%s»" % cd.display_name) if cd != null else " (карта закрыта)"])
	else:
		extra.append("Выберите подсвеченные ворота для броска сферы" if mine else "Шар соперника")
	for mk in cs.marks:
		extra.append("Метка «%s»: %s в следующем бою" % [_card_name(StringName(mk.get("src", ""))),
			("сила ровно %d" % int(mk["fix"])) if mk.has("fix") else "%+d" % int(mk.get("delta", 0))])
	if not cs.attached.is_empty():
		var names: Array[String] = []
		for a in cs.attached:
			names.append("«%s»" % _card_name(StringName(a[1])))
		extra.append("Прикреплено: " + ", ".join(names))
	lines[6] = "\n".join(extra)
	return lines


## Строка в ленту событий — в порядке очереди анимаций.
func _log(text: String, c: Color = UiTheme.TEXT) -> void:
	events.push(func() -> void: hud.log_event(text, c))


func _say(player: int, you: String, foe: String) -> String:
	return you if player == HUMAN else foe


# ---------------------------------------------------------------- обработчики сигналов контроллера
# Состояние контроллера уже изменено; здесь только ставим анимации в очередь.

func _on_phase_changed(phase: int, active_player: int) -> void:
	events.push(_anim_phase.bind(phase, active_player))


func _on_setup_requested(player: int) -> void:
	events.push(_anim_set_pending.bind({"kind": "setup", "player": player}))


func _on_arena_card_placed(player: int, slot: int) -> void:
	_log(_say(player, "Вы кладёте карту ворот", "Соперник кладёт карту ворот"))
	events.push(_anim_card_placed.bind(player, slot))


func _on_throw_requested(player: int) -> void:
	events.push(_anim_set_pending.bind({"kind": "throw", "player": player}))


func _on_creature_selected(player: int, uid: int, recalled: bool) -> void:
	_log("%s: %s" % [_say(player, "Вы бросаете", "Соперник бросает"), _cname(uid)])
	events.push(_anim_selected.bind(player, uid, recalled))


func _on_creature_returned(uid: int, reason: StringName) -> void:
	if reason == &"miss":
		_log("Промах: %s" % _cname(uid), Color(1.0, 0.7, 0.6))
	events.push(_anim_returned.bind(uid, reason))


func _on_creature_stood(uid: int, slot: int) -> void:
	_log("%s встаёт на ворота" % _cname(uid))
	events.push(_anim_stood.bind(uid, slot))


func _on_battle_started(slot: int, attacker_uid: int, defender_uid: int) -> void:
	var pre: BattleResult = ctrl.get_battle_preview()
	var pw: Array = [pre.powers[0], pre.powers[1]] if pre != null else []
	var mo: Array = [pre.momentum[0], pre.momentum[1]] if pre != null else [0, 0]
	_log("Бой: %s против %s" % [_cname(attacker_uid), _cname(defender_uid)], UiTheme.GOLD)
	events.push(_anim_battle_started.bind(slot, attacker_uid, defender_uid, pw, mo))
	if pre != null:
		events.push(battle_hud.set_chain.bind(pre.plays.duplicate(true), [false, false]))  # прикреплённые карты


func _on_card_revealed(slot: int, card_id: StringName) -> void:
	var owner: int = ctrl.get_view(HUMAN).slots[slot].card_owner
	events.push(_anim_card_revealed.bind(slot, card_id, owner))


func _on_ability_window(player: int, _options: Array) -> void:
	# Список карт берётся при ответе из ctrl.legal_abilities(player).
	events.push(_anim_set_pending.bind({"kind": "ability", "player": player}))


func _on_ability_played(player: int, card_id: StringName) -> void:
	_refresh_hand()
	_stats["abilities"][player] += 1
	_log("%s «%s»" % [_say(player, "Вы играете", "Соперник играет"), _card_name(card_id)], Color(0.75, 0.6, 1.0))
	var pre: BattleResult = ctrl.get_battle_preview()
	var pw: Array = [pre.powers[0], pre.powers[1]] if pre != null else []
	events.push(_anim_ability_msg.bind(player, card_id, false, pw))
	if pre != null:
		events.push(battle_hud.set_chain.bind(pre.plays.duplicate(true), pre.passed.duplicate()))


func _on_ability_cancelled(player: int, card_id: StringName) -> void:
	events.push(_anim_ability_msg.bind(player, card_id, true))


func _on_battle_resolved(result: BattleResult) -> void:
	_refresh_hand()
	if result.winner_uid < 0:
		var what: String = "Бой прерван: Отлив" if result.interrupted else "Выбывают оба бойца"
		_stats["battles"].append({"turn": ctrl.get_turn(), "winner": "—", "loser": "%s и %s" % [_cname(result.attacker_uid), _cname(result.defender_uid)],
			"wp": result.powers[0], "lp": result.powers[1], "mine": false})
		events.push(_anim_battle_resolved.bind(result))
		_log(what, UiTheme.GOLD)
		return
	var win_p: int = _owner_of(result.winner_uid)
	var atk_won: bool = result.winner_uid == result.attacker_uid
	var wp: int = result.powers[0 if atk_won else 1]
	var lp: int = result.powers[1 if atk_won else 0]
	_stats["wins"][win_p] += 1
	_stats["battles"].append({"turn": ctrl.get_turn(), "winner": _cname(result.winner_uid), "loser": _cname(result.loser_uid),
		"wp": wp, "lp": lp, "mine": win_p == HUMAN})
	events.push(_anim_battle_resolved.bind(result))
	_log("Побеждает %s (%d : %d)" % [_cname(result.winner_uid), wp, lp], Color(0.6, 1.0, 0.6) if win_p == HUMAN else Color(1.0, 0.6, 0.55))


func _on_creature_eliminated(uid: int) -> void:
	events.push(_anim_remove_ball.bind(uid, true))
	events.push(func() -> void: hud.kill_creature(_owner_of(uid), int(_pip_idx.get(uid, -1))))


func _on_card_captured(player: int, slot: int, _card_id: StringName) -> void:
	_log("%s: ворота захвачены" % _say(player, "Вы", "Соперник"), UiTheme.GOLD)
	events.push(_anim_captured.bind(player, slot))


func _on_turn_started(player: int, turn: int) -> void:
	_refresh_hand()
	events.push(_anim_turn.bind(player, turn))


func _on_ability_attached(player: int, uid: int, card_id: StringName) -> void:
	_refresh_hand()
	_stats["abilities"][player] += 1
	_log("%s «%s» → %s" % [_say(player, "Вы прикрепляете", "Соперник прикрепляет"), _card_name(card_id), _cname(uid)], Color(0.75, 0.6, 1.0))
	events.push(_anim_attached.bind(player, uid, card_id))


func _on_attach_window(player: int, _uid: int, _options: Array) -> void:
	events.push(_anim_set_pending.bind({"kind": "attach", "player": player}))


func _on_gate_thrown(player: int, slot: int, uid: int) -> void:
	_log("%s: ворота + бросок" % _say(player, "Вы", "Соперник"), UiTheme.GOLD)
	events.push(_anim_gate_thrown.bind(player, slot, uid))


func _on_gate_trap(slot: int, card_id: StringName, effect: StringName) -> void:
	_stats["traps"] += 1
	_log("ЛОВУШКА: %s" % _card_name(card_id), Color(1.0, 0.45, 0.35))
	events.push(_anim_trap.bind(slot, card_id, effect))


func _on_momentum_changed(player: int, value: int) -> void:
	events.push(_anim_momentum.bind(player, value))


func _on_final_round(player: int) -> void:
	if not MatchRules.author_bonuses(ctrl.get_view(HUMAN).ruleset):
		return
	_log("ФИНАЛЬНЫЙ БОЙ", Color(1.0, 0.45, 0.35))
	events.push(_anim_final_round.bind(player))


## Выбывшее существо вернулось в игру (в зону использованных): шарик на плашке снова горит.
func _on_creature_revived(uid: int) -> void:
	_log("%s возвращается в игру" % _cname(uid), Color(1.0, 0.95, 0.6))
	events.push(func() -> void:
		var p: int = _owner_of(uid)
		_alive[p] += 1
		_refresh_status()
		hud.revive_creature(p, int(_pip_idx.get(uid, -1)))
		SoundFx.i().play("power_up", -4.0)
		hud.screen_flash(Color(1.0, 0.95, 0.7, 0.3))
		await hud.banner("ВОЗВРАЩЕНИЕ", "%s снова в игре (зона использованных)" % _cname(uid), Color(1.0, 0.92, 0.55), 0.8))


## Метка на следующий бой: строка в ленте и вспышка у шара.
func _on_creature_marked(uid: int, card_id: StringName, mark: Dictionary) -> void:
	var txt: String = "сила ровно %d" % int(mark["fix"]) if mark.has("fix") else "%+d" % int(mark.get("delta", 0))
	_log("%s: %s в следующем бою («%s»)" % [_cname(uid), txt, _card_name(card_id)], Color(0.85, 0.75, 1.0))
	events.push(func() -> void:
		var b: CreatureBall = balls.get(uid)
		if b != null and is_instance_valid(b):
			b.ability_pulse()
			var good: bool = mark.has("fix") or int(mark.get("delta", 0)) > 0
			VisualUtil.ring_wave(world, b.global_position - Vector3(0, CreatureBall.RADIUS - 0.1, 0), Color(0.6, 1.0, 0.6) if good else Color(1.0, 0.35, 0.3), Arena.FIG_W * 0.5, 0.5))


## «Вихревая подмена»: прежний боец исчезает, новый появляется на его месте в бою.
func _on_fighter_swapped(old_uid: int, new_uid: int, slot: int) -> void:
	_log("Подмена: %s вместо %s" % [_cname(new_uid), _cname(old_uid)], Color(0.75, 0.6, 1.0))
	events.push(_anim_fighter_swapped.bind(old_uid, new_uid, slot))


func _anim_fighter_swapped(old_uid: int, new_uid: int, _slot: int) -> void:
	var ob: CreatureBall = balls.get(old_uid)
	var pos: Vector3 = ob.global_position if ob != null else Vector3.ZERO
	var facing: Vector3 = Vector3.ZERO
	if _battle_uids.size() == 2:
		var foe: int = _battle_uids[1] if _battle_uids[0] == old_uid else _battle_uids[0]
		var fb: CreatureBall = balls.get(foe)
		if fb != null:
			facing = fb.global_position
		_battle_uids[_battle_uids.find(old_uid)] = new_uid
	hud.flash("Вихревая подмена: %s врывается в бой" % _cname(new_uid))
	if ob != null:
		await _anim_remove_ball(old_uid)
	var nb: CreatureBall = balls.get(new_uid)
	if nb == null:
		nb = _spawn_ball(new_uid)
	nb.freeze_at(pos)
	if facing != Vector3.ZERO:
		nb.face_toward(facing)
	nb.open_animated()  # выход со стойкой и рёвом (CreatureAnim.appear)
	_cry(new_uid, "appear", 0.2)
	VisualUtil.ring_wave(world, pos - Vector3(0, CreatureBall.RADIUS - 0.1, 0), VisualUtil.attr_color(_creature_def(new_uid).attribute), Arena.FIG_W * 0.7, 0.55)
	_focus_labels(_battle_uids)
	await hud.wait_read(0.9)
	hud.clear_flash()


## «Сдвиг плит»: карты ворот меняются местами (узлы карт переезжают, существа остаются).
func _on_gates_swapped(a: int, b: int) -> void:
	_log("Сдвиг плит: ворота меняются местами", Color(0.75, 0.6, 1.0))
	events.push(func() -> void:
		var na: ArenaCardNode = card_nodes.get(a)
		var nb: ArenaCardNode = card_nodes.get(b)
		card_nodes.erase(a)
		card_nodes.erase(b)
		if na != null:
			card_nodes[b] = na
			na.slot = b
			na.create_tween().tween_property(na, "position", arena.slot_position(b), 0.45).set_trans(Tween.TRANS_QUAD)
		if nb != null:
			card_nodes[a] = nb
			nb.slot = a
			nb.create_tween().tween_property(nb, "position", arena.slot_position(a), 0.45).set_trans(Tween.TRANS_QUAD)
		cam.shake(0.4, 0.3)
		SoundFx.i().play("card_place")
		await _wait(0.55))


## Ворота сгорели без захвата (оба бойца выбыли).
func _on_gate_discarded(slot: int, _card_id: StringName) -> void:
	_log("Ворота сгорают", Color(1.0, 0.6, 0.4))
	events.push(func() -> void:
		var node: ArenaCardNode = card_nodes.get(slot)
		card_nodes.erase(slot)
		if node == null:
			return
		VisualUtil.burst(world, node.global_position + Vector3(0, 0.3, 0), Color(1.0, 0.5, 0.25), Arena.WORLD * 0.6)
		var tw := node.create_tween()
		tw.tween_property(node, "scale", Vector3(0.01, 0.01, 0.01), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		await tw.finished
		node.queue_free())


## Сыгранные способности вернулись в руку («Второе дыхание», карты камбэка).
func _on_abilities_recalled(player: int, card_ids: Array) -> void:
	_refresh_hand()
	var names: PackedStringArray = PackedStringArray()
	for id in card_ids:
		names.append(_card_name(StringName(id)))
	_log("%s в руку: %s" % [_say(player, "Карты возвращаются", "К сопернику возвращаются"), ", ".join(names)], Color(0.75, 0.6, 1.0))


## Перезарядка: карты, отдыхавшие один бой, снова в руке.
func _on_abilities_recharged(player: int, card_ids: Array) -> void:
	_refresh_hand()
	var names: PackedStringArray = PackedStringArray()
	for id in card_ids:
		names.append(_card_name(StringName(id)))
	_log("%s: %s" % [_say(player, "Перезарядка, снова в руке", "Перезарядка соперника"), ", ".join(names)], Color(0.6, 0.75, 1.0))


func _on_game_over(winner: int, reason: StringName) -> void:
	# Persist the controller result immediately, before the presentation queue drains.
	if tournament != null:
		_accept_tournament_result()
	ability_panel.set_dock_visible(false)
	if is_instance_valid(setup_panel): setup_panel.set_dock_visible(false)
	events.push(_anim_game_over.bind(winner, reason))


# ---------------------------------------------------------------- анимации (выполняются EventPlayer)

var _alive: Array[int] = [3, 3]
var _battle_uids: Array[int] = []  # [атакующий, защитник] текущего боя (для эффектов способностей)  # живые существа по ходу анимаций (для строки статуса)


func _refresh_status() -> void:
	hud.set_status(_turn, _active, _alive[0], _alive[1])
	hud.set_captures(captures[0], captures[1])


func _anim_phase(_phase: int, active_player: int) -> void:
	hud.set_phase(_phase)
	_active = active_player
	_refresh_status()


func _anim_turn(player: int, turn: int) -> void:
	for side in fighters.size(): fighters[side].active_turn = side == player
	_active = player
	_turn = turn
	_refresh_status()
	if turn > 0:
		SoundFx.i().play("turn_yours" if player == HUMAN else "turn_opponent", -5.0)


func _anim_set_pending(p: Dictionary) -> void:
	_pending = p


func _card_name(id: StringName) -> String:
	var c: CardDef = CardDB.card(id)
	return c.display_name if c != null else String(id)


## Карта прикреплена к существу вне боя: вспышка у шара, карта соперника показывается обоим.
func _anim_attached(player: int, uid: int, card_id: StringName) -> void:
	await director.ability_action(player,card_id,uid)
	cam.overview()
	_refresh_hand()
	ability_panel.show_played(card_id, player != HUMAN)
	var b: CreatureBall = balls.get(uid)
	if b != null:
		b.ability_pulse()
		var c: Color = VisualUtil.attr_color(_creature_def(uid).attribute).lightened(0.3)
		VisualUtil.ring_wave(world, b.global_position - Vector3(0, CreatureBall.RADIUS - 0.1, 0), c, Arena.FIG_W * 0.6, 0.6)
	hud.flash("%s «%s»" % [_say(player, "Вы прикрепляете", "Соперник прикрепляет"), _card_name(card_id)])
	await hud.wait_read(1.0)
	hud.clear_flash()
	if player == HUMAN and ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING and _active_ball != null and not director.flying:
		_show_pre_throw()


func _anim_gate_thrown(player: int, _slot: int, uid: int) -> void:
	SoundFx.i().play("card_select")
	hud.set_hint("Ворота + бросок: %s летит на новую карту" % _cname(uid))
	await hud.banner("ВОРОТА + БРОСОК", "%s: карта и бросок за один ход" % _say(player, "Вы", "Соперник"), UiTheme.GOLD, 0.55)


func _anim_trap(slot: int, card_id: StringName, effect: StringName) -> void:
	var sub: String = "Ловушка сработала"
	match effect:
		&"mute":
			sub = "Сопернику владельца способности запрещены"
		&"mirror":
			sub = "Силы бойцов меняются местами"
		&"limit":
			sub = "Кто сильнее 400 — проигрывает"
		&"clash":
			sub = "Оба бойца выбывают"
	SoundFx.i().play("gate_trap", -2.0)
	cam.impact(arena.slot_position(slot) + Vector3(0, Arena.FIG_H * 0.2, 0))
	cam.shake(0.7, 0.4)
	hud.screen_flash(Color(1.0, 0.3, 0.2, 0.35))
	await hud.banner("ЛОВУШКА!  %s" % _card_name(card_id).to_upper(), sub, Color(1.0, 0.35, 0.3), 0.9)
	cam.battle_wide()


func _anim_momentum(player: int, value: int) -> void:
	if not MatchRules.author_bonuses(ctrl.get_view(HUMAN).ruleset):
		hud.set_momentum(player, 0)
		return
	hud.set_momentum(player, value)
	if value > 0:
		SoundFx.i().play("power_up", -8.0)
		hud.log_event("%s: натиск +%d к силе" % [_say(player, "Вы", "Соперник"), value * PowerCalc.MOMENTUM_STEP], Color(1.0, 0.7, 0.3))


func _anim_final_round(_player: int) -> void:
	if not MatchRules.author_bonuses(ctrl.get_view(HUMAN).ruleset):
		return
	hud.set_final_round(true)
	SoundFx.i().play("battle_start", 0.0)
	cam.shake(0.8, 0.5)
	hud.screen_flash(Color(1.0, 0.5, 0.3, 0.3))
	await hud.banner("ФИНАЛЬНЫЙ БОЙ", "Остались последние существа: преимущество стихии ×2", Color(1.0, 0.5, 0.25), 1.2)


func _anim_card_placed(player: int, slot: int) -> void:
	await director.card_placed(player, slot)


func _spawn_ball(uid: int) -> CreatureBall:
	var b: CreatureBall = _prepared_balls.get(uid)
	if b != null:
		_prepared_balls.erase(uid)
		b.process_mode = Node.PROCESS_MODE_INHERIT
		b.freeze_at(_start_pos(_owner_of(uid)))
		b.close_up()
		b._shape.disabled = false
		b.slot = -1
		b._figure.rotation = Vector3.ZERO
		b.visible = true
	else:
		# Стенды и восстановление неполной сцены могут создавать существо без подготовки матча.
		b = BALL_SCENE.instantiate() as CreatureBall
		world.add_child(b)
		b.setup(_creature_def(uid), uid)
	balls[uid] = b
	return b


func _start_pos(player: int) -> Vector3:
	return Vector3(0.0, BALL_Y, THROW_Z if player == HUMAN else -THROW_Z)


func _anim_selected(player: int, uid: int, recalled: bool) -> void:
	var b: CreatureBall = balls.get(uid)
	if b == null:
		b = _spawn_ball(uid)
	elif recalled:
		b.unfreeze()
		b.close_up()
		b.slot = -1
	b.freeze_at(_start_pos(player))
	cam.overview()
	_focus_labels([])
	_active_ball = b
	_pending = {"kind": "launch", "player": player, "uid": uid}
	await _wait(0.25)


## Существо уходит в зону использованных: промах, после боя или со своих засчитанных ворот.
func _anim_returned(uid: int, reason: StringName) -> void:
	match reason:
		&"miss":
			SoundFx.i().play("miss", -2.0)
			hud.set_hint("Промах: %s уходит в зону использованных" % _cname(uid))
		&"gate_won":
			hud.set_hint("Свои ворота: карта засчитана")
		&"lost":
			await _anim_remove_ball(uid, true)
			return
	cam.overview()
	_focus_labels([])
	await _anim_remove_ball(uid)


## Попадание на свои ворота: существо переходит на другие ворота.
func _anim_relocated(uid: int, _from: int, to: int) -> void:
	var b: CreatureBall = balls.get(uid)
	hud.set_hint("%s остаётся на воротах" % _cname(uid) if _from == to else "%s переходит на другие ворота" % _cname(uid))
	if b == null:
		return
	var target := arena.slot_position(to) + Vector3(0.0, BALL_Y + 0.02, 0.0)
	b.freeze_at(b.global_position)
	cam.overview()
	var tw := create_tween() # Владелец — матч, а не сохраняемый каталогом шар.
	tw.tween_property(b, "global_position", target + Vector3(0, Arena.FIG_W * 0.4, 0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "global_position", target, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	b.freeze_at(target)


func _anim_refilled(player: int) -> void:
	hud.coach("used", "Зона использованных: существа после промаха или боя отдыхают. Когда бросать некого, они все возвращаются в руку.")
	hud.flash("Существа вернулись из зоны использованных" if player == HUMAN else "У соперника вернулись существа")
	await hud.wait_read(1.4)
	hud.clear_flash()


func _anim_remove_ball(uid: int, eliminated: bool = false) -> void:
	var b: CreatureBall = balls.get(uid)
	if b == null:
		return
	SoundFx.i().play("eliminated" if eliminated else "vanish", -2.0 if eliminated else -6.0)
	if eliminated:
		_alive[_owner_of(uid)] -= 1
		_refresh_status()
		VisualUtil.burst(world, b.global_position + Vector3(0, Arena.FIG_H * 0.2, 0), _creature_def(uid).color, Arena.WORLD * 0.8)
	balls.erase(uid)
	# Актёр остаётся учтённым и во время vanish: выход должен вернуть и его.
	_prepared_balls[uid] = b
	if b == _active_ball:
		_active_ball = null
	await b.vanish(eliminated)
	b.visible = false
	b.process_mode = Node.PROCESS_MODE_DISABLED


func _anim_stood(uid: int, slot: int) -> void:
	var b: CreatureBall = balls.get(uid)
	if b == null:
		return
	b.slot = slot
	hud.set_hint("%s встаёт на карту" % _cname(uid))
	# короткий наезд на фактическую точку остановки, потом кат на облёт
	if cam.mode == CameraRig.Mode.STATIC and not cam.is_overview():
		await _wait(0.4)
	var facing := Vector3(0.0, 0.0, -1.0 if _owner_of(uid) == HUMAN else 1.0)
	b.hold_landing_pose()
	b.face_toward(b.global_position + facing)
	var orbit_t: float = cam.reveal_orbit(b.global_position - Vector3(0, BALL_Y, 0), b.figure_height(), facing, b.figure_size())
	_focus_labels([uid])
	SoundFx.i().play("ball_land", -3.0)
	VisualUtil.ring_wave(world, Vector3(b.global_position.x, .08, b.global_position.z), VisualUtil.attr_color(_creature_def(uid).attribute), Arena.FIG_W * 0.7, 0.55)
	SoundFx.i().play_later("capsule_open", 0.05)
	_cry(uid, "appear", 0.4)
	b.open_animated()  # выход со стойкой и рёвом (CreatureAnim.appear), пик — к тряске камеры
	get_tree().create_timer(0.8).timeout.connect(func() -> void: cam.shake(0.3, 0.2))
	await _wait(orbit_t)
	# Плавный возврат после раскрытия.
	cam.overview()
	await _wait(0.3)


func _anim_battle_started(slot: int, attacker_uid: int, defender_uid: int, powers: Array = [], momentum: Array = [0, 0]) -> void:
	await director.battle_started(slot, attacker_uid, defender_uid, powers, momentum)


func _anim_card_revealed(slot: int, card_id: StringName, owner: int = -1) -> void:
	await director.fighter_action(owner,"gate")
	cam.battle_wide(true)
	var node: ArenaCardNode = card_nodes.get(slot)
	if node != null:
		node.reveal(CardDB.card(card_id))
		SoundFx.i().play("card_flip")
	await _wait(1.0)
	var preview := ctrl.get_battle_preview()
	if preview != null:
		battle_hud.set_powers(preview.powers)


func _anim_ability_msg(player: int, card_id: StringName, cancelled: bool, powers: Array = []) -> void:
	if not cancelled: await director.ability_action(player,card_id)
	var c: CardDef = CardDB.card(card_id)
	var cname: String = c.display_name if c != null else str(card_id)
	if cancelled: SoundFx.i().ability(c,true)
	if not cancelled:
		ability_panel.show_played(card_id, player != HUMAN)
		if c != null and CardEffects.is_fusion(c):
			_anim_ability_cam(player)
		else:
			cam.battle_wide()
		await _ability_fx(player, c)
	else:
		# Срыв карты виден на самом бойце, даже без изменения силы.
		for uid in _battle_uids:
			if _owner_of(uid) == player:
				var b: CreatureBall = balls.get(uid)
				if b != null:
					b.take_hit(Color(0.65, 0.7, 0.85))
					VisualUtil.ring_wave(world, b.global_position, Color(0.6, 0.68, 0.8), Arena.FIG_W * 0.6, 0.45)
		cam.shake(0.16, 0.18)
	await _wait(0.22)
	if powers.size() == 2:
		battle_hud.set_powers(powers)
	if cancelled:
		hud.flash("%s «%s» отменена" % ["Ваша карта" if player == HUMAN else "Карта соперника", cname])
	else:
		hud.flash(("Вы играете «%s»" if player == HUMAN else "Соперник играет «%s»") % cname)
	await hud.wait_read(0.75)
	hud.clear_flash()
	if not cancelled and _battle_uids.size() == 2:
		cam.battle_wide()


## Кат на автора способности с рывком камеры.
func _anim_ability_cam(player: int) -> void:
	if _battle_uids.size() != 2:
		return
	var mine: int = _battle_uids[0] if _owner_of(_battle_uids[0]) == player else _battle_uids[1]
	var foe: int = _battle_uids[1] if mine == _battle_uids[0] else _battle_uids[0]
	var mb: CreatureBall = balls.get(mine)
	var fb: CreatureBall = balls.get(foe)
	if mb == null:
		return
	var facing: Vector3 = (fb.global_position - mb.global_position) if fb != null else Vector3(0, 0, 1)
	cam.ability_jerk(mb.global_position - Vector3(0, CreatureBall.RADIUS, 0), facing, mb.figure_height(), mb.figure_size())


func _anim_battle_resolved(result: BattleResult) -> void:
	if fighters.size() == 2 and result.winner_uid >= 0:
		var winning_side := _owner_of(result.winner_uid)
		fighters[winning_side].play_motion("victory")
		fighters[1-winning_side].play_motion("defeat")
	await director.battle_resolved(result)


func _anim_no_winner(result: BattleResult) -> void:
	await director.no_winner(result)


func _anim_captured(player: int, slot: int) -> void:
	var node: ArenaCardNode = card_nodes.get(slot)
	cam.overview()
	_focus_labels([])
	captures[player] += 1
	_refresh_status()
	if node == null:
		return
	card_nodes.erase(slot)
	SoundFx.i().play("card_capture")
	node.tray_offset = float(captures[player] - 1) * 1.0 * Arena.WORLD
	await node.play_capture(player)


func _reason_text(reason: StringName) -> String:
	match reason:
		&"knockout":
			return "Все три существа проигравшего выбиты"
		&"turn_limit":
			return "Лимит ходов (%d): по числу оставшихся существ" % MatchController.MAX_TURNS
		&"stalemate", &"no_gates":
			return "Бросать больше некому: по числу оставшихся существ"
	return String(reason)


func _anim_game_over(winner: int, reason: StringName) -> void:
	if fighters.size() == 2:
		for side in 2:
			if winner < 0: fighters[side].reset_motion()
			else: fighters[side].play_motion("victory" if side == winner else "defeat")
	ctrl.save_debug_trace()
	_game_over = true
	_pending = {}
	hud.hide_creatures()
	setup_panel.hide_panel()
	ability_panel.hide_panel()
	SoundFx.i().stop_music(1.0)
	SoundFx.i().play("victory" if winner == HUMAN else "defeat")
	_stats["alive"] = [_alive[0], _alive[1]]
	_stats["captures"] = [captures[0], captures[1]]
	_stats["turns"] = ctrl.get_turn()
	var reason_text := _reason_text(reason)
	if tournament != null:
		var error := _accept_tournament_result()
		if error != OK:
			reason_text += "\nНе удалось сохранить результат. «К турниру» повторит сохранение."
		else:
			reason_text += "\nРезультат турнира сохранён."
		game_over_ui.set_restart_text("К турниру")
	game_over_ui.show_result(winner, reason_text, _stats)


# ---------------------------------------------------------------- физика / ввод

## Слоты с лежащими картами ворот (цели броска).
func _gate_slots() -> Array:
	var out: Array = []
	var view: MatchState = ctrl.get_view(HUMAN)
	for i in range(view.slots.size()):
		if (view.slots[i] as SlotState).has_card:
			out.append(i)
	return out


func _report(uid: int, slot: int) -> void:
	if _game_over:
		return
	ctrl.report_landing(uid, slot)


# ---------------------------------------------------------------- ответы игроков (только после drained)

func _pump() -> void:
	if _leaving_duel or _game_over or events.is_busy() or _pending.is_empty():
		return
	var phase: int = ctrl.get_phase()
	if phase == MatchController.Phase.GAME_OVER:
		return
	var p: Dictionary = _pending
	_pending = {}
	var player: int = int(p["player"])
	var want: int = -1
	match str(p["kind"]):
		"setup":
			want = MatchController.Phase.SETUP
		"throw":
			want = MatchController.Phase.AWAIT_THROW
		"launch":
			want = MatchController.Phase.AWAIT_LANDING
		"ability":
			want = MatchController.Phase.ABILITY_WINDOW
		"attach":
			want = MatchController.Phase.AFTER_LANDING
	if phase != want or (str(p["kind"]) != "launch" and ctrl.get_active_player() != player):
		push_warning("Пропущен запрос %s: фаза %d, активный игрок %d" % [str(p["kind"]), phase, ctrl.get_active_player()])
		return
	match str(p["kind"]):
		"setup":
			_do_setup(player)
		"throw":
			_do_throw_select(player)
		"launch":
			_do_launch(player)
			if player == HUMAN:
				_show_pre_throw()
		"ability":
			_do_ability(player)
		"attach":
			_do_attach(player)


func _do_setup(player: int) -> void:
	if player == HUMAN:
		var cards: Array = []
		for cid in ctrl.get_view(HUMAN).players[HUMAN].arena_hand:
			var c: CardDef = CardDB.card(cid)
			cards.append({"id": c.id, "name": c.display_name, "text": c.text})
		var legal: Array[int] = ctrl.legal_setup_slots()
		arena.set_highlight(legal, true)
		hud.set_hint("Карта ворот на поле? Положите карту или пропустите" if ctrl.can_skip_gate() else "Положите карту ворот на поле")
		setup_panel.begin(cards, legal, ctrl.can_skip_gate(), not _throwable_entries().is_empty())
		hud.coach("gate", "Карта ворот — поле боя: выбери карту и место (подсвечено). Соперник не видит её до боя — там могут быть ловушки. «Ворота + бросок» — положить карту и сразу бросить на неё существо.")
	else:
		hud.set_hint("Соперник выбирает карту ворот...")
		var choice: Dictionary = ai.choose_setup(ctrl.get_view(AI_PLAYER), ctrl.legal_setup_slots(), ctrl.can_skip_gate())
		var err: int = OK
		if choice.is_empty():
			err = ctrl.skip_gate(AI_PLAYER)
		elif int(choice.get("throw_uid", -1)) >= 0:
			# «ворота + бросок»: цель броска — только что положенная карта
			_ai_target_slot = int(choice["slot"])
			err = ctrl.throw_with_gate(AI_PLAYER, choice["card_id"], int(choice["slot"]), int(choice["throw_uid"]))
		else:
			err = ctrl.place_arena_card(AI_PLAYER, choice["card_id"], int(choice["slot"]))
		if err != OK:
			ctrl.save_debug_trace("user://replays/last_error.json")
			push_error("ИИ: выкладка ворот вернула ошибку %d" % err)


func _do_throw_select(player: int) -> void:
	if player == HUMAN:
		var view: MatchState = ctrl.get_view(HUMAN)
		var entries: Array = []
		for u in ctrl.legal_creatures(HUMAN):
			var d: CreatureDef = _creature_def(u)
			var note := "с карты" if view.creature(u).slot >= 0 else ""
			entries.append({"uid": u, "def": d, "text": "Существо #%d" % u, "note": note})
		hud.set_hint("Ваш бросок: выберите шар-существо")
		hud.show_creatures(entries)
	else:
		hud.set_hint("Соперник выбирает существо…")
		var c: Dictionary = ai.choose_throw(ctrl.get_view(AI_PLAYER))
		_ai_target_slot = int(c["target_slot"])
		var err: int = ctrl.select_creature(AI_PLAYER, int(c["uid"]))
		if err != OK:
			ctrl.save_debug_trace("user://replays/last_error.json")
			push_error("ИИ: select_creature вернул ошибку %d" % err)


func _do_launch(player: int) -> void:
	var uid: int = ctrl.get_selected_uid()
	var ball: CreatureBall = balls.get(uid)
	if ball == null:
		push_error("Нет шара для uid %d" % uid)
		return
	_active_ball = ball
	_focus_labels([])
	cam.overview()
	if ctrl.get_throw_gate_slot() >= 0:
		await director.launch_to(ctrl.get_throw_gate_slot())
	elif player == HUMAN:
		hud.set_hint("РАЗМЕЩЕНИЕ · выберите подсвеченные ворота для сферы")
		hud.coach("throw", "Выбери карту ворот щелчком по полю. Сфера сама долетит до выбранной карты. Способность можно прикрепить до выбора цели.")
		arena.set_highlight(_gate_slots(), true)
	else:
		hud.set_hint("Соперник выбирает цель…")
		await _wait(0.45)
		var target: int = _ai_target_slot
		if not _gate_slots().has(target):
			target = int(_gate_slots()[0])
		await director.launch_to(target)


func _on_slot_picked(slot: int) -> void:
	if events.is_busy() or director.flying:
		return
	if ctrl.get_phase() == MatchController.Phase.SETUP and ctrl.get_active_player() == HUMAN:
		setup_panel.pick_slot(slot)
	elif ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING and ctrl.get_active_player() == HUMAN:
		await director.launch_to(slot)


func _do_ability(player: int) -> void:
	var preview: BattleResult = ctrl.get_battle_preview()
	if preview == null:
		push_error("Окно способностей без предпросмотра боя")
		return
	battle_hud.set_chain(preview.plays, preview.passed, 0 if _owner_of(preview.attacker_uid) == player else 1)
	if player == HUMAN:
		var entries: Array = []
		for cid in ctrl.legal_abilities(HUMAN):
			var c: CardDef = CardDB.card(cid)
			entries.append({"id": c.id, "name": c.display_name, "text": c.text})
		var hdr := "Ваш ответ: способность или пас"
		var fusion_only := not entries.is_empty()
		for e in entries:
			if not CardEffects.is_fusion(CardDB.card(e["id"])):
				fusion_only = false
		if fusion_only:
			hdr = "Ваш ответ: слияние или пас"
		var my_side: int = 0 if _owner_of(preview.attacker_uid) == HUMAN else 1
		var note := "Два паса подряд завершат бой. На карту соперника можно ответить."
		if preview.passed.size() == 2 and preview.passed[1 - my_side]:
			note = "Соперник спасовал. Ваш пас завершит бой."
		if not ctrl.state.slots[preview.slot].revealed:
			note = ("Ворота закрыты. " if ctrl.can_reveal_gate(HUMAN) else "Закрытые ворота соперника. ") + note
		hud.set_hint("Слияние?" if fusion_only else "Ваша способность?")
		hud.coach("ability", "Бой! Закрытые ворота откроются, когда их владелец нажмёт «Открыть мои ворота». Карты играются по очереди, до 3 на бой — счётчик на плашке. Светящиеся — доступны. «Пас» — пропуск хода: на карту соперника можно ответить, бой решается после двух пасов подряд. Сыгранные карты отдыхают 2 боя и возвращаются в руку.")
		ability_panel.show_options(entries, hdr, {"moment": &"battle", "used": MatchController.MAX_BATTLE_ABILITIES - ctrl.abilities_left(HUMAN),
			"can_open_gate": ctrl.can_reveal_gate(HUMAN), "pass_text": "Пас", "pass_tip": "Пропустить ход обмена. Спасуют оба подряд — бой решится.", "note": note})
	else:
		hud.set_hint("Соперник думает...")
		if ctrl.can_reveal_gate(AI_PLAYER) and ai.should_open_gate(ctrl.get_view(AI_PLAYER), preview):
			ctrl.reveal_gate(AI_PLAYER)
			return
		var cid: StringName = ai.choose_ability(ctrl.get_view(AI_PLAYER), preview, ctrl.legal_abilities(AI_PLAYER))
		var err: int = OK
		if cid == &"":
			err = ctrl.pass_ability(AI_PLAYER)
		else:
			err = ctrl.play_ability(AI_PLAYER, cid)
		if err != OK:
			ctrl.save_debug_trace("user://replays/last_error.json")
			push_error("ИИ: ошибка способности %d" % err)


## Окно «после приземления»: прикрепить способность к существу, что встало на пустые ворота, или завершить ход.
func _do_attach(player: int) -> void:
	var uid: int = ctrl.get_landed_uid()
	if player == HUMAN:
		var entries: Array = []
		for cid in ctrl.legal_abilities(HUMAN):
			var c: CardDef = CardDB.card(cid)
			entries.append({"id": c.id, "name": c.display_name, "text": c.text})
		hud.set_hint("%s на воротах: прикрепить способность?" % _cname(uid))
		hud.coach("attach", "Существо встало на пустые ворота. Можно прикрепить карту: она сработает в его следующем бою (видна сопернику). Или завершить ход без неё.")
		ability_panel.show_options(entries, "Прикрепить способность к «%s»?" % _cname(uid), {"moment": &"after_landing",
			"used": MatchController.MAX_BATTLE_ABILITIES - ctrl.abilities_left(HUMAN), "pass_text": "Завершить ход",
			"pass_tip": "Не прикреплять карту — ход переходит сопернику.",
			"note": "Прикреплённая карта входит в лимит 3 карт на бой."})
	else:
		hud.set_hint("Соперник думает...")
		var cid: StringName = ai.choose_attach(ctrl.get_view(AI_PLAYER), uid, ctrl.legal_abilities(AI_PLAYER))
		var err: int = OK
		if cid == &"":
			err = ctrl.pass_ability(AI_PLAYER)
		else:
			err = ctrl.play_ability(AI_PLAYER, cid)
		if err != OK:
			ctrl.save_debug_trace("user://replays/last_error.json")
			push_error("ИИ: ошибка прикрепления %d" % err)


## До броска: рука приподнята, играбельные карты светятся; карта прикрепится к выбранному существу.
func _show_pre_throw() -> void:
	if _game_over or director.flying or ctrl.get_phase() != MatchController.Phase.AWAIT_LANDING:
		return
	var legal: Array[StringName] = ctrl.legal_abilities(HUMAN)
	if legal.is_empty():
		return
	var entries: Array = []
	for cid in legal:
		var c: CardDef = CardDB.card(cid)
		entries.append({"id": c.id, "name": c.display_name, "text": c.text})
	var uid: int = ctrl.get_selected_uid()
	hud.coach("prethrow", "Перед броском можно прикрепить способность к шару: она сработает в его бое. Это необязательно — просто выбери ворота.")
	ability_panel.show_options(entries, "До броска: прикрепить карту к «%s» (необязательно)" % _cname(uid), {"moment": &"pre_throw",
		"used": MatchController.MAX_BATTLE_ABILITIES - ctrl.abilities_left(HUMAN), "note": ""})


## Существа, которых можно бросить в фазе выкладки (в руке, не на воротах и не в зоне использованных).
func _throwable_entries() -> Array:
	var view: MatchState = ctrl.get_view(HUMAN)
	var entries: Array = []
	for u in view.players[HUMAN].creature_uids:
		var cs: CreatureState = view.creature(u)
		if cs.alive and cs.slot < 0 and not cs.used:
			entries.append({"uid": u, "def": _creature_def(u), "text": "Существо #%d" % u, "note": ""})
	return entries


func _on_setup_placed_throw(card_id: StringName, slot: int) -> void:
	var entries: Array = _throwable_entries()
	if entries.is_empty():
		_on_setup_placed(card_id, slot)
		return
	_gate_pick = {"card": card_id, "slot": slot}
	setup_panel.hide_panel()
	arena.set_highlight([slot])
	hud.set_hint("Ворота + бросок: кого бросить на новую карту?")
	hud.show_creatures(entries, "Кого бросить на новые ворота?", true)


func _on_gate_throw_cancelled() -> void:
	_gate_pick = {}
	hud.hide_creatures()
	_do_setup(HUMAN)


func _on_creature_chosen(uid: int) -> void:
	hud.hide_creatures()
	if not _gate_pick.is_empty():
		var pick: Dictionary = _gate_pick
		_gate_pick = {}
		arena.set_highlight([])
		var gerr: int = ctrl.throw_with_gate(HUMAN, pick["card"], int(pick["slot"]), uid)
		if gerr != OK:
			ctrl.save_debug_trace("user://replays/last_error.json")
			hud.reject_action("Не получилось: ворота + бросок")
			_do_setup(HUMAN)
		return
	var err: int = ctrl.select_creature(HUMAN, uid)
	if err != OK:
		ctrl.save_debug_trace("user://replays/last_error.json")
		hud.reject_action("Нельзя выбрать это существо")
		_pending = {"kind": "throw", "player": HUMAN}
		_pump()


func _on_setup_skipped() -> void:
	if ctrl.skip_gate(HUMAN) != OK:
		hud.reject_action("Ворот на поле нет: карту нужно положить")
		_pending = {"kind": "setup", "player": HUMAN}
		_pump()
		return
	setup_panel.hide_panel()
	arena.set_highlight([])


func _on_setup_placed(card_id: StringName, slot: int) -> void:
	var err: int = ctrl.place_arena_card(HUMAN, card_id, slot)
	if err != OK:
		ctrl.save_debug_trace("user://replays/last_error.json")
		hud.reject_action("Нельзя положить карту в этот слот")
		_pending = {"kind": "setup", "player": HUMAN}
		_pump()
		return
	setup_panel.hide_panel()
	arena.set_highlight([])


func _on_ability_chosen(card_id: StringName) -> void:
	var moment: StringName = ctrl.get_ability_moment()
	ability_panel.hide_panel()
	var err: int = ctrl.play_ability(HUMAN, card_id)
	if err != OK:
		ctrl.save_debug_trace("user://replays/last_error.json")
		hud.reject_action(ctrl.ability_unavailable_reason(HUMAN, card_id))
		match moment:
			&"after_landing":
				_pending = {"kind": "attach", "player": HUMAN}
			&"pre_throw":
				_show_pre_throw()
				return
			_:
				_pending = {"kind": "ability", "player": HUMAN}
		_pump()


func _on_gate_open_requested() -> void:
	if events.is_busy():
		return
	ability_panel.hide_panel()
	if ctrl.reveal_gate(HUMAN) != OK:
		hud.reject_action("Свои ворота можно открыть только в свой ответ во время боя")
		_pending = {"kind": "ability", "player": HUMAN}
		_pump()


func _on_ability_passed() -> void:
	ability_panel.hide_panel()
	ctrl.pass_ability(HUMAN)


func _on_card_drawn(player: int, card_id: StringName) -> void:
	events.push(func() -> void:
		_refresh_hand()
		SoundFx.i().play("card_select", -6.0)
		hud.draw_notice(_card_name(card_id) if player == HUMAN else "Соперник получает карту")
		await _wait(0.25))
	if player == HUMAN:
		_log("Получена карта «%s»" % CardDB.card(card_id).display_name, UiTheme.GOLD)
	else:
		_log("Соперник получает карту", UiTheme.TEXT_DIM)


func _apply_arena_environment(index: int) -> void:
	var data := Locations.definition(index)
	var high := GraphicsSettings.current() == GraphicsSettings.Level.HIGH
	_arena_sky.set_shader_parameter("sky_zenith", Color(data.zenith).linear_to_srgb())
	_arena_sky.set_shader_parameter("sky_horizon", Color(data.horizon).linear_to_srgb())
	_arena_sky.set_shader_parameter("sky_mist", Color(data.mist).linear_to_srgb())
	_env.fog_light_color = data.fog
	_env.ambient_light_color = data.ambient
	_sun.light_color = data.sun
	_sun.light_energy = .22 if index == 0 else data.sun_energy
	# Мягкий свет сохраняет цвет/форму фигур в тёмном зале, не заливая всю архитектуру.
	_fill.light_cull_mask = (CreatureBall.FIGURE_LIGHT_LAYER | (1 << 18) | (1 << 19)) if index == 0 else 1
	_fill.light_energy = (.76 if high else .68) if index == 0 else .9
	_env.ambient_light_energy = (.22 if GraphicsSettings.current() == GraphicsSettings.Level.LOW else .15) if index == 0 else .75
	_env.fog_density = .0009 if index == 0 else .0025
	_env.fog_sky_affect = .8 if index == 0 else .25
	_env.volumetric_fog_enabled = false
	_fill.light_color = Color(data.ambient).lightened(.15)
	_sun.rotation_degrees = Vector3(-38, -105, 0) if index == 2 else Vector3(-52, -30, 0)


func _preview_arena_location(index: int, save_choice: bool = true) -> void:
	if ctrl != null:
		return
	if save_choice:
		Locations.choose(index)
	if arena.location_id != index:
		if GameLoading.i().ready_to_play:
			GameLoading.i().return_arena(arena)
			arena = GameLoading.i().take_arena(index)
			arena.reparent(world, false)
		else:
			world.remove_child(arena)
			arena.queue_free()
			arena = ARENA_SCENE.instantiate() as Arena
			arena.location_id = index
			world.add_child(arena)
		# После замены арены переподключаем ввод при создании логики матча.
		apply_graphics()
	_apply_arena_environment(index)
	cam.location_preview_view(index == 0)
	hud.visible = false


## Entry is explicit because Boot constructs this scene before the player opens a mode.
func enter_requested_mode() -> void:
	var mode := TournamentSession.entry_mode
	TournamentSession.entry_mode = ""
	_campaign_registration = mode == "campaign_new"
	if mode in ["new", "campaign_new"]:
		_tournament_registration = true
		team_menu._go_btn.text = "Зарегистрироваться"
		team_menu._go_btn.tooltip_text = "Команда, колода и сложность закрепятся на всю кампанию" if _campaign_registration else "Команда, колода и сложность закрепятся на весь турнир"
		team_menu._arena_btn.disabled = true
		team_menu._arena_btn.text = "Арены по этапам"
		team_menu._arena_btn.tooltip_text = "Группы — Каньон; полуфиналы — Гавань; финал — Святилище"
		for label in team_menu.find_children("*", "Label", true, false):
			if label.text == "Соперник": label.text = "Сложность кампании" if _campaign_registration else "Сложность турнира"
			elif label.text.contains("Enter — в бой"): label.text = "1–3 шаги · ←/→ · Enter — регистрация · R — случайная"
		var title := team_menu.find_children("*", "Label", true, false)
		if not title.is_empty(): title[0].text = "Кампания · регистрация" if _campaign_registration else "Турнир · регистрация"
		var back := Button.new()
		back.text = "В меню"
		back.pressed.connect(_exit_tournament)
		team_menu._graphics_button.get_parent().add_child(back)
		return
	if mode not in ["continue", "campaign_continue"]: return
	var loaded := Campaign.load_file() if mode == "campaign_continue" else Tournament.load_file()
	if not String(loaded.error).is_empty():
		team_menu.hide()
		_show_tournament_error(String(loaded.error))
		return
	if mode == "campaign_continue":
		campaign = loaded.campaign
		tournament = campaign.cup
	else:
		tournament = loaded.tournament
	_show_tournament()


func _register_tournament(creatures: Array[StringName], gates: Array[StringName], abilities: Array[StringName]) -> void:
	team_menu.show()
	var error := CardDB.deck_error(creatures, gates, abilities)
	if not error.is_empty():
		team_menu._error.text = error
		return
	var save_path := Campaign.SAVE_PATH if _campaign_registration else Tournament.SAVE_PATH
	var invalid_save := FileAccess.file_exists(save_path) and not String((Campaign.load_file() if _campaign_registration else Tournament.load_file()).error).is_empty()
	var confirm := ConfirmationDialog.new()
	confirm.title = "Кампания · три кубка" if _campaign_registration else "Регистрация на турнир"
	confirm.dialog_text = "8 участников · 2 группы · полуфиналы и финал.\nКоманда, 3 карты ворот, 3 способности и сложность «%s»\nзакрепятся до конца турнира. Арены выбираются этапом.\nНезавершённый матч повторяется с начала с тем же начальным раскладом." % AIPlayer.difficulty_name(TeamMenu.difficulty)
	if _campaign_registration:
		confirm.dialog_text = "Три последовательных кубка: Каньон → Гавань → Стихии.\nТе же семь соперников; каждый кубок — группы и плей-офф.\nСледующий кубок открывается после завершения текущего, независимо от места.\nКоманда и сложность закрепятся на кампанию; соперники помнят только завершённые встречи с вами.\nСкрытого усиления характеристик и карт нет. Старый отдельный турнир сохранится."
	if invalid_save:
		confirm.dialog_text += "\nПрежнее сохранение не читается: оно останется отдельной резервной копией."
	elif FileAccess.file_exists(save_path):
		confirm.dialog_text += "\nПредыдущее активное сохранение будет заменено. История останется."
	confirm.ok_button_text = "Начать кампанию" if _campaign_registration else "Начать турнир"
	confirm.cancel_button_text = "Назад"
	ui_layer.add_child(confirm)
	confirm.confirmed.connect(func() -> void:
		if invalid_save and (Campaign.archive_invalid() if _campaign_registration else Tournament.archive_invalid()) != OK:
			team_menu._error.text = "Не удалось сохранить резервную копию прежнего турнира"
			confirm.queue_free()
			return
		var profile := PlayerProfile.new()
		profile.load_from()
		if _campaign_registration:
			campaign = Campaign.create(CardDB.build_deck(creatures, gates, abilities), TeamMenu.difficulty, (int(rng.randi()) & 0x7fffffff), profile.value.name)
			tournament = campaign.cup if campaign != null else null
		else:
			tournament = Tournament.create(CardDB.build_deck(creatures, gates, abilities), TeamMenu.difficulty, (int(rng.randi()) & 0x7fffffff), profile.value.name)
		if tournament == null:
			team_menu._error.text = "Не удалось сохранить: " + (Campaign.creation_error if _campaign_registration else Tournament.creation_error)
		else:
			_tournament_registration = false
			_show_tournament()
		confirm.queue_free())
	confirm.canceled.connect(confirm.queue_free)
	confirm.popup_centered()


func _show_tournament_error(message: String) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ui_layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var label := VisualUtil.label(message, 20)
	label.custom_minimum_size.x = 580
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var back := Button.new()
	back.text = "В главное меню"
	back.pressed.connect(_exit_tournament)
	box.add_child(back)
	panel.reset_size()
	panel.position = (get_viewport().get_visible_rect().size - panel.size) * .5


func _show_tournament() -> void:
	team_menu.hide()
	hud.hide()
	if not is_instance_valid(tournament_panel):
		tournament_panel = TournamentPanel.new()
		ui_layer.add_child(tournament_panel)
		tournament_panel.play_requested.connect(_play_tournament_match)
		tournament_panel.advance_requested.connect(_advance_tournament)
		tournament_panel.exit_requested.connect(_exit_tournament)
	var history := Campaign.history() if campaign != null else Tournament.history()
	tournament_panel.display(tournament, history.get("entries", []), campaign)
	if not String(tournament.state.get("in_progress", "")).is_empty():
		tournament_panel.show_notice("Матч был прерван. Он начнётся заново с теми же участниками, первым ходом и начальным раскладом.")


func _advance_tournament() -> void:
	if campaign != null and campaign.can_advance():
		if campaign.advance_cup() != OK:
			tournament_panel.show_notice(campaign.last_error, true)
			return
		tournament = campaign.cup
		_show_tournament()
		return
	# One bounded match per frame keeps the menu responsive even after elimination.
	tournament_panel.set_busy(true)
	while not tournament.completed():
		var fixture := tournament.next_match()
		if fixture.is_empty() or int(fixture.a) == 0 or int(fixture.b) == 0: break
		var simulated := campaign.simulate_next_npc() if campaign != null else tournament.simulate_next_npc()
		if not String(simulated.error).is_empty():
			tournament_panel.display(tournament, [], campaign)
			tournament_panel.show_notice(String(simulated.error), true)
			return
		await get_tree().process_frame
		if not is_inside_tree(): return
	var history := Campaign.history() if campaign != null else Tournament.history()
	tournament_panel.display(tournament, history.get("entries", []), campaign)


func _tournament_opponent() -> int:
	return int(_tournament_match.b) if int(_tournament_match.a) == 0 else int(_tournament_match.a)


func _tournament_first_side() -> int:
	var participant: int = int(_tournament_match.a) if int(_tournament_match.first_player) == 0 else int(_tournament_match.b)
	return 0 if participant == 0 else 1


func _play_tournament_match() -> void:
	_tournament_match = tournament.next_match()
	if _tournament_match.is_empty() or (int(_tournament_match.a) != 0 and int(_tournament_match.b) != 0): return
	if (campaign.begin_match(String(_tournament_match.id)) if campaign != null else tournament.begin_match(String(_tournament_match.id))) != OK:
		tournament_panel.show_notice("Не удалось сохранить начало матча. " + (campaign.last_error if campaign != null else tournament.last_error))
		return
	# All three arenas are already in Boot's resident catalog.
	var location: int = [1,2,0][campaign.cup_index()] if campaign != null else (1 if String(_tournament_match.stage).begins_with("group") else (2 if _tournament_match.stage == "semifinal" else 0))
	_preview_arena_location(location, false)
	cam.snap_overview()
	tournament_panel.hide()
	hud.show()
	_tournament_exit = Button.new()
	_tournament_exit.text = "Выйти из турнира"
	_tournament_exit.tooltip_text = "Этот незавершённый матч при продолжении начнётся заново"
	_tournament_exit.position = Vector2(12, 74)
	_tournament_exit.pressed.connect(func() -> void:
		var confirm := ConfirmationDialog.new()
		confirm.dialog_text = "Выйти в меню? Незавершённый матч начнётся заново\nс теми же участниками, первым ходом и начальным раскладом."
		confirm.ok_button_text = "Выйти"
		ui_layer.add_child(confirm)
		confirm.confirmed.connect(_exit_tournament)
		confirm.canceled.connect(confirm.queue_free)
		confirm.popup_centered())
	ui_layer.add_child(_tournament_exit)
	_preparing = true
	_build_logic()
	call_deferred("_start_game")


func _accept_tournament_result() -> Error:
	if tournament == null or _tournament_match.is_empty(): return ERR_UNAVAILABLE
	# An accepted result is never applied a second time when the result button is used.
	if String(tournament.next_match().get("id", "")) != String(_tournament_match.id): return OK
	var winner := -1 if ctrl.winner < 0 else (0 if ctrl.winner == 0 else _tournament_opponent())
	var alive := [ctrl.state.alive_count(0), ctrl.state.alive_count(1)]
	if int(_tournament_match.a) != 0: alive.reverse()
	if campaign != null:
		return campaign.record_result(String(_tournament_match.id), winner, alive, String(ctrl.game_over_reason), Campaign.observations_from_actions(ctrl.action_trace, HUMAN))
	return tournament.record_result(String(_tournament_match.id), winner, alive, String(ctrl.game_over_reason))


func _reload_tournament() -> void:
	if _accept_tournament_result() != OK:
		game_over_ui.show_result(ctrl.winner, "Не удалось сохранить результат. Повторите «К турниру». " + (campaign.last_error if campaign != null else tournament.last_error), _stats)
		return
	TournamentSession.entry_mode = "campaign_continue" if campaign != null else "continue"
	if GameLoading.i().ready_to_play:
		_release_game_resources()
		_restore_time_scale()
		GameLoading.i().show_game()
		get_tree().current_scene.enter_requested_mode()
	else:
		get_tree().reload_current_scene()


func _exit_tournament() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
