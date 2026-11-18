uniform vec2 bomber_zip_ends;
varying vec3 bomber_rest;

float bomber_welt(vec2 p, vec2 start, vec2 end, float radius) {
	vec2 axis = end - start;
	float t = clamp(dot(p - start, axis) / dot(axis, axis), 0.0, 1.0);
	float distance_to_welt = length(p - (start + t * axis));
	float width = max(fwidth(distance_to_welt) * 0.5, 0.0001);
	return 1.0 - smoothstep(radius - width, radius + width, distance_to_welt);
}

float bomber_trim_tone() {
	vec2 p = vec2(abs(bomber_rest.x), bomber_rest.y);
	float zip = bomber_welt(p, vec2(0.0, bomber_zip_ends.x), vec2(0.0, bomber_zip_ends.y), 0.0037);
	float pockets = bomber_welt(p, vec2(0.055, 0.135), vec2(0.105, 0.080), 0.0045);
	float front = smoothstep(0.025, 0.065, bomber_rest.z);
	return 1.0 - front * max(0.68 * zip, 0.57 * pockets);
}
