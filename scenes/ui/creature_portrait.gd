class_name CreaturePortrait
extends Control
## Точный 2D-концепт по ID; при его отсутствии — камера раскрытой резидентной фигуры.
## Нет копии модели, setup или своего мира.
const DEVICE := preload("res://scenes/ui/device_settings.gd")
const ART := preload("res://scenes/ui/card_artwork.gd")
const ELEMENT_ICON := preload("res://scenes/element_icon.gd")
const HUD_CROPS := preload("res://scenes/ui/creature_portrait_crops.gd")
const MATTE := preload("res://scenes/ui/portrait_matte.gd")
const INTERIOR_BACKGROUND := preload("res://scenes/ui/portrait_background_regions.gd")
const BACKDROP := preload("res://scenes/ui/portrait_backdrop.gdshader")
const ELEMENT_BACKDROPS := [Color("c96229"), Color("39a58d"), Color("cfb05f"), Color("97816a"), Color("9560c6"), Color("3686b8")]
const PORTRAIT_LAYER := 1 << 20
const FRAME_INTERVAL := 1.0 / 15.0
## Exact original concept filenames. Preloads share Boot resources and perform no match-time lookup.
const REFERENCE_TEXTURES := {
	&"creature_dragnar_fire": preload("res://assets/portraits/creatures/dragnar_fire.png"),
	&"creature_dragnar_gale": preload("res://assets/portraits/creatures/dragnar_gale.png"),
	&"creature_dragnar_light": preload("res://assets/portraits/creatures/dragnar_light.png"),
	&"creature_dragnar_stone": preload("res://assets/portraits/creatures/dragnar_stone.png"),
	&"creature_dragnar_shadow": preload("res://assets/portraits/creatures/dragnar_shadow.png"),
	&"creature_dragnar_tide": preload("res://assets/portraits/creatures/dragnar_tide.png"),
	&"creature_klykar_fire": preload("res://assets/portraits/creatures/klykar_fire.png"),
	&"creature_klykar_gale": preload("res://assets/portraits/creatures/klykar_gale.png"),
	&"creature_klykar_light": preload("res://assets/portraits/creatures/klykar_light.png"),
	&"creature_klykar_stone": preload("res://assets/portraits/creatures/klykar_stone.png"),
	&"creature_klykar_shadow": preload("res://assets/portraits/creatures/klykar_shadow.png"),
	&"creature_klykar_tide": preload("res://assets/portraits/creatures/klykar_tide.png"),
	&"creature_grifalon_fire": preload("res://assets/portraits/creatures/grifalon_fire.png"),
	&"creature_grifalon_gale": preload("res://assets/portraits/creatures/grifalon_gale.png"),
	&"creature_grifalon_light": preload("res://assets/portraits/creatures/grifalon_light.png"),
	&"creature_grifalon_stone": preload("res://assets/portraits/creatures/grifalon_stone.png"),
	&"creature_grifalon_shadow": preload("res://assets/portraits/creatures/grifalon_shadow.png"),
	&"creature_grifalon_tide": preload("res://assets/portraits/creatures/grifalon_tide.png"),
	&"creature_kolossar_fire": preload("res://assets/portraits/creatures/kolossar_fire.png"),
	&"creature_kolossar_gale": preload("res://assets/portraits/creatures/kolossar_gale.png"),
	&"creature_kolossar_light": preload("res://assets/portraits/creatures/kolossar_light.png"),
	&"creature_kolossar_stone": preload("res://assets/portraits/creatures/kolossar_stone.png"),
	&"creature_kolossar_shadow": preload("res://assets/portraits/creatures/kolossar_shadow.png"),
	&"creature_kolossar_tide": preload("res://assets/portraits/creatures/kolossar_tide.png"),
	&"creature_rogozhuk_fire": preload("res://assets/portraits/creatures/rogozhuk_fire.png"),
	&"creature_rogozhuk_gale": preload("res://assets/portraits/creatures/rogozhuk_gale.png"),
	&"creature_rogozhuk_light": preload("res://assets/portraits/creatures/rogozhuk_light.png"),
	&"creature_rogozhuk_stone": preload("res://assets/portraits/creatures/rogozhuk_stone.png"),
	&"creature_rogozhuk_shadow": preload("res://assets/portraits/creatures/rogozhuk_shadow.png"),
	&"creature_rogozhuk_tide": preload("res://assets/portraits/creatures/rogozhuk_tide.png"),
	&"creature_levian_fire": preload("res://assets/portraits/creatures/levian_fire.png"),
	&"creature_levian_gale": preload("res://assets/portraits/creatures/levian_gale.png"),
	&"creature_levian_light": preload("res://assets/portraits/creatures/levian_light.png"),
	&"creature_levian_stone": preload("res://assets/portraits/creatures/levian_stone.png"),
	&"creature_levian_shadow": preload("res://assets/portraits/creatures/levian_shadow.png"),
	&"creature_levian_tide": preload("res://assets/portraits/creatures/levian_tide.png"),
	&"creature_ratnik_fire": preload("res://assets/portraits/creatures/ratnik_fire.png"),
	&"creature_ratnik_gale": preload("res://assets/portraits/creatures/ratnik_gale.png"),
	&"creature_ratnik_light": preload("res://assets/portraits/creatures/ratnik_light.png"),
	&"creature_ratnik_stone": preload("res://assets/portraits/creatures/ratnik_stone.png"),
	&"creature_ratnik_shadow": preload("res://assets/portraits/creatures/ratnik_shadow.png"),
	&"creature_ratnik_tide": preload("res://assets/portraits/creatures/ratnik_tide.png"),
	&"creature_gorgul_fire": preload("res://assets/portraits/creatures/gorgul_fire.png"),
	&"creature_gorgul_gale": preload("res://assets/portraits/creatures/gorgul_gale.png"),
	&"creature_gorgul_light": preload("res://assets/portraits/creatures/gorgul_light.png"),
	&"creature_gorgul_stone": preload("res://assets/portraits/creatures/gorgul_stone.png"),
	&"creature_gorgul_shadow": preload("res://assets/portraits/creatures/gorgul_shadow.png"),
	&"creature_gorgul_tide": preload("res://assets/portraits/creatures/gorgul_tide.png"),
	&"creature_likorez_shadow": preload("res://assets/portraits/creatures/likorez_shadow.png"),
}

