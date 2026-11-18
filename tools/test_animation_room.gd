extends SceneTree
## Narrow Boot → menu → animation room → menu → duel test. Graphics use the offscreen wrapper.
const WINDOW := preload("res://tools/test_window.gd")
const BOOT := preload("res://scenes/loading/boot.tscn")
const ROOM := preload("res://scenes/ui/animation_room.gd")
const PIXAL_SOURCE_VERTICES := 2572890
const PIXAL_SOURCE_TRIANGLES := 5370274
# The runtime order differs from glTF. These buffers were checked against every
# referenced source position and oriented face in geometry-godot-audit.json.
const PIXAL_SOURCE_POSITION_SHA := "70df0715cc0722812e89659f791ac5eea9bb67da79e25e73c05b3bde23fd8657"
const PIXAL_SOURCE_INDEX_SHA := "4509d9c0fc68073d738ea6f3fde8f6444a030878b165b3b347889c1e716b2cc9"
var _failures := 0
var _checks := 0
var _out := "res://build/checks/presentation/animation-room"


func _initialize() -> void:
	if not has_meta("sfery_background_draw"): WINDOW.background(self)
	_run.call_deferred()


func _finalize() -> void:
	WINDOW.finish(self)


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1280, 720)
	GraphicsSettings.force_level(GraphicsSettings.Level.MEDIUM)
	AudioServer.set_bus_mute(0, true)
	var boot := BOOT.instantiate()
	root.add_child(boot)
	current_scene = boot
	var catalog := GameLoading.i()
	var deadline := Time.get_ticks_msec() + 240000
	while not current_scene is MainMenu and catalog.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(current_scene is MainMenu, "Boot opens the actual main menu: " + catalog.last_error)
	if not current_scene is MainMenu:
		await _finish()
		return
	var menu := current_scene as MainMenu
	var saved_arena := ArenaLocations.current()
	var original_arena: Arena = catalog._game.arena
	var built_arenas := catalog.arena_build_count
	var built_actors := catalog.actor_build_count
	var built_fighters := catalog.fighter_build_count
	menu._focus_button("Комната анимаций")
	await _key(KEY_ENTER)
	var room = menu._animation_room
	_check(is_instance_valid(room), "the room is open from the real menu by keyboard")
	if not is_instance_valid(room):
		await _finish()
		return
	_check(room._arena == original_arena and room._arena.location_id == saved_arena, "the selected Boot arena is used by the room")
	_check(root.gui_get_focus_owner() == room._map, "opening the room focuses arena selection")
	var layout_bounds := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var stage := room._viewport.get_parent() as SubViewportContainer
	_check(layout_bounds.encloses(stage.get_global_rect()) and stage.size.x > stage.size.y, "the preview fits the normal menu layout")
	if "--comparison-only" in OS.get_cmdline_user_args():
		await _check_ratnik_comparison(room, menu, catalog)
		_check(built_actors == catalog.actor_build_count and built_arenas == catalog.arena_build_count and built_fighters == catalog.fighter_build_count, "comparison does not rebuild the gameplay catalog")
		_check(Engine.max_fps == 60, "test remains capped at 60 FPS")
		await _finish()
		return
	await _key(KEY_ENTER)
	_check(room._map.get_popup().visible, "the arena selector opens with Enter")
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_check(room._arena.location_id == (saved_arena + 1) % ArenaLocations.LOCATIONS.size(), "the arena changes through popup keyboard input")
	_check(room._species.item_count == GameData.ALL_SPECIES.size() + 1 and room._element.item_count == Attr.COUNT, "published catalog and rare creature are selectable")
	_check(room._ball.is_figure_shown(), "the initial model is revealed")
	var dragnar: CreatureBall = room._ball
	var seen: Array[int] = []
	for index in ArenaLocations.LOCATIONS.size():
		_choose(room._map, index)
		await _frames(4)
		_check(room._arena.location_id == index and room._ball == dragnar, "arena selection preserves the current actor")
		seen.append(room._arena.location_id)
		await _capture("arena-%d" % index)
	_check(ArenaLocations.current() == saved_arena and seen == [0, 1, 2], "all three arena choices leave the match setting intact")
	var ratnik := _entry(room._species, &"ratnik")
	_choose(room._species, ratnik)
	_choose(room._element, _entry(room._element, &"creature_ratnik_light"))
	_check(room._ball.def.id == &"creature_ratnik_light" and not dragnar.visible and dragnar.get_parent() == catalog._storage, "filtering species and element returns the previous lease")
	_choose(room._motion, _entry(room._motion, &"sphere"))
	await _frames(4)
	_check(not room._ball.is_figure_shown() and room._ball._shell.is_visible_in_tree(), "sphere mode shows the shell at inspection distance")
	await _capture("sphere")
	_choose(room._motion, _entry(room._motion, &"reveal"))
	await _frames(8)
	_check(room._ball._open_tween.is_running() and room._ball._open_pillar != null, "reveal uses the in-game shell and effects")
	room._pause.pressed.emit()
	var reveal_elapsed: float = room._ball._open_tween.get_total_elapsed_time()
	await _frames(8)
	_check(is_equal_approx(reveal_elapsed, room._ball._open_tween.get_total_elapsed_time()), "pausing freezes reveal progression")
	room._pause.pressed.emit()
	_choose(room._motion, _entry(room._motion, &"attack"))
	await _frames(9)
	var attack_elapsed: float = room._ball._anim._elapsed
	_check(room._ball.is_figure_shown() and room._ball._anim._action == &"attack" and attack_elapsed > 0.0, "attack uses the creature's game animation")
	_check(room._ball._open_pillar == null, "switching out of reveal clears its pillar")
	room._replay.pressed.emit()
	_check(room._ball._anim._elapsed < attack_elapsed, "replay starts the attack again")
	await _capture("creature")
	_choose(room._motion, _entry(room._motion, &"idle"))
	await _frames(3)
	await _capture_attachment(room, "ratnik-grip", "sword", Vector3(-.5, .14, 1), .24)
	await _check_armat_repeat(room, catalog)
	_choose(room._species, _entry(room._species, &"likorez"))
	_check(room._element.item_count == 1 and room._ball.def.id == CardDB.RARE_SHADOW_ID, "rare creature offers its one resident element")
	_choose(room._category, 1)
	_choose(room._people, 2)
	_choose(room._motion, _entry(room._motion, &"throw"))
	await _frames(12)
	_check(room._fighter.selected == 1 and room._fighter.motion == "throw" and room._fighter.motion_time > 0.0, "fighter switches base model and plays throw")
	room._pause.pressed.emit()
	var elapsed: float = room._fighter.motion_time
	await _frames(8)
	_check(is_equal_approx(elapsed, room._fighter.motion_time), "pausing freezes the fighter independently of the arena")
	await _capture("fighter")
	var camera_before: Vector3 = room._camera.position
	var drag := InputEventMouseMotion.new()
	drag.position = stage.get_global_rect().get_center()
	drag.relative = Vector2(48, 18)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag, true)
	await _frames(2)
	_check(not room._camera.position.is_equal_approx(camera_before), "the preview accepts mouse drag while paused")
	camera_before = room._camera.position
	room._zoom_camera(1.2)
	_check(not room._camera.position.is_equal_approx(camera_before), "camera orbit and zoom work while paused")
	var fighter: VrmFighter = room._fighter
	await _key(KEY_ESCAPE)
	_check(menu._animation_room == null and menu.city.visible and root.gui_get_focus_owner().text == "Комната анимаций", "Escape closes the room and restores menu focus and city")
	_check(catalog._arenas.size() == ArenaLocations.LOCATIONS.size() and catalog._leased.is_empty() and fighter.get_parent() == catalog._storage, "closing restores arena, creature, and fighter leases")
	await _key(KEY_ENTER)
	room = menu._animation_room
	_check(is_instance_valid(room) and room._arena == original_arena and room._ball != null, "room can be reopened after returning all leases")
	room.close()
	menu._focus_button("Играть")
	await _key(KEY_ENTER)
	menu._focus_button("Дуэль")
	await _key(KEY_ENTER)
	await _frames(42)
	var game := current_scene
	_check(game.scene_file_path == "res://scenes/main.tscn" and game.arena == original_arena and game.team_menu.visible, "duel opens its team screen and uses the saved arena after the room")
	_check(built_actors == catalog.actor_build_count and built_arenas == catalog.arena_build_count and built_fighters == catalog.fighter_build_count, "no creature, arena, or fighter catalog rebuild")
	_check(Engine.max_fps == 60, "test remains capped at 60 FPS")
	await _finish()


