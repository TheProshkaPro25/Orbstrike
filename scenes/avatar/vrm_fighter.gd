class_name VrmFighter
extends VrmAvatar
## Retargeted Quaternius full-body clips; facial performance remains independent.
const LIBRARIES := [preload("res://assets/avatars/motions/fighter_0.res"),preload("res://assets/avatars/motions/fighter_1.res")]
const DURATIONS := {"throw":1.80,"card_throw":3.10,"command":2.80,"gate":2.24,"victory":2.0,"defeat":1.6}
const THROW_RELEASE := .60
var motion := "idle"
var motion_time := 0.0
var idle_time := 0.0
var active_turn := false
var _axes: Array[Quaternion] = []
var _bones: Dictionary = {}
var _free_arm_bones: Dictionary = {}
var _clips: Dictionary = {}
var _visemes: Array[Dictionary] = []
var _grip_rotations: Dictionary = {}
var _card_grip := Transform3D.IDENTITY
var _stance_feet: Dictionary = {}
var _grip_roll_axis := Vector3.UP
var _hand_vertices: Array[Dictionary] = []
var _grips: Dictionary = {}
var native_motions := false
var ability_variant := "CastDirect"
static var _native_libraries: Array[AnimationLibrary] = []
static var _native_checked := false
var ability_card: AbilityCardProp

static func prepare_native_libraries() -> void:
	if _native_checked: return
	_native_checked = true
	for model in 2:
		var path := "res://assets/avatars/motions/kevin_local/fighter_%d.res" % model
		if not ResourceLoader.exists(path):
			_native_libraries.clear()
			return
		var library := load(path) as AnimationLibrary
		if library == null:
			_native_libraries.clear()
			return
		for clip in ["BallThrow","Boomerang","CastingEnter","CastingExit","CastDirect","CastCall"]:
			if not library.has_animation(clip):
				_native_libraries.clear()
				return
		_native_libraries.append(library)

func ball_release_time() -> float: return .92 if native_motions else THROW_RELEASE
func card_release_time() -> float: return 1.00 if native_motions else THROW_RELEASE
func ability_ignition_time() -> float: return .22 if native_motions else .27

func add_motion_library(library: AnimationLibrary,prefix: String = "") -> void:
	for clip_name in library.get_animation_list():
		var clip := library.get_animation(clip_name)
		var tracks: Array[Dictionary] = []
		for track in clip.get_track_count():
			var bone := skeleton.find_bone(str(clip.track_get_path(track).get_subname(0)))
			if bone < 0: continue
			tracks.append({"bone":bone,"type":clip.track_get_type(track),"track":track})
		_clips[prefix+clip_name] = {"animation":clip,"tracks":tracks}

func prepare_ability(card: CardDef, element: int) -> void:
	ability_card.configure(card,element,ability_ignition_time(),DURATIONS.command)

func apply_profile(profile: Dictionary) -> void:
	super.apply_profile(profile)
	if ability_card == null:
		ability_card = AbilityCardProp.new()
		add_child(ability_card)
	reset_motion()
	_visemes.clear()
	for mesh in meshes:
		if not "Face" in str(mesh.name): continue
		for index in mesh.get_blend_shape_count():
			var shape := str(mesh.mesh.get_blend_shape_name(index))
			for suffix in ["_MTH_A","_MTH_I","_MTH_O"]:
				if shape.ends_with(suffix): _visemes.append({"mesh":mesh,"index":index,"vowel":suffix})
	_axes.clear()
	_bones.clear()
	skeleton.force_update_all_bone_transforms()
	for bone in skeleton.get_bone_count():
		_axes.append(skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion())
		_bones[str(skeleton.get_bone_name(bone))] = bone
	_free_arm_bones.clear()
	var free_chain: Array[int] = [_bones["LeftShoulder"]]
	var cursor := 0
	while cursor < free_chain.size():
		var bone: int = free_chain[cursor]
		_free_arm_bones[bone] = true
		free_chain.append_array(skeleton.get_bone_children(bone))
		cursor += 1
	_clips.clear()
	var library: AnimationLibrary = LIBRARIES[selected]
	for clip_name in library.get_animation_list():
		var clip := library.get_animation(clip_name)
		var tracks: Array[Dictionary] = []
		for track in clip.get_track_count():
			var bone := skeleton.find_bone(str(clip.track_get_path(track).get_subname(0)))
			assert(bone >= 0)
			tracks.append({"bone":bone,"type":clip.track_get_type(track),"track":track})
		_clips[clip_name] = {"animation":clip,"tracks":tracks}
	prepare_native_libraries()
	native_motions = _native_libraries.size() == 2
	if native_motions: add_motion_library(_native_libraries[selected],"ready/")
	# Gestures may move hands outside the original relaxed-pose bounds.
	body_part.custom_aabb = AABB(Vector3(-2,-.5,-2),Vector3(4,4,4))
	_cache_hand_vertices()
	_build_card_grip()
	reset_motion()
	_sample_clip("Idle_Loop",0,1.0)
	skeleton.force_update_all_bone_transforms()
	_stance_feet.clear()
	for side in ["Left","Right"]:
		_stance_feet[side] = skeleton.get_bone_global_pose(_bones[side+"Foot"])
	reset_motion()

