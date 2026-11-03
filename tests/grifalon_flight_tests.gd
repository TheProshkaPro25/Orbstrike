extends SceneTree
const Flight := preload("res://scenes/grifalon_flight.gd")
const Cleanup := preload("res://scenes/model_lifetime.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	CardDB.load_all()
	var variants := 0
	for d in CardDB.all_creatures():
		if d.species != &"grifalon": continue
		variants += 1
		var actor := CreatureAnim.new()
		root.add_child(actor)
		actor.set_process(false)
		actor.set_model(CreatureModels.build(d), d)
		actor._phase = 0
		var support = actor._support
		actor._support = null
		var skeleton: Skeleton3D = support.skeleton
		for action in ["idle", "attack"]:
			support.reset()
			actor.reset()
			actor.idle_on = true
			actor._player.stop()
			actor._player.play("idle", 0)
			actor._player.advance(0)
			if action == "attack": actor.lunge(actor.get_height() * .22)
			var previous: Array[Quaternion] = []
			var corrections: Array = [[], []]
			var first_hip := Quaternion.IDENTITY
			var max_hip_motion := 0.0
			var first_tail := Quaternion.IDENTITY
			var max_tail_motion := 0.0
			var tail1 := skeleton.find_bone("tail1")
			var tail4 := skeleton.find_bone("tail4")
			var rest_fan := skeleton.get_bone_global_rest(tail1).basis.orthonormalized().inverse() * skeleton.get_bone_global_rest(tail4).basis.orthonormalized()
			var knee_increase := 0.0
			var upper_names := ["chest", "neck", "head", "wing.L", "wing.R", "wingtip.L", "wingtip.R"]
			for frame in 300:
				support.restore()
				actor._process(1.0 / 120)
				var hip_pose := skeleton.get_bone_global_pose(support.hip).basis.orthonormalized().get_rotation_quaternion()
				if frame == 0: first_hip = hip_pose
				else: max_hip_motion = maxf(max_hip_motion, first_hip.angle_to(hip_pose))
				var tail_pose := skeleton.get_bone_pose_rotation(tail1)
				if frame == 0: first_tail = tail_pose
				else: max_tail_motion = maxf(max_tail_motion, first_tail.angle_to(tail_pose))
				var fan := skeleton.get_bone_global_pose(tail1).basis.orthonormalized().inverse() * skeleton.get_bone_global_pose(tail4).basis.orthonormalized()
				check(fan.get_rotation_quaternion().angle_to(rest_fan.get_rotation_quaternion()) < .001, "%s %s: хвостовой веер сохраняет rest-форму" % [d.id, action])
				var upper_before: Array[Transform3D] = []
				for name in upper_names:
					upper_before.append(skeleton.get_bone_global_pose(skeleton.find_bone(name)))
				var authored: Array = []
				var original: Array[Transform3D] = []
				for index in skeleton.get_bone_count(): original.append(skeleton.get_bone_pose(index))
				for limb in support.limbs:
					authored.append([skeleton.get_bone_global_pose(limb.a), skeleton.get_bone_global_pose(limb.b), skeleton.get_bone_global_pose(limb.c)])
				support.apply(1.0 / 120)
				Flight.apply(support)
				for index in upper_names.size():
					check(skeleton.get_bone_global_pose(skeleton.find_bone(upper_names[index])).is_equal_approx(upper_before[index]), "%s %s: полётные лапы не меняют верх/крылья" % [d.id, action])
				for i in support.limbs.size():
					var limb: Dictionary = support.limbs[i]
					var a: Transform3D = skeleton.get_bone_global_pose(limb.a)
					var b: Transform3D = skeleton.get_bone_global_pose(limb.b)
					var c: Transform3D = skeleton.get_bone_global_pose(limb.c)
					var before: Array = authored[i]
					var ankle_before: Basis = before[1].basis.orthonormalized().inverse() * before[2].basis.orthonormalized()
					var ankle_after: Basis = b.basis.orthonormalized().inverse() * c.basis.orthonormalized()
					check(ankle_before.get_rotation_quaternion().angle_to(ankle_after.get_rotation_quaternion()) < .001, "%s %s: угол голеностопа сохранён" % [d.id, action])
					check(absf(a.origin.distance_to(b.origin) - before[0].origin.distance_to(before[1].origin)) < .0001, "%s: бедро не растягивается" % d.id)
					check(absf(b.origin.distance_to(c.origin) - before[1].origin.distance_to(before[2].origin)) < .0001, "%s: голень не растягивается" % d.id)
					var knee_before: float = (before[1].origin - before[0].origin).angle_to(before[2].origin - before[1].origin)
					var knee_after := (b.origin - a.origin).angle_to(c.origin - b.origin)
					knee_increase = maxf(knee_increase, knee_after - knee_before)
					var correction: Quaternion = (a.basis.orthonormalized() * before[0].basis.orthonormalized().inverse()).get_rotation_quaternion()
					corrections[i].append(correction)
					if frame > 0:
						check(previous[i].angle_to(correction) < .06, "%s %s frame%d: нет скачка полётной поправки %.3f°" % [d.id, action, frame, rad_to_deg(previous[i].angle_to(correction))])
					if frame == 0: previous.append(correction)
					else: previous[i] = correction
				# Изменение чужого clock при той же позе крыла не меняет лапы.
				if frame == 150:
					var fixed: Array[Transform3D] = []
					for index in skeleton.get_bone_count(): fixed.append(skeleton.get_bone_pose(index))
					support.restore()
					var clock := actor._clock
					var original_phase: Dictionary = support.get_meta("grifalon_flight_phase").duplicate(true)
					var shifted_phase := original_phase.duplicate(true)
					shifted_phase.time += 197.0
					support.set_meta("grifalon_flight_phase", shifted_phase)
					actor._clock += 197.0
					Flight.apply(support)
					actor._clock = clock
					support.set_meta("grifalon_flight_phase", original_phase)
					for index in skeleton.get_bone_count(): check(skeleton.get_bone_pose(index).is_equal_approx(fixed[index]), "%s: лапы зависят от крыла, а не от clock" % d.id)
				support.restore()
				for index in skeleton.get_bone_count():
					check(skeleton.get_bone_pose(index).is_equal_approx(original[index]), "%s: restore возвращает исходную позу" % d.id)
			var ranges: Array = []
			for samples in corrections:
				var maximum := 0.0
				for i in range(0, samples.size(), 5):
					for j in range(i + 1, samples.size(), 5): maximum = maxf(maximum, samples[i].angle_to(samples[j]))
				ranges.append(rad_to_deg(maximum))
				if action == "idle": check(maximum >= deg_to_rad(12) and maximum <= deg_to_rad(20), "%s: выраженный, умеренный ход лапы %.2f°" % [d.id, rad_to_deg(maximum)])
			check(knee_increase < .002, "%s %s: исходный сгиб колена не усугубляется (%.3f°)" % [d.id, action, rad_to_deg(knee_increase)])
			check(max_hip_motion > .01, "%s %s: таз движется вместе с корпусом" % [d.id, action])
			check(max_tail_motion > .01, "%s %s: основание хвоста сохраняет исходное движение" % [d.id, action])
			print("GRIFALON %s %s sweep_deg=%s max_knee_increase_deg=%.4f hip_motion_deg=%.3f tail_motion_deg=%.3f" % [d.id, action, ranges, rad_to_deg(knee_increase), rad_to_deg(max_hip_motion), rad_to_deg(max_tail_motion)])
		Cleanup.release(actor, self)
		CreatureModels.clear()
		await process_frame
	check(variants == 6, "проверены все шесть стихий Грифалона")
	await process_frame
	print("Полётные лапы Грифалона: %d проверок, %d ошибок" % [checks, failures])
	quit(1 if failures else 0)
