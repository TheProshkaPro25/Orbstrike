extends SceneTree
## Offline preparation only. No mesh baking or file loading after the menu.
const PATHS := ["Sakurada_Fumiriya","Vita","HairSample_Male","HairSample_Female","Vivi"]
var sources: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var hands_only := "--only-hoodie-hands" in OS.get_cmdline_user_args()
	var vita_sharp_hair_only := "--vita-sharp-hair" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute("res://assets/avatars/vrm/parts")
	for name in PATHS:
		var packed := load("res://assets/avatars/vrm/"+name+".vrm") as PackedScene
		var actor := packed.instantiate() as Node3D
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(actor)
		var skeleton := actor.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
		for side in ["Left","Right"]:
			var bone := skeleton.find_bone(side+"UpperArm")
			var rest := skeleton.get_bone_global_rest(bone)
			var q := rest.basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(bone,skeleton.get_bone_pose_rotation(bone)*q.inverse()*Quaternion(Vector3(0,0,1),-signf(rest.origin.x)*1.08)*q)
		skeleton.force_update_all_bone_transforms()
		var head := skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("Head"))
		var meshes := actor.find_children("*","MeshInstance3D",true,false)
		var face: MeshInstance3D
		for mesh in meshes:
			if "Face" in str(mesh.name): face = mesh
		assert(face != null)
		var bounds: AABB = face.global_transform*face.get_aabb()
		sources.append({"name":name,"actor":actor,"skel":skeleton,"head":head,"bounds":bounds,"meshes":meshes})
	for frame in 3: await process_frame
	for target_index in 2:
		if hands_only and target_index != 0: continue
		if vita_sharp_hair_only and target_index != 1: continue
		var target_skeleton: Skeleton3D = sources[target_index].skel
		var skin := Skin.new()
		for bone in target_skeleton.get_bone_count():
			skin.add_bind(bone,(target_skeleton.global_transform*target_skeleton.get_bone_global_pose(bone)).affine_inverse())
		if not hands_only and not vita_sharp_hair_only:
			assert(ResourceSaver.save(skin,"res://assets/avatars/vrm/parts/skin_%d.res" % target_index,ResourceSaver.FLAG_COMPRESS)==OK)
		for source_index in PATHS.size():
			if hands_only: continue
			if vita_sharp_hair_only and source_index != 2: continue
			var source := sources[source_index]
			var target := sources[target_index]
			var fit: Vector3 = target.bounds.size/source.bounds.size
			fit = fit.clamp(Vector3.ONE*.8,Vector3.ONE*1.25)
			var head_inverse: Transform3D = source.head.affine_inverse()
			var transform := Transform3D(Basis.from_scale(fit),Vector3.ZERO)*head_inverse
			if target_index == 1 and source_index == 2:
				# This donor has open gaps between its roots. The taller Vita
				# scalp needs extra room at the crown and back, above the fringe.
				var anchor := Vector3(0,.07,.055)
				var crown_scale := Vector3(1.028,1.095,1.042)
				var crown_fit := Transform3D(Basis.from_scale(crown_scale),anchor*(Vector3.ONE-crown_scale))
				transform = crown_fit*transform
			var hair := gather(source,transform,true)
			var path := "res://assets/avatars/vrm/parts/hair_%d_%d.res" % [target_index,source_index]
			assert(ResourceSaver.save(hair,path,ResourceSaver.FLAG_COMPRESS)==OK)
			print("HAIR ",path," surfaces=",hair.get_surface_count()," aabb=",hair.get_aabb())
		if vita_sharp_hair_only: continue
		var outfits: Array = [0,2] if target_index == 0 else [1,3,4]
		for index in outfits.size():
			if hands_only and index != 1: continue
			var source := sources[outfits[index]]
			var target := sources[target_index]
			var scale: Vector3 = target.bounds.size/source.bounds.size
			scale.y = target.head.origin.y/source.head.origin.y
			var transform := Transform3D(Basis.from_scale(scale),Vector3.ZERO)
			var body := gather(source,transform,false,target_skeleton)
			var path := "res://assets/avatars/vrm/parts/body_%d_%d.res" % [target_index,index]
			assert(ResourceSaver.save(body,path,ResourceSaver.FLAG_COMPRESS)==OK)
			print("BODY ",path," surfaces=",body.get_surface_count()," aabb=",body.get_aabb())
	for source in sources: source.actor.queue_free()
	for frame in 3: await process_frame
	print("VRM parts prepared")
	quit()

func gather(source: Dictionary,transform: Transform3D,hair: bool,target: Skeleton3D = null) -> ArrayMesh:
	var groups: Dictionary = {}
	var names: Dictionary = {}
	for mesh: MeshInstance3D in source.meshes:
		if "Face" in str(mesh.name): continue
		if not hair and not "Body" in str(mesh.name): continue
		var rebind_hands: bool = source.name == "HairSample_Male" and target != null and target.get_bone_count() == 108
		var baked := cpu_bake(mesh,source.skel,target,transform,rebind_hands,source.name == "HairSample_Male")
		assert(baked != null)
		for surface in baked.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			var is_hair: bool = "_HAIR" in material.resource_name
			if is_hair != hair: continue
			var id := material.get_instance_id()
			if not groups.has(id):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tool.set_material(material)
				groups[id] = tool
				names[id] = material.resource_name
			groups[id].append_from(baked,surface,transform*mesh.global_transform)
	var output := ArrayMesh.new()
	var material_names := PackedStringArray()
	for id in groups:
		var tool: SurfaceTool = groups[id]
		tool.deindex()
		tool.index()
		tool.commit(output)
		output.surface_set_material(output.get_surface_count()-1,null)
		material_names.append(names[id])
	output.set_meta("part_source",PATHS.find(source.name))
	output.set_meta("surface_materials",material_names)
	return output