func reset_motion() -> void:
	motion = "idle"
	motion_time = 0.0
	idle_time = 0.0
	active_turn = false
	if ability_card != null: ability_card.clear()
	if skeleton != null:
		for bone in _bind_poses.size(): skeleton.set_bone_pose(bone,_bind_poses[bone])
	if actor != null: actor.position = Vector3.ZERO
	set_expression("RESET")
	_speak(0,false)

func play_motion(value: String) -> void:
	if not DURATIONS.has(value): return
	if ability_card != null: ability_card.clear()
	motion = value
	motion_time = 0.0
	set_expression("happy" if value == "victory" else "sad" if value == "defeat" else "RESET")

func _process(delta: float) -> void:
	if _axes.is_empty(): return
	idle_time += delta
	motion_time += delta
	if DURATIONS.has(motion) and motion_time >= DURATIONS[motion]:
		motion = "idle"
		motion_time = 0.0
		set_expression("RESET")
	sample_motion(motion_time,idle_time)

func sample_motion(time: float,idle_phase: float = -1.0) -> void:
	if _clips.is_empty(): return
	for bone in _bind_poses.size(): skeleton.set_bone_pose(bone,_bind_poses[bone])
	actor.position = Vector3.ZERO
	# Explicit samples are independent of earlier calls; live playback carries
	# the idle phase through gestures so the return cannot jump to frame zero.
	_sample_clip("Idle_Loop",fposmod(idle_phase if idle_phase >= 0.0 else time,2.5),1.0)
	_speak(time,motion in ["throw","card_throw","command","gate"])
	if native_motions and motion in ["throw","card_throw","command"]:
		_sample_native_action(time)
		if motion == "command": _present_card_arm(time)
		_update_ability_card(time)
		return
	match motion:
		"throw","card_throw":
			var blend := smoothstep(0,.18,time)*(1.0-smoothstep(1.52,1.76,time))
			_sample_clip("OverhandThrow",clampf(time-.18,0,1.333333),blend)
		"command":
			_sample_ability(_ability_source_time(time))
			_present_card_arm(time)
		"gate":
			_sample_clip("Interact",clampf(time-.12,0,2.0),smoothstep(0,.12,time)*(1.0-smoothstep(2.0,2.24,time)))
		"victory":
			_sample_reaction(time,true)
		"defeat":
			_sample_reaction(time,false)
	_update_ability_card(time)

func _sample_reaction(time: float,won: bool) -> void:
	# The reaction sits above the same idle stance: feet remain planted while
	# chest, shoulders, elbows and head take separate beats and settle together.
	var duration: float = DURATIONS.victory if won else DURATIONS.defeat
	var anticipation := smoothstep(0.0,.18,time)*(1.0-smoothstep(.18,.46,time))
	var body := smoothstep(.18,.60,time)*(1.0-smoothstep(duration-.37,duration,time))
	var arms := smoothstep(.25,.69,time)*(1.0-smoothstep(duration-.42,duration,time))
	var head := smoothstep(.32,.73,time)*(1.0-smoothstep(duration-.32,duration,time))
	if anticipation <= 0.0 and body <= 0.0 and arms <= 0.0 and head <= 0.0: return
	if won:
		_add_body_rotation("Spine",Vector3(.08*anticipation,-.07*body,.04*body))
		_add_body_rotation("Chest",Vector3(.10*anticipation-.12*body,-.12*body,.07*body))
		_add_body_rotation("RightShoulder",Vector3(-.04*arms,0,-.15*arms))
		_add_body_rotation("RightUpperArm",Vector3(-.34*arms,0,-1.02*arms))
		_add_body_rotation("RightLowerArm",Vector3(-.24*arms,0,-.35*arms))
		_add_body_rotation("LeftShoulder",Vector3(0,0,.08*body))
		_add_body_rotation("LeftUpperArm",Vector3(-.14*body,0,.22*body))
		_add_body_rotation("LeftLowerArm",Vector3(-.20*body,0,-.24*body))
		_add_body_rotation("Head",Vector3(-.07*anticipation+.09*head,.09*head,-.04*head))
	else:
		_add_body_rotation("Spine",Vector3(-.04*anticipation+.13*body,0,-.04*body))
		_add_body_rotation("Chest",Vector3(-.04*anticipation+.17*body,.035*body,-.035*body))
		_add_body_rotation("LeftShoulder",Vector3(0,0,-.10*body))
		_add_body_rotation("RightShoulder",Vector3(0,0,.10*body))
		_add_body_rotation("LeftUpperArm",Vector3(.08*arms,0,-.13*arms))
		_add_body_rotation("RightUpperArm",Vector3(.08*arms,0,.13*arms))
		_add_body_rotation("LeftLowerArm",Vector3(.10*arms,0,.17*arms))
		_add_body_rotation("RightLowerArm",Vector3(.10*arms,0,-.17*arms))
		_add_body_rotation("Head",Vector3(.31*head,-.04*head,.035*head))

