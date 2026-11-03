extends SceneTree
## Раскрытие: камера не прыгает в первый кадр, затем непрерывно движется вокруг существа.
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var camera := CameraRig.new()
	root.add_child(camera)
	camera.set_process(false)
	var max_step := 0.0
	for side in [-1.0,1.0]:
		camera._set_static(Vector3(3,4,12*side),Vector3(0,1,0),{"fov":65.0,"hand":0.0})
		camera.cut()
		var before := camera.global_transform
		var duration := camera.reveal_orbit(Vector3.ZERO,12,Vector3(0,0,-side),15)
		check(camera.global_transform.is_equal_approx(before),"вход не меняет transform мгновенно")
		check(camera.mode==CameraRig.Mode.ORBIT,"раскрытие использует один облёт")
		var previous := camera.global_position
		for frame in ceili(duration*60):
			camera._process(1.0/60)
			var step := camera.global_position.distance_to(previous)
			max_step=maxf(max_step,step)
			check(step<2.5,"непрерывное движение вместо переключения ракурсов")
			check(camera.global_position.is_finite(),"положение камеры конечно")
			check(camera.global_position.y>=CameraRig.MIN_Y,"камера над полом")
			previous=camera.global_position
		check(previous.distance_to(before.origin)>5,"камера действительно облетела существо")
	camera.queue_free()
	await process_frame
	print("Smooth reveal: checks=",checks," failures=",failures," max_frame_step=",max_step)
	quit(1 if failures else 0)
