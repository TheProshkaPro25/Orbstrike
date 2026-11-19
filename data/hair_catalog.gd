class_name HairCatalog
extends RefCounted
## Profile IDs are shared by both bases. Append new IDs just before SLOT_COUNT.
const LEGACY_COUNT := 11
enum {
	MICKET = LEGACY_COUNT, ANIME_GIRL, VICTORIA, SHINO,
	GEAR_PONYTAIL, GEAR_BOB, GEAR_FACE_FRAMING, GEAR_LAYERED,
	GEAR_ROUND, GEAR_SIDE_BANGS, GEAR_TAPERED,
	GEAR_CASCADE, GEAR_TWIN_TAILS, GEAR_STRAIGHT_TAIL, SLOT_COUNT,
}
const LEGACY_NAMES := ["Исходная", "Острые пряди", "Хвосты с ушками", "Боб с чёлкой", "Альтернативная чёлка", "Взъерошенные", "Асимметричная чёлка", "Короткие пряди", "Каре с пробором", "Высокий хвост", "Боковой пробор"]
const ADDITIONS := {
	MICKET: ["Хвост Micket", "micket_pony"],
	ANIME_GIRL: ["Anime Girl", "anime_long"],
	VICTORIA: ["Victoria", "victoria"],
	SHINO: ["Shino", "shino"],
	GEAR_PONYTAIL: ["Хвост GEAR", "clct_gear_allhair_248"],
	GEAR_BOB: ["Каре GEAR", "clct_gear_allhair_249"],
	GEAR_FACE_FRAMING: ["Пряди у лица GEAR", "clct_gear_allhair_250"],
	GEAR_LAYERED: ["Слоистая стрижка GEAR", "clct_gear_allhair_251"],
	GEAR_ROUND: ["Короткая округлая стрижка GEAR", "clct_gear_allhair_252"],
	GEAR_SIDE_BANGS: ["Косая чёлка GEAR", "clct_gear_allhair_253"],
	GEAR_TAPERED: ["Короткие пряди GEAR", "clct_gear_allhair_254"],
	GEAR_CASCADE: ["Каскад с боковым пробором GEAR", "clct_gear_back_142"],
	GEAR_TWIN_TAILS: ["Парные изогнутые хвосты GEAR", "clct_gear_tied_622"],
	GEAR_STRAIGHT_TAIL: ["Длинный прямой хвост GEAR", "clct_gear_tied_623"],
}
const ASSET_DIR := "res://assets/avatars/hair/"

static func style_name(model: int, id: int) -> String:
	if id == 4: return "Каре с украшениями" if model == 0 else "Мягкая чёлка"
	return LEGACY_NAMES[id] if id < LEGACY_COUNT else ADDITIONS[id][0]

static func asset_path(model: int, id: int) -> String:
	return ASSET_DIR + "%s_%d.res" % [ADDITIONS[id][1], model]

static func has_style(id: int) -> bool:
	if id >= 0 and id < LEGACY_COUNT: return true
	return ADDITIONS.has(id) and ResourceLoader.exists(asset_path(0, id), "ArrayMesh") and ResourceLoader.exists(asset_path(1, id), "ArrayMesh")

static func available_additions() -> Array[int]:
	var ids: Array[int] = []
	for id in ADDITIONS:
		if has_style(id): ids.append(id)
	return ids
