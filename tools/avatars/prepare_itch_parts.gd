extends "res://tools/avatars/prepare_vrm_parts.gd"
## Only new derived parts. Original bodies, hands, rig and IDs are retained.
const OUT := "res://assets/avatars/itch/parts/"
func relaxed(path: String) -> Dictionary:
	var actor: Node3D = load(path).instantiate()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(actor)
	var rig: Skeleton3D = actor.find_children("*","Skeleton3D",true,false)[0]
	for side in ["Left","Right"]:
		var bone := rig.find_bone(side+"UpperArm")
		var rest := rig.get_bone_global_rest(bone)
		var q := rest.basis.get_rotation_quaternion()
		rig.set_bone_pose_rotation(bone,rig.get_bone_pose_rotation(bone)*q.inverse()*Quaternion(Vector3.BACK,-signf(rest.origin.x)*1.08)*q)
	rig.force_update_all_bone_transforms()
	var meshes := actor.find_children("*","MeshInstance3D",true,false)
	var face: MeshInstance3D
	for mesh in meshes:
		if "Face" in str(mesh.name): face = mesh
	return {"actor":actor,"skel":rig,"head":rig.global_transform*rig.get_bone_global_pose(rig.find_bone("Head")),"bounds":face.global_transform*face.get_aabb(),"meshes":meshes}

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var kai := relaxed("res://assets/avatars/itch/Kai.vrm")
	for model in 2:
		var target := relaxed("res://assets/avatars/vrm/"+["Sakurada_Fumiriya","Vita"][model]+".vrm")
		var fit: Vector3 = target.bounds.size/kai.bounds.size
		fit.y = target.head.origin.y/kai.head.origin.y
		var transform := Transform3D(Basis.from_scale(fit),Vector3.ZERO)
		var body := ArrayMesh.new()
		var names := PackedStringArray()
		var material_sources := {}
		# Keep the accepted target's own skin and hands; hide only covered torso/legs.
		var own: ArrayMesh = load("res://assets/avatars/vrm/parts/body_%d_0.res" % model)
		var skin := own.surface_get_arrays(0)
		var indices: PackedInt32Array = skin[Mesh.ARRAY_INDEX]
		var visible := PackedInt32Array()
		var stride: int = skin[Mesh.ARRAY_BONES].size()/skin[0].size()
		for triangle in indices.size()/3:
			var keep := false
			for corner in 3:
				var index := indices[triangle*3+corner]
				if skin[0][index].y > target.head.origin.y-.08: keep = true
				for k in stride:
					var bone := str(target.skel.get_bone_name(skin[Mesh.ARRAY_BONES][index*stride+k]))
					if skin[Mesh.ARRAY_WEIGHTS][index*stride+k] > .02 and ("LowerArm" in bone or "Hand" in bone or "Thumb" in bone or "Index" in bone or "Middle" in bone or "Ring" in bone or "Little" in bone): keep = true
			if keep:
				for corner in 3: visible.append(indices[triangle*3+corner])
		skin[Mesh.ARRAY_INDEX] = visible
		body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,skin)
		names.append(own.get_meta("surface_materials")[0])
		material_sources[0] = model
		var hair_groups := {}
		var cloth_groups := {}
		for mesh: MeshInstance3D in kai.meshes:
			if "Face" in str(mesh.name): continue
			var body_bake := cpu_bake(mesh,kai.skel,target.skel,transform,false,true)
			var hair_bake := cpu_bake(mesh,kai.skel)
			for surface in mesh.mesh.get_surface_count():
				var material: ShaderMaterial = mesh.mesh.surface_get_material(surface)
				var name := material.resource_name
				if "_SKIN" in name: continue
				var hair: bool = "_HAIR" in name
				var groups: Dictionary = hair_groups if hair else cloth_groups
				if not groups.has(name):
					var tool := SurfaceTool.new()
					tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					groups[name] = tool
				var into_head: Transform3D = target.head.affine_inverse()*transform*mesh.global_transform
				groups[name].append_from(hair_bake if hair else body_bake,surface,into_head if hair else transform*mesh.global_transform)
		for name in cloth_groups:
			var tool: SurfaceTool = cloth_groups[name]
			tool.deindex()
			tool.index()
			tool.commit(body)
			names.append(name)
		body.set_meta("part_source",5)
		body.set_meta("surface_materials",names)
		body.set_meta("surface_sources",material_sources)
		assert(ResourceSaver.save(body,OUT+"body_%d.res" % model,ResourceSaver.FLAG_COMPRESS)==OK)
		var hair := ArrayMesh.new()
		var hair_names := PackedStringArray()
		for name in hair_groups:
			var tool: SurfaceTool = hair_groups[name]
			tool.deindex()
			tool.index()
			tool.commit(hair)
			hair_names.append(name)
		hair.set_meta("part_source",5)
		hair.set_meta("surface_materials",hair_names)
		assert(ResourceSaver.save(hair,OUT+"hair_%d.res" % model,ResourceSaver.FLAG_COMPRESS)==OK)
		for style in ["bob","short","twins","pony"]:
			var actor: Node3D = load("res://assets/avatars/itch/modular_"+style+".glb").instantiate()
			root.add_child(actor)
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			var material: StandardMaterial3D
			var base: ArrayMesh = load("res://assets/avatars/vrm/parts/hair_%d_0.res" % model)
			var width := base.get_aabb().size.x/.245
			# All four author styles share one scalp. Preserve pony/twin length.
			var shift := Vector3(0,base.get_aabb().end.y-1.583*width,.015)
			for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
				material = mesh.mesh.surface_get_material(0)
				for surface in mesh.mesh.get_surface_count():
					tool.append_from(mesh.mesh,surface,Transform3D(Basis.from_scale(Vector3.ONE*width),shift)*mesh.global_transform)
			tool.deindex()
			tool.index()
			var part := tool.commit()
			var source_mat: ShaderMaterial = kai.meshes[-1].mesh.surface_get_material(0)
			var mat := source_mat.duplicate(false) as ShaderMaterial
			mat.resource_name = "Modular_HAIR"
			mat.next_pass = null
			mat.set_shader_parameter("_MainTex",material.albedo_texture)
			mat.set_shader_parameter("_ShadeTexture",material.albedo_texture)
			mat.set_shader_parameter("_Color",material.albedo_color)
			mat.set_shader_parameter("_ShadeColor",material.albedo_color.darkened(.20))
			# Donor strands rely on their body's coloured scalp. The target's skin
			# has no such paint, so supply a continuous fitted cap beneath them.
			var cap := SurfaceTool.new()
			cap.begin(Mesh.PRIMITIVE_TRIANGLES)
			var point := func(row: int,column: int) -> Vector3:
				var phi := TAU*column/48.0
				var front := maxf(0.0,sin(phi))
				var rear := maxf(0.0,-sin(phi))
				var limit := 1.72-.68*front+.45*rear
				var theta := limit*row/16.0
				return Vector3(.096*width*sin(theta)*cos(phi),base.get_aabb().end.y-.018-.121*width+.121*width*cos(theta),-.022+.101*width*sin(theta)*sin(phi))
			for row in 16:
				for column in 48:
					var a: Vector3 = point.call(row,column)
					var b: Vector3 = point.call(row+1,column)
					var c: Vector3 = point.call(row+1,column+1)
					var d: Vector3 = point.call(row,column+1)
					var corners := [a,c,b,a,d,c]
					var uvs := [Vector2(column/48.0,row/16.0),Vector2((column+1)/48.0,(row+1)/16.0),Vector2(column/48.0,(row+1)/16.0),Vector2(column/48.0,row/16.0),Vector2((column+1)/48.0,row/16.0),Vector2((column+1)/48.0,(row+1)/16.0)]
					for i in 6:
						cap.set_uv(uvs[i])
						cap.add_vertex(corners[i])
			# The forehead is not ellipsoidal. Cover it with the actual target
			# scalp, offset just above skin, to prevent light skin between strands.
			for face: MeshInstance3D in target.meshes:
				if not ("Face" in str(face.name) or "Body" in str(face.name)): continue
				var baked := cpu_bake(face,target.skel)
				var local: Transform3D = target.head.affine_inverse()*face.global_transform
				for surface in face.mesh.get_surface_count():
					var original: ShaderMaterial = face.mesh.surface_get_material(surface)
					if not "_SKIN" in original.resource_name: continue
					var a := baked.surface_get_arrays(surface)
					var vertices: PackedVector3Array = a[0]
					var normals: PackedVector3Array = a[1]
					var forehead_indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
					var top: float = (target.head.affine_inverse()*target.bounds).end.y
					for triangle in forehead_indices.size()/3:
						var center := Vector3.ZERO
						for k in 3: center += local*vertices[forehead_indices[triangle*3+k]]/3
						var front := smoothstep(.015,.065,center.z)
						if center.y < top-lerpf(.145,.085,front): continue
						for k in 3:
							var i := forehead_indices[triangle*3+k]
							var p: Vector3 = local*vertices[i]+(local.basis*normals[i]).normalized()*.004
							cap.set_uv(Vector2(atan2(p.z,p.x)/TAU,.5))
							cap.add_vertex(p)
			cap.generate_normals()
			cap.commit(part)
			var cap_mat := mat.duplicate(false) as ShaderMaterial
			cap_mat.resource_name = "Modular_Scalp_HAIR"
			var white := Image.create(256,4,false,Image.FORMAT_RGBA8)
			for x in 256:
				var tone := .94+.06*cos(TAU*x/256.0*24)+.025*sin(TAU*x/256.0*53)
				for y in 4: white.set_pixel(x,y,Color("603c2c")*tone)
			var white_texture := ImageTexture.create_from_image(white)
			cap_mat.set_shader_parameter("_MainTex",white_texture)
			cap_mat.set_shader_parameter("_ShadeTexture",white_texture)
			cap_mat.set_shader_parameter("_Color",Color.WHITE)
			cap_mat.set_shader_parameter("_ShadeColor",Color("b4b4b4"))
			part.set_meta("part_source",5)
			part.set_meta("surface_materials",PackedStringArray(["Modular_HAIR","Modular_Scalp_HAIR"]))
			part.set_meta("variant_materials",{0:mat,1:cap_mat})
			assert(ResourceSaver.save(part,OUT+"hair_%d_%s.res" % [model,style],ResourceSaver.FLAG_COMPRESS)==OK)
			actor.queue_free()
		print("KAI parts ",model," body surfaces=",body.get_surface_count()," hair=",hair.get_aabb())
		target.actor.queue_free()
	kai.actor.queue_free()
	for i in 3: await process_frame
	quit()
