extends SceneTree
## Use the resident Boot, team controls, physical throws, event-player battles and real replay button.

const MENU := "res://scenes/menu/main_menu.tscn"
const MATCH := "res://scenes/main.tscn"
const OLD_TAG := "035b7d91f93c85e4ee3e30b310f5b21f721331431b0383ffbed1eb838641bcef"
const TEAM: Array[StringName] = [&"creature_armat_stone", &"creature_floris_stone", &"creature_klykar_stone"]
const FAMILY_BONES := {&"armat": 21, &"floris": 15, &"octo": 42}
const CLIPS := [&"idle", &"stance", &"attack", &"hit", &"roar"]
const AutoPlay := preload("res://tools/autoplay.gd")

var game: Node
var loader: GameLoading
var result_dir: String
var checks := 0
var failures := 0
var thrown := {}
var opened := {}
var fought := {}
var settled := {}
var battles := 0
var photographed := {}
var target := -1
var counts: Array[int] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)


func until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if condition.call():
			return true
	return false


func save_frame(label: String) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	check(frame != null and frame.get_size() == Vector2i(1280, 720)
		and frame.save_png(result_dir.path_join(label + ".png")) == OK, "capture " + label)


func catalog_counts() -> Array[int]:
	return [loader.preparation_count, loader.actor_build_count, loader.arena_build_count,
		loader.fighter_build_count, SoundFx.i().catalog_load_count]


func run() -> void:
	result_dir = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(result_dir)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	GraphicsSettings.force_level(GraphicsSettings.Level.MEDIUM)
	BattleTempo.loaded = true
	BattleTempo.selected = 3
	TeamMenu.difficulty = AIPlayer.Difficulty.HARD
	Engine.physics_ticks_per_second = 120
	change_scene_to_file("res://scenes/loading/boot.tscn")
	if not await until(func() -> bool: return current_scene != null and current_scene.scene_file_path == MENU, 180):
		check(false, "Boot reaches menu: " + GameLoading.i().last_error)
		await finish()
		return
	loader = GameLoading.i()
	counts = catalog_counts()
	check(loader.ready_to_play and counts[1] == 134 and counts[2] == 3, "67x2 and all three arenas before menu")
	check(Engine.max_fps == 60 and root.unfocusable and root.mode == Window.MODE_MINIMIZED,
		"minimized unfocusable window at 60 FPS")
	check_catalog()
	check_armat_decks()
	check_online()
	current_scene._on_play()
	if not await until(func() -> bool: return current_scene != null and current_scene.scene_file_path == MATCH, 15):
		check(false, "menu opens local match")
		await finish()
		return
	game = current_scene
	game.rng.seed = 119491
	game.team_menu._on_element(Attr.A.STONE)
	for id in game.team_menu._team.duplicate():
		game.team_menu._cards[id].pressed.emit()
	for id in TEAM:
		if not game.team_menu._cards.has(id):
			check(false, "missing local choice " + String(id))
			await finish()
			return
		game.team_menu._cards[id].pressed.emit()
	var preview: CreaturePreview = game.team_menu._preview
	check(preview._borrowed_ball != null and preview._shown_id == TEAM.back()
		and preview._pending.is_empty(), "team controls use the resident preview")
	await save_frame("local-team")
	var rng := RandomNumberGenerator.new()
	rng.seed = 82231
	var deck := CardDB.deck_from_creatures(TEAM, rng, CardDB.Pool.SPECIES)
	preview.show_creature(CardDB.creature(TEAM[0]))
	await save_frame("preview-armat")
	preview.show_creature(CardDB.creature(TEAM[1]))
	await save_frame("preview-floris")
	game.team_menu._show_step(1)
	for card in deck.arena:
		if game.team_menu._pick.get(CardDB.card_class(card)) != card.id:
			game.team_menu._cards[card.id].pressed.emit()
	game.team_menu._show_step(2)
	for card in deck.abilities:
		if game.team_menu._pick.get(CardDB.card_class(card)) != card.id:
			game.team_menu._cards[card.id].pressed.emit()
	check(not game.team_menu._go_btn.disabled, "normal UI accepts both new species in a valid deck")
	game.team_menu._open_arena_picker()
	game.team_menu._arena_picker.select(1)
	game.team_menu._close_arena_picker()
	game.team_menu._go_btn.pressed.emit()
	if not await until(func() -> bool: return game.ctrl != null and game.ctrl._started, 30):
		check(false, "ready match starts")
		await finish()
		return
	var acquired := {}
	for uid in game._prepared_balls:
		var ball: CreatureBall = game._prepared_balls[uid]
		acquired[uid] = ball.get_instance_id()
		check(not ball.visible and ball.process_mode == Node.PROCESS_MODE_DISABLED, "reserved uid hidden and inactive %s" % uid)
	for uid in TEAM.size():
		var ball: CreatureBall = game._prepared_balls.get(uid)
		check(ball != null and ball.uid == uid and ball.def.id == TEAM[uid], "correct resident definition for uid %d" % uid)
	game.ctrl.creature_selected.connect(func(side: int, uid: int, _recall: bool) -> void:
		if side == 0: thrown[uid] = true)
	game.ctrl.creature_stood.connect(func(uid: int, _slot: int) -> void: settled[uid] = true)
	game.ctrl.battle_started.connect(func(_slot: int, a: int, b: int) -> void:
		battles += 1
		settled[a] = true
		fought[a] = true
		fought[b] = true)
	game.director.creature_opened.connect(func(uid: int) -> void: opened[uid] = true)
	var bot := AIPlayer.new(0, 11831, -1.0, AIPlayer.Difficulty.HARD)
	check(await until(func() -> bool:
		drive(bot)
		return game.game_over_ui._panel.visible, 150), "complete real physical duel")
	for uid in 2:
		check(thrown.has(uid) and settled.has(uid) and opened.has(uid), "uid %d thrown, landed and revealed" % uid)
		check(fought.has(uid), "uid %d reached battle" % uid)
		check(photographed.has(uid), "uid %d has visible settled figure during the duel" % uid)
	check(battles > 0 and counts == catalog_counts(), "battles use resident resources")
	if not game.game_over_ui._panel.visible:
		print("Unfinished duel phase=", game.ctrl.get_phase(), " active=", game.ctrl.get_active_player(),
			" turn=", game.ctrl.get_turn(), " flying=", game.director.flying, " busy=", game.events.is_busy(),
			" interaction=", game.interaction.state, " reading=", game.hud._reading)
		game.ctrl.save_debug_trace(result_dir.path_join("unfinished-duel.json"))
	if game.game_over_ui._panel.visible:
		await save_frame("local-result")
		var replay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://replays/last_match.json"))
		check(replay.decks[0][0].has("creature_armat_stone") and MatchReplay.restore(replay).error.is_empty(),
			"recorded duel restores with Armat")
		var old_id := game.get_instance_id()
		game.game_over_ui.restart_requested.emit()
		if await until(func() -> bool: return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.scene_file_path == MATCH, 15):
			game = current_scene
			check(game.team_menu._team == TEAM, "replay restores the last local deck with both new species")
			check(counts == catalog_counts() and loader._leased.size() <= 1, "replay returns match leases and keeps catalog resident")
		else:
			check(false, "replay opens team menu")
	await finish()


