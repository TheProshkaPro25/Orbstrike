extends SceneTree
## Six attacks through EventPlayer on the resident match, with isolated light checks.

const CreatureElementFx := preload("res://scenes/presentation/creature_element_fx.gd")
const CARD_SCENE := preload("res://scenes/arena_card_node.tscn")
const MatchSpec := preload("res://scenes/modes/match_spec.gd")
const ROSTER := [
	&"creature_dragnar_fire", &"creature_grifalon_gale", &"creature_ratnik_light",
	&"creature_rogozhuk_stone", &"creature_klykar_shadow", &"creature_levian_tide",
]
const KEYS := ["fire", "gale", "light", "stone", "shadow", "tide"]

var loader: GameLoading
var game: Node
var output: String
var failures := 0
var checks := 0
var actors: Array[CreatureBall] = []
var stage_card: ArenaCardNode
var stage_origin: Vector3
var review_stone_tide := false


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)


func run() -> void:
	if DisplayServer.get_name() == "headless" or not has_meta("sfery_background_draw"):
		check(false, "render via tools/check.py with the minimized test window")
		quit(1)
		return
	output = OS.get_cmdline_user_args()[0]
	review_stone_tide = OS.get_cmdline_user_args().has("--stone-tide")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	GraphicsSettings.force_level(GraphicsSettings.Level.MEDIUM)
	GraphicsSettings.max_fps = 60
	seed(113481)
	loader = GameLoading.i()
	await loader.prepare()
	check(loader.ready_to_play and loader.actor_build_count == CreatureModels.catalog_defs().size() * 2, "Boot prepared the full resident roster: " + loader.last_error)
	if not loader.ready_to_play:
		await finish()
		return
	loader.show_game()
	game = current_scene
	await process_frame
	var preview_ball: CreatureBall = game.team_menu._preview._borrowed_ball
	check(preview_ball != null and preview_ball._figure.visible and not preview_ball._element_fx.is_visible_in_tree(), "team preview has no battle effect")
	Engine.time_scale = 1.0
	var spec := MatchSpec.new()
	spec.arena_id = 2
	spec.seed = 113481
	spec.profiles.assign([PlayerProfile.DEFAULT, PlayerProfile.DEFAULT])
	spec.names.assign(["Игрок", "Соперник"])
	var rng := RandomNumberGenerator.new()
	rng.seed = spec.seed
	for side in 2:
		var deck := CardDB.deck_from_creatures(ROSTER.slice(side * 3, side * 3 + 3), rng)
		check(deck != null, "valid team %d" % side)
		if deck == null:
			await finish()
			return
		spec.decks.append(deck)
	game._request_match(spec)
	if game.events.drained.is_connected(game._pump):
		game.events.drained.disconnect(game._pump)
	var deadline := Time.get_ticks_msec() + 25000
	while game._preparing and Time.get_ticks_msec() < deadline:
		await process_frame
	check(game.ctrl != null and game.ctrl._started and game._prepared_balls.size() == 6, "normal match preparation")
	if failures > 0:
		await finish()
		return
	game.ui_layer.hide()
	if not await setup_cast():
		await finish()
		return
	await showcase_attacks()
	if not review_stone_tide:
		await check_cancellation()
	game._release_game_resources()
	check(loader._leased.is_empty() and loader.actor_build_count == CreatureModels.catalog_defs().size() * 2, "all six returned without rebuilding")
	for ball in actors:
		check(not ball._element_fx.is_visible_in_tree(), "no attack detail in parked catalog")
	await finish()


func setup_cast() -> bool:
	var view: MatchState = game.ctrl.get_view(0)
	for side in 2:
		for uid in view.players[side].creature_uids:
			var prepared: CreatureBall = game._prepared_balls[uid]
			var effect := prepared._element_fx
			var ball: CreatureBall = game._spawn_ball(uid)
			if ball == null or effect == null:
				check(false, "match has six prepared actors and charge meshes")
				return false
			check(ball == prepared and ball._element_fx == effect, "reuse the resident charge mesh")
			check(not effect.is_visible_in_tree(), "closed sphere has no attack effect")
			check(effect.element == actors.size(), "correct element")
			ball.set_label_allowed(false)
			ball.freeze_at(game.arena.slot_position(actors.size()) + Vector3.UP * (CreatureBall.RADIUS + 0.02))
			game.director.open_creature(ball, false)
			actors.append(ball)
	var shared := actors[0]._element_fx.material_override as ShaderMaterial
	for parameter in CreatureElementFx.TEXTURES:
		check(shared.get_shader_parameter(parameter) == CreatureElementFx.TEXTURES[parameter], "reference texture " + String(parameter))
	await create_timer(2.0).timeout
	for ball in actors:
		check(ball.is_figure_shown() and not ball._element_fx.visible, "open idle has no attack effect")
		check(ball._element_fx.material_override == shared, "one shared material")
	stage_origin = game.arena.slot_position(4)
	stage_card = CARD_SCENE.instantiate() as ArenaCardNode
	stage_card.position = stage_origin
	game.world.add_child(stage_card)
	stage_card.set_field_surface(true)
	return true


