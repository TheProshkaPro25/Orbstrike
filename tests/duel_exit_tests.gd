extends SceneTree
## Реальный Boot и выход из подготовки, выбора карты, полёта и результата.
const WindowTest := preload("res://tools/test_window.gd")
const AutoPlay := preload("res://tools/autoplay.gd")
const MENU_PATH := "res://scenes/menu/main_menu.tscn"
const DUEL_PATH := "res://scenes/main.tscn"
const ONLINE_PATH := "res://scenes/online/online_game.tscn"
class ResultWaiter extends Node:
	var game: Node
	var finished := false
	func wait_result() -> void:
		var result := BattleResult.new()
		result.attacker_uid = 0
		result.defender_uid = 3
		result.winner_uid = 0
		result.loser_uid = 3
		result.powers = [410,390]
		await game.battle_overlay.show_result(result)
		finished = true
var checks := 0
var failures := 0
var loader: GameLoading
var main: Node
var counts: Array = []
var identities: Dictionary = {}
var out := "res://build/checks/duel-exit"
func _initialize() -> void:
	if not has_meta("sfery_background_draw"): WindowTest.background(self)
	call_deferred("run")
func _finalize() -> void: WindowTest.finish(self)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func until(predicate: Callable, seconds := 30.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if predicate.call(): return true
	return false
func frames(n: int) -> void:
	for f in n: await process_frame
func click(at: Vector2) -> void:
	for pressed in [true,false]:
		var e := InputEventMouseButton.new()
		e.position = at
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
func click_control(button: Button) -> void:
	var center := button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = center
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		await process_frame
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event,true)
		await process_frame
func find_button(node: Node, title: String) -> Button:
	for child in node.find_children("*","Button",true,false):
		if child.text == title and child.is_visible_in_tree(): return child as Button
	return null
func wait_scene(path: String) -> bool:
	return await until(func(): return is_instance_valid(current_scene) and current_scene.scene_file_path == path)
func open_mode(title: String, path: String) -> bool:
	var play := find_button(current_scene,"Играть")
	if play == null: return false
	await click_control(play)
	await frames(3)
	var mode := find_button(current_scene,title)
	if mode == null: return false
	await click_control(mode)
	return await wait_scene(path)
func preparation_counts() -> Array:
	return [loader.preparation_count,loader.actor_build_count,loader.arena_build_count,loader.fighter_build_count,SoundFx.i().catalog_load_count]
