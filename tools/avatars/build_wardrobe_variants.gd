extends "res://tools/avatars/prepare_vrm_parts.gd"
## Derived CC0 garments/hair only. Originals, rig, UV and accepted hands stay intact.
const OUTPUT := "res://assets/avatars/vrm/parts/"
var white: ImageTexture
var cloth_texture: Texture2D

func run() -> void:
	var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	white = ImageTexture.create_from_image(image)
	for name in PATHS:
		var actor: Node3D = load("res://assets/avatars/vrm/"+name+".vrm").instantiate()
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(actor)
		var skeleton: Skeleton3D = actor.find_children("*","Skeleton3D",true,false)[0]
		for side in ["Left","Right"]:
			var bone := skeleton.find_bone(side+"UpperArm")
			var q := skeleton.get_bone_global_rest(bone).basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(bone,skeleton.get_bone_pose_rotation(bone)*q.inverse()*Quaternion(Vector3(0,0,1),-signf(skeleton.get_bone_global_rest(bone).origin.x)*1.08)*q)
		skeleton.force_update_all_bone_transforms()
		var meshes := actor.find_children("*","MeshInstance3D",true,false)
		var face: MeshInstance3D
		for mesh in meshes:
			if "Face" in str(mesh.name): face = mesh
		sources.append({"name":name,"actor":actor,"skel":skeleton,"head":skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("Head")),"bounds":face.global_transform*face.get_aabb(),"meshes":meshes})
	var texture: Texture2D = original_material(2,"M00_006_01_Tops_01_CLOTH").get_shader_parameter("_MainTex")
	var cloth := ImageTexture.create_from_image(texture.get_image())
	assert(ResourceSaver.save(cloth,OUTPUT+"wardrobe_cloth.res",ResourceSaver.FLAG_COMPRESS)==OK)
	cloth_texture = load(OUTPUT+"wardrobe_cloth.res")
	for model in 2:
		for variant in 2:
			var source: ArrayMesh = load(OUTPUT+"hair_%d_%d.res" % [model,2 if variant == 0 else 0])
			var hair := deform_mesh(source,func(p: Vector3) -> Vector3: return hair_shape(p,variant))
			assert(ResourceSaver.save(hair,OUTPUT+"hair_%d_%d.res" % [model,5+variant],ResourceSaver.FLAG_COMPRESS)==OK)
		var hoodie: ArrayMesh
		if model == 0:
			hoodie = load(OUTPUT+"body_0_1.res")
		else:
			var fit: Vector3 = sources[model].bounds.size/sources[2].bounds.size
			fit.y = sources[model].head.origin.y/sources[2].head.origin.y
			hoodie = gather(sources[2],Transform3D(Basis.from_scale(fit),Vector3.ZERO),false,sources[model].skel)
		for variant in 2:
			var body := garment(hoodie,model,variant)
			var slot := (2 if model == 0 else 3)+variant
			assert(ResourceSaver.save(body,OUTPUT+"body_%d_%d.res" % [model,slot],ResourceSaver.FLAG_COMPRESS)==OK)
			print("WARDROBE ",model,"/",slot," ",body.get_aabb())
	for source in sources: source.actor.queue_free()
	for i in 3: await process_frame
	print("Wardrobe variants prepared; original parts untouched")
	quit()

func hair_shape(p: Vector3,variant: int) -> Vector3:
	var q := p
	if variant == 0:
		var crown := smoothstep(.065,.22,p.y)
		q.y += .062*crown*(.65+.35*sin(p.x*36+p.z*27))
		q.x *= 1.0+.20*crown
		q.z -= .018*crown
	else:
		var bang := smoothstep(.025,.13,p.z)*smoothstep(-.01,.14,p.y)
		q.x += .060*bang
		q.y += .021*bang
		q.z += .005*bang
	return q

func deform_mesh(source: ArrayMesh,shape: Callable) -> ArrayMesh:
	var output := ArrayMesh.new()
	for i in source.get_surface_count():
		var a := source.surface_get_arrays(i)
		deform_arrays(a,shape)
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)
	for key in source.get_meta_list(): output.set_meta(key,source.get_meta(key))
	return output

