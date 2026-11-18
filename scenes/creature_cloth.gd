class_name CreatureCloth
extends RefCounted
## Attach physics only to the explicitly separated Ratnik cape. Native skinning
## remains the fallback when the current renderer has no compute device.

const GPU_VERTEX := """
uniform bool gpu_driven = false;
uniform sampler2D positions_tex : filter_nearest;
uniform sampler2D normals_tex : filter_nearest;
uniform sampler2D welded_index_tex : filter_nearest;
uniform int tex_width = 4096;
uniform int render_tex_width = 4096;
uniform mat4 skel_to_mesh_transform;
uniform float render_offset = 0.0;
uniform vec4 flash_tint : source_color = vec4(0.0);
void vertex() {
 if (gpu_driven) {
  ivec2 r = ivec2(int(VERTEX_ID) % render_tex_width, int(VERTEX_ID) / render_tex_width);
  int index = int(texelFetch(welded_index_tex, r, 0).r);
  ivec2 p = ivec2(index % tex_width, index / tex_width);
  VERTEX = (skel_to_mesh_transform * vec4(texelFetch(positions_tex, p, 0).xyz, 1.0)).xyz;
  NORMAL = normalize(mat3(skel_to_mesh_transform) * texelFetch(normals_tex, p, 0).xyz);
  VERTEX += NORMAL * render_offset;
 }
}
"""
const GRID_VERTEX := """
uniform bool gpu_driven = false;
uniform sampler2D positions_tex : filter_nearest;
uniform ivec2 cloth_grid_size;
uniform mat4 skel_to_mesh_transform;
uniform vec4 flash_tint : source_color = vec4(0.0);
vec3 cloth_offset(ivec2 point) {
 return texelFetch(positions_tex, ivec2(point.y * cloth_grid_size.x + point.x, 0), 0).xyz;
}
void vertex() {
 if (gpu_driven) {
  vec2 uv = UV2 * vec2(cloth_grid_size - ivec2(1));
  ivec2 a = ivec2(floor(uv));
  ivec2 b = min(a + ivec2(1), cloth_grid_size - ivec2(1));
  vec2 weight = fract(uv);
  vec3 offset = mix(mix(cloth_offset(a), cloth_offset(ivec2(b.x, a.y)), weight.x),
                    mix(cloth_offset(ivec2(a.x, b.y)), cloth_offset(b), weight.x), weight.y);
  VERTEX += mat3(skel_to_mesh_transform) * offset;
 }
}
"""
const GRID_DATA := preload("res://assets/creatures_hd/ratnik_trellis/cape_grid.tres")
const GRID_PARAMETERS := ["gpu_driven", "positions_tex", "cloth_grid_size", "skel_to_mesh_transform"]
static var _shader: Shader
static var _rim_shader: Shader
static var _grid_shader: Shader
static var _grid_rim_shader: Shader
static var _grid_mesh: ArrayMesh
const RIM_META := &"creature_cloth_rim"
const GPU_PARAMETERS := ["gpu_driven", "positions_tex", "normals_tex", "welded_index_tex", "tex_width", "render_tex_width", "skel_to_mesh_transform", "render_offset"]

## A next_pass is a separate draw: it must read the same simulated cape as
## the base material. Only the shader is shared; uniforms belong to this cape.
static func rim_for_surface(source: Material, rim: Material) -> Material:
 if not source is ShaderMaterial or not rim is ShaderMaterial: return rim
 var cloth := source as ShaderMaterial
 if cloth.get_shader_parameter("gpu_driven") != true: return rim
 var grid := cloth.shader == _grid_shader
 if grid and _grid_rim_shader == null:
  _grid_rim_shader = Shader.new()
  _grid_rim_shader.code = (rim as ShaderMaterial).shader.code.replace("void fragment()", GRID_VERTEX + "\nvoid fragment()")
 if not grid and _rim_shader == null:
  _rim_shader = Shader.new()
  _rim_shader.code = (rim as ShaderMaterial).shader.code.replace("void fragment()", GPU_VERTEX + "\nvoid fragment()")
 var result: ShaderMaterial = cloth.get_meta(RIM_META) if cloth.has_meta(RIM_META) else null
 if result == null:
  result = ShaderMaterial.new()
  result.shader = _grid_rim_shader if grid else _rim_shader
  cloth.set_meta(RIM_META, result)
 for parameter in GRID_PARAMETERS if grid else GPU_PARAMETERS:
  result.set_shader_parameter(parameter, cloth.get_shader_parameter(parameter))
 for parameter in ["col", "strength"]:
  result.set_shader_parameter(parameter, (rim as ShaderMaterial).get_shader_parameter(parameter))
 return result