var _viewport: SubViewport
var _camera: Camera3D
var _image: TextureRect
var _fallback: TextureRect
var _backdrop: ColorRect
var _actor: CreatureBall
var _definition: CreatureDef
var _uid := -1
var _layers: Array[Dictionary] = []
var _elapsed := 0.0
var _active := false
var _reference_texture: Texture2D
var _hud_crop_enabled := false
static var _hud_reference_textures: Dictionary = {}
static var _presentation_textures: Dictionary = {}
static var _presentation_stats: Dictionary = {}
static var _background_materials: Dictionary = {}


## Explicit preparation is the only path that performs segmentation.
## Texture getters/present/style/resize only reuse resources, never Nodes.
static func preload_catalog() -> int:
	for definition_id: StringName in REFERENCE_TEXTURES:
		_prepare_reference(definition_id)
	for definition_id: StringName in HUD_CROPS.REGIONS:
		hud_reference_texture(definition_id)
	for element in ELEMENT_BACKDROPS.size():
		_background_material(element, false)
		_background_material(element, true)
	return REFERENCE_TEXTURES.size()


## Boot keeps rendering its loading screen between the bounded per-image tasks.
static func preload_catalog_async(tree: SceneTree, progress: Callable = Callable()) -> int:
	var done := 0
	for definition_id: StringName in REFERENCE_TEXTURES:
		var preparing := not _presentation_textures.has(definition_id)
		_prepare_reference(definition_id)
		done += 1
		if progress.is_valid():
			progress.call(done, REFERENCE_TEXTURES.size())
		if preparing and tree != null:
			await tree.process_frame
	return preload_catalog()


static func _prepare_reference(definition_id: StringName) -> void:
	if _presentation_textures.has(definition_id):
		return
	var begin := Time.get_ticks_usec()
	var prepared: Dictionary = MATTE.prepare(reference_texture(definition_id), false, INTERIOR_BACKGROUND.REGIONS.get(definition_id, {}))
	if prepared.is_empty():
		push_error("Could not prepare exact portrait: " + String(definition_id))
		return
	_presentation_textures[definition_id] = prepared.texture
	_presentation_stats[definition_id] = {"background_pixels": prepared.background_pixels, "interior_background_pixels": prepared.interior_background_pixels, "retained_closed_white_pixels": prepared.retained_closed_white_pixels, "softened_edge_pixels": prepared.softened_edge_pixels, "prepare_ms": (Time.get_ticks_usec() - begin) / 1000.0}
	_hud_reference_textures.erase(definition_id)


