class_name ShotPhysics
extends RefCounted
## Начальная скорость подбирается до броска. В полёте шар ведёт RigidBody3D,
## столкновения и отскоки решает движок; наведения и переноса в центр карты нет.
const GRAVITY := 44.0
const LIFT := 15.0
const RESTITUTION := 0.46
const AIR_DRAG := 0.16
const ROLL_DECEL := 34.0
const REST_VERTICAL := 2.5

static func predicted_range(speed: float, start_y: float, radius: float = .35) -> float:
	var y := start_y
	var vy := LIFT
	var distance := 0.0
	var dt := 1.0 / 120.0
	for i in 1200:
		var floor_contact := y <= radius + .025 and absf(vy) < REST_VERTICAL
		if floor_contact:
			vy = 0.0
			speed = maxf(0, speed - ROLL_DECEL * dt)
		else:
			speed /= 1.0 + AIR_DRAG * dt
		distance += speed * dt
		y += vy * dt
		vy -= GRAVITY * dt
		if y < radius:
			y = radius
			vy = -vy * RESTITUTION
		if floor_contact and speed < .12:
			break
	return distance

static func velocity_to(start: Vector3, destination: Vector3, radius: float = .35) -> Vector3:
	var offset := Vector3(destination.x - start.x, 0, destination.z - start.z)
	var low := 0.0
	var high := 110.0
	for i in 23:
		var middle := (low + high) * .5
		if predicted_range(middle, start.y, radius) < offset.length(): low = middle
		else: high = middle
	return offset.normalized() * (low + high) * .5 + Vector3.UP * LIFT

## Shared custom-integrator step for local and authoritative online throws.
## Collision response and contact positions remain the physics engine's work.
static func step_velocity(velocity: Vector3, floor_contact: bool, delta: float) -> Vector3:
	var rolling := floor_contact and absf(velocity.y) < REST_VERTICAL
	var flat := Vector3(velocity.x, 0, velocity.z)
	if rolling:
		velocity.y = 0.0
		flat = flat.move_toward(Vector3.ZERO, ROLL_DECEL * delta)
	else:
		flat /= 1.0 + AIR_DRAG * delta
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y -= GRAVITY * delta
	return velocity

static func spin_velocity(velocity: Vector3, rolling: bool, shell_radius: float) -> Vector3:
	return Vector3(-velocity.z, 0, velocity.x) / shell_radius * (.95 if rolling else .38)
