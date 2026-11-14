shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform int element = 0;
instance uniform vec3 figure_size = vec3(4.0, 8.0, 5.0);
instance uniform float phase_offset = 0.0;
instance uniform bool impact = false;
instance uniform float progress = 0.0;
instance uniform float amplitude = 1.0;
instance uniform float contact_height = 1.2;
instance uniform vec3 surface_origin = vec3(0.0);
instance uniform vec3 surface_axis_x = vec3(0.0);
instance uniform vec3 surface_axis_z = vec3(0.0);
instance uniform vec2 surface_limits = vec2(0.0);
instance uniform float surface_step = 0.0;

uniform sampler2D impact_fire : source_color, filter_linear_mipmap;
uniform sampler2D impact_smoke : source_color, filter_linear_mipmap;
uniform sampler2D impact_glint : source_color, filter_linear_mipmap;
uniform sampler2D storm_spark : source_color, filter_linear_mipmap;
uniform sampler2D storm_flare : source_color, filter_linear_mipmap;
uniform sampler2D dust_texture : source_color, filter_linear_mipmap;
uniform sampler2D soft_noise : repeat_enable, filter_linear_mipmap;

varying flat int shape;
varying flat float detail_time;
varying flat float detail_seed;
varying flat float envelope;
varying vec3 rock_normal;
varying vec3 rock_surface;
varying vec2 runoff_position;

const int FIRE = 0;
const int EMBER = 1;
const int SMOKE = 2;
const int ARC = 3;
const int FLARE = 4;
const int WIND = 5;
const int STAR = 6;
const int RAY = 7;
const int ROCK = 8;
const int DUST = 9;
const int DARK = 10;
const int SPLASH = 11;
const int DROP = 12;
const int RUNOFF = 13;
const int RUNOFF_FLOOR = 14;

int attack_shape(float index) {
	int kind = int(index) % 4;
	if (impact && index == 1.0) {
		if (element == 0 || element == 4) { return SMOKE; }
		if (element == 1) { return FLARE; }
		if (element == 2) { return STAR; }
		if (element == 3) { return DUST; }
		return RUNOFF;
	}
	if (element == 0) {
		return index == 0.0 || index == 2.0 || (!impact && kind == 0) ? FIRE : (kind == 3 ? SMOKE : EMBER);
	} else if (element == 1) {
		if (impact) { return index < 4.0 ? ARC : (kind == 3 ? WIND : EMBER); }
		return kind == 3 ? WIND : (kind == 1 ? FLARE : ARC);
	} else if (element == 2) {
		return index == 0.0 || (!impact && (kind == 0 || kind == 3)) ? RAY : STAR;
	} else if (element == 3) {
		return kind == 3 || (impact && index == 0.0) ? DUST : ROCK;
	} else if (element == 4) {
		if (impact) { return index == 0.0 || index == 2.0 ? DARK : SMOKE; }
		return kind == 3 ? SMOKE : DARK;
	}
	if (impact && index == 4.0) { return RUNOFF_FLOOR; }
	return index == 0.0 ? SPLASH : DROP;
}

bool over_gate(vec2 point) {
	vec2 local = surface_origin.xz + surface_axis_x.xz * point.x + surface_axis_z.xz * point.y;
	return surface_limits.x > 0.0 && all(lessThanEqual(abs(local), surface_limits));
}

float fall_to_ground(float time, float floor_offset, float start_height, float lift, float gravity, float bounce) {
	float first_contact = (lift + sqrt(lift * lift + 2.0 * gravity * (start_height - floor_offset))) / gravity;
	float falling = start_height + time * (lift - gravity * time * 0.5);
	float after = max(time - first_contact, 0.0);
	// A single parabolic rebound ends as soon as the fragment reaches the surface again.
	float rebound = max(0.0, after * (bounce - gravity * after * 0.5));
	return time < first_contact ? falling : floor_offset + rebound;
}

