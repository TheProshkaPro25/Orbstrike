class_name CardArtwork
extends RefCounted
## Original vector illustrations. Preloads keep every illustration in exported packages.
## Card identity comes from its element/species; gate illustrations depict the actual object.
const ELEMENTS := ["flame", "tornado", "star", "rock", "skull", "wave"]
const TEXTURES := {
	"altar": preload("res://assets/cards/art/altar.svg"),
	"clash": preload("res://assets/cards/art/clash.svg"),
	"dragnar": preload("res://assets/cards/art/dragnar.svg"),
	"dusk_throne": preload("res://assets/cards/art/dusk_throne.svg"),
	"fallen_call": preload("res://assets/cards/art/fallen_call.svg"),
	"flame": preload("res://assets/cards/art/flame.svg"),
	"funnel": preload("res://assets/cards/art/funnel.svg"),
	"gate_dragnar": preload("res://assets/cards/art/gate_dragnar.svg"),
	"gate_flame": preload("res://assets/cards/art/gate_flame.svg"),
	"gate_gorgul": preload("res://assets/cards/art/gate_gorgul.svg"),
	"gate_grifalon": preload("res://assets/cards/art/gate_grifalon.svg"),
	"gate_klykar": preload("res://assets/cards/art/gate_klykar.svg"),
	"gate_kolossar": preload("res://assets/cards/art/gate_kolossar.svg"),
	"gate_levian": preload("res://assets/cards/art/gate_levian.svg"),
	"gate_ratnik": preload("res://assets/cards/art/gate_ratnik.svg"),
	"gate_rock": preload("res://assets/cards/art/gate_rock.svg"),
	"gate_rogozhuk": preload("res://assets/cards/art/gate_rogozhuk.svg"),
	"gate_skull": preload("res://assets/cards/art/gate_skull.svg"),
	"gate_star": preload("res://assets/cards/art/gate_star.svg"),
	"gate_tornado": preload("res://assets/cards/art/gate_tornado.svg"),
	"gate_wave": preload("res://assets/cards/art/gate_wave.svg"),
	"gorgul": preload("res://assets/cards/art/gorgul.svg"),
	"grifalon": preload("res://assets/cards/art/grifalon.svg"),
	"hold": preload("res://assets/cards/art/hold.svg"),
	"klykar": preload("res://assets/cards/art/klykar.svg"),
	"kolossar": preload("res://assets/cards/art/kolossar.svg"),
	"levian": preload("res://assets/cards/art/levian.svg"),
	"limit": preload("res://assets/cards/art/limit.svg"),
	"mirror": preload("res://assets/cards/art/mirror.svg"),
	"mute": preload("res://assets/cards/art/mute.svg"),
	"ratnik": preload("res://assets/cards/art/ratnik.svg"),
	"rock": preload("res://assets/cards/art/rock.svg"),
	"rogozhuk": preload("res://assets/cards/art/rogozhuk.svg"),
	"skull": preload("res://assets/cards/art/skull.svg"),
	"star": preload("res://assets/cards/art/star.svg"),
	"tornado": preload("res://assets/cards/art/tornado.svg"),
	"wave": preload("res://assets/cards/art/wave.svg"),
	"web": preload("res://assets/cards/art/web.svg"),
	"valor": preload("res://assets/cards/art/valor.svg"),
	"weight": preload("res://assets/cards/art/weight.svg"),
}


static func key_for(def: CardDef) -> String:
	var gate := def.kind == CardDef.Kind.ARENA
	var species := String(CardEffects.species_lock(def))
	if not species.is_empty():
		return ("gate_" if gate else "") + species
	var attr := CardEffects.lock_attr(def)
	if attr < 0:
		attr = int(def.params.get("attr", -1))
	if attr >= 0 and attr < ELEMENTS.size():
		return ("gate_" if gate else "") + ELEMENTS[attr]
	if gate:
		return String(def.id).trim_prefix("arena_")
	return ""


static func texture_for(def: CardDef) -> Texture2D:
	return TEXTURES.get(key_for(def)) as Texture2D
