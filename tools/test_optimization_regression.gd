extends SceneTree
## Actual tooltip geometry and card UI, deterministic A/B CPU work and built-in GPU counters.
const Metrics := preload("res://scenes/performance_metrics.gd")
class GameFixture extends "res://scenes/main.gd":
	func _ready() -> void: pass
	func _exit_tree() -> void: pass
class ArenaFixture extends Arena:
	func _ready() -> void: pass
class BallFixture extends CreatureBall:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func figure_height() -> float: return 2.0
	func figure_size() -> float: return 2.0
var checks := 0
var failures := 0
var out := "res://build/checks/presentation/optimization"
var report := {}
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: " + message)
func frames(count: int = 3) -> void:
	for i in count: await process_frame
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	DeviceSettings.settings_path = out.path_join("isolated-settings.cfg")
	DeviceSettings.reload_settings()
	CardDB.load_all()
	Metrics.install()
	check(Performance.has_custom_monitor("orbstrike/hover_snapshots"), "built-in custom diagnostics installed")
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var game := GameFixture.new()
	root.add_child(game)
	game.hud = HudUI.new()
	game.team_menu = TeamMenu.new()
	game.team_menu.hide()
	game.events = EventPlayer.new()
	game.add_child(game.events)
	game.director = ArenaDirector.new()
	game.add_child(game.director)
	game.arena = ArenaFixture.new()
	game.add_child(game.arena)
	game.cam = CameraRig.new()
	game.add_child(game.cam)
	game.cam.set_process(false)
	game.cam.position = Vector3(0,52,63)
	game.cam.look_at(Vector3.ZERO)
	game.ctrl = MatchController.new(CardDB.preset_deck(0),CardDB.preset_deck(0),918)
	game.ctrl.start()
	game._index_creatures()
	var mouse := game.cam.unproject_position(game.arena.slot_position(0))
	var expected := game._tip_at_uncached(mouse)
	check(not expected.is_empty(), "fixture hits real projected setup slot")
	var snapshots := Metrics.value("hover_snapshots")
	var first := game._tip_at(mouse)
	for i in 120: check(game._tip_at(mouse) == expected, "cached tooltip matches uncached %d" % i)
	check(Metrics.value("hover_snapshots") == snapshots + 1, "120 stationary queries create one state snapshot")
	var begin := Time.get_ticks_usec()
	for i in 500: game._tip_at_uncached(mouse)
	report.uncached_500_usec = Time.get_ticks_usec() - begin
	begin = Time.get_ticks_usec()
	for i in 500: game._tip_at(mouse)
	report.cached_500_usec = Time.get_ticks_usec() - begin
	# Continuous overview drift still reuses its rules snapshot; geometry stays exact.
	snapshots = Metrics.value("hover_snapshots")
	for i in 20:
		game.cam.position.x += .1
		check(game._tip_at(mouse) == game._tip_at_uncached(mouse), "moving camera invalidates geometry")
	check(Metrics.value("hover_snapshots") == snapshots, "camera drift does not duplicate MatchState")
	game.cam.fov += 2
	check(game._tip_at(mouse) == game._tip_at_uncached(mouse), "FOV invalidates projection")
	game.cam.h_offset = .8
	game.cam.v_offset = .4
	check(game._tip_at(mouse) == game._tip_at_uncached(mouse), "camera shake offsets invalidate geometry")
	root.size = Vector2i(960,540)
	await frames()
	check(game._tip_at(mouse) == game._tip_at_uncached(mouse), "viewport resize invalidates projection")
	var ball := BallFixture.new()
	game.add_child(ball)
	ball.position = Vector3(0,.35,0)
	game.balls[0] = ball
	mouse = game.cam.unproject_position(Vector3(0,1,0))
	check(game._tip_at(mouse) == game._tip_at_uncached(mouse), "new actor invalidates geometry")
	ball.position.x += 9
	check(game._tip_at(mouse) == game._tip_at_uncached(mouse), "moving actor invalidates geometry")
	ball.hide()
	check(game._tip_at(mouse) == game._tip_at_uncached(mouse), "hidden actor invalidates geometry")
	var slot: int = game.ctrl.legal_setup_slots()[0]
	check(game.ctrl.place_arena_card(0,game.ctrl.get_view(0).players[0].arena_hand[0],slot) == OK, "real controller mutation")
	check(game._tip_at(mouse) == game._tip_at_uncached(mouse), "rule action invalidates snapshot and text")
	snapshots = Metrics.value("hover_snapshots")
	DeviceSettings.set_style(DeviceSettings.CLASSIC if DeviceSettings.is_device() else DeviceSettings.DEVICE)
	check(game._tip_at(mouse) == game._tip_at_uncached(mouse), "style invalidates text")
	check(Metrics.value("hover_snapshots") == snapshots + 1, "style revision refreshes cached text")
	game.hud._battle = true
	check(game._tip_at(mouse).is_empty(), "battle guard never returns cached field tooltip")
	game.hud._battle = false
	game.ctrl = MatchController.new(CardDB.preset_deck(1),CardDB.preset_deck(1),919)
	game.ctrl.start()
	check(game._tip_at(mouse) == game._tip_at_uncached(mouse), "controller replacement invalidates view")
	var preview := CreaturePreview.new()
	preview.position = Vector2(240,10)
	preview.size = Vector2(420,520)
	root.add_child(preview)
	for id in [CardDB.arena_ids()[0],CardDB.ability_ids()[0]]:
		preview.show_card(CardDB.card(id))
		await frames()
		check(preview._card_box.get_child_count() == 0 and preview._lines.get_child_count() == 0, "no invisible intermediate card or labels")
		check(preview._full_card_scroll.visible and preview._full_card.card_id == id, "full card remains visible and correct")
		check(preview._full_card.is_visible_in_tree() and preview._full_card.size.x > 200 and preview._full_card.size.y > 200, "full card has real visible layout")
	check(not StartupCatalog.resource_paths().has("res://assets/avatars/fighter_mpfb.glb"), "normal startup excludes legacy avatar")
	check(StartupCatalog.resource_paths().has("res://assets/avatars/vrm/Vivi.vrm"), "current wardrobe material source retained")
	Metrics.measure_render_time(root,true)
	await frames(12)
	report.metrics = Metrics.snapshot(root)
	Metrics.measure_render_time(root,false)
	if DisplayServer.get_name() != "headless":
		check(report.metrics.render_gpu_ms > 0, "GPU timing is measured, not inferred from FPS")
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(out.path_join("full-card.png")) == OK, "current full-card PNG")
	check(Engine.max_fps == 60, "test remains 60FPS")
	game.hud.free()
	game.team_menu.free()
	game.queue_free()
	preview.queue_free()
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(5)
	report.checks = checks
	report.failures = failures
	var file := FileAccess.open(out.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("OPTIMIZATION ", checks, "/", failures, " ", JSON.stringify(report))
	quit(1 if failures else 0)
