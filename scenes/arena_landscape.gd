extends RefCounted
## Архитектура локаций за пределами игрового поля. Сетка ворот и коллизии общие.
static func build(arena: Node3D, location: int) -> void:
	if location == 0:
		preload("res://scenes/sanctuary_interior.gd").build(arena)
	elif location == 1:
		_canyon(arena)
	else:
		_harbor(arena)
	arena._flush_static()

static func _canyon(arena: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2007
	var rock: Material = arena._stone(Color(0.38, 0.23, 0.13), 0.98, 0.08, 0.35)
	var edge: Material = arena._stone(Color(0.24, 0.15, 0.09), 0.94, 0.1, 0.4)
	var spire := CylinderMesh.new()
	spire.top_radius = 0.35
	spire.bottom_radius = 1.0
	spire.height = 1.0
	spire.radial_segments = 7
	spire.rings = 3
	for i in 40:
		var angle := TAU * i / 40.0 + rng.randf_range(-0.05, 0.05)
		var radius := rng.randf_range(110, 200)
		var h := rng.randf_range(18, 58)
		var w := rng.randf_range(7, 15)
		arena._static(spire, rock, Vector3(cos(angle) * radius, h * .5 - 2, sin(angle) * radius), Vector3(w, h, w * .8), Vector3(0, angle, rng.randf_range(-.12, .12)))
	for i in 3:
		var ring := TorusMesh.new()
		ring.inner_radius = 76.0 + i * 9.0
		ring.outer_radius = ring.inner_radius + 2.8
		ring.rings = 96
		ring.ring_segments = 8
		arena._mi(ring, edge, Vector3(0, 0.1 + i * 0.6, 0))
	var block := BoxMesh.new()
	for x in [-14.0, 14.0]:
		arena._static(block, rock, Vector3(x, 13, -101), Vector3(5, 26, 6), Vector3.ZERO)
	arena._static(block, edge, Vector3(0, 27, -101), Vector3(36, 4, 8), Vector3.ZERO)
	for i in 12:
		var angle := TAU * i / 12.0
		arena._static(block, edge, Vector3(cos(angle) * 67, 1.4, sin(angle) * 67), Vector3(4, 2.8, 4), Vector3(0, -angle, 0))

static func _harbor(arena: Node3D) -> void:
	var wood: Material = arena._stone(Color(0.12, 0.085, 0.06), 0.9, 0.02, 0.8)
	var rock: Material = arena._stone(Color(0.07, 0.12, 0.15), 0.95, 0.1, 0.4)
	var glow: Material = arena._glow_mat(Color(0.30, 0.75, 0.95), 1.1)
	var block := BoxMesh.new()
	for side in [-1.0, 1.0]:
		# Мостки выходят от внешнего края площадки к маякам.
		arena._static(block, wood, Vector3(side * 73, -.3, 5), Vector3(29, 1.0, 8), Vector3.ZERO)
		for x in [63, 73, 83]:
			for z in [0, 10]:
				arena._static(block, wood, Vector3(side * x, 1.0, z), Vector3(1.2, 5, 1.2), Vector3.ZERO)
	for i in 10:
		var angle := TAU * i / 10.0
		var p := Vector3(cos(angle) * 73, 0, sin(angle) * 73)
		arena._static(block, wood, p + Vector3(0, 2.5, 0), Vector3(1.3, 5, 1.3), Vector3.ZERO)
		arena._static(block, glow, p + Vector3(0, 5.2, 0), Vector3(2.0, 1.7, 2.0), Vector3.ZERO)
		arena._static(block, wood, p + Vector3(0, 6.2, 0), Vector3(2.6, .35, 2.6), Vector3.ZERO)
	var island := CylinderMesh.new()
	island.top_radius = .75
	island.bottom_radius = 1.0
	island.height = 1.0
	island.radial_segments = 9
	for i in 9:
		var angle := TAU * (i + .3) / 9.0
		var p := Vector3(cos(angle) * 190, 3, sin(angle) * 190)
		arena._static(island, rock, p, Vector3(23 + i % 3 * 8, 12, 23), Vector3.ZERO)
		if i % 2 == 0:
			arena._static(block, wood, p + Vector3(0, 13, 0), Vector3(5, 20, 5), Vector3.ZERO)
			arena._static(block, glow, p + Vector3(0, 24, 0), Vector3(5.5, 2, 5.5), Vector3.ZERO)
	var moon := SphereMesh.new()
	moon.radius = 11
	moon.height = 22
	moon.radial_segments = 32
	moon.rings = 16
	arena._mi(moon, arena._glow_mat(Color(0.65, 0.82, 1.0), .8), Vector3(-115, 120, -220))

