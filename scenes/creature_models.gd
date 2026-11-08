class_name CreatureModels
extends RefCounted
## 3D-модели существ: HD-модель вида в стихии или архетип вида + перекраска материалов под цвет и стихию.
## Модели генерирует tools/blender/make_creatures.py в assets/creatures/<архетип>.glb
## (высота 1.0, основание на y=0, лицом к +Z). Имена материалов: Primary, Secondary, Metal, Glow, Eye, Dark.

## Размер: длина/ширина фигуры = треть масштаба существ Arena.FIG_H (в бою два существа + треть пустоты между ними),
## высота не больше MAX_HEIGHT. Карты ворот крупнее (Arena.GATE_SCALE), существа от них не зависят.
const FOOTPRINT := Arena.FIG_H / 3.0
## Великаны над воротами: существо 0.85–1.0 FIG_H (шар рядом с ним — горошина).
const MAX_HEIGHT := Arena.FIG_H * 1.0
const MIN_HEIGHT := Arena.FIG_H * 0.85
## Предел длины вдоль карты (в третях карты) и ширины (в ширинах карты): в бою двое не пересекаются.
const MAX_LEN := 1.75
const MAX_WIDTH := 1.3
const DIR := "res://assets/creatures/%s.glb"
## Модели существ (Pixal3D, со своей текстурой): assets/creatures_hd/<вид>_<стихия>.glb (= id без creature_).
const HD_DIR := "res://assets/creatures_hd/%s.glb"
const GrifalonMotion := preload("res://scenes/grifalon_motion.gd")
const KolossarMotion := preload("res://scenes/kolossar_motion.gd")
const KolossarLightSkin := preload("res://scenes/kolossar_light_skin.gd")
const GrifalonGaleSkin := preload("res://scenes/grifalon_gale_skin.gd")
## Поворот HD-моделей вокруг Y, чтобы смотрели вдоль +Z (как архетипы).
const HD_YAW_DEG := 0.0
## Preserve the accepted body/motion frame across local decorative repairs.
## Godot compacts unused GLB vertices; removed wind or a new halo changes AABB
## and otherwise rescales the body or changes support/action amplitudes.
## Source frames measured before A01/A03/A04 (targeted runtime reports).
## Visual bounds stay live; these frames only preserve authored normalization.
const NORMALIZATION_FRAMES := {
	"hd:klykar_gale": {
		"triangles": 132146,
		"active": AABB(Vector3(-0.494633555412292, -0.393120139837265, -0.24501459300518),
			Vector3(0.823238730430603, 0.793244004249573, 0.593697786331177)),
		"source": AABB(Vector3(-0.494633555412292, -0.393120139837265, -0.337262958288193),
			Vector3(0.925168871879578, 0.793244004249573, 0.74784779548645)),
	},
	"hd:ratnik_light": {
		"triangles": 153632,
		"previous_triangles": 156366, # immutable pre-reopen source frame
		"active": AABB(Vector3(-0.484584450721741, -0.423645496368408, -0.494712114334106),
			Vector3(0.806332111358643, 0.899992823600769, 0.926286101341248)),
		"source": AABB(Vector3(-0.484584450721741, -0.423645496368408, -0.494712114334106),
			Vector3(0.806332111358643, 0.859198212623596, 0.926286101341248)),
	},
	"hd:kolossar_shadow": {
		"triangles": 171156,
		"active": AABB(Vector3(-0.3991594910621643, -0.415763258934021, -0.35553279519081116),
			Vector3(0.8174850046634674, 0.8263136744499207, 0.6669683456420898)),
		"source": AABB(Vector3(-0.3991594910621643, -0.415763258934021, -0.35553279519081116),
			Vector3(0.8174850046634674, 0.8477587699890137, 0.6669683456420898)),
	},
}


## Загрузчик перед меню закрепляет конечный каталог; изолированные стенды сохраняют
## прежнее время жизни ресурсов одного матча.
static var resident_catalog := false
static var _scenes: Dictionary = {}
## Производные неизменяемые данные текущего набора моделей; без узлов экземпляров.
static var preparation_cache: Dictionary = {}
## Immutable prepared curves; players, poses and blend state stay on each actor.
static var animation_library_cache: Dictionary = {}

