// REEBOO Stylized VFX - shared particle body.
// Included by vfx_add.gdshader (glowing, additive) and vfx_mix.gdshader (smoke, alpha blended).
// Color and alpha come from the particle's color ramp (vertex COLOR).
// Life progress comes from the particle system: INSTANCE_CUSTOM.y / INSTANCE_CUSTOM.w runs 0 -> 1.

uniform int shape : hint_enum("Soft Dot", "Flare", "Streak", "Ring", "Puff", "Star") = 0;
uniform int facing : hint_enum("Camera", "Velocity", "Mesh") = 0;
uniform float emission_energy : hint_range(0.0, 20.0) = 3.0;
uniform float softness : hint_range(0.01, 1.0) = 0.6;
uniform float ring_width : hint_range(0.01, 1.0) = 0.15;
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float noise_scale = 1.0;
uniform vec2 noise_scroll = vec2(0.0);
// Erosion eats the shape away over its life: 0 = never, 1 = fully gone at death.
uniform float erosion : hint_range(0.0, 1.0) = 0.0;
uniform float erosion_edge : hint_range(0.005, 0.5) = 0.06;
uniform vec4 edge_color : source_color = vec4(0.0);
// Fake top-down light on puffs (0 = flat).
uniform float puff_shading : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_scale : hint_range(0.0, 4.0) = 1.0;
// Fades the particle where it meets geometry, so it never shows hard intersection lines.
uniform float proximity_fade : hint_range(0.0, 4.0) = 0.25;
uniform sampler2D depth_texture : hint_depth_texture;

varying float v_age;
varying float v_seed;
varying float v_angle;

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y / max(INSTANCE_CUSTOM.w, 0.0001), 0.0, 1.0);
	v_seed = fract(sin(float(INSTANCE_ID) * 12.9898 + 78.233) * 43758.5453);
	v_angle = facing == 0 ? INSTANCE_CUSTOM.x : 0.0;
	if (facing == 0) {
		// Camera-facing billboard, rotated by the particle's angle, keeping particle scale.
		mat4 mat_world = mat4(
				normalize(INV_VIEW_MATRIX[0]),
				normalize(INV_VIEW_MATRIX[1]),
				normalize(INV_VIEW_MATRIX[2]),
				MODEL_MATRIX[3]);
		mat_world = mat_world * mat4(
				vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0),
				vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
				vec4(0.0, 0.0, 1.0, 0.0),
				vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
				vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
				vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
				vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0));
	} else if (facing == 1) {
		// Stretched along the particle's Y axis (enable "Align Y" on the process material),
		// turned to face the camera around that axis. Used for sparks and streaks.
		vec3 pos = MODEL_MATRIX[3].xyz;
		vec3 axis = MODEL_MATRIX[1].xyz;
		float axis_len = length(axis);
		axis = axis_len > 0.00001 ? axis / axis_len : vec3(0.0, 1.0, 0.0);
		vec3 to_cam = normalize(CAMERA_POSITION_WORLD - pos);
		vec3 side = cross(axis, to_cam);
		float side_len = length(side);
		side = side_len > 0.0001 ? side / side_len : normalize(INV_VIEW_MATRIX[0].xyz);
		vec3 fwd = cross(side, axis);
		float s = length(MODEL_MATRIX[0].xyz);
		mat4 mat_world = mat4(vec4(side * s, 0.0), vec4(axis * axis_len, 0.0), vec4(fwd * s, 0.0), vec4(pos, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float shape_mask(vec2 uv, float n) {
	vec2 p = uv * 2.0 - 1.0;
	float r = length(p);
	if (shape == 1) { // Flare: hot core with four thin rays.
		float core = exp(-r * r * 9.0);
		float rays = max(exp(-abs(p.x) * 28.0) * (1.0 - abs(p.y)), exp(-abs(p.y) * 28.0) * (1.0 - abs(p.x)));
		return clamp(core + rays * 0.9, 0.0, 1.0);
	} else if (shape == 2) { // Streak: thin, tapered at both ends.
		float across = clamp(1.0 - abs(p.x), 0.0, 1.0);
		float along = clamp(1.0 - abs(p.y), 0.0, 1.0);
		return pow(across, 2.5) * pow(along, 0.6);
	} else if (shape == 3) { // Ring.
		float d = abs(r - (1.0 - ring_width));
		return (1.0 - smoothstep(0.0, ring_width, d)) * step(r, 1.0);
	} else if (shape == 4) { // Puff: noisy blob for fire and smoke.
		float edge = r + (n - 0.5) * 0.45;
		return 1.0 - smoothstep(1.0 - softness, 1.0, edge + 0.15);
	} else if (shape == 5) { // Star: four-point twinkle.
		vec2 a = abs(p);
		float star = pow(a.x, 0.5) + pow(a.y, 0.5);
		float body = 1.0 - smoothstep(0.35, 1.0, star);
		return clamp(body + exp(-r * r * 14.0) * 0.6, 0.0, 1.0);
	}
	// Soft Dot.
	return smoothstep(0.0, softness, clamp(1.0 - r, 0.0, 1.0));
}

void fragment() {
	vec2 nuv = UV * noise_scale + noise_scroll * TIME + vec2(v_seed * 7.31, v_seed * 3.17);
	float n = texture(noise_texture, nuv).r;
	float m = shape_mask(UV, n);
	// Color ramps are authored in sRGB; convert to linear like StandardMaterial3D's "Vertex Color is sRGB".
	vec3 col = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));

	if (erosion > 0.0) {
		float threshold = v_age * erosion * 1.02;
		float value = m * (0.35 + 0.65 * n);
		float cut = smoothstep(threshold, threshold + erosion_edge, value);
		float band = cut * (1.0 - smoothstep(threshold + erosion_edge, threshold + erosion_edge * 3.0, value));
		col = mix(col, edge_color.rgb, band * edge_color.a);
		m = cut * mix(1.0, m, 0.35);
	}
	if (puff_shading > 0.0) {
		// Height on screen with the particle's spin undone, so the lit side always faces up.
		float up = -(UV.x - 0.5) * sin(v_angle) + (0.5 - UV.y) * cos(v_angle);
		float light = mix(0.65, 1.2, up + 0.5) * (0.85 + 0.3 * n);
		col *= mix(1.0, light, puff_shading);
	}

	ALBEDO = col * emission_energy;
	ALPHA = clamp(m * COLOR.a * alpha_scale, 0.0, 1.0);

	if (proximity_fade > 0.0) {
		float depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
		vec4 ndc = OUTPUT_IS_SRGB ? vec4(vec3(SCREEN_UV, depth_tex) * 2.0 - 1.0, 1.0) : vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
		vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
		view_pos.xyz /= view_pos.w;
		ALPHA *= clamp(1.0 - smoothstep(view_pos.z + proximity_fade, view_pos.z, VERTEX.z), 0.0, 1.0);
	}
}
