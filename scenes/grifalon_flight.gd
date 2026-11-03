extends RefCounted
## Грифалон гребёт лапами в ритме фактического взмаха, не независимого таймера.
## Поправки вращают целую цепь; голеностоп сохраняет угол исходного клипа.
static func apply(support) -> void:
	if support == null or support.skeleton == null or support.actor._species != &"grifalon":
		return
	support.restore()
	var skeleton: Skeleton3D = support.skeleton
	var actor: Node3D = support.actor
	var chest := skeleton.find_bone("chest")
	var body := Basis.IDENTITY
	if chest >= 0:
		body = skeleton.get_bone_global_pose(chest).basis.orthonormalized() * skeleton.get_bone_global_rest(chest).basis.orthonormalized().inverse()
	var up := (skeleton.global_basis.inverse() * actor.global_basis.y).normalized()
	var axis := (body * skeleton.global_basis.inverse() * actor.global_basis.x).normalized()
	var previous: Dictionary = support.get_meta("grifalon_flight_phase", {})
	var now: float = actor._clock
	var elapsed: float = now - float(previous.get("time", now))
	var next_strokes: Dictionary = {}
	for limb in support.limbs:
		var lift := _wing_lift(skeleton, String(limb.side), body, up)
		# Крылья имеют разные исходные развороты суставов. Измеренные диапазоны
		# наклона двух сторон дают одинаковую умеренную амплитуду лап.
		var center := .07 if limb.side == "R" else .045
		var amplitude := .185 if limb.side == "R" else .14
		var stroke := sin(clampf((lift - center) / amplitude, -1.0, 1.0) * PI * .5)
		# Крыло в атаке может резко сменить фазу; лапа с инерцией догоняет его.
		# Время задаёт только предел скорости, фазу всегда задаёт реальное крыло.
		if previous.has(limb.side) and elapsed >= 0:
			stroke = move_toward(float(previous[limb.side]), stroke, 12.0 * minf(elapsed, .1))
		next_strokes[limb.side] = stroke
		var sweep := Basis(axis, deg_to_rad(-4.0 + 9.0 * stroke))
		var upper_pose := skeleton.get_bone_global_pose(limb.a)
		var lower_pose := skeleton.get_bone_global_pose(limb.b)
		var foot_pose := skeleton.get_bone_global_pose(limb.c)
		var upper_dir := (lower_pose.origin - upper_pose.origin).normalized()
		var lower_dir := (foot_pose.origin - lower_pose.origin).normalized()
		var knee_angle := lower_dir.angle_to(upper_dir)
		var unbend_axis := lower_dir.cross(upper_dir)
		var lower_motion := sweep
		# Распрямляем только в анатомической плоскости колена, не прибавляя
		# второй сгиб поверх скульпта. Через прямую ногу не переходим.
		if unbend_axis.length_squared() > .000001:
			var extension := minf(deg_to_rad(5.0) * (stroke * .5 + .5), knee_angle * .5)
			lower_motion *= Basis(unbend_axis.normalized(), extension)
		support._set_global_rotation(limb.a, sweep * upper_pose.basis.orthonormalized())
		support._set_global_rotation(limb.b, lower_motion * lower_pose.basis.orthonormalized())
		support._set_global_rotation(limb.c, lower_motion * foot_pose.basis.orthonormalized())
	next_strokes["time"] = now
	support.set_meta("grifalon_flight_phase", next_strokes)


static func _wing_lift(skeleton: Skeleton3D, side: String, body: Basis, up: Vector3) -> float:
	var wing := skeleton.find_bone("wing." + side)
	var tip := skeleton.find_bone("wingtip." + side)
	if wing < 0 or tip < 0:
		return 0.0
	var span := skeleton.get_bone_rest(tip).origin
	var rest := (skeleton.get_bone_global_rest(wing).basis * span).normalized()
	var current := (body.inverse() * skeleton.get_bone_global_pose(wing).basis * span).normalized()
	return current.dot(up) - rest.dot(up)
