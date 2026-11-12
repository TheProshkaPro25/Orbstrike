extends RefCounted
## A mode operation either commits its domain save or returns a visible explanation.
var error: Error = OK
var message := ""

func _init(code: Error = OK, explanation: String = "") -> void:
	error = code
	message = explanation

func is_ok() -> bool:
	return error == OK
