extends RefCounted
## Архитектура локаций за пределами игрового поля. Сетка ворот и коллизии общие.
static func build(arena: Node3D, location: int) -> void:
	if location == 0:
		preload("res://scenes/sanctuary_interior.gd").build(arena)
	elif location == 1:
		preload("res://scenes/canyon_landscape.gd").build(arena)
	else:
		preload("res://scenes/harbor_landscape.gd").build(arena)
	arena._flush_static()
