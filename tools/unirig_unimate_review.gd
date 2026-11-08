extends SceneTree
## Isolated comparison renderer. Native clips and accepted runtime are explicitly separate.
const WINDOW := preload("res://tools/test_window.gd")
const RESET := preload("res://tools/model_review_state.gd")
const SOURCE := "res://assets/creatures_hd/grifalon_light.glb"
const EXPERIMENT := "res://build/experiments/unirig-unimate-2026-11-08"
var path := EXPERIMENT+"/input/grifalon_light.glb"
var out := EXPERIMENT+"/baseline"
var mode := "baseline"
var label := "accepted_source"
var aliases: Dictionary={}
var motion_samples := 4
var only_attack := false
var alignment_path := ""
var checks := 0
var failures := 0
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var camera_distance := 26.0
var target_height := 5.0
var reference_hover := 2.0
var report := {"captures":[],"modes":[],"scope":"No production writes. Native GLB clips are not runtime support/gameplay acceptance."}
func _initialize() -> void:
 if not has_meta("sfery_background_draw"):WINDOW.background(self)
 _run.call_deferred()
func _finalize() -> void:WINDOW.finish(self)
func check(value: bool, why: String) -> void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: "+why)
func frame(count: int=1) -> void:
 for i in range(count):await process_frame
func capture(name: String, view: Vector3=Vector3(.7,.65,1.0)) -> void:
 camera.look_at_from_position(view*camera_distance,Vector3(0,target_height+reference_hover,0))
 await frame(3);await RenderingServer.frame_post_draw
 check(Engine.max_fps==60 and root.unfocusable and root.mode==Window.MODE_MINIMIZED,"window contract")
 var image:=viewport.get_texture().get_image()
 check(not image.is_empty(),"real GPU image")
 check(image.save_png(out+"/"+name+".png")==OK,"save "+name)
 report.captures.append({"name":name,"sha256":FileAccess.get_sha256(out+"/"+name+".png")})
func make_world() -> void:
 viewport=SubViewport.new();viewport.size=Vector2i(640,640);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 world=Node3D.new();viewport.add_child(world)
 var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.055,.07,.095);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.70;world.add_child(env)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-42,-30,0);sun.light_energy=1.4;sun.shadow_enabled=true;world.add_child(sun)
 camera=Camera3D.new();camera.fov=38;camera.current=true;world.add_child(camera)
 var floor_node:=MeshInstance3D.new();var mesh:=PlaneMesh.new();mesh.size=Vector2(100,100);floor_node.mesh=mesh;floor_node.position.y=-.03
 var material:=StandardMaterial3D.new();material.albedo_color=Color(.12,.15,.19);material.roughness=1.0;floor_node.material_override=material;world.add_child(floor_node)
func player_of(node: Node) -> AnimationPlayer:
 if node is AnimationPlayer:return node
 for child in node.get_children():
  var found:=player_of(child)
  if found!=null:return found
 return null
func bones_of(node: Node) -> Array:
 var result: Array=[]
 if node is Skeleton3D:
  for bone in range(node.get_bone_count()):result.append({"name":node.get_bone_name(bone),"parent":node.get_bone_parent(bone)})
 for child in node.get_children():result.append_array(bones_of(child))
 return result
func record_runtime() -> void:
 var ball:=CreatureBall.new();world.add_child(ball);ball.setup(CardDB.creature(&"creature_grifalon_light"),81108);ball.freeze=true;ball.position.y=CreatureBall.RADIUS
 ball.open_animated(false);await frame(90)
 var actor: CreatureAnim=ball._anim;actor.set_process(false);ball.set_physics_process(false);actor._phase=0;actor.idle_on=true
 reference_hover=actor.get_hover_height();target_height=actor.get_height()*.45
 camera_distance=maxf(actor.get_height()+reference_hover,actor.get_extent())*2.4
 report.camera={"distance":camera_distance,"target_height":target_height,"hover":reference_hover,"fov":camera.fov,"quarter":[.7,.65,1.0],"side":[1,.5,0]}
 report.modes.append({"mode":"runtime_ordinary_creatureball","bones":bones_of(actor),"clips":Array(actor._player.get_animation_list()),"height":actor.get_height(),"extent":actor.get_extent()})
 for action in ["idle","attack","hit"]:
  for phase in [0.0,1.0/3.0,2.0/3.0,1.0]:
   RESET.reset_actor(actor);actor.idle_on=true
   for settle in range(60):actor._process(1.0/60)
   if action=="attack":actor.lunge(actor.get_height()*.22)
   elif action=="hit":actor.hit(Color.WHITE,actor.get_height()*.075)
   var duration:=2.0 if action=="idle" else actor._duration
   for tick in range(roundi(duration*phase*60.0)):actor._process(1.0/60)
   await capture("runtime-"+action+"-"+str(roundi(phase*100)))
 await capture("runtime-last-side",Vector3(1,.5,0))
 ModelLifetime.release(ball,self);await frame(2);CreatureModels.clear()
