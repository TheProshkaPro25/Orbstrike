extends SceneTree
## Local licensed clips. Run export_kevin_motion.py first; no source files distributed.
const BASE := "res://assets/avatars/motions/kevin_local/"
const MAP := {"Hips":"B-hips","Spine":"B-spine","Chest":"B-chest","Neck":"B-neck","Head":"B-head"}
func _initialize() -> void: call_deferred("run")
func quat(values: Array) -> Quaternion: return Quaternion(values[0],values[1],values[2],values[3]).normalized()
func point(values: Array) -> Vector3: return Vector3(values[0],values[1],values[2])
func run() -> void:
 var mapping := MAP.duplicate()
 for side in ["Left","Right"]:
  var suffix := ".L" if side == "Left" else ".R"
  for pair in [["Shoulder","shoulder"],["UpperArm","upperArm"],["LowerArm","forearm"],["Hand","hand"],["UpperLeg","thigh"],["LowerLeg","shin"],["Foot","foot"],["Toes","toe"]]: mapping[side+pair[0]] = "B-"+pair[1]+suffix
  for finger in ["Thumb","Index","Middle","Ring","Little"]:
   for index in 3:
    var target: String = side+finger+(["Metacarpal","Proximal","Distal"][index] if finger == "Thumb" else ["Proximal","Intermediate","Distal"][index])
    var source: String = {"Thumb":"thumb","Index":"indexFinger","Middle":"middleFinger","Ring":"ringFinger","Little":"pinky"}[finger]
    mapping[target] = "B-"+source+"%02d" % (index+1)+suffix
 for model in 2:
  var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE+"samples_"+("M" if model == 0 else "F")+".json"))
  var actor: Node3D = VrmAvatar.MODELS[model].instantiate()
  actor.process_mode = Node.PROCESS_MODE_DISABLED
  root.add_child(actor)
  var rig: Skeleton3D = actor.find_children("*","Skeleton3D",true,false)[0]
  var order: Array[int] = []
  order.assign(rig.get_parentless_bones())
  var cursor := 0
  while cursor < order.size():
   for child in rig.get_bone_children(order[cursor]): order.append(child)
   cursor += 1
  var lib := AnimationLibrary.new()
  for name in source:
   var clip: Dictionary = source[name]
   var anim := Animation.new()
   anim.length = clip.duration
   if "Idle" in name or "Hold" in name: anim.loop_mode = Animation.LOOP_LINEAR
   var tracks := {}
   for target in mapping:
    var bone := rig.find_bone(target)
    if bone < 0 or not clip.rest.has(mapping[target]): continue
    var track := anim.add_track(Animation.TYPE_ROTATION_3D)
    anim.track_set_path(track,NodePath(".:"+target))
    tracks[bone] = {"track":track,"source":mapping[target]}
   var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
   anim.track_set_path(pos_track,NodePath(".:Hips"))
   var hips := rig.find_bone("Hips")
   var source_rest_hip := point(clip.rest["B-hips"].p)
   assert(source_rest_hip.y > 10.0,"FBX root reference must be calibrated upright")
   var ratio := rig.get_bone_global_rest(hips).origin.y/source_rest_hip.y
   for frame in clip.frames.size():
    var time := minf(frame/30.0,anim.length)
    var sample: Dictionary = clip.frames[frame]
    var world := {}
    for bone in order:
     var parent := rig.get_bone_parent(bone)
     var parent_rotation: Quaternion = world[parent] if parent >= 0 else Quaternion.IDENTITY
     var local := rig.get_bone_rest(bone).basis.get_rotation_quaternion()
     var desired := parent_rotation*local
     if tracks.has(bone):
      var key: String = tracks[bone].source
      desired = quat(sample[key].q)*quat(clip.rest[key].q).inverse()*rig.get_bone_global_rest(bone).basis.get_rotation_quaternion()
      local = parent_rotation.inverse()*desired
      anim.rotation_track_insert_key(tracks[bone].track,time,local.normalized())
     world[bone] = desired
    var displacement := (point(sample["B-hips"].p)-source_rest_hip)*ratio
    var parent := rig.get_bone_parent(hips)
    var rest := rig.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY
    anim.position_track_insert_key(pos_track,time,rest.affine_inverse()*(rig.get_bone_global_rest(hips).origin+displacement))
   lib.add_animation(name,anim)
   print("KEVIN ",model," ",name," ",anim.length," bones ",tracks.size())
  assert(ResourceSaver.save(lib,BASE+"fighter_%d.res" % model,ResourceSaver.FLAG_COMPRESS)==OK)
  actor.queue_free()
 for i in 3: await process_frame
 print("Local motion libraries prepared")
 quit()
