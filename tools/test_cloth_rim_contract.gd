extends SceneTree
## CPU/material assignment only. This does not compile or render the GPU shader.
var checks := 0
var failures := 0

func _initialize() -> void:
	preload("res://tools/test_window.gd").background(self)
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func cloth() -> ShaderMaterial:
	var result := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = CreatureModels.ANIME_SHADER.replace("void fragment()", CreatureCloth.GPU_VERTEX + "\nvoid fragment()")
	result.shader = shader
	result.set_shader_parameter("gpu_driven", true)
	for parameter in ["positions_tex", "normals_tex", "welded_index_tex"]:
		result.set_shader_parameter(parameter, ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBAF)))
	result.set_shader_parameter("tex_width", 32)
	result.set_shader_parameter("render_tex_width", 64)
	result.set_shader_parameter("skel_to_mesh_transform", Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)))
	result.set_shader_parameter("render_offset", 0.015)
	return result

func _run() -> void:
	var shader := Shader.new()
	shader.code = CreatureBall.RIM_SHADER
	var own := ShaderMaterial.new()
	own.shader = shader
	own.set_shader_parameter("col", CreatureBall.OWNER_GLOW[0])
	own.set_shader_parameter("strength", CreatureBall.RIM_STRENGTH[0])
	var enemy := ShaderMaterial.new()
	enemy.shader = shader
	enemy.set_shader_parameter("col", CreatureBall.OWNER_GLOW[1])
	enemy.set_shader_parameter("strength", CreatureBall.RIM_STRENGTH[1])
	var source := cloth()
	var other := cloth()
	var pass_a := CreatureCloth.rim_for_surface(source, own) as ShaderMaterial
	var pass_b := CreatureCloth.rim_for_surface(other, own) as ShaderMaterial
	check(pass_a != own and pass_a != pass_b, "per-cape uniforms never share actor/owner material")
	check(pass_a.shader == pass_b.shader, "resource-only shader shared")
	check(pass_a.shader.code.contains(CreatureCloth.GPU_VERTEX), "exact same simulated vertex and normal hook")
	for parameter in CreatureCloth.GPU_PARAMETERS:
		check(pass_a.get_shader_parameter(parameter) == source.get_shader_parameter(parameter), "same cloth parameter " + parameter)
	check(pass_a.get_shader_parameter("positions_tex") != pass_b.get_shader_parameter("positions_tex"), "other actor keeps different texture")
	check(CreatureCloth.rim_for_surface(source, enemy) == pass_a, "owner switch reuses this cape pass")
	check(pass_a.get_shader_parameter("col") == CreatureBall.OWNER_GLOW[1], "owner switch sets enemy color")
	check(pass_b.get_shader_parameter("col") == CreatureBall.OWNER_GLOW[0], "owner switch leaves other actor alone")
	check(own.get_shader_parameter("strength") == CreatureBall.RIM_STRENGTH[0], "shared native rim unchanged")
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.set_surface_override_material(0, source)
	root.add_child(mesh)
	CreatureBall._set_rim(mesh, own)
	check(source.next_pass == pass_a, "actual CreatureBall assigns cloth pass")
	var parked := Node3D.new()
	root.add_child(parked)
	mesh.reparent(parked)
	CreatureBall._set_rim(mesh, enemy)
	check(source.next_pass == pass_a and pass_a.get_shader_parameter("gpu_driven") == true, "pooled reparent retains actor pass and simulation")
	var native := StandardMaterial3D.new()
	check(CreatureCloth.rim_for_surface(native, own) == own, "native fallback uses native rim")
	source.set_shader_parameter("gpu_driven", false)
	CreatureBall._set_rim(mesh, own)
	check(source.next_pass == own, "disabled compute fallback returns native rim")
	source.set_shader_parameter("gpu_driven", true)
	CreatureBall._set_rim(mesh, enemy)
	check(source.next_pass == pass_a, "reenabled pooled surface restores own pass")
	ModelLifetime.release(mesh, self)
	check(not source.has_meta(CreatureCloth.RIM_META) and source.next_pass == null, "real model release detaches cached pass")
	check(pass_a.get_shader_parameter("gpu_driven") == false, "release disables retained pass")
	for parameter in ["positions_tex", "normals_tex", "welded_index_tex"]:
		check(pass_a.get_shader_parameter(parameter) == null, "release clears " + parameter)
	check(pass_b.get_shader_parameter("gpu_driven") == true, "release does not touch other actor")
	CreatureCloth.clear_rim(other)
	# No external strong pass reference: release must retain its MaterialRID
	# until the same end-of-frame boundary as the source surface material.
	var released_source := cloth()
	var retained_only_by_lifetime: WeakRef = weakref(CreatureCloth.rim_for_surface(released_source, own))
	var released_mesh := MeshInstance3D.new()
	released_mesh.mesh = BoxMesh.new()
	released_mesh.set_surface_override_material(0, released_source)
	root.add_child(released_mesh)
	CreatureBall._set_rim(released_mesh, own)
	ModelLifetime.release(released_mesh, self)
	check(retained_only_by_lifetime.get_ref() != null, "detached pass MaterialRID retained until end of frame without external strongref")
	parked.queue_free()
	await process_frame
	await process_frame
	check(retained_only_by_lifetime.get_ref() == null, "detached pass released after frame boundary")
	var report := {"scope": "headless material assignment/lifecycle only; GPU shader compilation and visual acceptance OPEN", "checks": checks, "failures": failures}
	var output := "res://docs/audits/2026-11-06-gpu-acceptance/rim-contract.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("Cloth rim contract: ", checks, "/", failures, "; GPU visual OPEN")
	quit(1 if failures else 0)
