extends SceneTree
## Resource/Control contract of all 49 manual HUD decisions; no GLB or GPU claims.
const WINDOW := preload("res://tools/test_window.gd")
const CROPS := preload("res://scenes/ui/creature_portrait_crops.gd")
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
	DeviceSettings.set_style(DeviceSettings.DEVICE)
	DeviceSettings.set_reduce_motion(true)
	CardDB.load_all()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/portraits/hud_crops.json"))
	var decisions: Dictionary = manifest["candidates"]
	check(decisions.size() == 49, "manual manifest accounts for all49 exact IDs")
	check(CreaturePortrait.preload_catalog() == 49, "Boot prepares all49 references")
	check(CROPS.REGIONS.size() == 42 and CreaturePortrait._hud_reference_textures.size() == 42, "only42 reviewed crops are prepared as resource-only cache")
	var portrait := CreaturePortrait.new()
	portrait.size = Vector2(72, 100)
	root.add_child(portrait)
	var own := OpponentPanel.new()
	var opponent := OpponentPanel.new()
	own.configure_side(0)
	opponent.configure_side(1)
	root.add_child(own)
	root.add_child(opponent)
	await process_frame
	var cropped := 0
	var kept := 0
	for definition: CreatureDef in CreatureModels.catalog_defs():
		var id := definition.id
		var key := String(id)
		check(decisions.has(key), "individual decision exists: " + key)
		if not decisions.has(key): continue
		var decision: Dictionary = decisions[key]
		var source := CreaturePortrait.reference_texture(id)
		var presentation := CreaturePortrait.presentation_texture(id)
		var hud := CreaturePortrait.hud_reference_texture(id)
		var expected_path := "res://assets/portraits/creatures/" + key.trim_prefix("creature_") + ".png"
		check(source != null and source.resource_path == expected_path, "exact full-body source remains public reference: " + key)
		check(source.get_size() == Vector2(256, 256), "original runtime dimensions remain256square: " + key)
		check(not String(decision["intent"]).is_empty(), "manual crop/fullbody rationale exists: " + key)
		check(CROPS.REGIONS.has(id) == bool(decision["enabled"]), "generated runtime table follows per-ID decision: " + key)
		if bool(decision["enabled"]):
			cropped += 1
			check(hud is AtlasTexture, "reviewed portrait uses shared AtlasTexture: " + key)
			if hud is AtlasTexture:
				var atlas := hud as AtlasTexture
				var values: Array = decision["region"]
				var expected := Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
				check(atlas.atlas == presentation, "crop samples source-preserving prepared matte: " + key)
				check(atlas.region == expected and CROPS.REGIONS[id] == expected, "runtime region exactly matches manual manifest: " + key)
				check(Rect2(Vector2.ZERO, source.get_size()).encloses(atlas.region) and atlas.region.size.x == atlas.region.size.y, "crop is square and inside original bounds: " + key)
				check(atlas.margin == Rect2() and atlas.filter_clip, "crop has no added pixels and filters inside region: " + key)
				check(atlas.get_size() == expected.size, "resource aspect matches72px square composition: " + key)
		else:
			kept += 1
			check(hud == presentation, "reviewed fullbody choice keeps full prepared silhouette without wrapping: " + key)
		check(CreaturePortrait.hud_reference_texture(id) == hud, "repeat lookup reuses same resource: " + key)
		portrait.set_hud_crop_enabled(false)
		portrait.set_definition(definition, 7)
		check(portrait._fallback.texture == presentation, "default/full-reference consumer retains full prepared silhouette: " + key)
		portrait.set_hud_crop_enabled(true)
		check(portrait._fallback.texture == hud and portrait._reference_texture == source, "small-HUD opt-in selects composition without altering reference: " + key)
		portrait.set_hud_crop_enabled(false)
		check(portrait._fallback.texture == presentation, "turning crop off restores full prepared silhouette immediately: " + key)
		for panel: OpponentPanel in [own, opponent]:
			panel.present(definition, 7, 420)
			check(panel._portrait._hud_crop_enabled and panel._portrait._fallback.texture == hud, "real panel opts into same exact HUD ID on side" + str(panel.player_side) + ": " + key)
			check(panel._portrait._viewport == null and panel._portrait._camera == null and not panel._portrait.is_processing(), "known2D portrait allocates no render world/process on side" + str(panel.player_side) + ": " + key)
	check(cropped == 42 and kept == 7, "42 per-ID crops plus7 deliberate fullbody decisions cover49")
	check(CreaturePortrait.reference_texture(&"creature_unknown") == null and CreaturePortrait.hud_reference_texture(&"creature_unknown") == null, "unknown ID cannot borrow another exact portrait")
	var unknown := CreatureDef.make(&"creature_unknown", "Unknown", Attr.A.FIRE, 100, Color.RED)
	unknown.species = &"missing_species"
	portrait.set_hud_crop_enabled(true)
	portrait.set_definition(unknown, 8)
	check(portrait._fallback.texture != null and portrait._reference_texture == null and portrait._viewport == null, "unknown ID retains honest icon fallback without a borrowed portrait")
	portrait.reset()
	check(portrait._fallback.texture == null and not portrait._fallback.visible and portrait._viewport == null, "reset removes crop/fallback and creates no viewport")
	check(portrait._fallback.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and portrait._fallback.mouse_filter == Control.MOUSE_FILTER_IGNORE, "72px composition preserves aspect and cannot intercept input")
	check(Engine.max_fps == 60, "standard wrapper holds60FPS")
	var report := FileAccess.open(output.path_join("portrait-crop.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "cropped": cropped, "kept_fullbody": kept, "display": DisplayServer.get_name(), "gpu_acceptance": false}, "\t"))
	report.close()
	portrait.queue_free()
	own.queue_free()
	opponent.queue_free()
	await process_frame
	await process_frame
	print("portrait-crop: %d checks, %d failures; 42 manual crops / 7 fullbody; resource/Controls only" % [checks, failures])
	quit(0 if failures == 0 else 1)
