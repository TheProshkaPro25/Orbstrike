class_name PlayerProfile
extends RefCounted
## Только данные. Редактор работает с копией, запись происходит по «Сохранить».
const PATH := "user://player_profile.json"
const VERSION := 2
const DEFAULT := {"version": VERSION, "name": "Haru Akiyama", "vrm_model": 0, "vrm_case": 0, "vrm_denim": 0, "vrm_style": 0, "vrm_clothes": 0, "vrm_eye_shape": 0, "vrm_brows": 0, "vrm_mouth": 0, "vrm_hair": 0, "vrm_eyes": 0, "vrm_skin": 0, "vrm_outfit": 0, "vrm_outfit_color": "", "vrm_height": 1, "body": 0, "face": 0, "hair": 0, "skin": 1, "hair_color": 0, "eyes": 0, "jacket": 0, "element": 0}
const LIMITS := {"vrm_case": 2, "vrm_denim": 15, "vrm_style": 11, "vrm_clothes": WardrobeCatalog.SLOT_COUNT, "vrm_eye_shape": 3, "vrm_brows": 3, "vrm_mouth": 3,"vrm_model": 2, "vrm_hair": 6, "vrm_eyes": 6, "vrm_skin": 4, "vrm_outfit": 5, "vrm_height": 3,"body": 3, "face": 3, "hair": 3, "skin": 6, "hair_color": 6, "eyes": 6, "jacket": 4, "element": 6}
# Permanent tournament identities, in participant ID order (1–7). Each look uses
# one complete prepared costume: no remembered player denim or case overlays.
# Hair silhouettes and clothing colours remain stable when resident actors reuse a base.
const NPC_PRESETS := [
	{"name":"Akari Hoshino", "vrm_model":1, "vrm_style":9, "vrm_clothes":6, "vrm_hair":5, "vrm_eyes":4, "vrm_outfit":1, "vrm_height":1, "vrm_mouth":1},
	{"name":"Ren Kazehara", "vrm_model":0, "vrm_style":10, "vrm_clothes":6, "vrm_hair":2, "vrm_eyes":1, "vrm_outfit":2, "vrm_height":1, "vrm_eye_shape":1},
	{"name":"Hikari Aizawa", "vrm_model":1, "vrm_style":8, "vrm_clothes":1, "vrm_hair":3, "vrm_eyes":4, "vrm_outfit":0, "vrm_height":0, "vrm_brows":2, "vrm_mouth":1},
	{"name":"Daichi Iwata", "vrm_model":0, "vrm_style":7, "vrm_clothes":3, "vrm_hair":1, "vrm_eyes":2, "vrm_outfit":3, "vrm_height":2, "vrm_skin":1},
	{"name":"Yui Kurose", "vrm_model":1, "vrm_style":3, "vrm_clothes":3, "vrm_hair":2, "vrm_eyes":5, "vrm_outfit":4, "vrm_height":1, "vrm_eye_shape":1},
	{"name":"Kaito Minase", "vrm_model":0, "vrm_style":0, "vrm_clothes":1, "vrm_hair":4, "vrm_eyes":1, "vrm_outfit":0, "vrm_height":1, "vrm_eye_shape":2},
	{"name":"Takumi Hayashi", "vrm_model":0, "vrm_style":0, "vrm_clothes":0, "vrm_hair":1, "vrm_eyes":4, "vrm_outfit":0, "vrm_height":2, "vrm_brows":1},
]
var value: Dictionary = DEFAULT.duplicate(true)
var writable := true
var notice := ""

static func npc_profile(participant_id: int) -> Dictionary:
	if participant_id < 1 or participant_id > NPC_PRESETS.size():
		return DEFAULT.duplicate(true)
	return normalized(NPC_PRESETS[participant_id - 1])

static func normalized(source: Dictionary) -> Dictionary:
	var result := DEFAULT.duplicate(true)
	var raw_name: String = str(source.get("name", DEFAULT.name)).strip_edges()
	for code in range(1,32):
		raw_name = raw_name.replace(String.chr(code), "")
	result.name = raw_name.left(24) if not raw_name.is_empty() else DEFAULT.name
	for key in LIMITS:
		var v: Variant = source.get(key, DEFAULT[key])
		if (v is int or v is float) and is_finite(float(v)) and float(v) >= 0 and float(v) < LIMITS[key]:
			result[key] = int(v)
	var outfit_color: Variant = source.get("vrm_outfit_color", "")
	if outfit_color is String and outfit_color.length() == 6 and Color.html_is_valid(outfit_color):
		result.vrm_outfit_color = outfit_color.to_lower()
	if not WardrobeCatalog.has_outfit(result.vrm_model, result.vrm_clothes): result.vrm_clothes = 0
	return result

func load_from(path: String = PATH) -> void:
	value = DEFAULT.duplicate(true)
	writable = true
	notice = ""
	if not FileAccess.file_exists(path): return
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(path))
	var parsed: Variant = parser.data if parse_error == OK else null
	if not parsed is Dictionary or not parsed.get("version") is float and not parsed.get("version") is int:
		writable = false
		notice = "Профиль повреждён. Исходный файл сохранён; показан стандартный образ."
		return
	if parsed.version != VERSION and parsed.version != 1:
		writable = false
		notice = "Эта версия профиля не поддерживается. Исходный файл сохранён."
		return
	value = normalized(parsed)
	if parsed.version == 1:
		notice = "Имя сохранено. Выберите образ на новой аниме-основе."
	elif value.vrm_model == 0:
		var previous_id: Variant = parsed.get("vrm_clothes", 0)
		if previous_id is int or previous_id is float:
			if is_finite(float(previous_id)) and int(previous_id) in WardrobeCatalog.RETIRED_SAKURADA_IDS:
				notice = "Комплект перенесён к Вите. Сакурада в стандартном костюме, цвет сохранён."

func save_to(draft: Dictionary, path: String = PATH) -> Error:
	if not writable: return ERR_UNAVAILABLE
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(normalized(draft), "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return error
	if FileAccess.file_exists(path):
		error = DirAccess.copy_absolute(path, path + ".bak")
		if error != OK: return error
	error = DirAccess.rename_absolute(temp, path)
	if error == OK: value = normalized(draft)
	return error