func _check_ratnik_comparison(room, menu: MainMenu, catalog: GameLoading) -> void:
	_check(room._category.item_count == 3, "both local variants expose the Ratnik Light comparison")
	if room._category.item_count != 3: return
	var original: CreatureBall = room._ball
	var arena: Arena = room._arena
	var stock: CreatureBall = catalog._balls[ROOM.CURRENT_RATNIK].back()
	var stock_cloth: Node = stock._anim._cloth
	var cloth_texture: RID = stock_cloth._positions_img_rid if is_instance_valid(stock_cloth) else RID()
	var paths: Array = ROOM.RATNIK_COMPARISON.values()
	_check(not ResourceLoader.has_cached(paths[0]) and not ResourceLoader.has_cached(paths[1]) and not ResourceLoader.has_cached(ROOM.RATNIK_SOURCE), "Boot and opening the room leave local comparison assets unloaded")
	room._category.grab_focus()
	await _key(KEY_ENTER)
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	var comparison: Node3D = room._comparison
	_check(is_instance_valid(comparison), "Ratnik comparison opens with normal keyboard input")
	if not is_instance_valid(comparison): return
	_check(room._ball == null and original.get_parent() == catalog._storage, "comparison returns the previous catalog actor")
	_check(room._variant.is_visible_in_tree() and room._variant.item_count == 4 and room._motion.item_count == 6, "comparison offers the original Pixal, both fitted experiments and the current match model")
	var current: CreatureBall = room._comparison_current
	_check(current == stock and current.def.id == ROOM.CURRENT_RATNIK and current.def.attribute == Attr.A.LIGHT and catalog._leased.has(current.get_instance_id()), "the current version is the exact prebuilt Ratnik Light match actor")
	var current_model := current._anim._model
	var stock_source: PackedScene = current_model.get_meta("preparation_source")
	_check(stock_source.resource_path == CreatureModels.RATNIK_MODEL and _uses_ratnik_light_atlas(current_model), "the current version uses the production TRELLIS.2 GLB and Light palette")
	_check(DisplayServer.get_name() == "headless" or (cloth_texture.is_valid() and current._anim._cloth == stock_cloth and stock_cloth._positions_img_rid == cloth_texture), "the production actor retains its GPU cloth through reparent")
	var pixal: Node3D = room._comparison_variants[paths[0]]
	var uniforge: Node3D = room._comparison_variants[paths[1]]
	var source: Node3D = room._comparison_variants.get(ROOM.RATNIK_SOURCE)
	_check(is_instance_valid(source) and source.scene_file_path == ROOM.RATNIK_SOURCE, "the source is instantiated directly from its own imported GLB")
	if not is_instance_valid(source): return
	_check(room._variant.get_selected_metadata() == ROOM.RATNIK_SOURCE and source.visible and not pixal.visible and not uniforge.visible and not current.visible, "the original source is the first, visible comparison variant")
	_check(room._source_hint.is_visible_in_tree() and room._motion.disabled and room._replay.disabled and room._pause.disabled and room._repeat.disabled, "the original variant identifies itself as static and disables animation")
	_check_source_geometry(source)
	await _capture("source-quarter")
	var mesh_instance := source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var cull_probe := mesh_instance.get_active_material(0).duplicate() as StandardMaterial3D
	cull_probe.cull_mode = BaseMaterial3D.CULL_FRONT
	mesh_instance.material_override = cull_probe
	await _frames(3)
	await _capture("source-frontface-cull-quarter")
	mesh_instance.material_override = null
	room._source_neutral.button_pressed = true
	await _frames(3)
	await _capture("source-neutral-quarter")
	room._source_neutral.button_pressed = false
	_check(pixal.scene_file_path == paths[0] and uniforge.scene_file_path == paths[1], "two different imported meshes are selected")
	var pixal_hash := FileAccess.get_sha256(paths[0])
	var uniforge_hash := FileAccess.get_sha256(paths[1])
	_check(not pixal_hash.is_empty() and not uniforge_hash.is_empty() and pixal_hash != uniforge_hash, "comparison assets come from two distinct GLBs")
	print("Ratnik Light comparison GLBs: source %s, fitted Pixal3D %s, UniForge3D %s, current %s" % [
		FileAccess.get_sha256(ROOM.RATNIK_SOURCE), pixal_hash, uniforge_hash, FileAccess.get_sha256(stock_source.resource_path),
	])
	_check(_uses_vertex_colors(pixal) and _uses_vertex_colors(uniforge), "the imported armor and cloth use their exported colors")
	room._variant.grab_focus()
	await _key(KEY_ENTER)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_check(pixal.visible and not source.visible and not uniforge.visible and not current.visible and not room._motion.disabled, "keyboard chooses the fitted Pixal independently and restores animation controls")
	var pixal_player := pixal.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var uniforge_player := uniforge.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var current_player := current._anim._player
	_check(not pixal_player.is_playing() and not uniforge_player.is_playing() and not current_player.is_playing() and room._repeat.disabled, "inspection opens frozen")
	_check(_same_rig_pose(pixal, uniforge, true) and _same_rig_pose(pixal, current_model, true), "all three rigs share the neutral rest pose")
	var camera: Transform3D = room._camera.transform
	var light: float = room._key_light.light_energy
	var ambient: Color = room._environment.ambient_light_color
	await _capture("pixal-quarter")
	room._variant.grab_focus()
	await _key(KEY_ENTER)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_check(uniforge.visible and not pixal.visible, "keyboard switch selects only UniForge")
	_check(room._camera.transform.is_equal_approx(camera) and room._arena == arena, "switch preserves the exact camera and arena")
	_check(is_equal_approx(light, room._key_light.light_energy) and ambient == room._environment.ambient_light_color, "both figures use the same stage lights")
	await _capture("uniforge-quarter")
	await _key(KEY_ENTER)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_check(current.visible and not pixal.visible and not uniforge.visible, "keyboard switch selects only the current game version")
	_check(room._camera.transform.is_equal_approx(camera) and is_equal_approx(light, room._key_light.light_energy) and ambient == room._environment.ambient_light_color, "the current game version shares the exact camera and stage lights")
	await _capture("current-quarter")
	room._turn_camera(-ROOM.INITIAL_ORBIT.x)
	await _capture_source_comparison(room, "front")
	room._turn_camera(PI / 2.0)
	await _capture_source_comparison(room, "profile")
	room._turn_camera(PI / 2.0)
	await _capture_source_comparison(room, "back")
	room._reset_camera()
	_choose(room._motion, _entry(room._motion, &"attack"))
	await _frames(14)
	room._pause.pressed.emit()
	var elapsed := pixal_player.current_animation_position
	_check(pixal_player.current_animation == &"attack" and uniforge_player.current_animation == &"attack" and current_player.current_animation == &"attack" and elapsed > 0.0 and is_equal_approx(elapsed, uniforge_player.current_animation_position) and is_equal_approx(elapsed, current_player.current_animation_position), "the same authored attack drives all three models in sync")
	elapsed = pixal_player.current_animation_length * .55
	pixal_player.seek(elapsed, true)
	uniforge_player.seek(elapsed, true)
	current_player.seek(elapsed, true)
	_choose(room._variant, _entry(room._variant, String(ROOM.CURRENT_RATNIK)))
	await _frames(3)
	await _capture("current-attack")
	_check(is_equal_approx(pixal_player.current_animation_position, elapsed) and is_equal_approx(uniforge_player.current_animation_position, elapsed) and is_equal_approx(current_player.current_animation_position, elapsed), "paused attack phase persists across the version switch")
	_check(_same_rig_pose(pixal, uniforge) and _same_rig_pose(pixal, current_model), "all three rigs show the same paused attack pose")
	_choose(room._variant, _entry(room._variant, ROOM.RATNIK_SOURCE))
	await _frames(3)
	_check(room._comparison_variants[ROOM.RATNIK_SOURCE] == source and source.visible and room._pause.disabled and is_equal_approx(current_player.current_animation_position, elapsed), "switching back to the source reuses the same static mesh and preserves the paused clip")
	_choose(room._variant, _entry(room._variant, String(ROOM.CURRENT_RATNIK)))
	room._replay.pressed.emit()
	_check(is_zero_approx(pixal_player.current_animation_position) and is_zero_approx(uniforge_player.current_animation_position) and is_zero_approx(current_player.current_animation_position), "replay restarts all three versions together")
	_choose(room._motion, _entry(room._motion, &"inspect"))
	_check(not pixal_player.is_playing() and not uniforge_player.is_playing() and not current_player.is_playing() and _same_rig_pose(pixal, uniforge, true) and _same_rig_pose(pixal, current_model, true), "returning to inspection resets all rigs")
	_choose(room._map, (arena.location_id + 1) % ArenaLocations.LOCATIONS.size())
	_check(room._arena != arena and room._comparison == comparison, "arena change preserves the comparison actors")
	_choose(room._category, ROOM.Category.CREATURE)
	await _frames(3)
	_check(not is_instance_valid(comparison) and not is_instance_valid(source) and is_instance_valid(room._ball) and room._ball.is_figure_shown(), "leaving comparison removes the source and local actors and restores creature preview")
	_check(current.get_parent() == catalog._storage and current._anim.is_processing() and not catalog._leased.has(current.get_instance_id()), "leaving comparison returns the exact match actor with autonomous animation restored")
	await _key(KEY_ESCAPE)
	_check(menu._animation_room == null and catalog._arenas.size() == ArenaLocations.LOCATIONS.size() and catalog._leased.is_empty(), "closing the room restores the gameplay catalog and arena leases")


