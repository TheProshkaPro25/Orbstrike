extends Node
## Composition root: world/UI construction, explicit component wiring and scene navigation.
## Rules=MatchController; modes=GameModes; choices=Interaction; visible sequence=Presentation.
const ResourcesT := preload("res://scenes/match_resources.gd")
const MatchLifecycleT := preload("res://scenes/match_lifecycle.gd")
const PresentationT := preload("res://scenes/presentation/match_presentation.gd")
const InteractionT := preload("res://scenes/interaction/interaction_controller.gd")
const InteractionViewT := preload("res://scenes/interaction/interaction_view.gd")
const Request := preload("res://scenes/interaction/interaction_request.gd")
const ModesT := preload("res://scenes/modes/game_modes.gd")
const MatchSpec := preload("res://scenes/modes/match_spec.gd")
const Locations := preload("res://data/arena_locations.gd")
const ARENA_SCENE: PackedScene = preload("res://scenes/arena.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/creature_ball.tscn")
const CARD_SCENE: PackedScene = preload("res://scenes/arena_card_node.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const SETUP_SCENE: PackedScene = preload("res://scenes/ui/setup_panel.tscn")
const ABILITY_SCENE: PackedScene = preload("res://scenes/ui/ability_panel.tscn")
const BATTLE_SCENE: PackedScene = preload("res://scenes/ui/battle_overlay.tscn")
const GAMEOVER_SCENE: PackedScene = preload("res://scenes/ui/game_over.tscn")
const TEAM_MENU_SCENE: PackedScene = preload("res://scenes/ui/team_menu.tscn")
const HUMAN := 0
const AI_PLAYER := 1
const THROW_Z := Arena.STEP_Z * 0.5 + Arena.CARD_H * 0.5 + 0.8 * Arena.WORLD
const BALL_Y := 0.36
var presentation := PresentationT.new()
var interaction := InteractionT.new()
var modes := ModesT.new()
var rng := RandomNumberGenerator.new()
var world: Node3D
var cam: CameraRig
var events: EventPlayer
var director: ArenaDirector
var ui_layer: CanvasLayer
var hud: HudUI
var battle_hud: BattleHud
var setup_panel: SetupPanel
var ability_panel: AbilityPanel
var ability_target_picker: AbilityTargetPicker
var arena_slot_picker: ArenaSlotPicker
var battle_overlay: BattleOverlay
var game_over_ui: GameOverUI
var team_menu: TeamMenu
var hover_tips: HoverTips
var _launch_target: Button
var _duel_menu: Button
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _arena_sky: ShaderMaterial
var _resources: ResourcesT
var _lifecycle: MatchLifecycleT
var _view_configured := false
var _modes_configured := false
var _match_ui_bound := false
var _previous_time_scale := 1.0
var _time_scale_restored := false
var _online_game_over := false
var ctrl: MatchController:
	get: return interaction.ctrl
	set(value):
		interaction.ctrl = value
		presentation.ctrl = value
var ai: AIPlayer:
	get: return interaction.ai
	set(value): interaction.ai = value
var arena: Arena:
	get: return _ensure_resources().arena
	set(value): _ensure_resources().arena = value
var balls: Dictionary:
	get: return _ensure_resources().active
	set(value): _ensure_resources().active.assign(value)
var _prepared_balls: Dictionary:
	get: return _ensure_resources().reserve
var preparation_times_ms: Dictionary:
	get: return _ensure_resources().preparation_times_ms
var fighters: Array[VrmFighter]:
	get: return _ensure_resources().fighters
var fighter_portraits: Array[FighterPortrait]:
	get: return presentation.fighter_portraits
var _location_intro: LocationIntro:
	get: return _lifecycle.intro if is_instance_valid(_lifecycle) else null
var _preparing: bool:
	get: return is_instance_valid(_lifecycle) and _lifecycle.preparing()
var _game_over: bool:
	get: return _lifecycle.is_finished() if is_instance_valid(_lifecycle) else _online_game_over
	set(value):
		if is_instance_valid(_lifecycle):
			if value: _lifecycle.finish()
		else:
			_online_game_over = value
			presentation.set_finished(value)
var _pending: Dictionary:
	get: return interaction.pending.to_legacy()
	set(value): interaction.assign_legacy(value)
var _gate_pick: Dictionary:
	get: return interaction.gate_pick.to_legacy()
	set(value): interaction.gate_pick.assign_legacy(value)
var _ability_target_card: StringName:
	get: return interaction.ability_target_card
	set(value): interaction.ability_target_card = value
var _ai_target_slot: int:
	get: return interaction.ai_target_slot
	set(value): interaction.ai_target_slot = value
var _local_keyboard_navigation: bool:
	get: return interaction.keyboard_enabled
	set(value): interaction.keyboard_enabled = value
var _defs: Dictionary:
	get: return presentation.state.definitions
	set(value): presentation.state.definitions.assign(value)
var _owners: Dictionary:
	get: return presentation.state.owners
	set(value): presentation.state.owners.assign(value)
var _active_ball: CreatureBall:
	get: return presentation.state.active_ball
	set(value): presentation.state.active_ball = value
var card_nodes: Dictionary:
	get: return presentation.state.card_nodes
	set(value): presentation.state.card_nodes.assign(value)
var captures: Array[int]:
	get: return presentation.state.captures
	set(value): presentation.state.captures = value
var _pip_idx: Dictionary:
	get: return presentation.state.pip_indices
	set(value): presentation.state.pip_indices.assign(value)
var _stats: Dictionary:
	get: return presentation.state.stats
	set(value): presentation.state.stats = value
var _alive: Array[int]:
	get: return presentation.state.alive
	set(value): presentation.state.alive = value
var _turn: int:
	get: return presentation.state.turn
	set(value): presentation.state.turn = value
var _active: int:
	get: return presentation.state.active_player
	set(value): presentation.state.active_player = value
var _opponent_uid: int:
	get: return presentation.state.opponent_uid
	set(value): presentation.state.opponent_uid = value
var _opponent_power: int:
	get: return presentation.state.opponent_power
	set(value): presentation.state.opponent_power = value
var _own_uid: int:
	get: return presentation.state.own_uid
	set(value): presentation.state.own_uid = value
var _own_power: int:
	get: return presentation.state.own_power
	set(value): presentation.state.own_power = value
var _label_focus: Array:
	get: return presentation.state.label_focus
	set(value): presentation.state.label_focus = value
var _battle_uids: Array[int]:
	get: return presentation.state.battle_uids
	set(value): presentation.state.battle_uids = value
var campaign: Campaign:
	get: return modes.campaign
	set(value): modes.campaign = value
var career: Career:
	get: return modes.career
	set(value): modes.career = value
var tournament: Tournament:
	get: return modes.tournament
	set(value): modes.tournament = value
var career_panel: CareerPanel:
	get: return modes.career_panel
	set(value): modes.career_panel = value
var tournament_panel: TournamentPanel:
	get: return modes.tournament_panel
	set(value): modes.tournament_panel = value
var _tournament_match: Dictionary:
	get: return modes.fixture
	set(value): modes.fixture = value
var _tournament_registration: bool:
	get: return modes.registration
	set(value): modes.registration = value
var _campaign_registration: bool:
	get: return modes.campaign_registration
	set(value): modes.campaign_registration = value
var _player_deck: Array:
	get: return modes.player_deck
	set(value): modes.player_deck = value
var _tournament_exit: Button:
	get: return modes.exit_button
	set(value): modes.exit_button = value
var _leaving_duel: bool:
	get: return modes.leaving
	set(value): modes.leaving = value
var _duel_exit_confirm: ConfirmationDialog:
	get: return modes.exit_confirm
	set(value): modes.exit_confirm = value
var _player_ids: Array[StringName]:
	get:
		var ids: Array[StringName] = []
		if modes.player_deck.size() == 3: ids.assign(modes.player_deck[0])
		return ids
	set(value):
		if modes.player_deck.size() != 3: modes.player_deck = [[],[],[]]
		modes.player_deck[0] = value

func _init() -> void:
	add_child(presentation)
	add_child(interaction)
	add_child(modes)

func _ensure_resources() -> ResourcesT:
	if _resources == null: _resources = ResourcesT.new(world,GameLoading.i(),BALL_SCENE,ARENA_SCENE)
	return _resources

func _ready() -> void:
	_previous_time_scale = Engine.time_scale
	BattleTempo.load_settings()
	if is_equal_approx(Engine.time_scale,1.0): BattleTempo.apply()
	SoundFx.i()
	rng.randomize()
	_build_world()
	_build_ui()
	_lifecycle = MatchLifecycleT.new()
	add_child(_lifecycle)
	_lifecycle.configure(_resources,cam,ui_layer)
	interaction.lifecycle = _lifecycle
	_lifecycle.prepared.connect(presentation.present_match_roster)
	_lifecycle.started.connect(_on_match_started)
	_lifecycle.finishing.connect(_hide_match_docks)
	_lifecycle.finishing.connect(interaction.stop)
	_lifecycle.finished.connect(_close_match_actions)
	_lifecycle.finished.connect(func() -> void: presentation.set_finished(true))
	_lifecycle.released.connect(_on_match_released)
	_lifecycle.failed.connect(_on_match_failed)
	_configure_modes()
	if not GameLoading.i().preparing:
		SoundFx.i().play_music(SoundFx.MUSIC_TEAM)
		enter_requested_mode.call_deferred()

func _exit_tree() -> void:
	if is_instance_valid(GameLoading._inst) and GameLoading._inst.moving_scene: return
	_release_game_resources()
	_restore_time_scale()
	CreatureModels.clear()

func _restore_time_scale() -> void:
	if not _time_scale_restored:
		Engine.time_scale = _previous_time_scale
		_time_scale_restored = true


## Небо статично (без TIME): иначе Godot пересчитывает кубическую карту отражений каждый кадр.
const SKY_SHADER := """
shader_type sky;
uniform vec4 sky_zenith : source_color = vec4(0.016, 0.033, 0.062, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.08, 0.14, 0.19, 1.0);
uniform vec4 sky_mist : source_color = vec4(0.11, 0.035, 0.13, 1.0);
uniform bool harbor_sky = false;
uniform vec3 harbor_moon_direction = vec3(-1.0, 0.0, 0.0);
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
	if (harbor_sky) {
		float halo = pow(max(dot(d, harbor_moon_direction), 0.0), 18.0);
		float clouds = smoothstep(0.36, 0.85, mist) * (1.0 - smoothstep(0.03, 0.26, abs(d.y - 0.15)));
		col = zenith * 0.69 + sky_horizon.rgb * horizon * 0.78 + sky_mist.rgb * clouds * 0.61;
		col += vec3(0.048, 0.077, 0.128) * halo;
	}
	COLOR = col;
}
"""


## Экспозиция кадра (подобрана по контактным листам: средняя яркость ~0.25–0.35 без пересвета).
const LIGHT_EXPOSURE := 1.0


func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	_resources = ResourcesT.new(world,GameLoading.i(),BALL_SCENE,ARENA_SCENE)
	# Compatibility views for presentation/tools; ownership/transfers live in the lease.

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

	_resources.select_arena(Locations.current())
	arena = _resources.arena
	if arena != null: _apply_arena_environment(arena.location_id)
	apply_graphics()

	events = EventPlayer.new()
	add_child(events)
	director = ArenaDirector.new()
	add_child(director)


## Применить уровень графики (при старте и после смены в меню команды).

func apply_graphics() -> void:
	GraphicsSettings.apply_world(get_viewport(), _env, _sun)
	if arena != null:
		arena.apply_quality()
		_apply_arena_environment(arena.location_id)

func _build_ui(elemental_cards: bool = true, online_roster: bool = false) -> void:
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
	# Сетевая сцена наследует UI, но получает разрешения/цели от сервера отдельно.
	setup_panel._slot_btn.hide()
	ability_panel = ABILITY_SCENE.instantiate() as AbilityPanel
	ui_layer.add_child(ability_panel)
	ability_target_picker = AbilityTargetPicker.new()
	ui_layer.add_child(ability_target_picker)
	ability_target_picker.chosen.connect(_on_ability_target_chosen)
	ability_target_picker.cancelled.connect(_on_ability_target_cancelled)
	_launch_target = Button.new()
	_launch_target.text = "Выбрать ворота для броска…"
	_launch_target.tooltip_text = "Карта поля: Tab / стрелки — место, Enter — бросить, Esc — вернуться к способностям"
	_launch_target.custom_minimum_size = Vector2(272, 44)
	_launch_target.hide()
	_launch_target.pressed.connect(_request_launch_slot)
	ui_layer.add_child(_launch_target)
	_place_launch_target()
	get_viewport().size_changed.connect(_place_launch_target)
	arena_slot_picker = ArenaSlotPicker.new()
	ui_layer.add_child(arena_slot_picker)
	arena_slot_picker.chosen.connect(_on_slot_picked)
	arena_slot_picker.slot_hovered.connect(func(slot: int) -> void:
		if is_instance_valid(arena): arena.set_hover(slot))
	battle_overlay = BATTLE_SCENE.instantiate() as BattleOverlay
	ui_layer.add_child(battle_overlay)
	game_over_ui = GAMEOVER_SCENE.instantiate() as GameOverUI
	ui_layer.add_child(game_over_ui)
	team_menu = TEAM_MENU_SCENE.instantiate() as TeamMenu
	team_menu.elemental_cards = elemental_cards
	team_menu.online_roster = online_roster
	ui_layer.add_child(team_menu)
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
	ui_layer.add_child(_duel_menu)
	hud.register_interface(_duel_menu)
	hud.register_interface(_launch_target)
	_configure_views()

func _place_launch_target() -> void:
	var card_height := UiTheme.device_hand_card(get_viewport().get_visible_rect().size).y
	VisualUtil.place(_launch_target, 0.5, 1.0, 0.0, -card_height - 76.0)


func _apply_arena_environment(index: int) -> void:
	var data := Locations.definition(index)
	var low := GraphicsSettings.current() == GraphicsSettings.Level.LOW
	var sanctuary := index == 0
	var harbor := index == 2
	_arena_sky.set_shader_parameter("sky_zenith", Color(data.zenith).linear_to_srgb())
	_arena_sky.set_shader_parameter("sky_horizon", Color(data.horizon).linear_to_srgb())
	_arena_sky.set_shader_parameter("sky_mist", Color(data.mist).linear_to_srgb())
	_arena_sky.set_shader_parameter("harbor_sky", harbor)
	if harbor: _arena_sky.set_shader_parameter("harbor_moon_direction", Locations.HARBOR_MOON.normalized())
	_env.fog_light_color = Color(.083, .118, .173) if harbor else data.fog
	_env.ambient_light_color = Color(.50, .57, .66) if harbor else data.ambient
	_env.tonemap_exposure = 1.04 if harbor else LIGHT_EXPOSURE
	_env.glow_intensity = .64 if harbor else (.69 if sanctuary else .8)
	_env.glow_hdr_threshold = 1.28 if harbor or sanctuary else 1.1
	# Overcast night sky and water return light into the faces turned away from the moon.
	_env.ambient_light_energy = (.25 if low else .16) if sanctuary else ((.61 if low else .54) if harbor else .75)
	_env.fog_density = .0013 if sanctuary else (.0024 if harbor else .0025)
	_env.fog_sky_affect = .12 if harbor else (.8 if sanctuary else .25)
	_env.volumetric_fog_enabled = false
	_sun.light_color = Color(.77, .87, 1.0) if harbor else data.sun
	_sun.light_energy = 1.65 if harbor else (0.0 if sanctuary else data.sun_energy)
	_sun.light_specular = .15 if harbor else 1.0
	if harbor:
		_sun.look_at(_sun.global_position - Locations.HARBOR_MOON)
	else:
		_sun.rotation_degrees = Vector3(-52, -30, 0)
	_sun.visible = not sanctuary
	_sun.shadow_opacity = .49 if harbor else .6
	_fill.visible = not (harbor or sanctuary)
	_fill.light_color = Color(data.ambient).lightened(.15)


func _configure_views() -> void:
	if _view_configured: return
	_view_configured = true
	presentation.configure(_ensure_resources(),world,cam,events,director,hud,battle_hud,setup_panel,ability_panel,battle_overlay,game_over_ui,rng)
	var ui := InteractionViewT.new()
	ui.hud = hud
	ui.setup = setup_panel
	ui.ability = ability_panel
	ui.arena_picker = arena_slot_picker
	ui.ability_picker = ability_target_picker
	ui.launch = _launch_target
	ui.layer = ui_layer
	ui.team_menu = team_menu
	ui.game_over = game_over_ui
	ui.mode_modal_open = modes.modal_open
	ui.mode_focus_controls = modes.focus_controls
	interaction.configure(ui,presentation,_resources,_lifecycle,events,cam,director)
	presentation.input_requested.connect(interaction.queue_request)
	presentation.pre_throw_requested.connect(interaction.show_pre_throw)
	presentation.landing_ready.connect(interaction.report)
	presentation.runtime_failed.connect(func(message: String) -> void:
		if is_instance_valid(_lifecycle): _lifecycle.fail(message)
		else: hud.reject_action(message))
	presentation.result_ready.connect(_present_result)
	hover_tips.resolver = presentation.tip_at
	team_menu.visibility_changed.connect(func() -> void: _update_interaction_visibility())

func _configure_modes() -> void:
	if _modes_configured: return
	_modes_configured = true
	modes.configure(team_menu,hud,ui_layer,rng,_duel_menu)
	modes.match_requested.connect(_request_match)
	modes.arena_selection_requested.connect(_preview_arena_location)
	modes.restart_requested.connect(_restart_scene)
	modes.restart_rejected.connect(func(message: String) -> void: game_over_ui.show_result(ctrl.winner,message,presentation.state.stats))
	modes.exit_requested.connect(_exit_mode)
	modes.duel_menu_requested.connect(_request_duel_menu)
	modes.modal_opening.connect(arena_slot_picker.dismiss)
	modes.focus_restore_requested.connect(interaction.resume_keyboard_focus)

func _request_match(spec: MatchSpec) -> void:
	if is_instance_valid(_lifecycle) and _lifecycle.stage != MatchLifecycleT.Stage.SELECTING:
		modes.match_rejected("Предыдущий матч ещё не завершён.")
		return
	if not _preview_arena_location(spec.arena_id,false):
		modes.match_rejected("Арена матча сейчас недоступна. Попробуйте снова.")
		return
	if not _lifecycle.request_start(): return
	modes.match_accepted(spec)
	_build_logic(spec)
	_start_game.call_deferred()

func _build_logic(spec: MatchSpec = null) -> void:
	_configure_modes()
	setup_panel._slot_btn.show()
	CardDB.load_all()
	if spec == null: spec = modes.prepare_match_spec()
	modes.current_spec = spec
	ctrl = MatchController.new(spec.decks[0],spec.decks[1],spec.seed,MatchRules.Ruleset.ANIME_INSPIRED,spec.card_pool)
	spec.apply_power_snapshots(ctrl)
	ctrl.landing_window = true
	ai = AIPlayer.new(AI_PLAYER,spec.seed+1,-1.0,spec.difficulty)
	if not spec.ai_preferences.is_empty(): ai.configure_personality(spec.ai_preferences)
	presentation.bind_controller(ctrl,modes.career != null)
	director.semifinal_music = spec.fixture.get("stage") == "semifinal"
	presentation.set_roster_names(spec.names[0],spec.names[1])
	presentation.set_finished(false)
	presentation.connect_controller()
	interaction.bind_controller(ctrl,ai)
	ctrl.phase_changed.connect(_on_phase_changed)
	ctrl.setup_requested.connect(_on_setup_requested)
	ctrl.throw_requested.connect(_on_throw_requested)
	ctrl.ability_window.connect(_on_ability_window)
	ctrl.attach_window.connect(_on_attach_window)
	ctrl.game_over.connect(_on_game_over)
	_connect_match_interface()
	if is_instance_valid(arena):
		if not arena.slot_clicked.is_connected(_on_slot_picked): arena.slot_clicked.connect(_on_slot_picked)
		if not arena.invalid_pick.is_connected(_invalid_slot): arena.invalid_pick.connect(_invalid_slot)

func _connect_match_interface() -> void:
	if _match_ui_bound: return
	_match_ui_bound = true
	events.drained.connect(_pump)
	hud.creature_chosen.connect(_on_creature_chosen)
	hud.creature_cancelled.connect(_on_gate_throw_cancelled)
	setup_panel.placed.connect(_on_setup_placed)
	setup_panel.skipped.connect(_on_setup_skipped)
	setup_panel.placed_throw.connect(_on_setup_placed_throw)
	setup_panel.slot_pick_requested.connect(_request_setup_slot)
	setup_panel.slot_hovered.connect(func(slot: int) -> void: arena.set_hover(slot))
	ability_panel.unavailable.connect(hud.reject_action)
	ability_panel.reason_for_card = func(card: StringName) -> String: return ctrl.ability_unavailable_reason(HUMAN,card)
	ability_panel.warning_for_card = MatchController.ability_play_warning
	ability_panel.ability_chosen.connect(_on_ability_chosen)
	ability_panel.passed.connect(_on_ability_passed)
	ability_panel.gate_open_requested.connect(_on_gate_open_requested)
	game_over_ui.restart_requested.connect(_on_restart)

func _start_game() -> void:
	var spec := modes.current_spec
	var origins: Array[Vector3] = [presentation.start_pos(HUMAN),presentation.start_pos(AI_PLAYER)]
	var fighter_origins: Array[Vector3] = [Vector3(-2.3,0,THROW_Z+1.4),Vector3(2.3,0,-THROW_Z-1.4)]
	_update_interaction_visibility()
	var result := await _lifecycle.start(ctrl,presentation.state.definitions,presentation.state.owners,spec.profiles,origins,fighter_origins,spec.first_side)
	if not result.is_ok() and _lifecycle.stage != MatchLifecycleT.Stage.RELEASED:
		ctrl = null
		ai = null
		presentation.bind_controller(null)
		interaction.stop()
		_close_match_actions()
		modes.start_failed(result.message)
	_update_interaction_visibility()

func _on_match_started() -> void:
	presentation.refresh_hand()
	ability_panel.set_dock_visible(true)
	setup_panel.set_dock_visible(true)
	_duel_menu.visible = modes.tournament == null
	modes.place_exit(false, _duel_menu)
	hud.begin_match_interface([setup_panel,ability_panel])
	_update_interaction_visibility()

func _hide_match_docks() -> void:
	ability_panel.set_dock_visible(false)
	setup_panel.set_dock_visible(false)

func _close_match_actions() -> void:
	interaction.stop()
	hud.hide_creatures()
	setup_panel.hide_panel()
	ability_panel.hide_panel()
	_hide_match_docks()
	_launch_target.hide()
	arena_slot_picker.dismiss()

func _on_match_failed(message: String) -> void:
	events.stop()
	_close_match_actions()
	presentation.clear()
	SoundFx.i().cancel_match_sfx()
	SoundFx.i().stop_music(.2)
	game_over_ui.show_failure(message+"\nНачните заново или вернитесь в меню.","Повторить встречу" if modes.tournament != null else "Начать заново")

func _present_result(_winner: int, _reason: StringName) -> void:
	ctrl.save_debug_trace()
	if is_instance_valid(_lifecycle): _lifecycle.finish()
	else:
		_game_over = true
		_close_match_actions()
	presentation.set_result_context(modes.result_suffix(ctrl,presentation.state.stats),modes.restart_label())

func _on_game_over(winner: int, reason: StringName) -> void:
	if is_instance_valid(_lifecycle) and _lifecycle.stage == MatchLifecycleT.Stage.FAILED: return
	if modes.tournament != null: modes.accept_result(ctrl,presentation.state.stats)
	if is_instance_valid(_lifecycle): _lifecycle.begin_finish()
	else: _hide_match_docks()
	events.push(presentation.anim_game_over.bind(winner,reason))

func _on_phase_changed(phase: int, player: int) -> void:
	interaction.invalidate(phase,player)
	events.push(presentation.anim_phase.bind(phase,player))

func _on_setup_requested(player: int) -> void:
	events.push(interaction.queue_request.bind(Request.make(Request.Kind.SETUP,player) as Request))

func _on_throw_requested(player: int) -> void:
	events.push(interaction.queue_request.bind(Request.make(Request.Kind.THROW,player) as Request))

func _on_ability_window(player: int, _options: Array) -> void:
	events.push(interaction.queue_request.bind(Request.make(Request.Kind.ABILITY,player) as Request))

func _on_attach_window(player: int, _uid: int, _options: Array) -> void:
	events.push(interaction.queue_request.bind(Request.make(Request.Kind.ATTACH,player) as Request))

func _release_game_resources() -> void:
	presentation.clear()
	interaction.stop()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.cancel_match_sfx()
	if is_instance_valid(team_menu): team_menu._preview.release()
	if is_instance_valid(_lifecycle): _lifecycle.release()
	elif _resources != null:
		_resources.release()
		_on_match_released()

func _on_match_released() -> void:
	interaction.stop()
	process_mode = Node.PROCESS_MODE_DISABLED

func _on_restart() -> void:
	modes.request_restart(ctrl,presentation.state.stats,is_instance_valid(_lifecycle) and _lifecycle.stage == MatchLifecycleT.Stage.FAILED)

func _restart_scene(entry: String) -> void:
	if GameLoading.i().ready_to_play:
		_release_game_resources()
		_restore_time_scale()
		GameLoading.i().show_game()
		if not entry.is_empty(): get_tree().current_scene.enter_requested_mode()
	else: get_tree().reload_current_scene()

func _exit_mode() -> void:
	interaction.stop()
	events.stop()
	SoundFx.i().cancel_match_sfx()
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")

func _request_duel_menu() -> void:
	modes.request_duel_menu(ctrl,_game_over)

func _leave_duel_to_menu() -> void:
	modes.leave_duel()

func _invalid_slot() -> void:
	hud.reject_action("Выберите одно из подсвеченных мест на поле")

func _preview_arena_location(index: int, save_choice: bool = true) -> bool:
	if ctrl != null: return false
	var result := _ensure_resources().select_arena(index)
	if not result.is_ok():
		modes.arena_selection_completed(arena.location_id if is_instance_valid(arena) else Locations.current(),false,result.message)
		return false
	if save_choice: Locations.choose(index)
	apply_graphics()
	_apply_arena_environment(index)
	cam.location_preview_view(index == 0)
	hud.visible = false
	return true

func _update_interaction_visibility() -> void:
	presentation.set_interaction_blocked(_preparing or is_instance_valid(team_menu) and team_menu.visible)

func _index_creatures() -> void:
	_compat_presentation_ports()
	presentation.bind_controller(ctrl,modes.career != null)

func _place_duel_menu(battle: bool) -> void:
	modes.duel_button = _duel_menu
	modes.place_exit(battle)

func _compat_presentation_ports() -> void:
	if _view_configured: return
	presentation.resources = _ensure_resources()
	presentation.world = world
	presentation.cam = cam
	presentation.events = events
	presentation.director = director
	presentation.hud = hud
	presentation.battle_hud = battle_hud
	presentation.setup_panel = setup_panel
	presentation.ability_panel = ability_panel
	presentation.battle_overlay = battle_overlay
	presentation.game_over_ui = game_over_ui
	presentation.rng = rng
	presentation.set_interaction_blocked(_preparing or is_instance_valid(team_menu) and team_menu.visible)

# Thin legacy adapters for client inheritance and existing focused tools.
# They never hold state or implement a second decision path.
func _present_match_roster() -> void:
	_compat_presentation_ports()
	presentation.present_match_roster()

func _bind_match_portraits() -> void:
	_compat_presentation_ports()
	presentation.bind_match_portraits()

func _focus_labels(uids: Array) -> void:
	_compat_presentation_ports()
	presentation.focus_labels(uids)

func _ability_fx(player: int, def: CardDef) -> void:
	_compat_presentation_ports()
	await presentation.ability_fx(player,def)

func _gate_fx(base: Vector3, foe_base: Vector3) -> void:
	_compat_presentation_ports()
	presentation.gate_fx(base,foe_base)

func _cry(uid: int, kind: String, delay: float = 0.0, db: float = -1.0) -> void:
	_compat_presentation_ports()
	presentation.cry(uid,kind,delay,db)

func _refresh_hand() -> void:
	_compat_presentation_ports()
	presentation.refresh_hand()

func _clear_match_portraits() -> void:
	_compat_presentation_ports()
	presentation.clear_match_portraits()

func _creature_def(uid: int) -> CreatureDef:
	_compat_presentation_ports()
	return presentation.creature_def(uid)

func _owner_of(uid: int) -> int:
	_compat_presentation_ports()
	return presentation.owner_of(uid)

func _cname(uid: int) -> String:
	_compat_presentation_ports()
	return presentation.cname(uid)

func _names_for(r: BattleResult) -> Dictionary:
	_compat_presentation_ports()
	return presentation.names_for(r)

func _wait(sec: float) -> void:
	_compat_presentation_ports()
	await presentation.wait(sec)

func _tip_at(mp: Vector2) -> Dictionary:
	_compat_presentation_ports()
	return presentation.tip_at(mp)

func _tip_at_uncached(mp: Vector2, cached_view: MatchState = null) -> Dictionary:
	_compat_presentation_ports()
	return presentation.tip_at_uncached(mp,cached_view)

func _slot_tip(i: int, sl: SlotState, view: MatchState) -> Array:
	_compat_presentation_ports()
	return presentation.slot_tip(i,sl,view)

func _creature_tip(uid: int, view: MatchState) -> Array:
	_compat_presentation_ports()
	return presentation.creature_tip(uid,view)

func _log(text: String, c: Color = UiTheme.TEXT) -> void:
	_compat_presentation_ports()
	presentation.log_event(text,c)

func _say(player: int, you: String, foe: String) -> String:
	_compat_presentation_ports()
	return presentation.say(player,you,foe)

func _on_arena_card_placed(player: int, slot: int) -> void:
	_compat_presentation_ports()
	presentation.on_arena_card_placed(player,slot)

func _on_creature_selected(player: int, uid: int, recalled: bool) -> void:
	_compat_presentation_ports()
	presentation.on_creature_selected(player,uid,recalled)

func _on_creature_returned(uid: int, reason: StringName) -> void:
	_compat_presentation_ports()
	presentation.on_creature_returned(uid,reason)

func _on_creature_stood(uid: int, slot: int) -> void:
	_compat_presentation_ports()
	presentation.on_creature_stood(uid,slot)

func _on_battle_started(slot: int, attacker_uid: int, defender_uid: int) -> void:
	_compat_presentation_ports()
	presentation.on_battle_started(slot,attacker_uid,defender_uid)

func _on_card_revealed(slot: int, card_id: StringName) -> void:
	_compat_presentation_ports()
	presentation.on_card_revealed(slot,card_id)

func _on_ability_played(player: int, card_id: StringName) -> void:
	_compat_presentation_ports()
	presentation.on_ability_played(player,card_id)

func _on_ability_cancelled(player: int, card_id: StringName) -> void:
	_compat_presentation_ports()
	presentation.on_ability_cancelled(player,card_id)

func _on_battle_resolved(result: BattleResult) -> void:
	_compat_presentation_ports()
	presentation.on_battle_resolved(result)

func _on_creature_eliminated(uid: int) -> void:
	_compat_presentation_ports()
	presentation.on_creature_eliminated(uid)

func _on_card_captured(player: int, slot: int, _card_id: StringName) -> void:
	_compat_presentation_ports()
	presentation.on_card_captured(player,slot,_card_id)

func _on_turn_started(player: int, turn: int) -> void:
	_compat_presentation_ports()
	presentation.on_turn_started(player,turn)

func _on_ability_attached(player: int, uid: int, card_id: StringName) -> void:
	_compat_presentation_ports()
	presentation.on_ability_attached(player,uid,card_id)

func _on_gate_thrown(player: int, slot: int, uid: int) -> void:
	_compat_presentation_ports()
	presentation.on_gate_thrown(player,slot,uid)

func _on_gate_trap(slot: int, card_id: StringName, effect: StringName) -> void:
	_compat_presentation_ports()
	presentation.on_gate_trap(slot,card_id,effect)

func _on_momentum_changed(player: int, value: int) -> void:
	_compat_presentation_ports()
	presentation.on_momentum_changed(player,value)

func _on_final_round(player: int) -> void:
	_compat_presentation_ports()
	presentation.on_final_round(player)

func _on_creature_revived(uid: int) -> void:
	_compat_presentation_ports()
	await presentation.on_creature_revived(uid)

func _on_creature_marked(uid: int, card_id: StringName, mark: Dictionary) -> void:
	_compat_presentation_ports()
	presentation.on_creature_marked(uid,card_id,mark)

func _on_fighter_swapped(old_uid: int, new_uid: int, slot: int) -> void:
	_compat_presentation_ports()
	presentation.on_fighter_swapped(old_uid,new_uid,slot)

func _on_gates_swapped(a: int, b: int) -> void:
	_compat_presentation_ports()
	await presentation.on_gates_swapped(a,b)

func _on_gate_discarded(slot: int, _card_id: StringName) -> void:
	_compat_presentation_ports()
	await presentation.on_gate_discarded(slot,_card_id)

func _on_abilities_recalled(player: int, card_ids: Array) -> void:
	_compat_presentation_ports()
	presentation.on_abilities_recalled(player,card_ids)

func _on_abilities_recharged(player: int, card_ids: Array) -> void:
	_compat_presentation_ports()
	presentation.on_abilities_recharged(player,card_ids)

func _anim_fighter_swapped(old_uid: int, new_uid: int, _slot: int) -> void:
	_compat_presentation_ports()
	await presentation.anim_fighter_swapped(old_uid,new_uid,_slot)

func _anim_phase(_phase: int, active_player: int) -> void:
	_compat_presentation_ports()
	presentation.anim_phase(_phase,active_player)

func _anim_turn(player: int, turn: int) -> void:
	_compat_presentation_ports()
	presentation.anim_turn(player,turn)

func _anim_set_pending(p: Dictionary) -> void:
	_compat_presentation_ports()
	presentation.anim_set_pending(Request.from_legacy(p) as Request)

func _anim_attached(player: int, uid: int, card_id: StringName) -> void:
	_compat_presentation_ports()
	await presentation.anim_attached(player,uid,card_id)

func _anim_gate_thrown(player: int, _slot: int, uid: int) -> void:
	_compat_presentation_ports()
	await presentation.anim_gate_thrown(player,_slot,uid)

func _anim_trap(slot: int, card_id: StringName, effect: StringName) -> void:
	_compat_presentation_ports()
	await presentation.anim_trap(slot,card_id,effect)

func _anim_momentum(player: int, value: int) -> void:
	_compat_presentation_ports()
	presentation.anim_momentum(player,value)

func _anim_final_round(_player: int) -> void:
	_compat_presentation_ports()
	await presentation.anim_final_round(_player)

func _anim_card_placed(player: int, slot: int) -> void:
	_compat_presentation_ports()
	await presentation.anim_card_placed(player,slot)

func _anim_selected(player: int, uid: int, recalled: bool) -> void:
	_compat_presentation_ports()
	await presentation.anim_selected(player,uid,recalled)

func _anim_returned(uid: int, reason: StringName) -> void:
	_compat_presentation_ports()
	await presentation.anim_returned(uid,reason)

func _anim_relocated(uid: int, _from: int, to: int) -> void:
	_compat_presentation_ports()
	await presentation.anim_relocated(uid,_from,to)

func _anim_refilled(player: int) -> void:
	_compat_presentation_ports()
	await presentation.anim_refilled(player)

func _anim_remove_ball(uid: int, eliminated: bool = false) -> void:
	_compat_presentation_ports()
	await presentation.anim_remove_ball(uid,eliminated)

func _anim_stood(uid: int, slot: int) -> void:
	_compat_presentation_ports()
	await presentation.anim_stood(uid,slot)

func _anim_battle_started(slot: int, attacker_uid: int, defender_uid: int, powers: Array = [], momentum: Array = [0, 0]) -> void:
	_compat_presentation_ports()
	await presentation.anim_battle_started(slot,attacker_uid,defender_uid,powers,momentum)

func _anim_card_revealed(slot: int, card_id: StringName, owner: int = -1) -> void:
	_compat_presentation_ports()
	await presentation.anim_card_revealed(slot,card_id,owner)

func _anim_ability_msg(player: int, card_id: StringName, cancelled: bool, powers: Array = []) -> void:
	_compat_presentation_ports()
	await presentation.anim_ability_msg(player,card_id,cancelled,powers)

func _anim_ability_cam(player: int) -> void:
	_compat_presentation_ports()
	presentation.anim_ability_cam(player)

func _anim_battle_resolved(result: BattleResult) -> void:
	_compat_presentation_ports()
	await presentation.anim_battle_resolved(result)

func _anim_no_winner(result: BattleResult) -> void:
	_compat_presentation_ports()
	await presentation.anim_no_winner(result)

func _anim_captured(player: int, slot: int) -> void:
	_compat_presentation_ports()
	await presentation.anim_captured(player,slot)

func _anim_game_over(winner: int, reason: StringName) -> void:
	_compat_presentation_ports()
	presentation.anim_game_over(winner,reason)

func _refresh_status() -> void:
	_compat_presentation_ports()
	presentation.refresh_status()

func _card_name(id: StringName) -> String:
	_compat_presentation_ports()
	return presentation.card_name(id)

func _spawn_ball(uid: int) -> CreatureBall:
	_compat_presentation_ports()
	return presentation.spawn_ball(uid)

func _start_pos(player: int) -> Vector3:
	_compat_presentation_ports()
	return presentation.start_pos(player)

func _reason_text(reason: StringName) -> String:
	_compat_presentation_ports()
	return presentation.reason_text(reason)

func _gate_slots() -> Array:
	_compat_presentation_ports()
	return presentation.gate_slots()

func _on_card_drawn(player: int, card_id: StringName) -> void:
	_compat_presentation_ports()
	await presentation.on_card_drawn(player,card_id)

func _clear_opponent_panel() -> void:
	_compat_presentation_ports()
	presentation.clear_opponent_panel()

func _clear_own_panel() -> void:
	_compat_presentation_ports()
	presentation.clear_own_panel()

func _present_own(uid: int, power: int) -> void:
	_compat_presentation_ports()
	presentation.present_own(uid,power)

func _public_creature_opened(uid: int) -> void:
	_compat_presentation_ports()
	presentation.public_creature_opened(uid)

func _present_opponent(uid: int, power: int) -> void:
	_compat_presentation_ports()
	presentation.present_opponent(uid,power)

func _present_battle_opponent(attacker: int, defender: int, powers: Array) -> void:
	_compat_presentation_ports()
	presentation.present_battle_opponent(attacker,defender,powers)

func _present_battle_powers(powers: Array) -> void:
	_compat_presentation_ports()
	presentation.present_battle_powers(powers)

func _opponent_panel_layout() -> void:
	_compat_presentation_ports()
	presentation.opponent_panel_layout()

func _finish_opponent_battle() -> void:
	_compat_presentation_ports()
	presentation.finish_opponent_battle()

func _battle_blocks(result: BattleResult) -> Array:
	_compat_presentation_ports()
	return presentation.battle_blocks(result)

func _report(uid: int, slot: int) -> void:
	interaction.report(uid,slot)

func _pump() -> void:
	interaction.pump()

func _do_setup(player: int) -> void:
	interaction.do_setup(player)

func _do_throw_select(player: int) -> void:
	interaction.do_throw_select(player)

func _do_launch(player: int) -> void:
	await interaction.do_launch(player)

func _on_slot_picked(slot: int) -> void:
	await interaction.on_slot_picked(slot)

func _human_field_input_allowed() -> bool:
	return interaction.human_field_input_allowed()

func _blocking_modal() -> bool:
	return interaction.blocking_modal()

func _input(event: InputEvent) -> void:
	interaction.input(event)

func _collect_keyboard_controls(node: Node, choices: Array[Control]) -> void:
	interaction.collect_keyboard_controls(node,choices)

func _focus_action(control: Control) -> void:
	interaction.focus_action(control)

func _resume_keyboard_focus() -> void:
	interaction.resume_keyboard_focus()

func _request_setup_slot() -> void:
	interaction.request_setup_slot()

func _request_launch_slot() -> void:
	interaction.request_launch_slot()

func _field_slot_description(slot: int) -> String:
	return interaction.field_slot_description(slot)

func _do_ability(player: int) -> void:
	interaction.do_ability(player)

func _do_attach(player: int) -> void:
	interaction.do_attach(player)

func _show_pre_throw() -> void:
	interaction.show_pre_throw()

func _throwable_entries() -> Array:
	return interaction.throwable_entries()

func _on_setup_placed_throw(card_id: StringName, slot: int) -> void:
	interaction.on_setup_placed_throw(card_id,slot)

func _focus_ability_action() -> void:
	interaction.focus_ability_action()

func _on_gate_throw_cancelled() -> void:
	interaction.on_gate_throw_cancelled()

func _on_creature_chosen(uid: int) -> void:
	interaction.on_creature_chosen(uid)

func _on_setup_skipped() -> void:
	interaction.on_setup_skipped()

func _on_setup_placed(card_id: StringName, slot: int) -> void:
	interaction.on_setup_placed(card_id,slot)

func _on_ability_chosen(card_id: StringName) -> void:
	interaction.on_ability_chosen(card_id)

func _on_ability_target_chosen(target: Dictionary) -> void:
	interaction.on_ability_target_chosen(target)

func _on_ability_target_cancelled() -> void:
	interaction.on_ability_target_cancelled()

func _play_chosen_ability(card_id: StringName, target: Dictionary = {}) -> void:
	interaction.play_chosen_ability(card_id,target)

func _on_gate_open_requested() -> void:
	interaction.on_gate_open_requested()

func _on_ability_passed() -> void:
	interaction.on_ability_passed()

func enter_requested_mode() -> void:
	modes.enter_requested_mode()

func _on_deck_chosen(creatures: Array[StringName], arena_ids: Array[StringName], abilities: Array[StringName]) -> void:
	modes.submit_deck(creatures,arena_ids,abilities)

func _build_decks() -> Array[DeckDef]:
	return modes.choose_decks()

func _register_tournament(creatures: Array[StringName], gates: Array[StringName], abilities: Array[StringName]) -> void:
	modes.register_tournament(creatures,gates,abilities)

func _show_tournament_error(message: String) -> void:
	modes.show_error(message)

func _show_tournament() -> void:
	modes.show_tournament()

func _advance_tournament() -> void:
	await modes.advance_tournament()

func _career_tournament_heading() -> void:
	modes.career_tournament_heading()

func _tournament_opponent() -> int:
	return modes.opponent()

func _tournament_first_side() -> int:
	return modes.first_side()

func _play_tournament_match() -> void:
	modes.play_tournament_match()

func _make_tournament_exit_button() -> Button:
	return modes.make_exit_button()

func _enter_career() -> void:
	modes.enter_career()

func _show_career(notice: String = "") -> void:
	modes.show_career(notice)

func _create_career(element: int, difficulty: int) -> void:
	modes.create_career(element,difficulty)

func _register_career(creatures: Array[StringName], gates: Array[StringName], abilities: Array[StringName], levels: Dictionary) -> void:
	modes.register_career(creatures,gates,abilities,levels)

func _career_reward_text() -> String:
	return modes.reward_text()

func _accept_tournament_result() -> Error:
	return modes.accept_result(ctrl,presentation.state.stats).error

func _reload_tournament() -> void:
	_on_restart()

func _exit_tournament() -> void:
	modes.request_exit()
