extends SceneTree
## Focused old/new runtime poses: one edited knight, six unmodified giant controls.
const ReviewState := preload("res://tools/model_review_state.gd")
var failures := 0
var checks := 0
var visual := false
var family_new := false
var landmarks: Dictionary={}
var camera: Camera3D
var floor_node: MeshInstance3D
var out := "res://build/checks/humanoid-motion"
func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error("FAIL: " + why)
func values(tr: Transform3D) -> Array:
 var row_values: Array=[]
 for row in range(3):
  row_values.append(tr.basis.x[row]);row_values.append(tr.basis.y[row]);row_values.append(tr.basis.z[row]);row_values.append(tr.origin[row])
 return row_values
func difference(left: Array, right: Array) -> float:
 var result := 0.0
 for i in range(left.size()): result=maxf(result,absf(float(left[i])-float(right[i])))
 return result
func sample_actor(id: String, baseline: bool) -> Dictionary:
 var a := CreatureAnim.new();root.add_child(a);a.set_process(false)
 a.set_model(CreatureModels.build(CardDB.creature(StringName(id))),CardDB.creature(StringName(id)))
 if baseline:
  # Rebuild from the original source library, with only the new overlay omitted.
  # This does not mutate the source library or the published shared cache.
  for name in a._player.get_animation_library_list():
   var published := a._player.get_animation_library(name)
   for entry in CreatureModels.animation_library_cache.values():
    if entry.library != published: continue
    var original: AnimationLibrary=entry.original.duplicate(true)
    var identity: StringName=a._creature_id;a._creature_id=&""
    a._prepare_library(original);a._creature_id=identity
    a._player.remove_animation_library(name);a._player.add_animation_library(name,original)
    break
 a._phase=0.0;a.idle_on=true
 if visual and id.begins_with("creature_ratnik_"):
  var h:=a.get_height()
  camera.look_at_from_position(Vector3(h*1.7,h*1.85,h*2.65),Vector3(0,h*.45,0))
  (floor_node.mesh as PlaneMesh).size=Vector2(h*7,h*7)
  # Allow real draw/compute steps, unlike the headless numeric export.
  for settle in range(3):await process_frame
 var sk: Skeleton3D
 var stack: Array[Node]=[a]
 while not stack.is_empty():
  var n: Node=stack.pop_back();stack.append_array(n.get_children())
  if n is Skeleton3D:sk=n
 var report := {"id":id,"height":a.get_height(),"samples":[]}
 var contacts := [0]
 a.strike_contact.connect(func() -> void:
  contacts[0]+=1
  check(absf(a._attack_progress(a._elapsed)-1.0/3.0)<0.000001,id+" contact phase"))
 for action in ["idle","attack","hit"]:
  ReviewState.reset_actor(a)
  for frame in range(90):a._process(1.0/60.0)
  if action=="attack":a.lunge(a.get_height()*.22)
  elif action=="hit":a.hit(Color.WHITE,a.get_height()*.075)
  var frames:=ceili(a._duration*60.0) if action!="idle" else 120
  for frame in range(frames+1):
   if frame>0:a._process(1.0/60.0)
   if visual and id.begins_with("creature_ratnik_"):await process_frame
   if frame%4!=0 and frame!=frames:continue
   if visual and id.begins_with("creature_ratnik_") and action=="attack" and (not family_new or (not baseline and frame in [12,28,44,frames])):
    await RenderingServer.frame_post_draw
    var stage:=("before" if baseline else "after")+("/"+id if family_new else "")
    DirAccess.make_dir_recursive_absolute(out+"/gpu-"+stage)
    root.get_texture().get_image().save_png(out+"/gpu-"+stage+"/attack-%03d.png"%frame)
   var bones: Dictionary={}
   for i in range(sk.get_bone_count()):
    var tr:=sk.get_bone_global_pose(i)*sk.get_bone_global_rest(i).affine_inverse()
    bones[sk.get_bone_name(i)]=values(tr)
    check(tr.is_finite(),id+" finite "+str(i))
   var relative: Array=[]
   if id.begins_with("creature_ratnik_"):relative=values(sk.get_bone_global_pose(sk.find_bone("hand.L")).affine_inverse()*sk.get_bone_global_pose(sk.find_bone("sword")))
   report.samples.append({"action":action,"frame":frame,"phase":a._attack_progress(a._elapsed) if action=="attack" else 0.0,"bones":bones,"sword_relative":relative,"tip_rest":landmarks[id].tip_rest if landmarks.has(id) else [],"handle_rest":landmarks[id].handle_rest if landmarks.has(id) else [],"blade_tip":values(sk.get_bone_global_pose(sk.find_bone("sword"))*sk.get_bone_global_rest(sk.find_bone("sword")).affine_inverse()) if id.begins_with("creature_ratnik_") else [],"root_angles":[a.fx_pitch,a.fx_yaw,a.fx_roll]})
 check(contacts[0]==1,id+" one contact")
 ModelLifetime.release(a,self)
 return report