func _sample_native_action(time: float) -> void:
	if motion == "command":
		# Keep the source torso/weight shift, but stretch its presentation beat.
		# Blend the same clip back to idle: CastingExit starts in a different pose.
		var name := "ready/"+ability_variant
		var source_time := _ability_source_time(time)
		_sample_clip(name,minf(source_time+.20,_clips[name].animation.length),smoothstep(0,.12,time)*(1.0-smoothstep(1.75,DURATIONS.command,time)),true)
	else:
		var name := "ready/Boomerang" if motion == "card_throw" else "ready/BallThrow"
		var length: float = _clips[name].animation.length
		_sample_clip(name,clampf(time-.15,0,length),smoothstep(0,.15,time)*(1.0-smoothstep(DURATIONS[motion]-.20,DURATIONS[motion],time)))
		if motion == "card_throw" and time < card_release_time(): card_hand_transform("Right")

func _ability_source_time(time: float) -> float:
	if time < .40: return time
	if time < 1.75: return lerpf(.40,.65,(time-.40)/1.35)
	return lerpf(.65,1.50,smoothstep(1.75,DURATIONS.command,time))

func _present_card_arm(time: float) -> void:
	# Solve shoulder, elbow and wrist together. Turning only the wrist by PI
	# twists the sleeve and leaves the palm facing the audience in Direct_R.
	var weight := smoothstep(0,.28,time)*(1.0-smoothstep(1.75,DURATIONS.command,time))
	if weight <= 0: return
	skeleton.force_update_all_bone_transforms()
	var upper: int = _bones["RightUpperArm"]
	var lower: int = _bones["RightLowerArm"]
	var hand: int = _bones["RightHand"]
	var chain := [upper,lower,hand]
	var original: Array[Quaternion] = []
	for bone in chain: original.append(skeleton.get_bone_pose_rotation(bone))
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var elbow := skeleton.get_bone_global_pose(lower).origin
	var wrist := skeleton.get_bone_global_pose(hand).origin
	var upper_length := shoulder.distance_to(elbow)
	var lower_length := elbow.distance_to(wrist)
	var size := (upper_length+lower_length)/.52
	# Elbow stays low and slightly out; raised forearm carries the upright card.
	# This leaves a moderate wrist bend instead of a fully extended casting palm.
	var target := shoulder+Vector3(-.025,-.075,.29)*size
	var axis := (target-shoulder).normalized()
	var distance := minf(shoulder.distance_to(target),(upper_length+lower_length)*.96)
	target = shoulder+axis*distance
	var pole := Vector3(-.45,-1,-.2)
	pole = (pole-axis*pole.dot(axis)).normalized()
	var along := (upper_length*upper_length+distance*distance-lower_length*lower_length)/(2*distance)
	var target_elbow := shoulder+axis*along+pole*sqrt(maxf(0,upper_length*upper_length-along*along))
	var normal := Vector3(0,.08,1).normalized()
	var across := Vector3.RIGHT
	var up := normal.cross(across).normalized()
	var card_basis := Basis(across,normal,-up)
	var grip: Transform3D = _grips.Right.transform
	var hand_basis := card_basis*grip.basis.orthonormalized().inverse()
	# Transport the desired hand frame through the bind chain, then aim each
	# segment. This keeps the elbow hinge and forearm roll consistent with it.
	var rest_hand := skeleton.get_bone_global_rest(hand).basis
	var rest_lower := skeleton.get_bone_global_rest(lower).basis
	var rest_upper := skeleton.get_bone_global_rest(upper).basis
	var lower_basis := hand_basis*rest_hand.inverse()*rest_lower
	var lower_axis := rest_lower.inverse()*(skeleton.get_bone_global_rest(hand).origin-skeleton.get_bone_global_rest(lower).origin).normalized()
	lower_basis = Basis(Quaternion((lower_basis*lower_axis).normalized(),(target-target_elbow).normalized()))*lower_basis
	var upper_basis := lower_basis*rest_lower.inverse()*rest_upper
	var upper_axis := rest_upper.inverse()*(skeleton.get_bone_global_rest(lower).origin-skeleton.get_bone_global_rest(upper).origin).normalized()
	upper_basis = Basis(Quaternion((upper_basis*upper_axis).normalized(),(target_elbow-shoulder).normalized()))*upper_basis
	var desired := [upper_basis,lower_basis,hand_basis]
	for index in chain.size():
		var bone: int = chain[index]
		var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone)).basis
		skeleton.set_bone_pose_rotation(bone,(parent.inverse()*desired[index]).get_rotation_quaternion())
		skeleton.force_update_all_bone_transforms()
	# Blend local rotations only after solving the complete target chain.
	for index in chain.size():
		var bone: int = chain[index]
		skeleton.set_bone_pose_rotation(bone,original[index].slerp(skeleton.get_bone_pose_rotation(bone),weight))
	skeleton.force_update_all_bone_transforms()

