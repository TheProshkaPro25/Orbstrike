shader_type spatial;
render_mode cull_back, depth_draw_always, fog_disabled;

uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D wavelets : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float sea_level = -4.5;
uniform vec2 patch_half_extent = vec2(900.0);
// Per-channel extinction keeps sand/rocks visible under shallow clear water.
uniform vec3 extinction = vec3(0.115, 0.047, 0.028);
uniform vec4 deep_color : source_color = vec4(0.018, 0.105, 0.135, 1.0);
varying vec3 water_world;

vec3 view_position(vec2 uv, float depth, mat4 inverse_projection) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
#else
	// Forward+/Mobile reversed Z: leave sampled depth in [0,1].
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 p = inverse_projection * vec4(ndc, 1.0);
	return p.xyz / p.w;
}

vec3 noise_slope(vec2 uv) {
	float e = 0.00390625;
	float h = texture(wavelets, uv).r;
	float x = texture(wavelets, uv + vec2(e, 0.0)).r - texture(wavelets, uv - vec2(e, 0.0)).r;
	float z = texture(wavelets, uv + vec2(0.0, e)).r - texture(wavelets, uv - vec2(0.0, e)).r;
	return vec3(h, x, z);
}

void vertex() {
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Only broad low swells move the silhouette; small waves remain in the normal.
	// Meet the sparse outer ring at exactly y=0: interpolating different vertex
	// densities at a displaced shared edge otherwise opens tiny horizon cracks.
	vec2 patch_coordinate = abs(VERTEX.xz) / patch_half_extent;
	float swell_extent = 1.0 - smoothstep(0.65, 0.95, max(patch_coordinate.x, patch_coordinate.y));
	VERTEX.y += sin(dot(p.xz, vec2(0.124, 0.071)) - TIME * 0.66) * 0.12 * swell_extent;
	VERTEX.y += sin(dot(p.xz, vec2(-0.078, 0.19)) - TIME * 0.83) * 0.07 * swell_extent;
	water_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = water_world.xz;
	float distance_to_eye = length(CAMERA_POSITION_WORLD - water_world);
	float fine_fade = 1.0 - smoothstep(130.0, 550.0, distance_to_eye);
	vec2 drift = vec2(TIME * 0.0031, -TIME * 0.0022);
	vec3 n = noise_slope(p / 58.0 + drift);
	vec3 cross_n = noise_slope(vec2(-p.x * 0.67 + p.y * 0.41, p.x * 0.31 + p.y * 0.81) / 10.0 - drift * 1.3);
	float phase_a = dot(p, vec2(0.124, 0.071)) - TIME * 0.66 + (n.x - 0.5) * 1.8;
	float phase_b = dot(p, vec2(-0.078, 0.19)) - TIME * 0.83 + (n.x - 0.5) * 1.1;
	// Resolve the surface at the actual pixel footprint. Unfiltered analytic
	// slopes otherwise turn into moire rings when a flyby looks at the horizon.
	float resolved_swell = 1.0 - smoothstep(0.22, 0.95, max(fwidth(phase_a), fwidth(phase_b)));
	vec2 slope = vec2(0.124, 0.071) * cos(phase_a) * 0.065 * resolved_swell;
	slope += vec2(-0.078, 0.19) * cos(phase_b) * 0.04 * resolved_swell;
	slope += n.yz * 0.68;
	slope += vec2(-cross_n.y * 0.67 + cross_n.z * 0.31, cross_n.y * 0.41 + cross_n.z * 0.81) * 0.42 * fine_fade;
	slope *= 1.0 - smoothstep(420.0, 1500.0, distance_to_eye);
	vec3 world_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 view_normal = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	vec3 sight = normalize(CAMERA_POSITION_WORLD - water_world);
	float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(world_normal, sight), 0.0, 1.0), 5.0);

	float raw_depth = texture(scene_depth, SCREEN_UV).r;
	vec3 floor_view = view_position(SCREEN_UV, raw_depth, INV_PROJECTION_MATRIX);
	vec3 floor_world = (INV_VIEW_MATRIX * vec4(floor_view, 1.0)).xyz;
	float vertical_depth = max(0.0, water_world.y - floor_world.y);
	float path_length = min(length(floor_view - VERTEX), 160.0);
	// Refraction fades at intersections. Test the displaced depth in world space:
	// dry rocks, terrain silhouettes and foreground actors must never bleed into sea.
	vec2 offset = view_normal.xy * 0.024 * smoothstep(0.05, 2.5, vertical_depth);
	offset *= 1.0 - smoothstep(350.0, 1100.0, distance_to_eye);
	vec2 refracted_uv = SCREEN_UV + offset;
	vec2 inside = step(vec2(0.002), refracted_uv) * step(refracted_uv, vec2(0.998));
	float refracted_raw = texture(scene_depth, clamp(refracted_uv, vec2(0.002), vec2(0.998))).r;
	vec3 refracted_view = view_position(refracted_uv, refracted_raw, INV_PROJECTION_MATRIX);
	vec3 refracted_world = (INV_VIEW_MATRIX * vec4(refracted_view, 1.0)).xyz;
	float valid_refraction = inside.x * inside.y * smoothstep(0.03, 0.35, sea_level - refracted_world.y);
	valid_refraction *= step(-VERTEX.z + 0.02, -refracted_view.z);
	vec2 color_uv = mix(SCREEN_UV, refracted_uv, valid_refraction);
	path_length = mix(path_length, min(length(refracted_view - VERTEX), 160.0), valid_refraction);
	vec3 transmission = exp(-extinction * path_length);
	// Beyond the clear shelf unresolved suspended detail blends into the water
	// volume. A finite opaque seabed can never imprint its rectangular bounds.
	transmission *= 1.0 - smoothstep(6.0, 17.0, vertical_depth);
	vec3 bottom = textureLod(scene_color, color_uv, 0.0).rgb;
	vec3 transmitted = bottom * transmission + deep_color.rgb * (vec3(1.0) - transmission);

	// Sparse thin wash is keyed to the actual submerged shore, never a painted halo.
	float contact = (1.0 - smoothstep(0.10, 0.72, vertical_depth)) * smoothstep(0.015, 0.11, vertical_depth);
	float broken = smoothstep(0.49, 0.67, n.x + cross_n.x * 0.18);
	float runup = 0.5 + 0.5 * sin(vertical_depth * 8.0 - TIME * 1.12 + n.x * 6.0);
	float foam = contact * broken * smoothstep(0.35, 0.85, runup) * 0.34;
	// Real environment radiance + scene directional-light glints use this normal.
	// Emission carries the already-lit refracted seabed without lighting it twice.
	NORMAL = view_normal;
	ALBEDO = vec3(0.48, 0.56, 0.53) * foam;
	EMISSION = transmitted * (1.0 - fresnel) * (1.0 - foam);
	ROUGHNESS = 0.16 + (n.x * 0.055) + foam * 0.34 + (1.0 - fine_fade) * 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	// Maritime aerial perspective begins beyond the whole near-water landscape.
	// Unlike scene fog, this never recolors the refracted sand/rocks near the camera.
	float atmosphere = smoothstep(1000.0, 3000.0, distance_to_eye) * 0.96;
	EMISSION = mix(EMISSION, vec3(0.40, 0.59, 0.68), atmosphere);
	ALBEDO *= 1.0 - atmosphere;
	SPECULAR *= 1.0 - atmosphere;
	// Reading/writing alpha selects the transparent pass, after opaque scene copy.
	// Transmission is composited above; a second alpha blend would wash out clarity.
	ALPHA = 1.0;
}