## A missing explicit preparation honestly falls back to the source, without
## triggering expensive work from a UI event or touching an original bitmap.
static func presentation_texture(definition_id: StringName) -> Texture2D:
	return _presentation_textures.get(definition_id, reference_texture(definition_id)) as Texture2D


static func _background_material(element: int, device_style: bool) -> ShaderMaterial:
	var key := "%d/%d" % [element, int(device_style)]
	if _background_materials.has(key):
		return _background_materials[key] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = BACKDROP
	material.set_shader_parameter("element_color", ELEMENT_BACKDROPS[clampi(element, 0, ELEMENT_BACKDROPS.size() - 1)])
	material.set_shader_parameter("device_style", 1.0 if device_style else 0.0)
	_background_materials[key] = material
	return material

static func reference_texture(definition_id: StringName) -> Texture2D:
	return REFERENCE_TEXTURES.get(definition_id) as Texture2D


## Only explicitly reviewed IDs crop; every other exact source remains full-body.
static func hud_reference_texture(definition_id: StringName) -> Texture2D:
	var source := presentation_texture(definition_id)
	if source == null or not HUD_CROPS.REGIONS.has(definition_id): return source
	if _hud_reference_textures.has(definition_id): return _hud_reference_textures[definition_id] as Texture2D
	var base_region: Rect2 = HUD_CROPS.REGIONS[definition_id]
	var factor := Vector2(source.get_width(), source.get_height()) / HUD_CROPS.COORDINATE_SIZE
	var region := Rect2(base_region.position * factor, base_region.size * factor)
	if region.size.x <= 0 or region.size.y <= 0 or not Rect2(Vector2.ZERO, source.get_size()).encloses(region): return source
	var texture := AtlasTexture.new()
	texture.atlas = source
	texture.region = region
	texture.filter_clip = true
	_hud_reference_textures[definition_id] = texture
	return texture


## Explicitly scoped to the small public HUD; other consumers keep the full reference.
func set_hud_crop_enabled(enabled: bool) -> void:
	if _hud_crop_enabled == enabled: return
	_hud_crop_enabled = enabled
	_update_fallback()


func _enter_tree() -> void:
	if not DEVICE.events().changed.is_connected(_style_changed): DEVICE.events().changed.connect(_style_changed)
	_resume.call_deferred()


func _resume() -> void:
	if not is_inside_tree(): return
	_update_fallback()
	_sync()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = ColorRect.new()
	_backdrop.name = "ElementPortraitBackdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.hide()
	add_child(_backdrop)
	_image = _texture()
	_image.name = "ResidentFigureImage"
	_image.hide()
	add_child(_image)
	_fallback = _texture()
	_fallback.name = "PublicSpeciesFallback"
	_fallback.hide()
	add_child(_fallback)
	visibility_changed.connect(_sync)
	set_process(false)
	_update_fallback()
	_sync()


## Allocate render resources only for a visible, public, already open resident actor.
func _create_viewport() -> void:
	if is_instance_valid(_viewport): return
	_viewport = SubViewport.new()
	_viewport.name = "PortraitViewport"
	_viewport.size = Vector2i(256, 256)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.positional_shadow_atlas_size = 0
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.name = "PortraitCamera"
	_camera.cull_mask = PORTRAIT_LAYER
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.01
	_camera.far = 200.0
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.86, 0.90, 0.96)
	environment.ambient_light_energy = 0.85
	_camera.environment = environment
	_viewport.add_child(_camera)
	_camera.current = true
	_image.texture = _viewport.get_texture()


func set_definition(definition: CreatureDef, uid: int = -1) -> void:
	if _definition != definition or _uid != uid:
		stop()
	_definition = definition
	_uid = uid
	_update_fallback()


func bind_actor(actor: CreatureBall) -> void:
	if _actor == actor:
		_sync()
		return
	stop()
	if not is_instance_valid(actor) or _definition == null or actor.uid != _uid or actor.def == null or actor.def.id != _definition.id:
		return
	_actor = actor
	_actor.tree_exiting.connect(_actor_exiting)
	_actor.visibility_changed.connect(_sync)
	if is_instance_valid(_actor._figure):
		_actor._figure.tree_exiting.connect(_actor_exiting)
		_actor._figure.visibility_changed.connect(_sync)
	_sync()


