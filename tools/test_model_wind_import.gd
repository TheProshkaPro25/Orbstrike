extends SceneTree
## Narrow A01/A02 source/candidate import and real CreatureBall pose contract.
## Headless results are CPU/import evidence, never visual/GPU acceptance.
const ReviewState := preload("res://tools/model_review_state.gd")
const CASES := [
	["klykar_gale", "a01", 149996, 132146],
	["levian_gale", "a02", 144894, 142356],
]
var failures := 0
var assertions := 0
var report := {"scope": "Godot GLTF/import/CreatureBall CPU; no GPU or cloth", "cases": []}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func nodes(n: Node, type: String) -> Array:
	var result: Array = []
	if n.is_class(type): result.append(n)
	for child in n.get_children(): result.append_array(nodes(child, type))
	return result

func imported(path: String) -> PackedScene:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	check(document.append_from_file(path, state) == OK, "GLTF load " + path)
	var original := document.generate_scene(state)
	var packed := PackedScene.new()
	check(original != null and packed.pack(original) == OK, "GLTF pack " + path)
	original.free()
	return packed

func inspect_scene(packed: PackedScene) -> Dictionary:
	var instance := packed.instantiate()
	var triangles := 0
	var vertices := 0
	for mesh in nodes(instance, "MeshInstance3D"):
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			vertices += arrays[Mesh.ARRAY_VERTEX].size()
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
	var bounds := CreatureModels._bounds(instance, Transform3D.IDENTITY)
	instance.free()
	return {"triangles": triangles, "vertices": vertices, "bounds": [Array([bounds.position.x,bounds.position.y,bounds.position.z]), Array([bounds.size.x,bounds.size.y,bounds.size.z])]}

func actor(definition: CreatureDef, packed: PackedScene = null) -> CreatureBall:
	CreatureModels.clear()
	if packed != null:
		CreatureModels._scenes["hd:" + String(definition.id).trim_prefix("creature_")] = packed
	seed(70211)
	var ball := CreatureBall.new()
	root.add_child(ball)
	ball.freeze = true
	ball.setup(definition, 70211)
	# Manual _process still obeys CreatureAnim's visibility guard. This is an
	# isolated CPU pose fixture, not open_animated() or a gameplay reveal.
	ball._figure.show()
	ball._shell.hide()
	ball.set_process(false)
	ball.set_physics_process(false)
	ball._anim.set_process(false)
	ball._anim._phase = 0.0
	return ball

func signature(ball: CreatureBall) -> Dictionary:
	var a := ball._anim
	var model: Node3D = a.get_child(0)
	var wrapper: Node3D = model.get_child(0)
	return {"height": a.get_height(), "extent": a.get_extent(), "scale": wrapper.scale.x,
		"offset": [wrapper.position.x,wrapper.position.y,wrapper.position.z]}

func reference_points(ball: CreatureBall) -> PackedVector3Array:
	var points := PackedVector3Array()
	for mesh in nodes(ball._anim, "MeshInstance3D"):
		if mesh.skin == null: continue
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in 16: points.append(vertices[i*(vertices.size()-1)/15])
	return points

func bind_samples(ball: CreatureBall, points: PackedVector3Array) -> Array:
	var samples: Array = []
	for point in points:
		var found := false
		for mesh in nodes(ball._anim, "MeshInstance3D"):
			if mesh.skin == null: continue
			for surface in mesh.mesh.get_surface_count():
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var vertex := vertices.find(point)
				if vertex < 0: continue
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var stride := weights.size()/vertices.size()
				samples.append({"mesh": mesh, "skeleton": mesh.get_node(mesh.skeleton), "point": point,
					"weights": weights.slice(vertex*stride,(vertex+1)*stride),
					"bones": bones.slice(vertex*stride,(vertex+1)*stride)})
				found = true
				break
			if found: break
		check(found, "retained imported sample exists")
	return samples

