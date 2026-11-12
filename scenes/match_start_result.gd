extends RefCounted
## Explicit outcome of scene-side preparation; domain rules stay in core/.
var error: Error = OK
var message := ""

func _init(code: Error = OK, text: String = "") -> void:
	error = code
	message = text

func is_ok() -> bool:
	return error == OK
