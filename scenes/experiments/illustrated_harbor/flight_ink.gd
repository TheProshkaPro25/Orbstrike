extends Node2D
## Short twin ink strokes laid down by the airborne sphere, redrawn with the
## active camera so each segment stays anchored in the trajectory.

const EXPIRY := .52
const INK := Color("#effafa")
var camera: CameraRig
var _tracked: Node3D
var _positions := PackedVector3Array()
var _times := PackedFloat32Array()
var _age := 0.0


func update_path(delta: float) -> void:
	_age += delta
	var ball := camera._follow as CreatureBall if camera.mode == CameraRig.Mode.FOLLOW else null
	if is_instance_valid(ball) and ball.linear_velocity.length_squared() > 16.0 and ball.global_position.y > CreatureBall.RADIUS + .8:
		if _tracked != ball:
			clear_path()
			_tracked = ball
		if _positions.is_empty() or _positions[-1].distance_squared_to(ball.global_position) > .08:
			_positions.append(ball.global_position)
			_times.append(_age)
	while not _times.is_empty() and _times[0] < _age - EXPIRY:
		_positions.remove_at(0)
		_times.remove_at(0)
	queue_redraw()


func clear_path() -> void:
	_positions.clear()
	_times.clear()
	_tracked = null
	queue_redraw()


func _draw() -> void:
	for i in range(1, _positions.size() - 1):
		var a := _positions[i - 1]
		var b := _positions[i]
		if camera.is_position_behind(a) or camera.is_position_behind(b):
			continue
		var across := (b - a).cross(Vector3.UP).normalized() * .19
		var fade := 1.0 - clampf((_age - _times[i]) / EXPIRY, 0.0, 1.0)
		for sign_value: float in [-1.0, 1.0]:
			var offset := across * sign_value
			var begin := camera.unproject_position(a + offset)
			var end := camera.unproject_position(b + offset)
			draw_line(begin, end, Color(.08, .27, .34, fade * .46), lerpf(2.2, 4.2, fade), true)
			draw_line(begin, end, Color(INK, fade * .74), lerpf(.75, 2.5, fade), true)
