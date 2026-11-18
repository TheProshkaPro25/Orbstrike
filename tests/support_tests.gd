extends SceneTree
const ModelTestCleanup := preload("res://scenes/model_lifetime.gd")
const ModelReviewState := preload("res://tools/model_review_state.gd")
## Полнотелая опора: конечные позиции, подошвы, сохранение длин костей, конечные значения.
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error(message)
func _initialize():call_deferred("run")
func run():
 CardDB.load_all()
 var definitions := CardDB.all_creatures()
 for definition in definitions:
  var actor := CreatureAnim.new()
  root.add_child(actor);actor.set_process(false)
  actor.set_model(CreatureModels.build(definition),definition);actor.idle_on=true
  _check_support(actor, definition)
  if definition.id in [&"creature_rogozhuk_stone", &"creature_rogozhuk_light"]:
   _check_beetle_clearance(actor, definition)
  actor.reset();ModelTestCleanup.release(actor, self);CreatureModels.clear()
  await process_frame
 print("Полнотелая опора: %d моделей, проверок %d, ошибок %d"%[definitions.size(),checks,failures])
 quit(1 if failures else 0)

func _check_support(actor: CreatureAnim, definition: CreatureDef) -> void:
  var support=actor._support
  if definition.species == &"grifalon" and actor._authored_fullset:
   check(actor._flyer and support == null,"авторский полёт без наземной опоры: %s"%definition.id)
   return
  check(support != null and support.skeleton != null,"скелет опоры: %s"%definition.id)
  if support == null or support.skeleton == null: return
  for f in range(50):actor._process(1.0/60.0)
  if definition.species in [&"armat", &"floris", &"octo"]:
   # These three local rigs use clip-owned appendages with their own bone names.
   check(support.limbs.is_empty() and support.last_ground_errors.is_empty(),"лапами управляет клип: %s"%definition.id)
   return
  var authored_kolossar := definition.species == &"kolossar" and actor._authored_grounded
  var height := actor.get_height()
  if not actor._flyer and definition.species != &"levian":
   check(not support.last_ground_errors.is_empty(),"подошвы найдены: %s"%definition.id)
   for error in support.last_ground_errors:
    # Kolossar's clip can lift a foot. Late authored support only corrects penetration.
    check(error >= -height*.015 if authored_kolossar else absf(error)<height*.006,
     "опора в ожидании: %s, отклонение %.4f"%[definition.id,error])
  var initial_rotations: Array[Quaternion] = []
  for limb in support.limbs: initial_rotations.append(support.skeleton.get_bone_pose_rotation(limb.a))
  var leg_motion := 0.0
  var landing_error := 0.0
  actor.lunge(height*.22)
  for f in range(100):
   actor._process(1.0/60.0)
   if actor._action == &"attack" and actor._attack_progress(actor._elapsed)>.75:
    for error in support.last_ground_errors:
     # Authored recovery can carry the lead foot through the air.
     landing_error=maxf(landing_error,-error if actor._authored_grounded else absf(error))
   for l in range(support.limbs.size()):
    leg_motion=maxf(leg_motion,initial_rotations[l].angle_to(support.skeleton.get_bone_pose_rotation(support.limbs[l].a)))
   if f%15==0:
    for limb in support.limbs:
     var a:Transform3D=support.skeleton.get_bone_global_pose(limb.a)
     var b:Transform3D=support.skeleton.get_bone_global_pose(limb.b)
     var c:Transform3D=support.skeleton.get_bone_global_pose(limb.c)
     check(a.origin.is_finite() and b.origin.is_finite() and c.origin.is_finite(),"конечная поза ног: %s"%definition.id)
     var rest_a:Transform3D=support.skeleton.get_bone_global_rest(limb.a)
     var rest_b:Transform3D=support.skeleton.get_bone_global_rest(limb.b)
     check(absf(a.origin.distance_to(b.origin)-rest_a.origin.distance_to(rest_b.origin))<0.001,"бедро не растянуто: %s"%definition.id)
  if not support.limbs.is_empty():check(leg_motion>.03,"ноги участвуют в атаке: %s"%definition.id)
  if not actor._flyer:
   check(landing_error<height*(.015 if authored_kolossar else .006),"после выпада подошвы возвращаются на пол: %s (%.4f)"%[definition.id, landing_error])
  if actor._ratnik_trellis:
   for error in support.last_ground_errors:
    check(absf(error)<height*.006,"Ратник завершает возврат с обеими подошвами на полу: %s"%definition.id)


func _check_beetle_clearance(actor: CreatureAnim, definition: CreatureDef) -> void:
 var step := 1.0/60.0
 var height := actor.get_height()
 var poses := [&"windup", &"hit", &"recovery"] if definition.attribute == Attr.A.LIGHT else [&"windup"]
 for pose in poses:
  actor._phase = 0.0
  ModelReviewState.reset_actor(actor)
  actor.idle_on = true
  for frame in 45: actor._process(step)
  var elapsed: float
  if pose == &"hit":
   actor.hit(Color.WHITE,height*.075)
   elapsed = actor._duration*.46
  else:
   actor.lunge(height*.22)
   elapsed = actor._contact_time*.75 if pose == &"windup" else actor._duration*.77
  for frame in ceili(elapsed/step+.00001): actor._process(step)
  var lowest := _beetle_floor_clearance(actor)
  check(is_finite(lowest.x) and lowest.x >= -.02*height,"низ сетки: %s, %s (%.2f%% роста)"%[definition.id,pose,100*lowest.x/height])
  check(is_finite(lowest.y) and lowest.y >= -.006*height,"просвет правых лап: %s, %s (%.2f%% роста)"%[definition.id,pose,100*lowest.y/height])


func _beetle_floor_clearance(actor: CreatureAnim) -> Vector2:
 # Use the entire deformed mesh, independently of the support solver's samples.
 var lowest := Vector2(INF,INF)
 var right_bones := [&"thigh.R", &"shin.R", &"foot.R", &"rear_thigh.R", &"rear_shin.R", &"rear_foot.R"]
 for mesh in actor._meshes:
  var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
  if skeleton == null or mesh.skin == null: continue
  var palette: Array[Transform3D] = []
  var right_slots := PackedByteArray()
  for slot in mesh.skin.get_bind_count():
   var bone := mesh.skin.get_bind_bone(slot)
   if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(slot))
   palette.append(mesh.global_transform*skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(slot))
   right_slots.append(int(skeleton.get_bone_name(bone) in right_bones))
  for surface in mesh.mesh.get_surface_count():
   var arrays := mesh.mesh.surface_get_arrays(surface)
   var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
   var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
   var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
   @warning_ignore("integer_division")
   var stride := weights.size()/vertices.size()
   for vertex in vertices.size():
    var y := 0.0
    var right_weight := 0.0
    for offset in range(vertex*stride,(vertex+1)*stride):
     if weights[offset] > 0.0:
      var slot := joints[offset]
      y += (palette[slot]*vertices[vertex]).y*weights[offset]
      right_weight += right_slots[slot]*weights[offset]
    lowest.x = minf(lowest.x,y)
    if right_weight >= .65: lowest.y = minf(lowest.y,y)
 return lowest
