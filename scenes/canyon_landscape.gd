extends RefCounted
## Вырубленный в живом каньоне амфитеатр: связанные скалы, галереи и дорога в ущелье.
const D := preload("res://scenes/landscape_detail.gd")

static func build(arena: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2007
	var pale := _masonry(Color(.57,.48,.33))
	var sand := _masonry(Color(.29,.145,.075))
	var dark := D.material(Color(.14,.075,.043),.96)
	var gold := D.material(Color(.50,.29,.09),.55,.48)
	var inset := D.material(Color(.12,.12,.115),.9)
	var turquoise := D.material(Color(.075,.255,.225),.88,.05)
	turquoise.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glow: Material = arena._glow_mat(Color(1.0,.49,.13),.8)
	var cliff := ShaderMaterial.new()
	cliff.shader = Shader.new()
	cliff.shader.code = """
shader_type spatial;
render_mode cull_disabled;
varying vec3 world;
uniform vec3 stone_tint=vec3(1.0);
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	float bend = sin(world.x*.035+world.z*.026)*2.8 + sin(world.z*.071)*.7;
	float strata=world.y*.20+bend*.6;
	float band=floor(strata*1.2);
	float layer = sin(band*.59);
	float width=max(fwidth(strata)*.7,.025);
	float thin = 1.0-smoothstep(.022,.022+width,abs(fract(strata*1.2)-.5));
	float grain = (hash(floor(world*3.2))-.5)*(1.0-smoothstep(.18,.7,length(fwidth(world))));
	float weather = sin(world.x*.11+world.z*.083)*sin(world.z*.051-world.x*.03);
	float drainage = smoothstep(.72,.82,sin(world.x*.13+world.z*.19+sin(world.y*.06)*.55));
	float mineral = smoothstep(.84,.98,sin(world.y*.14+bend*.28))*smoothstep(-.2,.7,weather);
	vec3 sandstone = mix(vec3(.235,.125,.080),vec3(.47,.31,.19),layer*.5+.5);
	sandstone = mix(sandstone,vec3(.29,.31,.255),mineral*.43);
	ALBEDO = sandstone * stone_tint * (1.0-thin*.17+grain*.07+weather*.10-drainage*.14);
	ROUGHNESS = .98;
	SPECULAR = .16;
}
"""
	var block := BoxMesh.new()
	var rod := D.rod(10)
	var mesa := CylinderMesh.new()
	mesa.top_radius = .80
	mesa.bottom_radius = 1.0
	mesa.height = 1
	mesa.radial_segments = 9
	# Два непрерывных борта ущелья. Между ними настоящий выход на север;
	# радиус и высота меняются независимо, поэтому скалы не образуют частокол.
	arena._mi(_wall(-1.26,1.27,139,96,0),cliff,Vector3.ZERO)
	arena._mi(_wall(1.43,4.41,151,117,2.2),cliff,Vector3.ZERO)
	# Высокие контрфорсы эрозии вырастают из общего массива. Разные сечения,
	# независимые высоты и наклон дают вертикальные разломы поверх пластов.
	var buttresses := [Vector4(3.47,163,98,43),Vector4(3.91,160,116,38),Vector4(4.27,169,87,47),Vector4(-1.04,154,106,37),Vector4(-.57,158,78,46),Vector4(.20,159,112,40),Vector4(2.05,165,94,44)]
	for i in buttresses.size():
		var v: Vector4 = buttresses[i]
		arena._static(_outcrop(i+3),cliff,Vector3(cos(v.x)*v.y,0,sin(v.x)*v.y),Vector3(v.w,v.z,v.w*.90),Vector3(0,-v.x,0))
	var far_rock := cliff.duplicate() as ShaderMaterial
	far_rock.set_shader_parameter("stone_tint",Vector3(.74,.79,.84))
	var ridges: Array[ArrayMesh] = []
	for i in 5:
		var ridge := _outcrop(51+i)
		ridge.set_meta("canyon_far_ridge",true)
		ridges.append(ridge)
	# Дальний горизонт состоит из перекрывающихся массивов с седловинами.
	# У него нет кольцевой верхней полки, превращавшей просвет в плоский навес.
	for belt in 2:
		for i in 22:
			var a := -1.28+i*.267
			var radius := 308.0+belt*155+sin(i*2.7)*19
			var h := 65.0+float((i*7+belt*3)%6)*13
			var center := Vector3(cos(a)*radius,-3,sin(a)*radius-125-belt*85)
			var distance := Vector2(center.x,center.z).length()
			if distance < 360:
				center.x *= 360/distance
				center.z *= 360/distance
			arena._static(ridges[(i+belt*2)%5],far_rock,center,Vector3(78+i%3*17,h,68+i%4*13),Vector3(0,a*.6+belt*.4,0))
	arena._static(ridges[3],far_rock,Vector3(-30,-4,-368),Vector3(69,73,82),Vector3(0,.6,0))
	# Верхняя прогулочная терраса соединяет лестницы, аркаду и ворота на одной отметке.
	arena._mi(_terrace(),sand,Vector3.ZERO)
	# Низкое связующее основание и россыпь у стен, не заходящие на круг поля.
	for i in 48:
		var a := TAU*i/48.0
		if sin(a)<-.94: continue
		var p := Vector3(cos(a)*126,0,sin(a)*126)
		arena._static(mesa,cliff,p+Vector3(0,3,0),Vector3(19+rng.randf()*11,6+rng.randf()*10,17+rng.randf()*9),Vector3(.04,a,.05))
	# Дорога остаётся видна через проём, затем теряется в дальней седловине.
	for step in 26:
		var turn := maxf(0.0,step-13.0)*.70
		D.piece(arena,block,pale,Vector3.ZERO,0,Vector3(turn,8.15+step*.32,-119-step*5.1),Vector3(19,.5,5.2))
		for side in [-1.0,1.0]:
			D.piece(arena,block,sand,Vector3.ZERO,0,Vector3(turn+side*11.0,9.3+step*.32,-119-step*5.1),Vector3(1.3,2.9,5.2))
	_distant_pass(arena,block,rod,cliff,pale,sand,gold,turquoise)
	# Галереи встроены в оба борта: тёмные углубления, арки и общий карниз.
	_carved_wing(arena,Vector3(-99,8,-71),.86,block,rod,pale,sand,dark,gold,glow)
	_carved_wing(arena,Vector3(100,8,-68),-.90,block,rod,pale,sand,dark,gold,glow)
	# Ступенчатые кольца кладки. Четыре разрыва оставляют видимые лестничные проходы.
	for tier in 4:
		var radius := 71.5+tier*7.0
		var height := 1.5+tier*2.1
		for i in 96:
			if i%24 < 2 or i%24 > 21: continue
			var a := TAU*(i+.5)/96.0
			var center := Vector3(cos(a)*radius,0,sin(a)*radius)
			var yaw := -a-PI*.5
			var width := TAU*radius/96.0+.10
			D.piece(arena,block,sand,center,yaw,Vector3(0,height*.5,0),Vector3(width,height,7.1))
			D.piece(arena,block,pale,center,yaw,Vector3(0,height+.18,.18),Vector3(width+.1,.38,7.3))
			D.piece(arena,block,dark,center,yaw,Vector3(0,height-.35,3.65),Vector3(width,.20,.09))
	for aisle in 4:
		var a := TAU*aisle/4.0
		var center := Vector3(cos(a)*65,0,sin(a)*65)
		var yaw := -a-PI*.5
		for step in 15:
			D.piece(arena,block,pale,center,yaw,Vector3(0,.24+step*.31,-step*2.15),Vector3(9.5,.48+step*.62,2.2))
		# Невысокие боковые стенки с янтарными вставками.
		for side in [-1.0,1.0]:
			for k in 4:
				D.piece(arena,block,sand,center,yaw,Vector3(side*5.5,1.5+k*1.2,-k*7.0),Vector3(1.1,3+k*2.2,6.7))
	# Верхняя галерея с парными устоями и обработанными капителями.
	var gallery_arch := D.arch(7.1,1.0,4.4)
	var gallery_banner := _banner(3.8,10.0)
	for i in 28:
		var a := TAU*(i+.5)/28.0
		if absf(sin(a))>.98 or absf(cos(a))>.98: continue
		var p := Vector3(cos(a)*103,0,sin(a)*103)
		var yaw := -a-PI*.5
		D.piece(arena,block,sand,p,yaw,Vector3(0,3,0),Vector3(22,6,10))
		D.piece(arena,block,pale,p,yaw,Vector3(0,6.5,0),Vector3(22,1,11))
		D.piece(arena,gallery_arch,pale,p,yaw,Vector3(0,19,0),Vector3.ONE)
		for x in [-8.1,8.1]:
			D.piece(arena,rod,pale,p,yaw,Vector3(x,16.8,0),Vector3(.95,20,.95))
			D.piece(arena,block,gold,p,yaw,Vector3(x,26.4,0),Vector3(2.9,.7,3.3))
		for y in [8.4,25.8,27.1]:
			D.piece(arena,block,gold if y<27 else pale,p,yaw,Vector3(0,y,-3.5),Vector3(22,.5 if y<27 else 1.9,3.6))
		D.piece(arena,block,sand,p,yaw,Vector3(0,28.5,0),Vector3(22.3,1.2,10.8))
		D.piece(arena,block,pale,p,yaw,Vector3(0,29.4,0),Vector3(22.5,.55,11.0))
		# Мозаичный фриз идёт по несущему карнизу; полотна отмечают отдельные секции.
		for x in [-6.0,0.0,6.0]:
			D.piece(arena,block,turquoise,p,yaw,Vector3(x,27.6,5.46),Vector3(2.1,1.0,.18))
		if i%4 == 1:
			D.piece(arena,gallery_banner,turquoise,p,yaw,Vector3(0,25.5,4.5),Vector3.ONE)
			D.piece(arena,block,gold,p,yaw,Vector3(0,20.5,5.2),Vector3(1.7,1.7,.18),Vector3(0,0,PI*.25))
			D.piece(arena,rod,gold,p,yaw,Vector3(0,25.6,4.6),Vector3(.15,5,.15),Vector3(0,0,PI*.5))
	# Главные ворота: настоящий открытый свод, врезанные панели, ступени и реликвии.
	var gateway := Vector3(0,0,-116)
	var arch := D.arch(15,3.0,7)
	D.piece(arena,arch,pale,gateway,0,Vector3(0,20,0),Vector3.ONE)
	var trim_arch := D.arch(15,.38,7.3)
	D.piece(arena,trim_arch,gold,gateway,0,Vector3(0,20,0),Vector3.ONE)
	for side in [-1.0,1.0]:
		var p := gateway+Vector3(side*21,0,0)
		D.piece(arena,block,sand,p,0,Vector3(0,20,0),Vector3(12,40,12))
		for y in [1.5,6.0,30.0,37.0,40.0]:
			D.piece(arena,block,pale,p,0,Vector3(0,y,.3),Vector3(14,1.1,13.0))
		D.piece(arena,block,inset,p,0,Vector3(0,20,6.05),Vector3(6.2,18,.2))
		for y in [14.0,20.0,26.0]:
			D.piece(arena,block,gold,p,0,Vector3(0,y,6.3),Vector3(3.1,3.1,.24),Vector3(0,0,PI*.25))
		for x in [-4.6,4.6]:
			D.piece(arena,rod,pale,p,0,Vector3(x,19.0,6.4),Vector3(.45,25,.45))
		D.piece(arena,block,glow,p,0,Vector3(0,35,6.8),Vector3(3.8,.35,.4))
		D.piece(arena,block,turquoise,p,0,Vector3(0,7,6.10),Vector3(6.2,1.1,.19))
	# Шесть индивидуальных резных стел на внешней кромке поля.
	for i in 6:
		var a := TAU*(i+.5)/6.0
		var p := Vector3(cos(a)*65.5,0,sin(a)*65.5)
		var yaw := -a-PI*.5
		for step in 3:
			D.piece(arena,block,pale,p,yaw,Vector3(0,.3+step*.5,0),Vector3(6-step*.7,.6,4.2-step*.45))
		D.piece(arena,block,sand,p,yaw,Vector3(0,5.5,0),Vector3(3.7,8,2.7))
		D.piece(arena,block,dark,p,yaw,Vector3(0,6,1.40),Vector3(2.6,4.5,.12))
		D.piece(arena,block,gold,p,yaw,Vector3(0,10,0),Vector3(4.8,.8,3.5))
		var icon := Sprite3D.new()
		icon.texture = preload("res://scenes/element_icon.gd").glyph(i)
		icon.modulate = Color(.93,.68,.35)
		icon.pixel_size = .011
		icon.position = p+Basis(Vector3.UP,yaw)*Vector3(0,6,1.52)
		icon.rotation.y = yaw
		arena._decor.add_child(icon)
		# Небольшие светящиеся минералы в металлической оправе.
		var gem := SphereMesh.new()
		gem.radius = .8
		gem.height = 2.1
		gem.radial_segments = 6
		gem.rings = 2
		D.piece(arena,gem,glow,p,yaw,Vector3(0,11.5,0),Vector3.ONE)
	D.ring(arena,gold,61.8,.035,.12)
	D.ring(arena,pale,63.0,.04,.18)
	arena._decor.set_meta("detailed_location",1)
	arena._decor.set_meta("continuous_canyon",true)
	preload("res://scenes/landscape_atmosphere.gd").dust(arena)

## Общее тело уступов с замкнутой верхней полкой: не набор независимых цилиндров.
static func _wall(start: float, end: float, radius: float, height: float, phase: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rows := [Vector2(1.0,0),Vector2(.98,.10),Vector2(1.08,.14),Vector2(1.10,.35),Vector2(1.02,.39),Vector2(1.14,.60),Vector2(1.22,.63),Vector2(1.13,.86),Vector2(1.34,1),Vector2(1.65,1)]
	var segments := 72
	for i in segments:
		var ta := float(i)/segments
		var tb := float(i+1)/segments
		var a := lerpf(start,end,ta)
		var b := lerpf(start,end,tb)
		var ha := height*(.42+.58*smoothstep(0,.12,minf(ta,1-ta)))
		var hb := height*(.42+.58*smoothstep(0,.12,minf(tb,1-tb)))
		for j in rows.size()-1:
			var p := _rock_point(a,rows[j],radius,ha,phase)
			var q := _rock_point(b,rows[j],radius,hb,phase)
			var r := _rock_point(b,rows[j+1],radius,hb,phase)
			var s := _rock_point(a,rows[j+1],radius,ha,phase)
			D._quad(st,p,s,r,q)
		# Наружная спина и дно замыкают скалу, включая вид через боковой проход.
		var outer_a := _rock_point(a,rows.back(),radius,ha,phase)
		var outer_b := _rock_point(b,rows.back(),radius,hb,phase)
		var ground_a := Vector3(outer_a.x,-1.5,outer_a.z)
		var ground_b := Vector3(outer_b.x,-1.5,outer_b.z)
		D._quad(st,outer_a,ground_a,ground_b,outer_b)
		D._quad(st,ground_a,_rock_point(a,rows[0],radius,ha,phase),_rock_point(b,rows[0],radius,hb,phase),ground_b)
	# Закрытые торцы уступов: верхняя полка не висит в воздухе у просвета.
	for a in [start,end]:
		var edge: Array[Vector3] = []
		for row in rows: edge.append(_rock_point(a,row,radius,height*.42,phase))
		var outer: Vector3 = edge.back()
		edge.append(Vector3(outer.x,-1.5,outer.z))
		var center := Vector3.ZERO
		for p in edge: center += p
		center /= edge.size()
		for j in edge.size():
			var next := (j+1)%edge.size()
			for p in ([center,edge[next],edge[j]] if a == start else [center,edge[j],edge[next]]): st.add_vertex(p)
	st.generate_normals()
	return st.commit()

static func _rock_point(a: float, row: Vector2, radius: float, height: float, phase: float) -> Vector3:
	var crest := 1.0 + sin(a*2.0+phase)*.22 + sin(a*7.0-phase)*.12 + sin(a*17.0+phase)*.045
	var groove := sin(a*12.0+phase)*8.5+sin(a*27.0-phase)*3.3
	var r := radius*row.x+groove*(.3+row.y*.7)
	return Vector3(cos(a)*r,row.y*height*crest-1.5,sin(a)*r)

static func _terrace() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 128:
		var a := TAU*i/128.0
		var b := TAU*(i+1)/128.0
		var p := Vector3(cos(a),0,sin(a))
		var q := Vector3(cos(b),0,sin(b))
		D._quad(st,p*96+Vector3.UP*8,q*96+Vector3.UP*8,q*124+Vector3.UP*8,p*124+Vector3.UP*8)
		D._quad(st,p*124,p*124+Vector3.UP*8,q*124+Vector3.UP*8,q*124)
		D._quad(st,q*96,q*96+Vector3.UP*8,p*96+Vector3.UP*8,p*96)
		D._quad(st,p*96,p*124,q*124,q*96)
	st.generate_normals()
	return st.commit()

static func _outcrop(seed_value: int) -> ArrayMesh:
	var outline: Array[Vector2] = [Vector2(-.85,-.5),Vector2(-.2,-.95),Vector2(.7,-.65),Vector2(1,.1),Vector2(.48,.86),Vector2(-.3,1),Vector2(-.95,.45)]
	var layers := [Vector2(1.03,0),Vector2(.94,.20),Vector2(.83,.23),Vector2(.88,.54),Vector2(.66,.57),Vector2(.61,.85),Vector2(.47,1)]
	var rings: Array = []
	for k in layers.size():
		var row: Vector2 = layers[k]
		var vertices: Array[Vector3] = []
		for i in outline.size():
			var v: Vector2 = outline[i]
			var offset := Vector2(sin(float(seed_value))*.3,cos(float(seed_value*2))*.22)*row.y
			vertices.append(Vector3(v.x*row.x+offset.x,row.y*(1.0+sin(i*2.4+seed_value)*.04)-.025,v.y*row.x+offset.y))
		rings.append(vertices)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for k in rings.size()-1:
		for i in outline.size():
			var j := (i+1)%outline.size()
			D._quad(st,rings[k][i],rings[k+1][i],rings[k+1][j],rings[k][j])
	var crown: Array = rings.back()
	var center := Vector3.ZERO
	for p in crown: center += p
	center /= crown.size()
	for i in crown.size():
		for p in [center,crown[(i+1)%crown.size()],crown[i]]: st.add_vertex(p)
	var base: Array = rings.front()
	var base_center := Vector3.ZERO
	for p in base: base_center += p
	base_center /= base.size()
	for i in base.size():
		for p in [base_center,base[i],base[(i+1)%base.size()]]: st.add_vertex(p)
	st.generate_normals()
	return st.commit()

## За воротами — сжатое ущелье с заставой на дороге и отдельной дальней седловиной.
static func _distant_pass(arena: Node3D, block: Mesh, rod: Mesh, cliff: Material, pale: Material, sand: Material, gold: Material, turquoise: Material) -> void:
	for side in [-1.0,1.0]:
		arena._static(_outcrop(31+int(side)),cliff,Vector3(side*42,-2,-182),Vector3(25,78,40),Vector3(0,side*.35,0))
		arena._static(_outcrop(35+int(side)),cliff,Vector3(side*59,-1,-251),Vector3(47,103,53),Vector3(0,-side*.28,0))
	var c := Vector3(3,13.5,-204)
	var arch := D.arch(8.3,1.3,4.0)
	D.piece(arena,arch,pale,c,0,Vector3(0,12,0),Vector3.ONE)
	for side in [-1.0,1.0]:
		D.piece(arena,block,sand,c,0,Vector3(side*9.4,6,0),Vector3(2.5,12,4))
		D.piece(arena,block,pale,c,0,Vector3(side*9.4,12,0),Vector3(3.5,1.2,5))
		D.piece(arena,rod,gold,c,0,Vector3(side*12,15,0),Vector3(.16,23,.16))
		D.piece(arena,_banner(3,6),turquoise,c,0,Vector3(side*12,25,.3),Vector3.ONE)
	# Узкий каменный акведук наверху принадлежит проходу, не пересекает поле.
	D.piece(arena,block,sand,c,0,Vector3(0,23,-1),Vector3(35,2,6))
	D.piece(arena,block,pale,c,0,Vector3(0,24.2,-1),Vector3(36,.6,6.4))
	for x in [-16.0,-12.0,12.0,16.0]:
		D.piece(arena,block,sand,c,0,Vector3(x,11,-1),Vector3(2,22,5))
	# Малый павильон виден в глубине над вторым поворотом дороги.
	var watch := Vector3(26,20,-265)
	D.piece(arena,block,sand,watch,0,Vector3(0,8,0),Vector3(17,16,15))
	for x in [-6.0,0.0,6.0]:
		D.piece(arena,rod,pale,watch,0,Vector3(x,20,5),Vector3(.6,8,.6))
	D.piece(arena,block,pale,watch,0,Vector3(0,24,0),Vector3(21,1.3,19))
	# Силуэт дальней заставы имеет проёмы, парапет и свой небольшой световой ритм.
	for side in [-1.0,1.0]:
		D.piece(arena,block,pale,watch,0,Vector3(side*8,16,5),Vector3(1.5,15,3))
		D.piece(arena,block,gold,watch,0,Vector3(side*10,25.1,0),Vector3(.45,1.5,18))
		D.piece(arena,_banner(2.4,7),turquoise,watch,0,Vector3(side*6,22,6),Vector3.ONE)
	for z in [-6.0,0.0,6.0]:
		D.piece(arena,rod,pale,watch,0,Vector3(-8,20,z),Vector3(.6,8,.6))
		D.piece(arena,rod,pale,watch,0,Vector3(8,20,z),Vector3(.6,8,.6))
	D.piece(arena,block,sand,watch,0,Vector3(0,25.5,-3),Vector3(18,2,11))

static func _banner(width: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var a := i/8.0
		var b := (i+1)/8.0
		var y0 := -height+absf(a-.5)*1.5
		var y1 := -height+absf(b-.5)*1.5
		D._quad(st,Vector3((a-.5)*width,0,0),Vector3((a-.5)*width,y0,sin(a*PI)*.7),Vector3((b-.5)*width,y1,sin(b*PI)*.7),Vector3((b-.5)*width,0,0))
	st.generate_normals()
	return st.commit()

static func _masonry(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 stone : source_color;
varying vec3 world;
varying vec3 world_normal;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
void fragment() {
	vec2 p=abs(world_normal.z)>abs(world_normal.x)?world.xy:world.zy;
	if(abs(world_normal.y)>.7) p=world.xz;
	float row = floor(p.y/2.7);
	vec2 grid=vec2(p.x/6.7+mod(row,2.0)*.5,p.y/2.7);
	vec2 edge=min(fract(grid),1.0-fract(grid));
	vec2 aa=max(fwidth(grid)*.65,vec2(.002));
	float seam_y = smoothstep(.018,.018+aa.y,edge.y);
	float seam_x = smoothstep(.012,.012+aa.x,edge.x);
	float mortar = min(seam_y,seam_x);
	float grain = sin(world.x*4.1+world.z*.9)*sin(world.z*3.5-world.y*2.3);
	float variation = sin(floor(p.x/6.7+mod(row,2.0)*.5)*2.7+row*3.1)*.055;
	ALBEDO = stone.rgb * (.72+.28*mortar+grain*.035+variation);
	ROUGHNESS = .95;
	SPECULAR = .18;
}
"""
	mat.set_shader_parameter("stone",color)
	return mat

static func _carved_wing(arena: Node3D, p: Vector3, yaw: float, block: Mesh, rod: Mesh, pale: Material, sand: Material, dark: Material, gold: Material, glow: Material) -> void:
	# Высокий цоколь связывает здание с осыпью; верх несёт террасу и малый храм.
	D.piece(arena,block,sand,p,yaw,Vector3(0,15,-5),Vector3(66,30,20))
	for y in [1.0,28.5,32.0]:
		D.piece(arena,block,pale,p,yaw,Vector3(0,y,0),Vector3(69,1.5,21))
	var arch := D.arch(7,1.1,2.3)
	for x in [-23.0,0.0,23.0]:
		D.piece(arena,block,dark,p,yaw,Vector3(x,16,5.2),Vector3(13,21,.22))
		D.piece(arena,arch,pale,p,yaw,Vector3(x,20,6),Vector3.ONE)
		for side in [-1.0,1.0]:
			D.piece(arena,rod,pale,p,yaw,Vector3(x+side*7.6,12,6),Vector3(.8,16,.8))
			D.piece(arena,block,gold,p,yaw,Vector3(x+side*7.6,4,6),Vector3(2.4,1.0,2.4))
		D.piece(arena,block,glow,p,yaw,Vector3(x,10,5.5),Vector3(.3,6,.25))
	for x in [-30.0,-15.0,15.0,30.0]:
		D.piece(arena,block,sand,p,yaw,Vector3(x,36,-2),Vector3(2.5,8,3))
	D.piece(arena,block,pale,p,yaw,Vector3(0,40,-2),Vector3(65,1.2,4))
	# Верхняя открытая лоджия, выступающая из природной стены.
	D.piece(arena,block,sand,p,yaw,Vector3(0,37,-9),Vector3(22,9,9))
	for x in [-9.5,-3.2,3.2,9.5]:
		D.piece(arena,rod,pale,p,yaw,Vector3(x,45,-1),Vector3(.8,10,.8))
	D.piece(arena,block,pale,p,yaw,Vector3(0,50.3,-4),Vector3(25,2.2,14))
	D.piece(arena,block,gold,p,yaw,Vector3(0,52,-4),Vector3(26,.5,15))
	# Полотна чуть провисают и держатся на архитектуре; статический меш без cloth.
	var fabric := D.material(Color(.07,.19,.19),.98)
	fabric.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flag := SurfaceTool.new()
	flag.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var a := i/8.0
		var b := (i+1)/8.0
		D._quad(flag,Vector3(a*16-8,0,sin(a*PI)*1.3),Vector3(a*16-8,-10,sin(a*PI)*1.7),Vector3(b*16-8,-10,sin(b*PI)*1.7),Vector3(b*16-8,0,sin(b*PI)*1.3))
	flag.generate_normals()
	D.piece(arena,flag.commit(),fabric,p,yaw,Vector3(0,27,8),Vector3.ONE)
