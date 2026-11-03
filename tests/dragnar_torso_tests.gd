extends SceneTree
const Cleanup := preload("res://scenes/model_lifetime.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found := find_player(child)
		if found != null: return found
	return null

func track(animation: Animation, bone: StringName, type: int) -> int:
	for index in animation.get_track_count():
		var path := animation.track_get_path(index)
		if animation.track_get_type(index) == type and path.get_subname_count() == 1 and path.get_subname(0) == bone:
			return index
	return -1

func torso(animation: Animation, time: float, hips_rest: Vector3, chest_rest: Vector3) -> Transform3D:
	var hp := track(animation,&"hips",Animation.TYPE_POSITION_3D)
	var cp := track(animation,&"chest",Animation.TYPE_POSITION_3D)
	var hips := Transform3D(Basis(animation.rotation_track_interpolate(track(animation,&"hips",Animation.TYPE_ROTATION_3D),time)),animation.position_track_interpolate(hp,time) if hp>=0 else hips_rest)
	var chest := Transform3D(Basis(animation.rotation_track_interpolate(track(animation,&"chest",Animation.TYPE_ROTATION_3D),time)),animation.position_track_interpolate(cp,time) if cp>=0 else chest_rest)
	return hips * chest

func prepare_source(source: Animation, name: StringName) -> Animation:
	var animation := source.duplicate(true) as Animation
	for index in animation.get_track_count():
		if animation.track_get_type(index) in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D]:
			animation.track_set_interpolation_type(index,Animation.INTERPOLATION_CUBIC)
	animation.loop_mode = Animation.LOOP_LINEAR if name == &"idle" else Animation.LOOP_NONE
	if name == &"idle": CreatureAnim._prepare_idle_loop(animation)
	for index in animation.get_track_count(): animation.track_set_interpolation_loop_wrap(index,name == &"idle")
	return animation

func run() -> void:
	var summaries: Array = []
	for attribute in ["fire","gale","light","stone","shadow","tide"]:
		var definition := CardDB.creature(StringName("creature_dragnar_"+attribute))
		var model := CreatureModels.build(definition)
		var player := find_player(model)
		var baseline: Dictionary = {}
		for name in player.get_animation_list():
			baseline[name] = prepare_source(player.get_animation(name),name)
		var actor := CreatureAnim.new()
		root.add_child(actor)
		actor.set_process(false)
		actor.set_model(model,definition)
		var skeleton: Skeleton3D = actor._support.skeleton
		var hips_rest := skeleton.get_bone_rest(skeleton.find_bone(&"hips")).origin
		var chest_rest := skeleton.get_bone_rest(skeleton.find_bone(&"chest")).origin
		var worst_position := 0.0
		var worst_rotation := 0.0
		for name in baseline:
			var before: Animation = baseline[name]
			var after := actor._player.get_animation(name)
			check(is_equal_approx(before.length,after.length) and before.get_track_count() == after.get_track_count(),"same clip length and tracks "+attribute+"/"+String(name))
			var changed: bool = name in [&"idle",&"attack"]
			for index in before.get_track_count():
				var path := before.track_get_path(index)
				var allowed: bool = changed and path.get_subname_count() == 1 and path.get_subname(0) in [&"hips",&"chest"] and before.track_get_type(index)==Animation.TYPE_ROTATION_3D
				if allowed: continue
				check(before.track_get_key_count(index)==after.track_get_key_count(index),"untouched track key count "+String(path))
				var keys_identical := true
				for key in before.track_get_key_count(index):
					keys_identical = keys_identical and before.track_get_key_value(index,key)==after.track_get_key_value(index,key) and before.track_get_key_time(index,key)==after.track_get_key_time(index,key)
				check(keys_identical,"untouched non-torso curve "+String(path))
			if not changed: continue
			var h := track(after,&"hips",Animation.TYPE_ROTATION_3D)
			var first := after.rotation_track_interpolate(h,0)
			var movement := 0.0
			var clip_segment_error := 0.0
			var clip_rotation_error := 0.0
			for frame in range(ceili(before.length*240)+1):
				var time := minf(float(frame)/240,before.length)
				var original := torso(before,time,hips_rest,chest_rest)
				var result := torso(after,time,hips_rest,chest_rest)
				var position_error := original.origin.distance_to(result.origin)
				var angle_error := original.basis.get_rotation_quaternion().angle_to(result.basis.get_rotation_quaternion())
				worst_position=maxf(worst_position,position_error)
				worst_rotation=maxf(worst_rotation,angle_error)
				clip_segment_error=maxf(clip_segment_error,absf(result.origin.distance_to(hips_rest)-original.origin.distance_to(hips_rest)))
				clip_rotation_error=maxf(clip_rotation_error,angle_error)
				movement=maxf(movement,first.angle_to(after.rotation_track_interpolate(h,time)))
			check(clip_segment_error < .00001 and clip_rotation_error < .0015,"spine length and upper torso orientation preserved "+attribute+"/"+String(name))
			check(movement>.015,"lower torso participates in the same motion "+attribute+"/"+String(name))
			var saved := after.duplicate(true) as Animation
			CreatureAnim.DragnarTorso.prepare(after,actor._player,true)
			check(saved.track_get_key_count(h)==after.track_get_key_count(h),"idempotent preprocessing")
		summaries.append({"attribute":attribute,"upper_origin_arc_local":worst_position,"upper_orientation_error_rad":worst_rotation})
		Cleanup.release(actor,self)
		CreatureModels.clear()
		await process_frame
	print("DRAGNAR TORSO ",JSON.stringify({"checks":checks,"failures":failures,"summaries":summaries}))
	quit(1 if failures else 0)
