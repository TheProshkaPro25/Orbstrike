extends SceneTree
## Focused lifecycle regression: a result overlay can open AFTER disconnection.
## Minimal real controls/EventPlayer, no Boot, art models, catalog or network needed.
const Online = preload("res://scenes/online/online_game.gd")
const Client = preload("res://network/online_client.gd")
var checks := 0
var failures := 0
var action_started := false
var action_finished := false
var opened_late := false
class MinimalTeam extends TeamMenu:
	func _ready() -> void:
		_preview = CreaturePreview.new()
		add_child(_preview)
class MinimalArena extends Arena:
	func _ready() -> void: pass
class CleanupFixture extends Online:
	func _ready() -> void:
		_previous_time_scale = Engine.time_scale
		world = Node3D.new()
		add_child(world)
		arena = MinimalArena.new()
		world.add_child(arena)
		ui_layer = CanvasLayer.new()
		add_child(ui_layer)
		client = Client.new()
		add_child(client)
		events = EventPlayer.new()
		add_child(events)
		director = ArenaDirector.new()
		director.state = presentation.state
		add_child(director)
		for row in [["hud",HudUI.new()],["setup_panel",SetupPanel.new()],["ability_panel",AbilityPanel.new()],["game_over_ui",GameOverUI.new()],["battle_overlay",BattleOverlay.new()],["team_menu",MinimalTeam.new()],["battle_hud",BattleHud.new()]]:
			set(row[0],row[1])
			ui_layer.add_child(row[1])
		_build_connection_ui()
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
	var game := CleanupFixture.new()
	root.add_child(game)
	game.client.verified = true
	game._match_ready = true
	game._gate_pick = {"card":"old","slot":0}
	game.snapshot = {"old":true}
	game.game_over_ui.set_restart_text("Ждём согласия соперника…")
	game.events.push(func() -> void:
		action_started = true
		await create_timer(.15).timeout
		var result := BattleResult.new()
		result.attacker_uid = 0
		result.defender_uid = 3
		result.winner_uid = 0
		result.loser_uid = 3
		result.powers = [410,390]
		opened_late = true
		await game.battle_overlay.show_result(result)
		action_finished = true)
	for frame in 10:
		if action_started: break
		await process_frame
	check(action_started and game.events.is_busy(),"director action is running before disconnect")
	check(not game.battle_overlay._open,"overlay has not opened yet")
	game._disconnected("fixture disconnect")
	check(game._connect_button.disabled and game._cleaning_match,"reconnect disabled while action owns actors")
	check(not game.client.verified,"old socket cannot create a room during cleanup")
	for frame in 180:
		await process_frame
		if not game._cleaning_match: break
	check(opened_late,"late real result overlay was opened")
	check(action_finished and not game.events.is_busy(),"late overlay closed and action drained")
	check(not game._cleaning_match and not game._connect_button.disabled,"reconnect enabled after cleanup")
	check(not game._match_ready and game.snapshot.is_empty(),"old match state cleared before reconnect")
	check(game._gate_pick.is_empty(),"pending combination cleared")
	check(not game.battle_overlay._open,"no result overlay left open")
	check(game.game_over_ui._restart_button.text == "Реванш","rematch label restored")
	check(game._connection_panel.visible and game._connection_status.text == "fixture disconnect","disconnect reason preserved")
	check(game.balls.is_empty() and game.fighters.is_empty() and game.card_nodes.is_empty(),"cleanup leaves no match actor references")
	check(Engine.max_fps == 60,"60FPS limit preserved")
	game.queue_free()
	for frame in 4: await process_frame
	print("ONLINE DISCONNECT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
