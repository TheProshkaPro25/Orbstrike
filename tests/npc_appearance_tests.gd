extends SceneTree
## Seven permanent NPCs on reused runtime fighters, with compatible full costumes.
const OUT := "res://build/checks/npc-appearance/"
var checks := 0
var failures := 0
var viewport: SubViewport
var camera: Camera3D
var fighters: Array[VrmFighter] = []
var records: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func frames() -> void:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw

func tile(atlas: Image, pos: Vector2i, size: Vector2i) -> void:
	await frames()
	var shot := viewport.get_texture().get_image()
	shot.resize(size.x,size.y,Image.INTERPOLATE_LANCZOS)
	shot.convert(Image.FORMAT_RGBA8)
	atlas.blit_rect(shot,Rect2i(Vector2i.ZERO,size),pos)

func frame_body(fighter: VrmFighter, face: bool = false) -> void:
	var scale_y: float = VrmAvatar.HEIGHTS[fighter.appearance_profile.vrm_height]
	var head := fighter.skeleton.find_bone("Head")
	var height := (fighter.skeleton.get_bone_global_rest(head).origin.y + .09)*scale_y
	var full_height := height + .20*scale_y
	var distance := full_height/(2.0*tan(deg_to_rad(camera.fov)*.5))*1.25
	camera.position = Vector3(0,height,.96*scale_y) if face else Vector3(0,full_height*.51,distance)
	camera.look_at(Vector3(0,height,0) if face else Vector3(0,full_height*.50,0))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	viewport = SubViewport.new()
	viewport.size = Vector2i(400,600)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("354356")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("dbe3f1")
	environment.environment.ambient_light_energy = .35
	world.add_child(environment)
	for angle in [Vector3(-25,-30,0),Vector3(-15,140,0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = angle
		light.light_energy = .75 if angle.y < 0 else .20
		world.add_child(light)
	camera = Camera3D.new()
	camera.fov = 28
	world.add_child(camera)
	# One resident per base: preceding NPC/player details must never contaminate the next look.
	for model in 2:
		var fighter := VrmFighter.new()
		world.add_child(fighter)
		fighter.set_process(false)
		fighters.append(fighter)
	var ids: Array[int] = [1,2,3,4,5,6,7]
	var selected := OS.get_environment("NPC_APPEARANCE_IDS")
	if not selected.is_empty():
		ids.clear()
		for item in selected.split(","):
			var id := int(item)
			if id >= 1 and id <= 7 and not ids.has(id): ids.append(id)
		check(not ids.is_empty(),"selected NPC IDs valid")
		if ids.is_empty(): quit(1); return
	var identities := {}
	var lineup := Image.create(400*ids.size(),600,false,Image.FORMAT_RGBA8)
	for id in ids:
		var profile := PlayerProfile.npc_profile(id)
		check(profile.name == Tournament.NPCS[id-1][0],"NPC %d identity matches tournament" % id)
		var original := profile.duplicate(true)
		profile.vrm_case = 1
		check(PlayerProfile.npc_profile(id) == original,"NPC %d returned data is isolated" % id)
		profile = original
		check(profile.vrm_denim == 0 and profile.vrm_case == 0,"NPC %d has no incompatible overlays" % id)
		var signature := "%s/%s/%s/%s/%s" % [profile.vrm_model,profile.vrm_style,profile.vrm_clothes,profile.vrm_hair,profile.vrm_outfit]
		check(not identities.has(signature),"NPC %d has a distinct identity" % id)
		identities[signature] = true
		var fighter := fighters[profile.vrm_model]
		for actor in fighters: actor.hide()
		fighter.show()
		var dirty := PlayerProfile.DEFAULT.duplicate(true)
		dirty.vrm_model = profile.vrm_model
		dirty.vrm_style = 2
		dirty.vrm_clothes = VrmParts.BOMBER_IDS[profile.vrm_model]
		dirty.vrm_case = 1
		dirty.vrm_denim = 14
		fighter.apply_profile(dirty)
		fighter.apply_profile(profile)
		check(fighter.appearance_profile == profile,"NPC %d exact profile after resident reuse" % id)
		check(fighter.body_part.mesh == VrmParts.BODY[profile.vrm_model][profile.vrm_clothes],"NPC %d correct complete outfit" % id)
		check(not fighter.case_part.visible,"NPC %d no stale case after reuse" % id)
		for surface in fighter.body_part.mesh.get_surface_count():
			check(fighter.body_part.get_surface_override_material(surface) != null,"NPC %d material %d present" % [id,surface])
		var sheet := Image.create(1600,1200,false,Image.FORMAT_RGBA8)
		for angle in 3:
			fighter.rotation.y = [0.0,.70,PI][angle]
			fighter.reset_motion()
			fighter.sample_motion(.5)
			frame_body(fighter)
			await tile(sheet,Vector2i(angle*400,0),Vector2i(400,600))
			if angle == 0: await tile(lineup,Vector2i(ids.find(id)*400,0),Vector2i(400,600))
		fighter.rotation.y = 0
		frame_body(fighter,true)
		await tile(sheet,Vector2i(1200,0),Vector2i(400,600))
		frame_body(fighter)
		var actions := ["throw","card_throw","command","gate"]
		for action in actions.size():
			fighter.play_motion(actions[action])
			fighter.sample_motion(fighter.ball_release_time() if action == 0 else .9)
			fighter.skeleton.force_update_all_bone_transforms()
			for bone in fighter.skeleton.get_bone_count():
				check(fighter.skeleton.get_bone_global_pose(bone).origin.is_finite(),"NPC %d %s finite pose %d" % [id,actions[action],bone])
			await tile(sheet,Vector2i(action*400,600),Vector2i(400,600))
		var file := OUT+"%02d-%s.png" % [id,str(profile.name).replace(" ","-")]
		check(sheet.save_png(file) == OK,"NPC %d view sheet saved" % id)
		records.append({"id":id,"name":profile.name,"profile":profile,"sheet":file})
	var suffix := "" if selected.is_empty() else "-selected-"+selected.replace(",","-")
	lineup.save_png(OUT+"lineup"+suffix+".png")
	for fighter in fighters: fighter.queue_free()
	await frames()
	viewport.queue_free()
	await process_frame
	var summary := FileAccess.open(OUT+"summary"+suffix+".json",FileAccess.WRITE)
	summary.store_string(JSON.stringify({"checks":checks,"failures":failures,"scenarios":["permanent_profiles","resident_actor_reuse","complete_costumes","front_quarter_back_face","throw_card_command_gate"],"npcs":records},"  "))
	summary.close()
	print("NPC appearance: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
