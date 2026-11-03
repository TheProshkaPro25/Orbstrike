extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
func frames(count: int) -> void:
	for frame in count: await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	RenderingServer.viewport_set_size(root.get_viewport_rid(),1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/checks/vrm-fighter")
	var view := VrmPreview.new()
	root.add_child(view)
	var parent := view.avatar.get_parent()
	view.avatar.queue_free()
	var fighter := VrmFighter.new()
	parent.add_child(fighter)
	view.avatar = fighter
	fighter.set_process(false)
	var atlas := Image.create(2000,(VrmParts.BODY[0].size()+VrmParts.BODY[1].size())*600,false,Image.FORMAT_RGBA8)
	var reaction_atlas := Image.create(2000,1200,false,Image.FORMAT_RGBA8)
	var row := 0
	for model in 2:
		for clothes in VrmParts.BODY[model].size():
			var profile := PlayerProfile.DEFAULT.duplicate(true)
			profile.vrm_model = model
			profile.vrm_style = 1
			profile.vrm_clothes = clothes
			profile.vrm_height = 2 if model == 0 else 0
			fighter.apply_profile(profile)
			# Both the installed bank and CC0 fallback must leave the free hand down.
			var installed_bank := fighter.native_motions
			for use_bank in ([true,false] if installed_bank else [false]):
				fighter.native_motions = use_bank
				fighter.play_motion("command")
				fighter.sample_motion(0.0)
				var start_hand := fighter._bone_world("RightHand")
				var start_hip := fighter._bone_world("Hips")
				fighter.sample_motion(.01)
				check(start_hand.distance_to(fighter._bone_world("RightHand")) < .04,"immediate gesture enters without hand snap")
				check(start_hip.distance_to(fighter._bone_world("Hips")) < .02,"immediate gesture enters without pelvis snap")
				for time in [0.0,.04,.08,.15,.22,.40,.75,1.20,1.70]:
					fighter.sample_motion(time)
					var rig: Skeleton3D = fighter.skeleton
					rig.force_update_all_bone_transforms()
					var hand := rig.get_bone_global_pose(rig.find_bone("LeftHand")).origin
					var elbow := rig.get_bone_global_pose(rig.find_bone("LeftLowerArm")).origin
					var shoulder := rig.get_bone_global_pose(rig.find_bone("LeftUpperArm")).origin
					check(hand.y < elbow.y-.06 and elbow.y < shoulder.y-.08,"free hand stays lowered throughout ability %s/%.2f" % [use_bank,time])
				fighter.sample_motion(0.0)
				var card_hand := fighter._bone_world("RightHand")
				fighter.sample_motion(.15)
				check(card_hand.distance_to(fighter._bone_world("RightHand")) > (.10 if use_bank else .04),"right card arm extends immediately within 150ms bank=%s model=%d distance=%.3f" % [use_bank,model,card_hand.distance_to(fighter._bone_world("RightHand"))])
				# The real card face must stay towards the opponent through the hold.
				fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]),0)
				for time in [.35,.75,1.20,1.70]:
					fighter.sample_motion(time)
					var face := fighter.ability_card.global_basis.y.normalized()
					check(face.dot(fighter.global_basis.z.normalized()) > .90,"card face presented forward during hold bank=%s t=%.2f" % [use_bank,time])
					var hand := fighter._bone_world("RightHand")
					var elbow := fighter._bone_world("RightLowerArm")
					check(hand.y > elbow.y+.08,"presentation forearm rises naturally from elbow")
				fighter.sample_motion(1.70)
				var held := fighter._bone_world("RightHand")
				fighter.sample_motion(1.75)
				check(held.distance_to(fighter._bone_world("RightHand")) < .04,"extended hand held until recovery")
				var last_hand := fighter._bone_world("RightHand")
				for frame in range(1,64):
					fighter.sample_motion(1.75+float(frame)/63*(VrmFighter.DURATIONS.command-1.75))
					var next_hand := fighter._bone_world("RightHand")
					check(last_hand.distance_to(next_hand) < .045,"smooth hand recovery bank=%s frame=%d" % [use_bank,frame])
					last_hand = next_hand

			fighter.native_motions = installed_bank
			fighter.reset_motion()
			view.set_face_view(false)
			view.camera.position.z *= 1.25
			check(fighter.body_part.skin != null,"costume has skin")
			for surface in fighter.body_part.mesh.get_surface_count():
				var arrays := fighter.body_part.mesh.surface_get_arrays(surface)
				check(not arrays[Mesh.ARRAY_BONES].is_empty() and not arrays[Mesh.ARRAY_WEIGHTS].is_empty(),"costume weights retained")
			var column := 0
			for motion in ["idle","throw","command","gate"]:
				fighter.reset_motion()
				if motion != "idle": fighter.play_motion(motion)
				if motion == "command": fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]),0)
				fighter.sample_motion(.4 if motion == "throw" else .85 if motion == "victory" else .5)
				await frames(4)
				var image := view.viewport.get_texture().get_image()
				var width := image.get_height()*5/6
				image = image.get_region(Rect2i((image.get_width()-width)/2,0,width,image.get_height()))
				image.resize(500,600,Image.INTERPOLATE_LANCZOS)
				image.convert(Image.FORMAT_RGBA8)
				atlas.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i(column*500,row*600))
				column += 1
			for action in ["throw","card_throw","command","gate"]:
				fighter.play_motion(action)
				fighter.sample_motion(.34)
				var opening := 0.0
				for entry in fighter._visemes: opening += entry.mesh.get_blend_shape_value(entry.index)
				check(opening > .1,"mouth speaks on "+action)
				fighter.sample_motion(VrmFighter.DURATIONS[action])
				for entry in fighter._visemes: check(is_zero_approx(entry.mesh.get_blend_shape_value(entry.index)),"mouth closes after action")
				check(fighter.hand_position().distance_to(fighter.skeleton.to_global(fighter.skeleton.get_bone_global_pose(fighter.skeleton.find_bone("RightHand")).origin)) < .001,"release follows actual hand")
			if model == 0 and clothes == 0:
				for action in ["throw","card_throw","command","gate"]:
					fighter.play_motion(action)
					if action == "command": fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]),0)
					for frame in 24:
						fighter.sample_motion(float(frame)/23*VrmFighter.DURATIONS[action])
						await frames(2)
						var shot := view.viewport.get_texture().get_image()
						var width := shot.get_height()*5/6
						shot = shot.get_region(Rect2i((shot.get_width()-width)/2,0,width,shot.get_height()))
						shot.resize(500,600,Image.INTERPOLATE_LANCZOS)
						shot.save_png("res://build/checks/vrm-fighter/%s-%02d.png" % [action,frame])
			# Card presentation: all elemental palettes, hand tracking and interruption.
			for element in 6:
				fighter.play_motion("command")
				fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]),element)
				fighter.sample_motion(0.0)
				check(fighter.ability_card.visible and is_zero_approx(fighter.ability_card.strength),"card appears before ignition")
				var initial := fighter.ability_card.global_position
				fighter.sample_motion(fighter.ability_ignition_time()+.25)
				check(fighter.ability_card.strength > .95,"card ignites at extended hold")
				check(fighter.ability_card.light.light_color == VisualUtil.attr_color(element),"element palette %d" % element)
				check(initial.distance_to(fighter.ability_card.global_position) > .05,"card follows arm extension")
				check(fighter.ability_card.global_position.distance_to(fighter._bone_world("RightHand")) < .25,"card stays at fingers")
				fighter.sample_motion(VrmFighter.DURATIONS.command)
				check(not fighter.ability_card.visible and is_zero_approx(fighter.ability_card.light.light_energy),"card and light end with gesture")
			fighter.play_motion("command")
			fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]),4)
			fighter.sample_motion(.95)
			fighter.reset_motion()
			check(not fighter.ability_card.prepared and not fighter.ability_card.visible,"reset clears prepared card")
			# A real pinch: pads on opposite sides of the physical card plane.
			fighter.play_motion("command")
			fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]),0)
			for time in [.05,.15,.22,.40,.95,1.45]:
				fighter.sample_motion(time)
				var index_pad := fighter.ability_card.to_local(fighter.skeleton.to_global(fighter._finger_pad("Index","Right")))
				var thumb_pad := fighter.ability_card.to_local(fighter.skeleton.to_global(fighter._finger_pad("Thumb","Right")))
				for finger in ["Index","Middle","Ring","Little"]:
					var pad := fighter.ability_card.to_local(fighter.skeleton.to_global(fighter._finger_pad(finger,"Right")))
					check(pad.y > .003,finger+" pad axis on card face")
					check(absf(pad.x) < .06 and absf(pad.z) < .084,finger+" inside face edges")
				check(absf(index_pad.x-thumb_pad.x) < .004,"thumb behind index support line")
				for finger in ["Index","Middle","Ring","Little"]:
					for joint in ["Proximal","Intermediate","Distal"]:
						var point := fighter.ability_card.to_local(fighter._bone_world("Right"+finger+joint))
						check(point.y > .003,"whole finger chain in front: "+finger+joint)
				check(absf(index_pad.x) < .06 and absf(index_pad.z) < .084,"pinch lies inside card edges")
			fighter.sample_motion(.95)
			var front_intrusions := 0
			var back_intrusions := 0
			var gaps := {"Index":INF,"Middle":INF,"Ring":INF,"Little":INF}
			var thumb_contact := -INF
			var into_card := fighter.ability_card.global_transform.affine_inverse()*fighter.skeleton.global_transform
			for sample in fighter.hand_surface_samples("Right"):
				var point: Vector3 = into_card*sample.point
				if absf(point.x) >= .059 or absf(point.z) >= .083: continue
				if sample.group == "fingers": gaps[sample.finger] = minf(gaps[sample.finger],point.y)
				if sample.group == "thumb": thumb_contact = maxf(thumb_contact,point.y)
				if sample.group != "thumb" and point.y < .0006: front_intrusions += 1
				if sample.group == "thumb" and point.y > -.0003: back_intrusions += 1
			check(front_intrusions == 0,"actual finger/palm skin stays in front of card %d/%d: %d" % [model,clothes,front_intrusions])
			check(back_intrusions == 0,"actual thumb skin stays behind card %d/%d: %d" % [model,clothes,back_intrusions])
			for finger in gaps: check(gaps[finger] < .008,"skin contact gap %d/%d %s: %.4f" % [model,clothes,finger,gaps[finger]])
			check(thumb_contact > -.006,"thumb contact gap %d/%d: %.4f" % [model,clothes,thumb_contact])
			var saved_grip_camera := view.camera.global_transform
			var grip_frame := fighter.ability_card.global_transform.orthonormalized()
			fighter.ability_card.sample(.1)
			for side in ["front","back","edge"]:
				var offset := grip_frame.basis.y*.58 if side == "front" else -grip_frame.basis.y*.58 if side == "back" else grip_frame.basis.x*.60+grip_frame.basis.y*.025
				view.camera.global_position = grip_frame.origin+offset
				view.camera.look_at(grip_frame.origin,-grip_frame.basis.z)
				await frames(2)
				view.viewport.get_texture().get_image().save_png("res://build/checks/vrm-fighter/skin-grip-%d-%d-%s.png" % [model,clothes,side])
			view.camera.global_transform = saved_grip_camera
			# Gate uses the opposite hand: inspect actual skinned contact there too.
			fighter.play_motion("card_throw")
			fighter.sample_motion(.75)
			fighter.ability_card.global_transform = fighter.card_hand_transform("Right")
			fighter.ability_card.prepared = true
			fighter.ability_card.sample(.1)
			var right_frame := fighter.ability_card.global_transform
			var right_into := right_frame.affine_inverse()*fighter.skeleton.global_transform
			var right_gaps := {"Index":INF,"Middle":INF,"Ring":INF,"Little":INF}
			var right_thumb := -INF
			for sample in fighter.hand_surface_samples("Right"):
				var point: Vector3 = right_into*sample.point
				if absf(point.x) >= .059 or absf(point.z) >= .083: continue
				if sample.group == "fingers":
					check(point.y >= .0006,"gate finger skin in front of card")
					right_gaps[sample.finger] = minf(right_gaps[sample.finger],point.y)
				if sample.group == "thumb":
					check(point.y <= -.0003,"gate thumb skin behind card")
					right_thumb = maxf(right_thumb,point.y)
			for finger in right_gaps: check(right_gaps[finger] < .008,"gate contact gap "+finger)
			check(right_thumb > -.006,"gate thumb reaches card")
			for side in ["front","back","edge"]:
				var offset := right_frame.basis.y*.58 if side == "front" else -right_frame.basis.y*.58 if side == "back" else right_frame.basis.x*.60+right_frame.basis.y*.025
				view.camera.global_position = right_frame.origin+offset
				view.camera.look_at(right_frame.origin,-right_frame.basis.z)
				await frames(2)
				view.viewport.get_texture().get_image().save_png("res://build/checks/vrm-fighter/gate-grip-%d-%d-%s.png" % [model,clothes,side])
			view.camera.global_transform = saved_grip_camera
			fighter.play_motion("command")
			fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]),0)
			fighter.sample_motion(.95)
			if clothes == 0:
				fighter.sample_motion(.95)
				for finger in ["Index","Middle","Ring","Little"]:
					var proximal := fighter._bone_world("Right"+finger+"Proximal")
					var intermediate := fighter._bone_world("Right"+finger+"Intermediate")
					var distal := fighter._bone_world("Right"+finger+"Distal")
					var tip_index: int = fighter.skeleton.get_bone_children(fighter.skeleton.find_bone("Right"+finger+"Distal"))[0]
					var tip := fighter.skeleton.to_global(fighter.skeleton.get_bone_global_pose(tip_index).origin)
					var first_bend := (intermediate-proximal).angle_to(distal-intermediate)
					var last_bend := (distal-intermediate).angle_to(tip-distal)
					check(first_bend > .08 and first_bend < .25,"slight proximal bend "+finger)
					var across := fighter.ability_card.global_basis.x.normalized()
					check((intermediate-proximal).normalized().cross((distal-intermediate).normalized()).dot(across) < -.05,"PIP flexes towards palm "+finger)
					check((distal-intermediate).normalized().cross((tip-distal).normalized()).dot(across) < -.03,"DIP flexes towards palm "+finger)
					check(last_bend > .05 and last_bend < .20,"slight distal bend "+finger)
				var palm := (fighter._bone_world("RightIndexProximal")-fighter._bone_world("RightLittleProximal")).cross(fighter._bone_world("RightMiddleProximal")-fighter._bone_world("RightHand")).normalized()
				check(palm.dot(fighter.ability_card.global_basis.y.normalized()) < -.94,"palm towards card, dorsal side towards viewer")
				fighter.ability_card.sample(.1) # Show contact without glow concealing it.
				var original_camera := view.camera.global_transform
				var card_pose := fighter.ability_card.global_transform.orthonormalized()
				for angle in [-1,0,1]:
					view.camera.global_position = card_pose.origin+card_pose.basis.y*.58+card_pose.basis.x*float(angle)*.32
					view.camera.look_at(card_pose.origin,-card_pose.basis.z)
					await frames(3)
					view.viewport.get_texture().get_image().save_png("res://build/checks/vrm-fighter/grip-%d-%d.png" % [model,angle])
				for direction in ["edge","back"]:
					var offset := card_pose.basis.x*.60+card_pose.basis.y*.025 if direction == "edge" else -card_pose.basis.y*.58+card_pose.basis.x*.12
					view.camera.global_position = card_pose.origin+offset
					view.camera.look_at(card_pose.origin,-card_pose.basis.z)
					await frames(3)
					view.viewport.get_texture().get_image().save_png("res://build/checks/vrm-fighter/grip-%d-%s.png" % [model,direction])
				view.camera.global_transform = original_camera
			# Weight shift must bend the knees without sliding or rotating planted feet.
			fighter.play_motion("command")
			fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]),0)
			fighter.sample_motion(.40)
			var preparation_hips := fighter.skeleton.get_bone_global_pose(fighter.skeleton.find_bone("Hips")).origin
			for time in [.25,.40,.75,.95,1.25,1.65,1.85]:
				fighter.sample_motion(time)
				for side in ["Left","Right"]:
					var foot := fighter.skeleton.get_bone_global_pose(fighter.skeleton.find_bone(side+"Foot"))
					var anchor: Transform3D = fighter._stance_feet[side]
					if fighter.native_motions:
						check(foot.origin.y > -.12 and foot.origin.y < .5,"native clip foot stays near ground")
					else:
						check(foot.origin.distance_to(anchor.origin) < .003,"planted ankle during weight shift")
						check(foot.basis.get_rotation_quaternion().angle_to(anchor.basis.get_rotation_quaternion()) < .005,"planted sole orientation")
			fighter.sample_motion(.95)
			check(preparation_hips.distance_to(fighter.skeleton.get_bone_global_pose(fighter.skeleton.find_bone("Hips")).origin) > (.01 if fighter.native_motions else .05),"pelvis participates in action")
			if clothes == 0:
				var original_camera := view.camera.global_transform
				var floor_mesh := MeshInstance3D.new()
				var plane := PlaneMesh.new()
				plane.size = Vector2(8,8)
				floor_mesh.mesh = plane
				floor_mesh.position.y = -.012
				floor_mesh.material_override = VisualUtil.make_material(Color(.22,.25,.29))
				parent.add_child(floor_mesh)
				view.camera.global_position = fighter.to_global(Vector3(4.8,1.25,1.4))
				view.camera.look_at(fighter.to_global(Vector3(0,1.0,0)))
				for frame in 24:
					fighter.sample_motion(float(frame)/23*VrmFighter.DURATIONS.command)
					await frames(2)
					view.viewport.get_texture().get_image().save_png("res://build/checks/vrm-fighter/weight-side-%d-%02d.png" % [model,frame])
				floor_mesh.queue_free()
				await frames(2)
				view.camera.global_transform = original_camera
			# Full-body regression: the old procedural gesture never moved these.
			fighter.play_motion("throw")
			fighter.sample_motion(.20)
			var hips := fighter.skeleton.find_bone("Hips")
			var hip_before := fighter.skeleton.get_bone_pose_position(hips)
			var moving: Array[int] = []
			var rotations: Array[Quaternion] = []
			for bone_name in ["LeftUpperLeg","RightUpperLeg","LeftLowerLeg","RightLowerLeg"]:
				var bone := fighter.skeleton.find_bone(bone_name)
				moving.append(bone)
				rotations.append(fighter.skeleton.get_bone_pose_rotation(bone))
			fighter.sample_motion(.65)
			check(hip_before.distance_to(fighter.skeleton.get_bone_pose_position(hips)) > .03,"throw moves pelvis")
			var changed := 0
			for index in moving.size():
				if rotations[index].angle_to(fighter.skeleton.get_bone_pose_rotation(moving[index])) > .1: changed += 1
			check(changed >= 3,"throw bends both legs, not just the arm")
			# Hide face/hair: the pixel change must come from the skinned costume.
			fighter.hair_part.hide()
			for mesh in fighter.meshes:
				if "Face" in str(mesh.name): mesh.hide()
			fighter.reset_motion()
			await frames(3)
			var before := view.viewport.get_texture().get_image().get_data()
			fighter.play_motion("throw")
			fighter.sample_motion(.4)
			await frames(3)
			check(before != view.viewport.get_texture().get_image().get_data(),"body actually deforms on GPU %d/%d" % [model,clothes])
			fighter.play_motion("defeat")
			fighter.sample_motion(.8)
			check(fighter.skeleton.get_bone_pose_rotation(fighter.skeleton.find_bone("Head")) != fighter._bind_poses[fighter.skeleton.find_bone("Head")].basis.get_rotation_quaternion(),"defeat bends head")
			if clothes == 0:
				for use_bank in ([true,false] if installed_bank else [false]):
					fighter.native_motions = use_bank
					for reaction in ["victory","defeat"]:
						fighter.reset_motion()
						fighter.sample_motion(.9)
						var baseline: Dictionary = {}
						for bone_name in ["Spine","Chest","LeftShoulder","RightShoulder","LeftUpperArm","RightUpperArm","LeftLowerArm","RightLowerArm","Head"]:
							baseline[bone_name] = fighter.skeleton.get_bone_pose_rotation(fighter.skeleton.find_bone(bone_name))
						var feet: Dictionary = {}
						for side in ["Left","Right"]:
							feet[side] = fighter.skeleton.get_bone_global_pose(fighter.skeleton.find_bone(side+"Foot"))
						fighter.play_motion(reaction)
						fighter.sample_motion(.9)
						var reaction_bones_changed := 0
						for bone_name in baseline:
							if (baseline[bone_name] as Quaternion).angle_to(fighter.skeleton.get_bone_pose_rotation(fighter.skeleton.find_bone(bone_name))) > .04: reaction_bones_changed += 1
						check(reaction_bones_changed >= 5,"%s uses torso, shoulders, forearms and head on base %d bank=%s" % [reaction,model,use_bank])
						for side in feet:
							var foot := fighter.skeleton.get_bone_global_pose(fighter.skeleton.find_bone(side+"Foot"))
							check(foot.is_equal_approx(feet[side]),"%s keeps %s foot planted on base %d bank=%s" % [reaction,side,model,use_bank])
						var duration: float = VrmFighter.DURATIONS[reaction]
						fighter.sample_motion(duration)
						var end_poses: Array[Transform3D] = []
						for bone in fighter._bind_poses.size(): end_poses.append(fighter.skeleton.get_bone_pose(bone))
						fighter.reset_motion()
						fighter.sample_motion(duration)
						for bone in end_poses.size():
							check(end_poses[bone].is_equal_approx(fighter.skeleton.get_bone_pose(bone)),"%s leaves no residual bone pose on base %d bank=%s bone=%d" % [reaction,model,use_bank,bone])
						fighter.play_motion(reaction)
						fighter.idle_time = 3.91
						fighter.motion_time = duration-.004
						fighter.sample_motion(fighter.motion_time,fighter.idle_time)
						var before_hand := fighter._bone_world("RightHand")
						var before_head := fighter._bone_world("Head")
						fighter._process(.006)
						check(fighter.motion == "idle" and absf(fighter.idle_time-3.916) < .0001,"%s returns to continuing idle phase" % reaction)
						check(before_hand.distance_to(fighter._bone_world("RightHand")) < .02 and before_head.distance_to(fighter._bone_world("Head")) < .02,"%s returns without pose jump on base %d bank=%s" % [reaction,model,use_bank])
				fighter.native_motions = installed_bank
			fighter.reset_motion()
			for bone in fighter._bind_poses.size():
				check(fighter.skeleton.get_bone_pose(bone).is_equal_approx(fighter._bind_poses[bone]),"reset restores bind pose")
			fighter.hair_part.show()
			for mesh in fighter.meshes:
				if "Face" in str(mesh.name): mesh.show()
			if clothes == 0:
				for reaction_index in 2:
					var reaction := "victory" if reaction_index == 0 else "defeat"
					fighter.play_motion(reaction)
					fighter.sample_motion(.9)
					for phase in 2:
						if phase == 1: fighter._process(VrmFighter.DURATIONS[reaction])
						await frames(3)
						var shot := view.viewport.get_texture().get_image()
						var width := shot.get_height()*5/6
						shot = shot.get_region(Rect2i((shot.get_width()-width)/2,0,width,shot.get_height()))
						shot.resize(500,600,Image.INTERPOLATE_LANCZOS)
						shot.convert(Image.FORMAT_RGBA8)
						reaction_atlas.blit_rect(shot,Rect2i(Vector2i.ZERO,shot.get_size()),Vector2i((reaction_index*2+phase)*500,model*600))
			row += 1
	atlas.save_png("res://build/checks/vrm-fighter/motions.png")
	reaction_atlas.save_png("res://build/checks/vrm-fighter/reactions.png")
	var loader := GameLoading.i()
	loader._storage = Node3D.new()
	parent.add_child(loader._storage)
	await loader.prepare_fighters(loader._storage)
	for model in 2:
		var profile := PlayerProfile.DEFAULT.duplicate(true)
		profile.vrm_model = model
		profile.vrm_style = 3
		var first := loader.take_fighter(profile)
		var second := loader.take_fighter(profile)
		check(first != null and second != null and first != second,"two resident actors per base")
		first.reparent(parent,false)
		first.play_motion("throw")
		loader.return_fighter(first)
		check(not first.visible and first.process_mode == Node.PROCESS_MODE_DISABLED and first.motion == "idle","returned fighter parked and reset")
		loader.return_fighter(second)
		profile.vrm_style = 1
		var reused := loader.take_fighter(profile)
		check(reused == second and reused._hair_source == 2,"lease reuses actor and applies latest profile")
		var portrait := FighterPortrait.new()
		root.add_child(portrait)
		portrait.bind(reused,model)
		await frames(4)
		var image := portrait.get_texture().get_image()
		check(image.get_used_rect().size.x > 30,"portrait draws the resident actor")
		image.save_png("res://build/checks/vrm-fighter/portrait-%d.png" % model)
		portrait.queue_free()
		await frames(2)
		loader.return_fighter(reused)
	check(loader.fighter_build_count == 4,"no rebuild during leases")
	var hud := HudUI.new()
	root.add_child(hud)
	hud.setup_plates([Color.RED,Color.BLUE,Color.GREEN],[Color.RED,Color.BLUE,Color.GREEN])
	hud.set_names("Тестовый герой с длинным именем","Соперник · Боец")
	hud.set_status(1,0,3,3)
	var portrait_image := Image.load_from_file("res://build/checks/vrm-fighter/portrait-0.png")
	for side in 2: hud.set_portrait(side,ImageTexture.create_from_image(portrait_image))
	for size in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = size
		root.content_scale_size = size
		RenderingServer.viewport_set_size(root.get_viewport_rid(),size.x,size.y)
		await frames(4)
		var left: Rect2 = hud._plates[0].get_global_rect()
		var right: Rect2 = hud._plates[1].get_global_rect()
		var turn: Rect2 = hud._turn_clip.get_global_rect()
		check(left.end.x < turn.position.x and turn.end.x < right.position.x,"portraits leave turn readable at %d" % size.x)
		check(left.position.x >= 0 and right.end.x <= size.x,"plates inside screen")
	hud.queue_free()
	view.queue_free()
	loader.queue_free()
	await frames(6)
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(3)
	print("VRM fighter: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
