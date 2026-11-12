extends "res://tools/avatars/build_street_set.gd"
## Offline, additive CC0 derivatives. Does not write the accepted parts or source rigs.
const SPORT_DEST := "res://assets/avatars/sport/"
const SAKURADA_FABRIC := Color("526f88")
var sport_weave: Texture2D

func run() -> void:
	DirAccess.make_dir_recursive_absolute(SPORT_DEST)
	var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	white = ImageTexture.create_from_image(image)
	var hair_only := "--hair-only" in OS.get_cmdline_user_args()
	var sakurada_only := "--sakurada-costume" in OS.get_cmdline_user_args()
	var vita_only := "--vita-costume" in OS.get_cmdline_user_args()
	var costumes_only := sakurada_only or vita_only or "--costumes-only" in OS.get_cmdline_user_args()
	var models := [0] if sakurada_only else ([1] if vita_only else [0, 1])
	for model in models:
		var actor: Node3D = load("res://assets/avatars/vrm/"+PATHS[model]+".vrm").instantiate()
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(actor)
		var rig: Skeleton3D = actor.find_children("*","Skeleton3D",true,false)[0]
		if not hair_only:
			var body: ArrayMesh = load(OUTPUT+"body_%d_%d.res" % [model,2 if model == 0 else 3])
			var skin: Skin = load(OUTPUT+"skin_%d.res" % model)
			var suit := make_tracksuit(body,skin,rig,actor,model == 0)
			save_sport(suit,"tracksuit_%d" % model)
		if not costumes_only: save_sport(make_swept_hair(model,actor,rig),"swept_hair_%d" % model)
		actor.queue_free()
	for frame in 3: await process_frame
	print("Sakurada sports costume prepared" if sakurada_only else ("Sport hair prepared" if hair_only else ("Sport costumes prepared" if costumes_only else "Sport set prepared")))
	quit()

func save_sport(mesh: ArrayMesh,name: String) -> void:
	assert(ResourceSaver.save(mesh,SPORT_DEST+name+".res",ResourceSaver.FLAG_COMPRESS)==OK)
	print(name," ",mesh.get_aabb()," surfaces=",mesh.get_surface_count())

func make_tracksuit(source: ArrayMesh,skin: Skin,rig: Skeleton3D,actor: Node3D,sakurada: bool) -> ArrayMesh:
	var output := ArrayMesh.new()
	var names: PackedStringArray = source.get_meta("surface_materials").duplicate()
	var overrides: Dictionary = source.get_meta("variant_materials").duplicate()
	var waist := skin.get_bind_pose(rig.find_bone("Hips")).affine_inverse().origin
	var neck := skin.get_bind_pose(rig.find_bone("Neck")).affine_inverse().origin
	var size := neck.y/1.59513
	var top: Array
	var pants: Array
	var shoes: Array
	var cloth_template := part_material(source,1)
	# Discard the old short-hoodie collar/zip surface. Rebuild a sports collar and zip.
	for surface in source.get_surface_count()-1:
		var a := source.surface_get_arrays(surface)
		if "_SKIN" in names[surface]:
			a = hide_covered_skin(a,neck.y-.23*size,neck.y+.015*size)
		if "Tops_" in names[surface]:
			remove_hood_and_cords(a,neck.y,size)
			var shape := func(p: Vector3) -> Vector3:
				var torso := 1.0-smoothstep(.15*size,.22*size,absf(p.x))
				var q := p
				q.x *= 1.0-.075*torso
				q.z *= 1.0-.11*torso
				return q
			deform_arrays(a,shape)
			top = a
			# Append only to Tops; other surfaces never undergo an extra encode.
			var base := ArrayMesh.new()
			base.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)
			var collar := make_sport_collar(a,source.surface_get_arrays(0),rig,actor,neck,size)
			var joined := SurfaceTool.new()
			joined.begin(Mesh.PRIMITIVE_TRIANGLES)
			joined.append_from(base,0,Transform3D.IDENTITY)
			joined.append_from(collar,0,Transform3D.IDENTITY)
			a = joined.commit().surface_get_arrays(0)
			assert(a[Mesh.ARRAY_INDEX].size() == top[Mesh.ARRAY_INDEX].size()+120,"All forty collar triangles must be indexed")
			overrides[surface] = tracksuit_fabric(cloth_template,"Sport_Tops_01_CLOTH",sakurada)
		if "Bottoms_" in names[surface]:
			var shape := func(p: Vector3) -> Vector3:
				var q := p
				var lower := 1.0-smoothstep(.12*size,.88*size,p.y)
				var side := signf(p.x)
				var center := side*lerpf(.045,.067,clampf(p.y/(.85*size),0,1))*size
				q.x = center+(p.x-center)*(1.0-.24*lower)
				q.z *= 1.0-.15*lower
				return q
			deform_arrays(a,shape)
			pants = a
			overrides[surface] = tracksuit_fabric(cloth_template,"Sport_Bottoms_01_CLOTH",sakurada)
		if "Shoes_" in names[surface]:
			shoes = a.duplicate()
			deform_arrays(a, func(p: Vector3) -> Vector3:
				# Pull the old heel and leather welt inside the continuous sole.
				if p.y < .040 * size: p.y = .022 * size + .45 * p.y
				return p)
			names[surface] = "Sport_Shoes_Upper_CLOTH"
			overrides[surface] = sports_material(cloth_template,Color("344552"),"Sport_Shoes_Upper_CLOTH")
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)
	names.resize(output.get_surface_count())
	overrides.erase(source.get_surface_count()-1)
	if sakurada:
		add_sakurada_details(output,names,overrides,cloth_template,top,pants,shoes,skin,rig,waist,neck,size)
	else:
		add_vita_details(output,names,overrides,cloth_template,top,pants,shoes,skin,rig,waist,neck,size)
	for key in source.get_meta_list(): output.set_meta(key,source.get_meta(key))
	output.set_meta("surface_materials",names)
	output.set_meta("variant_materials",overrides)
	return output

