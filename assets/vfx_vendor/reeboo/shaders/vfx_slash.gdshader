// REEBOO Stylized VFX - sword slash arc.
// Made for the arc meshes in effects/meshes (UV.x runs along the arc, UV.y from inner to outer edge),
// drawn by a one-particle GPUParticles3D so the sweep follows that particle's life.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(1.0);
uniform float emission_energy : hint_range(0.0, 20.0) = 4.0;
// How much of the arc stays lit behind the head (in arc lengths).
uniform float trail_length : hint_range(0.05, 1.5) = 0.55;
// How far past the end of the arc the head travels before the slash is gone.
uniform float sweep_end : hint_range(1.0, 2.0) = 1.4;
// Below 1 = fast start and slow finish, which reads as a strong swing.
uniform float sweep_power : hint_range(0.2, 4.0) = 0.45;
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 noise_scale = vec2(3.0, 0.6);
uniform float noise_strength : hint_range(0.0, 1.0) = 0.55;

varying float v_age;

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y / max(INSTANCE_CUSTOM.w, 0.0001), 0.0, 1.0);
}

void fragment() {
	float head = pow(v_age, sweep_power) * sweep_end;
	float behind = head - UV.x;
	float trail = smoothstep(-0.02, 0.02, behind) * (1.0 - smoothstep(0.0, trail_length, behind));
	// The blade edge (outer rim) lasts longest; the inner body thins out down the trail.
	float inner = 1.0 - trail * 1.1;
	float body = smoothstep(inner, inner + 0.25, UV.y);
	float rim = 1.0 - smoothstep(0.9, 1.0, UV.y);
	float n = texture(noise_texture, vec2(UV.x * noise_scale.x - v_age * 2.0, UV.y * noise_scale.y)).r;
	float m = trail * body * rim * mix(1.0, n * 1.6, noise_strength);
	float hot = smoothstep(0.7, 0.97, UV.y) * trail;
	ALBEDO = mix(color.rgb, core_color.rgb, hot) * emission_energy;
	ALPHA = clamp(m * color.a * COLOR.a, 0.0, 1.0);
}