func cpu_bake(mesh: MeshInstance3D,skeleton: Skeleton3D,target: Skeleton3D = null,fit := Transform3D.IDENTITY,rebind_hands := false,rebind_sleeves := false) -> ArrayMesh:
	# CPU preparation works with the headless renderer too. Equivalent skinning:
	# skeleton_global * bone_pose * inverse_bind * vertex, converted to mesh space.
	var transforms: Array[Transform3D] = []
	var sleeve_transforms: Array[Transform3D] = []
	var remap := PackedInt32Array()
	var into_mesh := mesh.global_transform.affine_inverse()*skeleton.global_transform
	for bind in mesh.skin.get_bind_count():
		var bone := mesh.skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
		assert(bone >= 0)
		transforms.append(into_mesh*skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind))
		sleeve_transforms.append(transforms[-1])
		if target != null:
			var ancestor := bone
			while ancestor >= 0 and target.find_bone(skeleton.get_bone_name(ancestor)) < 0:
				ancestor = skeleton.get_bone_parent(ancestor)
			assert(ancestor >= 0)
			remap.append(target.find_bone(skeleton.get_bone_name(ancestor)))
			# This donor's hand pivots differ from the male base. Rebinding only
			# joint indices leaves skin rotating around the wrong thumb origin.
			var name := str(skeleton.get_bone_name(bone))
			# Sleeve endpoints must fit the target elbow AND wrist, not just share
			# bone indices. Scaling the donor torso left cuffs beside the real hand.
			if rebind_sleeves:
				var final_mesh := fit*mesh.global_transform
				for side in ["Left","Right"]:
					var end := ""
					if name == side+"UpperArm": end = side+"LowerArm"
					elif name == side+"LowerArm": end = side+"Hand"
					if not end.is_empty():
						var start := fit*skeleton.global_transform*skeleton.get_bone_global_pose(bone).origin
						var finish := fit*skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(end)).origin
						var target_start := target.global_transform*target.get_bone_global_pose(remap[-1]).origin
						var target_finish := target.global_transform*target.get_bone_global_pose(target.find_bone(end)).origin
						var correction := segment_fit(start,finish,target_start,target_finish)
						sleeve_transforms[-1] = final_mesh.affine_inverse()*correction*final_mesh*sleeve_transforms[-1]
						# Covered forearm skin must share the sleeve's fitted axis;
						# the existing hand/finger pivot correction below stays intact.
						transforms[-1] = sleeve_transforms[-1]
					elif name == side+"Hand":
						var donor_pose := fit*skeleton.global_transform*skeleton.get_bone_global_pose(bone)
						var target_pose := target.global_transform*target.get_bone_global_pose(remap[-1])
						sleeve_transforms[-1] = final_mesh.affine_inverse()*target_pose*donor_pose.affine_inverse()*final_mesh*sleeve_transforms[-1]
			var hand_bone := false
			for side in ["Left","Right"]:
				for suffix in ["Hand","Thumb","Index","Middle","Ring","Little"]:
					if name.begins_with(side+suffix): hand_bone = true
			if rebind_hands and hand_bone:
				var final_mesh := fit*mesh.global_transform
				var donor_pose := fit*skeleton.global_transform*skeleton.get_bone_global_pose(bone)
				var target_pose := target.global_transform*target.get_bone_global_pose(remap[-1])
				var correction := final_mesh.affine_inverse()*target_pose*donor_pose.affine_inverse()*final_mesh
				transforms[-1] = correction*transforms[-1]
	var output := ArrayMesh.new()
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.mesh.surface_get_material(surface)
		var sleeve: bool = material != null and "Tops_" in material.resource_name
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride := int(weights.size()/vertices.size())
		for i in vertices.size():
			var p := Vector3.ZERO
			var n := Vector3.ZERO
			var t := Vector3.ZERO
			for k in stride:
				var weight := weights[i*stride+k]
				if weight <= 0: continue
				var tr := sleeve_transforms[joints[i*stride+k]] if sleeve else transforms[joints[i*stride+k]]
				p += (tr*vertices[i])*weight
				if not normals.is_empty(): n += (tr.basis*normals[i])*weight
				if not tangents.is_empty(): t += (tr.basis*Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2]))*weight
			vertices[i] = p
			if not normals.is_empty(): normals[i] = n.normalized()
			if not tangents.is_empty():
				t = t.normalized()
				tangents[i*4] = t.x
				tangents[i*4+1] = t.y
				tangents[i*4+2] = t.z
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		if target == null:
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
		else:
			# Rebind the fitted relaxed pose to the target humanoid. Donor-only
			# accessory bones follow the closest common ancestor; weights survive.
			for i in joints.size(): joints[i] = remap[joints[i]]
			arrays[Mesh.ARRAY_BONES] = joints
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return output

func segment_fit(start: Vector3,finish: Vector3,target_start: Vector3,target_finish: Vector3) -> Transform3D:
	var axis := (finish-start).normalized()
	var target_axis := (target_finish-target_start).normalized()
	var stretch := target_start.distance_to(target_finish)/start.distance_to(finish)-1.0
	var along := Basis(Vector3.RIGHT+axis*axis.x*stretch,Vector3.UP+axis*axis.y*stretch,Vector3.BACK+axis*axis.z*stretch)
	var basis := Basis(Quaternion(axis,target_axis))*along
	return Transform3D(basis,target_start-basis*start)