func add_vita_details(output: ArrayMesh,names: PackedStringArray,overrides: Dictionary,cloth_template: ShaderMaterial,top: Array,pants: Array,shoes: Array,skin: Skin,rig: Skeleton3D,waist: Vector3,neck: Vector3,size: float) -> void:
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bottom := waist.y-.016*size
	for segment in 36:
		var y0 := lerpf(bottom,neck.y-.033*size,segment/36.0)
		var y1 := lerpf(bottom,neck.y-.033*size,(segment+1)/36.0)
		var p0 := Vector3(0,y0,front_at(top,y0,size)+.003*size)
		var p1 := Vector3(0,y1,front_at(top,y1,size)+.003*size)
		quad(trim,p0-Vector3.RIGHT*.0027*size,p0+Vector3.RIGHT*.0027*size,p1+Vector3.RIGHT*.0027*size,p1-Vector3.RIGHT*.0027*size,top)
	# Pocket openings are shallow welt geometry, not decals.
	for side in [-1,1]:
		var a := Vector3(side*.06*size,waist.y+.13*size,front_at(top,waist.y+.13*size,size)+.0025*size)
		var b := Vector3(side*.102*size,waist.y+.071*size,front_at(top,waist.y+.071*size,size)+.0025*size)
		quad(trim,a,b,b+Vector3.UP*.005*size,a+Vector3.UP*.005*size,top)
	trim.generate_normals()
	trim.commit(output)
	names.append("Sport_Trim_CLOTH")
	overrides[output.get_surface_count()-1] = sports_material(cloth_template,Color("4b6072"),"Sport_Trim_CLOTH")
	var jacket := triangle_polygons(top)
	var trousers := triangle_polygons(pants)
	var stripes := detail_surface()
	for side in [-1,1]:
		var prefix := "Left" if side == 1 else "Right"
		var shoulder := skin.get_bind_pose(rig.find_bone(prefix+"UpperArm")).affine_inverse().origin
		var hand := skin.get_bind_pose(rig.find_bone(prefix+"Hand")).affine_inverse().origin
		add_side_stripes(stripes, jacket, side, hand.y+.039*size, shoulder.y+.014*size, size)
		add_side_stripes(stripes, trousers, side, .155*size, waist.y-.071*size, size)
	save_detail(stripes,output,names,overrides,sports_material(cloth_template,Color("e8d4a1"),"Sport_Accent_CLOTH"))
	add_sport_trainers(detail_surface(),output,names,overrides,cloth_template,shoes,skin,rig,size)

func tracksuit_fabric(template: ShaderMaterial, name: String, sakurada: bool) -> ShaderMaterial:
	if not sakurada: return sports_material(template, Color("697f94"), name)
	if sport_weave == null:
		# Seamless greyscale knit on the existing UVs, shared by jacket and pants.
		var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y in image.get_height():
			for x in image.get_width():
				var u := TAU * x / image.get_width()
				var v := TAU * y / image.get_height()
				var weave := .019 * sin(64.0 * u) * sin(64.0 * v)
				var ribs := .012 * cos(43.0 * u + 37.0 * v)
				var variation := .008 * sin(7.0 * u - 11.0 * v) * cos(9.0 * u + 5.0 * v)
				var grey := .935 + weave + ribs + variation
				image.set_pixel(x, y, Color(grey, grey, grey))
		image.generate_mipmaps()
		sport_weave = ImageTexture.create_from_image(image)
	var material := sports_material(template, SAKURADA_FABRIC, name)
	material.set_shader_parameter("_MainTex", sport_weave)
	material.set_shader_parameter("_ShadeTexture", sport_weave)
	material.set_shader_parameter("_ShadeColor", SAKURADA_FABRIC.darkened(.40))
	material.set_shader_parameter("_ShadeToony", .32)
	return material

