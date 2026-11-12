extends "res://tools/avatars/build_wardrobe_variants.gd"
## Offline additions only: accepted meshes, UVs, weights and source VRMs stay intact.
const DEST := "res://assets/avatars/street/"

func run() -> void:
	DirAccess.make_dir_recursive_absolute(DEST)
	var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	white = ImageTexture.create_from_image(image)
	var bomber_only := "--bomber-only" in OS.get_cmdline_user_args()
	var models: Array[int] = [0,1]
	if "--male-only" in OS.get_cmdline_user_args(): models.resize(1)
	for model in models:
		var body: ArrayMesh = load(OUTPUT+"body_%d_%d.res" % [model,2 if model == 0 else 3])
		var skin: Skin = load(OUTPUT+"skin_%d.res" % model)
		var actor: Node3D = load("res://assets/avatars/vrm/"+PATHS[model]+".vrm").instantiate()
		root.add_child(actor)
		var rig: Skeleton3D = actor.find_children("*","Skeleton3D",true,false)[0]
		var hip := rig.find_bone("Hips")
		var waist := skin.get_bind_pose(hip).affine_inverse().origin
		var size := rig.get_bone_global_rest(rig.find_bone("Neck")).origin.y/1.59513
		var target_body: ArrayMesh = load(OUTPUT+"body_%d_%d.res" % [model,1 if model == 0 else 0])
		var bomber := make_bomber(body,waist,size,rig,target_body,model)
		save_part(bomber,"bomber_%d" % model)
		if not bomber_only:
			save_part(make_case(waist,size,hip,part_material(body,1)),"case_%d" % model)
			save_part(make_ponytail(model,actor,rig),"ponytail_%d" % model)
		actor.queue_free()
	for frame in 3: await process_frame
	print("Street bombers: %d resource(s) prepared; hair/case untouched" % models.size() if bomber_only else "Street set: six new resources prepared; previous parts untouched")
	quit()

func save_part(mesh: ArrayMesh,name: String) -> void:
	assert(ResourceSaver.save(mesh,DEST+name+".res",ResourceSaver.FLAG_COMPRESS)==OK)
	print(name," ",mesh.get_aabb())

