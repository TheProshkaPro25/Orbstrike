class_name OnlinePhysics
extends Node3D
## Authoritative, graphics-free physical throw in a room's private physics world.
## The server sends recorded transforms; clients never decide the landing.
const Motion := preload("res://scenes/shot_physics.gd")
const RADIUS := 0.35
const SHELL_RADIUS := 0.045
# Keep the physical board identical to Arena/ArenaCardNode. The focused regression
# checks these dimensions against the real arena without constructing its art.
const CARD_W := 20.78125
const CARD_H := 29.09375
const STEP_X := 26.03125
const STEP_Z := 34.34375
const SURFACE_Y := 0.052
const PHYS_HALF := 130.0
const WALL_HEIGHT := 6.0
const START_Z := STEP_Z * 0.5 + CARD_H * 0.5 + 2.8
const MAX_SAMPLES := 600

var _viewport: SubViewport
var _world: Node3D
var _busy := false

class ShotBody extends RigidBody3D:
	var gate_slots: Array[int] = []
	var elapsed := 0.0
	var slow := 0.0
	var done := false
	var on_surface := false
	var previous_vy := 0.0
	var bounce_count := 0
	var samples: Array = []

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if done: return
		var velocity := state.linear_velocity
		var point := state.transform.origin
		var height := 0.0
		for slot in gate_slots:
			var center := slot_position(slot)
			if absf(point.x-center.x) <= CARD_W*.5 and absf(point.z-center.z) <= CARD_H*.5:
				height = SURFACE_Y
		on_surface = point.y < RADIUS + height + .04
		if previous_vy < -Motion.REST_VERTICAL and velocity.y > .5:
			bounce_count += 1
		var rolling := on_surface and absf(velocity.y) < Motion.REST_VERTICAL
		velocity = Motion.step_velocity(velocity, on_surface, state.step)
		previous_vy = velocity.y
		state.linear_velocity = velocity
		state.angular_velocity = Motion.spin_velocity(velocity, rolling, SHELL_RADIUS)

	func _physics_process(delta: float) -> void:
		if done: return
		elapsed += delta
		samples.append(transform_sample(global_transform))
		var speed := Vector2(linear_velocity.x, linear_velocity.z).length()
		var on_floor := (on_surface or position.y < RADIUS+.10) and absf(linear_velocity.y) < Motion.REST_VERTICAL
		slow = slow + delta if on_floor and speed < .17 else 0.0
		if slow >= .15 or elapsed >= 9.0 or position.y < -2.0 or samples.size() >= MAX_SAMPLES:
			done = true
			# Preserve the actual solved transform, including rotation, when stopped.
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			freeze = true

	static func slot_position(slot: int) -> Vector3:
		return Vector3((slot%3-1)*STEP_X,0,(floori(slot/3.0)-.5)*STEP_Z)

	static func transform_sample(pose: Transform3D) -> Array:
		var q := pose.basis.orthonormalized().get_rotation_quaternion()
		return [pose.origin.x,pose.origin.y,pose.origin.z,q.x,q.y,q.z,q.w]

func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "RoomPhysicsWorld"
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.size = Vector2i(2,2)
	add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var floor_body := StaticBody3D.new()
	var material := PhysicsMaterial.new()
	material.friction = .6
	material.bounce = 0.0
	floor_body.physics_material_override = material
	_world.add_child(floor_body)
	_add_box(floor_body,Vector3(PHYS_HALF*2+20,1,PHYS_HALF*2+20),Vector3(0,-.5,0))
	for wall in [[Vector3(PHYS_HALF*2,WALL_HEIGHT,2),Vector3(0,WALL_HEIGHT*.5,-PHYS_HALF)],
		[Vector3(PHYS_HALF*2,WALL_HEIGHT,2),Vector3(0,WALL_HEIGHT*.5,PHYS_HALF)],
		[Vector3(2,WALL_HEIGHT,PHYS_HALF*2),Vector3(-PHYS_HALF,WALL_HEIGHT*.5,0)],
		[Vector3(2,WALL_HEIGHT,PHYS_HALF*2),Vector3(PHYS_HALF,WALL_HEIGHT*.5,0)]]:
		_add_box(floor_body,wall[0],wall[1])

static func _add_box(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)

static func slot_position(slot: int) -> Vector3:
	return ShotBody.slot_position(slot)

static func slot_at(point: Vector3) -> int:
	if point.y < -1.0: return -1
	for slot in 6:
		var center := slot_position(slot)
		if absf(point.x-center.x) <= CARD_W*.5 and absf(point.z-center.z) <= CARD_H*.5: return slot
	return -1

static func transform_sample(pose: Transform3D) -> Array:
	return ShotBody.transform_sample(pose)

func throw_ball(owner: int, uid: int, target_slot: int, gate_slots: Array[int], shot_seed: int) -> Dictionary:
	if _busy or not is_inside_tree() or _world == null or owner not in [0,1] or target_slot not in gate_slots or target_slot < 0 or target_slot > 5:
		return {}
	for slot in gate_slots:
		if slot < 0 or slot > 5: return {}
	if gate_slots.size() > 6: return {}
	_busy = true
	var cards := StaticBody3D.new()
	cards.collision_mask = 0
	_world.add_child(cards)
	for slot in gate_slots:
		_add_box(cards,Vector3(CARD_W,SURFACE_Y,CARD_H),slot_position(slot)+Vector3.UP*SURFACE_Y*.5)
	var ball := ShotBody.new()
	ball.gate_slots = gate_slots.duplicate()
	ball.mass = 1.0
	ball.custom_integrator = true
	ball.continuous_cd = true
	ball.max_contacts_reported = 8
	ball.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ball.linear_damp = 1.0
	ball.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ball.angular_damp = 1.5
	ball.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	ball.freeze = true
	ball.set_physics_process(false)
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = Motion.RESTITUTION
	ball.physics_material_override = material
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	ball.add_child(shape)
	ball.position = Vector3(0,.36,START_Z if owner == 0 else -START_Z)
	_world.add_child(ball)
	# Let newly installed collision shapes enter this room's isolated space.
	await get_tree().physics_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = shot_seed
	var target := slot_position(target_slot)+Vector3(rng.randf_range(-.20,.20)*CARD_W,0,rng.randf_range(-.18,.18)*CARD_H)
	ball.samples.append(transform_sample(ball.transform))
	ball.freeze = false
	ball.sleeping = false
	ball.linear_velocity = Motion.velocity_to(ball.position,target,RADIUS)
	ball.angular_velocity = Vector3(-ball.linear_velocity.z,0,ball.linear_velocity.x)/SHELL_RADIUS*.38
	ball.set_physics_process(true)
	while not ball.done:
		await get_tree().physics_frame
	var last: Array = ball.samples.back()
	var landed := slot_at(ball.position)
	if landed not in gate_slots: landed = -1
	var result := {"uid":uid,"slot":landed,"samples":ball.samples,"duration":float(ball.samples.size()-1)/60.0,
		"position":[last[0],last[1],last[2]],"quaternion":[last[3],last[4],last[5],last[6]],
		"bounces":ball.bounce_count,"timed_out":ball.elapsed >= 9.0}
	ball.queue_free()
	cards.queue_free()
	_busy = false
	return result
