class_name StartupCatalog
extends RefCounted
## Реальные ресурсы игры. Не обходим build/, инструменты или старый каталог
## assets/creatures: его 18 архетипов нужны только как запасной путь для отсутствующего HD.
const RESOURCE_EXTENSIONS := ["tscn", "tres", "gdshader", "gdshaderinc", "ttf", "otf", "png", "svg", "jpg", "jpeg", "webp"]
## Explicit roots stay required even when a missing file disappears from _collect.
const REQUIRED_SCENES := {
	"res://scenes/creature_ball.tscn": "res://scenes/creature_ball.gd",
	"res://scenes/arena.tscn": "res://scenes/arena.gd",
	"res://scenes/main.tscn": "res://scenes/main.gd",
	"res://scenes/menu/main_menu.tscn": "res://scenes/menu/main_menu.gd",
	"res://scenes/online/online_game.tscn": "res://scenes/online/online_game.gd",
}
class LoadResult extends RefCounted:
	var resources: Dictionary = {}
	var error := ""

const CARD_SCENE: PackedScene = preload("res://scenes/arena_card_node.tscn")
const MatchEffects := preload("res://scenes/presentation/match_effects.gd")
const CreatureElementFx := preload("res://scenes/presentation/creature_element_fx.gd")


static func resource_paths() -> Array[String]:
	var paths: Array[String] = ["res://assets/avatars/vrm/Sakurada_Fumiriya.vrm", "res://assets/avatars/vrm/Vita.vrm", "res://assets/avatars/vrm/HairSample_Male.vrm", "res://assets/avatars/vrm/HairSample_Female.vrm", "res://assets/avatars/vrm/Vivi.vrm"]
	_collect("res://scenes/", paths)
	_collect("res://assets/fonts/", paths)
	_collect("res://assets/avatars/editor/", paths)
	for model in WardrobeCatalog.LEGACY_COUNTS.size():
		for id in WardrobeCatalog.available_ids(model):
			if WardrobeCatalog.is_addition(model, id): paths.append(WardrobeCatalog.asset_path(model, id))
	_collect("res://assets/portraits/", paths)
	paths.append_array(CreatureModels.GrifalonMotion.resource_paths())
	paths.append_array(CreatureModels.KolossarMotion.resource_paths())
	paths.append(CreatureModels.KolossarLightSkin.PATH)
	paths.append(CreatureModels.GrifalonGaleSkin.PATH)
	for d in CreatureModels.catalog_defs():
		var path: String = CreatureModels._key_path(d)[1]
		if not paths.has(path):
			paths.append(path)
	for path in REQUIRED_SCENES:
		if not paths.has(path): paths.append(path)
	paths.sort()
	return paths


## Возвращаем сильные ссылки владельцу загрузки, чтобы ResourceLoader не терял
## их между матчами. Синхронный load по одному ресурсу избегает лишней памяти
## потоковой загрузки GLB; кадр между файлами обновляет начальный индикатор.
## progress.call(готово, всего, путь). Процедурные сцены/шейдеры прогревает владелец.
static func preload_resources(progress: Callable = Callable()) -> LoadResult:
	return await load_paths(resource_paths(), progress)


static func load_paths(paths: Array[String], progress: Callable = Callable()) -> LoadResult:
	var result := LoadResult.new()
	var tree := Engine.get_main_loop() as SceneTree
	var frame_budget := Time.get_ticks_usec()
	for index in paths.size():
		var path := paths[index]
		if not ResourceLoader.exists(path):
			result.error = "Отсутствует ресурс: " + path
			break
		var resource := ResourceLoader.load(path)
		if resource == null:
			result.error = "Не удалось загрузить ресурс: " + path
			break
		result.resources[path] = resource
		if progress.is_valid():
			progress.call(index + 1, paths.size(), path)
		if Time.get_ticks_usec()-frame_budget >= 8000 or index == paths.size()-1:
			await tree.process_frame
			frame_budget = Time.get_ticks_usec()
	if result.error.is_empty(): result.error = required_error(result.resources)
	if not result.error.is_empty(): result.resources.clear()
	return result


static func required_error(resources: Dictionary) -> String:
	for path in REQUIRED_SCENES:
		var scene := resources.get(path) as PackedScene
		if scene == null or not scene.can_instantiate():
			return "Нет обязательной сцены: " + path
		# Validate the root script before instantiate/add_child can execute _ready.
		var state := scene.get_state()
		var script: Script
		for property in state.get_node_property_count(0):
			if state.get_node_property_name(0, property) == &"script":
				script = state.get_node_property_value(0, property) as Script
				break
		if script == null or script.resource_path != REQUIRED_SCENES[path] or not script.can_instantiate():
			return "Несовместимая обязательная сцена: " + path
	return ""


