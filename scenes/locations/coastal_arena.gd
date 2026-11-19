extends RefCounted
## The illustrated archipelago layout rebuilt as opaque, naturally lit 3D land.
## Water and the gameplay bodies remain independent of this decorative landscape.
const SEA_LEVEL := -4.5
const D := preload("res://scenes/landscape_detail.gd")
const Water := preload("res://scenes/locations/coastal_water.gd")
static var _land_noise: ImageTexture
const Style := preload("res://scenes/locations/coastal_style.gd")
const ISLANDS := Style.ISLANDS

# Local angles of the exposed headlands seen from the straits and the intro.
const HEADLANDS := {0: 1.08, 22: -2.42, 23: .68}
const SHORE_RING := 32
const OUTER_RING := 48

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
	shelf.position = Style.island_offset(22)
	shelf.set_instance_shader_parameter("island_offset",shelf.position)
	root.add_child(shelf)
	var contacts := {}
	_vegetation(arena,contacts)
	for i in ISLANDS.size():
		var island := MeshInstance3D.new()
		island.name = "GreenIsland%02d" % i
		island.mesh = _island_mesh(ISLANDS[i],contacts)
		var shift := Style.island_offset(i)
		island.position = Vector3(ISLANDS[i][0],0,ISLANDS[i][1])+shift
		island.material_override = land
		island.set_instance_shader_parameter("island_offset",shift)
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
	var beacon := Vector2(ISLANDS[0][0],ISLANDS[0][1])
	_lighthouse(arena,Vector3(beacon.x,_island_height(beacon,ISLANDS[0]),beacon.y)+Style.island_offset(0))
	_sailboat(arena,Vector3(-194,SEA_LEVEL,-165)+Style.island_offset(0),1.0,-1.0)
	_sailboat(arena,Vector3(193,SEA_LEVEL,-145)+Style.island_offset(1),.69,-1.0)
	var seabed_rock := D.material(Color(.29,.30,.24),.92)
	var rock_mesh := _foliage_mesh()
	for i in 80:
		var a := i*2.399
		var p := Vector2(278+cos(a)*60.0,233+sin(a)*37.0)
		var h := _island_height(p,ISLANDS[22])
		if h < SEA_LEVEL-3.5 or h > SEA_LEVEL-1.0: continue
		arena._static(rock_mesh,seabed_rock,Vector3(p.x,h+.1,p.y)+shelf.position,Vector3(1.1+float(i%3)*.4,.5+float(i%2)*.25,1.5),Vector3(.1,a,.05))
	arena._coastal_water_mat = Water.build(root,SEA_LEVEL,Vector2(2400,2400))
	arena._flush_static()
	arena._decor.set_meta("detailed_location",3)

static func _island_height(p: Vector2, island: Array) -> float:
	var d := p-Vector2(island[0],island[1])
	var yaw: float = island[4]
	var u := (d.x*cos(yaw)+d.y*sin(yaw))/float(island[2])
	var v := (-d.x*sin(yaw)+d.y*cos(yaw))/float(island[3])
	var theta := atan2(v,u)
	var seed: float = island[5]
	var rough := (_coast_radius(theta, int(seed)) - 1.0) * smoothstep(.0,.60,Vector2(u,v).length())
	var shore := (1.0+rough-Vector2(u,v).length())*minf(island[2],island[3])
	if shore < 0: return maxf(-60.0,SEA_LEVEL+shore*.55)
	var ridge := (sin(u*3.5+seed*.61)+cos(v*4.1+seed))*.33
	# Low overlapping coastal folds, rather than the same smooth mound everywhere.
	ridge += (sin(u*8.1+v*2.7+seed)*.52+cos(v*9.3-u*3.2+seed*.73)*.28)*smoothstep(7,30,shore)
	var peak := 2.4*tanh(minf(island[2],island[3])/110.0)+.5
	var h := maxf(0,.49+pow(maxf(shore,0),.58)*peak/7.0+ridge)*smoothstep(0,9,shore)
	# The old canvas landmark had no terrain occlusion and visually sat below the
	# mathematical summit. A lower true hill keeps that silhouette with a real tower.
	var bluff := 0.0
	if HEADLANDS.has(int(seed)):
		var along := theta-float(HEADLANDS[int(seed)])
		# Resistant spurs alternate with narrow gullies. Their toes and brow
		# retreat independently instead of forming a single level retaining wall.
		var joint := absf(sin(along*12.0+sin(along*7.0+seed)*.95))
		var spur := smoothstep(.12,.88,joint)*(.70+.30*cos(along*7.7-seed))
		var apron := 1.1+(1.0-spur)*4.8
		bluff = _headland(theta,int(seed))*(.18+.82*spur)*smoothstep(0.0,apron+2.6,shore)*(1.0-smoothstep(8.0+spur*5.0,29.0,shore))
	return SEA_LEVEL+h*5.1+bluff*minf(10.5,float(island[3])*.155)