## Убирает запечённые фотографические блики из цветовой текстуры;
## широкие ступени света оставляют рисунок брони, но не имитируют полированный металл.
const ANIME_SHADER := """
shader_type spatial;
render_mode specular_disabled, cull_disabled;
uniform sampler2D color_map : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool has_texture = true;
uniform bool shadow_palette = false;
void fragment() {
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	vec3 tex = tint.rgb;
	if (has_texture) { tex *= texture(color_map, UV).rgb; }
	if (shadow_palette) {
		// Small foreign green patches in generated shadow textures aren't part of their palette.
		float foreign_green = smoothstep(0.025, 0.12, tex.g - max(tex.r, tex.b));
		float brightness = max(max(tex.r, tex.g), tex.b);
		tex = mix(tex, vec3(0.52, 0.37, 0.70) * brightness, foreign_green);
	}
	float value = max(max(tex.r, tex.g), tex.b);
	vec3 chroma = tex / max(value, 0.001);
	// Сжимаем запечённые белые блики и тёмные провалы, сохраняя оттенок.
	float tone = 0.06 + 0.50 * pow(clamp(value, 0.0, 1.0), 0.72);
	ALBEDO = chroma * tone;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float shade = mix(0.32, 0.72, smoothstep(0.12, 0.2, facing));
	shade = mix(shade, 1.0, smoothstep(0.65, 0.73, facing));
	// Godot applies ALBEDO after light(): multiply it once, not twice.
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * shade / PI;
}
"""
static var _anime_shader: Shader



static func _key_path(d: CreatureDef) -> Array:
	var key := String(d.id).trim_prefix("creature_")
	var hd_path := HD_DIR % key
	if ResourceLoader.exists(hd_path):
		return ["hd:" + key, hd_path]
	return [archetype_of(d), DIR % archetype_of(d)]


## Загрузка моделей существ матча (6 штук) при старте матча: к первому раскрытию они уже в памяти,
## без рывка кадра посреди хода. Синхронно: фоновая загрузка (load_threaded_request) текстур через
## потоки передачи RenderingDevice держала ~+600 МБ ОЗУ процесса; с VRAM-сжатыми текстурами 6 моделей
## грузятся за доли секунды.
static func preload_match(defs: Array) -> void:
	for d in defs:
		if d != null:
			var kp := _key_path(d)
			_scene(kp[0], kp[1])
			GrifalonMotion.preload_for(d)
			KolossarMotion.preload_for(d)
			if d.id == &"creature_kolossar_light": KolossarLightSkin.preload_required()
			if d.id == &"creature_grifalon_gale": GrifalonGaleSkin.preload_required()


## Меню исключает особую встречу из выбора, но загрузчик обязан подготовить и её.
static func catalog_defs() -> Array[CreatureDef]:
	var defs := CardDB.all_creatures()
	defs.append(CardDB.creature(CardDB.RARE_SHADOW_ID))
	return defs


static func preload_all_catalog() -> void:
	preload_match(catalog_defs())


static func preparation_cache_limit() -> int:
	return 64 if resident_catalog else 6


## Выход из матча не выгружает закреплённый каталог и канонические опоры.
static func clear() -> void:
	if resident_catalog:
		return
	_scenes.clear()
	preparation_cache.clear()
	animation_library_cache.clear()
	GrifalonMotion.clear()
	KolossarMotion.clear()
	KolossarLightSkin.clear()
	preload("res://scenes/authored_ground_support.gd").clear()
	GrifalonGaleSkin.clear()


static func _scene(res_key: String, path: String) -> PackedScene:
	if not _scenes.has(res_key):
		_scenes[res_key] = load(path) as PackedScene
	return _scenes[res_key]


static func archetype_of(d: CreatureDef) -> String:
	return d.archetype if d.archetype != "" else "knight"


