extends RefCounted
## The illustrated archipelago layout rebuilt as opaque, naturally lit 3D land.
## Water and the gameplay bodies remain independent of this decorative landscape.
const SEA_LEVEL := -4.5
const D := preload("res://scenes/landscape_detail.gd")
const Water := preload("res://scenes/locations/coastal_water.gd")
static var _land_noise: ImageTexture
# Exact footprints from tools/art/paint_illustrated_harbor.py: x,z,rx,rz,yaw,seed.
const ISLANDS := [
	[-400,-255,245,146,-.45,0],[257,-398,184,123,.34,1],[-40,-675,250,116,-.55,2],
	[652,-191,258,154,-.32,3],[-615,182,267,141,.71,4],[572,380,194,122,.12,5],
	[-245,509,211,163,-.17,6],[93,761,191,104,-.17,7],[468,-775,151,87,.28,8],
	[1019,-480,173,97,-.64,9],[-956,-594,263,103,.38,10],[-804,672,228,163,-.28,11],
	[1043,575,291,121,.78,12],[1128,113,90,52,.15,13],[-1088,-42,125,56,.35,14],
	[869,-993,258,109,.41,15],[-333,-1138,316,167,.13,16],[224,-1200,216,120,1.04,17],
	[-1200,966,204,123,.22,18],[588,980,214,111,-.46,19],[-308,1070,141,84,.18,20],
	[994,1098,103,102,.6,21],[278,233,57,32,-.45,22],[-211,227,54,38,-.37,23],
	[-194,-328,31,21,-.47,24],[131,-263,50,38,-.41,25],[338,79,75,39,.31,26],
	[-413,184,58,30,.25,27],[307,-622,66,34,-.91,28],[547,622,72,26,-.11,29],
]

static func build(arena: Node3D) -> void:
	var root := Node3D.new()
	root.name = "CoastalLandscape"
	arena._decor.add_child(root)
	var land := _terrain_material()
	var bed := MeshInstance3D.new()
	bed.name = "DeepOpaqueSeabed"
	var plane := PlaneMesh.new()
	plane.size = Vector2(8400,8400)
	bed.mesh = plane
	bed.position.y = -90.0
	bed.material_override = land
	root.add_child(bed)
	# One continuous shelf under the free-standing stage; it never forms a dry slab.
	var shelf := MeshInstance3D.new()
	shelf.name = "OpaqueSubmergedShelf"
	shelf.mesh = _shelf_mesh()
	shelf.material_override = land
	root.add_child(shelf)
	for i in ISLANDS.size():
		var island := MeshInstance3D.new()
		island.name = "GreenIsland%02d" % i
		island.mesh = _island_mesh(ISLANDS[i])
		island.material_override = land
		# Broad grazing-angle terrain must not cast biased shadow-map triangles on itself.
		# It still receives the trees' and lighthouse's contact shadows.
		island.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(island)
	var pale := D.material(Color(.61,.58,.47),.89)
	var trim := D.material(Color(.41,.43,.39),.88)
	var box := BoxMesh.new()
	# The same low square sea platform from the concept. Nothing encloses play.
	arena._static(box,trim,Vector3(0,-2.25,0),Vector3(282,4.3,282),Vector3.ZERO)
	for side in [-1.0,1.0]:
		arena._static(box,pale,Vector3(side*140,-.7,0),Vector3(1.5,.8,282),Vector3.ZERO)
		arena._static(box,pale,Vector3(0,-.7,side*140),Vector3(282,.8,1.5),Vector3.ZERO)
	_lighthouse(arena,Vector3(-400,_island_height(Vector2(-400,-255),ISLANDS[0]),-255))
	_sailboat(arena,Vector3(-194,SEA_LEVEL,-165),1.0,-1.0)
	_sailboat(arena,Vector3(193,SEA_LEVEL,-145),.69,-1.0)
	_vegetation(arena)
	var seabed_rock := D.material(Color(.29,.30,.24),.92)
	var rock_mesh := _foliage_mesh()
	for i in 80:
		var a := i*2.399
		var p := Vector2(278+cos(a)*60.0,233+sin(a)*37.0)
		var h := _island_height(p,ISLANDS[22])
		if h < SEA_LEVEL-3.5 or h > SEA_LEVEL-1.0: continue
		arena._static(rock_mesh,seabed_rock,Vector3(p.x,h+.1,p.y),Vector3(1.1+float(i%3)*.4,.5+float(i%2)*.25,1.5),Vector3(.1,a,.05))
	Water.build(root,SEA_LEVEL,Vector2(2400,2400))
	arena._flush_static()
	arena._decor.set_meta("detailed_location",3)

