shader_type canvas_item;
render_mode unshaded;

uniform float flight_time = 0.0;

float lane_random(float seed) {
	return fract(sin(seed * 37.73 + 9.23) * 4375.31);
}

void fragment() {
	// All strokes travel away from the flight's vanishing point. Bound their
	// inner ends in screen space, including on ultrawide and narrow displays.
	vec2 origin = vec2(0.5, 0.41);
	vec2 delta = UV - origin;
	vec2 to_edge = mix(origin, vec2(1.0) - origin, step(vec2(0.0), delta));
	float radius = max(abs(delta.x) / to_edge.x, abs(delta.y) / to_edge.y);
	float opacity = 0.0;
	if (radius > 0.57) {
		vec2 pixel_ray = delta / SCREEN_PIXEL_SIZE;
		float angle = (atan(pixel_ray.y, pixel_ray.x) / TAU + 0.5) * 74.0;
		float lane = floor(angle);
		float clock = flight_time * mix(1.05, 1.95, lane_random(lane)) + lane_random(lane + 79.0);
		float cycle = floor(clock);
		float age = fract(clock);
		float track = mix(0.16, 0.84, lane_random(lane + cycle * 83.0));
		float side = abs(fract(angle) - track);
		float head = mix(0.68, 1.25, age * age);
		float span = mix(0.095, 0.23, lane_random(lane + 41.0)) * (0.60 + age);
		float along = (head - radius) / span;
		float taper = smoothstep(0.0, 0.28, along) * (1.0 - smoothstep(0.28, 1.0, along));
		float width = mix(0.025, 0.068, lane_random(lane + 193.0)) * taper;
		float stroke = (1.0 - smoothstep(width * 0.25, width + 0.015, side)) * taper;
		opacity = stroke * smoothstep(0.57, 0.83, radius) * smoothstep(0.0, 0.24, age);
	}
	COLOR *= vec4(0.83, 0.93, 0.98, opacity * 0.58);
}
