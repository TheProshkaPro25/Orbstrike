extends SceneTree
## Настоящие RigidBody3D: оба направления, все ворота, обычный/ускоренный темп.
var failures := 0
var done := 0
var balls: Array[CreatureBall] = []
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps = 60
	var arena := Arena.new()
	root.add_child(arena)
	for slot in 6:
		var card := ArenaCardNode.new()
		arena.add_child(card)
		card.global_position = arena.slot_position(slot)
		card.set_field_surface(true)
	for setting in [Vector2(60, 1), Vector2(60, 2), Vector2(240, 4)]:
		var ticks := int(setting.x)
		Engine.time_scale = setting.y
		Engine.physics_ticks_per_second = ticks
		done = 0
		for side in [1.0, -1.0]:
			for slot in 6:
				var b := CreatureBall.new()
				root.add_child(b)
				b.freeze_at(Vector3(0, CreatureBall.RADIUS+.01, 34.8 * side))
				var goal := arena.slot_position(slot) + Vector3(1.5, 0, -1.5)
				b.settled.connect(func(ball: CreatureBall, p: Vector3) -> void:
					check(ball.bounce_count >= 2, "несколько отскоков: %s/%s/%s" % [ticks, side, slot])
					check(arena.slot_at(p) == slot, "остановка на выбранных воротах")
					check(ball._t < 8, "остановка до аварийного таймаута")
					check(p.y > .25 and p.y < .45, "контакт с поверхностью без провала")
					check(ball._shell.global_position.y-ball._shell.scale.x >= -.005,"маленькая оболочка не погружается в пол")
					check(ball._shell.global_position.y-ball._shell.scale.x >= ArenaCardNode.SURFACE_Y-.001,"оболочка лежит на карте, а не внутри неё")
					print("SHOT ticks=%d side=%d slot=%d bounces=%d rest=%s" % [ticks, side, slot, ball.bounce_count, p])
					done += 1)
				b.launch_towards(goal)
				b.collision_layer = 0 # параллельные пробы не сталкиваются друг с другом
				balls.append(b)
		for frame in 1500:
			await process_frame
			if done == 12: break
		check(done == 12, "все 12 бросков завершились")
		for b in balls: b.queue_free()
		balls.clear()
		await process_frame
	arena.queue_free()
	# Дождаться хвостов частиц и их отложенного освобождения, как в живом матче.
	await create_timer(3.0).timeout
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await process_frame
	print("Физические броски: 36, ошибок: ", failures)
	quit(1 if failures else 0)