func detail_surface() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool

func save_detail(tool: SurfaceTool, output: ArrayMesh, names: PackedStringArray, overrides: Dictionary, material: ShaderMaterial) -> void:
	tool.index()
	tool.commit(output)
	names.append(material.resource_name)
	overrides[output.get_surface_count()-1] = material

func add_sakurada_details(output: ArrayMesh, names: PackedStringArray, overrides: Dictionary, template: ShaderMaterial, top: Array, pants: Array, shoes: Array, skin: Skin, rig: Skeleton3D, waist: Vector3, neck: Vector3, size: float) -> void:
	var jacket := triangle_polygons(top)
	var trousers := triangle_polygons(pants)
	var stripes := detail_surface()
	var welts := detail_surface()
	var hardware := detail_surface()
	for side in [-1, 1]:
		var prefix := "Left" if side == 1 else "Right"
		var shoulder := skin.get_bind_pose(rig.find_bone(prefix+"UpperArm")).affine_inverse().origin
		var hand := skin.get_bind_pose(rig.find_bone(prefix+"Hand")).affine_inverse().origin
		add_side_stripes(stripes, jacket, side, hand.y+.039*size, shoulder.y+.014*size, size)
		add_side_stripes(stripes, trousers, side, .155*size, waist.y-.071*size, size)
		var pocket_start := Vector2(side*.063*size, waist.y+.143*size)
		var pocket_end := Vector2(side*.113*size, waist.y+.079*size)
		project_strip(welts, jacket, pocket_start, pocket_end, .012*size, .0018*size)
		project_strip(hardware, jacket, pocket_start+Vector2.UP*.004*size, pocket_end+Vector2.UP*.004*size, .0028*size, .0025*size)
	var zip_start := Vector2(0, waist.y+.007*size)
	var zip_end := Vector2(0, neck.y-.054*size)
	project_strip(welts, jacket, zip_start, zip_end, .018*size, .0017*size)
	project_strip(hardware, jacket, zip_start, zip_end, .004*size, .0024*size)
	project_strip(hardware, jacket, zip_end-Vector2.UP*.004*size, zip_end-Vector2.UP*.030*size, .012*size, .0037*size)
	save_detail(welts,output,names,overrides,sports_material(template,Color("263747"),"Sport_Trim_CLOTH"))
	save_detail(stripes,output,names,overrides,sports_material(template,Color("9bb9c8"),"Sport_Accent_CLOTH"))
	add_sport_trainers(hardware,output,names,overrides,template,shoes,skin,rig,size)

func add_sport_trainers(hardware: SurfaceTool, output: ArrayMesh, names: PackedStringArray, overrides: Dictionary, template: ShaderMaterial, shoes: Array, skin: Skin, rig: Skeleton3D, size: float) -> void:
	var shoe_upper := triangle_polygons(shoes)
	var midsoles := detail_surface()
	var tread := detail_surface()
	for side in [-1, 1]:
		add_trainer_sole(midsoles, tread, shoes, side, size)
		var center := skin.get_bind_pose(rig.find_bone(("Left" if side == 1 else "Right")+"Foot")).affine_inverse().origin.x
		for lace in 4:
			var z := (.036 + lace*.014)*size
			project_strip(hardware, shoe_upper, Vector2(center-.020*size,z),Vector2(center+.020*size,z+.003*size),.004*size,.0022*size,true)
	save_detail(hardware,output,names,overrides,sports_material(template,Color("b8c8cd"),"Sport_Hardware"))
	save_detail(midsoles,output,names,overrides,sports_material(template,Color("bbc7cb"),"Sport_Trainer_Midsole"))
	save_detail(tread,output,names,overrides,sports_material(template,Color("212a34"),"Sport_Trainer_Tread"))

func add_side_stripes(tool: SurfaceTool, triangles: Array, side: int, bottom: float, top: float, size: float) -> void:
	var steps := ceili((top-bottom)/(.010*size))
	var seam := PackedFloat32Array()
	for station in steps+1:
		var y := lerpf(bottom,top,float(station)/steps)
		seam.append(outer_section_z(triangles, side, y))
	for offset in [-.006, .006]:
		var previous: Array[Dictionary] = []
		for station in steps+1:
			var y := lerpf(bottom,top,float(station)/steps)
			var center := (seam[maxi(0,station-1)]+2.0*seam[station]+seam[mini(station+1,steps)])*.25
			var ribbon: Array[Dictionary] = []
			for edge in [-.0036, .0036]:
				var origin := Vector3(side*size, y, center+(offset+edge)*size)
				var hit := sample_surface(triangles, origin, Vector3.LEFT*side)
				assert(not hit.is_empty(), "Lateral seam must follow the limb continuously")
				ribbon.append(hit)
			if not previous.is_empty(): put_sampled_quad(tool, previous[0], previous[1], ribbon[1], ribbon[0], .0016*size)
			previous = ribbon

