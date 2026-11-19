shader_type spatial;
render_mode cull_disabled;

void vertex() {
	float reach = clamp(VERTEX.x / 15.0 + 0.5, 0.0, 1.0);
	float notch = max(0.0, 1.0 - abs(VERTEX.y) / 3.0);
	VERTEX.x -= reach * reach * notch * 4.8;
	float phase = reach * 7.0 - TIME * 2.4 + MODEL_MATRIX[3].x * 0.13;
	VERTEX.z += reach * (1.5 * sin(phase) + 0.45 * sin(phase * 1.8));
	VERTEX.y -= reach * (0.8 + 0.32 * cos(phase));
	NORMAL = normalize(vec3(-reach * cos(phase) * 0.7, 0.0, 1.0));
}

void fragment() {
	float chevron = abs(abs(UV.y - 0.5) * 0.65 + UV.x - 0.54);
	float gold = 1.0 - smoothstep(0.032, 0.055, chevron);
	ALBEDO = mix(vec3(0.04, 0.21, 0.18), vec3(0.72, 0.42, 0.13), gold);
	ROUGHNESS = 0.92;
}