func deform_arrays(a: Array,shape: Callable) -> void:
	var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
	var h := .0001
	for i in vertices.size():
		var p := vertices[i]
		var jac := Basis((shape.call(p+Vector3.RIGHT*h)-shape.call(p-Vector3.RIGHT*h))/(2*h),(shape.call(p+Vector3.UP*h)-shape.call(p-Vector3.UP*h))/(2*h),(shape.call(p+Vector3.BACK*h)-shape.call(p-Vector3.BACK*h))/(2*h))
		vertices[i] = shape.call(p)
		if not normals.is_empty(): normals[i] = (jac.inverse().transposed()*normals[i]).normalized()
		if not tangents.is_empty():
			var t := (jac*Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])).normalized()
			tangents[i*4] = t.x
			tangents[i*4+1] = t.y
			tangents[i*4+2] = t.z
	a[Mesh.ARRAY_VERTEX] = vertices
	a[Mesh.ARRAY_NORMAL] = normals
	a[Mesh.ARRAY_TANGENT] = tangents

func original_material(source: int,name: String) -> ShaderMaterial:
	for mesh in sources[source].meshes:
		for surface in mesh.mesh.get_surface_count():
			var material: ShaderMaterial = mesh.mesh.surface_get_material(surface)
			if material.resource_name == name: return material
	assert(false,"Missing material "+name)
	return null

func plain_material(template: ShaderMaterial,color: Color,name: String) -> ShaderMaterial:
	var mat := template.duplicate(false) as ShaderMaterial
	mat.resource_name = name
	mat.next_pass = null
	mat.set_shader_parameter("_MainTex",white)
	mat.set_shader_parameter("_ShadeTexture",white)
	mat.set_shader_parameter("_Color",color)
	mat.set_shader_parameter("_ShadeColor",color.darkened(.22))
	return mat

func garment(source: ArrayMesh,model: int,variant: int) -> ArrayMesh:
	var rig: Skeleton3D = sources[model].skel
	var hip := rig.get_bone_global_pose(rig.find_bone("Hips")).origin.y
	var neck := rig.get_bone_global_pose(rig.find_bone("Neck")).origin
	var size := neck.y/1.59513
	var names: PackedStringArray = source.get_meta("surface_materials")
	var output := ArrayMesh.new()
	var overrides := {}
	var surface_sources := {}
	var top: Array
	var hem := hip-(.04 if variant == 0 else .31)*size
	for i in source.get_surface_count():
		var a := source.surface_get_arrays(i)
		if "SKIN" in names[i] and model == 1:
			var own: ArrayMesh = load(OUTPUT+"body_1_0.res")
			a = own.surface_get_arrays(0)
			names[i] = own.get_meta("surface_materials")[0]
			surface_sources[i] = 1
		if "SKIN" in names[i]:
			var skin_indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var visible := PackedInt32Array()
			var stride: int = a[Mesh.ARRAY_BONES].size()/a[0].size()
			for triangle in skin_indices.size()/3:
				var keep_skin := false
				for corner in 3:
					var vi: int = skin_indices[triangle*3+corner]
					if a[0][vi].y > neck.y-.025*size: keep_skin = true
					for w in stride:
						var bone_name := str(rig.get_bone_name(a[Mesh.ARRAY_BONES][vi*stride+w]))
						# Retain the forearm under the cuff: removing it at the first
						# hand weight exposed a jagged hole when the wrist bends.
						if a[Mesh.ARRAY_WEIGHTS][vi*stride+w] > .02 and ("LowerArm" in bone_name or "Hand" in bone_name or "Thumb" in bone_name or "Index" in bone_name or "Middle" in bone_name or "Ring" in bone_name or "Little" in bone_name): keep_skin = true
				if keep_skin:
					for corner in 3: visible.append(skin_indices[triangle*3+corner])
			a[Mesh.ARRAY_INDEX] = visible
		if "Tops_" in names[i]:
			var lower := source.get_aabb().end.y
			for p in a[0]: lower = minf(lower,p.y)
			var shape := func(p: Vector3) -> Vector3:
				var q := p
				var torso := 1.0-smoothstep(.22*size,.30*size,absf(p.x))
				var t := clampf((hip+.09*size-p.y)/(hip+.09*size-lower),0,1)*torso
				q.y += (hem-lower)*pow(t,1.4)
				q.x *= 1.0+(.13 if variant == 1 else -.04)*t
				q.z *= 1.0+(.10 if variant == 1 else -.02)*t
				return q
			deform_arrays(a,shape)
			# Trim the upper hood at collar height; retain the source cloth shading.
			var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var keep := PackedInt32Array()
			for triangle in indices.size()/3:
				var center: Vector3 = (a[0][indices[triangle*3]]+a[0][indices[triangle*3+1]]+a[0][indices[triangle*3+2]])/3
				if center.y > neck.y+.025*size and absf(center.x) < .14*size: continue
				for k in 3: keep.append(indices[triangle*3+k])
			a[Mesh.ARRAY_INDEX] = keep
			top = a
			overrides[i] = plain_material(original_material(2,names[i]),Color("7188ac") if variant == 0 else Color("52657e"),"Variant_Tops_01_CLOTH")
			overrides[i].set_shader_parameter("_MainTex",cloth_texture)
			overrides[i].set_shader_parameter("_ShadeTexture",cloth_texture)
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)
	# Collar and centre zip are fitted mesh geometry with real weights.
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var collar_height := .048 if variant == 0 else .080
	band(trim,neck+Vector3(0,-.028*size,0),Vector3.UP,.068*size,.056*size,collar_height*size,rig.find_bone("Neck"))
	var zip_bottom := hem+.025*size
	for segment in 28:
		var y0 := lerpf(zip_bottom,neck.y-.025*size,float(segment)/28)
		var y1 := lerpf(zip_bottom,neck.y-.025*size,float(segment+1)/28)
		var p0 := Vector3(0,y0,front_at(top,y0,size)+.003*size)
		var p1 := Vector3(0,y1,front_at(top,y1,size)+.003*size)
		quad(trim,p0-Vector3.RIGHT*.0035*size,p0+Vector3.RIGHT*.0035*size,p1+Vector3.RIGHT*.0035*size,p1-Vector3.RIGHT*.0035*size,top)

	trim.generate_normals()
	trim.commit(output)
	names.append("Variant_Trim_CLOTH")
	overrides[output.get_surface_count()-1] = plain_material(original_material(2,source.get_meta("surface_materials")[1]),Color("192331"),"Variant_Trim_CLOTH")
	output.set_meta("part_source",2)
	output.set_meta("surface_materials",names)
	output.set_meta("variant_materials",overrides)
	output.set_meta("surface_sources",surface_sources)
	return output

