extends "res://tools/test_model_wind_import.gd"
## One-model imported/ordinary CPU contract. Does not accept GPU cloth or art.
const DIRECTORY := "res://build/model_candidates/2026-11-06-a04-reopen/"
const SOURCE := DIRECTORY + "source/ratnik_light.glb"
const CANDIDATE := DIRECTORY + "accepted.glb"
const PRODUCTION := "res://assets/creatures_hd/ratnik_light.glb"
const SOURCE_SHA := "b209b4bad3ec5e2a4b02104993b7de1adbbdd1b59dba565c7f1e14270fe13df8"
const ACTIONS := ["idle", "attack", "hit", "appear"]
const FRAMES := [0, 12, 24, 48, 90]

func inspect_scene(packed: PackedScene) -> Dictionary:
	var result := super.inspect_scene(packed)
	var instance := packed.instantiate()
	var surfaces: Array = []
	for mesh in nodes(instance, "MeshInstance3D"):
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var digest := HashingContext.new()
			digest.start(HashingContext.HASH_SHA256)
			for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_INDEX, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
				digest.update(var_to_bytes(arrays[attribute]))
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var position_keys: Array[String] = []
			for vertex in vertices: position_keys.append(var_to_bytes(vertex).hex_encode())
			var faces: Array[String] = []
			for face in indices.size() / 3:
				var triangle: Array[String] = [position_keys[indices[face*3]], position_keys[indices[face*3+1]], position_keys[indices[face*3+2]]]
				# Keep winding, but ignore cyclic first corner and importer reordering.
				var first := 0
				if triangle[1] < triangle[first]: first = 1
				if triangle[2] < triangle[first]: first = 2
				faces.append(triangle[first] + triangle[(first+1)%3] + triangle[(first+2)%3])
			faces.sort()
			surfaces.append({"mesh": String(mesh.name), "surface": surface,
				"vertices": mesh.mesh.surface_get_array_len(surface),
				"triangles": mesh.mesh.surface_get_array_index_len(surface) / 3,
				"position_normal_index_bones_weights_sha256": digest.finish().hex_encode(),
				"order_independent_oriented_geometry_sha256": "\n".join(faces).sha256_text()})
	result["surfaces"] = surfaces
	instance.free()
	return result

func same_geometry(before: Dictionary, after: Dictionary) -> bool:
	if before.triangles != after.triangles or before.vertices != after.vertices or before.bounds != after.bounds: return false
	if before.surfaces.size() != after.surfaces.size(): return false
	for index in before.surfaces.size():
		var a: Dictionary = before.surfaces[index]
		var b: Dictionary = after.surfaces[index]
		for key in ["mesh", "surface", "vertices", "triangles", "order_independent_oriented_geometry_sha256"]:
			if a[key] != b[key]: return false
	return true

func protected_points(ball: CreatureBall) -> PackedVector3Array:
	var points := PackedVector3Array()
	for mesh in nodes(ball._anim, "MeshInstance3D"):
		if mesh.skin == null: continue
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var eligible := PackedVector3Array()
			for vertex in vertices:
				# Deliberately exclude crown/collar/horn edits, all above this plane.
				if vertex.y < 0.28: eligible.append(vertex)
			if eligible.is_empty(): continue
			for sample in 32: points.append(eligible[sample * (eligible.size() - 1) / 31])
	check(points.size() >= 64, "protected body and cape world samples")
	return points

func upper_points(ball: CreatureBall) -> PackedVector3Array:
	var points := PackedVector3Array()
	for mesh in nodes(ball._anim, "MeshInstance3D"):
		if mesh.skin == null: continue
		for surface in mesh.mesh.get_surface_count():
			var eligible := PackedVector3Array()
			for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if vertex.y >= 0.28: eligible.append(vertex)
			if eligible.is_empty(): continue
			for sample in 32: points.append(eligible[sample * (eligible.size() - 1) / 31])
	check(points.size() >= 64, "upper crown/horn and ring samples")
	return points

func check_finite_points(samples: Array, label: String) -> void:
	var valid := true
	for point in world_points(samples): valid = valid and point.is_finite()
	check(valid, label + " finite posed upper skin samples")

