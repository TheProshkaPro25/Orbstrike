extends SceneTree
const ModelTestCleanup := preload("res://scenes/model_lifetime.gd")
## A turning stance must use the same coordinate frame for anchors, poles and feet.
const ReviewState := preload("res://tools/model_review_state.gd")
const EPSILON := 0.00001
var checks := 0
var failures := 0
var largest_error := 0.0
var bone_names: Array[StringName] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func sample(id: StringName, yaw: float, parent_yaw: float, stride: float = -1.0, attack_frames: int = 0, stride_by_bone: Dictionary = {}) -> Array[Transform3D]:
	var parent := Node3D.new()
	root.add_child(parent)
	parent.rotation.y = parent_yaw
	var actor := CreatureAnim.new()
	parent.add_child(actor)
	actor.set_process(false)
	var model := CreatureModels.build(CardDB.creature(id))
	if stride >= 0:
		# Override every existing marker in this isolated fixture, including
		# an installed 035 mesh, to compare identical assets at both strides.
		var nodes: Array[Node] = [model]
		while not nodes.is_empty():
			var node: Node = nodes.pop_back()
			nodes.append_array(node.get_children())
			var extras: Dictionary = node.get_meta("extras", {}).duplicate()
			extras.erase("sfery_stride_by_bone")
			if node == model or extras.has("sfery_middle_stride"):
				extras["sfery_middle_stride"] = stride
			if node == model and not stride_by_bone.is_empty():
				extras["sfery_stride_by_bone"] = stride_by_bone.duplicate()
			node.set_meta("extras", extras)
	if id == &"creature_rogozhuk_fire":
		# Keep non-rigid opt-in coverage on an actual unmodified normal rig,
		# independently of the accepted rigid Light asset.
		var extras: Dictionary = model.get_meta("extras", {}).duplicate()
		extras["sfery_turn_stance"] = true
		model.set_meta("extras", extras)
	actor.set_model(model, CardDB.creature(id))
	actor.idle_on = true
	actor._phase = 0
	ReviewState.reset_actor(actor)
	check(not actor._support.limbs.is_empty(), "%s has stance limbs" % id)
	for limb in actor._support.limbs:
		check(limb.get("turn_stance", false), "%s enables turning stance" % id)
		check(bool(limb.get("rigid", false)) == (id == &"creature_rogozhuk_stone"),
			"%s exercises the intended rigid/non-rigid solver" % id)
		if limb.front or limb.rear or id == &"creature_rogozhuk_fire":
			check(float(limb.get("stride_scale", 1.0)) == 1.0, "%s leaves other stance strides unchanged" % id)
	actor.fx_yaw = yaw
	actor._apply(0)
	if attack_frames > 0:
		actor.lunge(actor.get_height() * 0.22)
		for frame in range(attack_frames): actor._process(1.0 / 60.0)
	else:
		actor._support.apply(1.0 / 60.0)
	var skeleton: Skeleton3D = actor._support.skeleton
	var poses: Array[Transform3D] = []
	bone_names.clear()
	for bone in range(skeleton.get_bone_count()):
		poses.append(skeleton.get_bone_global_pose(bone))
		bone_names.append(skeleton.get_bone_name(bone))
	ModelTestCleanup.release(parent, self)
	return poses

func lowest_skinned_y(actor: CreatureAnim) -> float:
	var lowest := INF
	for mesh in actor._meshes:
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		var palette: Array[Transform3D] = []
		for slot in mesh.skin.get_bind_count():
			var bone := mesh.skin.get_bind_bone(slot)
			if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(slot))
			palette.append(mesh.global_transform * skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(slot))
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			@warning_ignore("integer_division")
			var stride := weights.size() / vertices.size()
			for vertex in vertices.size():
				var y := 0.0
				for influence in stride:
					var index := vertex * stride + influence
					if weights[index] > 0:
						y += (palette[joints[index]] * vertices[vertex]).y * weights[index]
				lowest = minf(lowest, y)
	return lowest