float rock_support(float index, float seed, vec2 height_axis) {
	// Project the same seven corners as the pooled fragment mesh onto the floor normal.
	float tip_z = sin(seed * TAU) * 0.20;
	float bottom = min(dot(height_axis, vec2(0.54, tip_z)),
			dot(height_axis, vec2(-0.48, tip_z * -0.70)));
	for (int corner = 0; corner < 5; corner++) {
		float i = float(corner);
		float angle = i * TAU / 5.0 + seed * 3.0;
		float radius = 0.37 + 0.15 * sin(index * 5.69 + i * 4.89);
		bottom = min(bottom, dot(height_axis, vec2(0.21 * sin(i * 5.1 + seed * 7.0), sin(angle) * radius)));
	}
	return -bottom;
}

void vertex() {
	float index = UV2.x;
	float seed = fract(UV2.y + phase_offset);
	float angle = index * 2.399963 + phase_offset * 2.0;
	shape = attack_shape(index);
	float age;
	vec3 center;
	float tilt = 0.0;
	vec2 dimensions;
	if (impact) {
		// Eruption is initially tight at contact, then carries debris through the target.
		float delay = index <= 1.0 ? 0.0 : seed * 0.17;
		age = clamp((progress - delay) / (1.0 - delay), 0.0, 1.0);
		float spread = 1.0 - pow(1.0 - age, 2.3);
		float scatter = index < 2.0 ? 0.0 : mix(0.66, 1.43, seed);
		float carry = spread * mix(0.24, 0.86, seed);
		float rise = 0.42 + 1.03 * sin(age * PI) * mix(0.54, 1.18, seed);
		center = vec3(cos(angle) * scatter * spread, rise, sin(angle) * scatter * spread + carry);
		center.y += contact_height - 1.2;
		dimensions = vec2(0.39, 0.58) * mix(0.8, 1.22, seed);
		tilt = sin(angle) * 0.9;
		envelope = smoothstep(delay, delay + 0.075, progress) * (1.0 - smoothstep(0.44, 1.0, age));
		if (shape == RUNOFF || shape == RUNOFF_FLOOR) {
			age = progress;
			seed = phase_offset;
			float settle = smoothstep(0.31, 0.91, progress);
			center = vec3(0.0, 0.009 - (shape == RUNOFF_FLOOR ? surface_step : 0.0), -0.12 + settle * 0.72);
			dimensions = vec2(1.54, 2.24) * mix(0.36, 1.61, settle);
			envelope = smoothstep(0.29, 0.49, progress) * (1.0 - smoothstep(0.82, 1.0, progress));
		} else if (shape == FIRE) {
			float surge = smoothstep(0.015, 0.34, age);
			center = vec3(cos(angle) * surge * 0.23, contact_height + age * (index == 0.0 ? 0.19 : 0.49),
					mix(-0.52, 0.76, surge) + (index == 0.0 ? 0.0 : 0.36));
			dimensions = (index == 0.0 ? vec2(3.52, 1.33) : vec2(2.51, 0.79)) * mix(0.63, 1.09, surge);
			tilt = index == 0.0 ? 0.14 : 0.33;
			envelope = smoothstep(delay, delay + 0.064, progress) * (1.0 - smoothstep(0.24, 0.81, age));
		} else if (shape == ARC) {
			float lengthening = smoothstep(0.0, 0.16, age);
			center = vec3(index == 0.0 ? 0.0 : cos(angle) * 0.32, contact_height + (index == 0.0 ? 0.0 : 0.40 * sin(angle)),
					index == 0.0 ? -0.42 : mix(-0.21, 0.64, seed));
			dimensions = (index == 0.0 ? vec2(3.08, 0.94) : vec2(1.47, 0.52)) * mix(0.72, 1.12, lengthening);
			tilt = index == 0.0 ? 0.06 : (index == 2.0 ? 0.49 : -0.52);
			envelope = smoothstep(delay, delay + 0.037, progress) * (1.0 - smoothstep(0.15, index == 0.0 ? 0.59 : 0.43, age));
		} else if (shape == FLARE || shape == WIND) {
			center.y = contact_height + (shape == FLARE ? 0.0 : 0.18 * sin(angle));
			dimensions = shape == FLARE ? vec2(0.89) : vec2(1.41, 0.21);
			envelope *= shape == FLARE ? 1.0 - smoothstep(0.06, 0.30, age) : 0.40;
		} else if (shape == EMBER) {
			float fan = spread * (0.34 + 0.72 * seed);
			center = vec3(cos(angle) * fan, contact_height + age * (mix(0.65, 2.45, seed) - age * 2.32),
					-0.14 + spread * mix(0.83, 2.1, seed) + sin(angle) * fan * 0.25);
			dimensions = (element == 0 ? vec2(0.22, 0.072) : vec2(0.16, 0.047)) * mix(0.49, 1.18, seed);
			tilt = -0.21 + sin(angle) * 0.69;
			envelope *= element == 0 ? 0.87 : (1.0 - smoothstep(0.35, 0.76, age));
		} else if (shape == RAY) {
			float pulse = smoothstep(0.0, 0.20, age);
			center = vec3(0.0, contact_height + 0.05, mix(-0.83, -0.13, pulse));
			dimensions = vec2(mix(2.43, 3.63, pulse), mix(0.81, 0.30, pulse));
			tilt = 0.085;
			envelope = smoothstep(0.0, 0.047, progress) * (1.0 - smoothstep(0.19, 0.54, age));
		} else if (shape == STAR) {
			if (index == 1.0) {
				center = vec3(0.0, contact_height, -0.06);
				dimensions = vec2(mix(0.62, 1.34, spread), mix(0.65, 1.35, spread));
				envelope = smoothstep(delay, delay + 0.047, progress) * (1.0 - smoothstep(0.10, 0.42, age));
			} else {
				center.y = contact_height + sin(angle) * spread * 0.72;
				dimensions = vec2(0.22, 0.31) * mix(0.46, 1.24, seed);
				envelope *= 0.63;
			}
		} else if (shape == ROCK) {
			// A few large fragments leave first, with smaller gravel fanning out further.
			bool large = index == 2.0 || index == 4.0 || (index == 5.0 && seed > 0.38);
			float mass = large ? mix(0.56, 0.92, seed) : pow(seed, 2.45) * 0.23;
			float distance = (1.0 - pow(1.0 - age, 1.65)) * mix(1.86, 1.02, mass);
			center = vec3(cos(angle) * distance, 0.0, sin(angle) * distance * 0.53 + spread * (large ? 0.27 : 0.69));
			dimensions = vec2(mix(0.13, 0.68, mass)) * vec2(mix(0.88, 1.18, fract(seed * 7.1)), 1.0);
			float floor_offset = over_gate(center.xz) ? 0.0 : -surface_step;
			float initial = max(0.23, contact_height * mix(0.75, 0.91, seed));
			float rolling_age = min(age, 0.75);
			center.y = fall_to_ground(age, floor_offset, initial, mix(1.0, 2.05, seed), 21.0, large ? mix(1.67, 2.13, seed) : 0.44);
			tilt = angle + rolling_age * mix(6.8, 2.3, mass);
			envelope = smoothstep(delay, delay + 0.041, progress) * (1.0 - smoothstep(0.80, 1.0, age));
		} else if (shape == DUST) {
			// The surface throws dust sideways. It lingers once the chips drop.
			float side = index == 0.0 ? -0.31 : cos(angle);
			float settle = smoothstep(0.16, 0.98, progress);
			center = vec3(side * (0.16 + spread * 1.20), mix(0.36, 0.14, settle), spread * (0.32 + sin(angle) * 0.52));
			if (!over_gate(center.xz)) { center.y -= surface_step; }
			dimensions = vec2(1.18, mix(0.81, 0.42, settle)) * mix(0.52, 1.61, spread);
			tilt = sin(angle) * 0.18;
			envelope = smoothstep(delay + 0.13, delay + 0.31, progress) * (1.0 - smoothstep(0.43, 1.0, age));
		} else if (shape == DARK) {
			float pulse = smoothstep(0.015, 0.29, age);
			center = vec3(cos(angle) * 0.16 * spread, contact_height + (index == 0.0 ? 0.01 : -0.23),
					mix(-0.32, 0.52, pulse));
			dimensions = (index == 0.0 ? vec2(2.62, 1.59) : vec2(1.4, 0.78)) * mix(0.51, 1.14, pulse);
			tilt = index == 0.0 ? 0.21 : -0.33;
			envelope = smoothstep(delay, delay + 0.06, progress) * (1.0 - smoothstep(0.35, 0.92, age));
		} else if (shape == SMOKE) {
			// The trailing smoke rolls upward and erodes once the core passes.
			center = vec3(cos(angle) * spread * 0.52, contact_height + spread * mix(0.14, 0.91, seed),
					0.38 + spread * mix(0.10, 0.93, seed));
			dimensions = vec2(1.1, 0.83) * mix(0.58, 1.22, spread);
			envelope = smoothstep(delay + 0.08, delay + 0.28, progress) * (1.0 - smoothstep(0.42, 1.0, age));
		} else if (shape == SPLASH) {
			// The leading edge reaches the torso, then the sheet falls and flattens into runoff.
			float drop = smoothstep(0.08, 0.64, progress);
			center = vec3(0.02, mix(contact_height - 0.37, 0.23, drop), -0.88 + spread * 1.60);
			dimensions = vec2(2.23, 1.29) * vec2(mix(0.78, 1.15, spread), mix(1.0, 0.40, drop));
			envelope = smoothstep(0.0, 0.085, progress) * (1.0 - smoothstep(0.37, 0.68, progress));
		} else if (shape == DROP) {
			center = vec3(cos(angle) * scatter * spread, 0.0, spread * (0.38 + seed * 1.02) + sin(angle) * 0.43 * spread);
			float floor_offset = (over_gate(center.xz) ? 0.0 : -surface_step) + 0.055;
			float height = contact_height * 0.82 + age * (mix(0.64, 2.31, seed) - 5.7 * age);
			center.y = max(height, floor_offset);
			dimensions = vec2(0.22, 0.32) * mix(0.50, 1.40, seed);
			tilt = -0.91 + 0.21 * sin(angle);
			envelope *= smoothstep(floor_offset, floor_offset + 0.33, height) * (1.0 - smoothstep(0.36, 0.76, age));
		}
	} else {
		// Bind this beat to the actor's normalized time to strike, including authored attack clips.
		age = min(progress, 1.0);
		float pull = smoothstep(0.18, 0.94, age);
		float release = smoothstep(1.0, 1.36, progress);
		float drift = angle + age * 2.0;
		float height = figure_size.y;
		vec3 start = vec3(cos(drift) * figure_size.x * 0.56, height * mix(0.14, 0.52, seed), sin(drift) * figure_size.z * 0.52);
		vec3 focus = vec3(cos(angle) * height * 0.115, height * mix(0.28, 0.53, seed), figure_size.z * 0.47 + height * 0.17);
		center = mix(start, focus, pull) + vec3(0.0, -0.05, release * height * 0.21);
		dimensions = height * vec2(0.102, 0.15) * mix(0.63, 1.12, pull) * mix(0.70, 1.17, seed);
		tilt = sin(drift) * 0.72;
		envelope = smoothstep(0.07 + seed * 0.22, 0.36 + seed * 0.19, age) * (1.0 - release) * 0.83;
		if (shape == FIRE || shape == SMOKE || shape == DARK) {
			dimensions *= vec2(1.49, 1.58);
		}
		if (shape == ARC || shape == RAY) {
			dimensions *= vec2(0.94, 1.51);
			tilt += sin(angle * 2.0 + age * 3.2) * 0.8;
		}
		if (shape == WIND) {
			dimensions *= vec2(2.01, 0.89);
		}
		if (shape == SPLASH || shape == DROP) {
			center.y *= 0.74;
			dimensions *= shape == SPLASH ? vec2(2.95, 1.09) : vec2(0.58, 0.52);
		}
		if (shape == ROCK || shape == DUST) {
			center.y *= 0.62;
			tilt += age * sign(sin(angle)) * 2.4;
		}
	}
	vec2 p = VERTEX.xy * dimensions;
	vec2 rotated = mat2(vec2(cos(tilt), sin(tilt)), vec2(-sin(tilt), cos(tilt))) * p;
	bool volume = UV2.y >= 1.0;
	if (volume != (shape == ROCK)) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	} else if (shape == ROCK) {
		// Tumble a solid fragment around two axes. Face normals stay in world space.
		float yaw = angle + (impact ? min(age, 0.75) : age) * mix(4.2, 1.2, seed);
		mat2 spin_x = mat2(vec2(cos(tilt), sin(tilt)), vec2(-sin(tilt), cos(tilt)));
		mat2 spin_y = mat2(vec2(cos(yaw), sin(yaw)), vec2(-sin(yaw), cos(yaw)));
		vec3 scales = vec3(dimensions.x, dimensions.y, mix(dimensions.x, dimensions.y, 0.62));
		if (impact) {
			vec2 height_axis = vec2(spin_x[0].x, spin_x[1].x) * scales.yz;
			center.y += rock_support(index, fract(UV2.y), height_axis);
		}
		vec3 vertex = VERTEX * scales;
		vertex.yz = spin_x * vertex.yz;
		vertex.xz = spin_y * vertex.xz;
		vec3 normal = NORMAL;
		normal.yz = spin_x * normal.yz;
		normal.xz = spin_y * normal.xz;
		rock_normal = normalize(mat3(MODEL_MATRIX) * normal);
		rock_surface = VERTEX;
		POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(center + vertex, 1.0);
	} else if (shape == RUNOFF || shape == RUNOFF_FLOOR) {
		runoff_position = center.xz + p;
		POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(center + vec3(p.x, 0.0, p.y), 1.0);
	} else {
		if (shape == SPLASH) {
			// Keep the curl rising up and the lip facing the world-space direction of impact.
			float direction = MODELVIEW_MATRIX[2].x < 0.0 ? -1.0 : 1.0;
			vec2 forward = normalize(vec2(abs(MODELVIEW_MATRIX[2].x) + 0.15, MODELVIEW_MATRIX[2].y));
			rotated = mat2(forward, vec2(-forward.y, forward.x)) * vec2(p.x * direction, p.y);
		} else if (impact && (shape == FIRE || shape == ARC || shape == RAY || shape == DARK || shape == EMBER)) {
			float direction = MODELVIEW_MATRIX[2].x < 0.0 ? -1.0 : 1.0;
			vec2 forward = normalize(vec2(abs(MODELVIEW_MATRIX[2].x) + 0.15, MODELVIEW_MATRIX[2].y * direction));
			vec2 turn = vec2(cos(tilt), sin(tilt));
			rotated = mat2(forward, vec2(-forward.y, forward.x)) *
					(mat2(turn, vec2(-turn.y, turn.x)) * vec2(p.x * direction, p.y));
		}
		vec2 scale = vec2(length(MODELVIEW_MATRIX[0].xyz), length(MODELVIEW_MATRIX[1].xyz));
		vec3 anchor = (MODELVIEW_MATRIX * vec4(center, 1.0)).xyz;
		POSITION = PROJECTION_MATRIX * vec4(anchor + vec3(rotated * scale, 0.0), 1.0);
	}
	detail_time = age;
	detail_seed = seed;
}