func head_relative_points(samples: Array) -> PackedVector3Array:
	var worlds := world_points(samples)
	var result := PackedVector3Array()
	for index in samples.size():
		var mesh: MeshInstance3D = samples[index].mesh
		var skeleton: Skeleton3D = samples[index].skeleton
		var head := skeleton.find_bone("head")
		check(head >= 0, "witness imported head bone")
		var frame := mesh.global_transform * skeleton.get_bone_global_pose(head)
		result.append(frame.affine_inverse() * worlds[index])
	return result

func skin_signature(ball: CreatureBall) -> Array:
	var result: Array = []
	for mesh in nodes(ball._anim, "MeshInstance3D"):
		if mesh.skin == null: continue
		var skeleton: Skeleton3D = mesh.get_node(mesh.skeleton)
		var binds: Array = []
		for slot in mesh.skin.get_bind_count():
			var bone: int = mesh.skin.get_bind_bone(slot)
			if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(slot))
			binds.append([bone, mesh.skin.get_bind_pose(slot)])
		result.append(binds)
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var stride := weights.size() / vertices.size()
			check(stride == 4 or stride == 8, "valid imported influence stride")
			var valid := true
			var max_sum_error := 0.0
			for vertex in vertices.size():
				var total := 0.0
				for influence in stride:
					var index: int = vertex * stride + influence
					var weight := weights[index]
					valid = valid and is_finite(weight) and weight >= 0.0
					if weight > 0.0:
						var slot := bones[index]
						valid = valid and slot >= 0 and slot < mesh.skin.get_bind_count()
						if slot >= 0 and slot < mesh.skin.get_bind_count():
							var bone: int = mesh.skin.get_bind_bone(slot)
							if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(slot))
							valid = valid and bone >= 0 and bone < skeleton.get_bone_count()
					total += weight
				max_sum_error = maxf(max_sum_error, absf(total - 1.0))
			print("IMPORTED SKIN %s/%d stride=%d valid_weights_binds=%s max_sum_error=%.9f" % [mesh.name, surface, stride, valid, max_sum_error])
			# ArrayMesh stores each weight at 16-bit precision. Summed truncation
			# is bounded by one quantization unit per influence, not float epsilon.
			valid = valid and max_sum_error <= float(stride) / 65535.0 + 0.000001
			check(valid, "finite normalized imported skin: " + String(mesh.name) + "/" + str(surface))
	return result

func same_binds(before: Array, after: Array) -> bool:
	if before.size() != after.size(): return false
	for mesh in before.size():
		if before[mesh].size() != after[mesh].size(): return false
		for slot in before[mesh].size():
			if before[mesh][slot][0] != after[mesh][slot][0]: return false
			var a: Transform3D = before[mesh][slot][1]
			var b: Transform3D = after[mesh][slot][1]
			if not a.is_equal_approx(b): return false
	return true

func pose(ball: CreatureBall, action: String, frame: int) -> PackedFloat64Array:
	if action != "appear": return super.pose(ball, action, frame)
	var anim := ball._anim
	check(anim.is_visible_in_tree(), "manual appear actor visible")
	ReviewState.reset_actor(anim)
	anim.idle_on = true
	anim.appear()
	for index in frame: anim._process(1.0 / 60.0)
	check(frame == 0 or anim._clock > 0.0, "manual appear clock advanced")
	var result := PackedFloat64Array()
	for skeleton in nodes(anim, "Skeleton3D"):
		for bone in skeleton.get_bone_count():
			var transform: Transform3D = skeleton.get_bone_global_pose(bone)
			for column in [transform.basis.x, transform.basis.y, transform.basis.z, transform.origin]:
				for coordinate in [column.x, column.y, column.z]:
					check(is_finite(coordinate), "finite appear")
					result.append(coordinate)
	return result