func stop() -> void:
	_deactivate()
	if is_instance_valid(_actor):
		if _actor.tree_exiting.is_connected(_actor_exiting): _actor.tree_exiting.disconnect(_actor_exiting)
		if _actor.visibility_changed.is_connected(_sync): _actor.visibility_changed.disconnect(_sync)
		if is_instance_valid(_actor._figure):
			if _actor._figure.tree_exiting.is_connected(_actor_exiting): _actor._figure.tree_exiting.disconnect(_actor_exiting)
			if _actor._figure.visibility_changed.is_connected(_sync): _actor._figure.visibility_changed.disconnect(_sync)
	_actor = null


func reset() -> void:
	stop()
	_definition = null
	_uid = -1
	_update_fallback()


func _actor_exiting() -> void:
	stop()


func _style_changed(_style: int) -> void:
	_update_fallback()
	_sync()


func _can_render() -> bool:
	return _reference_texture == null and DisplayServer.get_name() != "headless" and is_inside_tree() and is_visible_in_tree() and DEVICE.is_device() and _definition != null and is_instance_valid(_actor) and _actor.is_inside_tree() and _actor.uid == _uid and _actor.def != null and _actor.def.id == _definition.id and is_instance_valid(_actor._figure) and _actor.is_figure_shown() and _actor._figure.is_visible_in_tree()


func _sync() -> void:
	if not is_instance_valid(_image):
		return
	if not _can_render():
		_deactivate()
		return
	if not _active:
		_create_viewport()
		_collect(_actor._figure)
		if _layers.is_empty():
			_deactivate()
			return
		_viewport.world_3d = _actor.get_world_3d()
		_active = true
		_elapsed = 0.0
		_image.show()
		_fallback.hide()
		set_process(true)
		_render_once()


func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		_layers.append({"mesh": weakref(mesh), "layers": mesh.layers})
		if not mesh.tree_exiting.is_connected(_actor_exiting): mesh.tree_exiting.connect(_actor_exiting)
		mesh.layers = mesh.layers | PORTRAIT_LAYER
	for child in node.get_children():
		_collect(child)


func _deactivate() -> void:
	set_process(false)
	_active = false
	_elapsed = 0.0
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_viewport.world_3d = null
	for entry in _layers:
		var mesh: MeshInstance3D = entry.mesh.get_ref()
		if is_instance_valid(mesh):
			if mesh.tree_exiting.is_connected(_actor_exiting): mesh.tree_exiting.disconnect(_actor_exiting)
			mesh.layers = int(entry.layers)
	_layers.clear()
	if is_instance_valid(_image):
		_image.hide()
		_image.texture = null
	if is_instance_valid(_viewport):
		var old_viewport := _viewport
		_viewport = null
		_camera = null
		old_viewport.queue_free()
	if is_instance_valid(_fallback): _fallback.visible = _definition != null
	queue_redraw()


func _process(delta: float) -> void:
	if not _can_render():
		_deactivate()
		return
	_elapsed += delta
	if _elapsed >= FRAME_INTERVAL:
		_elapsed = fmod(_elapsed, FRAME_INTERVAL)
		_render_once()


func _render_once() -> void:
	var height := maxf(0.1, _actor.figure_height())
	var extent := maxf(height, _actor.figure_size())
	var center := _actor._figure.global_position + Vector3.UP * height * 0.48
	var forward := _actor._figure.global_basis.z.normalized()
	var side := _actor._figure.global_basis.x.normalized()
	_camera.size = extent * 1.35
	_camera.global_position = center + (forward + side * 0.22).normalized() * extent * 2.2 + Vector3.UP * extent * 0.12
	_camera.look_at(center, Vector3.UP)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _texture() -> TextureRect:
	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _update_fallback() -> void:
	_reference_texture = reference_texture(_definition.id) if _definition != null else null
	if is_instance_valid(_fallback):
		var texture: Texture2D = presentation_texture(_definition.id) if _definition != null else null
		if _hud_crop_enabled and _definition != null and _reference_texture != null:
			texture = hud_reference_texture(_definition.id)
		if texture == null and _definition != null:
			texture = ART.TEXTURES.get(String(_definition.species)) as Texture2D
		if texture == null and _definition != null:
			texture = ELEMENT_ICON.badge(_definition.attribute)
		_fallback.texture = texture
		_fallback.visible = not _active and _definition != null
	if is_instance_valid(_backdrop):
		_backdrop.visible = _definition != null
		if _definition != null:
			_backdrop.material = _background_material(_definition.attribute, DEVICE.is_device())
	queue_redraw()


func _exit_tree() -> void:
	stop()
	if DEVICE.events().changed.is_connected(_style_changed): DEVICE.events().changed.disconnect(_style_changed)
