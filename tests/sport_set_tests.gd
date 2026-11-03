extends "res://tests/wardrobe_wrist_tests.gd"
## The new outfit only: skinned cuffs, geometry, hair fit views and seven gestures.
const OUT := "res://build/checks/sport-set/"

func inspect_mesh(mesh: ArrayMesh, skinned: bool, bones: int) -> void:
	var names: PackedStringArray = mesh.get_meta("surface_materials")
	check(names.size() == mesh.get_surface_count(),"material mapping covers every surface")
	# Resolve at runtime to avoid a GDScript load cycle in this test harness.
	var parts = load("res://scenes/avatar/vrm_parts.gd")
	for surface in mesh.get_surface_count():
		check(parts.material_for(mesh,surface) != null,"surface material resolves")
		var a := mesh.surface_get_arrays(surface)
		check(not a[Mesh.ARRAY_VERTEX].is_empty(),"surface has geometry")
		for p in a[Mesh.ARRAY_VERTEX]: check(p.is_finite(),"finite vertex")
		if a[Mesh.ARRAY_INDEX] != null:
			for i in a[Mesh.ARRAY_INDEX]: check(i >= 0 and i < a[0].size(),"valid triangle index")
		if not skinned: continue
		var stride: int = a[Mesh.ARRAY_BONES].size()/a[0].size()
		check(stride == 4 or stride == 8,"skinned surface has bone weights")
		for i in a[0].size():
			var total := 0.0
			for k in stride:
				var weight: float = a[Mesh.ARRAY_WEIGHTS][i*stride+k]
				var bone: int = a[Mesh.ARRAY_BONES][i*stride+k]
				check(is_finite(weight) and weight >= 0 and bone >= 0 and bone < bones,"valid skin influence")
				total += weight
			check(absf(total-1.0) < .015,"skin weights normalized")

func tile(view: CharacterEditor, atlas: Image, position: Vector2i, size: Vector2i) -> void:
	await frames()
	var shot := view.viewport.get_texture().get_image()
	var width := mini(shot.get_width(),int(shot.get_height()*float(size.x)/size.y))
	shot = shot.get_region(Rect2i((shot.get_width()-width)/2,0,width,shot.get_height()))
	shot.resize(size.x,size.y,Image.INTERPOLATE_LANCZOS)
	shot.convert(Image.FORMAT_RGBA8)
	atlas.blit_rect(shot,Rect2i(Vector2i.ZERO,size),position)

func run() -> void:
	root.size = Vector2i(1280,900)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_size(root.get_viewport_rid(),1280,900)
	DirAccess.make_dir_recursive_absolute(OUT)
	var view := CharacterEditor.new()
	root.add_child(view)
	view._set_playing(false)
	var motions := Image.create(1960,800,false,Image.FORMAT_RGBA8)
	for model in 2:
		var p := PlayerProfile.DEFAULT.duplicate(true)
		p.vrm_model = model
		p.vrm_style = 10
		p.vrm_clothes = VrmParts.SPORT_IDS[model]
		p.vrm_case = 1
		p.vrm_denim = 14
		view._apply(p)
		var fighter = view.avatar
		check(not fighter.is_processing(),"preview samples exactly once")
		check(not fighter.case_part.visible and view.selectors.vrm_case.disabled,"sports outfit hides incompatible case")
		check(view.draft.vrm_denim == 14 and view.selectors.vrm_denim.disabled,"denim choice retained but disabled")
		inspect_mesh(fighter.body_part.mesh,true,fighter.skeleton.get_bone_count())
		inspect_mesh(fighter.hair_part.mesh,false,0)
		var rings := cuff_rings(fighter,fighter.body_part.mesh)
		for side in ["Left","Right"]: check(rings[side].size() >= 8,"cuff ring sampled")
		var angles := [0.0,.7,PI/2,PI]
		var sheet := Image.create(1440,900,false,Image.FORMAT_RGBA8)
		for i in angles.size():
			fighter.rotation.y = angles[i]
			view.set_face_view(false)
			await tile(view,sheet,Vector2i(i*360,0),Vector2i(360,450))
			view.set_face_view(true)
			await tile(view,sheet,Vector2i(i*360,450),Vector2i(360,450))
		sheet.save_png(OUT+"model-%d-views.png" % model)
		fighter.rotation.y = 0
		var installed: bool = fighter.native_motions
		for native in ([true,false] if installed else [false]):
			fighter.native_motions = native
			for index in view.MOTIONS.size():
				view._start_motion(index)
				var duration: float = view._motion_duration()
				for time in [0.0,.22,.5,.92,1.2,1.75,duration]:
					fighter.sample_motion(minf(time,duration))
					fighter.skeleton.force_update_all_bone_transforms()
					for side in ["Left","Right"]:
						var fit := cuff_fit(fighter,rings,side)
						check(fit.offset < .012 and fit.inside,"sports cuff %d/%s/%s %.2f bank=%s" % [model,view.MOTIONS[index],side,time,native])
				if native == installed:
					fighter.sample_motion(.9 if index in [5,6] else .5)
					view.set_face_view(false)
					await tile(view,motions,Vector2i(index*280,model*400),Vector2i(280,400))
		fighter.native_motions = installed
		for height in [0,2]:
			p.vrm_height = height
			view._apply(p)
			view._start_motion(3)
			fighter.sample_motion(.9)
			fighter.skeleton.force_update_all_bone_transforms()
			for side in ["Left","Right"]:
				var fit := cuff_fit(fighter,rings,side)
				check(fit.offset < .014 and fit.inside,"sports cuff at height extreme")
		view._start_motion(0)
		view._select(3,"vrm_outfit")
		view._select(2,"vrm_hair")
		view.set_face_view(false)
		for light in 3:
			view.set_lighting(light)
			await frames()
			view.viewport.get_texture().get_image().save_png(OUT+"model-%d-palette-light-%d.png" % [model,light])
		view.set_lighting(0)
	motions.save_png(OUT+"motions.png")
	var warm_parent := Node3D.new()
	view.avatar.get_parent().add_child(warm_parent)
	await StartupCatalog.warm_avatar_parts(warm_parent)
	check(warm_parent.get_child_count() == 2,"expanded catalog warms on both bases")
	warm_parent.queue_free()
	view.queue_free()
	await frames()
	print("Sport set: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
