class_name WardrobeCatalog
extends RefCounted
## Each stored ID is the one-based gallery number minus one. Retired IDs stay vacant.
const LEGACY_COUNTS := [7, 8]
const RETIRED_SAKURADA_IDS := [9, 10]
const LEGACY_NAMES := [
	["Школьный", "Худи", "Короткое худи", "Удлинённая куртка", "Контрастное худи", "Бомбер", "Спортивный костюм"],
	["Сценический", "Платье-рубашка", "Летнее платье", "Короткое худи", "Удлинённая куртка", "Контрастное худи", "Бомбер", "Спортивный костюм"],
]
# Matching cut, long, contrast, bomber and sport styles in each base's gallery order.
const SHARED_OUTFIT_IDS := [[2, 3, 4, 5, 6], [3, 4, 5, 6, 7]]
const ADDITIONS := [
	{
		7: ["Кимоно с хаори", "haori_0"],
		8: ["Фэнтезийная мантия", "fantasy_robe_0"],
		11: ["Хаори с оленями", "deer_haori_0"],
		12: ["Доспех", "orchid_armor_0"],
		13: ["Мундир", "orchid_uniform_0"],
	},
	{
		8: ["Форма OC", "oc_uniform_1"],
		9: ["Дирндль", "dirndl_1"],
		10: ["Пальто оператора", "operator_1"],
		11: ["Жакет и брюки", "jacket_pants_1"],
		12: ["Dreamy Angel", "dreamy_angel_1"],
	},
]
const SLOT_COUNT := 14

static func outfit_for_model_switch(from_model: int, id: int, to_model: int) -> int:
	if from_model == to_model: return id
	var shared_index: int = SHARED_OUTFIT_IDS[from_model].find(id)
	return SHARED_OUTFIT_IDS[to_model][shared_index] if shared_index >= 0 else 0

static func available_ids(model: int) -> Array:
	var ids := range(LEGACY_COUNTS[model])
	for id in ADDITIONS[model]:
		if has_outfit(model, id): ids.append(id)
	return ids

static func has_outfit(model: int, id: int) -> bool:
	if id < 0: return false
	if id < LEGACY_COUNTS[model]: return true
	return is_addition(model, id) and ResourceLoader.exists(asset_path(model, id), "ArrayMesh")

static func is_addition(model: int, id: int) -> bool:
	return ADDITIONS[model].has(id)

static func outfit_name(model: int, id: int) -> String:
	if not has_outfit(model, id): return "—"
	return ADDITIONS[model][id][0] if is_addition(model, id) else LEGACY_NAMES[model][id]

static func asset_path(model: int, id: int) -> String:
	return "res://assets/avatars/booth/%s.res" % ADDITIONS[model][id][1]