func compare(before: Dictionary, after: Dictionary) -> void:
 var id: String=before.id
 var changed:=0
 for i in range(before.samples.size()):
  var left: Dictionary=before.samples[i];var right: Dictionary=after.samples[i]
  check(left.action==right.action and left.frame==right.frame,id+" matching frame")
  check(difference(left.root_angles,right.root_angles)<0.000001,id+" root unchanged")
  if not left.sword_relative.is_empty() and left.action!="attack":check(difference(left.sword_relative,right.sword_relative)<0.000001,id+" unchanged sword outside attack")
  for bone in left.bones:
   var delta:=difference(left.bones[bone],right.bones[bone])
   var lower: bool=String(bone) in ["root","hips","thigh.L","thigh.R","shin.L","shin.R","foot.L","foot.R"]
   if not id.begins_with("creature_ratnik_") or left.action!="attack" or lower or left.frame==0 or i+1==before.samples.size() or (i+1<before.samples.size() and before.samples[i+1].action!="attack" and left.action=="attack"):
    check(delta<0.000001,id+" preserved "+left.action+" "+str(left.frame)+" "+bone)
   elif delta>0.00001:changed+=1
 if id.begins_with("creature_ratnik_"):
  check(changed>0,"knight runtime correction actually moves upper body")
  var attack: Array=after.samples.filter(func(s: Dictionary) -> bool:return s.action=="attack")
  var held: Array=attack[3].sword_relative
  for sample in attack:
   if sample.frame>=12:check(difference(held,sample.sword_relative)<0.000002,"rigid blade grip after incoming idle blend")
  var wind: Dictionary=attack[4];var contact: Dictionary=attack[7];var follow: Dictionary=attack[11]
  var a:=_blade_vector(wind);var b:=_blade_vector(contact)
  check(rad_to_deg(a.angle_to(b))>55.0,"actual surface blade rotates through slash; not translated fist")
  check(_blade_point(follow,_landmark(follow.tip_rest)).distance_to(_blade_point(contact,_landmark(contact.tip_rest)))>.20,"actual blade tip continues beyond contact")
func _blade_point(sample: Dictionary, point: Vector3) -> Vector3:
 var v: Array=sample.blade_tip
 return Vector3(v[0]*point.x+v[1]*point.y+v[2]*point.z+v[3],v[4]*point.x+v[5]*point.y+v[6]*point.z+v[7],v[8]*point.x+v[9]*point.y+v[10]*point.z+v[11])
func _blade_vector(sample: Dictionary) -> Vector3:
 return _blade_point(sample,_landmark(sample.tip_rest))-_blade_point(sample,_landmark(sample.handle_rest))
func _landmark(point: Array) -> Vector3:
 return Vector3(point[0],point[1],point[2])
func run() -> void:
 CardDB.load_all()
 family_new=OS.get_cmdline_user_args().has("family-new")
 if family_new:out="res://build/checks/ratnik-family"
 var source_rows: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ratnik_sword_landmarks.json"))
 for row in source_rows:landmarks[row.id]=row
 visual=DisplayServer.get_name()!="headless"
 if visual:
  root.size=Vector2i(640,640)
  var environment:=WorldEnvironment.new();environment.environment=Environment.new()
  environment.environment.background_mode=Environment.BG_COLOR
  environment.environment.background_color=Color(.05,.065,.09)
  environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
  environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.8
  root.add_child(environment)
  var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);light.light_energy=1.5;light.shadow_enabled=true;root.add_child(light)
  camera=Camera3D.new();camera.current=true;camera.fov=40;root.add_child(camera)
  floor_node=MeshInstance3D.new();floor_node.mesh=PlaneMesh.new();floor_node.position.y=-.03
  var material:=StandardMaterial3D.new();material.albedo_color=Color(.11,.14,.18);material.roughness=1.0;floor_node.material_override=material;root.add_child(floor_node)
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("out="):out=arg.trim_prefix("out=")
 var ids: Array[String]=["creature_ratnik_light"]
 if family_new:
  ids.clear()
  for element in ["fire","gale","stone","shadow","tide"]:ids.append("creature_ratnik_"+element)
 else:
  for element in ["fire","gale","light","stone","shadow","tide"]:ids.append("creature_kolossar_"+element)
 for id in ids:
  var before:=await sample_actor(id,true);await process_frame
  var after:=await sample_actor(id,false);await process_frame
  compare(before,after)
  for item in [["before",before],["after",after]]:
   DirAccess.make_dir_recursive_absolute(out+"/"+item[0])
   var f:=FileAccess.open(out+"/"+item[0]+"/"+id+".json",FileAccess.WRITE);f.store_string(JSON.stringify(item[1]));f.close()
  CreatureModels.clear()
 var f:=FileAccess.open(out+"/report.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Five newly updated Ratnik variants" if family_new else "Ratnik Light attack; six unmodified Kolossar controls"},"  "));f.close()
 print("HUMANOID_MOTION checks=",checks," failures=",failures)
 quit(1 if failures else 0)
