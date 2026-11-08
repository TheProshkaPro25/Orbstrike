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
static var _shader: Shader
static var _rim_shader: Shader
const RIM_META := &"creature_cloth_rim"
const GPU_PARAMETERS := ["gpu_driven", "positions_tex", "normals_tex", "welded_index_tex", "tex_width", "render_tex_width", "skel_to_mesh_transform", "render_offset"]

## A next_pass is a separate draw: it must read the same simulated cape as
## the base material. Only the shader is shared; uniforms belong to this cape.
static func rim_for_surface(source: Material, rim: Material) -> Material:
 if not source is ShaderMaterial or not rim is ShaderMaterial: return rim
 var cloth := source as ShaderMaterial
 if cloth.get_shader_parameter("gpu_driven") != true: return rim
 if _rim_shader == null:
  _rim_shader = Shader.new()
  _rim_shader.code = (rim as ShaderMaterial).shader.code.replace("void fragment()", GPU_VERTEX + "\nvoid fragment()")
 var result: ShaderMaterial = cloth.get_meta(RIM_META) if cloth.has_meta(RIM_META) else null
 if result == null:
  result = ShaderMaterial.new()
  result.shader = _rim_shader
  cloth.set_meta(RIM_META, result)
 for parameter in GPU_PARAMETERS:
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
 for parameter in ["positions_tex", "normals_tex", "welded_index_tex"]:
  rim.set_shader_parameter(parameter, null)
 if source.next_pass == rim: source.next_pass = null
 source.remove_meta(RIM_META)
 return rim

static func attach(model: Node3D) -> Node3D:
 if RenderingServer.get_rendering_device() == null: return null
 var cape: MeshInstance3D
 var body: MeshInstance3D
 var skeleton: Skeleton3D
 var stack: Array[Node] = [model]
 while not stack.is_empty():
  var node: Node = stack.pop_back()
  stack.append_array(node.get_children())
  if node is Skeleton3D: skeleton = node
  if node is MeshInstance3D and node.skin != null:
   if String(node.name).begins_with('CapeGPU'): cape = node
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
 var solver_path := 'res://scenes/resident_cloth_solver.gd' if CreatureModels.resident_catalog else 'res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd'
 var solver = load(solver_path).new()
 solver.name = 'CapePhysics'
 solver.set_meta('preparation_source', model.get_meta('preparation_source', null))
 # Paths are relative to the future solver child of the model root.
 solver.target_mesh = NodePath('../' + String(model.get_path_to(cape)))
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
 if solver._surf_mat != null: cape.set_meta('cloth_material', solver._surf_mat)
 return solver

static func update_floor(solver, actor: Node3D) -> void:
 var origin: Vector3 = actor._base
 if actor.get_parent() is Node3D: origin = actor.get_parent().to_global(origin)
 var scale: float = solver._ref_node.global_transform.basis.get_scale().x
 solver.get_node('Ground').global_transform = Transform3D(Basis.IDENTITY, origin - Vector3.UP * 2.0 * scale)
