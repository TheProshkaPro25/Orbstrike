extends SceneTree
const MAP := {
"Hips":"pelvis","Spine":"spine_01","Chest":"spine_02","UpperChest":"spine_03","Neck":"neck_01","Head":"Head",
"LeftShoulder":"clavicle_l","LeftUpperArm":"upperarm_l","LeftLowerArm":"lowerarm_l","LeftHand":"hand_l",
"RightShoulder":"clavicle_r","RightUpperArm":"upperarm_r","RightLowerArm":"lowerarm_r","RightHand":"hand_r",
"LeftUpperLeg":"thigh_l","LeftLowerLeg":"calf_l","LeftFoot":"foot_l","LeftToes":"ball_l",
"RightUpperLeg":"thigh_r","RightLowerLeg":"calf_r","RightFoot":"foot_r","RightToes":"ball_r"}
const CLIPS := {1:["Idle_Loop","Spell_Simple_Enter","Spell_Simple_Idle_Loop","Spell_Simple_Shoot","Spell_Simple_Exit","Interact"],2:["OverhandThrow"]}
func _initialize() -> void: call_deferred("run")
func rig(actor: Node) -> Skeleton3D: return actor.find_children("*","Skeleton3D",true,false)[0]
func run() -> void:
	var mapping := MAP.duplicate()
	for side in ["Left","Right"]:
		for finger in ["Thumb","Index","Middle","Ring","Little"]:
			for segment in 3:
				var target: String = side+finger+["Proximal","Intermediate","Distal"][segment]
				if finger == "Thumb": target = side+"Thumb"+["Metacarpal","Proximal","Distal"][segment]
				mapping[target] = ("pinky" if finger == "Little" else finger.to_lower())+"_%02d_" % (segment+1)+("l" if side == "Left" else "r")
	var models := ["Sakurada_Fumiriya","Vita"]
	for model in 2:
		var target_actor: Node3D = load("res://assets/avatars/vrm/"+models[model]+".vrm").instantiate()
		target_actor.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(target_actor)
		var target := rig(target_actor)
		var order: Array[int] = []
		order.assign(target.get_parentless_bones())
		var cursor := 0
		while cursor < order.size():
			for child in target.get_bone_children(order[cursor]): order.append(child)
			cursor += 1
		var library := AnimationLibrary.new()
		for pack in [1,2]:
			var source_actor: Node3D = load("res://assets/avatars/motions/UAL%d.glb" % pack).instantiate()
			source_actor.process_mode = Node.PROCESS_MODE_DISABLED
			root.add_child(source_actor)
			var source := rig(source_actor)
			var player: AnimationPlayer = source_actor.find_children("*","AnimationPlayer",true,false)[0]
			print("PACK ",pack," animations ",player.get_animation_list())
			var valid := {}
			for bone_name in mapping:
				var tb := target.find_bone(bone_name)
				var sb := source.find_bone(mapping[bone_name])
				if tb >= 0 and sb >= 0: valid[tb] = sb
			var sh := source.find_bone("pelvis")
			var th := target.find_bone("Hips")
			var scale_ratio := target.get_bone_global_rest(th).origin.y/source.get_bone_global_rest(sh).origin.y
			print("MODEL ",model," mapped=",valid.size()," ratio=",scale_ratio," source hip=",source.get_bone_global_rest(sh).origin," target hip=",target.get_bone_global_rest(th).origin)
			for clip in CLIPS[pack]:
				var imported_name: String = clip.trim_suffix("_Loop")
				assert(player.has_animation(imported_name),clip)
				var length := player.get_animation(imported_name).length
				var result := Animation.new()
				result.length = length
				var tracks := {}
				for tb in valid:
					var track := result.add_track(Animation.TYPE_ROTATION_3D)
					result.track_set_path(track,NodePath(".:"+target.get_bone_name(tb)))
					tracks[tb] = track
				var pos_track := result.add_track(Animation.TYPE_POSITION_3D)
				result.track_set_path(pos_track,NodePath(".:Hips"))
				player.play(imported_name)
				var count := int(ceil(length*30))
				for frame in count+1:
					var time := minf(float(frame)/30,length)
					player.seek(time,true)
					source.force_update_all_bone_transforms()
					var desired: Dictionary = {}
					for tb in order:
						var parent := target.get_bone_parent(tb)
						var parent_rotation: Quaternion = desired[parent] if parent >= 0 else Quaternion.IDENTITY
						var local := target.get_bone_rest(tb).basis.get_rotation_quaternion()
						var world_rotation := parent_rotation*local
						if valid.has(tb):
							var sb: int = valid[tb]
							var delta := source.get_bone_global_pose(sb).basis.get_rotation_quaternion()*source.get_bone_global_rest(sb).basis.get_rotation_quaternion().inverse()
							world_rotation = delta*target.get_bone_global_rest(tb).basis.get_rotation_quaternion()
							local = parent_rotation.inverse()*world_rotation
							result.rotation_track_insert_key(tracks[tb],time,local.normalized())
						desired[tb] = world_rotation
					var displacement := (source.get_bone_global_pose(sh).origin-source.get_bone_global_rest(sh).origin)*scale_ratio
					var parent := target.get_bone_parent(th)
					var parent_rest := target.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY
					var hip := parent_rest.affine_inverse()*(target.get_bone_global_rest(th).origin+displacement)
					result.position_track_insert_key(pos_track,time,hip)
				library.add_animation(clip,result)
				print("RETARGET ",model," ",clip," length=",length)
			source_actor.queue_free()
		assert(ResourceSaver.save(library,"res://assets/avatars/motions/fighter_%d.res" % model,ResourceSaver.FLAG_COMPRESS)==OK)
		target_actor.queue_free()
	await process_frame
	quit()
