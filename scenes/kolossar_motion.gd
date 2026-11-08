extends RefCounted
## Accepted manual five-clip set, retargeted offline to each unchanged source rig.
## Only paths and playback flags change here; authored key values stay untouched.
const ELEMENTS := ["fire", "gale", "stone", "light", "shadow", "tide"]
const CLIPS := [&"idle", &"stance", &"roar", &"attack", &"hit"]
const BONES := ["root", "hips", "chest", "arm.L", "forearm.L", "arm.R", "forearm.R", "neck", "head", "tail1", "tail2", "thigh.L", "shin.L", "thigh.R", "shin.R", "clavicle.L", "clavicle.R", "hand.L", "hand.R", "foot.L", "foot.R"]
const DIRECTORY := "res://assets/animations/kolossar/"
const MASTER_SHA := "b771a0b622888746bb1b35b52d4b12df973445ee9fdf59e01d82860aac6877c2"
static var libraries: Dictionary = {}
static var mapped_libraries: Dictionary = {}
static var load_count := 0

static func resource_paths() -> Array[String]:
	var result: Array[String] = []
	for element in ELEMENTS: result.append(DIRECTORY + element + ".res")
	return result

static func supports(d: CreatureDef) -> bool:
	return d != null and d.species == &"kolossar" and String(d.id).trim_prefix("creature_kolossar_") in ELEMENTS

static func preload_for(d: CreatureDef) -> AnimationLibrary:
	if not supports(d): return null
	if libraries.has(d.id): return libraries[d.id]
	var path := DIRECTORY + String(d.id).trim_prefix("creature_kolossar_") + ".res"
	var library := load(path) as AnimationLibrary
	if library == null:
		push_error("Kolossar animation library unavailable: " + path)
		return null
	var error := validation_error(library, d.id)
	if not error.is_empty():
		push_error("Kolossar animation library invalid: " + path + ": " + error)
		return null
	libraries[d.id] = library
	load_count += 1
	return library

static func preload_required() -> bool:
	var complete := true
	for element in ELEMENTS:
		var d := CardDB.creature(StringName("creature_kolossar_" + element))
		if d == null or preload_for(d) == null: complete = false
	return complete

## Also used by the narrow negative fixtures: validation never edits key values.
static func validation_error(library: AnimationLibrary, id: StringName) -> String:
	if library == null: return "missing library"
	if int(library.get_meta("authored_fullset_version", 0)) != 1 or String(library.get_meta("creature_id", "")) != String(id): return "wrong target/version"
	if String(library.get_meta("master_motion_source_sha256", "")) != MASTER_SHA: return "wrong motion master"
	if library.get_animation_list().size() != CLIPS.size(): return "expected exactly five clips"
	if not is_equal_approx(float(library.get_meta("contact_phase", -1.0)), 1.0 / 3.0): return "wrong contact phase"
	for metric in ["visual_top_source", "visual_extent_source"]:
		var value := float(library.get_meta(metric, -1.0))
		if not is_finite(value) or value <= 0.0: return "missing visual envelope " + metric
	for clip in CLIPS:
		if not library.has_animation(clip): return "missing " + String(clip)
		var animation := library.get_animation(clip)
		if animation == null or not is_finite(animation.length) or animation.length <= 0.0 or animation.get_track_count() == 0: return "empty " + String(clip)
		if animation.get_track_count() != BONES.size() * 3: return "incomplete bone TRS coverage " + String(clip)
		var coverage: Dictionary = {}
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			if path.get_subname_count() != 1 or not BONES.has(String(path.get_subname(0))): return "invalid bone path " + str(path)
			if animation.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] or animation.track_get_key_count(track) == 0: return "empty/non-transform track " + str(path)
			var channel := str([path.get_subname(0), animation.track_get_type(track)])
			if coverage.has(channel): return "duplicate bone channel " + str(path)
			coverage[channel] = true
			if absf(animation.track_get_key_time(track, 0)) > .00001 or absf(animation.track_get_key_time(track, animation.track_get_key_count(track) - 1) - animation.length) > .00001: return "incomplete clip time range " + str(path)
			for index in animation.track_get_key_count(track):
				var time := animation.track_get_key_time(track, index)
				if not is_finite(time) or time < -0.00001 or time > animation.length + 0.00001: return "key outside clip " + str(path)
				var value: Variant = animation.track_get_key_value(track, index)
				if not ((value is Quaternion or value is Vector3) and value.is_finite()): return "nonfinite transform " + str(path)
	return ""

static func install(model: Node3D, player: AnimationPlayer, d: CreatureDef) -> bool:
	if not supports(d) or player == null: return false
	var library := preload_for(d)
	if library == null: return false
	var skeleton := _skeleton(model)
	if skeleton == null:
		push_error("Kolossar animation target has no skeleton: " + String(d.id))
		return false
	var skeleton_path := player.get_node(player.root_node).get_path_to(skeleton)
	var key := str([library.get_instance_id(), skeleton_path])
	if not mapped_libraries.has(key):
		var mapped := library.duplicate(true) as AnimationLibrary
		for clip in CLIPS:
			var animation := mapped.get_animation(clip)
			for track in animation.get_track_count():
				var old := animation.track_get_path(track)
				if old.get_subname_count() != 1 or skeleton.find_bone(old.get_subname(0)) < 0:
					push_error("Invalid Kolossar bone track: " + str(old))
					return false
				animation.track_set_path(track, NodePath(str(skeleton_path) + ":" + String(old.get_subname(0))))
		mapped_libraries[key] = mapped
	for name in player.get_animation_library_list(): player.remove_animation_library(name)
	player.add_animation_library(&"", mapped_libraries[key])
	model.set_meta("authored_kolossar_fullset", 1)
	model.set_meta("authored_visual_top_source", maxf(float(library.get_meta("visual_top_source")), float(model.get_meta("skin_visual_top_source", 0.0))))
	model.set_meta("authored_visual_extent_source", maxf(float(library.get_meta("visual_extent_source")), float(model.get_meta("skin_visual_extent_source", 0.0))))
	return true

static func clear() -> void:
	libraries.clear()
	mapped_libraries.clear()
	load_count = 0

static func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found := _skeleton(child)
		if found != null: return found
	return null
