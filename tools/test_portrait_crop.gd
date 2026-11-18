extends SceneTree
## The small reveal and battle panels both fit the full catalog render.
const WINDOW := preload("res://tools/test_window.gd")
var checks := 0
var failures := 0
var output := "res://build/checks/presentation/portrait-crop"


func _initialize() -> void:
	if not has_meta("sfery_background_draw"): WINDOW.background(self)
	_run.call_deferred()


func _finalize() -> void:
	WINDOW.finish(self)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	DeviceSettings.settings_path = output.path_join("device-settings.cfg")
	DeviceSettings.reload_settings()
	DeviceSettings.set_reduce_motion(true)
	CardDB.load_all()
	var catalog := CreatureModels.catalog_defs()
	check(CreaturePortrait.preload_catalog() == catalog.size(), "one portrait for every catalog definition")
	check(CreaturePortrait._background_materials.size() == Attr.COUNT, "Boot can warm all six backdrops")

	var own := OpponentPanel.new()
	var opponent := OpponentPanel.new()
	own.configure_side(0)
	opponent.configure_side(1)
	root.add_child(own)
	root.add_child(opponent)
	await process_frame
	for definition: CreatureDef in catalog:
		var id := definition.id
		var key := String(id)
		var source := CreaturePortrait.presentation_texture(id)
		var expected_path := "res://assets/portraits/creatures/" + key.trim_prefix("creature_") + ".png"
		check(source != null and source.resource_path == expected_path, "exact model render: " + key)
		check(source is CompressedTexture2D and source.get_size() == Vector2(512, 512),
			"imported 512px square render: " + key)
		for panel: OpponentPanel in [own, opponent]:
			panel.present(definition, 7, 420)
			for mode in ["reveal", "battle"]:
				panel.show_context(mode)
				var portrait := panel._portrait
				check(portrait._fallback.texture == source and portrait._fallback.visible
					and portrait._fallback.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					and portrait._fallback.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
					"%s fits the same full silhouette for side %d: %s" % [mode, panel.player_side, key])
				check(portrait._viewport == null and portrait._camera == null and not portrait.is_processing(),
					"%s keeps the asset static for side %d: %s" % [mode, panel.player_side, key])
		check(CreaturePortrait.presentation_texture(id) == source, "warm lookup reuses the import: " + key)

	var portrait := own._portrait
	check(CreaturePortrait.presentation_texture(&"creature_unknown") == null, "unknown ID cannot borrow another exact portrait")
	var unknown := CreatureDef.make(&"creature_unknown", "Unknown", Attr.A.FIRE, 100, Color.RED)
	unknown.species = &"missing_species"
	portrait.set_definition(unknown, 8)
	check(portrait._fallback.texture != null and portrait._reference_texture == null and portrait._viewport == null,
		"unknown ID retains the icon fallback")
	portrait.reset()
	check(portrait._fallback.texture == null and not portrait._fallback.visible and portrait._viewport == null,
		"reset removes the previous texture")
	check(portrait._fallback.mouse_filter == Control.MOUSE_FILTER_IGNORE, "portrait cannot intercept input")
	check(Engine.max_fps == 60, "standard wrapper holds 60 FPS")

	var report := FileAccess.open(output.path_join("portrait-crop.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "catalog_count": catalog.size()}, "\t"))
	report.close()
	own.queue_free()
	opponent.queue_free()
	await process_frame
	await process_frame
	print("portrait-crop: %d checks, %d failures; %d full model portraits" % [checks, failures, catalog.size()])
	quit(0 if failures == 0 else 1)
