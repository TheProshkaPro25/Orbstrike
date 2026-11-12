extends RefCounted
## Explicit UI references used by the interaction controller, no application backpointer.
var hud: HudUI
var setup: SetupPanel
var ability: AbilityPanel
var arena_picker: ArenaSlotPicker
var ability_picker: AbilityTargetPicker
var launch: Button
var layer: CanvasLayer
var team_menu: TeamMenu
var game_over: GameOverUI
var mode_modal_open: Callable
var mode_focus_controls: Callable

func blocking_modal() -> bool:
	if mode_modal_open.is_valid() and mode_modal_open.call(): return true
	if ability_picker.visible or is_instance_valid(hud) and hud._tempo.get_popup().visible: return true
	for child in layer.get_children():
		if child is BattleOverlay and child._open: return true
		if (child is HelpOverlay or child is MenuSettings) and child.is_visible_in_tree(): return true
	return false

func extra_focus_controls() -> Array[Control]:
	var result: Array[Control] = []
	if mode_focus_controls.is_valid(): result.assign(mode_focus_controls.call())
	return result