func world_points(samples: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for sample in samples:
		var mesh: MeshInstance3D = sample.mesh
		var skeleton: Skeleton3D = sample.skeleton
		var point := Vector3.ZERO
		for influence in sample.weights.size():
			var slot: int = sample.bones[influence]
			var bone := mesh.skin.get_bind_bone(slot)
			if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(slot))
			var palette := skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(slot)
			point += (palette*sample.point)*sample.weights[influence]
		result.append(mesh.global_transform*point)
	return result

func point_delta(a: PackedVector3Array, b: PackedVector3Array) -> float:
	check(a.size()==b.size(), "same retained sample count")
	var delta := 0.0
	for i in mini(a.size(),b.size()): delta=maxf(delta,a[i].distance_to(b[i]))
	return delta

func pose(ball: CreatureBall, action: String, frame: int) -> PackedFloat64Array:
	var a := ball._anim
	check(a.is_visible_in_tree(), "manual pose actor visible: " + action)
	ReviewState.reset_actor(a)
	a.idle_on = true
	if action == "attack": a.lunge(a.get_height()*.22)
	if action == "hit": a.hit(Color.WHITE,a.get_height()*.075)
	for i in frame: a._process(1.0/60.0)
	check(frame == 0 or a._clock > 0.0, "manual pose clock advanced: " + action)
	var result := PackedFloat64Array()
	for skeleton in nodes(a, "Skeleton3D"):
		for bone in skeleton.get_bone_count():
			var transform: Transform3D = skeleton.get_bone_global_pose(bone)
			for column in [transform.basis.x,transform.basis.y,transform.basis.z,transform.origin]:
				for coordinate in [column.x,column.y,column.z]:
					check(is_finite(coordinate), "finite " + action)
					result.append(coordinate)
	return result

func palette_variation(before: PackedFloat64Array, after: PackedFloat64Array) -> float:
	var result := 0.0
	for index in mini(before.size(), after.size()):
		result = maxf(result, absf(before[index] - after[index]))
	return result

