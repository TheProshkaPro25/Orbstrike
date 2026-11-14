extends RefCounted
## Лунная гавань: затопленный морской город вокруг круглой портовой площади.
## Вся архитектура собирается один раз в статические MultiMesh; физических тел нет.
const D := preload("res://scenes/landscape_detail.gd")
const Locations := preload("res://data/arena_locations.gd")
const LANTERN_LIGHT := Color(1.0, .61, .31)
const SQUARE_LANTERN_COUNT := 14
const SQUARE_LANTERN_RADIUS := 63.2
const SQUARE_LANTERN_SCALE := .92
const LANTERN_GLASS_HEIGHT := 8.6
const QUAY_LANTERN_RADIUS := 99.9
const QUAY_LANTERN_SCALE := .78
const QUAY_LANTERN_FOOT := 11.48

static func build(arena: Node3D) -> void:
	var r := {
		"box": BoxMesh.new(), "rod": D.rod(12), "shaft": D.rod(24),
		"arch": D.arch(1.0,.21,1.0,20), "spandrel": _spandrel(), "roof": _roof(), "gable": _gable(), "dome": _dome(),
		"rock": _rock(), "hull": D.hull(), "sail": _sail(),
		"stone": _masonry(Color(.25,.33,.34),Color(.14,.20,.22)),
		"pale": _masonry(Color(.49,.54,.52),Color(.28,.36,.37)),
		"city": _masonry(Color(.37,.42,.43),Color(.20,.26,.28)),
		"ochre": _masonry(Color(.59,.45,.31),Color(.30,.26,.22)),
		"plaster": _masonry(Color(.65,.61,.50),Color(.37,.39,.35)),
		"rose": _masonry(Color(.48,.34,.31),Color(.27,.24,.24)),
		"tile": _roof_material(Color(.31,.15,.095),false),
		"slate": _roof_material(Color(.16,.22,.27),false),
		"patina": _roof_material(Color(.18,.32,.29),true),
		"awning": D.material(Color(.36,.18,.16),.98),
		"net": D.material(Color(.25,.31,.29),1.0),
		"dark": D.material(Color(.027,.057,.069),.94),
		"cliff": _cliff_material(Color(.075,.12,.14)),
		"cliff_light": _cliff_material(Color(.14,.205,.22)),
		"copper": _roof_material(Color(.13,.29,.28),true),
		"metal": D.material(Color(.31,.29,.20),.52,.56),
		"wood": D.material(Color(.19,.105,.053),.96),
		"plank": D.material(Color(.34,.225,.115),.95),
		"rope": D.material(Color(.39,.35,.24),1.0),
		"cloth": D.material(Color(.55,.52,.39),.95),
		"warm": arena._glow_mat(Color(.96,.65,.31),.84),
		"blue": arena._glow_mat(Color(.37,.70,.80),.70),
	}
	# Оконный ритм боковых стен — часть материала дома, без тысяч мелких деталей.
	for key in ["ochre","plaster","rose","city"]:
		r["house_"+key] = r[key].duplicate()
		r["house_"+key].set_shader_parameter("side_windows",true)
	r.cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Собственная вода только ЗА каменным кругом: убирает белое пятно и сетку волн,
	# не меняя материал поля, его геометрию, узоры или физику.
	arena._static(_sea(),_sea_material(),Vector3(0,.075,0),Vector3.ONE,Vector3.ZERO)
	_square_and_piers(arena,r)
	_quays(arena,r)
	_port_work(arena,r)
	_city(arena,r)
	_palace(arena,r,Vector3(92,12,-117),-.28)
	_observatory(arena,r,Vector3(-94,12,-119),.23)
	_bridge(arena,r)
	# Большой торговый парусник стоит в бассейне, а не случайно посреди моря.
	_ship(arena,r,Vector3(-87,.2,5),.10,1.65)
	_ship(arena,r,Vector3(88,.2,23),.35,.79)
	_ship(arena,r,Vector3(-70,.2,96),-.9,.65)
	_islands(arena,r)
	var moon := SphereMesh.new()
	moon.radius = 13
	moon.height = 26
	moon.radial_segments = 40
	moon.rings = 20
	arena._static(moon,arena._glow_mat(Color(.74,.86,.97),1.02),Locations.HARBOR_MOON,Vector3.ONE,Vector3.ZERO)
	var chimney_tops: Array[Vector3] = [Vector3(-101.5,52.15,-145),Vector3(91.5,62.15,-145),Vector3(33.6,65.65,-174)]
	preload("res://scenes/landscape_atmosphere.gd").smoke(arena,chimney_tops)
	arena._decor.set_meta("detailed_location",2)


