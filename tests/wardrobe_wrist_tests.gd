extends SceneTree
## Close views of the actual skinned sleeve/hand junction, not bone markers.
var checks := 0
var failures := 0
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)

func cuff_rings(fighter: VrmFighter,mesh: ArrayMesh) -> Dictionary:
	var names: PackedStringArray = mesh.get_meta("surface_materials")
	var surface := -1
	for i in names.size():
		if "Tops_" in names[i]: surface = i
	var a := mesh.surface_get_arrays(surface)
	# The cuff has a closed thickness, so there is no topological boundary.
	# Use the distal cloth cross-section, welding UV duplicates.
	var welded := {}
	for i in a[0].size():
		var key: Vector3 = a[0][i].snapped(Vector3.ONE*.00001)
		if not welded.has(key): welded[key] = i
	var result := {"arrays":a}
	var stride: int = a[Mesh.ARRAY_BONES].size()/a[0].size()
	for side in ["Left","Right"]:
		var hand := fighter.body_part.skin.get_bind_pose(fighter.skeleton.find_bone(side+"Hand")).affine_inverse().origin
		var elbow := fighter.body_part.skin.get_bind_pose(fighter.skeleton.find_bone(side+"LowerArm")).affine_inverse().origin
		var axis := (hand-elbow).normalized()
		var end := -INF
		var sleeve := PackedInt32Array()
		for index in welded.values():
			var influence := 0.0
			for k in stride:
				var name := str(fighter.skeleton.get_bone_name(a[Mesh.ARRAY_BONES][index*stride+k]))
				if name in [side+"LowerArm",side+"Hand"]: influence += a[Mesh.ARRAY_WEIGHTS][index*stride+k]
			var offset: Vector3 = a[0][index]-hand
			if influence > .5 and offset.length() < .14:
				sleeve.append(index)
				end = maxf(end,offset.dot(axis))
		var ring := PackedInt32Array()
		for index in sleeve:
			var offset: Vector3 = a[0][index]-hand
			if offset.dot(axis) > end-.025: ring.append(index)
		result[side] = ring
	return result

func cuff_fit(fighter: VrmFighter,rings: Dictionary,side: String) -> Dictionary:
	var a: Array = rings.arrays
	var stride: int = a[Mesh.ARRAY_BONES].size()/a[0].size()
	var center := Vector3.ZERO
	var points := PackedVector3Array()
	for index in rings[side]:
		var p := Vector3.ZERO
		for k in stride:
			var bind: int = a[Mesh.ARRAY_BONES][index*stride+k]
			var bone := fighter.body_part.skin.get_bind_bone(bind)
			p += fighter.skeleton.get_bone_global_pose(bone)*fighter.body_part.skin.get_bind_pose(bind)*a[0][index]*a[Mesh.ARRAY_WEIGHTS][index*stride+k]
		var world := fighter.skeleton.to_global(p)
		center += world
		points.append(world)
	center /= maxi(1,rings[side].size())
	var hand := fighter._bone_world(side+"Hand")
	var axis := (hand-fighter._bone_world(side+"LowerArm")).normalized()
	var offset := center-hand
	var u := axis.cross(Vector3.FORWARD).normalized()
	if u.length() < .1: u = axis.cross(Vector3.UP).normalized()
	var v := axis.cross(u).normalized()
	var section := PackedVector2Array()
	for point in points:
		var delta := point-hand
		section.append(Vector2(delta.dot(u),delta.dot(v)))
	var hull := Geometry2D.convex_hull(section)
	return {"offset":(offset-axis*offset.dot(axis)).length(),"inside":Geometry2D.is_point_in_polygon(Vector2.ZERO,hull)}
