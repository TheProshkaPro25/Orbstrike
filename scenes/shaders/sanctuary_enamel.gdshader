shader_type spatial;

varying float gleam;
void vertex() {
	float phase = TIME * 0.82 - float(INSTANCE_ID) * 1.047198;
	gleam = smoothstep(0.1, 1.0, cos(phase));
}

void fragment() {
	ALBEDO = mix(COLOR.rgb, vec3(0.76, 0.69, 0.52), 0.12);
	EMISSION = ALBEDO * (0.22 + 0.76 * gleam);
	ROUGHNESS = 0.38;
}
