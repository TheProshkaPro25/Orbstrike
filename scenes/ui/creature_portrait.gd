class_name CreaturePortrait
extends Control
## Точный 2D-концепт по ID; при его отсутствии — камера раскрытой резидентной фигуры.
## Нет копии модели, setup или своего мира.
const DEVICE := preload("res://scenes/ui/device_settings.gd")
const ART := preload("res://scenes/ui/card_artwork.gd")
const ELEMENT_ICON := preload("res://scenes/element_icon.gd")
const HUD_CROPS := preload("res://scenes/ui/creature_portrait_crops.gd")
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
var _actor: CreatureBall
var _definition: CreatureDef
var _uid := -1
var _layers: Array[Dictionary] = []
var _elapsed := 0.0
var _active := false
var _reference_texture: Texture2D
var _hud_crop_enabled := false
static var _hud_reference_textures: Dictionary = {}


## Boot may prepare these small resources before the menu; the cache never holds Nodes.
static func preload_catalog() -> int:
	# Resource-only AtlasTexture cache, prepared with the exact references before the menu.
	for definition_id: StringName in HUD_CROPS.REGIONS:
		hud_reference_texture(definition_id)
	return REFERENCE_TEXTURES.size()


static func reference_texture(definition_id: StringName) -> Texture2D:
	return REFERENCE_TEXTURES.get(definition_id) as Texture2D


## Only explicitly reviewed IDs crop; every other exact source remains full-body.
static func hud_reference_texture(definition_id: StringName) -> Texture2D:
	var source := reference_texture(definition_id)
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
		var texture: Texture2D = _reference_texture
		if _hud_crop_enabled and _definition != null and _reference_texture != null:
			texture = hud_reference_texture(_definition.id)
		if texture == null and _definition != null:
			texture = ART.TEXTURES.get(String(_definition.species)) as Texture2D
		if texture == null and _definition != null:
			texture = ELEMENT_ICON.badge(_definition.attribute)
		_fallback.texture = texture
		_fallback.visible = not _active and _definition != null
	queue_redraw()


func _exit_tree() -> void:
	stop()
	if DEVICE.events().changed.is_connected(_style_changed): DEVICE.events().changed.disconnect(_style_changed)
