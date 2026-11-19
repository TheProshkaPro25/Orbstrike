extends "res://tools/avatars/prepare_vrm_parts.gd"
## godot --headless --max-fps 60 -s res://tools/avatars/pack_fitted_hair.gd -- <fitted-glb-dir> <res-output-dir>
## Inputs use metres, +Y up, +Z forward and the destination Head origin.
const Catalog := preload("res://data/hair_catalog.gd")
const PROJECT_TEXTURE := preload("res://assets/avatars/itch/modular_bob_hairbobdifuse.png")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("Usage: pack_fitted_hair.gd -- <fitted-glb-dir> <res-output-dir>")
		quit(1)
		return
	var output := {}
	for id in Catalog.ADDITIONS:
		var stem: String = Catalog.ADDITIONS[id][1]
		var first := args[0].path_join(stem + "_0.glb")
		var second := args[0].path_join(stem + "_1.glb")
		if not FileAccess.file_exists(first) and not FileAccess.file_exists(second): continue
		for path in [first, second]:
			var mesh := pack_hair(path, id == Catalog.ANIME_GIRL)
			if mesh == null:
				printerr("Could not pack fitted hair: ", path)
				quit(1)
				return
			output[args[1].path_join(path.get_file().get_basename() + ".res")] = mesh
	var directory := ProjectSettings.globalize_path(args[1])
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(directory) != OK:
		printerr("No fitted hair pairs found or could not create output directory: ", directory)
		quit(1)
		return
	for path in output:
		var mesh: ArrayMesh = output[path]
		var error := ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			printerr("Could not save ", path, ": ", error_string(error))
			quit(1)
			return
		print(path, " surfaces=", mesh.get_surface_count(), " bounds=", mesh.get_aabb())
	quit()

func pack_hair(path: String, use_project_texture: bool) -> ArrayMesh:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	state.handle_binary_image = GLTFState.HANDLE_BINARY_EMBED_AS_UNCOMPRESSED
	if document.append_from_file(ProjectSettings.globalize_path(path), state) != OK: return null
	var scene := document.generate_scene(state)
	if scene == null: return null
	root.add_child(scene)
	var output := gather_hair(scene, use_project_texture)
	scene.free()
	return output

func gather_hair(scene: Node, use_project_texture: bool) -> ArrayMesh:
	var groups := {}
	var instances := scene.find_children("*", "MeshInstance3D", true, false)
	if scene is MeshInstance3D: instances.push_front(scene)
	for instance: MeshInstance3D in instances:
		var baked: Mesh = instance.mesh
		if instance.skin != null:
			var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
			if skeleton == null: return null
			skeleton.force_update_all_bone_transforms()
			baked = cpu_bake(instance, skeleton)
		for slot in baked.get_surface_count():
			var material := instance.mesh.surface_get_material(slot) as StandardMaterial3D
			if material == null or baked.surface_get_primitive_type(slot) != Mesh.PRIMITIVE_TRIANGLES: return null
			if not groups.has(material):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tool.set_material(toon_material(material, use_project_texture))
				groups[material] = tool
			var tool: SurfaceTool = groups[material]
			if use_project_texture:
				var arrays := baked.surface_get_arrays(slot)
				# The fitted Anime Girl GLB carries the project texture's UVs in its second set.
				if arrays[Mesh.ARRAY_TEX_UV2] != null:
					arrays[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV2]
					arrays[Mesh.ARRAY_TEX_UV2] = null
				var part := ArrayMesh.new()
				part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				tool.append_from(part, 0, instance.global_transform)
			else:
				tool.append_from(baked, slot, instance.global_transform)
	var output := ArrayMesh.new()
	var names := PackedStringArray()
	var materials := {}
	for source in groups:
		var tool: SurfaceTool = groups[source]
		tool.deindex()
		tool.index()
		tool.commit(output)
		var slot := output.get_surface_count() - 1
		var material := output.surface_get_material(slot) as ShaderMaterial
		names.append(material.resource_name)
		materials[slot] = material
		output.surface_set_material(slot, null)
	if materials.is_empty(): return null
	output.set_meta("part_source", -1)
	output.set_meta("surface_materials", names)
	output.set_meta("variant_materials", materials)
	return output

func toon_material(source: StandardMaterial3D, use_project_texture: bool) -> ShaderMaterial:
	var suffix := ""
	match source.transparency:
		BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
			suffix = "_cutout"
		BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
			suffix = "_trans_zwrite"
	if source.cull_mode == BaseMaterial3D.CULL_DISABLED: suffix += "_cull_off"
	var texture := PROJECT_TEXTURE if use_project_texture else source.albedo_texture
	var material := ShaderMaterial.new()
	material.resource_name = source.resource_name
	material.shader = VrmPaletteShaders.SHADERS["mtoon%s.gdshader" % suffix]
	material.set_shader_parameter("_MainTex", texture)
	material.set_shader_parameter("_ShadeTexture", texture)
	material.set_shader_parameter("_Color", source.albedo_color)
	material.set_shader_parameter("_ShadeColor", source.albedo_color * Color(0.72, 0.72, 0.72))
	material.set_shader_parameter("_Cutoff", source.alpha_scissor_threshold)
	material.set_shader_parameter("_BumpScale", 0.0)
	return material