func front_at(top: Array,y: float,size: float) -> float:
	var front := .07*size
	for p in top[0]:
		if absf(p.y-y)<.06*size and absf(p.x)<.07*size: front = maxf(front,p.z)
	return front

func put(tool: SurfaceTool,p: Vector3,bones: PackedInt32Array,weights: PackedFloat32Array) -> void:
	tool.set_bones(bones)
	tool.set_weights(weights)
	tool.set_uv(Vector2(.5,.5))
	tool.add_vertex(p)

func put_attached(tool: SurfaceTool,p: Vector3,top: Array) -> void:
	var closest := 0
	var distance := INF
	for i in top[0].size():
		var ds: float = p.distance_squared_to(top[0][i])
		if ds < distance:
			distance = ds
			closest = i
	var stride: int = top[Mesh.ARRAY_BONES].size()/top[0].size()
	put(tool,p,top[Mesh.ARRAY_BONES].slice(closest*stride,(closest+1)*stride),top[Mesh.ARRAY_WEIGHTS].slice(closest*stride,(closest+1)*stride))

func quad(tool: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3,top: Array) -> void:
	for p in [a,c,b,a,d,c]: put_attached(tool,p,top)

func band(tool: SurfaceTool,center: Vector3,axis: Vector3,rx: float,rz: float,height: float,bone: int) -> void:
	var x := axis.cross(Vector3.FORWARD).normalized()
	if x.length()<.1: x = Vector3.RIGHT
	var z := x.cross(axis).normalized()
	for segment in 32:
		var p := x*cos(TAU*segment/32)*rx+z*sin(TAU*segment/32)*rz
		var q := x*cos(TAU*(segment+1)/32)*rx+z*sin(TAU*(segment+1)/32)*rz
		for v in [center+p-axis*height*.5,center+q+axis*height*.5,center+q-axis*height*.5,center+p-axis*height*.5,center+p+axis*height*.5,center+q+axis*height*.5]:
			put(tool,v,PackedInt32Array([bone,0,0,0]),PackedFloat32Array([1,0,0,0]))