## Семь кадров в собственном загрузочном viewport: реальные draw calls прогревают
## общие материалы, частицы, ImmediateMesh и надписи карты до появления меню.
## Временные узлы не попадают в игровой мир и не проигрывают звук.
static func warm_effects(parent: Node3D) -> void:
	var tree := parent.get_tree()
	var temporary := Node3D.new()
	temporary.name = "StartupEffects"
	parent.add_child(temporary)
	temporary.position = Vector3(0, 6, 0)
	await warm_avatar_parts(temporary)
	var particles: Array[CPUParticles3D] = []
	for element in Attr.COUNT:
		var local_center := Vector3((element % 3 - 1) * 2.0, float(element / 3) * 1.5, 0)
		var center := temporary.to_global(local_center)
		var creature_effect := CreatureElementFx.new()
		creature_effect.configure(element, Vector2(0.8, 0.8), 1.2)
		creature_effect.position = local_center
		temporary.add_child(creature_effect)
		creature_effect.begin_charge(Vector3.FORWARD, 1.0)
		creature_effect.windup(0.72)
		var impact := CreatureElementFx.new()
		impact.prepare_impact()
		temporary.add_child(impact)
		impact.show_impact(element, center, Vector3.FORWARD, 0.65, 1.0, null, center.y - 0.72)
		impact._impact_frame(0.18)
		for role in ["trail", "roll", "open", "burst"]:
			var effect := BallFx.particles(element, role, 1.0)
			temporary.add_child(effect)
			effect.global_position = center
			# Даже непрерывный trail должен успеть породить видимые частицы
			# при очень коротком первом кадре загрузочного viewport.
			effect.preprocess = 0.15
			effect.emitting = true
			particles.append(effect)
		var color := BallFx.elem_color(element)
		BallFx.flash(temporary, center, color, 1.0, 0.05)
		BallFx.sigil_flash(temporary, center, element, 1.0, 0.05)
		BallFx.speed_ring(temporary, center, Vector3.FORWARD, color, 1.0, 0.05)
		VisualUtil.ring_wave(temporary, center, color, 1.0, 0.05)

	var target := Node3D.new()
	temporary.add_child(target)
	target.position = Vector3(-1, 0.5, 1)
	var trail := BallTrail.new()
	trail.target = target
	trail.color = BallFx.elem_color(Attr.A.FIRE)
	temporary.add_child(trail)
	trail.emitting = true
	# Двигаем детерминированно: даже при высоком FPS лента получает три
	# разные точки и создаёт поверхность, а не пустой ImmediateMesh.
	trail.set_process(false)
	trail._process(1.0 / 60.0)
	var match_effects := MatchEffects.new()
	temporary.add_child(match_effects)
	match_effects.hit(temporary.to_global(Vector3(-2, 0.6, 1)), Basis.IDENTITY, 1.0)
	match_effects.sword_slash(temporary.to_global(Vector3(2, 0.6, 1)), Basis.IDENTITY, 1.0)
	match_effects.gate_capture(temporary.to_global(Vector3(2, -0.7, 1)))

	var card := CARD_SCENE.instantiate() as ArenaCardNode
	temporary.add_child(card)
	card.rotation_degrees.x = 55.0
	var definition := CardDB.card(CardDB.arena_ids()[0])
	card.show_facedown(0, definition)
	await tree.process_frame
	target.position += Vector3(0.6, 0.2, 0)
	trail._process(1.0 / 60.0)
	await tree.process_frame
	target.position += Vector3(0.6, -0.1, 0)
	trail._process(1.0 / 60.0)
	await tree.process_frame

	for effect in particles:
		effect.emitting = false
	trail.emitting = false
	trail.set_process(false)
	card.show_face(definition)
	await tree.process_frame
	await tree.process_frame
	temporary.queue_free()
	await tree.process_frame
	await tree.process_frame


static func _collect(directory: String, paths: Array[String]) -> void:
	# ResourceLoader видит исходные имена и в PCK, где обычный DirAccess может
	# перечислять только *.remap вместо импортированных ресурсов.
	for entry in ResourceLoader.list_directory(directory):
		if entry.ends_with("/"):
			_collect(directory + entry, paths)
		elif entry.get_extension().to_lower() in RESOURCE_EXTENSIONS:
			paths.append(directory + entry)

## Covers every prepared hair/costume shader before the main menu.
static func warm_avatar_parts(parent: Node3D) -> void:
	var actors: Array[VrmAvatar] = []
	for model in VrmAvatar.MODELS.size():
		var avatar := VrmAvatar.new()
		parent.add_child(avatar)
		avatar.position.x = (model*2-1)*.7
		actors.append(avatar)
	var warm_steps: int = PlayerProfile.LIMITS.vrm_style
	for model in actors.size(): warm_steps = maxi(warm_steps, WardrobeCatalog.available_ids(model).size())
	for step in warm_steps:
		for model in actors.size():
			var profile := PlayerProfile.DEFAULT.duplicate(true)
			profile.vrm_model = model
			profile.vrm_style = step % PlayerProfile.LIMITS.vrm_style
			profile.vrm_case = 1
			var outfits := WardrobeCatalog.available_ids(model)
			profile.vrm_clothes = outfits[step % outfits.size()]
			actors[model].apply_profile(profile)
		await parent.get_tree().process_frame

	# Upload every denim texture before the menu; no first-use upload during a match.
	for index in DenimWardrobe.TEXTURES.size():
		for model in actors.size():
			var profile := PlayerProfile.DEFAULT.duplicate(true)
			profile.vrm_model = model
			profile.vrm_clothes = 1 if model == 0 else 3
			profile.vrm_denim = index+1
			actors[model].apply_profile(profile)
		await parent.get_tree().process_frame