func outer_section_z(triangles: Array, side: int, y: float) -> float:
	var outermost := -INF
	var z := 0.0
	for triangle in triangles:
		for i in 3:
			var a: Vector3 = triangle[i].p
			var b: Vector3 = triangle[(i+1)%3].p
			if (a.y < y) == (b.y < y): continue
			var point := a.lerp(b, (y-a.y)/(b.y-a.y))
			if side*point.x <= outermost: continue
			outermost = side*point.x
			z = point.z
	assert(outermost > 0.0, "Expected an outer limb cross-section")
	return z

func project_strip(tool: SurfaceTool, triangles: Array, start: Vector2, end: Vector2, width: float, lift: float, from_above: bool = false) -> void:
	var perpendicular := (end-start).orthogonal().normalized()*width*.5
	var steps := maxi(1, ceili(start.distance_to(end)/.011))
	var previous: Array[Dictionary] = []
	for station in steps+1:
		var center := start.lerp(end, float(station)/steps)
		var ribbon: Array[Dictionary] = []
		for edge in [-1, 1]:
			var point: Vector2 = center+edge*perpendicular
			var origin := Vector3(point.x, .35, point.y) if from_above else Vector3(point.x, point.y, .65)
			var hit := sample_surface(triangles, origin, Vector3.DOWN if from_above else Vector3.FORWARD)
			# A ray above the front neckline can otherwise hit the back of the collar.
			if not from_above and not hit.is_empty() and (hit.p.z < .035 or hit.n.z <= 0.0): hit = {}
			ribbon.append(hit)
		if not previous.is_empty() and not previous[0].is_empty() and not previous[1].is_empty() and not ribbon[0].is_empty() and not ribbon[1].is_empty():
			put_sampled_quad(tool,previous[0],previous[1],ribbon[1],ribbon[0],lift)
		previous = ribbon

func sample_surface(triangles: Array, origin: Vector3, direction: Vector3) -> Dictionary:
	var closest := INF
	var surface: Array = []
	var hit := Vector3.ZERO
	for triangle in triangles:
		var point: Variant = Geometry3D.ray_intersects_triangle(origin,direction,triangle[0].p,triangle[1].p,triangle[2].p)
		if point == null: continue
		var distance := origin.distance_squared_to(point)
		if distance >= closest: continue
		closest = distance
		surface = triangle
		hit = point
	if surface.is_empty(): return {}
	var bary := Geometry3D.get_triangle_barycentric_coords(hit,surface[0].p,surface[1].p,surface[2].p)
	var blend := surface_influences(surface, [bary.x,bary.y,bary.z])
	blend.p = hit
	blend.n = (surface[0].n*bary.x+surface[1].n*bary.y+surface[2].n*bary.z).normalized()
	return blend

func put_sampled_quad(tool: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary, d: Dictionary, lift: float) -> void:
	# Godot triangle winding is clockwise, measured against the sampled normal.
	var vertices := [a,c,b,a,d,c] if (b.p-a.p).cross(c.p-a.p).dot(a.n) > 0 else [a,b,c,a,c,d]
	for v in vertices:
		tool.set_normal(v.n)
		put(tool,v.p+v.n*lift,v.b,v.w)

func add_trainer_sole(midsole: SurfaceTool, tread: SurfaceTool, source: Array, side: int, size: float) -> void:
	var outline := PackedVector2Array()
	for vertex: Vector3 in source[Mesh.ARRAY_VERTEX]:
		if side*vertex.x > 0: outline.append(Vector2(vertex.x,vertex.z))
	var hull := Geometry2D.convex_hull(outline)
	var bounds := Rect2(hull[0],Vector2.ZERO)
	for point in hull: bounds = bounds.expand(point)
	var center := bounds.get_center()
	var layers := [[.0,.93],[.008,1.055],[.015,1.065],[.028,1.065],[.035,1.015]]
	for edge in hull.size()-1:
		for layer in layers.size()-1:
			var bottom: Array = layers[layer]
			var top: Array = layers[layer+1]
			var a := sole_point(hull[edge], center, bounds, bottom, size)
			var b := sole_point(hull[edge+1], center, bounds, bottom, size)
			var c := sole_point(hull[edge+1], center, bounds, top, size)
			var d := sole_point(hull[edge], center, bounds, top, size)
			var normal := (c-a).cross(b-a).normalized()
			var tool := tread if layer < 2 else midsole
			for p in [a,b,c,a,c,d]:
				tool.set_normal(normal)
				put_sole_vertex(tool,p,source,side,size)
		var a := sole_point(hull[edge], center, bounds, layers[0], size)
		var b := sole_point(hull[edge+1], center, bounds, layers[0], size)
		for p in [Vector3(center.x,0,center.y),b,a]:
			tread.set_normal(Vector3.DOWN)
			put_sole_vertex(tread,p,source,side,size)
		var upper_layer: Array = layers[-1]
		var inner := [.035, .77]
		a = sole_point(hull[edge], center, bounds, upper_layer, size)
		b = sole_point(hull[edge+1], center, bounds, upper_layer, size)
		var c := sole_point(hull[edge+1], center, bounds, inner, size)
		var d := sole_point(hull[edge], center, bounds, inner, size)
		for p in [a,c,b,a,d,c]:
			midsole.set_normal(Vector3.UP)
			put_sole_vertex(midsole,p,source,side,size)

