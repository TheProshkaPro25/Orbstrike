extends RefCounted
## Clear coastal sea. The opaque shore/seabed belongs to coastal_arena.gd;
## this surface refracts that real geometry, rather than painting a shallow band.
const WATER_SHADER := preload("res://scenes/locations/coastal_water.gdshader")
static var _wavelets: ImageTexture


static func build(parent: Node3D, sea_level: float = -4.5, extent: Vector2 = Vector2(1800.0, 1800.0)) -> ShaderMaterial:
	var root := Node3D.new()
	root.name = "ClearCoastalWater"
	parent.add_child(root)
	var surface := MeshInstance3D.new()
	surface.name = "RefractiveSea"
	var plane := PlaneMesh.new()
	plane.size = extent
	plane.subdivide_width = 192
	plane.subdivide_depth = 192
	surface.mesh = plane
	surface.position.y = sea_level
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.extra_cull_margin = 1.0
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.set_shader_parameter("wavelets", _wave_texture())
	material.set_shader_parameter("sea_level", sea_level)
	material.set_shader_parameter("patch_half_extent", extent * .5)
	surface.material_override = material
	root.add_child(surface)
	# The gameplay camera sees 3000 world units. Extend beyond its far plane so
	# a low flyby never reveals the straight edge of the detailed inner patch.
	var horizon := MeshInstance3D.new()
	horizon.name = "SeaToHorizon"
	horizon.mesh = _outer_sea(extent * .5, maxf(4200.0, maxf(extent.x, extent.y)))
	horizon.position.y = sea_level
	horizon.material_override = material
	horizon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	horizon.extra_cull_margin = 1.0
	root.add_child(horizon)
	root.set_meta("coastal_water", true)
	return material


static func _outer_sea(half_extent: Vector2, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect in [
		Vector4(-radius, -radius, radius, -half_extent.y),
		Vector4(-radius, half_extent.y, radius, radius),
		Vector4(-radius, -half_extent.y, -half_extent.x, half_extent.y),
		Vector4(half_extent.x, -half_extent.y, radius, half_extent.y),
	]:
		var points: Array[Vector3] = [Vector3(rect.x, 0, rect.y), Vector3(rect.z, 0, rect.y), Vector3(rect.z, 0, rect.w), Vector3(rect.x, 0, rect.w)]
		for index in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.add_vertex(points[index])
	return st.commit()


static func _wave_texture() -> ImageTexture:
	if _wavelets != null:
		return _wavelets
	var noise := FastNoiseLite.new()
	noise.seed = 48317
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = .055
	var image := noise.get_seamless_image(256, 256)
	image.generate_mipmaps()
	_wavelets = ImageTexture.create_from_image(image)
	return _wavelets
