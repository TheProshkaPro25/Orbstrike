class_name MatchRules
extends RefCounted

const MAX_BATTLE_ABILITIES: int = 3
## Направление правил, не заявление о точном воспроизведении аниме.
## LEGACY сохраняет авторские бонусы прежней версии для сравнения и старых сценариев.
enum Ruleset { ANIME_INSPIRED, LEGACY }
const LEGACY_RESCUE_EFFECTS: Array[String] = ["ebb", "doom", "revive", "copy"]

static func author_bonuses(ruleset: int) -> bool:
	return ruleset == Ruleset.LEGACY


## Последний рывок сокращает только обычный отдых, не явные returns/recall.
## ANIME: мгновенно возвращаются только синие усиления; управление и видовые отдыхают.
## LEGACY сохраняет историческое исключение для спасения и Копии.
static func last_rush_returns(card: CardDef, ruleset: int = Ruleset.ANIME_INSPIRED) -> bool:
	if card == null or card.kind != CardDef.Kind.ABILITY or bool(card.params.get("cooldown_always", false)):
		return false
	if ruleset == Ruleset.LEGACY:
		return not LEGACY_RESCUE_EFFECTS.has(String(card.effect_id))
	return CardDB.card_class(card) == &"blue"
