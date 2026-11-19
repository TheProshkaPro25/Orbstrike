shader_type spatial;
render_mode unshaded;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	if (radius > 1.0) { discard; }
	float angle = atan(p.y, p.x + 0.00001);
	float ticks = smoothstep(0.78, 0.94, cos(12.0 * angle)) * smoothstep(0.75, 0.80, radius);
	float tide = 0.12 + sin(TIME * 0.28) * 0.24 + sin(p.x * 5.0 - TIME) * 0.05;
	vec3 enamel = mix(vec3(0.04, 0.115, 0.15), vec3(0.11, 0.35, 0.38), smoothstep(tide - 0.02, tide + 0.02, p.y));
	vec2 hand = vec2(sin(TIME * 0.12), -cos(TIME * 0.12));
	float hand_dist = length(p - hand * clamp(dot(p, hand), 0.0, 0.7));
	float brass = max(ticks, 1.0 - smoothstep(0.035, 0.065, hand_dist));
	brass = max(brass, 1.0 - smoothstep(0.08, 0.12, radius));
	ALBEDO = mix(enamel, vec3(0.86, 0.65, 0.34), brass);
}
