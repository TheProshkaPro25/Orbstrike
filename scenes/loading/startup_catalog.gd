class_name StartupCatalog
extends RefCounted
## Реальные ресурсы игры. Не обходим build/, инструменты или старый каталог
## assets/creatures: его 18 архетипов нужны только как запасной путь для отсутствующего HD.
const RESOURCE_EXTENSIONS := ["tscn", "tres", "gdshader", "gdshaderinc", "ttf", "otf", "png", "svg", "jpg", "jpeg", "webp"]
const CARD_SCENE: PackedScene = preload("res://scenes/arena_card_node.tscn")


static func resource_paths() -> Array[String]:
	var paths: Array[String] = ["res://assets/avatars/fighter_mpfb.glb", "res://assets/avatars/vrm/Sakurada_Fumiriya.vrm", "res://assets/avatars/vrm/Vita.vrm", "res://assets/avatars/vrm/HairSample_Male.vrm", "res://assets/avatars/vrm/HairSample_Female.vrm", "res://assets/avatars/vrm/Vivi.vrm"]
	_collect("res://scenes/", paths)
	_collect("res://assets/fonts/", paths)
	_collect("res://assets/avatars/editor/", paths)
	_collect("res://assets/portraits/", paths)
	paths.append_array(CreatureModels.GrifalonMotion.resource_paths())
	paths.append_array(CreatureModels.KolossarMotion.resource_paths())
	paths.append(CreatureModels.KolossarLightSkin.PATH)
	paths.append(CreatureModels.GrifalonGaleSkin.PATH)
	for d in CreatureModels.catalog_defs():
		var path: String = CreatureModels._key_path(d)[1]
		if not paths.has(path):
			paths.append(path)
	paths.sort()
	return paths


## Возвращаем сильные ссылки владельцу загрузки, чтобы ResourceLoader не терял
## их между матчами. Синхронный load по одному ресурсу избегает лишней памяти
## потоковой загрузки GLB; кадр между файлами обновляет начальный индикатор.
## progress.call(готово, всего, путь). Процедурные сцены/шейдеры прогревает владелец.
static func preload_resources(progress: Callable = Callable()) -> Dictionary:
	var resources: Dictionary = {}
	var paths := resource_paths()
	var tree := Engine.get_main_loop() as SceneTree
	var frame_budget := Time.get_ticks_usec()
	for index in paths.size():
		var path := paths[index]
		var resource := ResourceLoader.load(path)
		if resource != null:
			resources[path] = resource
		else:
			push_error("Начальная загрузка: не удалось загрузить " + path)
		if progress.is_valid():
			progress.call(index + 1, paths.size(), path)
		if Time.get_ticks_usec()-frame_budget >= 8000 or index == paths.size()-1:
			await tree.process_frame
			frame_budget = Time.get_ticks_usec()
	return resources


## Семь кадров в собственном загрузочном viewport: реальные draw calls прогревают
## общие материалы, частицы, ImmediateMesh и надписи карты до появления меню.
## Временные узлы не попадают в игровой мир и не проигрывают звук.
static func warm_effects(parent: Node3D) -> void:
	var tree := parent.get_tree()
	var temporary := Node3D.new()
	temporary.name = "StartupEffects"
	parent.add_child(temporary)
	temporary.position = Vector3(0, 6, 0)
	var avatar := FighterAvatar.new()
	temporary.add_child(avatar)
	avatar.build(PlayerProfile.DEFAULT)
	await warm_avatar_parts(temporary)
	var particles: Array[CPUParticles3D] = []
	for element in Attr.COUNT:
		var local_center := Vector3((element % 3 - 1) * 2.0, float(element / 3) * 1.5, 0)
		var center := temporary.to_global(local_center)
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
	for style in PlayerProfile.LIMITS.vrm_style:
		for model in actors.size():
			var profile := PlayerProfile.DEFAULT.duplicate(true)
			profile.vrm_model = model
			profile.vrm_style = style
			profile.vrm_case = 1
			profile.vrm_clothes = style % VrmParts.BODY[model].size()
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
