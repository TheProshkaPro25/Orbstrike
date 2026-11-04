class_name SoundFx
extends Node
## Звук: эффекты, крики существ, музыка, шины громкости. Один экземпляр в корне дерева: SoundFx.i().
## Файлы: assets/audio/sfx/<имя>.ogg, assets/audio/creatures/<вид>_<стихия>_<appear|attack>.ogg,
## assets/audio/music/*.ogg. Записанные звуки собирает tools/audio/build_sfx.py (источники и лицензии — CREDITS.md);
## если .ogg нет, берётся .wav с тем же именем (старые синтезированные файлы tools/audio/gen_sfx.py).

const SFX_DIR := "res://assets/audio/sfx/"
const CREATURE_DIR := "res://assets/audio/creatures/"
## Музыка (Suno → tools/audio/prep_music.py: петля, −23 LUFS). Ходы матча — battle.ogg, пока его нет — team.ogg.
const MUSIC_MENU := "res://assets/audio/music/menu.ogg"
const MUSIC_TEAM := "res://assets/audio/music/team.ogg"
const MUSIC_BATTLE := "res://assets/audio/music/battle.ogg"
const MUSIC_CLASH := "res://assets/audio/music/battle_clash.ogg"
const MUSIC_XFADE := 2.5
const POOL := 14
const MUSIC_DB := -9.0
const SFX_DB := -2.0
## Все короткие эффекты (имена файлов без расширения) — для прогрева кэша и стенда tools/audio/play_all.gd.
const SFX_NAMES: Array[String] = [
	"ui_hover", "ui_click", "ui_denied", "turn_yours", "turn_opponent", "card_swoosh", "gate_flight_wind", "gate_expand_wave", "card_select", "card_place", "card_flip", "card_capture", "turn_start",
	"ball_throw", "ball_bounce_1", "ball_bounce_2", "ball_bounce_3", "ball_roll_loop", "ball_land", "capsule_open",
	"battle_start", "clash", "power_up", "power_down", "miss", "eliminated", "vanish",
	"battle_win", "battle_lose", "victory", "defeat", "gate_trap",
	"ability_play", "ability_cancel", "ability_fusion",
	"ability_fire", "ability_gale", "ability_light", "ability_stone", "ability_shadow", "ability_tide",
]
## Суффиксы стихий по Attr.A (как GameData.ATTR_KEYS): имя способности и файлов криков.
const ATTR_KEYS: Array[String] = ["fire", "gale", "light", "stone", "shadow", "tide"]

const VARIANTS := ["card_select", "card_place", "ball_throw", "clash"]
var _last_variant: Dictionary = {}
var _cache: Dictionary = {}
var catalog_ready := false
## Число обращений к новым путям (включая отсутствующий необязательный крик).
## После начальной загрузки обычная игра должна использовать только кэш.
var catalog_load_count := 0
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _roll: AudioStreamPlayer
var _mus: Array[AudioStreamPlayer] = []  # два плеера: текущий и следующий — для кроссфейда
var _mus_cur := 0
var _mus_path := ""
var _mus_resume: Dictionary = {}           # путь -> позиция: вернувшись к треку, играем дальше, а не сначала
var _music_tw: Tween
var _last_play: Dictionary = {}   # имя -> время, чтобы одинаковые звуки не накладывались кашей
var _match_sfx_epoch := 0
var music_muted := false

static var _inst: SoundFx


## Единственный экземпляр (создаётся при первом обращении и живёт в корне, переживая перезагрузку сцены).
static func i() -> SoundFx:
	if _inst == null or not is_instance_valid(_inst):
		_inst = SoundFx.new()
		_inst.name = "SoundFx"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	return _inst


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music", MUSIC_DB)
	_ensure_bus("SFX", SFX_DB)
	for i in range(POOL):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_roll = AudioStreamPlayer.new()
	_roll.bus = "SFX"
	_roll.volume_db = -60.0
	add_child(_roll)
	for _k in range(2):
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_mus.append(m)
	(Engine.get_main_loop() as SceneTree).node_added.connect(_on_node_added)


## Прогрев кэша коротких эффектов: первый звук броска/удара не ждёт загрузки с диска.
func _ready() -> void:
	_preload_effects()


func _preload_effects() -> void:
	for n in SFX_NAMES:
		_load(SFX_DIR + n)
	for n in VARIANTS:
		for v in [2, 3]:
			_load(SFX_DIR + n + "_v%d" % v)


## Только ресурсы: без запуска воспроизведения/декодеров. Держим музыку, все
## варианты и крики в одном живущем между сценами кэше до закрытия приложения.
func preload_catalog() -> void:
	if catalog_ready:
		return
	_preload_effects()
	for d in CreatureModels.catalog_defs():
		var short := String(d.id).trim_prefix("creature_")
		for kind in ["appear", "attack"]:
			_load(CREATURE_DIR + "%s_%s" % [short, kind])
	for path in [MUSIC_MENU, MUSIC_TEAM, MUSIC_BATTLE, MUSIC_CLASH]:
		_load(path.get_basename())
	catalog_ready = true