func check_catalog() -> void:
	for definition in CreatureModels.catalog_defs():
		if not FAMILY_BONES.has(definition.species):
			continue
		var id := definition.id
		var path := CreatureModels._key_path(definition)
		check(path[0] == "hd:" + String(id).trim_prefix("creature_"), "normal importer uses HD model " + String(id))
		var copies: Array = loader._balls[id]
		var portrait := CreaturePortrait.presentation_texture(id)
		check(portrait != null and portrait.get_size() == Vector2(512, 512), "exact RGBA portrait " + String(id))
		for copy: CreatureBall in copies:
			var anim := copy._anim
			var player := anim._player
			var skeleton := anim._strike_skeleton
			check(skeleton != null and skeleton.get_bone_count() == FAMILY_BONES[definition.species],
				"expected skeleton " + String(id))
			check(player != null and CLIPS.all(player.has_animation), "five authored clips " + String(id))
			var material := anim._meshes[0].get_active_material(0) as ShaderMaterial
			check(material != null and material.get_shader_parameter("has_texture"), "normal HD atlas " + String(id))
			check(not copy._figure.visible and copy._shape.shape is SphereShape3D, "standard closed sphere " + String(id))


func check_armat_decks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6450
	for element in GameData.ATTR_KEYS:
		var ids := ["creature_armat_" + element, "creature_gorgul_" + element, "creature_klykar_" + element]
		var deck := CardDB.deck_from_creatures(ids, rng, CardDB.Pool.SPECIES)
		check(deck != null and Tournament._deck_valid(Tournament.deck_ids(deck), CardDB.Pool.SPECIES),
			"Armat fits a legal local team in " + element)
		var career := Career.create(element, 1, 82231, "Армат", "")
		var id: String = ids[0]
		check(career != null and career.available_species().has(&"armat") and career.price(id) == 400
			and career.power(id, 1) == 230, "career shop offers Armat in " + element)
	for pool in [CardDB.Pool.BASE, CardDB.Pool.SPECIES]:
		var has_armat := false
		for i in 100:
			var ids := Tournament.deck_ids(CardDB.random_deck(rng, pool))
			check(Tournament._deck_valid(ids, pool), "legal random team in pool %d" % pool)
			has_armat = has_armat or ids[0].any(func(id: String) -> bool: return id.begins_with("creature_armat_"))
		check(has_armat, "random local teams can include Armat in pool %d" % pool)