func card_hand_transform(side: String = "Left") -> Transform3D:
	var grip: Dictionary = _grips[side]
	for bone in grip.rotations: skeleton.set_bone_pose_rotation(bone,grip.rotations[bone])
	skeleton.force_update_all_bone_transforms()
	return skeleton.global_transform*skeleton.get_bone_global_pose(_bones[side+"Hand"])*grip.transform

func _add_body_rotation(bone_name: String,angles: Vector3) -> void:
	var bone: int = _bones[bone_name]
	skeleton.force_update_all_bone_transforms()
	var pose := skeleton.get_bone_global_pose(bone).basis
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone)).basis
	skeleton.set_bone_pose_rotation(bone,(parent.inverse()*Basis(Quaternion.from_euler(angles))*pose).get_rotation_quaternion())

func _sample_ability(time: float) -> void:
	var entry_blend := smoothstep(0,.12,time)
	time += .65 # Skip the old preparatory stance in the CC0 fallback too.
	# Video reference GJ9b28lxkiI, opening activation: gather, shoulder sweep,
	# diagonal accent. Keep the source full-body motion alive through the hold.
	if time < .65:
		_sample_clip("Spell_Simple_Enter",.533*smoothstep(0,.65,time),smoothstep(0,.14,time)*entry_blend,true)
	elif time < 1.55:
		var shot := lerpf(0,.22,smoothstep(.65,.92,time)) if time < .92 else lerpf(.22,.50,smoothstep(.92,1.55,time))
		_sample_clip("Spell_Simple_Shoot",shot,entry_blend,true)
	else:
		_sample_clip("Spell_Simple_Exit",.433*smoothstep(1.55,2.15,time),(1.0-smoothstep(1.96,2.15,time))*entry_blend,true)
	var gather := smoothstep(0,.40,time)*(1.0-smoothstep(.60,.92,time))*entry_blend
	var accent := smoothstep(.65,.92,time)*(1.0-smoothstep(1.40,2.05,time))*entry_blend
	_add_body_rotation("Hips",Vector3(0,-.16*gather+.12*accent,0))
	_add_body_rotation("Spine",Vector3(.10*gather,-.20*gather+.20*accent,0))
	_add_body_rotation("Chest",Vector3(0,-.24*gather+.25*accent,-.06*accent))
	_add_body_rotation("Head",Vector3(-.06*gather,.36*gather-.36*accent,0))
	_add_body_rotation("RightUpperArm",Vector3(-.38*accent,0,-.15*accent))
	# Settle after the fast sweep, without freezing the upper body.
	var settle := sin(clampf((time-.92)/.65,0,1)*PI)*accent
	_add_body_rotation("Chest",Vector3(-.025*settle,.025*settle,0))
	_add_body_rotation("RightUpperArm",Vector3(-.035*settle,.025*settle,0))
	var hips: int = _bones["Hips"]
	var scale_ratio := skeleton.get_bone_global_rest(hips).origin.y/1.0
	var shift := Vector3(.035*gather-.065*accent,-.035*gather-.025*accent,-.02*gather+.035*accent)*scale_ratio
	skeleton.set_bone_pose_position(hips,skeleton.get_bone_pose_position(hips)+shift)
	_plant_ability_feet(smoothstep(0,.18,time)*(1.0-smoothstep(1.90,2.15,time))*entry_blend)