func make_bomber(source: ArrayMesh,waist: Vector3,size: float,rig: Skeleton3D,target_body: ArrayMesh,model: int) -> ArrayMesh:
	var neck_y := rig.get_bone_global_rest(rig.find_bone("Neck")).origin.y
	var output := ArrayMesh.new()
	var names: PackedStringArray = source.get_meta("surface_materials").duplicate()
	var overrides: Dictionary = source.get_meta("variant_materials").duplicate()
	var top: Array
	for surface in source.get_surface_count():
		var a := source.surface_get_arrays(surface)
		if surface == 0 and model == 0:
			a = restore_donor_neck(a,target_body.surface_get_arrays(0),neck_y,size)
		if surface == 0: trim_bomber_shoulders(a, neck_y, size)
		if "Tops_" in names[surface]:
			var shape := func(p: Vector3) -> Vector3:
				var q := p
				# Torso volume only. The accepted cuffs and hands lie outside this region.
				var torso := 1.0-smoothstep(.16*size,.22*size,absf(p.x))
				var puff := sin(PI*clampf((p.y-waist.y+.04*size)/(.43*size),0,1))*torso
				q.x *= 1.0+.10*puff
				q.z *= 1.0+.13*puff
				return q
			deform_arrays(a,shape)
			remove_hood_and_cords(a,neck_y,size)
			top = a
			var mat := part_material(source,surface).duplicate(false) as ShaderMaterial
			mat.resource_name = "Street_Tops_01_CLOTH"
			mat.set_shader_parameter("_BumpScale",0.0)
			mat.set_shader_parameter("_Color",Color("536e66"))
			mat.set_shader_parameter("_ShadeColor",Color("354b48"))
			overrides[surface] = mat
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)
	# Merge new pocket welts and hem into the existing trim surface.
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The donor's high cylindrical collar floats inside this wider bomber neck.
	# Keep its lower zipper, not the collar or exposed upper zipper segment.
	var donor_trim := source.surface_get_arrays(source.get_surface_count()-1)
	for polygon in skin_polygons(donor_trim):
		polygon = clip_neck(polygon,neck_y-.13*size,false)
		emit_polygon(trim,polygon,0.0,false)
	var low := INF
	for p in top[0]:
		if absf(p.x) < .17*size: low = minf(low,p.y)
	for segment in 64:
		var phi := TAU*segment/64.0
		var next := TAU*(segment+1)/64.0
		var a := Vector3(cos(phi)*.141*size,low+.010*size,sin(phi)*.100*size)
		var b := Vector3(cos(next)*.141*size,low+.010*size,sin(next)*.100*size)
		quad(trim,a,a+Vector3.UP*.037*size,b+Vector3.UP*.037*size,b,top)
	for side in [-1,1]:
		var y := waist.y+.10*size
		var z := front_at(top,y,size)+.006*size
		var a := Vector3(side*.055*size,y+.035*size,z)
		var b := Vector3(side*.105*size,y-.020*size,z-.008*size)
		quad(trim,a,b,b+Vector3.UP*.009*size,a+Vector3.UP*.009*size,top)
	# The original Face and retained body already provide textured neck skin.
	# A duplicate skin shell in this CLOTH surface covered it with a dark jagged
	# bib. Keep only the actual collar/zip/pocket/hem geometry in this material.
	trim.generate_normals()
	var merged := trim.commit()
	output.surface_remove(output.get_surface_count()-1)
	output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,merged.surface_get_arrays(0))
	for key in source.get_meta_list(): output.set_meta(key,source.get_meta(key))
	# Female uses its own target neck lining. Male already restored the exact
	# donor triangles in surface0, sharing the existing UV/material/skin owner.
	if model != 0:
		var lining := SurfaceTool.new()
		lining.begin(Mesh.PRIMITIVE_TRIANGLES)
		for polygon in skin_polygons(target_body.surface_get_arrays(0)):
			# Follow the opening across the clavicles and stop before the painted chest.
			var bottom := neck_y-.135*size
			polygon = clip_neck(polygon,bottom,true,Vector3(-.62,1.0,0.0))
			polygon = clip_neck(polygon,bottom,true,Vector3(.62,1.0,0.0))
			polygon = clip_neck(polygon,neck_y-.012*size,false)
			emit_polygon(lining,polygon,-.0008*size,true)
		lining.generate_tangents()
		lining.commit(output)
		var skin_material := part_material(target_body,0)
		names.append(skin_material.resource_name)
		overrides[output.get_surface_count()-1] = skin_material
	output.set_meta("surface_materials",names)
	output.set_meta("variant_materials",overrides)
	return output


func trim_bomber_shoulders(arrays: Array, neck_y: float, size: float) -> void:
	# The sleeve covers this skin in every pose. During the throw it moves past
	# the fabric, so omit the hidden triangles and leave the cuff and neckline.
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var visible := PackedInt32Array()
	var lower := neck_y - .27 * size
	var upper := neck_y - .086 * size
	var inner_edge := .121 * size
	for i in range(0, indices.size(), 3):
		var center := (points[indices[i]] + points[indices[i+1]] + points[indices[i+2]]) / 3.0
		if center.y > lower and center.y < upper and absf(center.x) > inner_edge:
			continue
		visible.append_array(indices.slice(i, i+3))
	arrays[Mesh.ARRAY_INDEX] = visible