## Выход из игры: останавливаем плееры и отпускаем звуки, иначе при закрытии остаются
## «resources still in use» / «ObjectDB instances leaked» (воспроизведения ещё держат потоки).
func _exit_tree() -> void:
	for p in _pool + [_roll] + _mus:
		p.stop()
		p.stream = null
	_cache.clear()
	catalog_ready = false


func _ensure_bus(bus_name: String, db: float) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(i, db)


## path без расширения: сначала .ogg (записанные), затем .wav (синтезированные).
func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	catalog_load_count += 1
	var s: AudioStream = null
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(path + ext):
			s = load(path + ext)
			break
	_cache[path] = s
	return s


## Есть ли файл эффекта (для стенда и проверок).
func has_sfx(sfx_name: String) -> bool:
	return _load(SFX_DIR + sfx_name) != null


func _play_stream(s: AudioStream, db: float, pitch: float) -> void:
	if s == null:
		return
	if not is_inside_tree():
		# экземпляр только что создан и ещё не добавлен в корень (add_child отложен) — играем на следующем кадре
		_play_stream.call_deferred(s, db, pitch)
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


## Короткий эффект. jitter - случайный разброс высоты (доля).
func play(sfx_name: String, db: float = 0.0, jitter: float = 0.04, pitch: float = 1.0) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(sfx_name, -1000)) < 40:
		return
	_last_play[sfx_name] = now
	var file_name := sfx_name
	if VARIANTS.has(sfx_name):
		var previous := int(_last_variant.get(sfx_name, -1))
		var variant := (previous + randi_range(1, 2)) % 3 if previous >= 0 else randi_range(0, 2)
		_last_variant[sfx_name] = variant
		file_name = sfx_name if variant == 0 else sfx_name + "_v%d" % (variant + 1)
	_play_stream(_load(SFX_DIR + file_name), db, pitch * (1.0 + randf_range(-jitter, jitter)))


## Остановить хвост уже загруженного эффекта, не загружая новых ресурсов.
func stop_sfx(sfx_name: String) -> void:
	var stream: AudioStream = _cache.get(SFX_DIR + sfx_name)
	if stream == null: return
	for player in _pool:
		if player.stream == stream: player.stop()


## Выход из обычной дуэли: хвосты и отложенные крики не переходят в меню.
## Музыка и прогретый каталог остаются у singleton; следующий матч может звучать сразу.
func cancel_match_sfx() -> void:
	_match_sfx_epoch += 1
	_roll.stop()
	for player in _pool:
		player.stop()
		player.stream = null
	_last_play.clear()


func _play_if_current(epoch: int, sfx_name: String, db: float) -> void:
	if epoch == _match_sfx_epoch:
		play(sfx_name, db)


func _play_stream_if_current(epoch: int, stream: AudioStream, db: float, pitch: float) -> void:
	if epoch == _match_sfx_epoch:
		_play_stream(stream, db, pitch)


## Отложенный эффект (не блокирует вызывающего).
func play_later(sfx_name: String, delay: float, db: float = 0.0) -> void:
	(Engine.get_main_loop() as SceneTree).create_timer(delay).timeout.connect(_play_if_current.bind(_match_sfx_epoch, sfx_name, db))


## Крик существа: kind = "appear" | "attack".
func cry(creature_id: StringName, kind: String = "appear", delay: float = 0.0, db: float = -1.0) -> void:
	var short := String(creature_id).trim_prefix("creature_")
	var s := _load(CREATURE_DIR + "%s_%s" % [short, kind])
	if delay <= 0.0:
		_play_stream(s, db, randf_range(0.97, 1.03))
	else:
		(Engine.get_main_loop() as SceneTree).create_timer(delay).timeout.connect(_play_stream_if_current.bind(_match_sfx_epoch, s, db, 1.0))


## Способность: звук по стихии карты (params.lock — стихия-замок) или слиянию, иначе общий.
func ability(card: CardDef, cancelled: bool = false, db: float = 0.0) -> void:
	play(ability_sfx(card, cancelled), db)


static func ability_sfx(card: CardDef, cancelled: bool = false) -> String:
	if cancelled:
		return "ability_cancel"
	if card != null:
		var lock: int = int(card.params.get("lock", -1))
		if lock >= 0 and lock < ATTR_KEYS.size():
			return "ability_" + ATTR_KEYS[lock]
		if card.params.get("fusion", false):
			return "ability_fusion"
	return "ability_play"


## Actor's card ignition: universal cards inherit the target creature's element.
static func activation_sfx(card: CardDef, element: int) -> String:
	if card != null and card.params.get("fusion", false): return "ability_fusion"
	if element >= 0 and element < ATTR_KEYS.size(): return "ability_"+ATTR_KEYS[element]
	return ability_sfx(card)


## Удар шара о борт/стол; strength - скорость удара (м/с).
func bounce(strength: float) -> void:
	if strength < 1.2 * Arena.WORLD:
		return
	var db := linear_to_db(clampf(strength / (9.0 * Arena.WORLD), 0.08, 1.0)) - 2.0
	play("ball_bounce_%d" % randi_range(1, 3), db, 0.08)


