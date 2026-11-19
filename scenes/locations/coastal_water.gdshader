shader_type spatial;
render_mode cull_back, depth_draw_always, fog_disabled;

uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D wavelets : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float sea_level = -4.5;
uniform float maritime_haze : hint_range(0.0, 0.1) = 0.045;
uniform bool local_reflections = false;
uniform vec2 patch_half_extent = vec2(900.0);
// Per-channel extinction keeps sand/rocks visible under shallow clear water.
uniform vec3 extinction = vec3(0.115, 0.047, 0.028);
uniform vec4 shelf_color : source_color = vec4(0.23, 0.50, 0.50, 1.0);
uniform vec4 offshore_color : source_color = vec4(0.16, 0.35, 0.46, 1.0);
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

vec2 projected_uv(vec3 point, mat4 projection) {
	vec4 clip = projection * vec4(point, 1.0);
	return clip.xy / clip.w * 0.5 + 0.5;
}

// Only opaque geometry on screen and above the waterline can replace sky
// radiance. Short rays resolve nearby island banks and hulls at grazing angles.
vec4 shore_reflection(vec3 origin, vec3 direction, mat4 projection, mat4 inverse_projection, mat4 inverse_view) {
	float last_travel = 0.0;
	for (int i = 1; i <= 10; i++) {
		float travel = float(i * i) * 1.28;
		vec3 probe = origin + direction * travel;
		if (probe.z >= -0.1) { break; }
		vec2 uv = projected_uv(probe, projection);
		if (any(lessThan(uv, vec2(0.002))) || any(greaterThan(uv, vec2(0.998)))) { break; }
		vec3 hit = view_position(uv, textureLod(scene_depth, uv, 0.0).r, inverse_projection);
		if (hit.z >= probe.z) {
			float lo = last_travel;
			float hi = travel;
			for (int j = 0; j < 3; j++) {
				float mid = (lo + hi) * 0.5;
				probe = origin + direction * mid;
				vec2 mid_uv = projected_uv(probe, projection);
				vec3 mid_hit = view_position(mid_uv, textureLod(scene_depth, mid_uv, 0.0).r, inverse_projection);
				if (mid_hit.z >= probe.z) {
					hi = mid;
					uv = mid_uv;
					hit = mid_hit;
				} else {
					lo = mid;
				}
			}
			float gap = hit.z - (origin.z + direction.z * hi);
			vec2 edges = min(uv, 1.0 - uv);
			float confidence = smoothstep(0.0, 0.045, min(edges.x, edges.y));
			confidence *= 1.0 - smoothstep(0.6, 3.5, gap);
			confidence *= smoothstep(0.01, 0.48, (inverse_view * vec4(hit, 1.0)).y - sea_level);
			confidence *= 1.0 - smoothstep(96.0, 128.0, hi);
			return vec4(textureLod(scene_color, uv, 0.0).rgb, confidence);
		}
		last_travel = travel;
	}
	return vec4(0.0);
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
	vec3 wind = noise_slope(p / 410.0 - drift * 0.16);
	float phase_a = dot(p, vec2(0.124, 0.071)) - TIME * 0.66 + (wind.x - 0.5) * 5.5;
	float phase_b = dot(p, vec2(-0.078, 0.19)) - TIME * 0.83 + (n.x - 0.5) * 1.7;
	// Resolve the surface at the actual pixel footprint. Unfiltered analytic
	// slopes otherwise turn into moire rings when a flyby looks at the horizon.
	float resolved_swell = 1.0 - smoothstep(0.22, 0.95, max(fwidth(phase_a), fwidth(phase_b)));
	vec2 slope = vec2(0.124, 0.071) * cos(phase_a) * 0.065 * resolved_swell;
	slope += vec2(-0.078, 0.19) * cos(phase_b) * 0.04 * resolved_swell;
	slope += wind.yz * 0.45;
	slope += n.yz * 0.46;
	slope += vec2(-cross_n.y * 0.67 + cross_n.z * 0.31, cross_n.y * 0.41 + cross_n.z * 0.81) * 0.35 * fine_fade;
	slope *= mix(0.60, 1.12, smoothstep(0.2, 0.8, wind.x));
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
	// The moving light pattern follows the submerged sand/rocks, so it stays
	// below the waves as the camera moves. Deep or distant floors receive none.
	vec2 bed = mix(floor_world.xz, refracted_world.xz, valid_refraction) * 3.7;
	vec2 bed_footprint = fwidth(bed);
	float footprint = max(bed_footprint.x, bed_footprint.y);
	float caustic_range = smoothstep(0.32, 0.90, vertical_depth) * (1.0 - smoothstep(1.5, 5.5, vertical_depth)) * fine_fade;
	caustic_range *= 1.0 - smoothstep(0.25, 0.95, footprint);
	if (caustic_range > 0.0) {
		vec2 warped = bed + vec2(sin(bed.y * 0.71 + TIME * 0.61), cos(bed.x * 0.63 - TIME * 0.37));
		warped += 2.6 * vec2(n.x, cross_n.x);
		float fold = abs(sin(warped.x + TIME * 0.23) + cos(warped.y - TIME * 0.38) * 0.81);
		float focus = 1.0 - smoothstep(0.035, 0.19 + footprint * 0.45, fold);
		bottom *= 1.0 + (focus - 0.14) * 0.21 * caustic_range * smoothstep(0.22, 0.72, n.x);
	}

	// Sparse thin wash is keyed to the actual submerged shore, never a painted halo.
	float contact = (1.0 - smoothstep(0.10, 0.72, vertical_depth)) * smoothstep(0.015, 0.11, vertical_depth);
	float broken = smoothstep(0.49, 0.67, n.x + cross_n.x * 0.18);
	float runup = 0.5 + 0.5 * sin(vertical_depth * 8.0 - TIME * 1.12 + n.x * 6.0);
	float foam = contact * broken * smoothstep(0.35, 0.85, runup) * 0.34;
	// The refracted seabed already contains its lighting. Suspended water and
	// foam receive the same ambient light, sun and shadows as the adjacent shore.
	float into_water = (1.0 - fresnel) * (1.0 - foam);
	NORMAL = view_normal;
	// Saturate before the edge of the opaque shelf. Both seabed meshes then
	// meet in the same offshore color even when their floor elevations differ.
	vec3 scattering = mix(shelf_color.rgb, offshore_color.rgb, smoothstep(3.0, 22.0, vertical_depth));
	ALBEDO = scattering * (vec3(1.0) - transmission) * into_water + vec3(0.48, 0.56, 0.53) * foam;
	EMISSION = bottom * transmission * into_water;
	ROUGHNESS = mix(0.115, 0.225, wind.x) + foam * 0.34 + (1.0 - fine_fade) * 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	if (local_reflections && distance_to_eye < 280.0 && fresnel > 0.044) {
		// A rough water pixel integrates many small facets. Trace its broad wave
		// direction; individual capillary normals would flicker across silhouettes.
		vec3 up_view = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		vec3 direction = reflect(-VIEW, normalize(mix(up_view, view_normal, 0.34)));
		vec4 reflected = shore_reflection(VERTEX + view_normal * 0.16, direction, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
		reflected.a *= 0.42 * (1.0 - smoothstep(200.0, 280.0, distance_to_eye)) * smoothstep(0.044, 0.10, fresnel);
		RADIANCE = reflected;
	}
	// The opaque bottom already carries scene fog. Add the light sea mist to
	// the water volume as its transmission falls, then meet the offshore haze.
	float water_volume = 1.0 - dot(transmission, vec3(0.2126, 0.7152, 0.0722));
	float sea_mist = maritime_haze * smoothstep(52.0, 360.0, distance_to_eye) * water_volume;
	float atmosphere = mix(sea_mist, 0.96, smoothstep(1000.0, 3000.0, distance_to_eye));
	EMISSION = mix(EMISSION, vec3(0.40, 0.59, 0.68), atmosphere);
	ALBEDO *= 1.0 - atmosphere;
	SPECULAR *= 1.0 - atmosphere;
	// Reading/writing alpha selects the transparent pass, after opaque scene copy.
	// Transmission is composited above; a second alpha blend would wash out clarity.
	ALPHA = 1.0;
}
