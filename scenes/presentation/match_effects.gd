extends Node3D
## One-shot presentation owned by the match. Boot draws these same effects once.

const HIT := preload("res://assets/vfx_vendor/reeboo/effects/hit_spark.tscn")
const SLASH := preload("res://assets/vfx_vendor/reeboo/effects/slash.tscn")
const CAPTURE := preload("res://assets/vfx_vendor/reeboo/effects/pickup_sparkle.tscn")
const FIRE := preload("res://assets/vfx_vendor/elemental_impact/scenes/elem_fire.tscn")
const KENNEY_SPARK := preload("res://assets/vfx_vendor/kenney/spark_05.png")

static var _particle_materials: Dictionary[ShaderMaterial, ShaderMaterial] = {}
static var _fire_presets: Dictionary[int, FreeElementalFxPreset] = {}


func hit(at: Vector3, facing: Basis, size: float) -> void:
	_play_reeboo(HIT, &"HitSpark", at, facing, size)


func sword_slash(at: Vector3, facing: Basis, size: float) -> void:
	_play_reeboo(SLASH, &"SwordSlash", at, facing, size)


func gate_capture(at: Vector3) -> void:
	_play_reeboo(CAPTURE, &"GateCaptureSparkle", at, Basis.IDENTITY, Arena.CARD_W * 0.17)


func fire_impact(at: Vector3, size: float) -> void:
	var effect := FIRE.instantiate() as FreeElementalFx
	var quality := GraphicsSettings.current()
	if not _fire_presets.has(quality):
		var preset := effect.preset.duplicate() as FreeElementalFxPreset
		preset.color_core = Color(1.28, 0.91, 0.49)
		preset.color_main = Color(1.16, 0.37, 0.09)
		preset.color_accent = Color(0.78, 0.17, 0.06)
		preset.sparks_amount = roundi(24.0 * BallFx.level_k())
		preset.spark_texture = KENNEY_SPARK
		preset.light_energy = 2.1 if GraphicsSettings.param("lights") else 0.0
		preset.light_range = 5.0
		_fire_presets[quality] = preset
	effect.name = &"FireImpact"
	effect.preset = _fire_presets[quality]
	effect.auto_play = false
	effect.loop = false
	effect.one_shot_free = true
	add_child(effect, true)
	effect.global_position = at
	effect.scale = Vector3.ONE * size
	effect.play()


func clear() -> void:
	for effect in get_children():
		effect.hide()
		effect.process_mode = Node.PROCESS_MODE_DISABLED
		effect.queue_free()


func _play_reeboo(scene: PackedScene, effect_name: StringName, at: Vector3, facing: Basis, size: float) -> void:
	var effect := scene.instantiate() as VFXEffect
	effect.name = effect_name
	effect.autoplay = false
	for light: OmniLight3D in effect.find_children("*", "OmniLight3D", true, false):
		light.light_energy *= 0.24 if GraphicsSettings.param("lights") else 0.0
		light.light_volumetric_fog_energy = 0.0
		if scene == CAPTURE:
			light.remove_meta(VFXEffect.FLICKER_META)
			light.set_meta(VFXEffect.FLASH_META, 0.32)
	for layer: GPUParticles3D in effect.find_children("*", "GPUParticles3D", true, false):
		var material := layer.material_override as ShaderMaterial
		if not _particle_materials.has(material):
			var softened := material.duplicate() as ShaderMaterial
			var energy := float(material.get_shader_parameter("emission_energy"))
			softened.set_shader_parameter("emission_energy", energy * (0.62 if scene == CAPTURE else 0.46))
			_particle_materials[material] = softened
		layer.material_override = _particle_materials[material]
		layer.amount = maxi(1, roundi(float(layer.amount) * BallFx.level_k()))
		if scene == CAPTURE:
			# The original pickup waits for interaction. Here the card already
			# belongs to its winner, so leave one short burst at the departure point.
			layer.one_shot = true
			layer.explosiveness = 0.88
			layer.lifetime *= 0.54
	add_child(effect, true)
	effect.global_transform = Transform3D(facing.scaled(Vector3.ONE * size), at)
	effect.play()
