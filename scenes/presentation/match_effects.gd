extends Node3D
## One-shot presentation owned by the match. Boot draws these same effects once.

const HIT := preload("res://assets/vfx_vendor/reeboo/effects/hit_spark.tscn")
const SLASH := preload("res://assets/vfx_vendor/reeboo/effects/slash.tscn")
const CAPTURE := preload("res://assets/vfx_vendor/reeboo/effects/pickup_sparkle.tscn")
const ElementEffect := preload("res://scenes/presentation/creature_element_fx.gd")

static var _particle_materials: Dictionary[ShaderMaterial, ShaderMaterial] = {}
var _impacts: Array[ElementEffect] = []
var _impact_slot := 0


func _ready() -> void:
	for slot in 2:
		var effect := ElementEffect.new()
		effect.prepare_impact()
		add_child(effect, true)
		_impacts.append(effect)


func hit(at: Vector3, facing: Basis, size: float) -> void:
	_play_reeboo(HIT, &"HitSpark", at, facing, size)


func sword_slash(at: Vector3, facing: Basis, size: float) -> void:
	_play_reeboo(SLASH, &"SwordSlash", at, facing, size)


func gate_capture(at: Vector3) -> void:
	_play_reeboo(CAPTURE, &"GateCaptureSparkle", at, Basis.IDENTITY, Arena.CARD_W * 0.17)


func elemental_impact(element: int, at: Vector3, direction: Vector3, size: float, strength: float, surface: ArenaCardNode = null) -> void:
	_impacts[_impact_slot].show_impact(element, at, direction, size, strength, surface)
	_impact_slot = (_impact_slot + 1) % _impacts.size()


func clear() -> void:
	for effect in get_children():
		if effect is ElementEffect:
			effect.reset_effect()
			continue
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