static func _island_height(p: Vector2, island: Array) -> float:
	var d := p-Vector2(island[0],island[1])
	var yaw: float = island[4]
	var u := (d.x*cos(yaw)+d.y*sin(yaw))/float(island[2])
	var v := (-d.x*sin(yaw)+d.y*cos(yaw))/float(island[3])
	var theta := atan2(v,u)
	var seed: float = island[5]
	var rough := (.11*sin(theta*3+seed)+.095*cos(theta*5+seed*.67)+.035*sin(theta*9+seed*.72))*smoothstep(.0,.60,Vector2(u,v).length())
	var shore := (1.0+rough-Vector2(u,v).length())*minf(island[2],island[3])
	if shore < 0: return maxf(-60.0,SEA_LEVEL+shore*.55)
	var ridge := (sin(u*3.5+seed*.61)+cos(v*4.1+seed))*.33
	# Low overlapping coastal folds, rather than the same smooth mound everywhere.
	ridge += (sin(u*8.1+v*2.7+seed)*.52+cos(v*9.3-u*3.2+seed*.73)*.28)*smoothstep(7,30,shore)
	var peak := 2.4*tanh(minf(island[2],island[3])/110.0)+.5
	var h := maxf(0,.49+pow(maxf(shore,0),.58)*peak/7.0+ridge)*smoothstep(0,9,shore)
	# The old canvas landmark had no terrain occlusion and visually sat below the
	# mathematical summit. A lower true hill keeps that silhouette with a real tower.
	return SEA_LEVEL+h*5.1

