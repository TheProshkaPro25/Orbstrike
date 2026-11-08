extends RefCounted
## Late, small sole penetration correction for authored grounded motion.
## Reuses the unchanged support sampler/IK without legacy step/crouch/sway.
static var surface_signatures: Dictionary = {}

static func configure(support, actor: Node3D, model: Node3D) -> void:
	var signature := String(model.get_meta("support_surface_signature", ""))
	if signature.is_empty():
		support.configure(actor, model)
		return
	var source: PackedScene = model.get_meta("preparation_source")
	var key: Array = ["soles", source.get_instance_id(), actor.get_height()]
	var identity := str(key)
	if not surface_signatures.has(identity) or surface_signatures[identity].signature != signature:
		CreatureModels.preparation_cache.erase(key)
		if surface_signatures.size() >= CreatureModels.preparation_cache_limit(): surface_signatures.erase(surface_signatures.keys()[0])
		surface_signatures[identity] = {"source": source, "signature": signature}
	# The disk cache describes the unchanged GLB's old weights. This synchronous
	# scoped preparation uses fresh overlay samples, then shares them in memory.
	var enabled := PreparationStore.enabled
	PreparationStore.enabled = false
	support.configure(actor, model)
	PreparationStore.enabled = enabled

static func clear() -> void: surface_signatures.clear()

static func apply(support, _delta: float) -> void:
	var skeleton: Skeleton3D = support.skeleton
	if skeleton == null: return
	var actor = support.actor
	support.last_ground_errors.clear()
	var floor_y: float = (support._parent_transform() * actor._base).y
	var epsilon: float = actor.get_height() * .0001
	var limit: float = actor.get_height() * .015
	for limb in support.limbs:
		if not limb.has("sole") or limb.sole.is_empty(): continue
		var error: float = support._sole_height(limb) - floor_y
		if error >= -epsilon or error < -limit:
			# A large bad pose or non-foot appendage must be fixed by the author.
			support.last_ground_errors.append(error)
			continue
		var ankle := skeleton.get_bone_global_pose(limb.c)
		var knee := skeleton.get_bone_global_pose(limb.b)
		var target: Vector3 = skeleton.global_transform * ankle.origin
		var pole: Vector3 = skeleton.global_transform * knee.origin
		var foot_basis := ankle.basis.orthonormalized()
		for iteration in 3:
			target.y -= error
			support._solve(limb, target, pole)
			support._set_global_rotation(limb.c, foot_basis)
			error = support._sole_height(limb) - floor_y
			if error >= -epsilon: break
		support.last_ground_errors.append(error)
