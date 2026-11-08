extends RefCounted
## Authored one-handed diagonal sword cut, baked into the actor's prepared library.
## No source GLB, skin, rest or bind changes. The hand drives the rigid sword.
const PHASES := [0.0, 0.19, 1.0/3.0, 0.56, 0.78, 1.0]
const EDITED := ["chest","neck","arm.L","forearm.L","hand.L","sword","arm.R"]
static func cache_signature(library: AnimationLibrary, player: AnimationPlayer, id: StringName) -> Array:
 var result: Array=[]
 if not String(id).begins_with("creature_ratnik_") or not library.has_animation(&"attack"):return result
 var animation:=library.get_animation(&"attack")
 for track in range(animation.get_track_count()):
  var path:=animation.track_get_path(track)
  if path.get_subname_count()!=1 or not EDITED.has(String(path.get_subname(0))):continue
  var sk:=player.get_node(player.root_node).get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
  if sk==null:continue
  var bone:=sk.find_bone(path.get_subname(0))
  if bone>=0:result.append([path,sk.get_bone_global_rest(bone)])
 return result
static func prepare(animation: Animation, player: AnimationPlayer, id: StringName, _species: StringName) -> void:
 if not String(id).begins_with("creature_ratnik_"):return
 var sk: Skeleton3D
 var tracks: Dictionary={}
 for track in range(animation.get_track_count()):
  var path:=animation.track_get_path(track)
  if path.get_subname_count()!=1 or animation.track_get_type(track)!=Animation.TYPE_ROTATION_3D:continue
  var node:=player.get_node(player.root_node).get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
  if node==null:continue
  sk=node;tracks[String(path.get_subname(0))]=track
 if sk==null:return
 for name in EDITED:
  if not tracks.has(name):return
 var first:=_pose(animation,tracks,sk,0.0)
 var base:=_globals(first,sk)
 var upper:=sk.find_bone("arm.L");var elbow:=sk.find_bone("forearm.L");var hand:=sk.find_bone("hand.L");var sword:=sk.find_bone("sword")
 var length1: float=(base[elbow] as Transform3D).origin.distance_to((base[upper] as Transform3D).origin)
 var length2: float=(base[hand] as Transform3D).origin.distance_to((base[elbow] as Transform3D).origin)
 var reach:=length1+length2
 var guard: Vector3=(base[hand] as Transform3D).origin-(base[upper] as Transform3D).origin
 var guard_pole: Vector3=(base[elbow] as Transform3D).origin-(base[upper] as Transform3D).origin
 var blade: Vector3=(base[sword] as Transform3D).basis.y.normalized()
 var hand_basis: Basis=(base[hand] as Transform3D).basis.orthonormalized()
 var hand_keys: Array=[guard,Vector3(-.25,.74,-.28)*reach,Vector3(.08,.12,.86)*reach,Vector3(.72,-.42,.30)*reach,Vector3(.35,-.62,.35)*reach,guard]
 var blade_keys: Array=[blade,Vector3(-.22,.97,-.10).normalized(),Vector3(.48,-.20,.85).normalized(),Vector3(.80,-.58,.12).normalized(),Vector3(.65,-.65,.39).normalized(),blade]
 var pole_keys: Array=[guard_pole,Vector3(-.80,.15,-.12)*reach,Vector3(-.80,-.25,.08)*reach,Vector3(-.50,-.60,.10)*reach,guard_pole,guard_pole]
 var chest_keys: Array=[Vector3.ZERO,Vector3(-7,-22,0),Vector3(5,14,0),Vector3(8,25,0),Vector3(3,12,0),Vector3.ZERO]
 var count:=maxi(91,ceili(animation.length*90.0)+1)
 var outputs: Dictionary={}
 for name in EDITED:outputs[name]=[]
 for index in range(count):
  var phase:=float(index)/float(count-1)
  var pose:=_pose(animation,tracks,sk,phase*animation.length)
  if index>0 and index<count-1:
   # Replace the generic jab's upper body; keep all lower/cloth source curves.
   for name in EDITED:pose[sk.find_bone(name)].basis=first[sk.find_bone(name)].basis
   var chest:=sk.find_bone("chest");var neck:=sk.find_bone("neck")
   var angles:=_key(chest_keys,phase)*PI/180.0
   _body_rotation(pose,sk,chest,angles)
   _body_rotation(pose,sk,neck,Vector3(-angles.x*.7,-angles.y*.6,0))
   _body_rotation(pose,sk,sk.find_bone("arm.R"),Vector3(0,0,-angles.y*.3))
   var global_pose:=_globals(pose,sk)
   var shoulder: Vector3=global_pose[upper].origin
   var target:=shoulder+_key(hand_keys,phase)
   var pole:=shoulder+_key(pole_keys,phase)
   _solve_arm(pose,global_pose,sk,upper,elbow,hand,target,pole,length1,length2)
   global_pose=_globals(pose,sk)
   var direction:=_key(blade_keys,phase).normalized()
   var desired:=Basis(Quaternion(blade,direction))*hand_basis
   _set_global_basis(pose,global_pose,sk,hand,desired)
   # Sword's local pose stays fixed in the palm; no independent blade pivot.
   pose[sword].basis=first[sword].basis
  for name in EDITED:outputs[name].append(pose[sk.find_bone(name)].basis.get_rotation_quaternion())
 for name in EDITED:
  var track: int=tracks[name]
  while animation.track_get_key_count(track)>0:animation.track_remove_key(track,animation.track_get_key_count(track)-1)
  for index in range(count):animation.rotation_track_insert_key(track,float(index)/float(count-1)*animation.length,outputs[name][index])
  animation.track_set_interpolation_type(track,Animation.INTERPOLATION_LINEAR)
