extends RefCounted

const FEATURE := "illustrated_harbor"
const LOCATION := 3
const NAME := "Рисованная гавань"
const DESCRIPTION := "Дневной архипелаг с рисованными островами, облаками и бирюзовыми отмелями."
const CANVAS_PATH := "res://scenes/experiments/illustrated_harbor/harbor_canvas.gd"
const DECK_PATH := "res://scenes/experiments/illustrated_harbor/deck.gdshader"
static var canvas_script: Script


static func enabled() -> bool:
	return OS.has_feature(FEATURE) or (OS.has_feature("editor") and OS.get_environment("ORBSTRIKE_ILLUSTRATED_HARBOR") == "1")


static func applies(location: int) -> bool:
	return location == LOCATION


static func prepare() -> void:
	if canvas_script == null:
		canvas_script = load(CANVAS_PATH)
