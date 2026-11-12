shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, skip_vertex_transform;

uniform int style = 4;
uniform vec4 core_color : source_color;
uniform vec4 body_color : source_color;
uniform vec4 halo_color : source_color;
uniform bool show_detail = true;
uniform float trail_span = 0.0;
uniform float flow_time = 0.0;
uniform float pattern_scale = 1.0;
uniform vec3 sample_center;

void vertex() {
	// Physics can move the shell after the last uploaded sample. Pin the
	// head in the renderer while the older history stays in world space.
	float attach = 1.0 - smoothstep(0.0, 0.18, UV.x);
	vec3 world = VERTEX + mix(sample_center, MODEL_MATRIX[3].xyz, attach);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

float hash_1d(float value) {
	return fract(sin(value * 84.73 + 7.51) * 43758.54);
}

float noise_1d(float value) {
	float cell = floor(value);
	float weight = fract(value);
	return mix(hash_1d(cell), hash_1d(cell + 1.0), weight * weight * (3.0 - 2.0 * weight));
}

float angular_noise(float value) {
	return mix(hash_1d(floor(value)), hash_1d(floor(value) + 1.0), fract(value));
}

float line_mask(float y, float center, float width, float aa) {
	return 1.0 - smoothstep(max(width - aa, 0.0), width + aa, abs(y - center));
}

// The third channel is a soft veil. The first two are the sharp core and its colored edge.
vec3 stroke(float y, float center, float width, float aa) {
	float offset = (y - center) / (width * 2.6 + aa);
	return vec3(line_mask(y, center, width * 0.35, aa),
		line_mask(y, center, width, aa),
		exp2(-3.0 * (offset * offset)) * 0.48);
}

vec3 cosmos(float x, float y, float t, float aa) {
	float bend = 0.05 * sin(8.0 * x - t * 0.65);
	float hot = 1.0 - smoothstep(0.27, 0.59, x + 0.04 * sin(9.0 * x + t));
	vec3 strands = stroke(y, bend + 0.06, 0.105, aa);
	strands = max(strands, stroke(y, bend - 0.14, 0.063, aa) * 0.87);
	strands *= hot;
	float curl = 0.24 * sin(9.0 * x - t * 0.42) * smoothstep(0.25, 0.65, x);
	strands.z = max(strands.z, line_mask(y, curl - 0.18, mix(0.23, 0.37, x), aa + 0.20) * 0.81);
	return strands;
}

vec3 dark(float x, float y, float t, float aa) {
	float shard = noise_1d(9.0 * x - t * 0.65);
	float pulse = mix(1.0, smoothstep(0.26, 0.72, shard), smoothstep(0.06, 0.31, x));
	float bend = 0.076 * sin(12.0 * x - t * 0.78);
	vec3 strands = stroke(y, bend + 0.13 + x * 0.14, 0.128 * (0.22 + 0.78 * shard), aa) * pulse;
	float echo = (1.0 - smoothstep(0.29, 0.70, x)) * (0.33 + 0.67 * noise_1d(x * 10.0 - t + 14.0));
	strands = max(strands, stroke(y, -bend - 0.22, 0.072, aa) * echo);
	strands.z = max(strands.z, 0.63 * line_mask(y, bend - 0.02, 0.36, aa + 0.25) * (0.55 + 0.45 * shard));
	return strands;
}

vec3 earth(float x, float y, float t, float aa) {
	float fault = angular_noise(12.0 * x - t * 0.41);
	float ridge = 0.13 * fault + 0.06 * sin(9.0 * x);
	float chip = angular_noise(9.0 * x + 9.0 - t * 0.52);
	vec3 strands = stroke(y, ridge, 0.050 + 0.14 * smoothstep(0.43, 0.84, fault), aa);
	strands *= 0.37 + 0.63 * smoothstep(0.14, 0.54, fault);
	strands = max(strands, stroke(y, 0.40 + 0.12 * chip - x * 0.23, 0.135 * chip, aa)
		* smoothstep(0.40, 0.73, chip) * (1.0 - smoothstep(0.35, 0.77, x)));
	strands.z = max(strands.z, 0.47 * line_mask(y, -0.21 - x * 0.15, 0.11 + fault * 0.15, aa + 0.22));
	return strands;
}

vec3 electric(float x, float y, float t, float aa) {
	float zigzag = angular_noise(x * 31.0 - t * 2.1);
	float pulse = angular_noise(x * 12.0 - t * 1.12 + 26.0);
	float bend = (zigzag - 0.5) * 0.085 + 0.05 * x;
	float needle = (0.035 + 0.112 * pulse) * (1.0 - 0.79 * smoothstep(0.18, 0.78, x));
	vec3 strands = stroke(y, bend, needle, aa) * (0.48 + 0.52 * pulse);
	float fork = (1.0 - smoothstep(0.31, 0.72, x)) * (0.28 + 0.72 * smoothstep(0.24, 0.75, pulse));
	strands = max(strands, stroke(y, bend - 0.24 - 0.16 * pulse, 0.034 + 0.087 * pulse, aa) * fork);
	if (show_detail) {
		float flick = angular_noise(x * 16.0 - t * 1.26 + 8.0);
		strands = max(strands, stroke(y, bend + 0.29 + 0.10 * flick, 0.065 * flick, aa)
			* smoothstep(0.47, 0.84, flick) * (1.0 - x));
	}
	strands.z = max(strands.z, line_mask(y, 0.12 * sin(7.0 * x - t * 0.35), 0.12 + x * 0.22, aa + 0.18) * 0.55);
	return strands;
}

vec3 fire(float x, float y, float t, float aa) {
	float motion = x * 7.0 - t * 0.98;
	float flame = angular_noise(motion);
	float head = 1.0 - smoothstep(0.03, 0.20 + 0.04 * flame, x);
	float bend = (flame - 0.50) * 0.16 + 0.055 * sin(11.0 * x - t * 1.18);
	vec3 strands = stroke(y, bend, 0.025 + 0.17 * head, aa) * (0.39 + 0.61 * head);
	strands = max(strands, stroke(y, bend - 0.23 + 0.12 * x, 0.097 * head, aa) * head);
	// Stretch one-sided tongues down the trail instead of dotting it with sparks.
	float flick = angular_noise(motion * 1.27 + 6.3);
	float tongue = smoothstep(0.34, 0.82, flick) * smoothstep(0.07, 0.23, x);
	float lick_y = bend + 0.29 * (fract(motion + 0.44) - 0.43);
	strands = max(strands, stroke(y, lick_y, 0.15 * tongue, aa) * tongue);
	if (show_detail) {
		float ember = smoothstep(0.71, 0.97, flame) * smoothstep(0.23, 0.42, x);
		strands = max(strands, stroke(y, lick_y - 0.22 + 0.14 * x, 0.047, aa) * ember);
	}
	return strands;
}

vec3 ice(float x, float y, float t, float aa) {
	float ridge = 0.095 + 0.06 * sin(x * 4.8 - t * 0.25);
	vec3 strands = stroke(y, ridge, mix(0.113, 0.033, x), aa);
	strands = max(strands, stroke(y, ridge - 0.32, 0.042, aa) * 0.59 * (1.0 - smoothstep(0.04, 0.22, x)));
	strands.z = max(strands.z, line_mask(y, ridge - 0.13, 0.12, aa + 0.17) * 0.28);
	return strands;
}

vec3 nature(float x, float y, float t, float aa) {
	float bend = 0.045 * sin(8.0 * x - t * 0.58);
	float spacing = 0.115 + 0.18 * sin(x * 2.8);
	vec3 strands = stroke(y, bend, 0.076, aa);
	strands = max(strands, stroke(y, bend + spacing + 0.045, 0.039, aa) * 0.94);
	strands = max(strands, stroke(y, bend - spacing - 0.10, 0.044, aa)
		* (0.28 + 0.72 * noise_1d(5.0 * x - t * 0.48)));
	strands.z = max(strands.z, line_mask(y, bend, 0.19, aa + 0.17) * 0.50);
	return strands;
}

vec3 sound_trail(float x, float y, float t, float aa) {
	vec3 strands = vec3(0.0);
	for (int line = 0; line < 5; line++) {
		float lane = float(line);
		float center = (lane - 2.0) * mix(0.36, 0.31, x) + 0.045 * sin(x * 4.4 + lane);
		float tone = pow(0.5 + 0.5 * sin(20.0 * x - 2.1 * t + lane * 2.13), 12.0);
		float width = 0.027 + tone * (show_detail ? 0.051 : 0.031);
		strands = max(strands, stroke(y, center, width, aa) * (0.73 + tone * 0.27));
	}
	return strands;
}

vec3 void_trail(float x, float y, float t, float aa) {
	float swell = 0.36 * sin(7.3 * x - t * 0.60) * (1.0 - x * 0.83);
	float gap = 0.20 + 0.80 * smoothstep(0.28, 0.67, angular_noise(x * 9.5 - t * 0.72 + 32.0));
	vec3 strands = stroke(y, abs(swell) + 0.08, 0.11 * gap, aa) * gap;
	strands = max(strands, stroke(y, -swell * 0.15 - 0.17, 0.089 * gap, aa) * gap * 0.57);
	strands.z = max(strands.z, line_mask(y, 0.24 * swell, 0.37, aa + 0.21) * 0.66);
	return strands;
}

vec3 water(float x, float y, float t, float aa) {
	float surge = sin(9.4 * x - t * 0.84 + 0.44 * sin(4.5 * x));
	float crest = pow(0.5 + 0.5 * surge, 7.0);
	float bend = 0.29 * surge * smoothstep(0.11, 0.47, x);
	vec3 strands = stroke(y, bend, 0.035 + 0.11 * crest, aa) * (0.62 + 0.38 * crest);
	float ripple = sin(8.8 * x - t * 0.76 + 1.19);
	strands = max(strands, stroke(y, 0.26 + 0.15 * ripple, 0.047 + 0.034 * crest, aa)
		* (0.39 + 0.38 * noise_1d(7.0 * x - 0.49 * t)));
	strands.z = max(strands.z, line_mask(y, bend + 0.03, 0.14, aa + 0.16) * (0.33 + 0.18 * crest));
	return strands;
}

void fragment() {
	float x = UV.x;
	float y = UV.y * 2.0 - 1.0;
	float aa = clamp(fwidth(y) * 0.58, 0.01, 0.24);
	float t = flow_time * 5.0;
	float detail_x = x * pattern_scale / mix(1.0, pattern_scale, x);
	vec3 inks;
	if (style == 0) {
		inks = cosmos(x, y, t, aa);
	} else if (style == 1) {
		inks = dark(x, y, t, aa);
	} else if (style == 2) {
		inks = earth(detail_x, y, t, aa);
	} else if (style == 3) {
		inks = electric(x, y, t, aa);
	} else if (style == 4) {
		inks = fire(detail_x, y, t, aa);
	} else if (style == 5) {
		inks = ice(x, y, t, aa);
	} else if (style == 6) {
		inks = nature(x, y, t, aa);
	} else if (style == 7) {
		inks = sound_trail(x, y, t, aa);
	} else if (style == 8) {
		inks = void_trail(x, y, t, aa);
	} else {
		inks = water(x, y, t, aa);
	}
	float age_fade = 1.0 - smoothstep(0.32, 1.0, x);
	float veil_fade = 1.0 - smoothstep(0.48, 1.0, x);
	float tip = 1.0 - smoothstep(max(trail_span - 0.11, 0.0), max(trail_span, 0.001), x);
	tip *= step(0.001, trail_span);
	float rim = 1.0 - smoothstep(0.76, 1.0, abs(y));
	float heat = (1.0 - smoothstep(0.02, 0.54, x)) * clamp(inks.x * 1.35, 0.0, 1.0);
	if (style == 4 || style == 1 || style == 8) {
		heat *= 1.0 - smoothstep(0.05, 0.30, x);
	}
	vec3 body = mix(halo_color.rgb, body_color.rgb, 1.0 - smoothstep(0.39, 0.99, x));
	ALBEDO = mix(mix(halo_color.rgb, body, clamp(inks.y * 1.4, 0.0, 1.0)), core_color.rgb, heat);
	EMISSION = body * inks.y * (0.48 + 0.41 * heat) + core_color.rgb * heat * 0.62;
	ALPHA = max(inks.y * 0.94 * age_fade, inks.z * 0.74 * veil_fade) * tip * rim;
}
