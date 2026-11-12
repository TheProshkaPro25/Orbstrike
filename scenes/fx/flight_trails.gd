extends Node3D
## Boot warms a reusable world-space trail for each of the six match elements.

const ElementalTrail := preload("res://assets/vfx/trails/elemental_trail.gd")
const MATCH_DURATION_SCALE := 0.80
const VARIANTS := [
	ElementalTrail.Style.FIRE, ElementalTrail.Style.ELECTRIC, ElementalTrail.Style.SOUND,
	ElementalTrail.Style.EARTH, ElementalTrail.Style.DARK, ElementalTrail.Style.WATER,
]

# These two silhouettes need more room near the shell in the pursuit camera.
const MATCH_VIEW_SHAPES := {Attr.A.FIRE: Vector2(1.40, 2.25), Attr.A.STONE: Vector2(1.33, 1.75)}

var _trails: Dictionary[int, ElementalTrail] = {}


func prepare() -> void:
	if not _trails.is_empty():
		return
	for element in Attr.COUNT:
		var trail := ElementalTrail.new()
		trail.configure(VARIANTS[element], MATCH_DURATION_SCALE,
			MATCH_VIEW_SHAPES.get(element, Vector2.ONE))
		trail.manual_sampling = true
		add_child(trail)
		trail.set_airborne(true, 0.32)
		_trails[element] = trail
	# Render moving geometry in the warm viewport before the first throw.
	for frame in 5:
		for element in Attr.COUNT:
			var point := Vector3(float(element - 3) * 3.0 + 0.42 * frame, 5.6 + 0.09 * frame, 0.0)
			_trails[element].position = point
			_trails[element].sample(_trails[element].global_position, 1.0 / 60.0)
		await get_tree().process_frame
	for trail in _trails.values():
		trail.set_airborne(false)
		trail.position = Vector3.ZERO


func take(element: int, shell: Node3D) -> ElementalTrail:
	var trail: ElementalTrail = _trails.get(element)
	if not is_instance_valid(trail) or trail.get_parent() != self:
		return null
	trail.reparent(shell, false)
	set_airborne(trail, true)
	return trail


func release(trail: ElementalTrail) -> void:
	trail.set_airborne(false)
	trail.reparent(self, false)


func set_airborne(trail: ElementalTrail, airborne: bool) -> void:
	if trail._active != airborne:
		var shell := trail.get_parent() as Node3D
		trail.set_airborne(airborne, shell.global_basis.x.length(), GraphicsSettings.current())