## Узел с моделью существа (основание на y=0); null, если модели нет.
static func build(d: CreatureDef) -> Node3D:
	if d == null:
		return null
	var kp := _key_path(d)
	var hd: bool = String(kp[0]).begins_with("hd:")
	var ps: PackedScene = _scene(kp[0], kp[1])
	if ps == null:
		return null
	var root := Node3D.new()
	var inst := ps.instantiate() as Node3D
	if d.id == &"creature_kolossar_light":
		if not KolossarLightSkin.apply(inst):
			push_error("Kolossar Light skin overlay: " + KolossarLightSkin.last_error)
			inst.free()
			root.free()
			return null
		root.set_meta("kolossar_light_skin_overlay", 1)
		root.set_meta("support_surface_signature", KolossarLightSkin.payload_digest(KolossarLightSkin.overlay))
		root.set_meta("skin_visual_top_source", KolossarLightSkin.overlay.get_meta("visual_top_source"))
		root.set_meta("skin_visual_extent_source", KolossarLightSkin.overlay.get_meta("visual_extent_source"))
	if d.id == &"creature_grifalon_gale":
		if not GrifalonGaleSkin.apply(inst):
			push_error("Grifalon Gale skin overlay: " + GrifalonGaleSkin.last_error)
			inst.free()
			root.free()
			return null
		root.set_meta("grifalon_gale_skin_overlay", 1)
		root.set_meta("skin_visual_top_source", GrifalonGaleSkin.overlay.get_meta("visual_top_source"))
		root.set_meta("skin_visual_extent_source", GrifalonGaleSkin.overlay.get_meta("visual_extent_source"))
	var model: Node3D = inst
	if hd:
		# обёртка с поворотом, чтобы модель смотрела вдоль +Z
		model = Node3D.new()
		inst.rotation_degrees.y = HD_YAW_DEG
		model.add_child(inst)
	var box := _bounds(model, Transform3D.IDENTITY)
	box = _normalization_frame(kp[0], model, box)
	var k: float = 1.0
	if box.size.length() > 0.001:
		var sx: float = maxf(box.size.x, 0.01)
		var sy: float = maxf(box.size.y, 0.01)
		var sz: float = maxf(box.size.z, 0.01)
		# длина вдоль карты (модели смотрят вдоль Z) = треть карты; но не ниже MIN_HEIGHT,
		# не длиннее MAX_LEN трети, не шире MAX_WIDTH карты и не выше MAX_HEIGHT
		k = maxf(FOOTPRINT / sz, MIN_HEIGHT / sy)
		k = minf(k, minf(FOOTPRINT * MAX_LEN / sz, minf(Arena.FIG_W * MAX_WIDTH / sx, MAX_HEIGHT / sy)))
	model.scale = Vector3.ONE * k
	# основание на y=0, центр по XZ
	model.position = Vector3(-(box.position.x + box.size.x * 0.5) * k, -box.position.y * k, -(box.position.z + box.size.z * 0.5) * k)
	root.add_child(model)
	root.set_meta("preparation_source", ps)
	root.set_meta("height", box.size.y * k)
	root.set_meta("normalization_scale", k)
	root.set_meta("normalization_floor_source", box.position.y)
	root.set_meta("extent", maxf(box.size.x, box.size.z) * k)  # наибольший размер по полу (для камеры)
	if hd:
		# Audit the whole instance before replacing any active material.
		_release_unused_hd_maps(model)
		_fix_hd_materials(model, d.attribute)
	else:
		_recolor(model, d)
	return root


## Scope the preserved frame to the reviewed repaired surface; a different model
## with different bounds or triangle count falls back to measured bounds.
static func _normalization_frame(key: String, model: Node, live: AABB) -> AABB:
	if not NORMALIZATION_FRAMES.has(key): return live
	var frame: Dictionary = NORMALIZATION_FRAMES[key]
	var expected: AABB = frame.active
	if not live.position.is_equal_approx(expected.position) or not live.size.is_equal_approx(expected.size):
		return live
	var stack: Array[Node] = [model]
	var triangles := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh != null:
			for surface in node.mesh.get_surface_count():
				triangles += node.mesh.surface_get_array_index_len(surface) / 3
	return frame.source if triangles == frame.triangles or triangles == frame.get("previous_triangles", -1) else live


## Общий AABB всех мешей поддерева в координатах корня (узел может быть вне дерева сцены).
static func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var has := false
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out = t * (n as MeshInstance3D).mesh.get_aabb()
		has = true
	for ch in n.get_children():
		var b := _bounds(ch, t)
		if b.size.length() > 0.0:
			out = b if not has else out.merge(b)
			has = true
	return out


## Мировой AABB видимых мешей поддерева (для камеры): учитывает плащи, крылья, хвосты. Отдельные эффекты
## (top_level: столбы света, следы) не входят. Пустой AABB, если мешей нет.
static func world_aabb(n: Node) -> AABB:
	var out := AABB()
	var has := false
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is Node3D and c != n and (c as Node3D).top_level:
			continue
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree():
				var b := mi.global_transform * mi.mesh.get_aabb()
				out = b if not has else out.merge(b)
				has = true
		stack.append_array(c.get_children())
	return out


## Only these imported maps are proven absent from both ANIME_SHADER and the
## cape variant (which adds vertex deformation + flash emission to that shader).
## Keep albedo including alpha, emission, unknown slots, and every fallback use.
const UNUSED_HD_TEXTURE_SLOTS := [&"normal_texture", &"roughness_texture", &"metallic_texture", &"ao_texture"]

