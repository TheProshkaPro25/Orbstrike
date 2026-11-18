#[compute]
#version 450

// Position-only output for display grids. Keep the position operations identical
// to cloth_output.glsl; simulation and topology are unaffected.
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) restrict readonly buffer Positions { vec4 positions[]; };
layout(set = 0, binding = 5, rgba32f) uniform writeonly image2D positions_img;
layout(set = 0, binding = 7, std430) restrict readonly buffer SkinnedTargets { vec4 skinned_targets[]; };
layout(push_constant, std430) uniform Params {
    uint particle_count;
    uint tex_width;
    uint output_skin_delta;
    float pad;
};
void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= particle_count) return;
    ivec2 coord = ivec2(int(idx % tex_width), int(idx / tex_width));
    vec4 position = positions[idx];
    if (output_skin_delta != 0u) {
        position.xyz -= skinned_targets[idx].xyz;
    }
    imageStore(positions_img, coord, position);
}
