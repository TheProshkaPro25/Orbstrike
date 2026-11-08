extends SceneTree
## Narrow GPU probe: actual hidden HUD/editor consumers, resume and actor replacement.
class CountedPortrait extends FighterPortrait:
	var ticks := 0
	func _process(delta: float) -> void:
		ticks += 1
		super._process(delta)
class Counter extends Node:
	var ticks := 0
	func _process(_delta: float) -> void: ticks += 1
var checks := 0
var failures := 0
var baseline := OS.get_environment("SFERY_PORTRAIT_BASELINE") == "1"
var output := "res://build/checks/portrait-visibility"
var rows: Array = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)
func frames(count: int) -> void:
	for frame in count: await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func sample(name: String, vp: SubViewport, counter: Node, hidden: bool) -> void:
	await frames(3)
	var before: int = counter.ticks
	var image := vp.get_texture().get_image().get_data()
	var camera := vp.get_camera_3d()
	var transform := camera.transform
	camera.position.x += 1.25
	var draw_calls := 0
	for frame in 12:
		await frames(1)
		draw_calls += vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var ticks: int = counter.ticks - before
	var frozen := image == vp.get_texture().get_image().get_data()
	rows.append({"name":name,"mode":vp.render_target_update_mode,"ticks_12_samples":ticks,"cached_draw_calls_12_samples":draw_calls,"image_frozen":frozen})
	print("PORTRAIT_SAMPLE ", rows.back())
	if not baseline or not hidden:
		check(ticks == 0 if hidden else ticks > 0, name + " processing")
		check(vp.render_target_update_mode == SubViewport.UPDATE_DISABLED if hidden else vp.render_target_update_mode != SubViewport.UPDATE_DISABLED, name + " render update")
		check(frozen if hidden else not frozen, name + " actual viewport pixels")
	camera.transform = transform
	await frames(2)
func run() -> void:
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	if baseline: output = output.path_join("baseline")
	else: output = output.path_join("after")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_size(root.get_viewport_rid(),1280,720)
	var world := Node3D.new()
	root.add_child(world)
	var fighter := VrmFighter.new()
	world.add_child(fighter)
	fighter.apply_profile(PlayerProfile.DEFAULT)
	var hud := HudUI.new()
	var hud_layer := CanvasLayer.new()
	root.add_child(hud_layer)
	hud_layer.add_child(hud)
	hud.setup_plates([Color.RED],[Color.BLUE])
	var portrait := CountedPortrait.new()
	root.add_child(portrait)
	portrait.bind(fighter,0)
	hud.set_portrait(0,portrait.get_texture())
	if portrait.has_method("watch_consumer"): portrait.call("watch_consumer",hud._plates[0]._portrait,hud)
	await sample("hud-visible",portrait,portrait,false)
	capture("hud-visible")
	hud.hide()
	var fighter_time := fighter.idle_time
	await sample("hud-hidden",portrait,portrait,true)
	check(fighter.idle_time > fighter_time,"hidden portrait keeps shared arena fighter animated")
	portrait.camera.position = Vector3(100,100,100)
	hud.show()
	if not baseline: check(portrait.camera.position.distance_to(fighter.position) < 3.0,"first resume updates portrait camera synchronously")
	await sample("hud-resume",portrait,portrait,false)
	hud_layer.hide()
	await sample("hud-layer-hidden",portrait,portrait,true)
	hud_layer.show()
	await sample("hud-layer-resume",portrait,portrait,false)
	hud.set_battle_mode(true)
	await sample("battle-covered",portrait,portrait,true)
	hud.set_battle_mode(false)
	await sample("battle-resume",portrait,portrait,false)
	fighter.apply_profile(PlayerProfile.npc_profile(3))
	portrait.bind(fighter,0)
	await sample("rebound-fighter",portrait,portrait,false)
	capture("hud-rebound")
	hud._plates[0]._portrait.hide()
	await sample("consumer-hidden",portrait,portrait,true)
	var replacement := VrmFighter.new()
	world.add_child(replacement)
	replacement.apply_profile(PlayerProfile.npc_profile(5))
	replacement.position.x = 3.0
	fighter.hide()
	portrait.bind(replacement,0)
	await sample("rebind-hidden",portrait,portrait,true)
	hud.set_portrait(0,portrait.get_texture())
	if not baseline: check(portrait.camera.position.distance_to(portrait._standby_actor.position) < 3.0,"rebound standby camera is ready before first draw")
	await sample("consumer-resume",portrait,portrait,false)
	check(portrait.get_texture().get_image().get_used_rect().size.x > 30,"replacement actor renders on resumed viewport")
	capture("hud-replacement-resume")
	portrait.queue_free()
	hud_layer.queue_free()
	world.queue_free()
	await frames(4)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(host)
	var editor := CharacterEditor.new()
	host.add_child(editor)
	var probe := Counter.new()
	editor.viewport.add_child(probe)
	await sample("editor-visible",editor.viewport,probe,false)
	capture("editor-visible")
	layer.hide()
	await sample("editor-layer-hidden",editor.viewport,probe,true)
	layer.show()
	await sample("editor-layer-resume",editor.viewport,probe,false)
	editor.preview_repeat = false
	var time := editor.preview_time
	host.hide()
	await sample("editor-parent-hidden",editor.viewport,probe,true)
	if not baseline: check(editor.preview_time == time,"hidden editor motion time preserved")
	editor.select_model(1)
	await sample("editor-model-hidden",editor.viewport,probe,true)
	host.show()
	await sample("editor-resume-model",editor.viewport,probe,false)
	capture("editor-resume-model")
	editor._set_playing(false)
	host.hide()
	await frames(3)
	host.show()
	await frames(3)
	check(not editor.preview_playing and not editor.preview_repeat,"paused editor and repeat choice stay unchanged on resume")
	check(not editor.avatar.is_processing(),"editor fighter keeps manual sampling")
	editor._close()
	await frames(4)
	check(not is_instance_valid(editor),"editor close frees viewport")
	var legacy := LegacyCharacterEditor.new()
	host.add_child(legacy)
	probe = Counter.new()
	legacy.viewport.add_child(probe)
	await sample("legacy-visible",legacy.viewport,probe,false)
	legacy._open_vrm_preview()
	await sample("legacy-covered",legacy.viewport,probe,true)
	var view := legacy.vrm_preview
	var vrm_probe := Counter.new()
	view.viewport.add_child(vrm_probe)
	await sample("vrm-visible",view.viewport,vrm_probe,false)
	view.hide()
	await sample("vrm-hidden",view.viewport,vrm_probe,true)
	view.select_model(1)
	view.show()
	await sample("vrm-resume-model",view.viewport,vrm_probe,false)
	capture("vrm-resume-model")
	view.close()
	await sample("legacy-resume",legacy.viewport,probe,false)
	legacy._close()
	await frames(4)
	layer.queue_free()
	await frames(4)
	var file := FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"baseline":baseline,"checks":checks,"failures":failures,"samples":rows},"\t"))
	file.close()
	print("Portrait visibility: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