func _initialize() -> void: call_deferred("run")
func frames() -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	root.size = Vector2i(1000,800)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_size(root.get_viewport_rid(),1000,800)
	DirAccess.make_dir_recursive_absolute("res://build/checks/wardrobe-wrists")
	var view := VrmPreview.new()
	root.add_child(view)
	var parent := view.avatar.get_parent()
	view.avatar.queue_free()
	var fighter := VrmFighter.new()
	parent.add_child(fighter)
	view.avatar = fighter
	fighter.set_process(false)
	for model in 2:
		for outfit in ([1,2,3,4,5] if model == 0 else [3,4,5,6]):
			var p := PlayerProfile.DEFAULT.duplicate(true)
			p.vrm_model = model
			p.vrm_clothes = outfit
			fighter.apply_profile(p)
			var rings := cuff_rings(fighter,fighter.body_part.mesh)
			for side in ["Right","Left"]: check(rings[side].size() >= 8,"distal cuff cloth sampled")
			# The historical failure used the same bones but a different cloth axis.
			# Compare old resources only when the local pre-fix snapshot is available.
			var old_path := "res://build/checks/wardrobe-wrists/before/body_%d_%d.res" % [model,outfit]
			if FileAccess.file_exists(old_path):
				var old := cuff_rings(fighter,load(old_path))
				for b in fighter._bind_poses.size(): fighter.skeleton.set_bone_pose(b,fighter._bind_poses[b])
				fighter.skeleton.force_update_all_bone_transforms()
				print("BEFORE cuff ",model,"/",outfit," ",cuff_fit(fighter,old,"Right"))
			var bank := fighter.native_motions
			for native in ([true,false] if bank else [false]):
				fighter.native_motions = native
				for action in ["throw","card_throw","command","gate"]:
					fighter.play_motion(action)
					if action == "command": fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]),0)
					for time in [0.0,.22,.5,.90,.92,.94,.98,1.0,1.02,1.75,2.35]:
						fighter.sample_motion(minf(time,VrmFighter.DURATIONS[action]))
						fighter.skeleton.force_update_all_bone_transforms()
						for side in ["Right","Left"]:
							var fit := cuff_fit(fighter,rings,side)
							check(fit.offset < .012 and fit.inside,"wrist inside skinned cuff %d/%d %s t=%.2f %s bank=%s" % [model,outfit,action,time,side,native])
			fighter.native_motions = bank
			for motion in ["editor","idle","command","throw","card_throw"]:
				fighter.reset_motion()
				if motion == "editor":
					for b in fighter._bind_poses.size(): fighter.skeleton.set_bone_pose(b,fighter._bind_poses[b])
				else:
					fighter.play_motion(motion)
					if motion == "command": fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]),0)
					fighter.sample_motion(.5)
				fighter.skeleton.force_update_all_bone_transforms()
				for side in ["Right","Left"]:
					var fit := cuff_fit(fighter,rings,side)
					check(fit.offset < .012 and fit.inside,"wrist inside actual cuff %d/%d %s %s: %s" % [model,outfit,motion,side,fit])
					print("CUFF ",model,"/",outfit," ",motion," ",side," ",fit)
				var atlas := Image.create(1200,600,false,Image.FORMAT_RGB8)
				for side_index in 2:
					var side: String = ["Right","Left"][side_index]
					var hand := fighter._bone_world(side+"Hand")
					var elbow := fighter._bone_world(side+"LowerArm")
					var target := hand.lerp(elbow,.20)
					view.camera.global_position = target+Vector3(.10 if side_index == 0 else -.10,.06,.65)
					view.camera.look_at(target)
					await frames()
					var shot := view.viewport.get_texture().get_image()
					var wh := mini(shot.get_width(),shot.get_height())
					shot = shot.get_region(Rect2i((shot.get_width()-wh)/2,(shot.get_height()-wh)/2,wh,wh))
					shot.resize(600,600,Image.INTERPOLATE_LANCZOS)
					shot.convert(Image.FORMAT_RGB8)
					atlas.blit_rect(shot,Rect2i(0,0,600,600),Vector2i(side_index*600,0))
				atlas.save_png("res://build/checks/wardrobe-wrists/%d-%d-%s.png" % [model,outfit,motion])
				if motion == "command" and outfit == (2 if model == 0 else 3):
					var hand := fighter._bone_world("RightHand")
					for angle in ["side","rear"]:
						var offset := Vector3(-.65,.05,.08) if angle == "side" else Vector3(-.55,.10,-.40)
						view.camera.global_position = hand+offset
						view.camera.look_at(hand)
						await frames()
						view.viewport.get_texture().get_image().save_png("res://build/checks/wardrobe-wrists/%d-command-%s.png" % [model,angle])
	view.queue_free()
	await frames()
	print("Wardrobe wrists: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