func _aim_leg_bone(bone: int,child: int,target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var direction := (skeleton.get_bone_global_pose(child).origin-pose.origin).normalized()
	var desired := Basis(Quaternion(direction,(target-pose.origin).normalized()))*pose.basis
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone)).basis
	skeleton.set_bone_pose_rotation(bone,(parent.inverse()*desired).get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()

func _plant_ability_feet(weight: float) -> void:
	if weight <= 0: return
	skeleton.force_update_all_bone_transforms()
	for side in ["Left","Right"]:
		var thigh: int = _bones[side+"UpperLeg"]
		var calf: int = _bones[side+"LowerLeg"]
		var foot: int = _bones[side+"Foot"]
		var original := [skeleton.get_bone_pose_rotation(thigh),skeleton.get_bone_pose_rotation(calf),skeleton.get_bone_pose_rotation(foot)]
		var hip := skeleton.get_bone_global_pose(thigh).origin
		var knee := skeleton.get_bone_global_pose(calf).origin
		var ankle := skeleton.get_bone_global_pose(foot).origin
		var target: Transform3D = _stance_feet[side]
		var upper := hip.distance_to(knee)
		var lower := knee.distance_to(ankle)
		var distance := clampf(hip.distance_to(target.origin),absf(upper-lower)+.001,upper+lower-.001)
		var axis := (target.origin-hip).normalized()
		# Knee points forward; feet retain their source idle contact and yaw.
		var pole := Vector3(0,0,1)-axis*axis.dot(Vector3(0,0,1))
		pole = pole.normalized()
		var along := (upper*upper+distance*distance-lower*lower)/(2*distance)
		var desired_knee := hip+axis*along+pole*sqrt(maxf(0,upper*upper-along*along))
		_aim_leg_bone(thigh,calf,desired_knee)
		_aim_leg_bone(calf,foot,target.origin)
		var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(foot)).basis
		skeleton.set_bone_pose_rotation(foot,(parent.inverse()*target.basis).get_rotation_quaternion())
		var chain := [thigh,calf,foot]
		for index in 3:
			skeleton.set_bone_pose_rotation(chain[index],original[index].slerp(skeleton.get_bone_pose_rotation(chain[index]),weight))
		skeleton.force_update_all_bone_transforms()

func _update_ability_card(time: float) -> void:
	if motion != "command" or time >= DURATIONS.command:
		ability_card.clear()
		return
	if not ability_card.prepared: return
	ability_card.global_transform = card_hand_transform("Right")
	ability_card.sample(time)

