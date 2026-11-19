shader_type spatial;
render_mode cull_disabled, unshaded;

void vertex() {
	float bird = float(INSTANCE_ID);
	float turn = TIME * 0.18 + bird * 0.035;
	float gliding = smoothstep(-0.45, 0.45, sin(TIME * 0.7 + bird));
	VERTEX.y += max(abs(VERTEX.x) - 0.45, 0.0) * sin(TIME * 4.7 + bird * 1.9) * 0.45 * gliding;
	// Face the tangent of the oval while the flock banks back into the strait.
	vec2 forward = normalize(vec2(-52.0 * sin(turn), 22.0 * cos(turn)));
	vec2 right = vec2(-forward.y, forward.x);
	VERTEX.y += VERTEX.x * 0.23;
	VERTEX.xz = right * VERTEX.x - forward * VERTEX.z + vec2(52.0 * cos(turn), 22.0 * sin(turn));
	VERTEX.y += 3.5 * sin(turn * 2.0 + bird * 0.11);
}

void fragment() {
	ALBEDO = COLOR.rgb;
}