func run() -> void:
	var installed := true
	for item in CASES:
		var key: String = item[0]
		var directory: String = "res://build/model_candidates/2026-11-06-" + item[1]
		var source: String = directory.path_join("source/" + key + ".glb")
		var candidate: String = directory.path_join(key + ".glb")
		var production := "res://assets/creatures_hd/" + key + ".glb"
		var definition := CardDB.creature(StringName("creature_" + key))
		var before := imported(source)
		var after := imported(candidate)
		var bm := inspect_scene(before)
		var am := inspect_scene(after)
		check(bm.triangles == item[2], key + " baseline triangle count")
		check(am.triangles == item[3], key + " candidate triangle count")
		var base_ball := actor(definition, before)
		var next_ball := actor(definition, after)
		var bs := signature(base_ball)
		var cs := signature(next_ball)
		var references := reference_points(next_ball)
		var base_samples := bind_samples(base_ball,references)
		var next_samples := bind_samples(next_ball,references)
		# The opt-in frame must reject unrelated keys, changed bounds and changed topology.
		var trial: Node3D = after.instantiate()
		var active := CreatureModels._bounds(trial,Transform3D.IDENTITY)
		check(CreatureModels._normalization_frame("hd:other",trial,active)==active,"frame key guard")
		var changed := AABB(active.position+Vector3(.01,0,0),active.size)
		check(CreatureModels._normalization_frame("hd:"+key,trial,changed)==changed,"frame bounds guard")
		var empty := Node3D.new()
		check(CreatureModels._normalization_frame("hd:"+key,empty,active)==active,"frame topology guard")
		empty.free()
		trial.free()
		check(absf(bs.scale - cs.scale) < 0.00001, key + " unchanged body normalization")
		check(Vector3(bs.offset[0],bs.offset[1],bs.offset[2]).distance_to(Vector3(cs.offset[0],cs.offset[1],cs.offset[2])) < .00001, key + " unchanged body center")
		var max_delta := 0.0
		var max_world_delta := 0.0
		var candidate_poses: Array[PackedFloat64Array] = []
		var candidate_points: Array[PackedVector3Array] = []
		var motion_variation := {}
		for action in ["idle", "attack", "hit"]:
			var action_origin := PackedFloat64Array()
			var action_variation := 0.0
			for frame in [0, 12, 24, 48, 90]:
				var bp := pose(base_ball, action, frame)
				var cp := pose(next_ball, action, frame)
				if action_origin.is_empty(): action_origin = cp
				action_variation = maxf(action_variation, palette_variation(action_origin, cp))
				candidate_poses.append(cp)
				var wp := world_points(next_samples)
				candidate_points.append(wp)
				max_world_delta=maxf(max_world_delta,point_delta(world_points(base_samples),wp))
				check(bp.size() == cp.size(), key + " same skeleton")
				for i in mini(bp.size(),cp.size()): max_delta = maxf(max_delta,absf(bp[i]-cp[i]))
			motion_variation[action] = action_variation
			check(action_variation > 0.0, key + " nonzero within-action palette variation: " + action)
		check(max_delta < 0.00001, key + " CPU runtime palettes unchanged")
		check(max_world_delta < 0.00002, key + " retained skinned world surface unchanged")
		ModelLifetime.release(base_ball,self)
		ModelLifetime.release(next_ball,self)
		await process_frame
		CreatureModels.clear()
		var normal := load(production) as PackedScene
		check(normal != null, key + " ordinary imported path load")
		var normal_metrics := inspect_scene(normal)
		var promoted := FileAccess.get_sha256(production) == FileAccess.get_sha256(candidate)
		installed = installed and promoted
		check(normal_metrics.triangles == (item[3] if promoted else item[2]), key + " imported cache matches source SHA")
		var normal_ball := actor(definition)
		var ns := signature(normal_ball)
		var normal_samples := bind_samples(normal_ball,references)
		check(absf(bs.scale-ns.scale)<.00001, key+" ordinary imported body scale")
		check(Vector3(bs.offset[0],bs.offset[1],bs.offset[2]).distance_to(Vector3(ns.offset[0],ns.offset[1],ns.offset[2])) < .00001, key + " ordinary imported body center")
		var ordinary_delta := 0.0
		var ordinary_world_delta := 0.0
		var pose_index := 0
		for action in ["idle", "attack", "hit"]:
			for frame in [0,12,24,48,90]:
				var np := pose(normal_ball, action, frame)
				var cp := candidate_poses[pose_index]
				ordinary_world_delta=maxf(ordinary_world_delta,point_delta(world_points(normal_samples),candidate_points[pose_index]))
				check(np.size()==cp.size(), key+" ordinary imported skeleton")
				for i in mini(np.size(),cp.size()): ordinary_delta=maxf(ordinary_delta,absf(np[i]-cp[i]))
				pose_index += 1
		check(ordinary_delta<.0001, key+" ordinary import CPU palettes")
		check(ordinary_world_delta<.0001,key+" ordinary path retained world surface")
		ModelLifetime.release(normal_ball,self)
		await process_frame
		report.cases.append({"id": key, "production_sha256": FileAccess.get_sha256(production), "installed": promoted,
			"direct_before": bm, "direct_after": am, "ordinary_import": normal_metrics,
			"before_build": bs, "after_build": cs, "ordinary_build": ns, "max_pose_palette_delta": max_delta, "ordinary_pose_delta": ordinary_delta,
			"retained_world_samples": references.size(), "max_world_delta": max_world_delta, "ordinary_world_delta": ordinary_world_delta,
			"within_action_palette_variation": motion_variation,
			"sampled_actions": ["idle","attack","hit"], "frames": [0,12,24,48,90]})
		CreatureModels.clear()
		CreatureModels.animation_library_cache.clear()
		await process_frame
	var output := "res://docs/audits/2026-11-06-model-wind-runtime/"
	DirAccess.make_dir_recursive_absolute(output)
	report["assertions"] = assertions
	report["failures"] = failures
	report["installed_both"] = installed
	report["display_server"] = DisplayServer.get_name()
	var file := FileAccess.open(output.path_join("installed.json" if installed else "pre-promotion.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	file.close()
	print("MODEL WIND IMPORT: %d assertions, %d failures; CPU only" % [assertions,failures])
	await process_frame
	quit(1 if failures else 0)