func restore_donor_neck(retained: Array,donor: Array,neck_y: float,size: float) -> Array:
	# garment() only removed INDEX entries from this exact donor body. Restore
	# missing upper-chest triangles, never a second surface or another UV chart.
	for attribute in Mesh.ARRAY_MAX:
		if attribute not in [Mesh.ARRAY_INDEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT]:
			assert(retained[attribute] == donor[attribute],"Donor skin position/UV/bone/weight attributes must match retained skin")
	var indices: PackedInt32Array = retained[Mesh.ARRAY_INDEX].duplicate()
	var present: Dictionary = {}
	for triangle in indices.size()/3:
		present[Vector3i(indices[triangle*3],indices[triangle*3+1],indices[triangle*3+2])] = true
	var original: PackedInt32Array = donor[Mesh.ARRAY_INDEX]
	var restored := 0
	for triangle in original.size()/3:
		var key := Vector3i(original[triangle*3],original[triangle*3+1],original[triangle*3+2])
		if present.has(key): continue
		var lowest := minf(donor[0][key.x].y,minf(donor[0][key.y].y,donor[0][key.z].y))
		# Keep the donor skin inside the neckline, including under its lower edge.
		var center: Vector3 = (donor[0][key.x]+donor[0][key.y]+donor[0][key.z])/3.0
		if center.y < neck_y-.142*size + .62*absf(center.x) or lowest > neck_y+.025*size: continue
		indices.append_array(PackedInt32Array([key.x,key.y,key.z]))
		present[key] = true
		restored += 1
	retained[Mesh.ARRAY_INDEX] = indices
	print("Restored matching donor neck triangles: ",restored)
	return retained


func skin_polygons(arrays: Array) -> Array:
	var polygons: Array = []
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for i in arrays[0].size(): indices.append(i)
	var stride: int = arrays[Mesh.ARRAY_BONES].size()/arrays[0].size()
	for triangle in indices.size()/3:
		var polygon: Array = []
		for corner in 3:
			var i: int = indices[triangle*3+corner]
			polygon.append({"p":arrays[0][i],"n":arrays[1][i],"uv":arrays[Mesh.ARRAY_TEX_UV][i],"b":arrays[Mesh.ARRAY_BONES].slice(i*stride,(i+1)*stride),"w":arrays[Mesh.ARRAY_WEIGHTS].slice(i*stride,(i+1)*stride)})
		polygons.append(polygon)
	return polygons


func emit_polygon(tool: SurfaceTool,polygon: Array,offset: float,textured: bool) -> void:
	if polygon.size() < 3: return
	for i in range(1,polygon.size()-1):
		for vertex in [polygon[0],polygon[i],polygon[i+1]]:
			tool.set_bones(vertex.b)
			tool.set_weights(vertex.w)
			tool.set_uv(vertex.uv if textured else Vector2(.5,.5))
			tool.set_normal(vertex.n)
			tool.add_vertex(vertex.p+vertex.n*offset)


