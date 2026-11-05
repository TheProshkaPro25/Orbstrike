extends RefCounted
## Локальные GPU шлейфы за игровой площадью. Ни одного кадрового CPU обработчика.
static var _cloud: Texture2D

static func _texture() -> Texture2D:
	if _cloud != null: return _cloud
	var noise := FastNoiseLite.new()
	noise.seed = 8147
	noise.frequency = .065
	noise.fractal_octaves = 4
	var image := Image.create(96,96,false,Image.FORMAT_RGBA8)
	for y in 96:
		for x in 96:
			var p := Vector2(x-47.5,y-47.5)/47.5
			var edge := maxf(0,1.0-p.length())
			var wisps := clampf(.55+noise.get_noise_2d(x,y)*1.15,0,1)
			image.set_pixel(x,y,Color(1,1,1,pow(edge,1.35)*wisps))
	image.generate_mipmaps()
	_cloud = ImageTexture.create_from_image(image)
	return _cloud

static func _plume(arena: Node3D, label: String, point: Vector3, count: int, lifetime: float, color: Color, velocity: Vector3, spread: Vector3, size: Vector2) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = label
	particles.position = point
	particles.amount = count
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.randomness = .22
	particles.fixed_fps = 30
	particles.interpolate = true
	particles.local_coords = false
	particles.use_fixed_seed = true
	particles.seed = 8147+count
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-28,-8,-20),Vector3(85,70,44))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = spread
	process.direction = velocity.normalized()
	process.spread = 12
	process.initial_velocity_min = velocity.length()*.8
	process.initial_velocity_max = velocity.length()*1.15
	process.gravity = Vector3(0,.06,0)
	process.angular_velocity_min = -9
	process.angular_velocity_max = 9
	process.scale_min = size.x
	process.scale_max = size.y
	var growth := Curve.new()
	growth.add_point(Vector2(0,.48))
	growth.add_point(Vector2(1,1.5))
	var curve := CurveTexture.new()
	curve.curve = growth
	process.scale_curve = curve
	var gradient := Gradient.new()
	gradient.set_color(0,Color(color,0))
	gradient.set_color(1,Color(color,0))
	gradient.add_point(.16,color)
	gradient.add_point(.65,Color(color,color.a*.65))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _texture()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	particles.draw_pass_1 = quad
	particles.set_meta("landscape_effect",true)
	particles.set_meta("full_amount",count)
	arena._decor.add_child(particles)
	arena._landscape_effects.append(particles)
	return particles

static func dust(arena: Node3D) -> void:
	# Боковой ветер несёт редкую пыль у основания скал и в проходе, вне r70.
	_plume(arena,"CanyonDustWest",Vector3(-90,9,-57),42,10,Color(.63,.41,.22,.30),Vector3(3.3,.20,.3),Vector3(14,1.2,4),Vector2(5,10))
	_plume(arena,"CanyonDustPass",Vector3(7,14,-150),34,12,Color(.69,.47,.26,.32),Vector3(3.0,.28,.1),Vector3(8,1,6),Vector2(5,11))
	_plume(arena,"CanyonDustEast",Vector3(95,8,40),26,10,Color(.66,.43,.24,.26),Vector3(.7,.22,2.5),Vector3(5,1,12),Vector2(4,8))

static func smoke(arena: Node3D, points: Array[Vector3]) -> void:
	for i in points.size():
		_plume(arena,"HarborChimneySmoke%d" % i,points[i],24,10,Color(.34,.43,.48,.40),Vector3(1.7,2.0,.25),Vector3(.22,.05,.22),Vector2(2.1,3.7))

static func active(arena: Node3D, enabled: bool) -> void:
	for particles: GPUParticles3D in arena._landscape_effects:
		particles.emitting = enabled
		# DISABLED останавливает CPU наследников; speed_scale=0 явно останавливает GPU.
		particles.speed_scale = 1.0 if enabled else 0.0
		if enabled: particles.restart()

static func quality(arena: Node3D, low: bool) -> void:
	for particles: GPUParticles3D in arena._landscape_effects:
		particles.amount_ratio = .55 if low else 1.0
