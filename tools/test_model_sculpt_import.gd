extends "res://tools/test_model_wind_import.gd"
## A03 exact-geometry material partition and A04 crown import/build/pose contract.
const SCULPTS := [["kolossar_shadow",149994,149994],["ratnik_light",149994,156366]]

func material_signature(ball: CreatureBall) -> Array:
	var materials: Array = []
	for mesh in nodes(ball._anim,"MeshInstance3D"):
		if mesh.skin == null: continue
		for surface in mesh.mesh.get_surface_count():
			var material: ShaderMaterial = mesh.get_active_material(surface)
			check(material != null,"production anime material exists")
			var tint: Color = material.get_shader_parameter("tint")
			materials.append({"mesh":String(mesh.name),"surface":surface,
				"triangles":mesh.mesh.surface_get_array_index_len(surface)/3,
				"tint":[tint.r,tint.g,tint.b,tint.a],"has_texture":material.get_shader_parameter("has_texture")})
	return materials

func run() -> void:
	report={"scope":"A03 material/A04 crown Godot import and CreatureBall CPU; no GPU cloth", "cases":[]}
	var installed_both := true
	var only_a03 := OS.get_cmdline_user_args().has("a03-only")
	for item in SCULPTS:
		if only_a03 and item[0]!="kolossar_shadow":continue
		var key: String = item[0]
		var directory := "res://build/model_candidates/2026-11-06-sculpt/"
		var before := imported(directory+"source/"+key+".glb")
		var after := imported(directory+"candidate/"+key+".glb")
		var bm := inspect_scene(before)
		var am := inspect_scene(after)
		check(bm.triangles==item[1],key+" source triangles")
		check(am.triangles==item[2],key+" candidate triangles")
		var definition := CardDB.creature(StringName("creature_"+key))
		var base_ball := actor(definition,before)
		var next_ball := actor(definition,after)
		var bs := signature(base_ball)
		var cs := signature(next_ball)
		var materials := material_signature(next_ball)
		var references := PackedVector3Array()
		var base_samples: Array = []
		var next_samples: Array = []
		if key=="kolossar_shadow":
			references=reference_points(base_ball)
			base_samples=bind_samples(base_ball,references)
			next_samples=bind_samples(next_ball,references)
			check(materials.size()==2,key+" local material partition")
			var colored := 0
			for material in materials:
				var color: Array = material.tint
				if color[2]>color[0] and color[0]>color[1]:
					colored+=1
					check(material.has_texture,key+" source painted detail retained")
				else: check(color==[1.0,1.0,1.0,1.0],key+" original armor tint unchanged")
			check(colored==1,key+" one violet effect material reaches production shader")
		check(absf(bs.scale-cs.scale)<.00001,key+" retained body scale")
		check(absf(bs.height-cs.height)<.00001,key+" authored motion height")
		check(Vector3(bs.offset[0],bs.offset[1],bs.offset[2]).distance_to(Vector3(cs.offset[0],cs.offset[1],cs.offset[2]))<.00001,key+" retained body center")
		var max_delta := 0.0
		var max_world_delta := 0.0
		var candidate_poses: Array[PackedFloat64Array] = []
		var candidate_points: Array[PackedVector3Array] = []
		for action in ["idle","attack","hit"]:
			for frame in [0,12,24,48,90]:
				var bp := pose(base_ball,action,frame)
				var cp := pose(next_ball,action,frame)
				candidate_poses.append(cp)
				if not references.is_empty():
					var wp:=world_points(next_samples)
					candidate_points.append(wp)
					max_world_delta=maxf(max_world_delta,point_delta(world_points(base_samples),wp))
				check(bp.size()==cp.size(),key+" same skeleton")
				for i in mini(bp.size(),cp.size()):max_delta=maxf(max_delta,absf(bp[i]-cp[i]))
		check(max_delta<.00001,key+" preserved CPU pose palettes")
		check(max_world_delta<.00002,key+" retained skinned world points")
		ModelLifetime.release(base_ball,self)
		ModelLifetime.release(next_ball,self)
		await process_frame
		CreatureModels.clear()
		var production := "res://assets/creatures_hd/"+key+".glb"
		var promoted := FileAccess.get_sha256(production)==FileAccess.get_sha256(directory+"candidate/"+key+".glb")
		installed_both=installed_both and promoted
		var normal := load(production) as PackedScene
		var nm := inspect_scene(normal)
		check(nm.triangles==(item[2] if promoted else item[1]),key+" ordinary imported cache matches source SHA")
		var normal_ball := actor(definition)
		var ns := signature(normal_ball)
		var normal_materials := material_signature(normal_ball)
		if promoted: check(normal_materials==materials,key+" ordinary production shader material values")
		var normal_samples: Array=[]
		if not references.is_empty():normal_samples=bind_samples(normal_ball,references)
		check(absf(bs.scale-ns.scale)<.00001 and absf(bs.height-ns.height)<.00001,key+" ordinary actor normalization")
		check(Vector3(bs.offset[0],bs.offset[1],bs.offset[2]).distance_to(Vector3(ns.offset[0],ns.offset[1],ns.offset[2]))<.00001,key+" ordinary actor center")
		var normal_delta := 0.0
		var normal_world_delta := 0.0
		var index := 0
		for action in ["idle","attack","hit"]:
			for frame in [0,12,24,48,90]:
				var np := pose(normal_ball,action,frame)
				var cp := candidate_poses[index]
				check(np.size()==cp.size(),key+" ordinary skeleton size")
				if not references.is_empty():normal_world_delta=maxf(normal_world_delta,point_delta(world_points(normal_samples),candidate_points[index]))
				for i in mini(np.size(),cp.size()):normal_delta=maxf(normal_delta,absf(np[i]-cp[i]))
				index+=1
		check(normal_delta<.0001,key+" ordinary CPU palettes")
		check(normal_world_delta<.0001,key+" ordinary retained world points")
		ModelLifetime.release(normal_ball,self)
		await process_frame
		report.cases.append({"id":key,"installed":promoted,"source_sha256":FileAccess.get_sha256(directory+"source/"+key+".glb"),
			"candidate_sha256":FileAccess.get_sha256(directory+"candidate/"+key+".glb"),"production_sha256":FileAccess.get_sha256(production),
			"direct_before":bm,"direct_after":am,"ordinary_import":nm,"before_build":bs,"after_build":cs,"ordinary_build":ns,
			"palette_delta":max_delta,"ordinary_palette_delta":normal_delta,"sampled_actions":["idle","attack","hit"],"frames":[0,12,24,48,90]})
		report.cases[-1]["retained_world_samples"]=references.size()
		report.cases[-1]["max_world_delta"]=max_world_delta
		report.cases[-1]["ordinary_world_delta"]=normal_world_delta
		report.cases[-1]["direct_materials"]=materials
		report.cases[-1]["ordinary_materials"]=normal_materials
		CreatureModels.clear()
		CreatureModels.animation_library_cache.clear()
		await process_frame
	var output := "res://docs/audits/2026-11-06-model-sculpt-runtime/"
	DirAccess.make_dir_recursive_absolute(output)
	report["assertions"]=assertions
	report["failures"]=failures
	report["installed_both"]=installed_both and not only_a03
	report["installed_selected"]=installed_both
	report["only_a03"]=only_a03
	var filename := ("material-installed.json" if installed_both else "material-pre-promotion.json") if only_a03 else ("installed.json" if installed_both else "pre-promotion.json")
	var file := FileAccess.open(output.path_join(filename),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	file.close()
	print("MODEL SCULPT IMPORT: %d assertions, %d failures; CPU only" % [assertions,failures])
	quit(1 if failures else 0)
