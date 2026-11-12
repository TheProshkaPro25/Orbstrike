@tool
class_name VFXEffect
extends Node3D
## Root node of every REEBOO Stylized VFX effect.
##
## Plays all child particle systems together, honoring each layer's start delay, and fades
## its flash lights. One-shot effects (explosions, hits) free themselves when they finish.
## Looping effects (projectiles, auras, shields) run until you call stop() or free them.
##
## Spawn one from code:
##     var fx := VFXEffect.spawn(preload("res://assets/vfx_vendor/reeboo/effects/hit_spark.tscn"), get_tree().current_scene, hit_position)
##
## Per-layer timing lives in node metadata, editable in the Inspector:
##     vfx_delay   (float) seconds before a particle layer or light starts
##     vfx_flash   (float) seconds for a light to fade from its energy to zero
##     vfx_flicker (float) 0..1 flicker strength for a light that stays on

## Emitted when a one-shot effect has fully finished (never for looping effects).
signal finished

const DELAY_META := &"vfx_delay"
const FLASH_META := &"vfx_flash"
const FLICKER_META := &"vfx_flicker"

## Start as soon as the effect is added to the scene.
@export var autoplay := true
## One-shot effects only: free the node once it has finished playing.
@export var auto_free := true
## Plays the whole effect faster (above 1) or slower (below 1).
@export_range(0.05, 4.0, 0.05) var time_scale := 1.0:
	set(value):
		time_scale = value
		for layer in _layers():
			layer.speed_scale = value
## Replays the effect in the editor viewport.
@export_tool_button("Replay", "Play") var replay_button := play

var _light_energy := {}
var _play_id := 0
var _clock := 0.0


func _ready() -> void:
	# Lights are only animated in the running game, so the editor never saves a faded energy.
	if not Engine.is_editor_hint():
		for light in _lights():
			_light_energy[light] = light.light_energy
			if light.get_meta(FLASH_META, 0.0) > 0.0:
				light.light_energy = 0.0
	time_scale = time_scale
	set_process(_light_energy.keys().any(func(l): return l.get_meta(FLICKER_META, 0.0) > 0.0))
	if autoplay:
		# Deferred so spawn() can place the effect before its particles start emitting.
		play.call_deferred()


## Spawns an effect scene under [param parent] at a world position and returns it.
static func spawn(scene: PackedScene, parent: Node, at: Vector3, orientation := Basis.IDENTITY) -> VFXEffect:
	var fx := scene.instantiate() as VFXEffect
	parent.add_child(fx)
	fx.global_transform = Transform3D(orientation, at)
	return fx


## Plays (or replays) every layer from the start.
func play() -> void:
	if not is_inside_tree():
		return
	_play_id += 1
	var id := _play_id
	for layer in _layers():
		_start_layer(layer, id)
	for light: Light3D in _light_energy:
		_start_light(light, id)
	if is_looping():
		return
	await get_tree().create_timer(get_duration()).timeout
	if id != _play_id or not is_inside_tree():
		return
	finished.emit()
	if auto_free and not Engine.is_editor_hint():
		queue_free()


## Stops emitting. Particles already alive finish naturally; lights fade out.
## With auto_free on, the node frees itself once the last particle is gone.
func stop() -> void:
	_play_id += 1
	var id := _play_id
	var longest := 0.0
	for layer in _layers():
		layer.emitting = false
		longest = maxf(longest, layer.lifetime)
	for light: Light3D in _light_energy:
		create_tween().tween_property(light, "light_energy", 0.0, 0.3)
	if auto_free and not Engine.is_editor_hint():
		await get_tree().create_timer(longest / time_scale).timeout
		if id == _play_id and is_inside_tree():
			queue_free()


## Plays a ripple on any shield-type mesh in this effect (materials with a hit_progress parameter).
func impact(world_position: Vector3, duration := 0.6) -> void:
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		var mat := mesh.get_active_material(0) as ShaderMaterial
		if mat == null or mat.shader == null:
			continue
		if not mat.shader.get_shader_uniform_list().any(func(u): return u.name == "hit_progress"):
			continue
		mat.set_shader_parameter("hit_position", mesh.to_local(world_position))
		mat.set_shader_parameter("hit_progress", 0.0)
		create_tween().tween_method(func(v: float): mat.set_shader_parameter("hit_progress", v), 0.0, 1.0, duration)


## True when any layer keeps emitting forever.
func is_looping() -> bool:
	return _layers().any(func(l: GPUParticles3D): return not l.one_shot)


## Seconds until every one-shot layer and flash light is done, at the current time_scale.
func get_duration() -> float:
	var longest := 0.0
	for layer in _layers():
		# With explosiveness below 1, the last particle is born up to one lifetime late.
		var life := layer.lifetime * (2.0 - layer.explosiveness)
		longest = maxf(longest, layer.get_meta(DELAY_META, 0.0) + life)
	for light in _lights():
		longest = maxf(longest, light.get_meta(DELAY_META, 0.0) + light.get_meta(FLASH_META, 0.0))
	return longest / time_scale


func _process(delta: float) -> void:
	_clock += delta
	for light: Light3D in _light_energy:
		var amount: float = light.get_meta(FLICKER_META, 0.0)
		if amount > 0.0 and is_instance_valid(light):
			var wave := sin(_clock * 23.0) * 0.5 + sin(_clock * 7.3 + 1.7) * 0.5
			light.light_energy = _light_energy[light] * (1.0 - amount * 0.5 + amount * 0.5 * wave)


func _start_layer(layer: GPUParticles3D, id: int) -> void:
	layer.emitting = false
	var delay: float = layer.get_meta(DELAY_META, 0.0)
	if delay > 0.0:
		await get_tree().create_timer(delay / time_scale).timeout
		if id != _play_id or not is_inside_tree():
			return
	layer.restart()


func _start_light(light: Light3D, id: int) -> void:
	var flash: float = light.get_meta(FLASH_META, 0.0)
	var energy: float = _light_energy.get(light, light.light_energy)
	if flash <= 0.0:
		light.light_energy = energy
		return
	light.light_energy = 0.0
	var delay: float = light.get_meta(DELAY_META, 0.0)
	if delay > 0.0:
		await get_tree().create_timer(delay / time_scale).timeout
		if id != _play_id or not is_inside_tree():
			return
	light.light_energy = energy
	create_tween().tween_property(light, "light_energy", 0.0, flash / time_scale) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _layers() -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	out.assign(find_children("*", "GPUParticles3D", true, false))
	return out


func _lights() -> Array[Light3D]:
	var out: Array[Light3D] = []
	out.assign(find_children("*", "Light3D", true, false))
	return out
