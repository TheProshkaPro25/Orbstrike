extends SceneTree
## Render catalog figures with their in-game materials and an idle pose.
## Run with --windowed --position -20000,-20000, then pass an output directory
## and optional comma-separated creature IDs after --.
const WINDOW := preload("res://tools/test_window.gd")
const CAPTURE_SIZE := 1024
const OUTPUT_SIZE := 512
const FIGURE_SIZE := 470
const STUDIO_ANGLES := {
	&"dragnar": Vector2(-27, 10),
	&"klykar": Vector2(31, 12),
	&"grifalon": Vector2(24, 8),
	&"kolossar": Vector2(18, 6),
	&"rogozhuk": Vector2(27, 15),
	&"levian": Vector2(-28, 10),
	&"ratnik": Vector2(-21, 6),
	&"gorgul": Vector2(22, 9),
	&"likorez": Vector2(-16, 6),
}

var _viewport: SubViewport
var _camera: Camera3D


func _initialize() -> void:
	WINDOW.background(self)
	_run.call_deferred()


func _finalize() -> void:
	WINDOW.finish(self)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		printerr("A graphics session and output directory are required.")
		quit(1)
		return
	var output: String = args[0]
	var ids := args[1].split(",", false) if args.size() > 1 else PackedStringArray()
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		printerr("Cannot create portrait directory: ", output)
		quit(1)
		return
	_create_studio()
	CardDB.load_all()
	var rendered := 0
	var failed := 0
	for definition: CreatureDef in CreatureModels.catalog_defs():
		var selected := STUDIO_ANGLES.has(definition.species) if ids.is_empty() else ids.has(String(definition.id))
		if not selected:
			continue
		if await _capture(definition, output):
			rendered += 1
		else:
			failed += 1
	var expected := rendered + failed if ids.is_empty() else ids.size()
	print("CREATURE PORTRAITS ", rendered, "/", expected, " failed=", failed)
	quit(0 if failed == 0 and rendered == expected else 1)


func _create_studio() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(CAPTURE_SIZE, CAPTURE_SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.02
	_camera.far = 200.0
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.89, 0.93, 1.0)
	environment.ambient_light_energy = 0.29
	_camera.environment = environment
	_viewport.add_child(_camera)
	_camera.make_current()
	_add_light(Vector3(-3, 5, 4), Color(1.0, 0.93, 0.87), 1.58)
	_add_light(Vector3(4, 1, 3), Color(0.81, 0.9, 1.0), 0.48)
	_add_light(Vector3(1, 4, -5), Color(0.93, 0.94, 1.0), 1.2)


func _add_light(direction: Vector3, color: Color, energy: float) -> void:
	var light := DirectionalLight3D.new()
	light.light_color = color
	light.light_energy = energy
	_viewport.add_child(light)
	light.position = direction
	light.look_at(Vector3.ZERO)


func _capture(definition: CreatureDef, output: String) -> bool:
	var model := CreatureModels.build(definition)
	if model == null:
		printerr("Cannot build portrait figure: ", definition.id)
		return false
	var actor := CreatureAnim.new()
	_viewport.add_child(actor)
	actor.set_process(false)
	actor._phase = 0.0
	actor.set_model(model, definition)
	if actor._player != null and actor._player.has_animation(&"idle"):
		actor._player.seek(0.0, true)

	var bounds := CreatureModels.world_aabb(model)
	var center := bounds.get_center()
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var angles: Vector2 = STUDIO_ANGLES.get(definition.species, Vector2(23, 8))
	var yaw := deg_to_rad(angles.x)
	var elevation := deg_to_rad(angles.y)
	var direction := Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation))
	_camera.size = 1.75 * extent
	_camera.position = center + direction * (5.0 * extent)
	_camera.look_at(center)
	var source: Image
	var used := Rect2i()
	var frame := Rect2i(2, 2, CAPTURE_SIZE - 4, CAPTURE_SIZE - 4)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for attempt in 3:
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		source = _viewport.get_texture().get_image()
		used = source.get_used_rect()
		if frame.encloses(used):
			break
		# Imported skinned bounds can understate an authored idle pose.
		_camera.size *= 1.5
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	await process_frame
	ModelLifetime.release(actor, self)
	CreatureModels.clear()
	if used.size.x < 2 or used.size.y < 2 or not frame.encloses(used):
		printerr("Missing or cropped silhouette: ", definition.id, " ", used)
		return false
	# Centre the complete alpha silhouette in a square texture, leaving 21 px
	# around the longest dimension for the rounded battle frame.
	var scale := float(FIGURE_SIZE) / maxi(used.size.x, used.size.y)
	var figure := source.get_region(used)
	figure.convert(Image.FORMAT_RGBA8)
	figure.resize(maxi(1, roundi(used.size.x * scale)), maxi(1, roundi(used.size.y * scale)), Image.INTERPOLATE_LANCZOS)
	figure = _straight_alpha(figure)
	var portrait := Image.create(OUTPUT_SIZE, OUTPUT_SIZE, false, Image.FORMAT_RGBA8)
	portrait.blit_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), (Vector2i(OUTPUT_SIZE, OUTPUT_SIZE) - figure.get_size()) / 2)
	var path := output.path_join(String(definition.id).trim_prefix("creature_") + ".png")
	var error := portrait.save_png(path)
	if error != OK:
		printerr("Cannot save ", path, " error=", error)
	else:
		print("RENDER ", definition.id, " ", portrait.get_used_rect())
	return error == OK


## Transparent 3D targets store coverage in both colour and alpha. Keep that
## representation through downsampling, then write ordinary straight-alpha PNG.
func _straight_alpha(image: Image) -> Image:
	var pixels := image.get_data()
	for offset in range(0, pixels.size(), 4):
		var alpha := pixels[offset + 3]
		if alpha == 255:
			continue
		for channel in 3:
			pixels[offset + channel] = mini(255, roundi(pixels[offset + channel] * 255.0 / alpha)) if alpha > 0 else 0
	return Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, pixels)