func sole_point(point: Vector2, center: Vector2, bounds: Rect2, layer: Array, size: float) -> Vector3:
	var footprint := center+(point-center)*float(layer[1])
	var toe_spring := smoothstep(bounds.get_center().y,bounds.end.y,footprint.y)*.010*size
	return Vector3(footprint.x,float(layer[0])*size+toe_spring,footprint.y)

func put_sole_vertex(tool: SurfaceTool, point: Vector3, source: Array, side: int, size: float) -> void:
	var closest := 0
	var distance := INF
	var anchor := Vector3(point.x,.027*size,point.z)
	for i in source[Mesh.ARRAY_VERTEX].size():
		var vertex: Vector3 = source[Mesh.ARRAY_VERTEX][i]
		if side * vertex.x <= 0.0: continue
		var value := anchor.distance_squared_to(vertex)
		if value < distance:
			distance = value
			closest = i
	var stride: int = source[Mesh.ARRAY_BONES].size()/source[Mesh.ARRAY_VERTEX].size()
	var start := closest*stride
	put(tool,point,source[Mesh.ARRAY_BONES].slice(start,start+stride),source[Mesh.ARRAY_WEIGHTS].slice(start,start+stride))

func make_sport_collar(arrays: Array,skin_arrays: Array,rig: Skeleton3D,actor: Node3D,neck: Vector3,size: float) -> ArrayMesh:
	# Stitch garment geometry to the real opening, not a skin-shaped sheet.
	var positions: PackedVector3Array = arrays[0]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var welded: Dictionary = {}
	var representatives := PackedInt32Array()
	var remap := PackedInt32Array()
	for i in positions.size():
		var p := positions[i]
		var key := Vector3i(roundi(p.x*100000),roundi(p.y*100000),roundi(p.z*100000))
		if not welded.has(key): welded[key] = representatives.size(); representatives.append(i)
		remap.append(welded[key])
	var edges: Dictionary = {}
	for triangle in indices.size()/3:
		for corner in 3:
			var a: int = remap[indices[triangle*3+corner]]
			var b: int = remap[indices[triangle*3+(corner+1)%3]]
			var key := Vector2i(mini(a,b),maxi(a,b))
			edges[key] = edges.get(key,0)+1
	var adjacency: Dictionary = {}
	for edge in edges:
		if edges[edge] != 1: continue
		if not adjacency.has(edge.x): adjacency[edge.x] = []
		if not adjacency.has(edge.y): adjacency[edge.y] = []
		adjacency[edge.x].append(edge.y); adjacency[edge.y].append(edge.x)
	assert(adjacency.size() >= 12,"Jacket neckline needs a real boundary")
	var loop := PackedInt32Array()
	var start: int = adjacency.keys()[0]
	var previous := -1
	var current := start
	while loop.is_empty() or current != start:
		assert(adjacency[current].size() == 2,"Neckline must be a closed degree-two loop")
		loop.append(representatives[current])
		var next: int = adjacency[current][0] if adjacency[current][0] != previous else adjacency[current][1]
		previous = current; current = next
		assert(loop.size() <= adjacency.size(),"Neckline traversal must close")
	assert(loop.size() == adjacency.size(),"Only the neckline boundary is expected")
	var level := neck.y+.023*size
	var cross: Array = []
	add_skin_section(skin_arrays,level,Transform3D.IDENTITY,cross)
	for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		if not "Face" in str(mesh.name): continue
		var baked := cpu_bake(mesh,rig,rig)
		for slot in mesh.mesh.get_surface_count():
			if "_SKIN" in mesh.mesh.surface_get_material(slot).resource_name:
				add_skin_section(baked.surface_get_arrays(slot),level,mesh.global_transform,cross)
	var section := PackedVector2Array()
	var lookup: Dictionary = {}
	for v in cross:
		var point := Vector2(v.p.x,v.p.z)
		section.append(point); lookup[point] = v
	var hull := Geometry2D.convex_hull(section)
	assert(hull.size() >= 4,"Collar must enclose the actual Body and Face neck skin")
	var center := Vector2(neck.x,neck.z)
	var upper: Array = []
	for index in loop:
		var direction := (Vector2(positions[index].x,positions[index].z)-center).normalized()
		var radius := 0.0
		var attributes: Dictionary = {}
		for edge in hull.size()-1:
			var hit: Variant = Geometry2D.segment_intersects_segment(center,center+direction*.4*size,hull[edge],hull[edge+1])
			if hit != null and center.distance_to(hit) > radius:
				radius = center.distance_to(hit)
				var t := hull[edge].distance_to(hit)/hull[edge].distance_to(hull[edge+1])
				attributes = section_influences(lookup[hull[edge]],lookup[hull[edge+1]],t)
		assert(radius > .02*size,"Neck cross-section must intersect every collar direction")
		# Chords between section samples need clearance for the curved skin
		# between them and its posed interpolation (measured overlap <1.3 mm).
		var point := center+direction*(radius+.004*size)
		attributes.p = Vector3(point.x,level,point.y)
		upper.append(attributes)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stride: int = arrays[Mesh.ARRAY_BONES].size()/positions.size()
	for segment in loop.size():
		var next := (segment+1)%loop.size()
		for corners in [[Vector2i(segment,0),Vector2i(next,1),Vector2i(next,0)],[Vector2i(segment,0),Vector2i(segment,1),Vector2i(next,1)]]:
			var points: Array[Vector3] = []
			for corner in corners: points.append(positions[loop[corner.x]] if corner.y == 0 else upper[corner.x].p)
			var normal := (points[1]-points[0]).cross(points[2]-points[0]).normalized()
			var middle := (points[0]+points[1]+points[2])/3.0
			var radial := Vector3(middle.x-neck.x,0,middle.z-neck.z).normalized()
			if normal.dot(radial) < 0:
				corners.reverse(); points.reverse(); normal = -normal
			assert(normal.dot(radial) > 0,"Collar normals must face away from the neck")
			for i in 3:
				var corner: Vector2i = corners[i]
				var index: int = loop[corner.x]
				tool.set_normal(normal)
				tool.set_uv(Vector2(float(corner.x)/loop.size(),corner.y))
				if corner.y == 0:
					tool.set_bones(arrays[Mesh.ARRAY_BONES].slice(index*stride,(index+1)*stride))
					tool.set_weights(arrays[Mesh.ARRAY_WEIGHTS].slice(index*stride,(index+1)*stride))
				else:
					tool.set_bones(upper[corner.x].b)
					tool.set_weights(upper[corner.x].w)
				tool.add_vertex(points[i])
	tool.generate_tangents()
	# append_from must receive indexed geometry when the original Tops is indexed.
	tool.index()
	print("Sport collar: ",loop.size()," actual boundary vertices, ",cross.size()," Body/Face skin samples")
	return tool.commit()