static func _headland(angle: float, seed: int) -> float:
	if not HEADLANDS.has(seed):
		return 0.0
	return smoothstep(.81,.995,cos(angle-float(HEADLANDS[seed])))


static func _coast_radius(angle: float, seed: int) -> float:
	var r := 1.0+.11*sin(angle*3+seed)+.095*cos(angle*5+seed*.67)+.035*sin(angle*9+seed*.72)
	if HEADLANDS.has(seed):
		var along := angle-float(HEADLANDS[seed])
		r += (.05+.027*sin(along*18.0+seed)+.016*sin(along*29.0-seed))*_headland(angle,seed)
		r -= .04*smoothstep(.90,.995,cos(along-.64))
	return r


static func _radial_distance(ring: int, coast: float, short_radius: float) -> float:
	# Sample the actual waterline exactly once, with extra resolution on the
	# bluff and submerged bank. The outer edge still ends at the original 1.9.
	var bank := 10.0/short_radius
	if ring <= 24: return (coast-bank)*float(ring)/24.0
	if ring <= SHORE_RING: return coast-bank*float(SHORE_RING-ring)/8.0
	if ring <= 40: return coast+bank*float(ring-SHORE_RING)/8.0
	return lerpf(coast+bank,1.9,float(ring-40)/8.0)


