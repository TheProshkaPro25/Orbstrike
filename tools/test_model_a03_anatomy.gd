extends "res://tools/test_model_wind_import.gd"
## A03 source-exact body, local anatomy import and actual post-support poses.
const DIRECTORY := "res://build/model_candidates/2026-11-06-a03-anatomy/"
const OUTPUT := "res://docs/audits/2026-11-06-model-a03-anatomy/"

func actor(definition: CreatureDef, packed: PackedScene = null) -> CreatureBall:
	var ball := super.actor(definition,packed)
	# CreatureAnim deliberately skips hidden spheres. This fixture must expose the
	# figure internally, while the outer test Window remains minimized/no-focus.
	ball._figure.visible=true
	ball._anim.visible=true
	ball._open=true
	ball._ball_mesh.visible=false
	ball._shell.visible=false
	check(ball._anim.is_visible_in_tree(),"A03 animation fixture is internally visible")
	return ball

func retained_references(ball: CreatureBall) -> PackedVector3Array:
	var result := PackedVector3Array()
	for mesh in nodes(ball._anim,"MeshInstance3D"):
		if mesh.skin == null: continue
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in 32: result.append(vertices[i*(vertices.size()-1)/31])
	return result

func export_poses(ball: CreatureBall, directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var a := ball._anim
	var sk: Skeleton3D = nodes(a,"Skeleton3D")[0]
	var meshes: Array = []
	for node in nodes(a,"MeshInstance3D"):
		if node.skin != null: meshes.append(node)
	var info := signature(ball)
	info["normalization_scale"]=info.scale
	info["normalization_offset"]=info.offset
	info["meshes"]=[]
	info["poses"]=[]
	info["export_kind"]="ACTUAL_GODOT_DIRECT_IMPORT_CREATUREBALL_POST_SUPPORT"
	for mi in meshes.size():
		var mesh: MeshInstance3D = meshes[mi]
		var names: Array[String] = []
		for slot in mesh.skin.get_bind_count():
			var bone := mesh.skin.get_bind_bone(slot)
			if bone<0: bone=sk.find_bone(mesh.skin.get_bind_name(slot))
			names.append(sk.get_bone_name(bone))
		for surf in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surf)
			var prefix := "%d_%d" % [mi,surf]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for item in [["vertices",verts.to_byte_array()],["indices",indices.to_byte_array()],["joints",joints.to_byte_array()],["weights",weights.to_byte_array()]]:
				var file := FileAccess.open(directory.path_join(prefix+"_"+item[0]+".bin"),FileAccess.WRITE)
				file.store_buffer(item[1])
			info.meshes.append({"prefix":prefix,"mi":mi,"name":String(mesh.name),"vertices":verts.size(),"stride":weights.size()/verts.size(),"bones":names})
	for action in ["idle","attack","hit"]:
		ReviewState.reset_actor(a)
		a.idle_on=true
		if action=="attack":a.lunge(a.get_height()*.22)
		if action=="hit":a.hit(Color.WHITE,a.get_height()*.075)
		var duration: float = 2.0 if action=="idle" else a._duration
		var frames := ceili(duration*60)
		for frame in frames+1:
			if frame>0:a._process(1.0/60)
			if frame%6!=0 and frame!=frames:continue
			var palettes: Array = []
			for mesh in meshes:
				var palette := PackedFloat32Array()
				for slot in mesh.skin.get_bind_count():
					var bone: int = mesh.skin.get_bind_bone(slot)
					if bone<0:bone=sk.find_bone(mesh.skin.get_bind_name(slot))
					var transform: Transform3D = sk.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(slot)
					for row in 3:
						palette.append(transform.basis.x[row]);palette.append(transform.basis.y[row]);palette.append(transform.basis.z[row]);palette.append(transform.origin[row])
				palettes.append(Array(palette))
			info.poses.append({"action":action,"frame":frame,"palettes":palettes})
	var file := FileAccess.open(directory.path_join("poses.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(info,"\t")+"\n")

func run() -> void:
	var definition := CardDB.creature(&"creature_kolossar_shadow")
	var before := imported(DIRECTORY+"source/kolossar_shadow.glb")
	var after := imported(DIRECTORY+"rounded_smoke22.glb")
	var bm := inspect_scene(before)
	var am := inspect_scene(after)
	check(bm.triangles==149994,"A03 immutable source triangles")
	check(am.triangles==171156,"A03 anatomy candidate triangles")
	var base_ball := actor(definition,before)
	var next_ball := actor(definition,after)
	var bs := signature(base_ball)
	var cs := signature(next_ball)
	check(absf(bs.scale-cs.scale)<.00001,"A03 body scale preserved")
	check(absf(bs.height-cs.height)<.00001,"A03 authored action height preserved")
	check(Vector3(bs.offset[0],bs.offset[1],bs.offset[2]).distance_to(Vector3(cs.offset[0],cs.offset[1],cs.offset[2]))<.00001,"A03 normalization center preserved")
	var refs := retained_references(next_ball)
	var source_samples := bind_samples(base_ball,refs)
	var candidate_samples := bind_samples(next_ball,refs)
	var max_palette := 0.0
	var max_world := 0.0
	var motion_delta := 0.0
	var saved_palettes: Array = []
	var saved_world: Array = []
	for action in ["idle","attack","hit"]:
		for frame in [0,12,24,48,90]:
			var bp := pose(base_ball,action,frame)
			var cp := pose(next_ball,action,frame)
			check(bp.size()==cp.size(),"A03 same skeleton")
			for i in mini(bp.size(),cp.size()):max_palette=maxf(max_palette,absf(bp[i]-cp[i]))
			var points := world_points(candidate_samples)
			max_world=maxf(max_world,point_delta(world_points(source_samples),points))
			saved_palettes.append(cp);saved_world.append(points)
	for cp in saved_palettes:
		for i in cp.size():motion_delta=maxf(motion_delta,absf(cp[i]-saved_palettes[0][i]))
	check(motion_delta>.01,"A03 actual bone palettes change across visible idle/attack/hit poses")
	check(max_palette<.00001,"A03 same actual source/candidate pose palettes")
	check(max_world<.00002,"A03 retained world surface exact")
	export_poses(base_ball,DIRECTORY+"actual-source")
	export_poses(next_ball,DIRECTORY+"actual-candidate")
	ModelLifetime.release(base_ball,self);ModelLifetime.release(next_ball,self)
	await process_frame
	CreatureModels.clear()
	var production := "res://assets/creatures_hd/kolossar_shadow.glb"
	var installed := FileAccess.get_sha256(production)==FileAccess.get_sha256(DIRECTORY+"rounded_smoke22.glb")
	var ordinary := load(production) as PackedScene
	var om := inspect_scene(ordinary)
	check(om.triangles==(171156 if installed else 149994),"A03 ordinary import follows actual installed SHA")
	var ball := actor(definition)
	var osig := signature(ball)
	var old_ordinary := load(DIRECTORY+"source/kolossar_shadow-ordinary.scn") as PackedScene
	check(old_ordinary!=null,"A03 immutable ordinary-animation baseline exists")
	var old_ball := actor(definition,old_ordinary)
	var old_samples := bind_samples(old_ball,refs)
	var samples := bind_samples(ball,refs)
	var ordinary_palette := 0.0
	var ordinary_world := 0.0
	var ordinary_direct_palette := 0.0
	var ordinary_direct_world := 0.0
	var index := 0
	for action in ["idle","attack","hit"]:
		for frame in [0,12,24,48,90]:
			var op := pose(ball,action,frame)
			var cp: PackedFloat64Array = saved_palettes[index]
			var bp := pose(old_ball,action,frame)
			for i in mini(op.size(),bp.size()):ordinary_palette=maxf(ordinary_palette,absf(op[i]-bp[i]))
			ordinary_world=maxf(ordinary_world,point_delta(world_points(samples),world_points(old_samples)))
			for i in mini(op.size(),cp.size()):ordinary_direct_palette=maxf(ordinary_direct_palette,absf(op[i]-cp[i]))
			ordinary_direct_world=maxf(ordinary_direct_world,point_delta(world_points(samples),saved_world[index]));index+=1
	check(ordinary_palette<.00001,"A03 ordinary actor preserves previous ordinary animation")
	check(ordinary_world<.00002,"A03 ordinary retained world surface versus immutable ordinary baseline")
	ModelLifetime.release(ball,self);ModelLifetime.release(old_ball,self);await process_frame
	CreatureModels.clear();CreatureModels.animation_library_cache.clear();await process_frame
	var result := {"scope":"Actual Godot GLTF/CreatureBall CPU import and poses; no rendered/GPU acceptance","candidate_sha256":FileAccess.get_sha256(DIRECTORY+"rounded_smoke22.glb"),"source_sha256":FileAccess.get_sha256(DIRECTORY+"source/kolossar_shadow.glb"),"production_sha256":FileAccess.get_sha256(production),"installed":installed,"source_import":bm,"candidate_import":am,"ordinary_import":om,"source_actor":bs,"candidate_actor":cs,"ordinary_actor":osig,"actual_pose_motion_delta":motion_delta,"source_candidate_palette_delta":max_palette,"source_candidate_world_delta":max_world,"ordinary_palette_delta":ordinary_palette,"ordinary_world_delta":ordinary_world,"ordinary_direct_palette_delta_diagnostic":ordinary_direct_palette,"ordinary_direct_world_delta_diagnostic":ordinary_direct_world,"ordinary_baseline_sha256":FileAccess.get_sha256(DIRECTORY+"source/kolossar_shadow-ordinary.scn"),"world_samples":refs.size(),"display_server":DisplayServer.get_name(),"assertions":assertions,"failures":failures}
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var file := FileAccess.open(OUTPUT+"actual-import.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t")+"\n")
	print("A03 ANATOMY: %d assertions, %d failures; CPU import and actual poses" % [assertions,failures])
	quit(1 if failures else 0)
