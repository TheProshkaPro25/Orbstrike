extends SceneTree

const TestWindow := preload("res://tools/test_window.gd")
const Showcase := preload("res://tools/vfx_showcase/showcase.tscn")
const ShowcaseScript := preload("res://tools/vfx_showcase/showcase.gd")
const Effects := preload("res://tools/vfx_showcase/preview_effects.gd")

var _failures := 0


func _initialize() -> void:
	TestWindow.background(self)
	_run.call_deferred()


func _finalize() -> void:
	TestWindow.finish(self)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var own_only := args.has("--own-only")
	args.erase("--own-only")
	var out := args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://build/checks/vfx-showcase")
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("FAIL: capture requires a background Forward+ viewport")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		push_error("FAIL: cannot create capture output directory")
		quit(1)
		return
	root.size = Vector2i(1200, 675)
	var showcase := Showcase.instantiate() as ShowcaseScript
	showcase.capture_mode = true
	root.add_child(showcase)
	if not own_only:
		await _capture(showcase, 0, 0, 0.45, out.path_join("01-effects-lab.png"))
		await _capture(showcase, 1, 0, 0.22, out.path_join("02-reeboo.png"))
		await _save(out.path_join("02-reeboo-pickup.png"), 0.66)
		await _capture(showcase, 2, 0, 0.18, out.path_join("03-fire-impact.png"))
		await _save(out.path_join("03-fire-impact-smoke.png"), 0.32)
		for index in Effects.TRAIL_NAMES.size():
			var element: String = Effects.TRAIL_NAMES[index]
			await _capture(showcase, 3, index, 1.27, out.path_join("04-trail-%02d-%s.png" % [index + 1, element.to_lower()]))
			_expect(showcase.trail_has_geometry(), element + " ribbon generated visible geometry")
			_expect(showcase.trail_has_audio(), element + " trail has original looping audio resource")
		await _capture(showcase, 4, 0, 0.29, out.path_join("05-kenney.png"))
	for index in Effects.TRAIL_NAMES.size():
		var element: String = Effects.TRAIL_NAMES[index]
		await _capture(showcase, 5, index, 1.27, out.path_join("orbstrike-%02d-%s.png" % [index + 1, element.to_lower()]))
		_expect(showcase.trail_has_geometry(), "Orbstrike " + element + " generated visible geometry")
	_expect(Engine.max_fps == 60 and root.unfocusable and root.mode == Window.MODE_MINIMIZED, "60 FPS minimized offscreen test")
	showcase.queue_free()
	await process_frame
	print("VFX showcase: %d failures" % _failures)
	quit(1 if _failures else 0)


func _capture(showcase: ShowcaseScript, section: int, variant: int, seconds: float, file: String) -> void:
	showcase.show_sample(section, variant)
	await _save(file, seconds)


func _save(file: String, seconds: float) -> void:
	await create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_expect(image != null and image.save_png(file) == OK, "saved " + file.get_file())


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
