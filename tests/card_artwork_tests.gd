extends SceneTree
## Isolated rendered contact sheets for the six elements and every gate.
## tools/check.py supplies the non-focusing, minimized 60 FPS wrapper.
var failures := 0
var checks := 0
var out_dir := "user://cards-art"

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("_run")

func _capture(name: String) -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))

func _clear(host: Control) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()

func _run() -> void:
	CardDB.load_all()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.theme = UiTheme.get_theme()
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color(0.025, 0.035, 0.06))
	var host := Control.new()
	root.add_child(host)
	var all_keys := {}
	for id in CardDB.ability_ids() + CardDB.arena_ids():
		var def := CardDB.card(id)
		var key := CardArtwork.key_for(def)
		var cv := CardView.new().for_card(def)
		host.add_child(cv)
		await process_frame
		check(not key.is_empty() and CardArtwork.TEXTURES.has(key), "illustration assigned: %s" % id)
		check(cv._artwork.visible and cv._artwork.texture != null, "illustration displayed: %s" % id)
		check(int(cv._mat.get_shader_parameter("sigil")) == -1, "abstract glyph replaced: %s" % id)
		var art_bounds := Rect2(cv._artwork.position, cv._artwork.size)
		check(art_bounds.position.y > cv._kind.position.y + cv._kind.size.y - 2, "art below compatibility: %s" % id)
		check(art_bounds.end.y < cv._role.position.y, "art above role: %s" % id)
		if cv._power.visible:
			var badge: Vector4 = cv._lay["plaque"]
			var badge_bounds := Rect2(Vector2(badge.x - badge.z, badge.y - badge.w) * 150.0, Vector2(badge.z, badge.w) * 300.0)
			check(not art_bounds.intersects(badge_bounds), "art does not overlap power badge: %s" % id)
		cv.set_dimmed(true, true)
		check(cv._artwork.self_modulate.r < 1.0, "unavailable artwork dims: %s" % id)
		cv.set_dimmed(false)
		check(cv._artwork.self_modulate == Color.WHITE, "available artwork restored: %s" % id)
		all_keys[key] = true
		_clear(host)
	for frame in 2: await process_frame
	var element_ids := [&"ability_fire_counter", &"ability_gale_rebuttal", &"ability_light_counter", &"ability_stone_counter", &"ability_shadow_counter", &"ability_tide_counter"]
	for i in element_ids.size():
		var def := CardDB.card(element_ids[i])
		var cv := CardView.new().for_card(def, Vector2(240, 336))
		cv.position = Vector2(30 + i * 258, 54)
		host.add_child(cv)
		var enlarged := TextureRect.new()
		enlarged.texture = CardArtwork.texture_for(def)
		enlarged.position = Vector2(53 + i * 258, 430)
		enlarged.size = Vector2(194, 194)
		enlarged.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		enlarged.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(enlarged)
	var caption := VisualUtil.label("ШЕСТЬ СТИХИЙ · КАРТА И ИЛЛЮСТРАЦИЯ", 24)
	caption.position = Vector2(30, 10)
	host.add_child(caption)
	await _capture("six-elements")
	_clear(host)
	var gates := CardDB.arena_ids()
	for offset in range(0, gates.size(), 10):
		for i in mini(10, gates.size() - offset):
			var cv := CardView.new().for_card(CardDB.card(gates[offset + i]), Vector2(250, 350))
			cv.position = Vector2(90 + (i % 5) * 285, 46 + (i / 5) * 420)
			host.add_child(cv)
		await _capture("gates-%02d" % offset)
		_clear(host)
	# One complete sheet keeps the final visual review of all gate silhouettes together.
	for i in gates.size():
		var cv := CardView.new().for_card(CardDB.card(gates[i]), Vector2(170, 238))
		cv.position = Vector2(40 + (i % 8) * 190, 12 + (i / 8) * 245)
		host.add_child(cv)
	await _capture("gates-overview")
	_clear(host)
	for i in element_ids.size():
		var cv := CardView.new().for_card(CardDB.card(element_ids[i]), Vector2(96, 134))
		cv.position = Vector2(70 + i * 130, 64)
		host.add_child(cv)
		var gate := CardView.new().for_card(CardDB.card(gates[i]), Vector2(96, 134))
		gate.position = Vector2(70 + i * 130, 260)
		host.add_child(gate)
	await _capture("compact-elements-and-gates")
	_clear(host)
	await _review_3d(host)
	host.queue_free()
	for frame in 3: await process_frame
	print("Card artwork: %d checks, %d failures; %d distinct illustrations" % [checks, failures, all_keys.size()])
	quit(1 if failures else 0)


func _review_3d(host: Control) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.025, 0.035, 0.06)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 1.0
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-70, -20, 0)
	light.light_energy = 1.2
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.2
	camera.position = Vector3(0, 3.4, 0.02)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.current = true
	var gate := ArenaCardNode.new()
	gate.scale = Vector3.ONE / ArenaCardNode.SIZE.x
	gate.position.x = -0.7
	world.add_child(gate)
	gate.set_field_surface(true)
	for id in CardDB.arena_ids():
		var def := CardDB.card(id)
		gate.show_face(def)
		check(bool(gate._mat.get_shader_parameter("illustration_on")), "3D gate illustration enabled: %s" % id)
		check(gate._mat.get_shader_parameter("illustration_tex") == CardArtwork.texture_for(def), "3D gate uses identical art: %s" % id)
		check(int(gate._mat.get_shader_parameter("sigil")) == -1, "3D abstract glyph replaced: %s" % id)
	gate.show_facedown(0, null)
	check(not bool(gate._mat.get_shader_parameter("illustration_on")), "face-down gate hides art")
	check(gate._mat.get_shader_parameter("illustration_tex") == null, "face-down gate releases artwork reference")
	gate.show_face(CardDB.card(&"arena_field_fire"))
	check(gate.is_in_group("gate_surfaces") and gate._field_body.collision_layer == 1, "real field gate retains its surface")
	var prop := AbilityCardProp.new()
	prop.scale = Vector3.ONE / 0.12
	prop.position.x = 0.7
	world.add_child(prop)
	for id in [&"ability_fire_counter", &"ability_gale_rebuttal", &"ability_light_counter", &"ability_stone_counter", &"ability_shadow_counter", &"ability_tide_counter"]:
		var def := CardDB.card(id)
		prop.configure(def, CardEffects.lock_attr(def))
		check(bool(prop.card._mat.get_shader_parameter("illustration_on")), "hero prop illustration enabled: %s" % id)
		check(prop.card._mat.get_shader_parameter("illustration_tex") == CardArtwork.texture_for(def), "hero prop uses identical art: %s" % id)
		check(not bool(prop.back._mat.get_shader_parameter("illustration_on")), "hero prop back remains concealed")
	var caption := VisualUtil.label("КАРТА НА ПОЛЕ                                    КАРТА СПОСОБНОСТИ В РУКЕ ГЕРОЯ", 24)
	caption.position = Vector2(155, 50)
	host.add_child(caption)
	await _capture("arena-and-hero-prop")
	_clear(host)
	world.queue_free()
	for frame in 4: await process_frame