static func _key(keys: Array, phase: float) -> Vector3:
 for i in range(PHASES.size()-1):
  if phase<=PHASES[i+1]:
   var t:=inverse_lerp(PHASES[i],PHASES[i+1],phase);t=t*t*(3.0-2.0*t)
   return (keys[i] as Vector3).lerp(keys[i+1],t)
 return keys[-1]
static func _pose(animation: Animation, tracks: Dictionary, sk: Skeleton3D, time: float) -> Array[Transform3D]:
 var pose: Array[Transform3D]=[]
 for bone in range(sk.get_bone_count()):
  var tr:=sk.get_bone_rest(bone);var name:=sk.get_bone_name(bone)
  if tracks.has(String(name)):tr.basis=Basis(animation.rotation_track_interpolate(tracks[String(name)],time))
  pose.append(tr)
 return pose
static func _globals(pose: Array[Transform3D], sk: Skeleton3D) -> Array[Transform3D]:
 var result: Array[Transform3D]=[]
 for i in range(pose.size()):result.append(Transform3D.IDENTITY)
 # Bone order is not assumed: clavicles were added after their descendants.
 for i in range(pose.size()):result[i]=_global(i,pose,sk)
 return result
static func _global(index: int, pose: Array[Transform3D], sk: Skeleton3D) -> Transform3D:
 var parent:=sk.get_bone_parent(index)
 return _global(parent,pose,sk)*pose[index] if parent>=0 else pose[index]
static func _body_rotation(pose: Array[Transform3D], sk: Skeleton3D, bone: int, angles: Vector3) -> void:
 var parent:=sk.get_bone_parent(bone)
 var frame:=sk.get_bone_global_rest(parent).basis.orthonormalized() if parent>=0 else Basis.IDENTITY
 var inv:=frame.inverse()
 var delta:=Basis(Quaternion((inv*Vector3.UP).normalized(),angles.y))*Basis(Quaternion((inv*Vector3.RIGHT).normalized(),angles.x))*Basis(Quaternion((inv*Vector3.BACK).normalized(),angles.z))
 pose[bone].basis=delta*pose[bone].basis
static func _set_global_basis(pose: Array[Transform3D], global_pose: Array[Transform3D], sk: Skeleton3D, bone: int, basis: Basis) -> void:
 var parent:=sk.get_bone_parent(bone)
 pose[bone].basis=(global_pose[parent].basis.inverse()*basis if parent>=0 else basis).orthonormalized()
static func _solve_arm(pose: Array[Transform3D], global_pose: Array[Transform3D], sk: Skeleton3D, upper: int, elbow: int, hand: int, target: Vector3, pole: Vector3, l1: float, l2: float) -> void:
 var a: Vector3=global_pose[upper].origin;var b: Vector3=global_pose[elbow].origin;var c: Vector3=global_pose[hand].origin
 var axis:=(target-a).normalized();var distance:=clampf(a.distance_to(target),absf(l1-l2)+.00001,l1+l2-.00001)
 var bend:=pole-a;bend-=axis*bend.dot(axis);bend=bend.normalized()
 var along:=(l1*l1+distance*distance-l2*l2)/(2.0*distance)
 var knee:=a+axis*along+bend*sqrt(maxf(0,l1*l1-along*along))
 _set_global_basis(pose,global_pose,sk,upper,Basis(Quaternion((b-a).normalized(),(knee-a).normalized()))*global_pose[upper].basis)
 global_pose=_globals(pose,sk);b=global_pose[elbow].origin;c=global_pose[hand].origin
 _set_global_basis(pose,global_pose,sk,elbow,Basis(Quaternion((c-b).normalized(),(a+axis*distance-b).normalized()))*global_pose[elbow].basis)
