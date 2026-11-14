extends SceneTree
## Реальные физические броски: мировой transform оболочки непрерывен при раскрытии,
## фигура вертикальна, повторное использование не накапливает предыдущий наклон.
var failures := 0
var checks := 0
var rotated_landings := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Engine.max_fps = 60
	Engine.time_scale = 4
	Engine.physics_ticks_per_second = 240
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	floor_shape.shape = box
	floor_shape.position.y = -.5
	floor_body.add_child(floor_shape)
	var material := PhysicsMaterial.new()
	material.bounce = 0
	material.friction = 0
	floor_body.physics_material_override = material
	root.add_child(floor_body)
	for side in [-1.0, 1.0]:
		var ball := CreatureBall.new()
		root.add_child(ball)
		for reuse in 2:
			var start := Vector3(0, .36, 34.8 * side)
			ball.freeze_at(start)
			ball.close_up()
			check(not ball._landing_shell_held and ball._shell.rotation.is_zero_approx(), "новый бросок не наследует наклон прошлой оболочки")
			var final_pose: Array = []
			var capture := func(_ball: CreatureBall, _pos: Vector3) -> void:
				final_pose.append([ball.global_transform, ball._shell.global_transform])
			ball.settled.connect(capture, CONNECT_ONE_SHOT)
			ball.launch_towards(Vector3(-18 + reuse * 31, 0, -17 * side))
			for frame in 1100:
				await process_frame
				if not final_pose.is_empty(): break
			check(not final_pose.is_empty(), "физический бросок завершился")
			if final_pose.is_empty(): continue
			var body_pose: Transform3D = final_pose[0][0]
			var shell_pose: Transform3D = final_pose[0][1]
			if body_pose.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) > .05:
				rotated_landings += 1
			check(ball.bounce_count >= 2, "перед переходом были настоящие отскоки")
			ball.hold_landing_pose()
			check(ball.global_position.is_equal_approx(body_pose.origin), "тело осталось в фактической точке остановки")
			check(ball._shell.global_transform.is_equal_approx(shell_pose), "фиксация не изменила мировую позицию и поворот оболочки")
			ball.hold_landing_pose() # сцена повторно фиксирует шар перед облётом
			check(ball._shell.global_transform.is_equal_approx(shell_pose), "повторная фиксация не обнулила позу оболочки")
			await create_timer(.2).timeout
			check(ball._shell.global_transform.is_equal_approx(shell_pose), "пауза перед раскрытием сохраняет всю позу")
			ball.face_toward(ball.global_position + Vector3.FORWARD)
			var opening: Signal = ball.open_animated()
			check(ball._shell.global_transform.is_equal_approx(shell_pose), "первый кадр пластин продолжает физическую позу")
			var rotation := shell_pose.basis.orthonormalized()
			var saw_shrinking_shell := false
			for frame in 60:
				await process_frame
				if ball._shell.visible:
					saw_shrinking_shell = saw_shrinking_shell or ball._shell.scale.x < CreatureBall._shell_r() * .9
					check(ball._shell.global_position.is_equal_approx(shell_pose.origin), "центр оболочки не сползает при уменьшении")
					check(ball._shell.global_basis.orthonormalized().is_equal_approx(rotation), "оболочка сохраняет угол при раскрытии")
				check(ball._figure.global_basis.orthonormalized().y.dot(Vector3.UP) > .9999, "существо выходит вертикально, независимо от наклона шара")
				if not ball._open_tween.is_running(): break
			check(saw_shrinking_shell, "проверка охватила фазу уменьшения оболочки")
			if ball._open_tween.is_running(): await opening
			check(ball._open and not ball._shell.visible, "раскрытие завершено")
		ball.queue_free()
		await process_frame
	check(rotated_landings == 4, "все четыре пробы реально остановились с ненулевым физическим поворотом")
	floor_body.queue_free()
	await create_timer(4.0).timeout
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await process_frame
	print("Непрерывность позы сферы: %d проверок, %d ошибок, %d физических остановок с поворотом" % [checks, failures, rotated_landings])
	quit(1 if failures else 0)
