extends "res://tools/avatars/build_street_set.gd"
## Offline, additive CC0 derivatives. Does not write the accepted parts or source rigs.
const SPORT_DEST := "res://assets/avatars/sport/"

func run() -> void:
	DirAccess.make_dir_recursive_absolute(SPORT_DEST)
	var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	white = ImageTexture.create_from_image(image)
	var hair_only := "--hair-only" in OS.get_cmdline_user_args()
	for model in 2:
		var actor: Node3D = load("res://assets/avatars/vrm/"+PATHS[model]+".vrm").instantiate()
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(actor)
		var rig: Skeleton3D = actor.find_children("*","Skeleton3D",true,false)[0]
		if not hair_only:
			var body: ArrayMesh = load(OUTPUT+"body_%d_%d.res" % [model,2 if model == 0 else 3])
			var skin: Skin = load(OUTPUT+"skin_%d.res" % model)
			var suit := make_tracksuit(body,skin,rig,actor)
			save_sport(suit,"tracksuit_%d" % model)
		save_sport(make_swept_hair(model,actor,rig),"swept_hair_%d" % model)
		actor.queue_free()
	for frame in 3: await process_frame
	print("Sport hair: two resources prepared; tracksuits untouched" if hair_only else "Sport set: four new resources prepared; previous parts and source rigs untouched")
	quit()

func save_sport(mesh: ArrayMesh,name: String) -> void:
	assert(ResourceSaver.save(mesh,SPORT_DEST+name+".res",ResourceSaver.FLAG_COMPRESS)==OK)
	print(name," ",mesh.get_aabb()," surfaces=",mesh.get_surface_count())

func make_tracksuit(source: ArrayMesh,skin: Skin,rig: Skeleton3D,actor: Node3D) -> ArrayMesh:
	var output := ArrayMesh.new()
	var names: PackedStringArray = source.get_meta("surface_materials").duplicate()
	var overrides: Dictionary = source.get_meta("variant_materials").duplicate()
	var waist := skin.get_bind_pose(rig.find_bone("Hips")).affine_inverse().origin
	var neck := skin.get_bind_pose(rig.find_bone("Neck")).affine_inverse().origin
	var size := neck.y/1.59513
	var top: Array
	var pants: Array
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
			overrides[surface] = sports_material(cloth_template,Color("697f94"),"Sport_Tops_01_CLOTH")
			overrides[surface].set_shader_parameter("_MainTex",cloth_template.get_shader_parameter("_MainTex"))
			overrides[surface].set_shader_parameter("_ShadeTexture",cloth_template.get_shader_parameter("_ShadeTexture"))
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
			overrides[surface] = sports_material(part_material(source,surface),Color("495f73"),"Sport_Bottoms_01_CLOTH")
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)
	names.resize(output.get_surface_count())
	overrides.erase(source.get_surface_count()-1)
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Follow the actual retained source skin, including its broad shoulder skirt.
	# A high collar-only cut leaves the donor shoulder triangles exposed; this
	# extends well inside the jacket and retains their exact interpolated weights.
	for tri in triangle_polygons(source.surface_get_arrays(0)):
		var polygon := clip_neck(tri,neck.y-.23*size,true)
		polygon = clip_neck(polygon,neck.y+.015*size,false)
		append_polygon(trim,polygon,.008*size)
	# Face remains visible in the avatar and owns a second neck/chest skin layer.
	# Cover this exact layer too; its outline differs from the fitted donor body.
	for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		if not "Face" in str(mesh.name): continue
		var baked := cpu_bake(mesh,rig,rig)
		for surface in mesh.mesh.get_surface_count():
			if not "_SKIN" in mesh.mesh.surface_get_material(surface).resource_name: continue
			for tri in triangle_polygons(baked.surface_get_arrays(surface)):
				for v in tri:
					v.p = mesh.global_transform*v.p
					v.n = (mesh.global_transform.basis*v.n).normalized()
				var polygon := clip_neck(tri,neck.y-.23*size,true)
				polygon = clip_neck(polygon,neck.y+.015*size,false)
				append_polygon(trim,polygon,.008*size)
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
	# Clip real sleeve/pants triangles to narrow planes, interpolating all skin
	# weights at every edge. Contrasting stripes retain the actual curved cloth.
	var stripes := SurfaceTool.new()
	stripes.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1,1]:
		var prefix := "Left" if side == 1 else "Right"
		var shoulder := skin.get_bind_pose(rig.find_bone(prefix+"UpperArm")).affine_inverse().origin
		var hand := skin.get_bind_pose(rig.find_bone(prefix+"Hand")).affine_inverse().origin
		var slope: float = (hand.x-shoulder.x)*side/(shoulder.y-hand.y)
		for stripe in 2:
			var offset := (stripe-.5)*.014*size
			var value: float = shoulder.x*side+slope*shoulder.y+offset
			var sleeve_planes := [[Vector3(side,slope,0),value-.0045*size,true],[Vector3(side,slope,0),value+.0045*size,false],[Vector3.UP,hand.y+.009*size,true],[Vector3.UP,shoulder.y+.024*size,false],[Vector3.BACK,.022*size,true]]
			append_clipped(stripes,top,sleeve_planes,.0014*size)
			var leg_value := (.063+(stripe-.5)*.012)*size
			var leg_planes := [[Vector3(side,-.042,0),leg_value-.0036*size,true],[Vector3(side,-.042,0),leg_value+.0036*size,false],[Vector3.UP,.14*size,true],[Vector3.UP,waist.y-.015*size,false],[Vector3.BACK,.017*size,true]]
			append_clipped(stripes,pants,leg_planes,.0014*size)
	stripes.generate_normals()
	stripes.commit(output)
	names.append("Sport_Accent_CLOTH")
	overrides[output.get_surface_count()-1] = sports_material(cloth_template,Color("e8d4a1"),"Sport_Accent_CLOTH")
	for key in source.get_meta_list(): output.set_meta(key,source.get_meta(key))
	output.set_meta("surface_materials",names)
	output.set_meta("variant_materials",overrides)
	return output

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

func append_polygon(tool: SurfaceTool,polygon: Array,offset: float) -> void:
	if polygon.size() < 3: return
	for i in range(1,polygon.size()-1):
		for v in [polygon[0],polygon[i],polygon[i+1]]:
			put(tool,v.p+v.n*offset,v.b,v.w)

func append_clipped(tool: SurfaceTool,a: Array,planes: Array,offset: float) -> void:
	for tri in triangle_polygons(a):
		var polygon: Array = tri
		for plane in planes:
			polygon = clip_plane(polygon,plane[0],plane[1],plane[2])
			if polygon.is_empty(): break
		append_polygon(tool,polygon,offset)

func clip_plane(polygon: Array,normal: Vector3,d: float,above: bool) -> Array:
	# Reuse the exact interpolating neck clipper through an orthonormal change of
	# coordinates. Normals/positions are transformed back before mesh emission.
	if polygon.is_empty(): return []
	var axis := normal.normalized()
	var x := Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < .95 else Vector3.BACK
	x = (x-axis*x.dot(axis)).normalized()
	var basis := Basis(x,axis,x.cross(axis))
	var inverse := basis.transposed()
	var local := []
	for v in polygon:
		local.append({"p":inverse*v.p,"n":inverse*v.n,"b":v.b,"w":v.w})
	var result := clip_neck(local,d/normal.length(),above)
	for v in result:
		v.p = basis*v.p
		v.n = basis*v.n
	return result

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