static func _p(arena: Node3D, r: Dictionary, mesh: String, mat: String, center: Vector3, yaw: float, p: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	D.piece(arena,r[mesh],r[mat],center,yaw,p,size,rot)


static func _square_and_piers(arena: Node3D, r: Dictionary) -> void:
	# Широкая гранитная кромка превращает арену в портовую площадь.
	for i in 112:
		var a := TAU*(i+.5)/112.0
		var p := Vector3(cos(a)*65.8,0,sin(a)*65.8)
		var yaw := -a-PI*.5
		_p(arena,r,"box","stone",p,yaw,Vector3(0,-.55,0),Vector3(3.8,1.7,7.4))
		_p(arena,r,"box","pale",p,yaw,Vector3(0,.32,0),Vector3(3.78,.32,7.5))
		if i%4 == 0:
			_p(arena,r,"shaft","metal",p,yaw,Vector3(0,1.0,-1.5),Vector3(.42,1.3,.42))
			_p(arena,r,"box","metal",p,yaw,Vector3(0,1.7,-1.5),Vector3(1.6,.3,.5))
	D.ring(arena,r.metal,62.0,.09,.09)
	# Главный каменный мост выходит из площади и приходит на общую набережную.
	var center := Vector3(0,0,-68)
	for i in 17:
		_p(arena,r,"box","stone",center,0,Vector3(0,.1,-i*1.8),Vector3(13,.9,1.76))
	for side in [-1.0,1.0]:
		_p(arena,r,"box","pale",center,0,Vector3(side*6.2,.6,-14.5),Vector3(.8,.5,31))
		for i in 8:
			_p(arena,r,"box","stone",center,0,Vector3(side*6.1,1.6,-i*4.1),Vector3(.6,2,.7))
		_p(arena,r,"box","metal",center,0,Vector3(side*6.1,2.6,-14.4),Vector3(.21,.2,30))
	# Боковые рабочие понтоны связаны с портовой стеной, проход оставлен открытым.
	for side in [-1.0,1.0]:
		var c := Vector3(side*70,0,8)
		var yaw: float = -side*PI*.5
		for i in 26:
			_p(arena,r,"box","plank",c,yaw,Vector3(0,.25,-i*1.6),Vector3(10,.5,1.52))
		for z in [-2.0,-13.0,-24.0,-37.0]:
			for x in [-4.1,4.1]:
				_p(arena,r,"rod","wood",c,yaw,Vector3(x,.6,z),Vector3(.5,4.0,.5))
				_p(arena,r,"shaft","metal",c,yaw,Vector3(x,2.5,z),Vector3(.56,.3,.56))
		for i in 4:
			var p := Vector3(-2.7+(i%2)*5.4,1.55,-27-i*3.1)
			_p(arena,r,"box","plank",c,yaw,p,Vector3(2.5,2.2,2.5))
			for x in [-.8,.8]:
				_p(arena,r,"box","metal",c,yaw,p+Vector3(x,0,0),Vector3(.12,2.3,2.6))
	for i in SQUARE_LANTERN_COUNT:
		var angle := TAU * (i + .5) / SQUARE_LANTERN_COUNT
		var radial := Vector3(cos(angle), 0, sin(angle))
		var point := radial * SQUARE_LANTERN_RADIUS
		var target := radial * 47.0
		var quality := GraphicsSettings.Level.MEDIUM
		# The east-facing battle camera sees the shoulders lit by these foreground lamps.
		if i in [0, 1, 12, 13]:
			target = Vector3(14.0, 3.8, 17.0 if point.z >= 0.0 else -17.0)
			quality = GraphicsSettings.Level.LOW
		_lantern(arena, r, point, SQUARE_LANTERN_SCALE, target, quality)


static func _quays(arena: Node3D, r: Dictionary) -> void:
	# Непрерывная вогнутая каменная набережная с глубокими водяными аркадами.
	# Тёмная задняя стенка проёма отнесена на восемь единиц, архивольт объёмный.
	for i in 21:
		var a := -1.43+i*.143
		var center := Vector3(sin(a)*108,0,-cos(a)*108)
		var yaw := -a
		_p(arena,r,"box","stone",center,yaw,Vector3(0,4.6,-7.3),Vector3(16.4,11.2,17))
		for side in [-1.0,1.0]:
			_p(arena,r,"box","stone",center,yaw,Vector3(side*6.7,3,2.7),Vector3(2.8,8,5))
		_p(arena,r,"arch","pale",center,yaw,Vector3(0,1.5,3.8),Vector3(5.35,5.35,2.7))
		_p(arena,r,"box","city",center,yaw,Vector3(0,9.2,3.0),Vector3(16.4,3.4,5.5))
		_p(arena,r,"box","pale",center,yaw,Vector3(0,11,0),Vector3(16.7,.85,19.0))
		_p(arena,r,"box","metal",center,yaw,Vector3(0,11.5,6.2),Vector3(16.0,.18,.22))
		# Парапет с прорезями вместо глухой стены над водой.
		for j in 5:
			_p(arena,r,"box","pale",center,yaw,Vector3((j-2)*3.1,12.5,7.2),Vector3(.5,2.2,.6))
		_p(arena,r,"box","pale",center,yaw,Vector3(0,13.6,7.2),Vector3(16.4,.4,.85))
		if i%3 == 0:
			var quality := GraphicsSettings.Level.MEDIUM if i % 6 == 0 else GraphicsSettings.Level.HIGH
			var inward := Vector3(-sin(a), 0, cos(a))
			var point := -inward * QUAY_LANTERN_RADIUS + Vector3.UP * QUAY_LANTERN_FOOT
			# Aim along the arcade front and the water under it, rather than into the parapet.
			_lantern(arena, r, point, QUAY_LANTERN_SCALE, center + inward * 14.5 + Vector3.UP * 2.5, quality)
	# Передняя сторона остаётся низкой: волнолом/скалистый берег замыкают бухту,
	# но не перекрывают камеру обзора и выбор локации.
	for i in 21:
		var a := 1.57+i*.157
		var center := Vector3(sin(a)*120,0,-cos(a)*120)
		var yaw := -a
		_p(arena,r,"box","stone",center,yaw,Vector3(0,1.4,0),Vector3(19.5,4.7,13))
		_p(arena,r,"box","pale",center,yaw,Vector3(0,3.9,0),Vector3(19.7,.55,13.3))
		if i%3 == 0:
			_p(arena,r,"rock","dark",center,yaw,Vector3(0,1,11),Vector3(17,7,17))
	# Низкая широкая лестница от главного мостика на верхнюю набережную.
	for i in 18:
		_p(arena,r,"box","pale",Vector3.ZERO,0,Vector3(0,.35+i*.65,-97-i*.65),Vector3(18,.7,1.2))
	# Маяк принадлежит волнолому: каменное основание непрерывно связано с ним.
	_lighthouse(arena,r,Vector3(119,4,39),.92)
	_lighthouse(arena,r,Vector3(-117,4,58),.62)


static func _port_work(arena: Node3D, r: Dictionary) -> void:
	# Обжитая кромка бассейна: швартовные тумбы, лестницы, деревянные отбойники.
	# Высокие детали стоят на верхней набережной, вне круга и главного прохода.
	for i in 9:
		if i == 4: continue
		var a := -1.28+i*.32
		var c := Vector3(sin(a)*108,0,-cos(a)*108)
		var yaw := -a
		for dx in [-4.0,4.0]:
			_p(arena,r,"rod","wood",c,yaw,Vector3(dx,2.2,6.2),Vector3(.43,6,.43))
			_p(arena,r,"shaft","metal",c,yaw,Vector3(dx,4.9,6.2),Vector3(.48,.3,.48))
		_p(arena,r,"shaft","metal",c,yaw,Vector3(-4,12.1,4.6),Vector3(.4,1.1,.4))
		_p(arena,r,"box","metal",c,yaw,Vector3(-4,12.7,4.6),Vector3(1.6,.3,.5))
		for dx in [-.85,.85]:
			_p(arena,r,"rod","metal",c,yaw,Vector3(dx,5.7,5.9),Vector3(.11,12.2,.11))
		for j in 12:
			_p(arena,r,"box","metal",c,yaw,Vector3(0,.3+j*.95,6),Vector3(1.8,.13,.2))
		# Грузовая площадка с бочками и закрытыми ящиками.
		for j in 3:
			var p := Vector3(3.4+float(j%2)*2.1,12.5,-1.7-j*1.7)
			_p(arena,r,"shaft","wood",c,yaw,p,Vector3(.85,2.4,.85))
			for dy in [-.8,.8]:
				_p(arena,r,"shaft","metal",c,yaw,p+Vector3(0,dy,0),Vector3(.89,.15,.89))
		if i%2 == 0:
			_p(arena,r,"box","plank",c,yaw,Vector3(-3,12.8,-3),Vector3(3,2.6,2.8))
			for dx in [-1.0,1.0]:
				_p(arena,r,"box","wood",c,yaw,Vector3(-3+dx,12.8,-1.5),Vector3(.16,2.8,.2))
		# Навес над рыбным прилавком: ткань, стойки и сам прилавок.
		if i in [1,2,6,7]:
			_p(arena,r,"box","plank",c,yaw,Vector3(0,12.9,-3.2),Vector3(7,1.5,2.4))
			for dx in [-3.5,3.5]:
				for z in [-5.0,-.8]:
					_p(arena,r,"rod","wood",c,yaw,Vector3(dx,14.3,z),Vector3(.16,5.5,.16))
			for j in 7:
				_p(arena,r,"box","cloth" if j%2 == 0 else "awning",c,yaw,Vector3(j-3,17,-2.9),Vector3(.98,.18,5),Vector3(.14,0,0))
		# Два маленьких портальных крана: широкие треноги и подвешенные крюки.
		if i in [0,8]:
			for dx in [-2.4,2.4]:
				_p(arena,r,"box","wood",c,yaw,Vector3(dx,17,-1),Vector3(.65,11,.7))
			_p(arena,r,"box","wood",c,yaw,Vector3(0,22.5,1.3),Vector3(6.8,.7,7))
			_p(arena,r,"rod","rope",c,yaw,Vector3(0,15.6,4.4),Vector3(.08,13,.08))
			_p(arena,r,"arch","metal",c,yaw,Vector3(0,8.8,4.4),Vector3(.6,.6,.15),Vector3(0,0,PI))
	# Низкие рыбацкие лодки и рамы сушащихся сетей оживляют обратный вид.
	for side in [-1.0,1.0]:
		var c := Vector3(side*80,.08,66)
		var yaw: float = -side*.88
		_p(arena,r,"hull","wood",c,yaw,Vector3.ZERO,Vector3(.72,.7,1.05))
		for j in 5:
			_p(arena,r,"box","plank",c,yaw,Vector3(0,1.2,(j-2)*3),Vector3(4.2,.22,.65))
		_p(arena,r,"box","wood",c,yaw,Vector3(.4,1.5,0),Vector3(.18,.18,18),Vector3(0,.2,0))
		var frame := Vector3(side*101,4.2,65.5)
		for dx in [-4.0,4.0]:
			_p(arena,r,"rod","wood",frame,yaw,Vector3(dx,2,0),Vector3(.18,4,.18))
		_p(arena,r,"box","wood",frame,yaw,Vector3(0,4,0),Vector3(8.6,.2,.22))
		for j in 9:
			_p(arena,r,"rod","net",frame,yaw,Vector3(j-4,2.6,0),Vector3(.025,2.7,.025))
		for j in 6:
			_p(arena,r,"box","net",frame,yaw,Vector3(0,1.4+j*.48,0),Vector3(8,.025,.025))


static func _city(arena: Node3D, r: Dictionary) -> void:
	# Три связанные террасы старого города, а не одинаковые отдельные склады.
	for row in 3:
		var z := -140.0-row*29.0
		var width := 285.0+row*38
		_p(arena,r,"box","stone",Vector3.ZERO,0,Vector3(0,8+row*7,z),Vector3(width,18+row*7,32))
		_p(arena,r,"box","pale",Vector3.ZERO,0,Vector3(0,17.4+row*10.5,z+15.8),Vector3(width+1,.9,1.6))
		for i in 15:
			# По оси оставлен канал/проход и вид на дальнюю башню.
			if row == 0 and i in [6,7,8]: continue
			var x := (i-7)*19.3
			var height := 17.0+fmod(float(i*13+row*7),20.0)+row*5
			var c := Vector3(x,17.8+row*10.5,z-1)
			_townhouse(arena,r,c,height,(i+row*3)%5,i+row*15)
	# Дальняя часовая башня города, видимая поверх крыш, принадлежит застройке.
	var c := Vector3(27,28,-207)
	_p(arena,r,"box","city",c,0,Vector3(0,36,0),Vector3(17,72,19))
	for y in [2.0,31.0,57.0,72.0]:
		_p(arena,r,"box","pale",c,0,Vector3(0,y,0),Vector3(19,1.2,21))
	_p(arena,r,"roof","copper",c,0,Vector3(0,73,0),Vector3(24,15,25))
	# Циферблат на тёмной круглой нише и металлические стрелки.
	_p(arena,r,"shaft","metal",c,0,Vector3(0,61,10.2),Vector3(5.3,.55,5.3),Vector3(PI*.5,0,0))
	_p(arena,r,"shaft","blue",c,0,Vector3(0,61,10.6),Vector3(4.65,.2,4.65),Vector3(PI*.5,0,0))
	_p(arena,r,"box","dark",c,0,Vector3(-.8,62,10.8),Vector3(.35,3.2,.22),Vector3(0,0,-.55))
	_p(arena,r,"box","dark",c,0,Vector3(1,61.5,10.9),Vector3(2.5,.35,.22),Vector3(0,0,.4))


static func _townhouse(arena: Node3D, r: Dictionary, c: Vector3, h: float, style: int, seed_index: int) -> void:
	# Функция здания читается в фасаде и кровле: склад, жилой дом, мастерская,
	# купеческая лоджия и дом с открытой террасой. Палитра приглушена ночным светом.
	var wall: String = ["ochre","plaster","rose","city","plaster"][style]
	var depth := 20.5+float(seed_index%3)*1.1
	var front := depth*.5
	_p(arena,r,"box","house_"+wall,c,0,Vector3(0,h*.5,0),Vector3(17.7,h,depth))
	_p(arena,r,"box","stone",c,0,Vector3(0,1.4,0),Vector3(18.1,2.8,depth+.5))
	_p(arena,r,"box","pale",c,0,Vector3(0,h-.6,0),Vector3(18.8,.85,depth+1))
	for dx in [-8.2,8.2]:
		_p(arena,r,"box","pale",c,0,Vector3(dx,h*.5,front+.14),Vector3(.65,h,1.1))
	for floor_index in int(h/6.0):
		var y := 3.5+floor_index*5.8
		for column in 3:
			var dx := float(column-1)*5.15
			_p(arena,r,"box","dark",c,0,Vector3(dx,y,front+.18),Vector3(2.5,3.9,.55))
			if (seed_index+floor_index+column)%4 != 0:
				_p(arena,r,"box","warm",c,0,Vector3(dx,y,front+.48),Vector3(1.55,2.7,.12))
			_p(arena,r,"box","pale",c,0,Vector3(dx,y-1.95,front+.4),Vector3(3.2,.35,1.2))
			# Ставни только на доступном глазу первом этаже ближнего ряда.
			# Дальние тонкие переплёты не читаются и не расходуют бюджет экземпляров.
			if style in [1,2] and c.y < 20.0 and floor_index == 0:
				for side in [-1.0,1.0]:
					_p(arena,r,"box","patina",c,0,Vector3(dx+side*1.7,y,front+.4),Vector3(.7,3.2,.35))
		if style == 3 and floor_index%2 == 1:
			_p(arena,r,"box","pale",c,0,Vector3(0,y-2.1,front+1.2),Vector3(15,.55,3))
			_p(arena,r,"box","metal",c,0,Vector3(0,y-.5,front+2.5),Vector3(14,.16,.2))
			for j in 8:
				_p(arena,r,"rod","metal",c,0,Vector3((j-3.5)*1.85,y-1.3,front+2.5),Vector3(.075,1.7,.075))
	match style:
		0:
			# Высокий щипец склада, люк и выносная балка под грузовую лебёдку.
			_p(arena,r,"gable","tile",c,0,Vector3(0,h,0),Vector3(20,10,depth+2))
			_p(arena,r,"box","wood",c,0,Vector3(0,h+2,front+.14),Vector3(3.3,4.4,.4))
			_p(arena,r,"box","wood",c,0,Vector3(0,h+5.1,front+2.7),Vector3(.55,.6,5.8))
			_p(arena,r,"rod","metal",c,0,Vector3(0,h+2.5,front+5.2),Vector3(.08,5,.08))
		1:
			# Низкая черепичная кровля с небольшими слуховыми окнами.
			_p(arena,r,"roof","tile",c,0,Vector3(0,h,0),Vector3(20,5.5,depth+2))
			for dx in [-5.0,5.0]:
				_p(arena,r,"box",wall,c,0,Vector3(dx,h+1.7,front*.55),Vector3(3,3.3,3))
				_p(arena,r,"gable","slate",c,0,Vector3(dx,h+3.4,front*.55),Vector3(4,2,4))
				_window(arena,r,c,0,Vector3(dx,h+1.9,front*.55+1.6),1.1,1.8)
		2:
			# Крутая сланцевая мансарда на узком красноватом доме.
			_p(arena,r,"roof","slate",c,0,Vector3(0,h,0),Vector3(19.7,10,depth+1.5))
			_p(arena,r,"box","rose",c,0,Vector3(-5,h+7,-4),Vector3(2.3,8,3))
			_p(arena,r,"box","pale",c,0,Vector3(-5,h+11,-4),Vector3(3.2,.6,3.8))
		3:
			_p(arena,r,"roof","patina",c,0,Vector3(0,h,0),Vector3(20,4.5,depth+2))
			_p(arena,r,"shaft","pale",c,0,Vector3(2,h+5,0),Vector3(3.2,3,3.2))
			_p(arena,r,"dome","patina",c,0,Vector3(2,h+6.5,0),Vector3(3.5,4.2,3.5))
		4:
			# Плоская кровля: непрерывный парапет и лёгкая деревянная пергола.
			_p(arena,r,"box","stone",c,0,Vector3(0,h+.3,0),Vector3(18,.6,depth))
			for side in [-1.0,1.0]:
				_p(arena,r,"box","pale",c,0,Vector3(side*8.5,h+1.4,0),Vector3(.6,2.2,depth))
				_p(arena,r,"box","pale",c,0,Vector3(0,h+1.4,side*(front-.3)),Vector3(17,2.2,.6))
				for z in [-4.0,4.0]:
					_p(arena,r,"rod","wood",c,0,Vector3(side*5.5,h+3,z),Vector3(.18,5,.18))
			for j in 7:
				_p(arena,r,"box","wood",c,0,Vector3((j-3)*1.8,h+5.4,0),Vector3(.25,.3,10))
	if style in [1,3]:
		_p(arena,r,"box","awning",c,0,Vector3(0,5.7,front+2),Vector3(13,.3,4),Vector3(.15,0,0))
		for dx in [-6.2,6.2]:
			_p(arena,r,"rod","wood",c,0,Vector3(dx,2.8,front+3.7),Vector3(.12,5.6,.12))
	# Вход отличается от жилых окон; не создаёт физики и логики магазинов.
	_p(arena,r,"box","wood",c,0,Vector3(0,2.3,front+.7),Vector3(3.6,4.6,.5))
	_p(arena,r,"box","metal",c,0,Vector3(.9,2.1,front+1),Vector3(.2,.2,.2))


static func _palace(arena: Node3D, r: Dictionary, c: Vector3, yaw: float) -> void:
	# Морская таможня: тяжёлое основание, лоджии, протяжённая медная кровля,
	# ступенчатый центральный ризалит и две башни; фасад обращён к бухте.
	_p(arena,r,"box","stone",c,yaw,Vector3(0,3,0),Vector3(91,8,34))
	_p(arena,r,"box","city",c,yaw,Vector3(0,20,-5),Vector3(84,32,27))
	for y in [7.0,22.0,36.5]:
		_p(arena,r,"box","pale",c,yaw,Vector3(0,y,-1),Vector3(88,1.1,35))
	_p(arena,r,"roof","copper",c,yaw,Vector3(0,37,-3),Vector3(91,13,39))
	for i in 11:
		var x := (i-5)*7.5
		_p(arena,r,"box","pale",c,yaw,Vector3(x,14,16),Vector3(1.3,14,1.5))
		_p(arena,r,"arch","pale",c,yaw,Vector3(x+3.75,15,16),Vector3(3.1,5,1.4))
		for y in [26.5,32.0]:
			_window(arena,r,c,yaw,Vector3(x,y,9.0),1.8,3.8)
		# Лоджия верхнего яруса и её видимые балки.
		_p(arena,r,"box","dark",c,yaw,Vector3(x,23.2,15.2),Vector3(5.6,.3,1))
		_p(arena,r,"box","pale",c,yaw,Vector3(x,24.2,16),Vector3(.5,2,.5))
	_p(arena,r,"box","pale",c,yaw,Vector3(0,25.3,16),Vector3(84,.5,.7))
	for side in [-1.0,1.0]:
		var base := Vector3(side*38,0,0)
		_p(arena,r,"box","stone",c,yaw,base+Vector3(0,28,0),Vector3(15,55,23))
		for y in [8.0,30.0,48.0,56.0]:
			_p(arena,r,"box","pale",c,yaw,base+Vector3(0,y,0),Vector3(17,1.1,25))
		_p(arena,r,"roof","copper",c,yaw,base+Vector3(0,56,0),Vector3(21,17,28))
		for y in [17.0,26.0,38.0,47.0]:
			_window(arena,r,c,yaw,base+Vector3(0,y,11.8),2.6,5)
	# Центральный фронтон: силуэт большого морского здания вместо одинаковых домов.
	_p(arena,r,"box","pale",c,yaw,Vector3(0,40,5),Vector3(21,14,16))
	_p(arena,r,"roof","copper",c,yaw,Vector3(0,47,5),Vector3(27,13,21))
	_p(arena,r,"shaft","metal",c,yaw,Vector3(0,42.5,13.5),Vector3(4,.4,4),Vector3(PI*.5,0,0))
	_p(arena,r,"shaft","blue",c,yaw,Vector3(0,42.5,13.8),Vector3(3.3,.2,3.3),Vector3(PI*.5,0,0))


static func _observatory(arena: Node3D, r: Dictionary, c: Vector3, yaw: float) -> void:
	# Лунная обсерватория и основание великого маяка образуют единую левую массу.
	_p(arena,r,"box","stone",c,yaw,Vector3(0,3,-4),Vector3(70,8,48))
	_p(arena,r,"box","city",c,yaw,Vector3(0,16,-7),Vector3(62,25,33))
	_p(arena,r,"box","pale",c,yaw,Vector3(0,29,-6),Vector3(66,1.5,37))
	_p(arena,r,"shaft","pale",c,yaw,Vector3(3,28,-5),Vector3(24,7,24))
	_p(arena,r,"dome","copper",c,yaw,Vector3(3,31,-5),Vector3(24,20,24))
	_p(arena,r,"shaft","metal",c,yaw,Vector3(3,52,-5),Vector3(.35,5,.35))
	for i in 9:
		var x := (i-4)*7.0
		_p(arena,r,"box","pale",c,yaw,Vector3(x,13,13),Vector3(1.4,20,1.6))
		_p(arena,r,"arch","pale",c,yaw,Vector3(x+3.5,19,13),Vector3(2.8,5.7,1.5))
		_window(arena,r,c,yaw,Vector3(x,18,10),2.2,6.5)
	_p(arena,r,"box","pale",c,yaw,Vector3(0,6,15),Vector3(65,1,9))
	for i in 7:
		_p(arena,r,"box","stone",c,yaw,Vector3(0,3.7-i*.5,20+i*.8),Vector3(26,.6,1.6))
	_lighthouse(arena,r,c+Basis(Vector3.UP,yaw)*Vector3(-22,8,-3),1.50)
	# Купольные рёбра и меридианы видны сверху и связывают медную кровлю с темой луны.
	for i in 12:
		var a := TAU*i/12.0
		for j in 7:
			var t0 := j*PI*.5/7
			var t1 := (j+1)*PI*.5/7
			var p0 := c+Basis(Vector3.UP,yaw)*(Vector3(3,31,-5)+Vector3(cos(a)*24*cos(t0),20*sin(t0),sin(a)*24*cos(t0)))
			var p1 := c+Basis(Vector3.UP,yaw)*(Vector3(3,31,-5)+Vector3(cos(a)*24*cos(t1),20*sin(t1),sin(a)*24*cos(t1)))
			D.beam(arena,r.rod,r.metal,p0,p1,.16)


static func _bridge(arena: Node3D, r: Dictionary) -> void:
	# Большой арочный канал соединяет архитектурные берега и ведёт взгляд в город.
	var c := Vector3(0,12,-129)
	for side in [-1.0,1.0]:
		_p(arena,r,"box","stone",c,0,Vector3(side*29,9,0),Vector3(13,24,20))
		_p(arena,r,"box","pale",c,0,Vector3(side*29,21.3,0),Vector3(15,1.2,22))
	_p(arena,r,"arch","pale",c,0,Vector3(0,4,6),Vector3(22,16,8))
	# Пазухи над дугой заполнены камнем: окна дальних домов не видны сквозь мост.
	_p(arena,r,"spandrel","stone",c,0,Vector3(0,4,0),Vector3(22,16,20))
	_p(arena,r,"box","stone",c,0,Vector3(0,24,0),Vector3(71,7,20))
	_p(arena,r,"box","pale",c,0,Vector3(0,28,0),Vector3(73,.9,22))
	for i in 17:
		_p(arena,r,"box","pale",c,0,Vector3((i-8)*4.2,30,10.4),Vector3(.7,3.4,.8))
	_p(arena,r,"box","pale",c,0,Vector3(0,31.7,10.4),Vector3(73,.6,1.2))
	for side in [-1.0,1.0]:
		_lantern(arena,r,c+Vector3(side*29,29,6),1.1)
		# Два морских обелиска с медными венцами закрепляют большой пролёт.
		_p(arena,r,"box","stone",c,0,Vector3(side*34,39,-3),Vector3(7,23,9))
		_p(arena,r,"roof","copper",c,0,Vector3(side*34,51,-3),Vector3(10,10,12))
		_window(arena,r,c,0,Vector3(side*34,43,1.8),2,7)


static func _window(arena: Node3D, r: Dictionary, c: Vector3, yaw: float, p: Vector3, width: float, height: float) -> void:
	_p(arena,r,"box","dark",c,yaw,p,Vector3(width+1,height+1,.65))
	_p(arena,r,"box","warm",c,yaw,p+Vector3(0,0,.36),Vector3(width,height,.14))
	_p(arena,r,"box","metal",c,yaw,p+Vector3(0,0,.47),Vector3(.16,height+.1,.16))
	_p(arena,r,"box","metal",c,yaw,p+Vector3(0,0,.47),Vector3(width+.1,.18,.16))
	_p(arena,r,"box","pale",c,yaw,p+Vector3(0,-height*.5-.5,.3),Vector3(width+1.6,.4,1.3))


static func _lighthouse(arena: Node3D, r: Dictionary, p: Vector3, s: float) -> void:
	for part in [[2.0,4.0,10.5],[10.0,13.0,7.3],[28.0,25.0,5.9],[43.0,7.0,5.0]]:
		_p(arena,r,"shaft","stone",p,0,Vector3(0,part[0],0)*s,Vector3(part[2],part[1],part[2])*s)
	for y in [4.3,16.2,36.0,47.0]:
		_p(arena,r,"shaft","pale",p,0,Vector3(0,y,0)*s,Vector3(7.2,1.1,7.2)*s)
	_p(arena,r,"shaft","metal",p,0,Vector3(0,49,0)*s,Vector3(9,.8,9)*s)
	_p(arena,r,"shaft","blue",p,0,Vector3(0,54,0)*s,Vector3(4.5,7,4.5)*s)
	for i in 12:
		var a := TAU*i/12.0
		_p(arena,r,"rod","metal",p,0,Vector3(cos(a)*4.8,54,sin(a)*4.8)*s,Vector3(.16,8,.16)*s)
		_p(arena,r,"rod","metal",p,0,Vector3(cos(a)*8.2,50.5,sin(a)*8.2)*s,Vector3(.12,2,.12)*s)
	_p(arena,r,"shaft","metal",p,0,Vector3(0,51.5,0)*s,Vector3(8.5,.2,8.5)*s)
	_p(arena,r,"dome","copper",p,0,Vector3(0,58,0)*s,Vector3(7.5,5.5,7.5)*s)
	_p(arena,r,"rod","metal",p,0,Vector3(0,65,0)*s,Vector3(.3,5,.3)*s)
	for y in [20.0,29.0,39.0]:
		_window(arena,r,p,0,Vector3(0,y,5.9)*s,1.3*s,3*s)


static func _lantern(arena: Node3D, r: Dictionary, p: Vector3, s: float, target: Vector3 = Vector3.ZERO, quality: int = -1) -> void:
	_p(arena,r,"shaft","stone",p,0,Vector3(0,.6,0)*s,Vector3(1.2,1.2,1.2)*s)
	_p(arena,r,"rod","metal",p,0,Vector3(0,4,0)*s,Vector3(.22,7,.22)*s)
	_p(arena,r,"shaft","metal",p,0,Vector3(0,7.5,0)*s,Vector3(1.35,.35,1.35)*s)
	_p(arena,r,"shaft","warm",p,0,Vector3(0,LANTERN_GLASS_HEIGHT,0)*s,Vector3(.77,1.85,.77)*s)
	for i in 4:
		var a := TAU*(i+.5)/4
		_p(arena,r,"rod","metal",p,0,Vector3(cos(a),8.6,sin(a))*s,Vector3(.09,2.2,.09)*s)
	_p(arena,r,"roof","copper",p,0,Vector3(0,9.7,0)*s,Vector3(2.6,1.5,2.6)*s)
	if quality >= 0:
		var glass := p + Vector3.UP * LANTERN_GLASS_HEIGHT * s
		var light := SpotLight3D.new()
		light.name = "HarborLantern"
		arena._decor.add_child(light, true)
		light.position = glass + (target - glass).normalized() * .48 * s
		light.look_at(target)
		light.light_color = LANTERN_LIGHT
		var across_square := p.y < 2.0 and target.y > 2.0
		light.light_energy = 43.0 if across_square else (14.0 if p.y < 2.0 else 31.0)
		light.light_specular = .23
		light.spot_range = glass.distance_to(target) + (32.0 if across_square else 14.0)
		light.spot_angle = 32 if across_square else 49
		light.spot_angle_attenuation = 1.9
		light.spot_attenuation = .93 if across_square else 1.15
		light.light_volumetric_fog_energy = 0.0
		light.set_meta("min_quality", quality)
		light.set_meta("source_glass", glass)
		light.set_meta("light_target", target)
		arena._harbor_lights.append(light)


static func _ship(arena: Node3D, r: Dictionary, c: Vector3, yaw: float, s: float) -> void:
	_p(arena,r,"hull","wood",c,yaw,Vector3.ZERO,Vector3(1.5,1.8,2.1)*s)
	for i in 29:
		var z := (i-14)*1.35
		var width := 10.1*sqrt(maxf(.05,1.0-pow(z/21.0,2)))
		_p(arena,r,"box","plank",c,yaw,Vector3(0,3.5,z)*s,Vector3(width,.25,1.28)*s)
	for side in [-1.0,1.0]:
		for i in 12:
			var z0 := -18+i*3
			var z1 := z0+3
			var x0: float = side*5.1*sqrt(maxf(.05,1.0-pow(z0/21.0,2)))
			var x1: float = side*5.1*sqrt(maxf(.05,1.0-pow(z1/21.0,2)))
			D.beam(arena,r.rod,r.metal,c+Basis(Vector3.UP,yaw)*Vector3(x0,4.9,z0)*s,c+Basis(Vector3.UP,yaw)*Vector3(x1,4.9,z1)*s,.13*s)
			_p(arena,r,"rod","wood",c,yaw,Vector3(x0,4.1,z0)*s,Vector3(.14,1.8,.14)*s)
	_p(arena,r,"box","wood",c,yaw,Vector3(0,5.7,12)*s,Vector3(7,4.2,8)*s)
	_p(arena,r,"roof","copper",c,yaw,Vector3(0,8,12)*s,Vector3(8.6,2.3,10)*s)
	for dx in [-2.4,0.0,2.4]:
		_p(arena,r,"box","warm",c,yaw,Vector3(dx,6,16.1)*s,Vector3(1.2,1.4,.1)*s)
	for spec in [[-7.0,30.0,1.0],[6.0,25.0,.8]]:
		var z: float = spec[0]
		var h: float = spec[1]
		var sail_scale: float = spec[2]
		_p(arena,r,"rod","plank",c,yaw,Vector3(0,4+h*.5,z)*s,Vector3(.3,h,.3)*s)
		for dy in [0.0,-11.0]:
			_p(arena,r,"rod","wood",c,yaw,Vector3(0,h+dy,z)*s,Vector3(.2,20*sail_scale,.2)*s,Vector3(0,0,PI*.5))
			_p(arena,r,"sail","cloth",c,yaw,Vector3(0,h+dy-9,z)*s,Vector3(sail_scale,.85,1)*s)
		for side in [-1.0,1.0]:
			var basis := Basis(Vector3.UP,yaw)
			D.beam(arena,r.rod,r.rope,c+basis*Vector3(0,h+3,z)*s,c+basis*Vector3(side*4.8,4,z+7)*s,.055*s)
			D.beam(arena,r.rod,r.rope,c+basis*Vector3(0,h+3,z)*s,c+basis*Vector3(0,4,-23)*s,.045*s)
	# Носовой бушприт и канаты к причалу связывают корабль с реальным портом.
	D.beam(arena,r.rod,r.plank,c+Basis(Vector3.UP,yaw)*Vector3(0,3,-18)*s,c+Basis(Vector3.UP,yaw)*Vector3(0,7,-30)*s,.19*s)
	for z in [-14.0,13.0]:
		D.beam(arena,r.rod,r.rope,c+Basis(Vector3.UP,yaw)*Vector3(-4,4,z)*s,c+Basis(Vector3.UP,yaw)*Vector3(-17,1,z+7)*s,.07*s)


static func _islands(arena: Node3D, r: Dictionary) -> void:
	# Каменная земля с разным силуэтом замыкает горизонт бухты на всех ракурсах.
	for i in 27:
		var a := TAU*(i+.15)/27
		var radius := 265.0+float(i%4)*26
		var c := Vector3(cos(a)*radius,-3,sin(a)*radius)
		var height := 20.0+float((i*13)%7)*6
		_p(arena,r,"rock","cliff",c,a,Vector3.ZERO,Vector3(57+float(i%3)*12,height,40))
		_p(arena,r,"rock","cliff_light",c,a+.25,Vector3(9,7,-4),Vector3(34,height*.75,27))
	# Ближние валуны у переднего волнолома обрывают бесконечную плоскость воды.
	for i in 9:
		var a := .28+i*.33
		var c := Vector3(cos(a)*161,-.8,sin(a)*161)
		_p(arena,r,"rock","cliff",c,a,Vector3.ZERO,Vector3(24,8+float(i%3)*3,20))


static func _cliff_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """shader_type spatial;
varying vec3 wp;
uniform vec4 rock_color : source_color;
void vertex() { wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 float course=wp.y*.31+wp.x*.026+wp.z*.018;
 float q=fract(course);
 float seam=1.0-smoothstep(.018,.055,min(q,1.0-q));
 float layer=fract(sin(floor(course)*19.73)*417.13);
 float chip=fract(sin(dot(floor(wp.xz*.4),vec2(21.9,13.7)))*137.1);
 ALBEDO=rock_color.rgb*(.84+layer*.24+chip*.055-seam*.13);
 ROUGHNESS=.98; SPECULAR=.12;
}
"""
	mat.set_shader_parameter("rock_color",color)
	return mat


static func _masonry(light: Color, dark: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """shader_type spatial;
varying vec3 wp;
varying vec3 wn;
uniform vec4 stone_light : source_color;
uniform vec4 stone_dark : source_color;
uniform bool side_windows = false;
varying vec3 local_p;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void vertex() { wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; wn=normalize(MODEL_NORMAL_MATRIX*NORMAL); local_p=VERTEX; }
void fragment() {
 vec2 p=abs(wn.z)>abs(wn.x)?wp.xy:wp.zy;
 if(abs(wn.y)>.7) p=wp.xz;
 float row=floor(p.y/1.7); vec2 grid=vec2(p.x/4.8+mod(row,2.0)*.5,p.y/1.7);
 vec2 cell=floor(grid); vec2 q=fract(grid);
 float joint=1.0-smoothstep(.025,.045,min(min(q.x,1.0-q.x),min(q.y,1.0-q.y)));
 float grain=hash(floor(p*11.0))*.07;
 float block=hash(cell)*.28+.48;
 vec3 base=mix(stone_dark.rgb,stone_light.rgb,block+grain);
 float wet=1.0-smoothstep(-.5,5.0,wp.y);
 ALBEDO=mix(base,stone_dark.rgb,joint*.45+wet*.27);
 // Боковые фасады не остаются глухими коробками в косом ракурсе.
 // Граница стены и кровли задаётся геометрией; рисунок внутри неё резкий.
 if(side_windows && abs(wn.x)>.9 && abs(local_p.y)<.43 && abs(local_p.z)<.42) {
  vec2 cell=vec2(wp.z/5.8,wp.y/5.8); vec2 q=fract(cell);
  float inset=step(.28,q.x)*step(q.x,.72)*step(.23,q.y)*step(q.y,.82);
  float pane=step(.35,q.x)*step(q.x,.65)*step(.30,q.y)*step(q.y,.74);
  float crossbar=step(abs(q.x-.5),.018)+step(abs(q.y-.52),.018);
  float lit=step(.28,hash(floor(cell)))*pane*(1.0-clamp(crossbar,0.0,1.0));
  ALBEDO=mix(ALBEDO,vec3(.023,.042,.05),inset);
  ALBEDO=mix(ALBEDO,vec3(.32,.16,.065),lit);
  EMISSION=vec3(.13,.048,.014)*lit;
 }
 ROUGHNESS=.92; SPECULAR=.22;
}
"""
	mat.set_shader_parameter("stone_light",light)
	mat.set_shader_parameter("stone_dark",dark)
	return mat


static func _roof_material(color: Color, copper: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """shader_type spatial;
varying vec3 wp;
uniform vec4 roof_color : source_color;
uniform float copper;
void vertex() { wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 float row=floor(wp.y/.72);
 vec2 q=fract(vec2(wp.x*.8+mod(row,2.0)*.5,wp.y/.72));
 float seam=1.0-smoothstep(.025,.065,min(q.x,min(q.y,1.0-q.y)));
 float age=sin(wp.x*.39+wp.z*.27)*sin(wp.y*.6+wp.z*.15)*.055;
 ALBEDO=roof_color.rgb*(.92+age-seam*.22);
 ROUGHNESS=mix(.88,.69,copper); METALLIC=copper*.28; SPECULAR=.22;
}
"""
	mat.set_shader_parameter("roof_color",color)
	mat.set_shader_parameter("copper",1.0 if copper else 0.0)
	return mat


static func _sea_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec3 moon_direction;
uniform float square_lantern_radius = 63.2;
uniform float square_lantern_height = 7.84;
uniform float square_lantern_count = 14.0;
uniform float quay_lantern_radius;
uniform float quay_lantern_height;
varying vec3 wp;
void vertex() { wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 float t=TIME*.39;
 float swell=sin(wp.x*.15+wp.z*.09-t);
 float ripple=sin(wp.x*.43+sin(wp.z*.17-t)*1.7+t)*sin(wp.z*.59+sin(wp.x*.21+t));
 float far=smoothstep(80.0,430.0,length(wp.xz));
 vec3 water=mix(vec3(.012,.037,.052),vec3(.009,.020,.039),far);
 float radius=length(wp.xz);
 vec3 wave = normalize(vec3(ripple*.049+swell*.037,1.0,cos(wp.z*.45+t)*.053));
 vec3 sight = normalize(CAMERA_POSITION_WORLD - wp);
 vec3 reflected = reflect(-sight, wave);
 // Short broken paths line up with the two rows of emissive glass even without SSR.
 vec2 reflected_square = wp.xz + reflected.xz * (square_lantern_height / max(reflected.y, .11));
 float square_angle=atan(reflected_square.y,reflected_square.x);
 float square_light=pow(max(0.0,cos(square_angle*square_lantern_count-PI)),18.0)
   * exp(-abs(length(reflected_square)-square_lantern_radius)*.16);
 vec2 reflected_quay = wp.xz + reflected.xz * (quay_lantern_height / max(reflected.y, .11));
 float angle=atan(reflected_quay.x,-reflected_quay.y);
 float quay_light=pow(max(0.0,cos((angle+1.43)/.429*TAU)),25.0);
 quay_light*=exp(-abs(length(reflected_quay)-quay_lantern_radius)*.12)*(1.0-smoothstep(1.35,1.55,abs(angle)));
 float broken=mix(.18,1.0,smoothstep(-.02,.65,ripple))*(quay_light + square_light*.83);
 // Узкая прерывистая кромка у камня вместо белого контура всей бухты.
 float shore=exp(-abs(radius-100.2-swell*.10)*5.0);
 shore*=1.0-smoothstep(1.36,1.53,abs(atan(wp.x,-wp.z)));
 float foam=shore*smoothstep(-.2,.8,ripple)*.35;
 float moon = pow(max(dot(reflected,moon_direction),0.0),116.0) * (.28 + .72 * smoothstep(.03,.82,ripple));
 ALBEDO=water+vec3(.003,.005,.006)*(ripple+swell*.5);
 ALBEDO+=vec3(.045,.024,.010)*broken+vec3(.06,.11,.12)*foam;
 EMISSION=vec3(.29,.113,.028)*broken+vec3(.058,.096,.145)*moon;
 NORMAL=(VIEW_MATRIX*vec4(wave,0.0)).xyz;
 ROUGHNESS=mix(.53,.70,.5+.5*ripple); SPECULAR=.23;
}
"""
	mat.set_shader_parameter("moon_direction", Locations.HARBOR_MOON.normalized())
	mat.set_shader_parameter("square_lantern_count", float(SQUARE_LANTERN_COUNT))
	mat.set_shader_parameter("square_lantern_height", LANTERN_GLASS_HEIGHT * SQUARE_LANTERN_SCALE - .075)
	mat.set_shader_parameter("square_lantern_radius", SQUARE_LANTERN_RADIUS)
	mat.set_shader_parameter("quay_lantern_height", QUAY_LANTERN_FOOT + LANTERN_GLASS_HEIGHT * QUAY_LANTERN_SCALE - .075)
	mat.set_shader_parameter("quay_lantern_radius", QUAY_LANTERN_RADIUS)
	return mat


static func _sea() -> ArrayMesh:
	# Внешние поверхности по часовой стрелке — лицевая сторона в Godot.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for limits in [[70.0,150.0],[150.0,400.0],[400.0,1000.0],[1000.0,2900.0]]:
		for i in 192:
			var a := TAU*i/192
			var b := TAU*(i+1)/192
			D._quad(st,Vector3(cos(a)*limits[0],0,sin(a)*limits[0]),Vector3(cos(a)*limits[1],0,sin(a)*limits[1]),Vector3(cos(b)*limits[1],0,sin(b)*limits[1]),Vector3(cos(b)*limits[0],0,sin(b)*limits[0]))
	st.generate_normals()
	return st.commit()


static func _spandrel() -> ArrayMesh:
	# Замкнутое заполнение между внешней дугой архивольта и прямым настилом.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in 20:
		var a := PI*i/20
		var b := PI*(i+1)/20
		var p := Vector2(cos(a),sin(a))*1.20
		var q := Vector2(cos(b),sin(b))*1.20
		D._quad(st,Vector3(p.x,p.y,.5),Vector3(q.x,q.y,.5),Vector3(q.x,1.30,.5),Vector3(p.x,1.30,.5))
		D._quad(st,Vector3(q.x,q.y,-.5),Vector3(p.x,p.y,-.5),Vector3(p.x,1.30,-.5),Vector3(q.x,1.30,-.5))
		D._quad(st,Vector3(p.x,p.y,-.5),Vector3(q.x,q.y,-.5),Vector3(q.x,q.y,.5),Vector3(p.x,p.y,.5))
		D._quad(st,Vector3(p.x,1.30,.5),Vector3(q.x,1.30,.5),Vector3(q.x,1.30,-.5),Vector3(p.x,1.30,-.5))
	for side in [-1.0,1.0]:
		var x: float = side*1.20
		if side>0:
			D._quad(st,Vector3(x,0,.5),Vector3(x,1.30,.5),Vector3(x,1.30,-.5),Vector3(x,0,-.5))
		else:
			D._quad(st,Vector3(x,0,-.5),Vector3(x,1.30,-.5),Vector3(x,1.30,.5),Vector3(x,0,.5))
	st.generate_normals()
	return st.commit()


static func _roof() -> ArrayMesh:
	# Плоские нормали сохраняют изломы четырёх скатов; снизу кровля замкнута.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var a := Vector3(-.5,0,-.5)
	var b := Vector3(.5,0,-.5)
	var c := Vector3(.5,0,.5)
	var d := Vector3(-.5,0,.5)
	var l := Vector3(-.31,1,0)
	var rr := Vector3(.31,1,0)
	D._quad(st,a,b,rr,l)
	D._quad(st,d,l,rr,c)
	for v in [a,l,d,b,c,rr]: st.add_vertex(v)
	D._quad(st,a,d,c,b)
	st.generate_normals()
	return st.commit()


static func _gable() -> ArrayMesh:
	# Замкнутая двускатная крыша: щипец обращён к воде (+Z).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var a := Vector3(-.5,0,-.5)
	var b := Vector3(.5,0,-.5)
	var c := Vector3(.5,0,.5)
	var d := Vector3(-.5,0,.5)
	var l := Vector3(0,1,-.5)
	var rr := Vector3(0,1,.5)
	D._quad(st,a,l,rr,d)
	D._quad(st,b,c,rr,l)
	for v in [a,b,l,d,rr,c]: st.add_vertex(v)
	D._quad(st,a,d,c,b)
	st.generate_normals()
	return st.commit()


static func _dome() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 12:
		for i in 48:
			var a := TAU*i/48
			var b := TAU*(i+1)/48
			var t := j*PI*.5/12
			var u := (j+1)*PI*.5/12
			D._quad(st,Vector3(cos(a)*cos(t),sin(t),sin(a)*cos(t)),Vector3(cos(b)*cos(t),sin(t),sin(b)*cos(t)),Vector3(cos(b)*cos(u),sin(u),sin(b)*cos(u)),Vector3(cos(a)*cos(u),sin(u),sin(a)*cos(u)))
	st.set_smooth_group(-1)
	for i in 48:
		var a := TAU*i/48
		var b := TAU*(i+1)/48
		for v in [Vector3(cos(b),0,sin(b)),Vector3(cos(a),0,sin(a)),Vector3.ZERO]: st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func _rock() -> ArrayMesh:
	# Замкнутый уступчатый остров: береговая полка, наклонные пласты и
	# неровный гребень вместо одного повторённого конуса. Индекс шва замкнут.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rings: Array = []
	for level in 5:
		var ring: Array[Vector3] = []
		for i in 14:
			var a := TAU*i/14.0
			var ridge := sin(i*2.31)*.055+cos(i*1.17)*.035
			var radius: float = [.56,.53,.38,.27,.105][level]
			var y: float = [-.15,.025,.20,.47,.68][level]
			var irregular := 1.0+sin(i*2.13+level*.8)*.13
			var shift := Vector3(level*.035,0,-level*.018)
			ring.append(Vector3(cos(a)*radius*irregular,y+ridge*float(level)*.5,sin(a)*radius*irregular)+shift)
		rings.append(ring)
	for level in 4:
		for i in 14:
			var j := (i+1)%14
			D._quad(st,rings[level][i],rings[level][j],rings[level+1][j],rings[level+1][i])
	for i in 14:
		var j := (i+1)%14
		for v in [rings[4][i],rings[4][j],Vector3(.14,.76,-.07)]: st.add_vertex(v)
		for v in [rings[0][j],rings[0][i],Vector3(0,-.15,0)]: st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func _sail() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in 6:
		for x in 12:
			var vertices: Array[Vector3] = []
			for point in [Vector2(x,y),Vector2(x+1,y),Vector2(x+1,y+1),Vector2(x,y+1)]:
				var xx: float = point.x/12.0
				var yy: float = point.y/6.0
				vertices.append(Vector3((xx-.5)*(18.0-yy*2),yy*9,sin(xx*PI)*sin(yy*PI)*2.5))
			D._quad(st,vertices[0],vertices[1],vertices[2],vertices[3])
	st.generate_normals()
	return st.commit()