func add_skin_section(arrays: Array,level: float,transform: Transform3D,result: Array) -> void:
	for triangle in triangle_polygons(arrays):
		for v in triangle: v.p = transform*v.p
		for v in clip_neck(triangle,level,true):
			if absf(v.p.y-level) < .000001: result.append(v)

func section_influences(a: Dictionary,b: Dictionary,t: float) -> Dictionary:
	return surface_influences([a,b],[1.0-t,t])

func surface_influences(vertices: Array, factors: Array) -> Dictionary:
	var influences: Dictionary = {}
	for i in vertices.size():
		for k in vertices[i].b.size():
			var bone: int = vertices[i].b[k]
			influences[bone] = influences.get(bone,0.0)+vertices[i].w[k]*maxf(0.0,factors[i])
	var order := influences.keys()
	order.sort_custom(func(x: int,y: int) -> bool: return influences[x] > influences[y])
	var bones := PackedInt32Array([0,0,0,0])
	var weights := PackedFloat32Array([0,0,0,0])
	var total := 0.0
	for k in mini(4,order.size()):
		bones[k] = order[k]; weights[k] = influences[order[k]]; total += weights[k]
	for k in 4: weights[k] /= maxf(total,.00001)
	return {"b":bones,"w":weights}


func sports_material(template: ShaderMaterial,color: Color,name: String) -> ShaderMaterial:
	var material := plain_material(template,color,name)
	material.set_shader_parameter("_BumpScale",0.0)
	material.set_shader_parameter("_ShadeToony",.55)
	material.set_shader_parameter("_ShadeShift",-.15)
	material.set_shader_parameter("_MatcapColor",Color(.035,.035,.035,1))
	return material

func triangle_polygons(a: Array) -> Array:
	var output := []
	var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var stride: int = a[Mesh.ARRAY_BONES].size()/a[0].size()
	for triangle in indices.size()/3:
		var polygon := []
		for k in 3:
			var i := indices[triangle*3+k]
			polygon.append({"p":a[0][i],"n":a[1][i],"b":a[Mesh.ARRAY_BONES].slice(i*stride,(i+1)*stride),"w":a[Mesh.ARRAY_WEIGHTS].slice(i*stride,(i+1)*stride)})
		output.append(polygon)
	return output