## Release path keeps materials alive until end of frame; stop the old pass
## advertising RD textures while the solver tears down its own wrappers.
static func clear_rim(source: Material) -> ShaderMaterial:
 if source == null or not source.has_meta(RIM_META): return null
 var rim: ShaderMaterial = source.get_meta(RIM_META)
 rim.set_shader_parameter("gpu_driven", false)
 var textures := ["positions_tex"] if (source as ShaderMaterial).shader == _grid_shader else ["positions_tex", "normals_tex", "welded_index_tex"]
 for parameter in textures:
  rim.set_shader_parameter(parameter, null)
 if source.next_pass == rim: source.next_pass = null
 source.remove_meta(RIM_META)
 return rim

static func attach(model: Node3D, position_only_grid: bool = true) -> Node3D:
 if RenderingServer.get_rendering_device() == null: return null
 var cape: MeshInstance3D
 var body: MeshInstance3D
 var skeleton: Skeleton3D
 var trellis := bool(model.get_meta("ratnik_trellis", false))
 var stack: Array[Node] = [model]
 while not stack.is_empty():
  var node: Node = stack.pop_back()
  stack.append_array(node.get_children())
  if node is Skeleton3D: skeleton = node
  if node is MeshInstance3D and node.skin != null:
   if String(node.name).begins_with('CapeGPU') or (trellis and node.name == &"RatnikCape"): cape = node
   else: body = node
 if cape == null or body == null or skeleton == null: return null
 var source := cape.get_active_material(0) as ShaderMaterial
 if source == null: return null
 if _shader == null:
  _shader = Shader.new()
  _shader.code = CreatureModels.ANIME_SHADER.replace('void fragment()', GPU_VERTEX + '\nvoid fragment()')
  _shader.code = _shader.code.replace('SPECULAR = 0.0;', 'SPECULAR = 0.0; EMISSION = flash_tint.rgb * flash_tint.a;')
 var material := ShaderMaterial.new()
 material.shader = _shader
 for parameter in ['tint', 'has_texture', 'shadow_palette', 'color_map']:
  material.set_shader_parameter(parameter, source.get_shader_parameter(parameter))
 var solver_path := 'res://scenes/resident_cloth_solver.gd' if CreatureModels.resident_catalog or trellis else 'res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd'
 var solver = load(solver_path).new()
 solver.name = 'CapePhysics'
 solver.set_meta('preparation_source', model.get_meta('preparation_source', null))
 # Paths are relative to the future solver child of the model root.
 var target_mesh := _make_proxy(cape, skeleton) if trellis else cape
 solver.target_mesh = NodePath('../' + String(model.get_path_to(target_mesh)))
 solver.skeleton = NodePath('../' + String(model.get_path_to(skeleton)))
 solver.body_mesh = NodePath('../' + String(model.get_path_to(body)))
 solver.cloth_material = material
 solver.weld_epsilon = 0.0000005
 solver.substeps = 3
 solver.solver_iterations = 3
 solver.stiffness = 0.92
 solver.bend_stiffness = 0.3
 solver.damping = 0.985
 solver.max_speed = 1.2
 solver.max_travel_distance = 0.10
 solver.gravity = Vector3(0, -2.5, 0)
 solver.wind = Vector3(0.10, 0, -0.16)
 solver.wind_turbulence = 0.25
 solver.flip_normals = false
 solver.body_collider_voxel_resolution = 10
 solver.body_collider_thickness = 0.004
 solver.collider_friction = 0.45
 solver.inertia_scale = Vector3(0.65, 0.35, 0.65)
 solver.rotational_inertia_scale = 0.5
 if trellis:
  solver.output_skin_delta = true
  # GRID_VERTEX and its rim variant sample positions only; the proxy is never
  # rendered. Ordinary CapeGPU and other delta consumers keep normal output.
  solver.output_positions_only = position_only_grid
  solver.substeps = 2
  solver.solver_iterations = 2
  solver.max_travel_distance = 0.055
  solver.wind = Vector3(0.24, 0, -0.38)
  solver.body_collider_voxel_resolution = 9
 var ground = load('res://addons/godot_gpu_cloth/src/gpu_cloth_collider.gd').new()
 ground.name = 'Ground'
 ground.shape = 2 # GPUClothCollider.Shape.BOX
 ground.extents = Vector3(2, 2, 2)
 ground.top_level = true
 solver.add_child(ground)
 var colliders: Array[NodePath] = [NodePath('Ground')]
 solver.collider_targets = colliders
 model.add_child(solver)
 update_floor(solver, model.get_parent())
 if solver._surf_mat == null: return solver
 if trellis:
  _apply_grid(cape, solver)
 else:
  cape.set_meta('cloth_materials', [solver._surf_mat])
 return solver