func check_beetle_ground_clearance(id: StringName) -> void:
	var definition := CardDB.creature(id)
	var actor := CreatureAnim.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.set_model(CreatureModels.build(definition), definition)
	actor._phase = 0
	ReviewState.reset_actor(actor)
	actor.idle_on = true
	for frame in 45: actor._process(1.0 / 60.0)
	var idle_floor := lowest_skinned_y(actor) / actor.get_height()
	check(absf(idle_floor) < .015, "%s idle surface reaches the floor, normalized y=%.4f" % [id, idle_floor])
	ReviewState.reset_actor(actor)
	for frame in 20: actor._process(1.0 / 60.0)
	actor.hit(Color.WHITE, actor.get_height() * .075)
	for frame in ceili(60 * actor._duration * .46): actor._process(1.0 / 60.0)
	var hit_floor := lowest_skinned_y(actor) / actor.get_height()
	check(absf(hit_floor) < .02, "%s hit preserves the claw silhouette, normalized y=%.4f" % [id, hit_floor])
	print("BEETLE FLOOR ", id, " idle=", idle_floor, " hit=", hit_floor)
	ModelTestCleanup.release(actor, self)

func run() -> void:
	CardDB.load_all()
	for id in [&"creature_rogozhuk_stone", &"creature_rogozhuk_fire"]:
		var reference := sample(id, 0, 0)
		for angles in [Vector2(-0.3, 0), Vector2(0, 0.7), Vector2(-0.3, 0.7)]:
			var turned := sample(id, angles.x, angles.y)
			check(reference.size() == turned.size(), "%s retains the same skeleton" % id)
			if reference.size() != turned.size(): continue
			var error := 0.0
			for bone in range(reference.size()):
				if not reference[bone].is_finite() or not turned[bone].is_finite():
					error = INF
					break
				error = maxf(error, reference[bone].origin.distance_to(turned[bone].origin))
				for axis in range(3):
					error = maxf(error, (reference[bone].basis[axis] - turned[bone].basis[axis]).length())
			largest_error = maxf(largest_error, error)
			check(error <= EPSILON, "%s actor/parent yaw %s changes local stance by %.9f" % [id, angles, error])
		CreatureModels.clear()
		await process_frame
	# The asset marker must change the actual middle-leg attack pose without
	# moving the front/rear pairs, body, or any unrelated bone.
	var full_stride := sample(&"creature_rogozhuk_stone", 0, 0, 1.0, 23)
	var short_stride := sample(&"creature_rogozhuk_stone", 0, 0, 0.85, 23)
	var changed_middle := 0
	for bone in range(full_stride.size()):
		var error := full_stride[bone].origin.distance_to(short_stride[bone].origin)
		for axis in range(3):
			error = maxf(error, (full_stride[bone].basis[axis] - short_stride[bone].basis[axis]).length())
		var name := String(bone_names[bone])
		if name.begins_with("thigh.") or name.begins_with("shin.") or name.begins_with("foot."):
			if error > 0.0001: changed_middle += 1
		else:
			check(error <= EPSILON, "middle stride must not alter %s (%.9f)" % [name, error])
	check(changed_middle == 6, "shorter stride changes all six middle-chain bones")
	# Per-bone metadata must override the shared middle stride only for the
	# nominated chain, including its solved lower joints in the actual attack.
	var asymmetric_stride := sample(&"creature_rogozhuk_stone", 0, 0, 0.85, 23, {"thigh.R": 0.6})
	var changed_right := 0
	for bone in range(short_stride.size()):
		var error := short_stride[bone].origin.distance_to(asymmetric_stride[bone].origin)
		for axis in range(3):
			error = maxf(error, (short_stride[bone].basis[axis] - asymmetric_stride[bone].basis[axis]).length())
		var name := String(bone_names[bone])
		if name in ["thigh.R", "shin.R", "foot.R"]:
			if error > 0.0001: changed_right += 1
		else:
			check(error <= EPSILON, "right stride override must not alter %s (%.9f)" % [name, error])
	check(changed_right == 3, "right override changes exactly its three middle-chain bones")
	for id in [&"creature_rogozhuk_stone", &"creature_rogozhuk_tide"]:
		check_beetle_ground_clearance(id)
		await process_frame
	CreatureModels.clear()
	print("Stance frames: checks=%d failures=%d max_pose_error=%.9f" % [checks, failures, largest_error])
	quit(1 if failures else 0)