func make_ponytail(model: int,actor: Node3D,rig: Skeleton3D) -> ArrayMesh:
	var base: ArrayMesh = load(OUTPUT+"hair_%d_0.res" % model)
	var output := ArrayMesh.new()
	var material := plain_material(part_material(base,0),Color("393442"),"Street_HAIR")
	material.set_shader_parameter("_MatcapColor",Color(.07,.07,.07,1))
	material.set_shader_parameter("_BumpScale",0.0)
	material.set_shader_parameter("_ShadeToony",.65)
	var overrides := {}
	var names := PackedStringArray()
	var scalp := SurfaceTool.new()
	scalp.begin(Mesh.PRIMITIVE_TRIANGLES)
	for surface in base.get_surface_count(): scalp.append_from(base,surface,Transform3D.IDENTITY)
	scalp.commit(output)
	overrides[0] = material
	names.append("Street_HAIR")
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var scale := base.get_aabb().size.x/.25
	var crown := base.get_aabb().end.y
	# Nine closed, tapered locks fan from a high tie and clear the collar behind.
	for lock in 9:
		var angle := TAU*lock/9.0
		for row in 24:
			for segment in 10:
				var corners := [Vector2i(row,segment),Vector2i(row+1,segment),Vector2i(row+1,segment+1),Vector2i(row,segment),Vector2i(row+1,segment+1),Vector2i(row,segment+1)]
				for corner in corners:
					var t: float = corner.x/24.0
					var phi: float = TAU*corner.y/10.0
					var radius := (.014+.009*sin(PI*t))*pow(1.0-t,.6)+.0002
					var spread := .018+.032*sin(PI*t)
					var center := Vector3(cos(angle)*spread,crown-.055+.09*sin(PI*t)-.32*t,-.105-.19*sin(PI*t*.65))
					center.y += sin(angle)*spread
					center.x += .035*sin(PI*t)*t
					var p := center+Vector3(cos(phi)*radius,0,sin(phi)*radius)
					p.x *= scale
					p.z *= scale
					tool.set_uv(Vector2(corner.y/10.0,t))
					tool.add_vertex(p)
	tool.generate_normals()
	tool.commit(output)
	overrides[output.get_surface_count()-1] = material
	names.append("Street_HAIR")
	# Cover seams with the target's own skull surface, offset beneath the outer locks.
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head_inv := (rig.global_transform*rig.get_bone_global_pose(rig.find_bone("Head"))).affine_inverse()
	var head_top := -INF
	var face_mesh: MeshInstance3D
	for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		if "Face" in str(mesh.name): face_mesh = mesh
	head_top = (head_inv*face_mesh.global_transform*face_mesh.get_aabb()).end.y
	for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		if not ("Face" in str(mesh.name) or "Body" in str(mesh.name)): continue
		var baked := cpu_bake(mesh,rig)
		var local := head_inv*mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			if not "_SKIN" in mesh.mesh.surface_get_material(surface).resource_name: continue
			var a := baked.surface_get_arrays(surface)
			var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			for t in indices.size()/3:
				var center := Vector3.ZERO
				for k in 3: center += local*a[0][indices[t*3+k]]/3.0
				var front := smoothstep(.015,.065,center.z)
				if center.y < head_top-lerpf(.14,.09,front): continue
				for k in 3:
					var i := indices[t*3+k]
					cap.set_uv(Vector2(.5,.5))
					cap.add_vertex(local*a[0][i]+(local.basis*a[1][i]).normalized()*.003)
	cap.generate_normals()
	cap.commit(output)
	overrides[output.get_surface_count()-1] = material
	names.append("Street_HAIR")
	output.set_meta("part_source",0)
	output.set_meta("surface_materials",names)
	output.set_meta("variant_materials",overrides)
	return output

func make_case(waist: Vector3,size: float,bone: int,template: ShaderMaterial) -> ArrayMesh:
	var output := ArrayMesh.new()
	var center := Vector3(-.191*size,waist.y-.055*size,.018*size)
	var housing := CapsuleMesh.new()
	housing.radius = .043*size
	housing.height = .185*size
	housing.radial_segments = 16
	housing.rings = 4
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	frame.append_from(housing,0,Transform3D(Basis.from_scale(Vector3(1,1,.75)),center))
	var box := BoxMesh.new()
	box.size = Vector3(.05,.026,.035)*size
	frame.append_from(box,0,Transform3D(Basis.IDENTITY,center+Vector3(.030,.060,-.012)*size))
	append_rigid(output,frame.commit(),bone)
	var lenses := SurfaceTool.new()
	lenses.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 3:
		var sphere := SphereMesh.new()
		sphere.radius = .021*size
		sphere.height = .042*size
		sphere.radial_segments = 16
		sphere.rings = 8
		lenses.append_from(sphere,0,Transform3D(Basis.from_scale(Vector3(1,1,.6)),center+Vector3(0,(index-1)*.052,.031)*size))
	append_rigid(output,lenses.commit(),bone)
	output.set_meta("part_source",0)
	output.set_meta("surface_materials",PackedStringArray(["Street_Case_CLOTH","Street_CaseAccent_CLOTH"]))
	output.set_meta("variant_materials",{0:plain_material(template,Color("222d38"),"Street_Case_CLOTH"),1:plain_material(template,Color("d8af65"),"Street_CaseAccent_CLOTH")})
	return output