func stage(attacker: CreatureBall, target: CreatureBall, on_gate: bool = true) -> void:
	for ball in actors:
		ball.visible = ball == attacker or ball == target
		ball.set_label_allowed(false)
	var separation := Vector3.BACK * Arena.FIG_H / 3.0
	var floor_height := ArenaCardNode.SURFACE_Y if on_gate else 0.0
	var floor_offset := Vector3.UP * (CreatureBall.RADIUS + floor_height)
	attacker.freeze_at(stage_origin + separation + floor_offset)
	target.freeze_at(stage_origin - separation + floor_offset)
	attacker.face_toward(target.global_position)
	target.face_toward(attacker.global_position)
	stage_card.show_facedown(0, CardDB.card(StringName("arena_field_" + KEYS[attacker.def.attribute])))
	stage_card.visible = on_gate
	stage_card.set_field_surface(on_gate)
	game.cam.battle_view(stage_origin, maxf(attacker.figure_height(), target.figure_height()), true, maxf(attacker.figure_size(), target.figure_size()))


func result(attacker: CreatureBall, target: CreatureBall) -> BattleResult:
	var battle := BattleResult.new()
	battle.slot = 4
	battle.attacker_uid = attacker.uid
	battle.defender_uid = target.uid
	battle.winner_uid = attacker.uid
	battle.loser_uid = target.uid
	battle.powers.assign([430, 330])
	return battle