func _capture_source_comparison(room, view: String) -> void:
	var entries := {
		"source": ROOM.RATNIK_SOURCE,
		"source-neutral": ROOM.RATNIK_SOURCE,
		"current": String(ROOM.CURRENT_RATNIK),
	}
	for prefix: String in entries:
		_choose(room._variant, _entry(room._variant, entries[prefix]))
		room._source_neutral.button_pressed = prefix == "source-neutral"
		await _frames(3)
		await _capture(prefix + "-" + view)


func _check_source_geometry(source: Node3D) -> void:
	var meshes := source.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() == 1 and source.find_children("*", "Skeleton3D", true, false).is_empty(), "the source loads one unrigged visible surface")
	if meshes.size() != 1: return
	var instance := meshes[0] as MeshInstance3D
	var mesh := instance.mesh as ArrayMesh
	_check(instance.is_visible_in_tree() and mesh != null and mesh.get_surface_count() == 1, "the exact source mesh is visible in the viewport")
	if mesh == null or mesh.get_surface_count() != 1: return
	_check(mesh.surface_get_array_len(0) == PIXAL_SOURCE_VERTICES and mesh.surface_get_array_index_len(0) == PIXAL_SOURCE_TRIANGLES * 3, "Godot keeps every source triangle and every referenced position")
	var arrays := mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var position_sha := _sha256(positions.to_byte_array())
	var index_sha := _sha256(indices.to_byte_array())
	print("Pixal source Godot geometry: %d vertices, %d triangles; position %s; index %s" % [positions.size(), indices.size() / 3, position_sha, index_sha])
	_check(position_sha == PIXAL_SOURCE_POSITION_SHA and index_sha == PIXAL_SOURCE_INDEX_SHA, "the visible Godot buffers match every source position and oriented triangle after import")
	var material := instance.get_active_material(0) as StandardMaterial3D
	_check(material != null and material.vertex_color_use_as_albedo and (mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0, "the original surface draws the painted vertex material")


func _sha256(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


func _uses_ratnik_light_atlas(model: Node3D) -> bool:
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface) as ShaderMaterial
			if material == null: continue
			var atlas := material.get_shader_parameter("color_map") as Texture2D
			if atlas != null and atlas.resource_path == "res://assets/creatures_hd/ratnik_trellis/light.png":
				return true
	return false


func _uses_vertex_colors(model: Node3D) -> bool:
	var colored_surfaces: Array[String] = []
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := instance.mesh as ArrayMesh
		if mesh == null: continue
		for surface in mesh.get_surface_count():
			if (mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR) == 0: continue
			var material := instance.get_active_material(surface) as StandardMaterial3D
			if material == null or not material.vertex_color_use_as_albedo: return false
			colored_surfaces.append(material.resource_name)
	return "Ratnik · Gold plates and dark joints" in colored_surfaces and "Cape · Brown fabric" in colored_surfaces


func _same_rig_pose(first: Node3D, second: Node3D, at_rest: bool = false) -> bool:
	var first_rigs := first.find_children("*", "Skeleton3D", true, false)
	var second_rigs := second.find_children("*", "Skeleton3D", true, false)
	if first_rigs.size() != 1 or second_rigs.size() != 1: return false
	var a := first_rigs[0] as Skeleton3D
	var b := second_rigs[0] as Skeleton3D
	if not a.global_transform.is_equal_approx(b.global_transform): return false
	if a.get_bone_count() != b.get_bone_count(): return false
	for index in a.get_bone_count():
		var match_index := b.find_bone(a.get_bone_name(index))
		if match_index < 0 or not a.get_bone_global_pose(index).is_equal_approx(b.get_bone_global_pose(match_index)):
			return false
		if at_rest and not a.get_bone_pose(index).is_equal_approx(a.get_bone_rest(index)): return false
	return true


func _check_armat_repeat(room, catalog: GameLoading) -> void:
	_choose(room._species, _entry(room._species, &"armat"))
	_choose(room._element, _entry(room._element, &"creature_armat_stone"))
	_choose(room._motion, _entry(room._motion, &"idle"))
	var ball: CreatureBall = room._ball
	var animator: CreatureAnim = ball._anim
	var player := animator._player
	var idle := player.get_animation(&"idle")
	_check(room._repeat.disabled and idle.loop_mode == Animation.LOOP_LINEAR, "Armat idle already loops naturally")
	await _capture_attachment(room, "armat-hind-hip", "hind_upper.L", Vector3(1, .12, -.45), 1.35)
	var step := 1.0 / 60.0
	for track in idle.get_track_count():
		if idle.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			var left := idle.rotation_track_interpolate(track, idle.length - step)
			var right := idle.rotation_track_interpolate(track, step)
			_check(left.angle_to(right) < .12, "Armat idle has no angular jump at the seam")
		elif idle.track_get_type(track) == Animation.TYPE_POSITION_3D:
			var left := idle.position_track_interpolate(track, idle.length - step)
			var right := idle.position_track_interpolate(track, step)
			_check(left.distance_to(right) < .025, "Armat idle has no translation jump at the seam")
	await _frames(2)
	player.seek(idle.length - 0.07, true)
	_check(await _until(func() -> bool: return player.current_animation_position < .25), "Armat idle crosses the loop boundary in the actual room")
	_choose(room._motion, _entry(room._motion, &"attack"))
	var completed: Array[StringName] = []
	var record := func(action: StringName) -> void: completed.append(action)
	animator.action_finished.connect(record)
	room._repeat.button_pressed = true
	_check(await _until(func() -> bool: return &"attack" in completed), "the room completes the first attack")
	_check(animator._action == &"" and player.current_animation == &"idle", "the room allows the recovery blend to start")
	_check(await _until(func() -> bool: return animator._action == &"attack"), "the room repeats the completed attack")
	_check(player.get_animation(&"attack").loop_mode == Animation.LOOP_NONE, "preview repeat does not change the shared attack clip")
	room._pause.pressed.emit()
	var paused_elapsed := animator._elapsed
	await _frames(8)
	_check(is_equal_approx(animator._elapsed, paused_elapsed), "auto repeat respects pause")
	room._pause.pressed.emit()
	_choose(room._motion, _entry(room._motion, &"hit"))
	_check(animator._action == &"hit" and room._repeat.button_pressed, "changing action keeps repeat on the selected clip")
	_check(await _until(func() -> bool: return &"hit" in completed and animator._action == &"hit"), "the hit replaces the attack in the preview loop")
	animator.action_finished.disconnect(record)
	_choose(room._element, _entry(room._element, &"creature_armat_fire"))
	_check(room._ball != ball and room._ball._anim._action == &"hit", "swapping Armat previews repeats only the new actor")
	_check(ball.get_parent() == catalog._storage and ball.process_mode == Node.PROCESS_MODE_DISABLED and animator._action == &"", "the returned Armat has no pending preview replay")
	room._repeat.button_pressed = false
	var next: CreatureAnim = room._ball._anim
	_check(await _until(func() -> bool: return next._action == &""), "disabling preview repeat lets the current action finish")
	await _frames(10)
	_check(next._action == &"" and next._player.current_animation == &"idle", "a completed one-shot returns to idle without restarting")
	_check(next._player.get_animation(&"hit").loop_mode == Animation.LOOP_NONE, "preview repeat does not change the shared hit clip")


func _until(condition: Callable) -> bool:
	for index in 300:
		if condition.call(): return true
		await process_frame
	return false


func _finish() -> void:
	if is_instance_valid(current_scene):
		if current_scene is MainMenu and is_instance_valid(current_scene._animation_room):
			current_scene._animation_room.close()
		current_scene.queue_free()
	await _frames(5)
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	await _frames(5)
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await _frames(5)
	print("animation-room: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _choose(option: OptionButton, index: int) -> void:
	option.select(index)
	option.item_selected.emit(index)


func _entry(option: OptionButton, id: Variant) -> int:
	for index in option.item_count:
		if option.get_item_metadata(index) == id: return index
	return -1


func _capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(_out.path_join(label + ".png")) == OK, "captured " + label)


func _capture_attachment(room, label: String, bone_name: String, view: Vector3, distance: float) -> void:
	if DisplayServer.get_name() == "headless": return
	var camera: Camera3D = room._camera
	var skeleton: Skeleton3D = room._ball._anim._strike_skeleton
	var bone := skeleton.find_bone(bone_name)
	_check(bone >= 0, "capture bone exists: " + bone_name)
	if bone < 0: return
	room._pause.pressed.emit()
	var target := skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
	camera.look_at_from_position(target + view.normalized() * room._ball.figure_height() * distance, target)
	await _frames(2)
	await _capture(label)
	room._frame_camera()
	room._pause.pressed.emit()


func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await _frames(3)


func _frames(count: int) -> void:
	for index in count: await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
