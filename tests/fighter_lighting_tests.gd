extends SceneTree
class LightWorld extends "res://scenes/main.gd":
 func _ready() -> void: _build_world()
 func _exit_tree() -> void: pass
var failures := 0
const OUT := "res://build/checks/fighter-lighting/"
func _initialize() -> void: call_deferred("run")
func frames(n: int) -> void:
 for i in n: await process_frame
 await RenderingServer.frame_post_draw
func run() -> void:
 root.size = Vector2i(768,768)
 RenderingServer.viewport_set_size(root.get_viewport_rid(),768,768)
 DirAccess.make_dir_recursive_absolute(OUT)
 GraphicsSettings.level = GraphicsSettings.Level.HIGH
 ArenaLocations._current = 0
 var host := LightWorld.new()
 root.add_child(host)
 var world: Node3D = host.world
 var arena: Arena = host.arena
 var fighter := VrmFighter.new()
 world.add_child(fighter)
 fighter.set_process(false)
 fighter.position = Vector3(-2.3,0,preload("res://scenes/main.gd").THROW_Z+1.4)
 fighter.rotation.y = PI
 var camera: CameraRig = host.cam
 camera.cull_mask = 0xFFFFF
 camera.set_process(false)
 print("Temple lights: ",arena._sanctuary_lights.size()," sun mask ",host._sun.light_cull_mask)
 var portrait := FighterPortrait.new()
 root.add_child(portrait)
 var results := []
 for choice in [Vector2i(0,0),Vector2i(0,1),Vector2i(1,0)]:
  var profile := PlayerProfile.DEFAULT.duplicate(true)
  profile.vrm_model = choice.x
  profile.vrm_clothes = choice.y
  fighter.apply_profile(profile)
  fighter.sample_motion(.3)
  portrait.bind(fighter,0)
  camera.fighter_view(fighter,"command")
  camera.cut()
  await frames(6)
  var image := root.get_texture().get_image()
  image.save_png(OUT+"sanctuary-%d-%d.png" % [choice.x,choice.y])
  fighter.hide()
  await frames(3)
  var background := root.get_texture().get_image()
  fighter.show()
  await frames(3)
  var foreground := 0
  var clipped := 0
  var sum := 0.0
  for y in range(100,680,2):
   for x in range(150,620,2):
    var c := image.get_pixel(x,y)
    var bg := background.get_pixel(x,y)
    if maxf(absf(c.r-bg.r),maxf(absf(c.g-bg.g),absf(c.b-bg.b))) < .08: continue
    foreground += 1
    sum += c.get_luminance()
    if c.r > .97 and c.g > .97 and c.b > .97: clipped += 1
  var fraction := float(clipped)/maxi(1,foreground)
  results.append({"model":choice.x,"clothes":choice.y,"clipped":fraction,"mean":sum/maxi(1,foreground)})
  if foreground < 500 or fraction > .12:
   failures += 1
   printerr("FAIL: sanctuary avatar clipping ",choice," fraction=",fraction," foreground=",foreground)
 FileAccess.open(OUT+"metrics.json",FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
 print("Fighter lighting: ",JSON.stringify(results))
 var clear := ColorRect.new()
 clear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.add_child(clear)
 portrait.queue_free()
 fighter.queue_free()
 await frames(6)
 host.queue_free()
 for i in 6: await process_frame
 if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
 if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
 for i in 3: await process_frame
 quit(1 if failures else 0)
