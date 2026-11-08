extends SceneTree
const WINDOW = preload("res://tools/test_window.gd")
const OUT = "res://build/checks/card-hover-independent-2026-11-08"
var result={"scope":"Actual production CardView focus lifecycle, headless; no visual or physical mouse claim","states":[]}
func _initialize()->void:
 WINDOW.background(self)
 run.call_deferred()
func _finalize()->void:WINDOW.finish(self)
func layers(c:Control)->int:
 var n=0
 for x in c.get_children():
  if x is CanvasLayer:n+=1
 return n
func run()->void:
 root.size=Vector2i(1280,720)
 root.content_scale_size=Vector2i(1280,720)
 CardDB.load_all()
 var a=CardView.new().for_card(CardDB.card(&"arena_field_fire"),Vector2(100,140))
 var b=Button.new();b.text="other";b.position=Vector2(400,100)
 root.add_child(a);root.add_child(b)
 await process_frame
 for batch in 3:
  var start=Time.get_ticks_usec()
  for i in 30:
   a.grab_focus();b.grab_focus()
  a.grab_focus()
  await process_frame
  await process_frame
  result.states.append({"state":"focused_after_batch%d"%batch,"live_canvas_layers":layers(a),"node_count":get_node_count(),"elapsed_us":Time.get_ticks_usec()-start,"focused":a.has_focus()})
 b.grab_focus()
 for i in 3:await process_frame
 result.states.append({"state":"after_blur","live_canvas_layers":layers(a),"node_count":get_node_count()})
 a.queue_free();b.queue_free()
 for i in 3:await process_frame
 result.window={"max_fps":Engine.max_fps,"display":DisplayServer.get_name()}
 var f=FileAccess.open(OUT+"/focus-growth-after.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
 print(JSON.stringify(result));quit()