func _roll_grip_hand(angle: float) -> void:
	skeleton.force_update_all_bone_transforms()
	var hand: int = _bones["LeftHand"]
	var forearm: int = _bones["LeftLowerArm"]
	var hand_pose := skeleton.get_bone_global_pose(hand)
	var forearm_pose := skeleton.get_bone_global_pose(forearm)
	var desired_hand := hand_pose.basis*Basis(Quaternion(_grip_roll_axis,angle))
	var axis := (hand_pose.origin-forearm_pose.origin).normalized()
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(forearm)).basis
	skeleton.set_bone_pose_rotation(forearm,(parent.inverse()*Basis(Quaternion(axis,angle*.65))*forearm_pose.basis).get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()
	parent = skeleton.get_bone_global_pose(forearm).basis
	skeleton.set_bone_pose_rotation(hand,(parent.inverse()*desired_hand).get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()

func _finger_pad(finger: String,side: String = "Left") -> Vector3:
	var distal: int = _bones[side+finger+"Distal"]
	var tip: int = skeleton.get_bone_children(distal)[0]
	return skeleton.get_bone_global_pose(distal).origin.lerp(skeleton.get_bone_global_pose(tip).origin,.75)

func _fit_finger(finger: String,target: Vector3,side: String = "Left") -> void:
	var joints := ["Distal","Proximal","Metacarpal"] if finger == "Thumb" else ["Distal","Intermediate","Proximal"]
	for iteration in 24:
		for joint in joints:
			var bone: int = _bones[side+finger+joint]
			var pose := skeleton.get_bone_global_pose(bone)
			var from := (_finger_pad(finger,side)-pose.origin).normalized()
			var to := (target-pose.origin).normalized()
			var delta := Quaternion(from,to)
			var desired := Basis(delta)*pose.basis
			var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone)).basis
			var rotation := (parent.inverse()*desired).get_rotation_quaternion()
			if finger == "Thumb":
				# Swing the phalanx, but do not accumulate axial corkscrew twist.
				var rest := _bind_poses[bone].basis.get_rotation_quaternion()
				var relative := rest.inverse()*rotation
				var child: int = skeleton.get_bone_children(bone)[0]
				var axis := skeleton.get_bone_rest(child).origin.normalized()
				var projection := axis*Vector3(relative.x,relative.y,relative.z).dot(axis)
				var twist := Quaternion(projection.x,projection.y,projection.z,relative.w)
				twist = twist.normalized() if twist.length_squared() > .000001 else Quaternion.IDENTITY
				var swing := relative*twist.inverse()
				if swing.w < 0: swing = Quaternion(-swing.x,-swing.y,-swing.z,-swing.w)
				var limit := deg_to_rad(75.0 if joint == "Metacarpal" else 90.0 if joint == "Proximal" else 80.0)
				if swing.get_angle() > limit: swing = Quaternion.IDENTITY.slerp(swing,limit/swing.get_angle())
				rotation = rest*swing
			skeleton.set_bone_pose_rotation(bone,rotation)
			skeleton.force_update_all_bone_transforms()
		if _finger_pad(finger,side).distance_to(target) < .0003: break

func _cache_hand_vertices() -> void:
	_hand_vertices.clear()
	for surface in body_part.mesh.get_surface_count():
		var arrays := body_part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride := weights.size()/vertices.size()
		for index in vertices.size():
			var dominant := 0
			for k in stride:
				if weights[index*stride+k] > weights[index*stride+dominant]: dominant = k
			var bind := joints[index*stride+dominant]
			var bone := body_part.skin.get_bind_bone(bind)
			var bone_name := str(skeleton.get_bone_name(bone))
			if not bone_name.begins_with("Left") and not bone_name.begins_with("Right"): continue
			var side := "Left" if bone_name.begins_with("Left") else "Right"
			var group := "thumb" if "Thumb" in bone_name else "palm" if bone_name == side+"Hand" else "fingers" if bone_name.trim_prefix(side).begins_with("Index") or bone_name.trim_prefix(side).begins_with("Middle") or bone_name.trim_prefix(side).begins_with("Ring") or bone_name.trim_prefix(side).begins_with("Little") else ""
			if group == "": continue
			var finger_name := ""
			for name in ["Index","Middle","Ring","Little"]:
				if bone_name.begins_with(side+name): finger_name = name
			_hand_vertices.append({"point":vertices[index],"joints":joints.slice(index*stride,(index+1)*stride),"weights":weights.slice(index*stride,(index+1)*stride),"group":group,"finger":finger_name,"side":side})

func hand_surface_samples(side: String = "Left") -> Array[Dictionary]:
	skeleton.force_update_all_bone_transforms()
	var transforms: Array[Transform3D] = []
	for bind in body_part.skin.get_bind_count():
		transforms.append(skeleton.get_bone_global_pose(body_part.skin.get_bind_bone(bind))*body_part.skin.get_bind_pose(bind))
	var samples: Array[Dictionary] = []
	for vertex in _hand_vertices:
		if vertex.side != side: continue
		var point := Vector3.ZERO
		for k in vertex.weights.size():
			if vertex.weights[k] > 0: point += (transforms[vertex.joints[k]]*vertex.point)*vertex.weights[k]
		samples.append({"point":point,"group":vertex.group,"finger":vertex.finger})
	return samples

func _build_card_grip() -> void:
	_grips.clear()
	for side in ["Left","Right"]:
		for bone in _bind_poses.size(): skeleton.set_bone_pose(bone,_bind_poses[bone])
		_grip_rotations = {}
		_build_card_grip_side(side)
		_grips[side] = {"rotations":_grip_rotations.duplicate(),"transform":_card_grip,"roll_axis":_grip_roll_axis}
	_grip_rotations = _grips.Left.rotations
	_card_grip = _grips.Left.transform
	_grip_roll_axis = _grips.Left.roll_axis

