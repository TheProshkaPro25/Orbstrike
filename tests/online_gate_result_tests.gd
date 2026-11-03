extends SceneTree
## Final rule snapshots remove a gate; its visual must survive result confirmation.
const Cleanup = preload("res://tests/online_disconnect_tests.gd")
const Codec = preload("res://network/state_codec.gd")
const View = preload("res://network/online_view.gd")
var checks := 0
var failures := 0
class ObserveDirector extends ArenaDirector:
	var present_at_result := false
	var present_during_result := false
	func battle_resolved(result: BattleResult) -> void:
		present_at_result = game.card_nodes.has(result.slot) and game.card_nodes[result.slot].is_inside_tree()
		await get_tree().create_timer(.05).timeout
		present_during_result = game.card_nodes.has(result.slot) and not game.card_nodes[result.slot].is_queued_for_deletion()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	call_deferred("run")
func run() -> void:
	var game := Cleanup.CleanupFixture.new()
	root.add_child(game)
	game.ctrl = View.new()
	var view := game.ctrl.get_view(0)
	view.phase = MatchController.Phase.SETUP
	view.active_player = 1
	view.turn = 2
	game._match_ready = true
	game._index_creatures()
	game.hud.setup_plates([Color.BLUE,Color.BLUE,Color.BLUE],[Color.RED,Color.RED,Color.RED],[[0,0,0],[1,1,1]])
	game.cam = CameraRig.new()
	game.world.add_child(game.cam)
	game.director.queue_free()
	var director := ObserveDirector.new()
	director.game = game
	game.add_child(director)
	game.director = director
	game._battle_key = "already introduced"
	for uid in range(6):
		var ball := CreatureBall.new()
		ball.uid = uid
		game.world.add_child(ball)
		ball.freeze_at(Vector3(0,.4,0))
		ball._open = true
		ball._figure.show()
		game.balls[uid] = ball
	var card := ArenaCardNode.new()
	game.world.add_child(card)
	card.set_field_surface(true)
	game.card_nodes[0] = card
	var result := BattleResult.new()
	result.slot = 0
	result.attacker_uid = 0
	result.defender_uid = 3
	result.winner_uid = 0
	result.loser_uid = 3
	result.powers = [410,390]
	view.creatures[3].alive = false
	var snapshot := {"player":0,"view":Codec.encode_view(view),"battle_serial":1,"last_battle":Codec.preview(result),"selected_uid":-1,"busy":false,"preview":{},"winner":-2,"legal":{},"reason":""}
	check(not view.slots[0].has_card and game.card_nodes.has(0),"final rules removed gate while prior presentation still has it")
	await game._apply_snapshot(JSON.parse_string(JSON.stringify(snapshot)))
	check(director.present_at_result,"gate exists when result animation starts")
	check(director.present_during_result,"gate remains throughout result confirmation")
	check(not game.card_nodes.has(0),"gate removed from scene registry after confirmation")
	check(card.is_queued_for_deletion(),"visual gate released after result")
	check(card._field_body.collision_layer == 0,"removed gate physical surface disabled")
	check(game._last_battle_serial == 1,"public result processed once")
	check(Engine.max_fps == 60,"60FPS cap preserved")
	game.game_over_ui.show_result(0,"fixture",{"summary_only":true,"alive":[3,0],"captures":[2,1],"turns":8})
	var labels: Array = game.game_over_ui._table.get_children().map(func(node): return node.text)
	check(not labels.has("Боёв выиграно") and not labels.has("Карт способностей"),"online summary hides unavailable counters")
	check(labels.has("Существ осталось") and labels.has("Ворот захвачено") and labels.has("Ходов в матче"),"online summary retains observed state facts")
	check(not game.game_over_ui._battle_title.visible,"online summary hides unavailable battle history")
	game.game_over_ui.show_result(0,"fixture",{"alive":[3,0],"captures":[2,1],"turns":8,"wins":[3,0],"abilities":[2,1]})
	labels = game.game_over_ui._table.get_children().map(func(node): return node.text)
	check(labels.has("Боёв выиграно") and labels.has("Карт способностей"),"ordinary match retains its recorded counters")
	check(game.game_over_ui._battle_title.visible,"ordinary match retains battle history heading")
	for frame in 3: await process_frame
	# Frozen replay bodies have no physics velocity. Their camera must derive
	# motion from recorded transforms and use the server's mirrored owner-one path.
	var flight := {"uid":3,"owner":1,"slot":-1,"duration":.05,"samples":[[0,.36,-34.5,0,0,0,1],[0,.8,-33.5,0,0,0,1],[0,.8,-32.5,0,0,0,1],[0,.4,-31.5,0,0,0,1]]}
	var replay_finished: Array = [false]
	var replay := func() -> void:
		await game._play_flight(flight)
		replay_finished[0] = true
	replay.call()
	check(game.cam._follow_staged,"recorded replay uses transform-based camera velocity")
	check(game.cam._follow_dir.z > .99,"owner-one camera starts along positive-Z recorded flight")
	for frame in 180:
		await process_frame
		if replay_finished[0]: break
	check(replay_finished[0],"short recorded flight completes")
	check(game.balls[3].global_position.is_equal_approx(Vector3(0,.4,-31.5)),"camera change preserves exact last recorded position")
	game.queue_free()
	for frame in 5: await process_frame
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	for frame in 4: await process_frame
	print("ONLINE GATE RESULT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