## Качение шара: громкость от скорости, 0 - тишина.
func set_roll(speed: float) -> void:
	if _roll.stream == null:
		var src := _load(SFX_DIR + "ball_roll_loop")
		if src == null:
			return
		var s: AudioStream = src.duplicate()
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		elif s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		_roll.stream = s
	var v := clampf(speed / (7.0 * Arena.WORLD), 0.0, 1.0)
	if v < 0.03:
		if _roll.playing:
			_roll.stop()
		return
	if not _roll.playing and is_inside_tree():
		_roll.play()
	_roll.volume_db = linear_to_db(v) - 8.0
	_roll.pitch_scale = 0.8 + 0.5 * v


# ---------------------------------------------------------------- музыка

## Музыка ходов матча: battle.ogg, если трек есть, иначе музыка выбора команды.
func turn_music() -> String:
	return MUSIC_BATTLE if ResourceLoader.exists(MUSIC_BATTLE) or FileAccess.file_exists(MUSIC_BATTLE) else MUSIC_TEAM


## Плавный переход на трек: старый гаснет, новый нарастает (равная мощность), без обрыва.
## resume — продолжить трек с места, где он прервался (музыка хода после боя).
func play_music(path: String, fade: float = MUSIC_XFADE, resume: bool = true) -> void:
	var cur := _mus[_mus_cur]
	if path == _mus_path and cur.playing:
		_fade_to(cur, fade)  # снять приглушение и завершить уход другого трека
		return
	var s := _load(path.get_basename())
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	if _mus_path != "" and cur.playing:
		_mus_resume[_mus_path] = cur.get_playback_position()
	var nxt := _mus[1 - _mus_cur]
	# Быстрый возврат A→B→A разворачивает ещё живой кроссфейд:
	# сохраняем амплитуду и декодер A, вместо stop/play и провала до −80 dB.
	if not (resume and nxt.playing and nxt.stream == s):
		nxt.stop()
		nxt.stream = s
		nxt.volume_db = -80.0
		var at := 0.0
		if resume and _mus_resume.has(path):
			at = fmod(float(_mus_resume[path]), maxf(s.get_length(), 1.0))
		if nxt.is_inside_tree():
			nxt.play(at)
		else:
			nxt.play.call_deferred(at)
	_mus_cur = 1 - _mus_cur
	_mus_path = path
	_fade_to(nxt, fade)


func stop_music(fade: float = 1.2) -> void:
	var cur := _mus[_mus_cur]
	if _mus_path != "" and cur.playing:
		_mus_resume[_mus_path] = cur.get_playback_position()
	_mus_path = ""
	_fade_to(null, fade)


## Приглушить музыку на время джингла/важного звука (вернуть — play_music того же трека).
func duck_music(db: float = -14.0, fade: float = 0.4) -> void:
	var cur := _mus[_mus_cur]
	_fade_to(cur if cur.playing else null, fade, db)


## Любой новый переход завершает уход всех остальных плееров, даже если
## предыдущий tween прервали повторным запросом, приглушением или stop.
func _fade_to(incoming: AudioStreamPlayer, fade: float, incoming_db: float = 0.0) -> void:
	if _music_tw != null:
		_music_tw.kill()
	var in0 := db_to_linear(incoming.volume_db) if incoming != null else 0.0
	var target := db_to_linear(incoming_db)
	var outgoing: Dictionary = {}
	for player in _mus:
		if player != incoming and player.playing:
			outgoing[player] = db_to_linear(player.volume_db)
	_music_tw = create_tween()
	_music_tw.tween_method(func(t: float) -> void:
		if incoming != null:
			incoming.volume_db = linear_to_db(maxf(lerpf(in0, target, sin(t * PI / 2.0)), 0.0001))
		for player: AudioStreamPlayer in outgoing:
			player.volume_db = linear_to_db(maxf(float(outgoing[player]) * cos(t * PI / 2.0), 0.0001)),
		0.0, 1.0, maxf(fade, 0.05))
	for player: AudioStreamPlayer in outgoing:
		_music_tw.tween_callback(player.stop)


func toggle_music_mute() -> void:
	music_muted = not music_muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), music_muted)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match (e as InputEventKey).keycode:
			KEY_M:
				toggle_music_mute()


# ---------------------------------------------------------------- кнопки интерфейса

func _on_node_added(n: Node) -> void:
	if n is CardView:
		var cv := n as CardView
		if not cv.mouse_entered.is_connected(_ui_hover):
			cv.mouse_entered.connect(_ui_hover.bind(cv))
			cv.pressed.connect(func() -> void:
				if not cv.get_meta("silent_select", false):
					play("card_select", -3.0))
	elif n is BaseButton:
		var b := n as BaseButton
		if not b.pressed.is_connected(_ui_click):
			b.pressed.connect(_ui_click)
			b.mouse_entered.connect(_ui_hover.bind(b))


func _ui_click() -> void:
	play("ui_click", -4.0)


func _ui_hover(b: BaseButton) -> void:
	if not b.disabled:
		play("ui_hover", -10.0, 0.06)