func showcase_attacks() -> void:
	var pairs: Array[Vector2i] = []
	if review_stone_tide:
		pairs.assign([Vector2i(3, 0), Vector2i(5, 0), Vector2i(3, 2), Vector2i(5, 2)])
	else:
		pairs.assign([Vector2i(0, 2), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 2), Vector2i(4, 0), Vector2i(5, 2)])
	var sound := SoundFx.i()
	var initial_audio_loads := sound.catalog_load_count
	for pair in pairs:
		var path := SoundFx.SFX_DIR + "impact_" + String(KEYS[pair.x])
		check(sound._cache.get(path) is AudioStream, "contact audio is resident at Boot " + String(KEYS[pair.x]))
	var contact_heights := {}
	for pair in pairs:
		var element := pair.x
		var attacker := actors[pair.x]
		var target := actors[pair.y]
		var key: String = KEYS[element]
		if review_stone_tide: key += "-air" if pair.y == 0 else "-ground"
		# Cover both the placed gate and the arena surface. Props never act as the floor.
		stage(attacker, target, not review_stone_tide or pair.y == 0)
		var impacts: Array = game.director.effects._impacts
		var slot: int = game.director.effects._impact_slot
		var effect: CreatureElementFx = impacts[slot]
		var battle := result(attacker, target)
		game.battle_hud.open([attacker.def.display_name, target.def.display_name], [element, target.def.attribute], battle.powers)
		game.events.push(game.presentation.anim_battle_resolved.bind(battle))
		if not await until(func() -> bool: return attacker._element_fx.visible and float(attacker._element_fx.get_instance_shader_parameter(&"progress")) >= 0.35):
			check(false, "capture windup " + KEYS[element])
			return
		check(not effect.visible and not effect._light.visible, "no impact or light before contact " + KEYS[element])
		check(impact_voice_count(element) == 0, "no elemental contact audio during windup " + key)
		await save(key + "-windup")
		if not await until(func() -> bool: return effect.visible and effect.element == element):
			check(false, "EventPlayer routes confirmed impact " + KEYS[element])
			return
		check(attacker._anim._contact_sent and target._anim._action == &"hit", "impact is synchronized with reaction " + KEYS[element])
		check(impact_voice_count(element) == 1, "one elemental audio voice on contact frame " + key)
		var anchor := target._anim.strike_anchor()
		check(target._anim._strike_bone >= 0 and absf(effect.impact_contact.y - anchor.y) < 0.35, "contact follows torso pose " + key)
		var surface_y := ArenaCardNode.SURFACE_Y if stage_card.visible else 0.0
		check(is_equal_approx(effect.global_position.y, surface_y) and is_equal_approx(effect.impact_surface_y, surface_y), "secondary FX use surface height " + key)
		check(float(effect.get_instance_shader_parameter(&"contact_height")) > 0.4, "body anchor is separate from surface " + key)
		contact_heights[key] = effect.impact_contact.y - surface_y
		if element == Attr.A.STONE:
			check(effect.mesh.get_aabb().size.z > 0.1, "stone uses solid tumbling shards")
		var has_light: bool = CreatureElementFx.LIGHT_ENERGY[element] > 0.0
		check(effect._light.visible == has_light and (effect._light.light_energy > 0.0) == has_light, "light style " + KEYS[element])
		await create_timer(0.064 if element == Attr.A.GALE or element == Attr.A.LIGHT else 0.12).timeout
		paused = true
		var rendered := await capture()
		check(rendered.save_png(output.path_join(key + "-impact.png")) == OK, "save impact " + key)
		if has_light:
			effect._light.hide()
			var unlit := await capture()
			check(unlit.save_png(output.path_join(key + "-no-light.png")) == OK, "save comparison " + key)
			check(diff_pixels(rendered, unlit) >= 400, "local light changes the rendered surroundings " + KEYS[element])
			effect._light.show()
		paused = false
		if review_stone_tide:
			check(await until(func() -> bool: return float(effect.get_instance_shader_parameter(&"progress")) >= 0.66), "reach surface phase " + key)
			await save(key + "-surface")
		check(await settle_result(), "EventPlayer completes the result " + KEYS[element])
		check(not effect.visible and not effect._light.visible and effect._light.light_energy == 0.0 and not attacker._element_fx.visible, "all strike visuals finish " + KEYS[element])
		var stream: AudioStream = sound._cache[SoundFx.SFX_DIR + "impact_" + KEYS[element]]
		check(await until(func() -> bool: return impact_voice_count(element) == 0, stream.get_length() + 0.2), "elemental audio ends naturally " + key)
	print("Pose-derived contact heights over their own surface: ", JSON.stringify(contact_heights))
	check(sound.catalog_load_count == initial_audio_loads, "combat audio reuses the Boot catalog")


func impact_voice_count(element: int = -1) -> int:
	var sound := SoundFx.i()
	var file_name := "/impact_" if element < 0 else "/impact_" + String(KEYS[element]) + ".ogg"
	return sound._pool.filter(func(player: AudioStreamPlayer) -> bool:
		return player.playing and player.stream != null and player.stream.resource_path.contains(file_name)).size()