func make_swept_hair(model: int,actor: Node3D,rig: Skeleton3D) -> ArrayMesh:
	# The accepted HairSample_Male has coherent front/side/back layered locks.
	# Preserve authored strand topology/UV and material passes; derive a local
	# brighter diffuse below while retaining the strand texture detail and alpha.
	var source: ArrayMesh = load(OUTPUT+"hair_%d_2.res" % model)
	var size := source.get_aabb().size.x/.269615
	var shape := func(p: Vector3) -> Vector3:
		var q := p
		var front := smoothstep(.0*size,.075*size,p.z)
		var low := 1.0-smoothstep(.070*size,.175*size,p.y)
		var temple := smoothstep(.065*size,.11*size,absf(p.x))
		var nape := 1.0-smoothstep(-.10*size,-.035*size,p.z)
		# Short diagonal fringe, with the existing irregular tips and overlapping
		# locks. Sideburns and nape stop above the old long tips.
		q.x += .029*size*front*low
		q.y += .045*size*front*low+.016*size*temple*low+.019*size*nape*low
		q.z += .006*size*nape*low-.006*size*front*low
		# The fitted sports donor skull is a little taller than the target face.
		# Lift the whole crown smoothly, then flatten only the thin ahoge outlier;
		# this preserves scalp clearance without a new visible cap or tall tuft.
		q.y += .027*size*smoothstep(.085*size,.170*size,p.y)
		q.y -= .035*size*smoothstep(.215*size,.260*size,p.y)
		return q
	var output := deform_mesh(source,shape)
	var template := part_material(source,0)
	prepare_sport_hair_textures(template)
	var material := template.duplicate(false) as ShaderMaterial
	material.resource_name = "Sport_Layered_HAIR"
	material.set_shader_parameter("_MainTex",sport_hair_texture)
	material.set_shader_parameter("_ShadeTexture",sport_hair_texture)
	material.set_shader_parameter("_Color",Color.WHITE)
	material.set_shader_parameter("_ShadeColor",Color(.72,.72,.72,1))
	var under_material := material.duplicate(false) as ShaderMaterial
	under_material.resource_name = "Sport_Underlayer_HAIR"
	under_material.next_pass = null
	under_material.set_shader_parameter("_MainTex",sport_hair_opaque)
	under_material.set_shader_parameter("_ShadeTexture",sport_hair_opaque)
	under_material.set_shader_parameter("_BumpScale",0.0)
	add_rear_underlayer(output,model,actor,rig)
	output.set_meta("surface_materials",PackedStringArray(["Sport_Layered_HAIR","Sport_Underlayer_HAIR"]))
	output.set_meta("variant_materials",{0:material,1:under_material})
	return output

var sport_hair_texture: ImageTexture
var sport_hair_opaque: ImageTexture

func prepare_sport_hair_textures(template: ShaderMaterial) -> void:
	if sport_hair_texture != null: return
	# Local derivative only: preserve authored fibre contrast and alpha, lift the
	# dark donor diffuse so the existing value-preserving palette can show silver.
	var original: Image = template.get_shader_parameter("_MainTex").get_image()
	if original.is_compressed(): original.decompress()
	original.convert(Image.FORMAT_RGBA8)
	var diffuse := original.duplicate()
	var opaque := original.duplicate()
	for y in original.get_height():
		for x in original.get_width():
			var pixel := original.get_pixel(x,y)
			var value := maxf(pixel.r,maxf(pixel.g,pixel.b))
			var brightness := .32+.68*sqrt(value)
			var color := Color(brightness,brightness*.72,brightness*.53,pixel.a)
			diffuse.set_pixel(x,y,color)
			color.a = 1.0
			opaque.set_pixel(x,y,color)
	sport_hair_texture = ImageTexture.create_from_image(diffuse)
	sport_hair_opaque = ImageTexture.create_from_image(opaque)