float mask_tex(vec4 texel) {
	return texel.r * texel.a;
}

float stroke(float d, float width, float feather) {
	return 1.0 - smoothstep(width, width + feather, abs(d));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float y = 1.0 - UV.y;
	float age = detail_time;
	float seed = detail_seed;
	vec2 mirror = vec2(seed < 0.5 ? UV.x : 1.0 - UV.x, UV.y);
	float aa = clamp(length(fwidth(p)), 0.020, 0.11);
	float noise = texture(soft_noise, UV + vec2(seed * 4.1, -age * 0.61)).r;
	vec3 color = vec3(1.0);
	float opacity = 0.0;

	if (shape == FIRE) {
		// Separate hot interior and rolling outer flame, as in Elemental Impact.
		float travel = impact ? UV.x : y;
		float across = impact ? p.y : p.x;
		float bend = sin(travel * 8.4 - age * 10.2 + seed * 5.1) * 0.11;
		vec2 map = vec2(0.5 + across * 0.49 + bend, mix(0.94, 0.19, travel));
		float fire = mask_tex(texture(impact_fire, map));
		float turbulent = texture(soft_noise, map * vec2(2.4, 1.7) + vec2(age * 0.77, -age * 1.6)).r;
		float fill = fire * mix(0.63, 1.29, turbulent);
		float taper = stroke(across + bend, mix(0.51, 0.31, travel) + noise * 0.20, 0.20);
		float source = smoothstep(0.0, 0.14, travel) * (1.0 - smoothstep(0.69, 1.0, travel));
		float heat = smoothstep(0.37, 0.84, fill) * (1.0 - age * 0.37);
		float outer = smoothstep(0.07 + age * 0.33, 0.32 + age * 0.35, fill) * taper * source;
		color = mix(vec3(0.89, 0.074, 0.010), vec3(1.95, 0.88, 0.22), heat);
		opacity = outer;
	} else if (shape == EMBER || shape == FLARE || shape == ARC) {
		if (shape == ARC) {
			if (impact) {
				// A connected stepped channel with weaker streamers. Kenney's mask adds small irregular filaments.
				float pulse = floor(age * 22.0);
				float node = UV.x * 15.0;
				float a = fract(sin((floor(node) + seed * 31.7 + pulse * 9.1) * 58.73) * 43758.54);
				float b = fract(sin((ceil(node) + seed * 31.7 + pulse * 9.1) * 58.73) * 43758.54);
				float spine = mix(a, b, fract(node)) * 0.85 - 0.425;
				float gap = p.y - spine * sin(PI * UV.x);
				float taper = smoothstep(0.0, 0.11, UV.x) * (1.0 - smoothstep(0.89, 1.0, UV.x));
				float core = stroke(gap, 0.038, aa * 0.68);
				float glow = stroke(gap, 0.13, 0.55);
				float filament = mask_tex(texture(storm_spark, UV.yx));
				float branch = stroke(gap + (UV.x - 0.54) * (seed < 0.5 ? -1.20 : 1.46), 0.026, aa);
				branch *= smoothstep(0.54, 0.59, UV.x) * (1.0 - smoothstep(0.76, 0.91, UV.x));
				color = mix(vec3(0.032, 0.31, 0.89), vec3(0.77, 1.47, 2.05), core);
				opacity = taper * max(core, max(branch * 0.63, max(glow * 0.19, filament * 0.29)));
			} else {
				float bolt = mask_tex(texture(storm_spark, vec2((mirror.x - 0.5) * 0.83 + 0.5, mirror.y)));
				opacity = pow(bolt, 0.55) * stroke(p.y, 0.70, 0.30);
				color = mix(vec3(0.046, 0.48, 1.05), vec3(0.85, 1.42, 1.6), bolt);
			}
		} else if (shape == EMBER) {
			opacity = pow(mask_tex(texture(impact_glint, vec2(UV.x, UV.y * 0.86 + 0.07))), 0.60);
			color = element == 0 ? mix(vec3(1.92, 0.60, 0.093), vec3(0.97, 0.25, 0.047), age) : vec3(0.25, 0.79, 1.58);
		} else {
			opacity = pow(mask_tex(texture(storm_flare, UV)), 0.48);
			color = vec3(0.36, 1.19, 1.52);
		}
	} else if (shape == SMOKE || shape == DARK || shape == DUST) {
		vec2 curl = mirror + vec2(sin(y * 6.2 - seed * 3.9 - age * 4.6) * 0.14 * y, 0.0);
		float smoke = shape == SMOKE && element == 0 ? mask_tex(texture(impact_smoke, curl)) : texture(dust_texture, curl).a;
		float volume = smoke * mix(0.61, 1.04, noise);
		opacity = smoothstep(0.035, 0.55, volume) * 0.77;
		if (shape == DUST) {
			// Like the softer Elemental Impact layer, the thinning cloud dissolves on fine noise.
			float erosion = smoothstep(0.30, 1.0, age) * 0.22;
			opacity = smoothstep(0.045 + erosion, 0.51 + erosion, volume) * 0.79;
		}
		if (shape == DARK) {
			float drift = sin(p.x * 4.0 + noise * 3.2 - age * 4.1) * 0.20;
			float ragged = texture(soft_noise, UV * vec2(2.9, 2.4) + vec2(-age * 0.34, age * 0.29)).r;
			float edge_at = length(vec2(p.x * 1.03, p.y + drift)) + (ragged - 0.56) * 0.39;
			float body = 1.0 - smoothstep(0.33, 0.91, edge_at);
			float edge = stroke(edge_at - 0.57, 0.045, 0.19) * smoothstep(0.36, 0.85, ragged);
			color = mix(vec3(0.011, 0.006, 0.023), vec3(0.34, 0.12, 0.51), edge * 0.76);
			opacity = max(body * 0.95, edge * 0.77);
		} else if (element == 4) {
			color = mix(vec3(0.018, 0.010, 0.027), vec3(0.083, 0.041, 0.12), volume);
			opacity *= 0.52;
		} else {
			color = element == 0 ? vec3(0.35, 0.098, 0.040) : mix(vec3(0.22, 0.19, 0.17), vec3(0.49, 0.43, 0.34), y);
		}
	} else if (shape == ROCK) {
		float facets = 0.44 + 0.56 * max(0.0, dot(rock_normal, normalize(vec3(-0.51, 0.79, 0.34))));
		float vein = texture(soft_noise, rock_surface.xz * 1.06 + rock_surface.y * 0.61 + seed).r;
		vec3 mineral = mix(vec3(0.20, 0.16, 0.13), vec3(0.54, 0.45, 0.35), seed);
		color = mineral * facets * (0.78 + 0.31 * vein);
		opacity = 1.0;
	} else if (shape == RAY || shape == STAR) {
		if (shape == RAY) {
			// Effects Lab: the tapered envelope and moving noise break up a soft shaft.
			float lengthwise = impact ? UV.x : y;
			float distance = abs(impact ? p.y : p.x);
			float along = smoothstep(0.0, 0.24, lengthwise) * (1.0 - smoothstep(0.61, 1.0, lengthwise));
			float across = pow(1.0 - distance, mix(2.9, 7.4, lengthwise));
			float core = stroke(distance, 0.08, 0.13);
			opacity = along * max(core * 0.92, across * mix(0.62, 0.98, noise));
			color = mix(vec3(1.13, 0.55, 0.15), vec3(1.89, 1.52, 0.90), core);
		} else {
			// REEBOO pickup twinkle over a soft center.
			float star = 1.0 - smoothstep(0.25, 0.98, sqrt(abs(p.x)) + sqrt(abs(p.y)));
			float glow = exp(-dot(p, p) * 12.0);
			opacity = max(star, glow * 0.51);
			color = mix(vec3(1.3, 0.66, 0.16), vec3(1.72, 1.47, 0.93), star);
		}
	} else if (shape == WIND) {
		float wave = p.y + 0.52 - mix(0.72, 1.10, seed) * p.x * p.x + p.x * 0.18;
		float rim = stroke(wave - 0.23, 0.045, aa);
		float flow = stroke(wave - 0.03, 0.13, 0.37);
		opacity = max(rim * 0.93, flow * 0.61) * stroke(p.x, 0.52, 0.47);
		color = mix(vec3(0.23, 0.71, 0.63), vec3(0.49, 1.14, 1.08), rim);
	} else if (shape == SPLASH) {
		// Effects Lab water: independent coarse flow and fine noise break up the crest foam.
		float striation = texture(soft_noise, vec2(UV.x * 2.23 - age * 1.9, UV.y * 1.22 + age * 0.59) + seed).r;
		float turbulence = texture(soft_noise, vec2(UV.x * 4.8 - age * 2.1, UV.y * 2.7 + age * 0.84) - seed).r;
		float taper = smoothstep(-1.0, -0.32, p.x) * (1.0 - smoothstep(0.75, 0.99, p.x));
		float face = y - (0.45 + 0.35 * p.x + 0.31 * sin((p.x + 0.31) * 2.51) + (striation - 0.48) * 0.18);
		float body = (1.0 - smoothstep(0.00, 0.071, face)) * smoothstep(0.03, 0.35, y) * taper;
		float thickness = smoothstep(0.04, 0.30, -face) * (0.68 + striation * 0.32);
		float foam_edge = stroke(face + (turbulence - 0.48) * 0.11, 0.020, 0.084) * smoothstep(0.24, 0.74, striation);
		float streak = sin((p.x + 0.64 * p.y + striation * 0.23 - age * 0.83) * 25.0);
		float streaks = smoothstep(0.61, 0.96, streak) * smoothstep(0.34, 0.75, turbulence) * body;
		float foam_inside = smoothstep(0.53, 0.76, striation * turbulence) * body * (1.0 - thickness) + streaks * 0.32;
		float foam = clamp((foam_edge + foam_inside * 0.65) * taper, 0.0, 1.0) * (1.0 - smoothstep(0.27, 0.57, age));
		vec3 water = mix(vec3(0.025, 0.13, 0.21), vec3(0.12, 0.31, 0.40), striation);
		water += vec3(0.046, 0.103, 0.13) * streaks;
		color = mix(water, vec3(0.57, 0.70, 0.76), foam);
		opacity = max(body * mix(0.51, 0.91, thickness), foam * 0.86);
	} else if (shape == DROP) {
		float bead = stroke(length(vec2(p.x * (1.8 + y), p.y * 0.72 + p.x * 0.17)), 0.22, 0.29);
		float sparkle = stroke(length(vec2(p.x + 0.11, p.y - 0.31) * vec2(2.3, 1.26)), 0.08, 0.13);
		opacity = max(bead * 0.69, sparkle * 0.73);
		color = mix(vec3(0.19, 0.34, 0.43), vec3(0.53, 0.66, 0.73), sparkle);
	} else if (shape == RUNOFF || shape == RUNOFF_FLOOR) {
		// Projected water has separate height on and off the thin gate card. No stacked planes at the edge.
		bool card = over_gate(runoff_position);
		if ((shape == RUNOFF_FLOOR && (card || surface_step <= 0.0)) ||
				(shape == RUNOFF && surface_step > 0.0 && !card)) { discard; }
		float outline = length(vec2(p.x * 1.12, p.y * 0.89)) + (noise - 0.53) * 0.37;
		float flow = 1.0 - smoothstep(0.42, 0.90, outline);
		float flow_lines = sin(19.0 * (p.y + p.x * 0.21 - age * 0.45) + noise * 5.0);
		float edge = stroke(outline - 0.70, 0.02, 0.11) * smoothstep(0.43, 0.77, noise);
		float flecks = smoothstep(0.57, 0.81, noise) * smoothstep(0.02, 0.86, flow_lines) * flow;
		float sheen = max(flecks * 0.73, edge * 0.66) * (1.0 - smoothstep(0.66, 0.98, age));
		opacity = max(flow * 0.76, sheen * 0.84);
		color = mix(vec3(0.014, 0.043, 0.063), vec3(0.29, 0.44, 0.51), sheen);
	}

	ALBEDO = color;
	ALPHA = opacity * envelope * amplitude;
}
