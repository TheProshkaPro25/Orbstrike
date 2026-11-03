extends "res://tests/wardrobe_wrist_tests.gd"
## Focused visual/pose acceptance for the first street outfit.
const OUT := "res://build/checks/street-set/"

func capture(view: CharacterEditor,name: String) -> void:
	await frames()
	view.viewport.get_texture().get_image().save_png(OUT+name+".png")

func run() -> void:
	root.size = Vector2i(1280,900)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_size(root.get_viewport_rid(),1280,900)
	DirAccess.make_dir_recursive_absolute(OUT)
	var view := CharacterEditor.new()
	root.add_child(view)
	await frames()
	for model in 2:
		var p := PlayerProfile.DEFAULT.duplicate(true)
		p.vrm_model = model
		p.vrm_style = 9
		p.vrm_clothes = 5 if model == 0 else 6
		p.vrm_case = 1
		view._apply(p)
		check(view.avatar.case_part.visible,"case visible with bomber")
		check(view.avatar.hair_part.mesh.get_surface_count() <= 4,"hair surfaces merged")
		var locks := view.avatar.hair_part.mesh.surface_get_arrays(1)
		check(locks[Mesh.ARRAY_NORMAL][0].x > .5,"tail normals face outwards")
		check(not view.selectors.vrm_case.disabled,"case selector enabled for bomber")
		for angle in [0.0,.65,PI/2,PI]:
			view.avatar.rotation.y = angle
			view.set_face_view(false)
			await capture(view,"model-%d-full-%.2f" % [model,angle])
			view.set_face_view(true)
			await capture(view,"model-%d-hair-%.2f" % [model,angle])
		view.avatar.rotation.y = 0
		for light in [1,2]:
			view.set_lighting(light)
			view.set_face_view(false)
			await capture(view,"model-%d-light-%d" % [model,light])
		view.set_lighting(0)
		view._select(0,"vrm_clothes")
		check(not view.avatar.case_part.visible and view.selectors.vrm_case.disabled,"incompatible outfit hides case")
		check(view.draft.vrm_case == 1,"case selection remembered")
		view._select(p.vrm_clothes,"vrm_clothes")
		check(view.avatar.case_part.visible,"case returns with bomber")
		view._select(0,"vrm_case")
		check(not view.avatar.case_part.visible,"case can be removed")
		view._select(1,"vrm_case")
		var fighter := VrmFighter.new()
		view.avatar.get_parent().add_child(fighter)
		fighter.apply_profile(p)
		fighter.set_process(false)
		view.avatar.hide()
		var rings := cuff_rings(fighter,fighter.body_part.mesh)
		var hips := fighter.skeleton.find_bone("Hips")
		for surface in fighter.case_part.mesh.get_surface_count():
			var a := fighter.case_part.mesh.surface_get_arrays(surface)
			for i in a[0].size():
				check(a[Mesh.ARRAY_BONES][i*4] == hips and a[Mesh.ARRAY_WEIGHTS][i*4] == 1.0,"case bound to hips")
		var bank := fighter.native_motions
		for native in ([true,false] if bank else [false]):
			fighter.native_motions = native
			for action in ["idle","throw","card_throw","command","gate","victory","defeat"]:
				fighter.play_motion(action)
				if action == "command": fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]),0)
				for time in [0.0,.22,.5,.92,1.0,1.75,2.35]:
					fighter.sample_motion(minf(time,VrmFighter.DURATIONS.get(action,2.0)))
					fighter.skeleton.force_update_all_bone_transforms()
					for side in ["Left","Right"]:
						var fit := cuff_fit(fighter,rings,side)
						check(fit.offset < .012 and fit.inside,"bomber cuff %d %s %s %.2f" % [model,action,side,time])
					if native == bank and time in [.5,.92] and action in ["idle","throw","command","gate"]:
						await capture(view,"model-%d-%s-%.2f" % [model,action,time])
		fighter.queue_free()
		view.avatar.show()
		await frames()
		# Source and per-instance materials stay isolated when the new parts change colour.
		var original: Color = VrmParts.material_for(view.avatar.body_part.mesh,1).get_shader_parameter("_Color")
		view._select(3,"vrm_outfit")
		check(VrmParts.material_for(view.avatar.body_part.mesh,1).get_shader_parameter("_Color") == original,"bomber source material immutable")
	var warm_parent := Node3D.new()
	view.avatar.get_parent().add_child(warm_parent)
	await StartupCatalog.warm_avatar_parts(warm_parent)
	check(warm_parent.get_child_count() == 2,"startup warm keeps two actors")
	warm_parent.queue_free()
	view.queue_free()
	await frames()
	print("Street set: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