static func _release_unused_hd_maps(model: Node3D) -> void:
	var candidates: Dictionary = {}
	var protected: Dictionary = {}
	var pending: Array[Node] = [model]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh != null:
			# A whole-mesh override outranks surface overrides. Preserve it because
			# _fix_hd_materials cannot replace this native/fallback rendering path.
			_protect_material_value(node.material_override, protected)
			_protect_material_value(node.material_overlay, protected)
			for surface in node.mesh.get_surface_count():
				var material := node.get_active_material(surface) as BaseMaterial3D
				if material == null:
					# Unconverted custom materials may retain a native PBR next pass.
					_protect_material_value(node.get_active_material(surface), protected)
					continue
				if node.material_override != null:
					protected[material] = true
				else:
					candidates[material] = true
		if node is AnimationPlayer:
			# A material/mesh assigned by a future animation key may still use PBR.
			# Such authored resource swaps are not part of the conversion contract.
			for clip in node.get_animation_list():
				var animation: Animation = node.get_animation(clip)
				for track in animation.get_track_count():
					for key in animation.track_get_key_count(track):
						_protect_material_value(animation.track_get_key_value(track, key), protected)
	for material in candidates:
		if protected.has(material): continue
		for slot in UNUSED_HD_TEXTURE_SLOTS: material.set(slot, null)


static func _protect_material_value(value: Variant, protected: Dictionary) -> void:
	if value is Material:
		if protected.has(value): return
		protected[value] = true
		_protect_material_value(value.next_pass, protected)
	elif value is Mesh:
		for surface in value.get_surface_count():
			_protect_material_value(value.surface_get_material(surface), protected)
	elif value is Array:
		for child in value: _protect_material_value(child, protected)
	elif value is Dictionary:
		for child in value.values(): _protect_material_value(child, protected)


## Матовая аниме-подача: текстура цвета сохраняется, но PBR-карты не создают
## блестящие пятна, грязные впадины и шум нормалей на сгенерированной поверхности.
## Геометрические дефекты исходного меша требуют отдельной правки модели.
static func _fix_hd_materials(node: Node, attribute: int = -1) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			return
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(i) as BaseMaterial3D
			if src == null:
				continue
			if _anime_shader == null:
				_anime_shader = Shader.new()
				_anime_shader.code = ANIME_SHADER
			var m := ShaderMaterial.new()
			m.shader = _anime_shader
			m.set_shader_parameter("tint", src.albedo_color)
			m.set_shader_parameter("shadow_palette", attribute == Attr.A.SHADOW)
			m.set_shader_parameter("has_texture", src.albedo_texture != null)
			if src.albedo_texture != null:
				m.set_shader_parameter("color_map", src.albedo_texture)
			mi.set_surface_override_material(i, m)
	for ch in node.get_children():
		_fix_hd_materials(ch, attribute)


static func _recolor(node: Node, d: CreatureDef) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(i)
			var mname := src.resource_name if src != null else ""
			mi.set_surface_override_material(i, _material(mname, d))
	for ch in node.get_children():
		_recolor(ch, d)


static func _material(mname: String, d: CreatureDef) -> StandardMaterial3D:
	var c: Color = d.color
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	match mname:
		"Primary":
			m.albedo_color = c
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.6
			match d.attribute:
				Attr.A.STONE:
					m.roughness = 0.9
				Attr.A.TIDE:
					m.roughness = 1.05
					m.clearcoat_enabled = true
				Attr.A.LIGHT:
					m.emission_enabled = true
					m.emission = c
					m.emission_energy_multiplier = 0.25
				Attr.A.SHADOW:
					m.albedo_color = c.darkened(0.15)
		"Secondary":
			m.albedo_color = c.darkened(0.5)
			m.roughness = 0.7
		"Metal":
			m.albedo_color = Color(0.78, 0.78, 0.82).lerp(c, 0.2)
			m.metallic = 0.0
			m.roughness = 1.08
		"Glow":
			m.albedo_color = c.lightened(0.5)
			m.emission_enabled = true
			m.emission = c.lightened(0.35)
			m.emission_energy_multiplier = 0.35
			if d.archetype == "cyclops" or d.archetype == "flying_eye":
				m.emission_enabled = false
		"Eye":
			m.albedo_color = Color(0.95, 0.93, 0.88)
			m.roughness = 1.0
		"Dark":
			m.albedo_color = Color(0.06, 0.06, 0.07)
		_:
			m.albedo_color = c
	return m
