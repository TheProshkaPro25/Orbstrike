extends SceneTree
## Кэш содержит прежние канонические samples, перепривязанные к новому экземпляру.
const Cleanup := preload("res://scenes/model_lifetime.gd")
var failures := 0
var checks := 0
var verify_disk := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func snapshot(d: CreatureDef) -> Dictionary:
	var actor := CreatureAnim.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.set_model(CreatureModels.build(d),d)
	actor._phase = 0
	actor.idle_on = true
	actor._clock = 0
	actor.reset()
	var result := {"limbs":[],"poses":[],"ms":actor.preparation_ms.support}
	for limb in actor._support.limbs:
		var data := {"anchor":limb.anchor,"samples":[]}
		for sample in limb.get("sole",[]):
			check(is_instance_valid(sample.mesh) and actor.is_ancestor_of(sample.mesh),"samples bind to live current model")
			data.samples.append([sample.point,sample.rest,sample.bones,sample.weights,sample.poses])
		result.limbs.append(data)
	for frame in 30: actor._process(1.0/60)
	var skeleton: Skeleton3D = actor._support.skeleton
	for index in skeleton.get_bone_count(): result.poses.append(skeleton.get_bone_global_pose(index))
	Cleanup.release(actor,self)
	return result
func run() -> void:
	CardDB.load_all()
	verify_disk = OS.get_cmdline_user_args().has("disk")
	for id in [&"creature_ratnik_light",&"creature_kolossar_stone",&"creature_rogozhuk_stone",&"creature_klykar_shadow",&"creature_levian_tide",&"creature_dragnar_fire"]:
		var d := CardDB.creature(id)
		CreatureModels.preparation_cache.clear()
		if verify_disk: PreparationStore.enabled = false
		var fresh := snapshot(d)
		await process_frame
		if verify_disk:
			CreatureModels.preparation_cache.clear()
			PreparationStore.enabled = true
		var hits_before: int = PreparationStore.statistics().hits
		var cached := snapshot(d)
		if verify_disk and fresh.limbs.any(func(limb: Dictionary) -> bool: return not limb.samples.is_empty()):
			check(PreparationStore.statistics().hits > hits_before,"persistent sole data loaded: "+String(id))
		check(fresh.limbs == cached.limbs,"cached sole samples and anchors are identical: "+String(id))
		for bone in fresh.poses.size(): check(fresh.poses[bone].is_equal_approx(cached.poses[bone]),"cached support gives same pose: "+String(id))
		print("CACHE ",id," cold_ms=",fresh.ms," cached_ms=",cached.ms)
		await process_frame
	CreatureModels.clear()
	check(CreatureModels.preparation_cache.is_empty(),"new match releases preparation cache")
	await process_frame
	print("Preparation cache: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