func _build_card_grip_side(side: String) -> void:
	# Fit once per profile, in skeleton space: identical contact at every action frame.
	_grip_rotations.clear()
	skeleton.force_update_all_bone_transforms()
	var hand := skeleton.get_bone_global_pose(_bones[side+"Hand"])
	var middle_rest := skeleton.get_bone_global_pose(_bones[side+"MiddleProximal"]).origin
	_grip_roll_axis = (hand.basis.inverse()*(middle_rest-hand.origin)).normalized()
	if not native_motions and side == "Left": _roll_grip_hand(PI)
	hand = skeleton.get_bone_global_pose(_bones[side+"Hand"])
	var index := skeleton.get_bone_global_pose(_bones[side+"IndexProximal"]).origin
	var middle := skeleton.get_bone_global_pose(_bones[side+"MiddleProximal"]).origin
	var little := skeleton.get_bone_global_pose(_bones[side+"LittleProximal"]).origin
	var up := (middle-hand.origin).normalized()
	var across := ((index-little) if side == "Left" else (little-index)).normalized()
	var across_sign := -1.0 if side == "Left" else 1.0
	var normal := across.cross(up).normalized()
	across = up.cross(normal).normalized()
	var size := (middle-hand.origin).length()/.073
	# Anatomical flexion: all three joints bend towards the palm (-normal).
	# Card normal points dorsally, so nails face out and finger pads face the card.
	for finger in ["Index","Middle","Ring","Little"]:
		for joint in ["Proximal","Intermediate","Distal"]:
			var bone: int = _bones[side+finger+joint]
			var child: int = skeleton.get_bone_children(bone)[0]
			var pose := skeleton.get_bone_global_pose(bone)
			var direction := (skeleton.get_bone_global_pose(child).origin-pose.origin).normalized()
			var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone)).basis
			var degrees: float = {"Proximal":5.0,"Intermediate":13.0,"Distal":18.0}[joint]
			var tangent := up*cos(deg_to_rad(degrees))-normal*sin(deg_to_rad(degrees))
			var desired := Basis(Quaternion(direction,tangent))*pose.basis
			skeleton.set_bone_pose_rotation(bone,(parent.inverse()*desired).get_rotation_quaternion())
			skeleton.force_update_all_bone_transforms()
	# Tilt the card with the average finger direction; retain a shallow flexion.
	var tip_line := (_finger_pad("Middle",side)-middle).normalized()
	normal = across.cross(tip_line).normalized()
	up = normal.cross(across).normalized()
	var plane_offset := INF
	for finger in ["Index","Middle","Ring","Little"]:
		for joint in ["Proximal","Intermediate","Distal"]:
			var point := skeleton.get_bone_global_pose(_bones[side+finger+joint]).origin
			plane_offset = minf(plane_offset,(point-index).dot(normal))
		plane_offset = minf(plane_offset,(_finger_pad(finger,side)-index).dot(normal))
	# Fit to the skinned surface, not only bone axes: skin has real thickness.
	var center := index+(up*.102+across*.032*across_sign)*size
	for sample in hand_surface_samples(side):
		var uv := Vector2((sample.point-center).dot(across),(sample.point-center).dot(up))/size
		if sample.group != "thumb" and absf(uv.x) < .062 and absf(uv.y) < .086:
			plane_offset = minf(plane_offset,(sample.point-index).dot(normal)+.005*size)
	var pinch := index+up*.026*size+normal*(plane_offset-.006*size)
	for finger in ["Index","Middle","Ring","Little"]:
		for iteration in 5:
			var nearest := INF
			var contact := Vector3.ZERO
			for sample in hand_surface_samples(side):
				if sample.finger != finger: continue
				var uv := Vector2((sample.point-center).dot(across),(sample.point-center).dot(up))/size
				if absf(uv.x) >= .059 or absf(uv.y) >= .083: continue
				var gap: float = (sample.point-pinch).dot(normal)
				if gap < nearest:
					nearest = gap
					contact = sample.point
			if not is_finite(nearest) or absf(nearest-.002*size) < .0003*size: break
			var bone: int = _bones[side+finger+"Proximal"]
			var pose := skeleton.get_bone_global_pose(bone)
			var lever := maxf((contact-pose.origin).dot(up),.025*size)
			var angle := clampf((nearest-.002*size)/lever,-.08,.08)
			var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone)).basis
			skeleton.set_bone_pose_rotation(bone,(parent.inverse()*Basis(Quaternion(across,-angle))*pose.basis).get_rotation_quaternion())
			skeleton.force_update_all_bone_transforms()
	_fit_finger("Thumb",pinch-normal*.006*size,side)
	for iteration in 10:
		var intrusion := -INF
		for sample in hand_surface_samples(side):
			var uv := Vector2((sample.point-center).dot(across),(sample.point-center).dot(up))/size
			if sample.group == "thumb" and absf(uv.x) < .061 and absf(uv.y) < .085:
				# Reserve 2 mm for skin blended with the moving forearm.
				intrusion = maxf(intrusion,(sample.point-pinch).dot(normal)+.0035*size)
		if not is_finite(intrusion) or absf(intrusion) < .0002*size: break
		_fit_finger("Thumb",_finger_pad("Thumb",side)-normal*clampf(intrusion*.65,-.010*size,.010*size),side)
	for finger in ["Thumb","Index","Middle","Ring","Little"]:
		var joints := ["Metacarpal","Proximal","Distal"] if finger == "Thumb" else ["Proximal","Intermediate","Distal"]
		for joint in joints:
			var bone: int = _bones[side+finger+joint]
			_grip_rotations[bone] = skeleton.get_bone_pose_rotation(bone)
	# Rear thumb contact is 8 mm above the lower edge, towards the corner.
	var card_pose := Transform3D(Basis(across,normal,-up).scaled(Vector3.ONE*size),pinch+(up*.076+across*.032*across_sign)*size)
	_card_grip = hand.affine_inverse()*card_pose

