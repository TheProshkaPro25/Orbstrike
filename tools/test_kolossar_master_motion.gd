extends SceneTree
## Read-only actual .res samples + real action timing, no renderer/Boot replay.
const Motion := preload("res://scenes/kolossar_motion.gd")
const MASTER := "b771a0b622888746bb1b35b52d4b12df973445ee9fdf59e01d82860aac6877c2"
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + text)
func vector(v: Vector3) -> Array: return [v.x, v.y, v.z]
func quaternion(q: Quaternion) -> Array: return [q.x, q.y, q.z, q.w]
func run() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	var result := {"master_motion_source_sha256": MASTER, "elements": {}, "legacy_controls": []}
	for element in Motion.ELEMENTS:
		var d := CardDB.creature(StringName("creature_kolossar_" + element))
		var a := CreatureAnim.new()
		root.add_child(a)
		a.set_process(false)
		var model := CreatureModels.build(d)
		a.set_model(model, d)
		a.idle_on = true
		a._phase = 0
		a.reset()
		var library: AnimationLibrary = Motion.libraries[d.id]
		check(a._authored_fullset and a._tempo == 1.0, "common authored timing " + element)
		check(String(library.get_meta("master_motion_source_sha256", "")) == MASTER, "common master identity " + element)
		var row := {"master_motion_source_sha256": library.get_meta("master_motion_source_sha256"), "library_sha256": FileAccess.get_sha256(library.resource_path), "anatomical_scale": library.get_meta("anatomical_scale"), "yaw_alignment_degrees": library.get_meta("yaw_alignment_degrees"), "source_floor_min_y": library.get_meta("source_floor_min_y"), "root_static_ground_adapter_source": library.get_meta("root_static_ground_adapter_source"), "source_glb_sha256": library.get_meta("source_glb_sha256"), "rest_local": {}, "parents": {}, "clips": {}, "runtime_timing": {}}
		var sk := Motion._skeleton(model)
		for bone in sk.get_bone_count():
			var name := sk.get_bone_name(bone)
			var rest := sk.get_bone_rest(bone)
			row.rest_local[name] = {"position": vector(rest.origin), "rotation": quaternion(rest.basis.get_rotation_quaternion()), "scale": vector(rest.basis.get_scale())}
			var parent := sk.get_bone_parent(bone)
			row.parents[name] = String(sk.get_bone_name(parent)) if parent >= 0 else ""
		var source_grid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://build/experiments/kolossar-fullset-2026-11-08/retarget-six/" + element + "-tracks.json"))
		for clip in Motion.CLIPS:
			var animation := library.get_animation(clip)
			var times: Array = source_grid.clips[clip].times
			var data := {"times": times, "length": animation.length, "bones": {}}
			for name in Motion.BONES: data.bones[name] = {"rotation": [], "position": [], "scale": []}
			for track in animation.get_track_count():
				var name := String(animation.track_get_path(track).get_subname(0))
				for time in times:
					match animation.track_get_type(track):
						Animation.TYPE_ROTATION_3D: data.bones[name].rotation.append(quaternion(animation.rotation_track_interpolate(track, time)))
						Animation.TYPE_POSITION_3D: data.bones[name].position.append(vector(animation.position_track_interpolate(track, time)))
						Animation.TYPE_SCALE_3D: data.bones[name].scale.append(vector(animation.scale_track_interpolate(track, time)))
			row.clips[clip] = data
		a.reset()
		row.runtime_timing.idle = {"clip_length": library.get_animation(&"idle").length, "playback_speed": a._player.get_playing_speed()}
		for item in [["stance", "appear", 1.1], ["roar", "roar", 1.05], ["hit", "hit", .8], ["ability", "ability_pulse", .85], ["brace", "brace", .8]]:
			a.reset()
			if item[0] == "hit": a.hit(Color.WHITE, .5)
			else: a.call(item[1])
			check(absf(a._duration - item[2]) < .000001, "common action duration " + element + " " + item[0])
			row.runtime_timing[item[0]] = {"duration": a._duration}
		var contacts: Array = []
		a.strike_contact.connect(func() -> void: contacts.append(a._elapsed))
		a.reset()
		a.lunge(1.0)
		row.runtime_timing.attack = {"contact": a._contact_time, "duration": a._duration}
		for frame in 160: a._process(1.0 / 120.0)
		check(contacts.size() == 1 and absf(a._contact_time - .4) < .000001 and absf(a._duration - 1.2) < .000001, "common real contact " + element)
		row.runtime_timing.attack.signal_times = contacts.duplicate()
		a.reset()
		a.counter(1.0)
		check(absf(a._contact_time - .4) < .000001, "common counter contact")
		a.reset()
		a.lunge(1.0, .46)
		check(absf(a._contact_time - .46) < .000001 and absf(a._attack_progress(.46) - 1.0 / 3.0) < .000001 and absf(a._attack_progress(.50) - 1.0 / 3.0) < .000001, "clash override and hold preserved")
		row.runtime_timing.clash = {"contact": a._contact_time, "duration": a._duration}
		result.elements[element] = row
		ModelLifetime.release(a, self)
		await process_frame
	for id in [&"creature_dragnar_fire", &"creature_ratnik_stone"]:
		var d := CardDB.creature(id)
		var a := CreatureAnim.new()
		root.add_child(a)
		a.set_process(false)
		a.set_model(CreatureModels.build(d), d)
		check(not a._authored_fullset and a._tempo == CreatureAnim.TEMPO[d.attribute], "legacy elemental tempo unchanged " + String(id))
		result.legacy_controls.append({"id": id, "tempo": a._tempo, "authored": a._authored_fullset})
		ModelLifetime.release(a, self)
		await process_frame
	CreatureModels.clear()
	await process_frame
	result.checks = checks
	result.failures = failures
	var file := FileAccess.open("res://build/checks/kolossar-fullset/common-master-runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print("KOLOSSAR_MASTER_RUNTIME checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
