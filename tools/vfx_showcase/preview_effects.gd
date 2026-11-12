extends RefCounted

const SHAFT_SHADER := preload("res://assets/vfx_vendor/effects_lab/shaft.gdshader")
const REEBOO_SCENES := [
	preload("res://assets/vfx_vendor/reeboo/effects/hit_spark.tscn"),
	preload("res://assets/vfx_vendor/reeboo/effects/slash.tscn"),
	preload("res://assets/vfx_vendor/reeboo/effects/pickup_sparkle.tscn"),
]
const FIRE_IMPACT := preload("res://assets/vfx_vendor/elemental_impact/scenes/elem_fire.tscn")
const KENNEY_SPARK := preload("res://assets/vfx_vendor/kenney/spark_05.png")
const KENNEY_FLARE := preload("res://assets/vfx_vendor/kenney/flare_01.png")
const TRAIL_PATH := "res://assets/vfx_vendor/local/vefects/VFX/Particles/VFX_Trail_%s.tscn"
const TRAIL_NAMES := ["Cosmos", "Dark", "Earth", "Electric", "Fire", "Ice", "Nature", "Sound", "Void", "Water"]


static func shafts(parent: Node3D) -> void:
	var noise := NoiseTexture2D.new()
	noise.width = 128
	noise.height = 128
	var source := FastNoiseLite.new()
	source.seed = 9
	source.frequency = 0.05
	noise.noise = source
	for offset in [-0.72, 0.0, 0.72]:
		var origin := Vector3(-2.55 + offset, 3.65, -2.05)
		var target := Vector3(0.75 + offset, 0.18, 0.75)
		var material := ShaderMaterial.new()
		material.shader = SHAFT_SHADER
		material.set_shader_parameter("noise_texture", noise)
		material.set_shader_parameter("color", Color("ffd5a2").lerp(Color("9cd9ff"), (offset + 0.72) / 1.44))
		material.set_shader_parameter("intensity", 0.24)
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.76, origin.distance_to(target))
		mesh.material = material
		var beam := MeshInstance3D.new()
		beam.name = "WindowShaft%d" % parent.get_child_count()
		beam.mesh = mesh
		beam.position = (origin + target) * 0.5
		beam.basis = Basis(Quaternion(Vector3.UP, (origin - target).normalized()))
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(beam)


static func reeboo(parent: Node3D, index: int, position: Vector3) -> VFXEffect:
	var effect := REEBOO_SCENES[index].instantiate() as VFXEffect
	effect.position = position
	effect.scale = Vector3.ONE * 0.78
	for light in effect.find_children("*", "OmniLight3D", true, false):
		light.light_energy *= 0.36
	for layer: GPUParticles3D in effect.find_children("*", "GPUParticles3D", true, false):
		var material := layer.material_override.duplicate() as ShaderMaterial
		material.set_shader_parameter("emission_energy", float(material.get_shader_parameter("emission_energy")) * 0.52)
		layer.material_override = material
		layer.use_fixed_seed = true
		layer.seed = 143
		if not layer.one_shot:
			layer.preprocess = 0.65
	parent.add_child(effect)
	return effect


static func fire_impact(parent: Node3D, position: Vector3) -> FreeElementalFx:
	var effect := FIRE_IMPACT.instantiate() as FreeElementalFx
	# The imported resources stay intact for reuse. Scale the HDR values on this instance.
	var preset := effect.preset.duplicate() as FreeElementalFxPreset
	preset.color_core = Color(1.28, 0.91, 0.49)
	preset.color_main = Color(1.16, 0.37, 0.09)
	preset.color_accent = Color(0.78, 0.17, 0.06)
	preset.sparks_amount = 24
	preset.light_energy = 2.7
	preset.light_range = 3.4
	effect.preset = preset
	effect.position = position
	effect.scale = Vector3.ONE * 0.88
	effect.loop = false
	effect.one_shot_free = true
	parent.add_child(effect)
	return effect


static func kenney(parent: Node3D, position: Vector3) -> void:
	var burst := Node3D.new()
	burst.position = position
	parent.add_child(burst)
	_kenney_layer(burst, KENNEY_FLARE, 4, 0.48, Color("7ee8fe"), 0.55, 1.2)
	_kenney_layer(burst, KENNEY_SPARK, 19, 0.75, Color("c4fff3"), 1.1, 3.1)
	burst.get_tree().create_timer(1.0).timeout.connect(burst.queue_free)


static func _kenney_layer(parent: Node3D, texture: Texture2D, count: int, duration: float, tint: Color, speed_min: float, speed_max: float) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = tint
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (0.68 if count < 10 else 0.36)
	quad.material = material

	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.52, Color(1.0, 1.0, 1.0, 0.86))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 125.0
	motion.gravity = Vector3(0.0, -1.1, 0.0)
	motion.initial_velocity_min = speed_min
	motion.initial_velocity_max = speed_max
	motion.angle_min = -180
	motion.angle_max = 180
	motion.scale_min = 0.45
	motion.scale_max = 1.25
	motion.color_ramp = fade_texture

	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = duration
	particles.explosiveness = 1.0
	particles.use_fixed_seed = true
	particles.seed = 51
	particles.process_material = motion
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(particles)
	particles.restart()


static func trail(parent: Node3D, element: String, audible: bool = false) -> Node3D:
	var path := TRAIL_PATH % element
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	var scene := load(path) as PackedScene
	var effect := scene.instantiate() as Node3D
	for sound: AudioStreamPlayer3D in effect.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.autoplay = audible
		sound.volume_db -= 10.0
	for ribbon in effect.find_children("*", "MeshInstance3D", true, false):
		if not ribbon.has_method("clear"):
			continue
		ribbon.set("width", float(ribbon.get("width")) * 0.29)
		ribbon.set("time", clampf(float(ribbon.get("time")) * 0.5, 0.28, 0.78))
		ribbon.set("min_vertex_distance", 0.055)
		var samples: PackedColorArray = ribbon.get("color_samples")
		for index in samples.size():
			samples[index].a *= 0.76
		ribbon.set("color_samples", samples)
	parent.add_child(effect)
	return effect