func _bone_world(bone_name: String) -> Vector3:
	return skeleton.to_global(skeleton.get_bone_global_pose(_bones[bone_name]).origin)

func _sample_clip(name: String,time: float,weight: float,keep_free_arm: bool = false) -> void:
	var data: Dictionary = _clips[name]
	var clip: Animation = data.animation
	for entry in data.tracks:
		# Ability acts with the card arm only; the other arm keeps its relaxed idle.
		if keep_free_arm and _free_arm_bones.has(entry.bone): continue
		if entry.type == Animation.TYPE_ROTATION_3D:
			var rotation := clip.rotation_track_interpolate(entry.track,time)
			skeleton.set_bone_pose_rotation(entry.bone,skeleton.get_bone_pose_rotation(entry.bone).slerp(rotation,weight))
		elif entry.type == Animation.TYPE_POSITION_3D:
			var position := clip.position_track_interpolate(entry.track,time)
			skeleton.set_bone_pose_position(entry.bone,skeleton.get_bone_pose_position(entry.bone).lerp(position,weight))


## A portrait samples standby on its own skeleton without touching arena playback.
func sample_standby_skeleton(target: Skeleton3D) -> void:
	for bone in _bind_poses.size(): target.set_bone_pose(bone, _bind_poses[bone])
	if not _clips.has("Idle_Loop"): return
	var data: Dictionary = _clips["Idle_Loop"]
	var clip: Animation = data.animation
	for entry in data.tracks:
		if entry.type == Animation.TYPE_ROTATION_3D:
			target.set_bone_pose_rotation(entry.bone, clip.rotation_track_interpolate(entry.track, 0.0))
		elif entry.type == Animation.TYPE_POSITION_3D:
			target.set_bone_pose_position(entry.bone, clip.position_track_interpolate(entry.track, 0.0))
	target.force_update_all_bone_transforms()

func _speak(time: float,enabled: bool) -> void:
	# Syllabic facial performance, not audio lip sync. Ends before recovery.
	var envelope := smoothstep(.10,.22,time)*(1.0-smoothstep(.92,1.20,time)) if enabled else 0.0
	var syllable := pow(maxf(0,sin(time*23.0)),.7)*envelope
	for entry in _visemes:
		if not is_instance_valid(entry.mesh): continue
		var amount := .0
		match entry.vowel:
			"_MTH_A": amount = .48*syllable
			"_MTH_I": amount = .16*syllable*(.5+.5*sin(time*11))
			"_MTH_O": amount = .22*syllable*(.5+.5*cos(time*13))
		entry.mesh.set_blend_shape_value(entry.index,amount)

func hand_position() -> Vector3:
	skeleton.force_update_all_bone_transforms()
	return skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin)

func ball_hold_position() -> Vector3:
	skeleton.force_update_all_bone_transforms()
	var wrist := _bone_world("RightHand")
	var middle := _bone_world("RightMiddleProximal")
	var palm := (_bone_world("RightIndexProximal")-_bone_world("RightLittleProximal")).cross(middle-wrist).normalized()
	return wrist+(middle-wrist)*.70+palm*CreatureBall._shell_r()*.85
