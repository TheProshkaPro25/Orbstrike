extends SceneTree
## Verify imported alpha and safe silhouette bounds for every model portrait.
const WINDOW := preload("res://tools/test_window.gd")
const MATTE := preload("res://scenes/ui/portrait_matte.gd")
const MIN_MARGIN := 1
var _out := "res://build/checks/portrait-background"
var _checks := 0
var _failures := 0


func _initialize() -> void:
	if not has_meta("sfery_background_draw"): WINDOW.background(self)
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	CardDB.load_all()
	var catalog := CreatureModels.catalog_defs()
	var rows := {}
	var portrait := CreaturePortrait.new()
	root.add_child(portrait)
	await process_frame
	for definition in catalog:
		var texture := CreaturePortrait.presentation_texture(definition.id)
		_check(texture != null, "existing render " + String(definition.id))
		if texture == null:
			continue
		var image := texture.get_image()
		_check(image.has_mipmaps(), "each rendered portrait has minification levels " + String(definition.id))
		image.clear_mipmaps()
		image.convert(Image.FORMAT_RGBA8)
		var visible := image.get_used_rect()
		var inner := Rect2i(Vector2i.ONE * MIN_MARGIN, image.get_size() - Vector2i.ONE * (2 * MIN_MARGIN))
		var bytes := image.get_data()
		var opaque := 0
		var translucent := 0
		var transparent := 0
		for offset in range(3, bytes.size(), 4):
			match bytes[offset]:
				0: transparent += 1
				255: opaque += 1
				_: translucent += 1
		var id := String(definition.id)
		_check(visible.has_area() and inner.encloses(visible), "complete silhouette fits inside its texture " + id)
		_check(transparent > 0 and translucent > 0 and opaque > 0, "transparent background, soft edges and opaque interior " + id)
		portrait.set_definition(definition)
		portrait.set_battle_style(true)
		_check(portrait._fallback.texture == texture, "battle uses the imported alpha " + id)
		portrait.set_battle_style(false)
		_check(portrait._fallback.texture == texture, "reveal uses the same imported alpha " + id)
		rows[id] = {"bounds": [visible.position.x, visible.position.y, visible.size.x, visible.size.y],
			"transparent": transparent, "translucent": translucent, "opaque": opaque}
	_check(MATTE.generation_count == 0, "warm presentation never segments a model render")
	FileAccess.open(_out.path_join("summary.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "failures": _failures, "catalog_count": catalog.size(), "portraits": rows}, "  "))
	print("portrait-background: %d checks, %d failures; %d alpha silhouettes" % [_checks, _failures, rows.size()])
	quit(1 if _failures else 0)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: " + label)
