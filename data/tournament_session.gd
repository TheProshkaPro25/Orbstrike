class_name TournamentSession
extends RefCounted
## Одноразовое намерение перехода из главного меню. Данные турнира принадлежат Main.

static var entry_mode: String = ""


static func take_entry_mode() -> String:
	var requested := entry_mode
	entry_mode = ""
	return requested