func preparation_exit() -> bool:
	root.size = Vector2i(960,540)
	var menu_tempo := Engine.time_scale
	if not await open_mode("Дуэль",DUEL_PATH): return false
	var game := current_scene
	var team: TeamMenu = game.team_menu
	check(game.ctrl == null and team.visible and team._back_btn.text == "← В меню" and not team._back_btn.disabled,"первый шаг дуэли показывает доступный выход до матча")
	check(is_equal_approx(Engine.time_scale,2.0) and is_equal_approx(menu_tempo,1.0),"подготовка применяет сохранённый темп дуэли")
	check(root.get_visible_rect().encloses(team._back_btn.get_global_rect()),"выход из подготовки целиком в экране 960×540")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(out.path_join("duel-preparation-960.png")) == OK,"кадр выхода из подготовки 960×540")
	await key(KEY_3)
	check(team._step == 2 and team._back_btn.text == "← Назад","на третьем шаге кнопка возвращает к предыдущему шагу")
	await key(KEY_ESCAPE)
	check(current_scene == game and team._step == 1,"Esc с третьего шага возвращает к воротам")
	await click_control(team._back_btn)
	check(current_scene == game and team._step == 0,"Назад с ворот возвращает к команде")
	var help_button := find_button(team,"Как играть")
	if help_button == null: return false
	await click_control(help_button)
	var help: HelpOverlay
	for child in team.get_children():
		if child is HelpOverlay: help = child
	check(is_instance_valid(help) and help.visible,"справка открылась над подготовкой")
	await key(KEY_ESCAPE)
	check(current_scene == game and (not is_instance_valid(help) or not help.visible),"Esc закрывает справку и оставляет команду")
	var initial_location := ArenaLocations.current()
	var preview_location := (initial_location + 1) % ArenaLocations.LOCATIONS.size()
	await click_control(team._arena_btn)
	check(team._arena_picker.visible,"выбор арены открыт над подготовкой")
	await key(KEY_RIGHT)
	check(game.arena.location_id == preview_location and ArenaLocations.current() == initial_location,"стрелка меняет только предпросмотр арены")
	await key(KEY_ESCAPE)
	check(current_scene == game and not team._arena_picker.visible and root.gui_get_focus_owner() == team._arena_btn,"Esc закрывает выбор арены и возвращает фокус к кнопке")
	check(game.arena.location_id == initial_location and ArenaLocations.current() == initial_location,"Esc восстанавливает сохранённую арену")
	await click_control(team._arena_btn)
	await click_control(team._arena_picker._buttons[preview_location])
	await click_control(team._arena_picker._confirm_button)
	check(not team._arena_picker.visible and root.gui_get_focus_owner() == team._arena_btn,"подтверждение мышью возвращает фокус к кнопке")
	var arena: Arena = game.arena
	var actor: CreatureBall = team._preview._borrowed_ball
	var location := arena.location_id
	check(location == preview_location and ArenaLocations.current() == location,"подтверждение сохраняет просмотренную арену")
	var old_game: WeakRef = weakref(game)
	check(is_instance_valid(actor) and loader._leased.has(actor.get_instance_id()) and not loader._arenas.has(location),"портретная модель и арена арендованы перед выходом")
	await click_control(team._back_btn)
	if not await wait_scene(MENU_PATH): return false
	check(old_game.get_ref() == null and is_equal_approx(Engine.time_scale,menu_tempo),"выход уничтожает сцену подготовки и возвращает темп меню")
	check(loader._arenas.size() == 3 and loader._arenas.get(location) == arena,"в каталог возвращена та же арена")
	check(is_instance_valid(actor) and loader._balls.get(actor.def.id,[]).has(actor) and loader._leased.is_empty(),"в каталог возвращена та же фигура предпросмотра")
	check(preparation_counts() == counts,"выход из подготовки сохраняет счётчики Boot")
	if not await open_mode("Дуэль",DUEL_PATH): return false
	game = current_scene
	check(game.team_menu.visible and game.ctrl == null and game.arena == arena,"повторный вход открывает первый шаг с той же ареной")
	await key(KEY_ESCAPE)
	if not await wait_scene(MENU_PATH): return false
	check(loader._leased.is_empty() and loader._arenas.size() == 3 and preparation_counts() == counts,"Esc с первого шага возвращает аренду и сохраняет каталог")
	root.size = Vector2i(1280,720)
	await frames(4)
	return true
func other_mode_navigation() -> bool:
	if not await open_mode("Новая кампания",DUEL_PATH): return false
	var game := current_scene
	var team: TeamMenu = game.team_menu
	check(team._back_btn.disabled and team._back_btn.text == "← Назад" and game.modes._registration_back.visible,"регистрация сохраняет собственную кнопку выхода")
	await key(KEY_ESCAPE)
	check(current_scene == game,"Esc из команды регистрации не запускает выход дуэли")
	await click_control(game.modes._registration_back)
	if not await wait_scene(MENU_PATH): return false
	if not await open_mode("Игра через интернет",ONLINE_PATH): return false
	var online := current_scene
	online._choose_deck()
	await frames(3)
	team = online.team_menu
	check(online.client.socket == null,"интерфейс интернет-команды открыт в тесте без подключения")
	check(team._back_btn.disabled and team._back_btn.text == "← Назад" and online._leave_button.visible,"сетевая команда сохраняет собственный выход")
	await key(KEY_ESCAPE)
	check(current_scene == online and team.visible,"Esc из сетевой команды не запускает локальный выход")
	await click_control(online._leave_button)
	return await wait_scene(MENU_PATH)
