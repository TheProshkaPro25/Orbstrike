class_name CreaturePortrait
extends Control
## Прозрачный рендер модели по ID. Для неизвестного ID доступна камера
## уже раскрытой резидентной фигуры, без копирования модели и setup.
const ART := preload("res://scenes/ui/card_artwork.gd")
const ELEMENT_ICON := preload("res://scenes/element_icon.gd")
const BACKDROP := preload("res://scenes/ui/portrait_backdrop.gdshader")
const BATTLE_BACKDROP := preload("res://scenes/ui/battle_portrait_backdrop.gdshader")
const BATTLE_CORNER_RADIUS := 10
const BATTLE_ART_INSET := 3.0
const ELEMENT_BACKDROPS := [Color("c96229"), Color("39a58d"), Color("cfb05f"), Color("97816a"), Color("9560c6"), Color("3686b8")]
const PORTRAIT_LAYER := 1 << 20
const FRAME_INTERVAL := 1.0 / 15.0
## Exact model renders shared with Boot, including the rare encounter.
const RENDERED_TEXTURES := {
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
	&"creature_floris_fire": preload("res://assets/portraits/creatures/floris_fire.png"),
	&"creature_floris_gale": preload("res://assets/portraits/creatures/floris_gale.png"),
	&"creature_floris_light": preload("res://assets/portraits/creatures/floris_light.png"),
	&"creature_floris_stone": preload("res://assets/portraits/creatures/floris_stone.png"),
	&"creature_floris_shadow": preload("res://assets/portraits/creatures/floris_shadow.png"),
	&"creature_floris_tide": preload("res://assets/portraits/creatures/floris_tide.png"),
	&"creature_octo_fire": preload("res://assets/portraits/creatures/octo_fire.png"),
	&"creature_octo_gale": preload("res://assets/portraits/creatures/octo_gale.png"),
	&"creature_octo_light": preload("res://assets/portraits/creatures/octo_light.png"),
	&"creature_octo_stone": preload("res://assets/portraits/creatures/octo_stone.png"),
	&"creature_octo_shadow": preload("res://assets/portraits/creatures/octo_shadow.png"),
	&"creature_octo_tide": preload("res://assets/portraits/creatures/octo_tide.png"),
	&"creature_armat_fire": preload("res://assets/portraits/creatures/armat_fire.png"),
	&"creature_armat_gale": preload("res://assets/portraits/creatures/armat_gale.png"),
	&"creature_armat_light": preload("res://assets/portraits/creatures/armat_light.png"),
	&"creature_armat_stone": preload("res://assets/portraits/creatures/armat_stone.png"),
	&"creature_armat_shadow": preload("res://assets/portraits/creatures/armat_shadow.png"),
	&"creature_armat_tide": preload("res://assets/portraits/creatures/armat_tide.png"),
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
var _battle_style := false
var _battle_backdrop: ShaderMaterial
var _battle_frame: Panel
static var _background_materials: Dictionary = {}
static var _battle_frame_style: StyleBoxFlat
static var _battle_mask_style: StyleBoxFlat


static func preload_catalog() -> int:
	for element in ELEMENT_BACKDROPS.size():
		_background_material(element)
	return RENDERED_TEXTURES.size()


static func presentation_texture(definition_id: StringName) -> Texture2D:
	return RENDERED_TEXTURES.get(definition_id) as Texture2D


static func _background_material(element: int) -> ShaderMaterial:
	if _background_materials.has(element):
		return _background_materials[element] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = BACKDROP
	material.set_shader_parameter("element_color", ELEMENT_BACKDROPS[clampi(element, 0, ELEMENT_BACKDROPS.size() - 1)])
	_background_materials[element] = material
	return material

func set_battle_style(enabled: bool) -> void:
	if _battle_style == enabled: return
	_battle_style = enabled
	_update_fallback()


func _enter_tree() -> void:
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
	_fallback.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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


func _can_render() -> bool:
	return _reference_texture == null and DisplayServer.get_name() != "headless" and is_inside_tree() and is_visible_in_tree() and _definition != null and is_instance_valid(_actor) and _actor.is_inside_tree() and _actor.uid == _uid and _actor.def != null and _actor.def.id == _definition.id and is_instance_valid(_actor._figure) and _actor.is_figure_shown() and _actor._figure.is_visible_in_tree()


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
	_reference_texture = presentation_texture(_definition.id) if _definition != null else null
	var battle := _battle_style and _definition != null
	if is_instance_valid(_fallback):
		var texture := _reference_texture
		if texture == null and _definition != null:
			texture = ART.TEXTURES.get(String(_definition.species)) as Texture2D
		if texture == null and _definition != null:
			texture = ELEMENT_ICON.badge(_definition.attribute)
		_fallback.texture = texture
		_fallback.visible = not _active and _definition != null
	if is_instance_valid(_backdrop):
		_backdrop.visible = _definition != null
		if battle:
			if _battle_backdrop == null:
				_battle_backdrop = ShaderMaterial.new()
				_battle_backdrop.shader = BATTLE_BACKDROP
			_battle_backdrop.set_shader_parameter("element_color", ELEMENT_BACKDROPS[_definition.attribute])
			_battle_backdrop.set_shader_parameter("element", _definition.attribute)
			_backdrop.material = _battle_backdrop
			_show_battle_frame()
		elif _definition != null:
			_backdrop.material = _background_material(_definition.attribute)
	if is_instance_valid(_battle_frame):
		_battle_frame.visible = battle
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY if battle else CanvasItem.CLIP_CHILDREN_DISABLED
	var inset := BATTLE_ART_INSET if battle else 0.0
	for art in [_fallback, _image]:
		if not is_instance_valid(art): continue
		art.offset_left = inset
		art.offset_top = inset
		art.offset_right = -inset
		art.offset_bottom = -inset
	queue_redraw()


func _show_battle_frame() -> void:
	if is_instance_valid(_battle_frame): return
	if _battle_frame_style == null:
		_battle_frame_style = UiTheme.box(Color.TRANSPARENT, UiTheme.DEVICE_DIM.lightened(0.08), 1, BATTLE_CORNER_RADIUS, 0)
		_battle_frame_style.draw_center = false
		_battle_mask_style = UiTheme.box(Color.WHITE, Color.TRANSPARENT, 0, BATTLE_CORNER_RADIUS, 0)
	_battle_frame = Panel.new()
	_battle_frame.name = "BattlePortraitFrame"
	_battle_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battle_frame.add_theme_stylebox_override("panel", _battle_frame_style)
	add_child(_battle_frame)
	_battle_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if clip_children == CanvasItem.CLIP_CHILDREN_ONLY and _battle_mask_style != null:
		draw_style_box(_battle_mask_style, Rect2(Vector2.ZERO, size))


func _exit_tree() -> void:
	stop()
