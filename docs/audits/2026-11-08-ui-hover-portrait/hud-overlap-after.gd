extends SceneTree
const WINDOW=preload("res://tools/test_window.gd")
var rows=[]
func _initialize()->void:
 WINDOW.background(self);run.call_deferred()
func _finalize()->void:WINDOW.finish(self)
func rect(c:Control)->Array:
 var r=c.get_global_rect();return [r.position.x,r.position.y,r.size.x,r.size.y]
func run()->void:
 CardDB.load_all()
 DeviceSettings.settings_path="res://build/checks/card-hover-independent-2026-11-08/isolated-settings.cfg"
 DeviceSettings.reload_settings();DeviceSettings.set_reduce_motion(true)
 root.content_scale_size=Vector2i(1280,720)
 for dims in [Vector2i(960,540),Vector2i(1280,720)]:
  root.size=dims
  for style in [DeviceSettings.CLASSIC,DeviceSettings.DEVICE]:
   DeviceSettings.set_style(style)
   var hud=HudUI.new();root.add_child(hud)
   hud.setup_plates([Color.RED,Color.RED,Color.RED],[Color.BLUE,Color.BLUE,Color.BLUE])
   hud.set_names("Игрок","Очень длинное русское имя соперника — Александр Константинович")
   var texture=GradientTexture2D.new();hud.set_portrait(0,texture);hud.set_portrait(1,texture)
   hud.set_status(12,1,3,3)
   hud.set_hint("Соперник бросает Колоссара Тени на выбранную карту ворот")
   for i in 4:await process_frame
   rows.append({"physical":str(dims),"logical":str(root.get_visible_rect().size),"style":style,"hint":rect(hud._hint_plate),"enemy":rect(hud._plates[1]),"hint_enemy_overlap":hud._hint_plate.get_global_rect().intersection(hud._plates[1].get_global_rect()).get_area(),"turn_enemy_overlap":hud._turn_clip.get_global_rect().intersection(hud._plates[1].get_global_rect()).get_area()})
   hud.queue_free()
   for i in 3:await process_frame
 var f=FileAccess.open("res://build/checks/card-hover-independent-2026-11-08/hud-overlap-after.json",FileAccess.WRITE);f.store_string(JSON.stringify({"scope":"Actual production HudUI rects, no visual proof","rows":rows},"  "));f.close();print(JSON.stringify(rows));quit()
