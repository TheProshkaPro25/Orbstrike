extends Node3D
## Обжитая смотровая терраса: один статический mesh, один материал, без lights/physics.
## Геометрия отделена от города и каталога существ; время суток меняет только uniform.
var material: ShaderMaterial
var geometry: MeshInstance3D
var stair_landing := Vector3.ZERO

func _ready() -> void:
	position = Vector3(-22.0, 26.0, 220.0)
	var k := MenuTraffic.MeshKit.new()
	# Подпорная кладка и толстая кромка; грунт остаётся под площадкой.
	k.box(Vector3(-23,-15,-12),Vector3(30,-.55,19),0)
	k.box(Vector3(-23.4,-.55,-12.4),Vector3(30.4,0,19.4),1)
	# Спуск с холма к набережной, с низкими каменными щеками.
	for i in range(48):
		var z := -13.2-float(i)*1.15
		var y := -.6-float(i)*.64
		k.box(Vector3(-13,y-1.2,z-1.15),Vector3(-3,y,z),1)
		for x: float in [-14.0,-2.0]:
			k.box(Vector3(x-.35,y-1.5,z-1.15),Vector3(x+.35,y+.6,z),0)
		stair_landing = Vector3(-8,y,z-.575)
		var ground: float = get_parent().height_at(position.x-8.0,position.z+z-.575)-position.y
		if y <= ground+.64: break
	# Ограда открывает вид с сидячего места: каменные столбики и тонкий металл.
	for x: float in [-22,-14,-2,10,18,29]:
		k.box(Vector3(x-.32,0,-12),Vector3(x+.32,1.75,-11.35),0)
		k.box(Vector3(x-.48,1.75,-12.15),Vector3(x+.48,1.98,-11.2),1)
	for bounds: Vector2 in [Vector2(-22,-14),Vector2(-2,29)]:
		for y: float in [.55,1.45]:
			k.box(Vector3(bounds.x,y,-11.72),Vector3(bounds.y,y+.09,-11.61),2)
		var x := bounds.x
		while x < bounds.y:
			k.box(Vector3(x,.56,-11.72),Vector3(x+.075,1.45,-11.61),2)
			x += 1.25
	# Скамьи смотрят на город; доски раздельные, опоры и крепления металлические.
	for center: Vector2 in [Vector2(15,-4),Vector2(-17,5)]:
		for x: float in [-2.2,2.2]:
			k.box(Vector3(center.x+x-.16,0,center.y-.85),Vector3(center.x+x+.16,.85,center.y+.9),2)
			k.box(Vector3(center.x+x-.15,.65,center.y+.67),Vector3(center.x+x+.15,2.2,center.y+.83),2)
		for i in range(5):
			var z := center.y-.9+float(i)*.36
			k.box(Vector3(center.x-3,.82,z),Vector3(center.x+3,1.03,z+.28),3)
		for i in range(3):
			var y := 1.25+float(i)*.35
			k.box(Vector3(center.x-3,y,center.y+.8),Vector3(center.x+3,y+.27,center.y+1.02),3)
	# Невысокая зелень смягчает край каменной террасы; места прохода свободны.
	for center: Vector2 in [Vector2(-17,-8),Vector2(8,-8),Vector2(26,0)]:
		k.box(Vector3(center.x-2.8,0,center.y-1.2),Vector3(center.x+2.8,.85,center.y+1.2),0)
		k.box(Vector3(center.x-2.65,.85,center.y-1.05),Vector3(center.x+2.65,.92,center.y+1.05),6)
		for i in range(5):
			k.shade = float(i)*.17
			k.ico(Vector3(center.x-2.0+float(i),1.35,center.y),Vector3(.8,.75,.85),6)
	k.shade = 0.0
	# Пергола у края кадра даёт камерный масштаб и полосы тени, сохраняя панораму.
	for x: float in [19,28]:
		for z: float in [5,16]:
			k.box(Vector3(x-.34,0,z-.34),Vector3(x+.34,4.8,z+.34),3)
		k.box(Vector3(x-.25,4.6,4.2),Vector3(x+.25,5.05,16.8),3)
	for i in range(10):
		var z := 4.5+float(i)*1.35
		k.box(Vector3(18.3,4.92,z-.10),Vector3(28.7,5.18,z+.10),3)
	# Лампы тёплые и невысокие: эмиссия в стекле, без дополнительных теневых источников.
	for point: Vector2 in [Vector2(27,-10),Vector2(-21,-10),Vector2(27,15)]:
		k.box(Vector3(point.x-.5,0,point.y-.5),Vector3(point.x+.5,.25,point.y+.5),0)
		k.box(Vector3(point.x-.15,.25,point.y-.15),Vector3(point.x+.15,3.25,point.y+.15),2)
		k.box(Vector3(point.x-.4,2.65,point.y-.4),Vector3(point.x+.4,3.3,point.y+.4),5)
		k.box(Vector3(point.x-.55,3.3,point.y-.55),Vector3(point.x+.55,3.5,point.y+.55),2)
	# Шесть минеральных вставок — городской знак стихий, встроенный в камень.
	var center := Vector3(3,.035,4)
	for i in range(96):
		var a := TAU*float(i)/96.0
		var b := TAU*float(i+1)/96.0
		var p := Vector3(cos(a),0,sin(a))
		var q := Vector3(cos(b),0,sin(b))
		k.quad(center+p*4.1,center+q*4.1,center+q*4.25,center+p*4.25,2,center-Vector3.UP)
	for i in range(6):
		k.shade = float(i)/5.0
		var a := TAU*float(i)/6.0+.025
		var b := TAU*float(i+1)/6.0-.025
		var pa := center+Vector3(cos(a),0,sin(a))*3.6
		var pb := center+Vector3(cos(b),0,sin(b))*3.6
		k.tri(center,pa,pb,4,center-Vector3.UP)
	material = ShaderMaterial.new()
	material.shader = preload("res://scenes/menu/overlook.gdshader")
	geometry = MeshInstance3D.new()
	geometry.name = "TerraceStoneWoodIron"
	geometry.mesh = k.commit()
	geometry.material_override = material
	add_child(geometry)

func update_night(night: float) -> void:
	material.set_shader_parameter("night",night)

func apply_quality(level: int) -> void:
	geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if level == GraphicsSettings.Level.LOW else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