func compare_signature(before: Dictionary, after: Dictionary, label: String) -> void:
	check(absf(before.scale - after.scale) < 0.00001, label + " body scale")
	check(absf(before.height - after.height) < 0.00001, label + " motion height")
	check(absf(before.extent - after.extent) < 0.00001, label + " motion extent")
	check(Vector3(before.offset[0], before.offset[1], before.offset[2]).distance_to(Vector3(after.offset[0], after.offset[1], after.offset[2])) < 0.00001, label + " body offset")

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "runtime-freeze.json"))
	var source_sha := FileAccess.get_sha256(SOURCE)
	var candidate_sha := FileAccess.get_sha256(CANDIDATE)
	check(source_sha == SOURCE_SHA, "immutable b209 source SHA")
	check(candidate_sha == manifest.get("candidate_sha256", ""), "explicit frozen candidate SHA")
	var installed := FileAccess.get_sha256(PRODUCTION) == candidate_sha
	check(installed or FileAccess.get_sha256(PRODUCTION) == SOURCE_SHA, "production is source or frozen candidate")
	var before := imported(SOURCE)
	var after := imported(CANDIDATE)
	var bm := inspect_scene(before)
	var am := inspect_scene(after)
	check(bm.triangles == 156366, "source imported triangle count")
	check(am.triangles == manifest.get("triangles", -1), "frozen imported triangle count")
	var trial: Node3D = after.instantiate()
	var active := CreatureModels._bounds(trial, Transform3D.IDENTITY)
	check(CreatureModels._normalization_frame("hd:unrelated", trial, active) == active, "normalization key guard")
	var changed := AABB(active.position + Vector3(0.01, 0, 0), active.size)
	check(CreatureModels._normalization_frame("hd:ratnik_light", trial, changed) == changed, "normalization bounds guard")
	var empty := Node3D.new()
	check(CreatureModels._normalization_frame("hd:ratnik_light", empty, active) == active, "normalization topology guard")
	empty.free()
	trial.free()
	var definition := CardDB.creature(&"creature_ratnik_light")
	var base_ball := actor(definition, before)
	var next_ball := actor(definition, after)
	var bs := signature(base_ball)
	var cs := signature(next_ball)
	compare_signature(bs, cs, "candidate")
	check(same_binds(skin_signature(base_ball), skin_signature(next_ball)), "source/candidate immutable skin bind palette")
	var references := protected_points(base_ball)
	var base_samples := bind_samples(base_ball, references)
	var next_samples := bind_samples(next_ball, references)
	var upper_references := upper_points(next_ball)
	var next_upper_samples := bind_samples(next_ball, upper_references)
	var witness: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/audits/2026-11-06-model-a04-reopen/witness.json"))
	check(witness.candidate_sha256 == candidate_sha, "witness frozen candidate SHA")
	var witness_references := PackedVector3Array()
	for point in witness.points: witness_references.append(Vector3(point.position[0], point.position[1], point.position[2]))
	check(witness_references.size() == 12, "twelve local forehead-contact witness vertices")
	var witness_samples := bind_samples(next_ball, witness_references)
	var witness_origin := PackedVector3Array()
	var witness_poses: Array[PackedVector3Array] = []
	var witness_max_drift := 0.0
	var witness_drift_by_pose: Array = []
	var max_palette := 0.0
	var max_world := 0.0
	var candidate_poses: Array[PackedFloat64Array] = []
	var candidate_points: Array[PackedVector3Array] = []
	var motion_variation := {}
	for action in ACTIONS:
		var action_origin := PackedFloat64Array()
		var action_variation := 0.0
		for frame in FRAMES:
			var bp := pose(base_ball, action, frame)
			var cp := pose(next_ball, action, frame)
			if action_origin.is_empty(): action_origin = cp
			action_variation = maxf(action_variation, palette_variation(action_origin, cp))
			check_finite_points(next_upper_samples, action + str(frame))
			var relative := head_relative_points(witness_samples)
			if witness_origin.is_empty(): witness_origin = relative
			var drift := point_delta(witness_origin, relative)
			witness_max_drift = maxf(witness_max_drift, drift)
			witness_drift_by_pose.append({"action": action, "frame": frame, "head_relative_delta": drift,
				"head_relative_points_float32_sha256": relative.to_byte_array().hex_encode().sha256_text()})
			witness_poses.append(relative)
			candidate_poses.append(cp)
			var wp := world_points(next_samples)
			candidate_points.append(wp)
			max_world = maxf(max_world, point_delta(world_points(base_samples), wp))
			check(bp.size() == cp.size(), "candidate same skeleton")
			for index in mini(bp.size(), cp.size()): max_palette = maxf(max_palette, absf(bp[index] - cp[index]))
		motion_variation[action] = action_variation
		check(action_variation > 0.0, "nonzero within-action palette variation: " + action)
	check(max_palette < 0.00001, "source/candidate CPU bone palettes unchanged")
	check(max_world < 0.00002, "protected skinned world points unchanged")
	var candidate_skin := skin_signature(next_ball)
	ModelLifetime.release(base_ball, self)
	ModelLifetime.release(next_ball, self)
	await process_frame
	CreatureModels.clear()
	var ordinary: Dictionary = {}
	if installed:
		# No injected PackedScene: this explicitly loads the editor-produced SCN.
		var normal := load(PRODUCTION) as PackedScene
		check(normal != null, "ordinary production resource load")
		var nm := inspect_scene(normal)
		check(same_geometry(nm, am), "ordinary SCN exact oriented geometry matches frozen GLTF despite importer reordering")
		var normal_ball := actor(definition)
		var ns := signature(normal_ball)
		compare_signature(bs, ns, "ordinary")
		check(same_binds(skin_signature(normal_ball), candidate_skin), "ordinary resolved skin bind palette")
		var normal_samples := bind_samples(normal_ball, references)
		var normal_upper_samples := bind_samples(normal_ball, upper_references)
		var ordinary_witness_samples := bind_samples(normal_ball, witness_references)
		var witness_ordinary_delta := 0.0
		var palette_delta := 0.0
		var world_delta := 0.0
		var pose_index := 0
		for action in ACTIONS:
			for frame in FRAMES:
				var np := pose(normal_ball, action, frame)
				check_finite_points(normal_upper_samples, "ordinary " + action + str(frame))
				witness_ordinary_delta = maxf(witness_ordinary_delta, point_delta(head_relative_points(ordinary_witness_samples), witness_poses[pose_index]))
				var cp := candidate_poses[pose_index]
				check(np.size() == cp.size(), "ordinary skeleton")
				world_delta = maxf(world_delta, point_delta(world_points(normal_samples), candidate_points[pose_index]))
				for index in mini(np.size(), cp.size()): palette_delta = maxf(palette_delta, absf(np[index] - cp[index]))
				pose_index += 1
		check(palette_delta < 0.0001, "ordinary CPU bone palettes")
		check(world_delta < 0.0001, "ordinary protected skinned world points")
		check(witness_ordinary_delta < 0.00001, "ordinary head-relative witnesses match direct GLTF")
		ordinary = {"metrics": nm, "build": ns, "palette_delta": palette_delta, "world_delta": world_delta,
			"head_relative_witness_delta": witness_ordinary_delta}
		ModelLifetime.release(normal_ball, self)
		await process_frame
	CreatureModels.clear()
	CreatureModels.animation_library_cache.clear()
	await process_frame
	var output := "res://docs/audits/2026-11-06-model-a04-reopen-runtime/"
	DirAccess.make_dir_recursive_absolute(output)
	var result := {"scope": "ratnik_light GLTF/import/CreatureBall CPU; no GPU cloth/art", "source_sha256": source_sha,
		"candidate_sha256": candidate_sha, "production_sha256": FileAccess.get_sha256(PRODUCTION),
		"installed": installed, "direct_before": bm, "direct_after": am, "before_build": bs, "after_build": cs,
		"max_palette_delta": max_palette, "protected_world_samples": references.size(), "upper_skin_samples": upper_references.size(), "max_world_delta": max_world,
		"within_action_palette_variation": motion_variation,
		"forehead_witness": {"vertices": witness_references.size(), "max_head_relative_drift_model_units": witness_max_drift,
			"max_head_relative_drift_scaled_world_units": witness_max_drift * cs.scale, "poses": witness_drift_by_pose,
			"scope": "Measured vertex motion in actual head frame; does not remove three existing cap/body contacts"},
		"actions": ACTIONS, "frames": FRAMES, "ordinary": ordinary, "assertions": assertions, "failures": failures,
		"display_server": DisplayServer.get_name(), "engine_max_fps": Engine.max_fps}
	var file := FileAccess.open(output + ("installed.json" if installed else "pre-promotion.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("RATNIK CROWN REOPEN: %d assertions, %d failures; installed=%s; CPU only" % [assertions, failures, installed])
	quit(1 if failures else 0)