func append_rigid(output: ArrayMesh,source: ArrayMesh,bone: int) -> void:
	var a := source.surface_get_arrays(0)
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for v in a[0].size():
		bones.append_array(PackedInt32Array([bone,0,0,0]))
		weights.append_array(PackedFloat32Array([1,0,0,0]))
	a[Mesh.ARRAY_BONES] = bones
	a[Mesh.ARRAY_WEIGHTS] = weights
	output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)

func remove_hood_and_cords(a: Array,neck_y: float,size: float) -> void:
	# UV seams split the hood and drawstrings from torso/sleeves. Classify islands
	# geometrically, retaining sleeve islands and their original weights.
	var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var parent := PackedInt32Array()
	for i in vertices.size(): parent.append(i)
	for t in indices.size()/3:
		for k in 2:
			parent[island_root(parent,indices[t*3+k])] = island_root(parent,indices[t*3+k+1])
	var bounds := {}
	for index in indices:
		var id := island_root(parent,index)
		if not bounds.has(id): bounds[id] = AABB(vertices[index],Vector3.ZERO)
		bounds[id] = bounds[id].expand(vertices[index])
	var kept := PackedInt32Array()
	for t in indices.size()/3:
		var b: AABB = bounds[island_root(parent,indices[t*3])]
		var hood := b.position.y > neck_y-.12*size
		var cord := b.size.x < .035*size and b.end.y > neck_y-.06*size
		if not hood and not cord:
			for k in 3: kept.append(indices[t*3+k])
	a[Mesh.ARRAY_INDEX] = kept

func island_root(parent: PackedInt32Array,index: int) -> int:
	while parent[index] != index: index = parent[index]
	return index

var source_materials: Dictionary = {}
func part_material(part: Mesh,surface: int) -> ShaderMaterial:
	var overrides: Dictionary = part.get_meta("variant_materials",{})
	if overrides.has(surface): return overrides[surface]
	var source: int = part.get_meta("surface_sources",{}).get(surface,part.get_meta("part_source"))
	if not source_materials.has(source):
		var actor: Node3D = load("res://assets/avatars/vrm/"+PATHS[source]+".vrm").instantiate()
		var lookup := {}
		for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
			for i in mesh.mesh.get_surface_count():
				var mat := mesh.mesh.surface_get_material(i)
				lookup[mat.resource_name] = mat
		source_materials[source] = lookup
		actor.free()
	return source_materials[source][part.get_meta("surface_materials")[surface]]

func clip_neck(polygon: Array, level: float, above: bool, plane_normal := Vector3.UP) -> Array:
	var result := []
	if polygon.is_empty(): return result
	var previous: Dictionary = polygon[-1]
	var previous_height := plane_normal.dot(previous.p)
	var previous_inside := previous_height >= level if above else previous_height <= level
	for current: Dictionary in polygon:
		var height := plane_normal.dot(current.p)
		var inside := height >= level if above else height <= level
		if inside != previous_inside:
			var t := (level-previous_height)/(height-previous_height)
			var influence := {}
			for pair in [[previous,1.0-t],[current,t]]:
				for k in pair[0].b.size():
					var bone: int = pair[0].b[k]
					influence[bone] = influence.get(bone,0.0)+pair[0].w[k]*pair[1]
			var order := influence.keys()
			order.sort_custom(func(a: int,b: int) -> bool: return influence[a] > influence[b])
			var bones := PackedInt32Array([0,0,0,0])
			var weights := PackedFloat32Array([0,0,0,0])
			var total := 0.0
			for k in mini(4,order.size()):
				bones[k] = order[k]
				weights[k] = influence[order[k]]
				total += weights[k]
			for k in 4: weights[k] /= maxf(total,.00001)
			var intersection := {"p":previous.p.lerp(current.p,t),"n":previous.n.lerp(current.n,t).normalized(),"b":bones,"w":weights}
			if previous.has("uv") and current.has("uv"): intersection.uv = previous.uv.lerp(current.uv,t)
			result.append(intersection)
		if inside: result.append(current)
		previous = current
		previous_height = height
		previous_inside = inside
	return result