static func _island_indices(sides: int, stride: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	var previous := 0
	for ring in range(1, OUTER_RING+1):
		if ring % stride != 0 and absi(ring-SHORE_RING) > 1: continue
		for x in sides:
			var next := (x+1) % sides
			var outer := 1+(ring-1)*sides
			if previous == 0:
				indices.append_array(PackedInt32Array([0,outer+x,outer+next]))
			else:
				var inner := 1+(previous-1)*sides
				indices.append_array(PackedInt32Array([inner+x,outer+next,inner+next,inner+x,outer+x,outer+next]))
		previous = ring
	return indices


static func _island_mesh(island: Array, contacts: Dictionary) -> ArrayMesh:
	var size := Vector2(island[2],island[3])
	var center := Vector2(island[0],island[1])
	var seed := int(island[5])
	var sides := clampi(ceili(size.x/8.0)*8, 80, 192)
	var vertices := PackedVector3Array([Vector3(0,_island_height(center,island),0)])
	var normals := PackedVector3Array([Vector3.UP])
	var colors := PackedColorArray([Color.BLACK])
	for ring in range(1, OUTER_RING+1):
		for x in sides:
			var angle := TAU*float(x)/sides
			var coast := _coast_radius(angle,seed)
			var radial := _radial_distance(ring,coast,minf(size.x,size.y))
			var local := (Vector2.from_angle(angle)*size*radial).rotated(island[4])
			var point := center+local
			var height := _island_height(point,island)
			var normal := Vector3(_island_height(point-Vector2(.4,0),island)-_island_height(point+Vector2(.4,0),island),.8,_island_height(point-Vector2(0,.4),island)-_island_height(point+Vector2(0,.4),island)).normalized()
			vertices.append(Vector3(local.x,height,local.y))
			normals.append(normal)
			colors.append(Color(_headland(angle,seed)*smoothstep(.45,.85,radial),_ground_contact(point,contacts),0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _island_indices(sides,1)
	# Godot chooses by projected error and the active viewport's LOD threshold.
	# All three meshes share the same three rings around the shoreline.
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{.35:_island_indices(sides,2),1.25:_island_indices(sides,4)})
	return mesh


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

# Bake a short contact shadow around actual roots and rock feet into the land
# vertices. The spatial grid exists only while constructing the resident arena.
static func _add_contact(point: Vector2, radius: float, contacts: Dictionary) -> void:
	var lo := Vector2i(((point-Vector2.ONE*radius)/12.0).floor())
	var hi := Vector2i(((point+Vector2.ONE*radius)/12.0).floor())
	for y in range(lo.y,hi.y+1):
		for x in range(lo.x,hi.x+1):
			var cell := Vector2i(x,y)
			if not contacts.has(cell): contacts[cell] = []
			contacts[cell].append(Vector3(point.x,point.y,radius))


static func _ground_contact(point: Vector2, contacts: Dictionary) -> float:
	var cell := Vector2i((point/12.0).floor())
	var shade := 0.0
	if contacts.has(cell):
		for foot: Vector3 in contacts[cell]:
			shade = maxf(shade,1.0-smoothstep(.0,foot.z,point.distance_to(Vector2(foot.x,foot.y))))
	return shade


static func _supports_growth(p: Vector2, island: Array) -> bool:
	if not HEADLANDS.has(int(island[5])): return true
	var dx := _island_height(p+Vector2.RIGHT,island)-_island_height(p-Vector2.RIGHT,island)
	var dz := _island_height(p+Vector2.DOWN,island)-_island_height(p-Vector2.DOWN,island)
	# A two-metre baseline excludes the exposed, steep cliff faces.
	return dx*dx+dz*dz < 1.0


static func _vegetation(arena: Node3D, contacts: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 18213
	var trunk := D.material(Color(.19,.155,.102),.97)
	var leaves := [D.material(Color(.17,.25,.13),.98),D.material(Color(.205,.29,.14),.98),D.material(Color(.26,.33,.155),.98)]
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
		var shift := Style.island_offset(int(island[5]))
		var count := int(float(island[2])*float(island[3])/430.0)
		for i in count:
			var p := Vector2(island[0]+rng.randf_range(-island[2],island[2]),island[1]+rng.randf_range(-island[3],island[3]))
			var h := _island_height(p,island)
			if h < .5 or p.distance_to(Vector2(-400,-255)) < 29: continue
			var pos := Vector3(p.x,h,p.y)+shift
			var rooted := _supports_growth(p,island)
			var grove := sin(p.x*.037+island[5])*.55+cos(p.y*.042-p.x*.014)*.45
			# Wind-exposed meadow and small brush separate the irregular groves.
			if grove > .06 and h > 3.0 and minf(island[2],island[3]) > 36:
				var size := rng.randf_range(8.0,minf(24.0,float(island[3])*.41))
				if rooted: _add_contact(p,size*.41,contacts)
				var yaw := rng.randf()*TAU
				var lean := Vector3(cos(yaw),0,sin(yaw))*size*(.05+.09*absf(sin(i*2.28)))
				var fork := pos+Vector3(0,size*.43,0)+lean
				if rooted: D.beam(arena,rod,trunk,pos-Vector3.UP*(size*.085+1.45),fork,size*.040)
				var pine := (i+int(island[5]))%3 == 0
				for j in 5:
					var a := yaw+float(j)*2.399
					var spread := size*(.055 if pine else .21)*rng.randf_range(.75,1.25)
					# Pines form a tapering, upright silhouette; broadleaf trees keep
					# asymmetric lateral crowns. Both use the same opaque leaf sprays.
					var crown_y := .38+float(j)*.16 if pine else .55+float(j%3)*.19
					var offset := Vector3(cos(a)*spread,size*crown_y,sin(a)*spread)+lean
					var tip := pos+offset
					if rooted: D.beam(arena,rod,trunk,fork,tip,size*.025)
					var taper := 1.0-float(j)*.17
					var shape := Vector3(.36*taper,.13,.31*taper) if pine else Vector3(.25,.22,.23)
					var dimensions := shape*size*rng.randf_range(.85,1.12)
					if rooted: arena._static(crown,leaves[(i+j)%3],tip,dimensions,Vector3(.1,a,.09))
			elif i%2 == 0:
				var size := rng.randf_range(1.8,4.2)
				var turn := rng.randf()*TAU
				if rooted: arena._static(brush,bushes[(i/2)%2],pos+Vector3(0,size*.33,0),Vector3(size,size*.65,size*.8),Vector3(0,turn,.15))
			for j in 3:
				var q := p+Vector2(rng.randf_range(-9,9),rng.randf_range(-9,9))
				var y := _island_height(q,island)
				if y < -.5: continue
				var s := rng.randf_range(.7,1.5)
				var turn := rng.randf()*TAU
				if _supports_growth(q,island): arena._static(tuft,grass,Vector3(q.x,y+.03,q.y)+shift,Vector3(s,s,s),Vector3(0,turn,0))
		# Exposed stone occurs in small asymmetric groups, never a ring of props.
		for i in (int(float(island[2])*float(island[3])/900.0) if minf(island[2],island[3]) > 60 else 0):
			var a: float = rng.randf()*TAU
			var r := rng.randf_range(.69,.96)
			var local := Vector2(cos(a)*island[2],sin(a)*island[3])*r
			var yaw: float = island[4]
			var p := Vector2(local.x*cos(yaw)-local.y*sin(yaw),local.x*sin(yaw)+local.y*cos(yaw))+Vector2(island[0],island[1])
			var h := _island_height(p,island)
			if h < SEA_LEVEL+1 or h > 7 or sin(a*3+island[5]) < .1 or _headland(a,int(island[5])) > .22: continue
			var s := rng.randf_range(2.0,5.5)
			for j in 3:
				var q := p+Vector2(cos(a+j)*s*.7,sin(a+j)*s*.7)
				_add_contact(q,s*.94,contacts)
				arena._static(crag,rock[j%2],Vector3(q.x,_island_height(q,island)+s*.12,q.y)+shift,Vector3(s,s*rng.randf_range(.5,.9),s*.75),Vector3(.12,a+j*.7,.08))

	# Concentrate geology and wind-pruned growth on the shores the camera passes.
	# The rest of the coast keeps its open coves; all instances reuse these meshes.
	var slate := _outcrop_material()
	var ledge := _slate_mesh()
	for seed in HEADLANDS:
		var island: Array = ISLANDS[seed]
		var shift := Style.island_offset(seed)
		var bearing := float(HEADLANDS[seed])
		var scale := clampf(float(island[3])/70.0,.62,1.45)
		for ledge_spec in [[-.24,.9,6.3],[-.06,.4,9.0],[.02,-1.4,6.0],[.27,-1.8,4.3],[-.36,-.8,3.4]]:
			var angle := bearing+float(ledge_spec[0])
			var point := _bank_point(island,angle,ledge_spec[1])
			var span := float(ledge_spec[2])*scale
			_add_contact(point,span*1.22,contacts)
			var pos := Vector3(point.x,_island_height(point,island)-span*.10,point.y)+shift
			# Offset and overlap a few bedrock plates; their toes enter the water.
			arena._static(ledge,slate,pos,Vector3(span,span*(.32+.10*cos(angle*16.0)),span*(.52+.18*sin(angle*14.0))),Vector3(.12*cos(angle*17.0), -angle-float(island[4])+1.1+sin(angle*21.0)*.46,-.12))
		for j in 15:
			var angle := bearing+float([-.24,-.06,.27][j%3])
			angle += rng.randf_range(-.045,.045)
			var point := _bank_point(island,angle,rng.randf_range(-2.8,.65))
			var span := rng.randf_range(.7,2.0)*scale
			arena._static(ledge,slate,Vector3(point.x,_island_height(point,island)-span*.12,point.y)+shift,Vector3(span,span*.55,span*.74),Vector3(.09,-angle+rng.randf_range(-.5,.5),.10))
		for grove in [[-.54,10.0,6.1],[-.43,13.0,7.4],[-.62,17.0,4.4],[.31,9.5,5.0],[.40,15.0,6.6]]:
			var angle := bearing+float(grove[0])
			var point := _bank_point(island,angle,grove[1])
			var foot := Vector3(point.x,_island_height(point,island)-.55,point.y)+shift
			var rooted := _supports_growth(point,island)
			var size := float(grove[2])*scale
			if rooted: _add_contact(point,size*.62,contacts)
			var inland := Vector3(float(island[0])-point.x,0,float(island[1])-point.y).normalized()
			var upright: bool = grove[0] < -.5 or grove[0] > .35
			inland = inland.rotated(Vector3.UP,sin(float(grove[0])*18.0)*.88)
			var fork := foot+Vector3.UP*size*(.39 if upright else .53)+inland*size*(.08 if upright else .29)
			if rooted: D.beam(arena,rod,trunk,foot-Vector3.UP*2.05,fork,size*.052)
			for j in 4:
				var side := inland.rotated(Vector3.UP,(-1.0 if j%2 == 0 else 1.0)*.9)
				var spread := (.23-j*.047) if upright else (.32+.082*j)
				var lift := (.05+j*.20) if upright else (.14+j*.075)
				var tip := fork+side*size*spread+Vector3.UP*size*lift
				if rooted: D.beam(arena,rod,trunk,fork,tip,size*.033)
				var shape := Vector3(.42-j*.076,.18,.36-j*.065) if upright else Vector3(.43,.19,.30)
				if rooted: arena._static(crown,leaves[j%3],tip,shape*size,Vector3(.10,-angle+j*.6,.12))
			for j in 3:
				var q := point+Vector2(rng.randf_range(-3.4,3.4),rng.randf_range(-2.4,3.5))
				var h := rng.randf_range(.65,1.7)*scale
				if _supports_growth(q,island): arena._static(brush,bushes[j%2],Vector3(q.x,_island_height(q,island)+h*.28,q.y)+shift,Vector3(h*1.45,h*.8,h),Vector3(0,angle,.08))


static func _bank_point(island: Array, angle: float, setback: float) -> Vector2:
	var radii := Vector2(island[2],island[3])
	var radial := _coast_radius(angle,int(island[5]))-setback/minf(radii.x,radii.y)
	return Vector2(island[0],island[1])+(Vector2.from_angle(angle)*radii*radial).rotated(island[4])


static func _slate_mesh() -> ArrayMesh:
	# Offset shelves and a sloping cap give a fractured headland profile.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rings := PackedVector3Array()
	for layer in [[-.85,.78],[-.32,1.0],[.17,.94],[.57,.77],[.69,.43]]:
		for j in 9:
			var a := TAU*j/9.0
			var r := float(layer[1])*(1.0+.15*sin(3*a+.2)+.09*cos(4*a))
			var x := cos(a)*r+float(layer[0])*.21
			var z := sin(a)*r
			rings.append(Vector3(x,float(layer[0])+.17*x+.08*z+.045*sin(a*3),z))
	for row in 4:
		for j in 9:
			var k := (j+1)%9
			for i in [row*9+j,row*9+k,(row+1)*9+k,row*9+j,(row+1)*9+k,(row+1)*9+j]: st.add_vertex(rings[i])
	for j in range(1,8):
		for i in [36,36+j,37+j]: st.add_vertex(rings[i])
	st.generate_normals()
	return st.commit()


static func _outcrop_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """shader_type spatial;
uniform sampler2D grain : repeat_enable, filter_linear_mipmap;
varying vec3 wp;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float fleck=texture(grain,wp.xz*.068).r;
 float break_up=texture(grain,wp.xz*.009).r;
 float bedding=texture(grain,vec2((wp.x+wp.z*.6)*.018,wp.y*.074+wp.x*.003+break_up*.22)).r;
 float cracks=(1.0-smoothstep(.02,.115,abs(bedding-.45)))*smoothstep(.41,.67,fleck);
 vec3 slate=mix(vec3(.105,.132,.131),vec3(.255,.257,.215),break_up);
 slate*=.85+fleck*.22+bedding*.095-cracks*.18;
 float dry=smoothstep(-4.52,-3.50,wp.y);
 ALBEDO=slate*mix(.62,1.0,dry);ROUGHNESS=mix(.56,.92,dry);SPECULAR=.24;
}"""
	mat.set_shader_parameter("grain",_land_noise)
	return mat


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
		var lobes := 1.0+.14*sin(a*3.0+y*1.8)+.09*cos(a*5.0-y*2.4)
		var center := normal*rng.randf_range(.61,1.0)*lobes
		var u := normal.cross(Vector3.UP if absf(y) < .9 else Vector3.RIGHT).normalized()
		var v := normal.cross(u).normalized()
		var size := rng.randf_range(.20,.32)
		var points := [center+u*size,center+v*size*.72,center-u*size,center-v*size*.72]
		st.set_color(Color.WHITE*rng.randf_range(.78,1.08))
		for j in 4:
			for p in [points[j],center+normal*.10,points[(j+1)%4]]: st.add_vertex(p)
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
instance uniform vec3 island_offset = vec3(0.0);
uniform sampler2D terrain_noise : repeat_enable, filter_linear_mipmap;
// A filtered texture avoids sin/hash precision discontinuities between the
// triangles of broad world-space terrain on Vulkan.
float noise(vec2 p){return texture(terrain_noise,p*.075).r;}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz-island_offset;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
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
 // Wind-reddened heath on exposed tops and sweeps of darker meadow break
 // up the hill at flyby scale. Fine grains fade before they turn to shimmer.
 float heath=smoothstep(.43,.72,meadow*.58+patch*.42+(1.0-wn.y)*.32);
 grass=mix(grass,vec3(.24,.205,.10),heath*.50);
 grass*=mix(.77,1.06,smoothstep(.25,.70,meadow*.65+patch*.35));
 vec3 stone=mix(vec3(.165,.190,.175),vec3(.345,.34,.275),n);
 vec3 sand=mix(vec3(.34,.315,.22),vec3(.56,.52,.36),n);
 float old_shore=1.0-smoothstep(-3.7,.15+(n-.5)*1.8,wp.y);
 float slope=1.0-clamp(wn.y,0.0,1.0);
 float cliff=smoothstep(.13,.42,slope);
 float exposed=max(COLOR.r,smoothstep(.45,.70,patch*.70+meadow*.30+slope*.48)*.78);
 float height=wp.y+4.5;
 float beach=1.0-smoothstep(.30,mix(3.4,.65,exposed),height);
 float bank=exposed*(1.0-smoothstep(2.1,9.0,height));
 float near_detail=1.0-smoothstep(60.0,240.0,length(CAMERA_POSITION_WORLD-(wp+island_offset)));
 float grain=noise(wp.xz*.52);
 // Weathered beds follow the face. A projection through height avoids the
 // vertical stretch of an XZ texture across a steep cliff.
 float strike=wp.x*.04-wp.z*.06+patch*2.4;
 float side=abs(wn.x)/(abs(wn.x)+abs(wn.z)+.001);
 float strata=mix(noise(vec2(wp.x*.14,wp.y*.47+strike)),noise(vec2(wp.z*.17,wp.y*.54+strike)),side);
 float fissure=(1.0-smoothstep(.015,.095,abs(strata-.46)))*smoothstep(.44,.68,patch+.15*(grain-.5));
 vec3 bank_stone=mix(vec3(.147,.169,.158),vec3(.35,.33,.265),strata);
 bank_stone*=.93+(grain-.5)*.10-fissure*.20*near_detail;
 vec3 dry_land=mix(grass,bank_stone,max(cliff,bank));
 dry_land=mix(dry_land,sand,beach*(1.0-exposed));
 dry_land*=1.0+(grain-.5)*near_detail*.17;
 float wash=1.0-smoothstep(.12,.95+(patch-.5)*.45,height);
 dry_land*=mix(1.0,.65,wash);
 dry_land*=1.0-COLOR.g*.19;
 // Keep the underwater sand and rocks used by the water's refraction.
 vec3 submerged=mix(mix(grass,stone,cliff*.85),sand,old_shore)*.90;
 ALBEDO=mix(submerged,dry_land,smoothstep(-.35,.14,height));
 ROUGHNESS=mix(.96,.62,wash);SPECULAR=.22;
 AO=1.0-COLOR.g*.36*smoothstep(.0,1.0,height);

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