func check_cancellation() -> void:
	var attacker := actors[5] if review_stone_tide else actors[0]
	var target := actors[3] if review_stone_tide else actors[5]
	stage(attacker, target)
	var battle := result(attacker, target)
	battle.winner_uid = -1
	battle.loser_uid = -1
	battle.interrupted = true
	var slot: int = game.director.effects._impact_slot
	game.battle_hud.open([attacker.def.display_name, target.def.display_name], [attacker.def.attribute, target.def.attribute], battle.powers)
	game.events.push(game.presentation.anim_battle_resolved.bind(battle))
	check(await settle_result(), "interrupted battle finishes normally")
	check(game.director.effects._impact_slot == slot and not attacker._element_fx.visible and not target._element_fx.visible, "interrupted battle plays no strike")
	check(impact_voice_count() == 0, "interrupted battle plays no elemental audio")

	stage(attacker, target)
	battle.both_lose = true
	battle.interrupted = false
	game.events.push(game.presentation.anim_battle_resolved.bind(battle))
	check(await until(func() -> bool: return game.director.effects._impacts.all(func(impact: CreatureElementFx) -> bool: return impact.visible)), "both contacts use separate pooled impacts")
	check(impact_voice_count(attacker.def.attribute) == 1 and impact_voice_count(target.def.attribute) == 1, "both confirmed impacts play their own element audio")
	check(await settle_result(), "both contacts complete the result")
	check(game.director.effects._impact_slot == slot, "both contacts consume exactly two slots")
	var sound := SoundFx.i()
	sound.strike_impact(attacker.def.attribute)
	sound.strike_impact(attacker.def.attribute)
	check(impact_voice_count(attacker.def.attribute) == 1, "same-element simultaneous voices do not double the transient")
	sound.cancel_match_sfx()

	stage(attacker, target)
	game.events.push(game.presentation.anim_battle_resolved.bind(result(attacker, target)))
	check(await until(func() -> bool: return attacker._element_fx.visible), "start a windup before folding")
	attacker.close_up()
	await process_frame
	check(impact_voice_count() == 0, "folding before contact plays no elemental audio")
	check(await settle_result(), "closing the attacker releases contact wait and finishes result")
	check(not attacker._element_fx.visible and game.director.effects._impact_slot == slot, "fold cancels windup and impact")
	await attacker.open_animated(false)
	check(not attacker._element_fx.visible, "reopening does not replay interrupted effect")

	stage(attacker, target)
	GraphicsSettings.force_level(GraphicsSettings.Level.LOW)
	game.apply_graphics()
	game.events.push(game.presentation.anim_battle_resolved.bind(result(attacker, target)))
	var effect: CreatureElementFx = game.director.effects._impacts[slot]
	check(await until(func() -> bool: return effect.visible), "low quality keeps impact")
	check(impact_voice_count(attacker.def.attribute) == 1, "low graphics keeps elemental audio")
	check(not effect._light.visible and effect.mesh.surface_get_array_index_len(0) == 8 * 6, "low quality has eight details and no dynamic lamp")
	game.director.effects.clear()
	for impact in game.director.effects._impacts:
		check(not impact.visible and not impact._light.visible and impact._light.light_energy == 0.0, "clearing pooled impact stops its light immediately")
	check(await settle_result(), "battle can close after effects are cleared")
	var uid := attacker.uid
	var charge := attacker._element_fx
	await game._anim_remove_ball(uid)
	check(not charge.visible and not charge.is_visible_in_tree(), "removed actor returns to the reserve clear")
	var reused: CreatureBall = game._spawn_ball(uid)
	check(reused == attacker and reused._element_fx == charge and not charge.visible, "reserve reuses the same inactive attack effect")
	if reused == attacker:
		await check_teardown()


func check_teardown() -> void:
	var attacker := actors[5] if review_stone_tide else actors[0]
	var target := actors[3] if review_stone_tide else actors[5]
	await attacker.open_animated(false)
	stage(attacker, target)
	var slot: int = game.director.effects._impact_slot
	game.events.push(game.presentation.anim_battle_resolved.bind(result(attacker, target)))
	check(await until(func() -> bool: return attacker._element_fx.visible), "start charge before match release")
	SoundFx.i().strike_impact(target.def.attribute, 0.72)
	check(impact_voice_count(target.def.attribute) == 1, "release test has an active elemental voice")
	game._release_game_resources()
	check(await until(func() -> bool: return not game.events.is_busy()), "released match finishes its contact wait")
	check(game.director.effects._impact_slot == slot and not game.battle_overlay._open and not attacker._element_fx.visible, "released match cannot play stale impact or result")
	check(impact_voice_count() == 0, "released match leaves no elemental audio")


func settle_result() -> bool:
	if not await until(func() -> bool: return game.battle_overlay._open, 4.0):
		return false
	game.battle_overlay._close()
	return await until(func() -> bool: return not game.events.is_busy())


func until(condition: Callable, seconds: float = 2.8) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return condition.call()


func diff_pixels(with_effect: Image, without_effect: Image) -> int:
	var first := with_effect.get_data()
	var second := without_effect.get_data()
	if first.size() != second.size():
		return 0
	var channels := 4 if with_effect.get_format() == Image.FORMAT_RGBA8 else 3
	var changed := 0
	for pixel in range(0, first.size(), channels):
		if absi(first[pixel] - second[pixel]) + absi(first[pixel + 1] - second[pixel + 1]) + absi(first[pixel + 2] - second[pixel + 2]) >= 46:
			changed += 1
	return changed


func capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func save(name: String) -> void:
	var image := await capture()
	check(image.save_png(output.path_join(name + ".png")) == OK, "save " + name)


func finish() -> void:
	if is_instance_valid(game):
		game._release_game_resources()
		game.queue_free()
		await process_frame
	if is_instance_valid(loader):
		loader.queue_free()
		await process_frame
	if is_instance_valid(SoundFx._inst):
		SoundFx._inst.queue_free()
	await process_frame
	await create_timer(0.2, true, false, true).timeout
	print("Creature element effects: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