func record_native() -> void:
 var definition:=CardDB.creature(&"creature_grifalon_light")
 var document:=GLTFDocument.new();var state:=GLTFState.new()
 check(document.append_from_file(path,state)==OK,"native GLB parse")
 var imported:=document.generate_scene(state)
 check(imported!=null,"native scene")
 if imported==null:return
 var model: Node3D
 if not alignment_path.is_empty():
  # Invert the measured canonical frame and retain the SOURCE normalization.
  # Transforming a canonical axis-aligned box would spuriously enlarge its bounds.
  var alignment: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(alignment_path))
  var rows: Array=alignment.source_from_unimate_canonical_matrix_row_major
  var basis:=Basis(Vector3(rows[0][0],rows[1][0],rows[2][0]),Vector3(rows[0][1],rows[1][1],rows[2][1]),Vector3(rows[0][2],rows[1][2],rows[2][2]))
  var inverse_node:=Node3D.new();inverse_node.transform=Transform3D(basis,Vector3(rows[0][3],rows[1][3],rows[2][3]));inverse_node.add_child(imported)
  var normalization:=Node3D.new();normalization.scale=Vector3.ONE*float(alignment.reference_normalization_scale)
  var origin: Array=alignment.reference_normalization_origin;normalization.position=Vector3(origin[0],origin[1],origin[2]);normalization.add_child(inverse_node)
  model=Node3D.new();model.add_child(normalization);model.set_meta("height",alignment.reference_height);model.set_meta("extent",alignment.reference_extent)
  CreatureModels._release_unused_hd_maps(model);CreatureModels._fix_hd_materials(model,definition.attribute)
  report.render_alignment=alignment;report.render_alignment_path=alignment_path
 else:
  var packed:=PackedScene.new();check(packed.pack(imported)==OK,"native pack");ModelLifetime.release(imported,self);await frame()
  CreatureModels._scenes["hd:grifalon_light"]=packed
  model=CreatureModels.build(definition)
 world.add_child(model);model.position.y=reference_hover
 var player:=player_of(model)
 report.modes.append({"mode":"native_glb_no_runtime_support","bones":bones_of(model),"clips":Array(player.get_animation_list()) if player!=null else [],"height":model.get_meta("height",0),"extent":model.get_meta("extent",0)})
 if player!=null:player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;player.stop()
 await capture("native-rest-quarter");await capture("native-rest-side",Vector3(1,.5,0))
 if player!=null:
  for action in (["attack"] if only_attack else ["idle","attack","hit"]):
   var clip: StringName=StringName(aliases.get(action,action))
   if not player.has_animation(clip):
    if aliases.has(action):check(false,"requested clip missing: "+String(clip))
    continue
   var animation:=player.get_animation(clip)
   for sample_index in range(motion_samples):
    var phase:=float(sample_index)/float(motion_samples-1)
    player.play(clip,0.0);player.seek(animation.length*phase,true);player.advance(0)
    await capture("native-"+action+"-"+str(roundi(phase*100)))
 ModelLifetime.release(model,self);await frame(2);CreatureModels.clear()
func _run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("path="):path=arg.trim_prefix("path=")
  elif arg.begins_with("out="):out=arg.trim_prefix("out=")
  elif arg.begins_with("mode="):mode=arg.trim_prefix("mode=")
  elif arg.begins_with("label="):label=arg.trim_prefix("label=")
  elif arg.begins_with("clips="):aliases=JSON.parse_string(arg.trim_prefix("clips="))
  elif arg.begins_with("motion-samples="):motion_samples=maxi(2,int(arg.trim_prefix("motion-samples=")))
  elif arg=="only-attack":only_attack=true
  elif arg.begins_with("alignment="):alignment_path=arg.trim_prefix("alignment=")
 DirAccess.make_dir_recursive_absolute(out)
 report.label=label;report.path=path;report.source_sha256=FileAccess.get_sha256(path);report.production_sha256=FileAccess.get_sha256(SOURCE);report.mode=mode;report.clip_aliases=aliases;report.motion_samples=motion_samples;report.phase_comparison="normalized clip phase, not equal wall-clock time"
 if DisplayServer.get_name()=="headless" or RenderingServer.get_rendering_device()==null:
  check(false,"hardware windowed GPU required")
 else:
  report.adapter=RenderingServer.get_video_adapter_name();report.display=DisplayServer.get_name();report.engine=Engine.get_version_info()
  CardDB.load_all();make_world()
  if mode=="baseline":await record_runtime()
  else:
   var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(EXPERIMENT+"/baseline/report.json"))
   camera_distance=reference.camera.distance;target_height=reference.camera.target_height;reference_hover=reference.camera.hover
   report.camera=reference.camera
  await record_native()
 check(FileAccess.get_sha256(SOURCE)==report.production_sha256,"production source unchanged")
 report.checks=checks;report.failures=failures;report.visual_review="OPEN: Sol must inspect PNGs";report.is_baseline_only=mode=="baseline"
 var file:=FileAccess.open(out+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 print("UNIRIG_UNIMATE_REVIEW ",checks,"/",failures," PNG=",report.captures.size()," label=",label)
 quit(1 if failures else 0)
