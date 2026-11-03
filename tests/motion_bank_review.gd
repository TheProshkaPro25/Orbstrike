extends SceneTree
func _initialize() -> void: call_deferred("run")
func frames(n: int) -> void:
 for i in n: await process_frame
 await RenderingServer.frame_post_draw
func run() -> void:
 root.size = Vector2i(1280,720)
 RenderingServer.viewport_set_size(root.get_viewport_rid(),1280,720)
 var out := "res://build/checks/motion-bank/"
 DirAccess.make_dir_recursive_absolute(out)
 var view := VrmPreview.new()
 root.add_child(view)
 var parent := view.avatar.get_parent()
 view.avatar.queue_free()
 var fighter := VrmFighter.new()
 parent.add_child(fighter)
 view.avatar = fighter
 fighter.set_process(false)
 for model in 2:
  var profile := PlayerProfile.DEFAULT.duplicate(true)
  profile.vrm_model = model
  fighter.apply_profile(profile)
  view.set_face_view(false)
  view.camera.position.z *= 1.4
  var library: AnimationLibrary = load("res://assets/avatars/motions/kevin_local/fighter_%d.res" % model)
  fighter.add_motion_library(library,"bank/")
  for name in ["Boomerang","BallThrow","CastCall","CastDirect"]:
   var duration := library.get_animation(name).length
   for frame in 24:
    fighter.reset_motion()
    fighter._sample_clip("bank/"+name,float(frame)/23*duration,1.0)
    await frames(2)
    var im := view.viewport.get_texture().get_image()
    var width := im.get_height()*5/6
    im = im.get_region(Rect2i((im.get_width()-width)/2,0,width,im.get_height()))
    im.resize(500,600)
    im.save_png(out+"%d-%s-%02d.png" % [model,name,frame])
 view.queue_free()
 await frames(6)
 print("Motion bank previews ready")
 quit()
