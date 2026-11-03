extends SceneTree
## Twelve simultaneous headless room worlds: both owners, all six gate targets.
const Physics := preload("res://network/online_physics.gd")
var failures := 0
var checks := 0
var completed := 0
var worlds: Array = []
var results: Array = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
func _initialize() -> void:
	Engine.max_fps = 60
	Engine.physics_ticks_per_second = 60
	call_deferred("run")
func run() -> void:
	check(Physics.RADIUS == CreatureBall.RADIUS,"same physical sphere radius")
	check(is_equal_approx(Physics.SHELL_RADIUS,CreatureBall._shell_r()),"same rolling shell radius")
	check(Physics.CARD_W == Arena.CARD_W and Physics.CARD_H == Arena.CARD_H,"same gate width and height")
	check(Physics.STEP_X == Arena.STEP_X and Physics.STEP_Z == Arena.STEP_Z,"same slot grid")
	check(is_equal_approx(Physics.SURFACE_Y,ArenaCardNode.SURFACE_Y),"same raised card top")
	check(Physics.PHYS_HALF == Arena.PHYS_HALF and Physics.WALL_HEIGHT == Arena.WALL_HEIGHT,"same floor walls")
	check(is_equal_approx(Physics.START_Z,Arena.STEP_Z*.5+Arena.CARD_H*.5+.8*Arena.WORLD),"same initial throw position")
	var arena := Arena.new()
	for slot in 6:
		check(Physics.slot_position(slot).is_equal_approx(arena.slot_position(slot)),"slot position %d"%slot)
		check(Physics.slot_at(Physics.slot_position(slot)+Vector3(1,1,-1)) == slot,"slot real position %d"%slot)
	check(Physics.slot_at(Vector3(120,0,120)) == -1,"outside cards is a miss")
	check(Physics.slot_at(Vector3(0,-2,0)) == -1,"below floor is a miss")
	arena.free()
	for owner in 2:
		for slot in 6:
			var world := Physics.new()
			root.add_child(world)
			worlds.append(world)
			_run_throw(world,owner,slot)
	for frame in 650:
		await process_frame
		if completed == 12: break
	check(completed == 12,"all twelve physical throws finish")
	check(worlds.size() == 12,"twelve independent room worlds")
	for i in worlds.size():
		for j in range(i):
			check(worlds[i]._world.get_world_3d().space != worlds[j]._world.get_world_3d().space,"room physics isolation %d/%d"%[i,j])
	# No graphics/catalog/model scene is required in any authoritative world.
	for world in worlds:
		check(world.find_children("*","GeometryInstance3D",true,false).is_empty(),"authoritative physics has no graphics")
		world.queue_free()
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/checks/online-physics"))
	var report := FileAccess.open("res://build/checks/online-physics/summary.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"throws":results,"physics_hz":60,"max_fps":60},"  "))
	print("Online physics: %d checks, %d errors; 12 physical room throws"%[checks,failures])
	quit(1 if failures else 0)
func _run_throw(world: Node3D, owner: int, slot: int) -> void:
	var gates: Array[int] = [0,1,2,3,4,5]
	var result: Dictionary = await world.throw_ball(owner,owner*3+slot,slot,gates,1400+owner*6+slot)
	check(not result.is_empty(),"physical result exists")
	if result.is_empty():
		completed += 1
		return
	check(result.slot == slot,"actual landing on requested gate %d/%d"%[owner,slot])
	check(not result.timed_out,"physical stop before timeout")
	check(result.bounces >= 2,"multiple real bounces")
	var samples: Array = result.samples
	check(samples.size() > 60 and samples.size() <= Physics.MAX_SAMPLES,"bounded full physical trajectory")
	check(is_equal_approx(result.duration,float(samples.size()-1)/60.0),"replay frame duration")
	var first: Array = samples.front()
	check(is_equal_approx(first[2],Physics.START_Z*(1 if owner == 0 else -1)),"correct owner's starting side")
	var last: Array = samples.back()
	check(result.position == last.slice(0,3),"landing position is last real sample")
	check(result.quaternion == last.slice(3,7),"landing orientation is last real sample")
	var actual := Vector3(last[0],last[1],last[2])
	check(actual.y > .25 and actual.y < .45,"sphere resting on card without falling through")
	check(actual.distance_to(Physics.slot_position(slot)) > .40,"landing keeps real position without center snap")
	for sample in samples:
		check(sample.size() == 7,"position and quaternion sample")
		check(Vector3(sample[0],sample[1],sample[2]).is_finite(),"finite physical position")
		var q := Quaternion(sample[3],sample[4],sample[5],sample[6])
		check(q.is_finite() and is_equal_approx(q.length(),1.0),"finite normalized rotation")
	check(await world.throw_ball(3,9,slot,gates,1) == {},"invalid owner rejected")
	check(await world.throw_ball(owner,9,6,gates,1) == {},"invalid target rejected")
	results.append(result)
	completed += 1
	print("ONLINE_SHOT owner=%d slot=%d samples=%d bounces=%d landing=%s"%[owner,slot,samples.size(),result.bounces,result.position])