static func _make_proxy(cape: MeshInstance3D, skeleton: Skeleton3D) -> MeshInstance3D:
 if _grid_mesh == null:
  var size: Vector2i = GRID_DATA.get_meta("size")
  var points: PackedVector3Array = GRID_DATA.get_meta("points")
  var mobility: PackedFloat32Array = GRID_DATA.get_meta("mobility")
  var binds: PackedInt32Array = GRID_DATA.get_meta("binds")
  var bones := PackedInt32Array()
  var colors := PackedColorArray()
  for weight: float in mobility:
   bones.append_array(binds)
   colors.append(Color(weight, 0, 0))
  var indices := PackedInt32Array()
  for y in size.y - 1:
   for x in size.x - 1:
    var a := y * size.x + x
    var b := a + size.x
    indices.append_array([a, b, a + 1, a + 1, b, b + 1])
  var arrays := []
  arrays.resize(Mesh.ARRAY_MAX)
  arrays[Mesh.ARRAY_VERTEX] = points
  arrays[Mesh.ARRAY_COLOR] = colors
  arrays[Mesh.ARRAY_BONES] = bones
  arrays[Mesh.ARRAY_WEIGHTS] = GRID_DATA.get_meta("weights")
  arrays[Mesh.ARRAY_INDEX] = indices
  _grid_mesh = ArrayMesh.new()
  _grid_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
 var proxy := MeshInstance3D.new()
 proxy.name = &"CapeSimulationMesh"
 proxy.mesh = _grid_mesh
 proxy.skin = cape.skin
 proxy.transform = cape.transform
 proxy.layers = 0
 proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 cape.get_parent().add_child(proxy)
 proxy.skeleton = proxy.get_path_to(skeleton)
 return proxy


static func _apply_grid(cape: MeshInstance3D, solver: Node) -> void:
 var size: Vector2i = GRID_DATA.get_meta("size")
 assert(solver._particle_count == size.x * size.y and solver._tex_w == solver._particle_count)
 if _grid_shader == null:
  _grid_shader = Shader.new()
  _grid_shader.code = CreatureModels.ANIME_SHADER.replace('void fragment()', GRID_VERTEX + '\nvoid fragment()')
  _grid_shader.code = _grid_shader.code.replace('SPECULAR = 0.0;', 'SPECULAR = 0.0; EMISSION = flash_tint.rgb * flash_tint.a;')
 var materials: Array[ShaderMaterial] = []
 for i in cape.mesh.get_surface_count():
  var source := cape.get_active_material(i) as ShaderMaterial
  var material := ShaderMaterial.new()
  material.shader = _grid_shader
  for parameter in ['tint', 'has_texture', 'shadow_palette', 'color_map']:
   material.set_shader_parameter(parameter, source.get_shader_parameter(parameter))
  material.set_shader_parameter("positions_tex", solver._positions_tex)
  material.set_shader_parameter("cloth_grid_size", size)
  material.set_shader_parameter("skel_to_mesh_transform", solver._surf_mat.get_shader_parameter("skel_to_mesh_transform"))
  material.set_shader_parameter("gpu_driven", true)
  cape.set_surface_override_material(i, material)
  materials.append(material)
 cape.set_meta('cloth_materials', materials)
 cape.extra_cull_margin = 0.07
 solver.deformation_materials = materials


static func set_flash(mesh: MeshInstance3D, color: Color) -> bool:
 if not mesh.has_meta("cloth_materials"): return false
 for material: ShaderMaterial in mesh.get_meta("cloth_materials"):
  material.set_shader_parameter("flash_tint", color)
 return true

static func update_floor(solver, actor: Node3D) -> void:
 var origin: Vector3 = actor._base
 if actor.get_parent() is Node3D: origin = actor.get_parent().to_global(origin)
 var scale: float = solver._ref_node.global_transform.basis.get_scale().x
 solver.get_node('Ground').global_transform = Transform3D(Basis.IDENTITY, origin - Vector3.UP * 2.0 * scale)