static func _island_mesh(island: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var rings := 112
	var sides := 256
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	# Share analytic samples across adjacent triangles. Catalog construction uses
	# these meshes only once, before the menu, rather than retracing every corner.
	for z in rings+1:
		for x in sides+1:
			var a := float(x)/float(sides)*TAU
			var radial := float(z)/32.0*.75 if z <= 32 else (.75+float(z-32)/64.0*.55 if z <= 96 else 1.3+float(z-96)/16.0*.6)
			var local := Vector2(cos(a)*float(island[2]),sin(a)*float(island[3]))*radial
			var yaw: float = island[4]
			var p := Vector2(local.x*cos(yaw)-local.y*sin(yaw),local.x*sin(yaw)+local.y*cos(yaw))+Vector2(island[0],island[1])
			positions.append(Vector3(p.x,_island_height(p,island),p.y))
			normals.append(Vector3(_island_height(Vector2(p.x-.4,p.y),island)-_island_height(Vector2(p.x+.4,p.y),island),.8,_island_height(Vector2(p.x,p.y-.4),island)-_island_height(Vector2(p.x,p.y+.4),island)).normalized())
	for z in rings:
		for x in sides:
			# Angle/radius coordinates have opposite winding to a Cartesian grid.
			for i in [z*(sides+1)+x,(z+1)*(sides+1)+x+1,z*(sides+1)+x+1,z*(sides+1)+x,(z+1)*(sides+1)+x,(z+1)*(sides+1)+x+1]:
				st.set_normal(normals[i])
				st.add_vertex(positions[i])
	st.index()
	return st.commit()

static func _shelf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var steps := 200
	for z in steps:
		for x in steps:
			var vertices: Array[Vector3] = []
			for v in [Vector2(x,z),Vector2(x+1,z),Vector2(x+1,z+1),Vector2(x,z+1)]:
				var p: Vector2 = v/float(steps)*620.0-Vector2.ONE*310.0
				# Continues the real small island's underwater slope; no separate disc.
				var h := maxf(-28.0,minf(-6.0,_island_height(p,ISLANDS[22])))
				vertices.append(Vector3(p.x,h,p.y))
			for i in [0,1,2,0,2,3]: st.add_vertex(vertices[i])
	st.index()
	st.generate_normals()
	return st.commit()

static func _lighthouse(arena: Node3D, p: Vector3) -> void:
	var white := D.material(Color(.75,.72,.61),.88)
	var red := D.material(Color(.38,.115,.075),.82)
	var metal := D.material(Color(.075,.13,.15),.56,.35)
	var stone := D.material(Color(.35,.38,.32),.91)
	var rod := D.rod(32)
	var box := BoxMesh.new()
	arena._static(box,stone,p+Vector3(0,-2,0),Vector3(27,8,24),Vector3.ZERO)
	var foundation := D.rod(12)
	arena._static(foundation,stone,p+Vector3(0,2.0,0),Vector3(11.5,2.0,11.5),Vector3.ZERO)
	var step := D.material(Color(.53,.51,.42),.93)
	for i in 4:
		arena._static(box,step,p+Vector3(0,.3+float(i)*.8,15-float(i)*1.8),Vector3(6.5,1,3.5),Vector3.ZERO)
	var tower := CylinderMesh.new()
	tower.top_radius = 5.2
	tower.bottom_radius = 8.0
	tower.height = 51
	tower.radial_segments = 48
	arena._static(tower,white,p+Vector3(0,27,0),Vector3.ONE,Vector3.ZERO)
	arena._static(rod,red,p+Vector3(0,31,0),Vector3(6.7,9.0,6.7),Vector3.ZERO)
	for y in [10.0,42.0]:
		arena._static(box,metal,p+Vector3(0,y,8.15-y*.055),Vector3(2.5,4.8,.5),Vector3.ZERO)
	arena._static(box,metal,p+Vector3(0,5,7.8),Vector3(3.3,7,.6),Vector3.ZERO)
	arena._static(rod,metal,p+Vector3(0,54,0),Vector3(7.2,1.2,7.2),Vector3.ZERO)
	# A walk-around lantern gallery gives the tower a readable architectural scale.
	for i in 16:
		var a := TAU*i/16.0
		var b := TAU*(i+1)/16.0
		var rim := Vector3(cos(a)*6.65,56.6,sin(a)*6.65)
		arena._static(rod,metal,p+rim-Vector3(0,1.1,0),Vector3(.12,2.2,.12),Vector3.ZERO)
		D.beam(arena,rod,metal,p+rim,p+Vector3(cos(b)*6.65,56.6,sin(b)*6.65),.15)
	var lamp := D.material(Color(.67,.56,.31),.3,.2)
	for i in 8:
		var a := TAU*i/8.0
		arena._static(rod,metal,p+Vector3(cos(a)*4.9,59,sin(a)*4.9),Vector3(.22,9,.22),Vector3.ZERO)
	arena._static(rod,lamp,p+Vector3(0,59,0),Vector3(3.1,7,3.1),Vector3.ZERO)
	var roof := CylinderMesh.new()
	roof.top_radius = 0
	roof.bottom_radius = 8.0
	roof.height = 5
	roof.radial_segments = 32
	arena._static(roof,red,p+Vector3(0,66,0),Vector3.ONE,Vector3.ZERO)

static func _sailboat(arena: Node3D, p: Vector3, s: float, yaw: float) -> void:
	var wood := D.material(Color(.21,.105,.058),.84)
	var cloth := D.material(Color(.76,.72,.58),.96)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	D.piece(arena,D.hull(),wood,p,yaw,Vector3.ZERO,Vector3(1.3,.9,1.65)*s)
	D.piece(arena,D.rod(12),wood,p,yaw,Vector3(0,18,0)*s,Vector3(.32,35,.32)*s)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pts in [[Vector3(0,34,0),Vector3(0,4,0),Vector3(0,4,-20)], [Vector3(0,27,1),Vector3(0,4,1),Vector3(0,4,17)]]:
		for point in pts: st.add_vertex(point)
	st.generate_normals()
	D.piece(arena,st.commit(),cloth,p,yaw,Vector3.ZERO,Vector3.ONE*s)

static func _vegetation(arena: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 18213
	var trunk := D.material(Color(.19,.155,.102),.97)
	var leaves := [D.material(Color(.095,.16,.075),.98),D.material(Color(.14,.215,.095),.98),D.material(Color(.21,.265,.12),.98)]
	for material in leaves:
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var bushes := [D.material(Color(.20,.25,.12),.99),D.material(Color(.30,.31,.17),.99)]
	var rock := [D.material(Color(.36,.375,.32),.95),D.material(Color(.48,.47,.38),.96)]
	var grass := D.material(Color(.32,.36,.16),.99)
	grass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rod := D.rod(8)
	var crown := _tree_crown_mesh()
	var brush := _foliage_mesh()
	var crag := _coastal_rock_mesh()
	var tuft := _grass_mesh()
	for island in ISLANDS:
		var count := int(float(island[2])*float(island[3])/430.0)
		for i in count:
			var p := Vector2(island[0]+rng.randf_range(-island[2],island[2]),island[1]+rng.randf_range(-island[3],island[3]))
			var h := _island_height(p,island)
			if h < .5 or p.distance_to(Vector2(-400,-255)) < 29: continue
			var pos := Vector3(p.x,h,p.y)
			var grove := sin(p.x*.037+island[5])*.55+cos(p.y*.042-p.x*.014)*.45
			# Wind-exposed meadow and small brush separate the irregular groves.
			if grove > .06 and h > 3.0 and minf(island[2],island[3]) > 36:
				var size := rng.randf_range(10.0,24.0)
				var yaw := rng.randf()*TAU
				var lean := Vector3(cos(yaw)*size*.10,0,sin(yaw)*size*.10)
				var fork := pos+Vector3(0,size*.59,0)+lean
				D.beam(arena,rod,trunk,pos,fork,size*.065)
				var pine := i%3 == 0
				for j in 5:
					var a := yaw+float(j)*2.399
					var spread := size*(.055 if pine else .21)*rng.randf_range(.75,1.25)
					# Pines form a tapering, upright silhouette; broadleaf trees keep
					# asymmetric lateral crowns. Both use the same opaque leaf sprays.
					var crown_y := .47+float(j)*.14 if pine else .70+float(j%3)*.14
					var offset := Vector3(cos(a)*spread,size*crown_y,sin(a)*spread)+lean
					var tip := pos+offset
					D.beam(arena,rod,trunk,fork,tip,size*.025)
					var taper := 1.0-float(j)*.17
					var shape := Vector3(.36*taper,.13,.31*taper) if pine else Vector3(.25,.22,.23)
					arena._static(crown,leaves[(i+j)%3],tip,shape*size*rng.randf_range(.85,1.12),Vector3(.1,a,.09))
			elif i%2 == 0:
				var size := rng.randf_range(1.8,4.2)
				arena._static(brush,bushes[i%2],pos+Vector3(0,size*.45,0),Vector3(size,size*.65,size*.8),Vector3(0,rng.randf()*TAU,.15))
			for j in 3:
				var q := p+Vector2(rng.randf_range(-9,9),rng.randf_range(-9,9))
				var y := _island_height(q,island)
				if y < -.5: continue
				var s := rng.randf_range(.7,1.5)
				arena._static(tuft,grass,Vector3(q.x,y+.03,q.y),Vector3(s,s,s),Vector3(0,rng.randf()*TAU,0))
		# Exposed stone occurs in small asymmetric groups, never a ring of props.
		for i in (int(float(island[2])*float(island[3])/900.0) if minf(island[2],island[3]) > 60 else 0):
			var a: float = rng.randf()*TAU
			var r := rng.randf_range(.69,.96)
			var local := Vector2(cos(a)*island[2],sin(a)*island[3])*r
			var yaw: float = island[4]
			var p := Vector2(local.x*cos(yaw)-local.y*sin(yaw),local.x*sin(yaw)+local.y*cos(yaw))+Vector2(island[0],island[1])
			var h := _island_height(p,island)
			if h < SEA_LEVEL+1 or h > 7 or sin(a*3+island[5]) < .1: continue
			var s := rng.randf_range(2.0,5.5)
			for j in 3:
				var q := p+Vector2(cos(a+j)*s*.7,sin(a+j)*s*.7)
				arena._static(crag,rock[j%2],Vector3(q.x,_island_height(q,island)+s*.12,q.y),Vector3(s,s*rng.randf_range(.5,.9),s*.75),Vector3(.12,a+j*.7,.08))

static func _coastal_rock_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in 5:
		for x in 11:
			for v in [Vector2(x,y),Vector2(x+1,y+1),Vector2(x+1,y),Vector2(x,y),Vector2(x,y+1),Vector2(x+1,y+1)]:
				var a: float = v.x/11.0*TAU
				var b: float = v.y/5.0*PI
				var r := 1.0+sin(a*3+b*2)*.19+cos(a*5-b*3)*.13
				st.add_vertex(Vector3(cos(a)*sin(b)*r,cos(b)*.8,sin(a)*sin(b)*r))
	st.index()
	st.generate_normals()
	return st.commit()

static func _tree_crown_mesh() -> ArrayMesh:
	# Separated overlapping leaf sprays give real silhouette gaps at no alpha cost.
	# Shared by all crowns; the old closed ellipsoid is retained for small shrubs.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 40819
	for i in 88:
		var a := float(i)*2.399
		var y := 1.0-2.0*(float(i)+.5)/88.0
		var r := sqrt(1.0-y*y)
		var normal := Vector3(cos(a)*r,y,sin(a)*r)
		var center := normal*rng.randf_range(.68,1.0)
		var u := normal.cross(Vector3.UP if absf(y) < .9 else Vector3.RIGHT).normalized()
		var v := normal.cross(u).normalized()
		var size := rng.randf_range(.23,.34)
		var points := [center+u*size,center+v*size*.72,center-u*size,center-v*size*.72]
		st.set_color(Color.WHITE*rng.randf_range(.78,1.08))
		for j in 4:
			for p in [points[j],points[(j+1)%4],center+normal*.10]: st.add_vertex(p)
	st.index()
	st.generate_normals()
	return st.commit()

static func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 9:
		var a := i*2.399
		var foot := Vector3(cos(a)*float(i%3)*.32,0,sin(a)*float(i%3)*.32)
		var width := Vector3(cos(a),0,sin(a))*.08
		for p in [foot-width,foot+Vector3(.18,.6+float(i%4)*.21,.1),foot+width]:
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	return st.commit()

static func _foliage_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for y in 10:
		for x in 18:
			for v in [Vector2(x,y),Vector2(x+1,y+1),Vector2(x+1,y),Vector2(x,y),Vector2(x,y+1),Vector2(x+1,y+1)]:
				var a: float = v.x/18.0*TAU
				var b: float = v.y/10.0*PI
				var n := 1.0+sin(a*5+b*3)*.09+cos(a*7-b*4)*.07
				st.add_vertex(Vector3(cos(a)*sin(b)*n,cos(b)*(1+sin(a*4)*sin(b)*.11),sin(a)*sin(b)*n))
	st.index()
	st.generate_normals()
	return st.commit()

static func _terrain_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """shader_type spatial;
varying vec3 wp;
varying vec3 wn;
uniform sampler2D terrain_noise : repeat_enable, filter_linear_mipmap;
// A filtered texture avoids sin/hash precision discontinuities between the
// triangles of broad world-space terrain on Vulkan.
float noise(vec2 p){return texture(terrain_noise,p*.075).r;}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 float n=noise(wp.xz*.018)*.57+noise(wp.xz*.11)*.28+noise(wp.xz*.95)*.15;
 // Broad meadow masses remain readable during the flyby. Smaller variation
 // follows them instead of covering the islands with speckled detail.
 float meadow=noise(wp.xz*.009+vec2(13.2,6.1));
 float patch=noise(wp.xz*.021+vec2(2.8,9.4));
 float meadow_t=smoothstep(.25,.75,meadow*.76+patch*.24);
 vec3 grass=mix(vec3(.105,.17,.055),vec3(.29,.35,.13),n);
 grass*=mix(.86,1.05,meadow_t);
 float dry=smoothstep(.40,.80,noise(wp.xz*.011+vec2(8.2,3.1)));
 grass=mix(grass,vec3(.29,.285,.145),dry*.22);
 float t=clamp((wp.x+400.0)/125.0,0.0,1.0);
 float trail_z=-255.0+sin(t*1.2)*45.0+t*42.0;
 float trail=(1.0-smoothstep(1.3,3.0+noise(wp.xz*.25),abs(wp.z-trail_z)))*smoothstep(-411.0,-397.0,wp.x)*(1.0-smoothstep(-300.0,-265.0,wp.x));
 grass=mix(grass,vec3(.34,.31,.21),trail*.47);
 vec3 stone=mix(vec3(.22,.25,.20),vec3(.43,.43,.32),n);
 vec3 sand=mix(vec3(.34,.315,.22),vec3(.56,.52,.36),n);
 // Keep the accepted submerged sand intact. Above water, beach width and
 // weathered stone vary by land mass and slope instead of a uniform pale ring.
 float old_shore=1.0-smoothstep(-3.7,.15+(n-.5)*1.8,wp.y);
 float shore=1.0-smoothstep(-3.9,-1.9+(patch-.5)*2.2,wp.y);
 float cliff=(1.0-smoothstep(.60,.88,abs(wn.y)))*smoothstep(-1.0,5.0,wp.y);
 float bank=smoothstep(.49,.67,patch*.67+meadow*.33+(1.0-abs(wn.y))*.6);
 bank*=smoothstep(-4.3,-3.0,wp.y)*(1.0-smoothstep(1.0,5.5,wp.y));
 float bedding=sin(wp.y*2.7+noise(wp.xz*.30)*3.4)*.024;
 vec3 bank_stone=mix(vec3(.235,.255,.215),vec3(.39,.385,.30),patch)+bedding;
 vec3 dry_land=mix(mix(grass,stone,cliff*.85),sand,shore);
 dry_land=mix(dry_land,bank_stone,bank*.83);
 vec3 submerged=mix(mix(grass,stone,cliff*.85),sand,old_shore);
 ALBEDO=mix(submerged,dry_land,smoothstep(-4.45,-4.0,wp.y));
 float wet=1.0-smoothstep(-4.5,-3.0,wp.y);
 ALBEDO*=1.0-wet*.10;
 ROUGHNESS=mix(.97,.70,wet);SPECULAR=.22;
}"""
	if _land_noise == null:
		var field := FastNoiseLite.new()
		field.seed = 55173
		field.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		field.fractal_type = FastNoiseLite.FRACTAL_FBM
		field.frequency = .075
		var pixels := field.get_seamless_image(256,256)
		pixels.generate_mipmaps()
		_land_noise = ImageTexture.create_from_image(pixels)
	mat.set_shader_parameter("terrain_noise",_land_noise)
	return mat