func add_rear_underlayer(output: ArrayMesh,model: int,actor: Node3D,rig: Skeleton3D) -> void:
	# Short rear/temple roots close the donor's open V-shaped back underneath the
	# authored locks. The frontal edge remains high under the fringe, never across
	# the forehead. This is a textured support layer, not the visible hairstyle.
	var head_inverse := (rig.global_transform*rig.get_bone_global_pose(rig.find_bone("Head"))).affine_inverse()
	var skull := []
	var top := -INF
	for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		if not ("Face" in str(mesh.name) or "Body" in str(mesh.name)): continue
		var baked := cpu_bake(mesh,rig)
		var local := head_inverse*mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			if not "_SKIN" in mesh.mesh.surface_get_material(surface).resource_name: continue
			var arrays := baked.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for t in indices.size()/3:
				var triangle := PackedVector3Array()
				for k in 3:
					var p: Vector3 = local*arrays[0][indices[t*3+k]]
					top = maxf(top,p.y)
					triangle.append(p)
				skull.append(triangle)
	var body_paths := []
	for outfit in (4 if model == 0 else 5): body_paths.append(OUTPUT+"body_%d_%d.res" % [model,outfit])
	body_paths.append("res://assets/avatars/itch/parts/body_%d.res" % model)
	for path in body_paths:
		var body: ArrayMesh = load(path)
		var names: PackedStringArray = body.get_meta("surface_materials")
		for surface in body.get_surface_count():
			if not "_SKIN" in names[surface]: continue
			var arrays := body.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for t in indices.size()/3:
				var triangle := PackedVector3Array()
				for k in 3:
					var p: Vector3 = head_inverse*arrays[0][indices[t*3+k]]
					top = maxf(top,p.y)
					triangle.append(p)
				skull.append(triangle)
	var size := output.get_aabb().size.x/.28035
	skull = skull.filter(func(t: PackedVector3Array) -> bool: return (t[0].y+t[1].y+t[2].y)/3.0 > top-.26*size)
	var center := Vector3(0,top-.117*size,-.016*size)
	var grid := []
	for row in 29:
		var line := PackedVector3Array()
		for segment in 73:
			var phi := TAU*segment/72.0
			var front := smoothstep(.1,.7,sin(phi))
			var rear := smoothstep(.12,.8,-sin(phi))
			var theta := row/28.0*lerpf(lerpf(1.85,2.80,rear),.78,front)
			var direction := Vector3(sin(theta)*cos(phi),cos(theta),sin(theta)*sin(phi))
			var radius := 0.0
			for tri in skull:
				var hit = Geometry3D.ray_intersects_triangle(center,direction,tri[0],tri[1],tri[2])
				if hit != null: radius = maxf(radius,(hit-center).length())
			if radius < .025*size: radius = 1.0/sqrt(pow(direction.x/(.108*size),2)+pow(direction.y/(.12*size),2)+pow(direction.z/(.117*size),2))
			line.append(center+direction*(radius+.014*size))
		grid.append(line)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 28:
		for segment in 72:
			for c in [Vector2i(row,segment),Vector2i(row+1,segment),Vector2i(row+1,segment+1),Vector2i(row,segment),Vector2i(row+1,segment+1),Vector2i(row,segment+1)]:
				tool.set_uv(Vector2(c.y/72.0,c.x/28.0))
				tool.add_vertex(grid[c.x][c.y])
	tool.generate_normals()
	tool.commit(output)

func hide_covered_skin(a: Array,lower: float,upper: float) -> Array:
	# Clip the covered skin band exactly, rather than deleting intersected whole
	# triangles (which would leave saw-toothed edges around the visible neck).
	var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	var stride: int = bones.size()/vertices.size()
	for triangle in indices.size()/3:
		var tri := []
		var original := []
		for k in 3:
			var index := indices[triangle*3+k]
			original.append(index)
			tri.append({"p":vertices[index],"n":normals[index],"b":bones.slice(index*stride,(index+1)*stride),"w":weights.slice(index*stride,(index+1)*stride)})
		if (tri[0].p.y >= upper and tri[1].p.y >= upper and tri[2].p.y >= upper) or (tri[0].p.y <= lower and tri[1].p.y <= lower and tri[2].p.y <= lower):
			kept.append_array(PackedInt32Array(original))
			continue
		for polygon in [clip_neck(tri,lower,false),clip_neck(tri,upper,true)]:
			if polygon.size() < 3: continue
			var added := []
			for v in polygon:
				var bary := Geometry3D.get_triangle_barycentric_coords(v.p,tri[0].p,tri[1].p,tri[2].p)
				var new_uv := Vector2.ZERO
				var new_tangent := Vector3.ZERO
				for k in 3:
					new_uv += uv[original[k]]*bary[k]
					if not tangents.is_empty(): new_tangent += Vector3(tangents[original[k]*4],tangents[original[k]*4+1],tangents[original[k]*4+2])*bary[k]
				added.append(vertices.size())
				vertices.append(v.p)
				normals.append(v.n)
				uv.append(new_uv)
				bones.append_array(v.b)
				weights.append_array(v.w)
				if not tangents.is_empty():
					new_tangent = new_tangent.normalized()
					tangents.append_array(PackedFloat32Array([new_tangent.x,new_tangent.y,new_tangent.z,tangents[original[0]*4+3]]))
			for k in range(1,added.size()-1): kept.append_array(PackedInt32Array([added[0],added[k],added[k+1]]))
	a[Mesh.ARRAY_VERTEX] = vertices
	a[Mesh.ARRAY_NORMAL] = normals
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_TANGENT] = tangents
	a[Mesh.ARRAY_BONES] = bones
	a[Mesh.ARRAY_WEIGHTS] = weights
	a[Mesh.ARRAY_INDEX] = kept
	return a