func check_online() -> void:
	var deck := CardDB.preset_deck(0)
	var original: Array[String] = []
	var gates: Array[String] = []
	var abilities: Array[String] = []
	for d in deck.creatures: original.append(String(d.id))
	for d in deck.arena: gates.append(String(d.id))
	for d in deck.abilities: abilities.append(String(d.id))
	var packet := {"creatures": original, "gates": gates, "abilities": abilities}
	check(OnlineProtocol.content_tag() == OLD_TAG, "client handshake content tag unchanged")
	check(OnlineProtocol.deck_error(packet).is_empty(), "established roster passes wire deck validator")
	var snapshot := OnlineStateCodec.encode_view(MatchController.new(deck, CardDB.preset_deck(1), 4242).get_view(0))
	snapshot = JSON.parse_string(JSON.stringify(snapshot))
	check(OnlineStateCodec.valid_view(snapshot), "established roster passes wire snapshot validator")
	var settings := {"element": Attr.A.STONE, "creatures": TEAM, "pick": {}}
	TeamMenu.last_deck = settings
	var menu := TeamMenu.new()
	menu.online_roster = true
	menu.elemental_cards = false
	root.add_child(menu)
	check(menu._team.all(CardDB.online_creature_available) and menu._cards.size() == 8, "online UI drops local roster from saved team")
	menu._on_element(Attr.A.STONE)
	check(not menu._cards.has(TEAM[0]) and not menu._cards.has(TEAM[1]), "local-only creatures not in online UI")
	var online_sent: Array = []
	menu.deck_chosen.connect(func(ids, _gates, _abilities): online_sent.assign(ids))
	menu.pick_random_and_start()
	check(online_sent.size() == 3 and online_sent.all(CardDB.online_creature_available), "online UI only submits server-roster IDs")
	check(TeamMenu.last_deck == settings, "online preserves local saved team")
	for id in TEAM.slice(0, 2):
		packet.creatures[0] = String(id)
		snapshot.creatures[0].def_id = String(id)
		check(not OnlineProtocol.deck_error(packet).is_empty() and not OnlineStateCodec.valid_view(snapshot),
			"both wire validators reject local-only ID " + String(id))
	menu.queue_free()
	TeamMenu.last_deck = {}


func drive(bot: AIPlayer) -> void:
	if game == null or game.ctrl == null:
		return
	if game.hud._reading > 0:
		game.hud._skip_flag = true
	if game.battle_overlay._open:
		game.battle_overlay._close()
	if AutoPlay.press_next_turn(game):
		return
	for uid in 2:
		if photographed.has(uid):
			continue
		var ball: CreatureBall = game.balls.get(uid)
		if ball != null and ball.is_figure_shown() and ball._figure.scale.is_equal_approx(Vector3.ONE) and not ball._shell.visible:
			opened[uid] = true
			photographed[uid] = true
			save_frame("open-%s" % TEAM[uid])
	var ctrl: MatchController = game.ctrl
	if ctrl.get_active_player() != 0 or game.events.is_busy():
		return
	var view := ctrl.get_view(0)
	if game.setup_panel._panel.visible:
		if ctrl.can_skip_gate():
			game._on_setup_skipped()
		else:
			var c := bot.choose_setup(view, ctrl.legal_setup_slots(), false)
			if not c.is_empty(): game._on_setup_placed(c.card_id, c.slot)
	elif game.hud._creature_panel.visible:
		var legal := ctrl.legal_creatures(0)
		if legal.is_empty(): return
		var c := bot.choose_throw(view)
		var requested_uid := int(c.get("uid", legal[0]))
		for uid in 2:
			if legal.has(uid) and not fought.has(uid):
				requested_uid = uid
				break
		target = int(c.get("target_slot", -1))
		for i in view.slots.size():
			var occupier: int = view.slots[i].occupant_uid
			if view.slots[i].has_card and occupier >= 3:
				target = i
				break
		game._on_creature_chosen(requested_uid)
	elif game._active_ball != null and not game.director.flying and ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING:
		var slots: Array = game._gate_slots()
		if not slots.is_empty(): game._on_slot_picked(target if slots.has(target) else int(slots[0]))
	elif game.ability_panel._panel.visible and ctrl.get_ability_moment() in [&"after_landing", &"battle"]:
		game._on_ability_passed()


func finish() -> void:
	if is_instance_valid(game):
		game._release_game_resources()
	if is_instance_valid(SoundFx._inst):
		for node in SoundFx._inst.get_children():
			var audio := node as AudioStreamPlayer
			if audio != null: audio.stop()
		await create_timer(.16, true, false, true).timeout
	if current_scene != null: current_scene.queue_free()
	await process_frame
	if is_instance_valid(loader): loader.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await process_frame
	await process_frame
	var report := FileAccess.open(result_dir.path_join("result.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "battles": battles,
		"thrown": thrown.keys(), "settled": settled.keys(), "opened": opened.keys(), "fought": fought.keys(),
		"catalog_counts": counts, "renderer": RenderingServer.get_current_rendering_method()}, "  ") + "\n")
	report.close()
	print("LOCAL CREATURES ", checks, "/", failures, " battles=", battles)
	quit(1 if failures else 0)