func start_duel() -> bool:
	current_scene._on_play()
	if not await until(func(): return current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn"): return false
	main = current_scene
	main.rng.seed = 424242
	main.team_menu.hide()
	var deck := CardDB.preset_deck(1)
	var creatures: Array[StringName] = []
	var gates: Array[StringName] = []
	var abilities: Array[StringName] = []
	for d in deck.creatures: creatures.append(d.id)
	for d in deck.arena: gates.append(d.id)
	for d in deck.abilities: abilities.append(d.id)
	main._on_deck_chosen(creatures,gates,abilities)
	if not await until(func():
		if not main._preparing: AutoPlay.press_next_turn(main)
		return not main._preparing and main.setup_panel._panel.visible): return false
	check(main._duel_menu.visible and not main._duel_menu.disabled,"обычная дуэль показывает активную кнопку В меню")
	check(preparation_counts()==counts,"после Boot нет новой подготовки моделей/арен/звуков")
	check(loader._leased.size()==6,"матч арендует ровно шесть существ")
	for uid in main._prepared_balls:
		var ball: CreatureBall = main._prepared_balls[uid]
		if identities.has(uid): check(identities[uid]==ball.get_instance_id(),"повтор использует тот же экземпляр uid=%d"%uid)
		else: identities[uid]=ball.get_instance_id()
		check(ball.uid==uid and ball.slot==-1 and not ball._shape.disabled and not ball._open,"uid/коллайдер/поза сброшены uid=%d"%uid)
	return true
func menu_exit() -> void:
	var previous := main
	var old_ref: WeakRef = weakref(previous)
	await click(main._duel_menu.get_global_rect().get_center())
	check(is_instance_valid(main._duel_exit_confirm) and main._duel_exit_confirm.visible,"кнопка запрашивает подтверждение выхода")
	await click(Vector2(main._duel_exit_confirm.position)+main._duel_exit_confirm.get_ok_button().get_global_rect().get_center())
	check(await until(func(): return current_scene != null and current_scene.scene_file_path=="res://scenes/menu/main_menu.tscn"),"выход приводит в главное меню")
	main = null
	previous = null
	await frames(8)
	check(old_ref.get_ref()==null,"сцена дуэли и владельцы await освобождены")
	check(loader._leased.is_empty() and loader._arenas.size()==3,"все существа и три арены возвращены в каталог")
	check(preparation_counts()==counts,"выход не пересоздаёт каталог")
	for id in loader._balls:
		for ball: CreatureBall in loader._balls[id]:
			check(not ball.visible and ball.process_mode==Node.PROCESS_MODE_DISABLED,"резерв скрыт и отключён")
			check(ball.surface_bounced.get_connections().is_empty(),"нет старого callback полёта в резерве")
			check(ball._stage_tween==null and ball._throw_tween==null,"твины арендуемых актёров остановлены")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with(ProjectSettings.globalize_path("res://build/checks/")):
		check(false,"выбор арены требует изолированных данных tools/check.py")
		await finish()
		return
	DirAccess.make_dir_recursive_absolute(out)
	Engine.time_scale = 1.0
	BattleTempo.loaded = true
	BattleTempo.selected = 3
	root.size = Vector2i(1280,720)
	root.content_scale_size=root.size
	change_scene_to_file("res://scenes/loading/boot.tscn")
	if not await until(func(): return current_scene != null and current_scene.scene_file_path=="res://scenes/menu/main_menu.tscn",180):
		check(false,"Boot завершается")
		await finish()
		return
	loader=GameLoading.i()
	counts=preparation_counts()
	if not await preparation_exit():
		check(false,"выход мышью и Esc из подготовки возвращает в главное меню")
		await finish()
		return
	if not await other_mode_navigation():
		check(false,"регистрация и интернет-команда возвращаются через собственные кнопки")
		await finish()
		return
	Engine.time_scale = 4.0
	if not await start_duel():
		check(false,"первая дуэль начинается")
		await finish()
		return
	# Выбранная карта сохраняется после отмены подтверждения.
	var card: Button = main.setup_panel._card_buttons.values()[0]
	await click(card.get_global_rect().get_center())
	var selected: StringName = main.setup_panel._selected
	await click(main._duel_menu.get_global_rect().get_center())
	await click(Vector2(main._duel_exit_confirm.position)+main._duel_exit_confirm.get_cancel_button().get_global_rect().get_center())
	check(main.setup_panel._selected==selected and selected!=&"","отмена выхода сохраняет выбор карты")
	check(not main._duel_exit_confirm.visible,"отмена закрывает подтверждение")
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size=size
		root.content_scale_size=size
		await frames(5)
		var rect: Rect2 = main._duel_menu.get_global_rect()
		check(root.get_visible_rect().encloses(rect),"кнопка целиком в экране %d"%size.x)
		for control in [main.setup_panel._panel,main.setup_panel._cards_box,main.ability_panel._panel]:
			if control.visible: check(not rect.intersects(control.get_global_rect()),"кнопка не перекрывает руку/управление %d"%size.x)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("duel-%d.png"%size.x))
		main.hud.set_battle_mode(true)
		main.battle_hud.open(["Атакующий","Защитник"],[0,1],[410,390])
		await frames(12)
		var battle_exit: Rect2 = main._duel_menu.get_global_rect()
		for plate in main.battle_hud._plates:
			check(not battle_exit.intersects(plate.get_global_rect()),"В меню не перекрывает боевую силу %d"%size.x)
		check(main._duel_menu.is_visible_in_tree() and root.get_visible_rect().encloses(battle_exit),"кнопка В меню видна целиком в бою %d"%size.x)
		main.hud.set_battle_mode(false)
		main.battle_hud.close()
		await frames(12)
	await menu_exit()
	if not await start_duel():
		check(false,"вторая дуэль начинается")
		await finish()
		return
	var bot := AIPlayer.new(0,4242)
	var target := 0
	var deadline := Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if main.hud._reading>0: main.hud._skip_flag=true
		if main.director.flying and main._active_ball!=null and not main._active_ball.freeze: break
		if AutoPlay.press_next_turn(main): continue
		var view: MatchState = main.ctrl.get_view(0)
		if main.setup_panel._panel.visible:
			var choice := bot.choose_setup(view,main.ctrl.legal_setup_slots(),main.ctrl.can_skip_gate())
			main.setup_panel.hide_panel()
			if choice.is_empty(): main._on_setup_skipped()
			else: main._on_setup_placed(choice.card_id,int(choice.slot))
		elif main.hud._creature_panel.visible:
			var choice := bot.choose_throw(view)
			target=int(choice.target_slot)
			main._on_creature_chosen(int(choice.uid))
		elif main._active_ball!=null and not main.director.flying and not main.events.is_busy(): main._on_slot_picked(target)
	check(main.director.flying and main._active_ball!=null and not main._active_ball.freeze,"выход проверяется во время настоящего физического полёта")
	await menu_exit()
	if not await start_duel():
		check(false,"третья дуэль начинается")
		await finish()
		return
	# Реальный экран результата намеренно оставлен ждать пользователя.
	var waiter := ResultWaiter.new()
	waiter.game=main
	main.add_child(waiter)
	main.events.push(waiter.wait_result)
	check(await until(func(): return main.battle_overlay._open),"EventPlayer ждёт подтверждения реального BattleOverlay")
	Engine.time_scale=1.0
	var moving: CreatureBall = main._spawn_ball(0)
	moving.stage_at(moving.global_position+Vector3(12,0,0),Vector3.ZERO)
	var vanishing: CreatureBall = main._spawn_ball(1)
	main._anim_remove_ball(1,true)
	check(main._prepared_balls.get(1)==vanishing and not main.balls.has(1),"исчезающий актёр учтён до завершения await")
	check(vanishing._open_tween!=null and vanishing._open_tween.is_running(),"выход прерывает живую vanish-анимацию")
	main.events.push(func(): check(false,"отменённая очередь не должна исполняться"))
	await menu_exit()
	check(Engine.max_fps==60,"лимит теста 60FPS сохранён")
	await finish()
func finish() -> void:
	if is_instance_valid(current_scene): current_scene.queue_free()
	await frames(3)
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	await frames(3)
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(3)
	print("DUEL EXIT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
