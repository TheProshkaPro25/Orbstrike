shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec2 sun_uv = vec2(0.5);
uniform vec2 lens_extent = vec2(2.6, 1.0);
uniform float exposure_pulse = 0.0;
uniform float recovery = 0.0;

// Local lens response, centered on the projected sun. The horizontal flare
// is broad at the solar disk and tapers to a thin filament at either end.
void fragment() {
	vec2 p = (UV - sun_uv) * lens_extent;
	float radius2 = dot(p, p);
	float aureole = exp(-radius2 * 22.0);
	float core = exp(-radius2 * 155.0);
	float beam_width = 0.006 + 0.016 * core;
	float beam = exp(-abs(p.x) * 3.1 - abs(p.y) / beam_width);
	vec2 axis = vec2(0.89, -0.456);
	float diagonal = exp(-abs(dot(p, axis)) * 9.0 - abs(dot(p, vec2(-axis.y, axis.x))) * 96.0);
	// A faint coloured arc is strongest below the light, like scattered glass.
	float arc = exp(-abs(sqrt(radius2) - 0.285) * 61.0) * smoothstep(0.03, 0.26, p.y - p.x * 0.42);
	float margin = max(abs(p.x) / 1.3, abs(p.y) * 2.0);
	vec3 light = vec3(1.0, 0.73, 0.43) * (aureole * 0.24 + beam * 0.92 + diagonal * 0.27);
	light += vec3(0.54, 0.73, 0.77) * arc * 0.09;
	light *= 1.0 - smoothstep(0.78, 1.0, margin);
	// A single overexposure sweeps out from the projected disk into the surrounding sky.
	vec3 glare = vec3(0.76, 0.645, 0.455) * exp(-radius2 * 0.18);
	glare += vec3(0.94, 0.88, 0.79) * exp(-radius2 * 0.95);
	// As the lens recovers, the sharp rays disappear first. Their remaining
	// light spreads into a soft elliptical halo around the real solar disk.
	float direct = pow(max(1.0 - recovery / 0.55, 0.0), 2.0);
	float sharp = pow(max(1.0 - recovery / 0.37, 0.0), 2.0);
	float scattered = (1.0 - sharp) * exp(-2.0 * recovery) * (1.0 - smoothstep(0.65, 1.0, recovery));
	vec2 halo_p = p * vec2(0.84, 1.08);
	float halo_r2 = dot(halo_p, halo_p);
	float falloff = mix(4.3, 2.0, smoothstep(0.0, 0.72, recovery));
	float halo = 0.58 * exp(-halo_r2 * falloff) + 0.24 * exp(-halo_r2);
	vec3 afterglow = vec3(0.78, 0.66, 0.49) * halo * scattered;
	COLOR = vec4(light * sharp + glare * exposure_pulse * direct + afterglow, COLOR.a);
}
