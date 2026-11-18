shader_type spatial;
render_mode specular_disabled;

uniform float max_quality = 0.0;
uniform vec2 wave_origin;
uniform vec4 wave_color : source_color = vec4(.4, .8, 1.0, 1.0);
uniform float wave_radius = -20.0;
uniform float wave_strength = 0.0;
uniform vec4 limestone : source_color = vec4(.64, .59, .46, 1.0);
uniform vec4 deep_tile : source_color = vec4(.43, .45, .39, 1.0);
uniform vec4 ink : source_color = vec4(.14, .29, .36, 1.0);
uniform vec4 trim : source_color = vec4(.91, .77, .43, 1.0);
varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float line(float distance_to_line, float width) {
	return 1.0 - smoothstep(width, width + max(fwidth(distance_to_line), .02), abs(distance_to_line));
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 q = abs(p);
	// Keep the entire ordinary throw and rebound area above a drawing of a low seawall.
	float edge = max(max(q.x, q.y) - 140.0, q.x + q.y - 263.0);
	if (edge > 0.0) {
		discard;
	}
	float r = length(p);
	vec2 tile = p / vec2(16.5, 14.7);
	tile.x += mod(floor(tile.y), 2.0) * .5;
	vec2 joints = abs(fract(tile) - .5);
	float grout = line(max(joints.x, joints.y) - .5, .012);
	float tile_tint = hash(floor(tile));
	vec3 stone = mix(deep_tile.rgb, limestone.rgb, .62 + .26 * tile_tint);
	stone *= 1.0 - grout * .15;
	float wear = hash(floor(p * 2.3));
	stone *= .978 + wear * .044;
	// The broad approach and center are different ink tones on the same level.
	float parapet = max(max(q.x - 90.0, q.y - 76.0), q.x + q.y - 139.0);
	float outer = smoothstep(-1.0, .3, parapet);
	stone = mix(stone, mix(ink.rgb * 1.08, deep_tile.rgb, .29 + tile_tint * .21), outer);
	float paver = max(line(parapet + .1, .43), line(parapet + 2.2, .22));
	float approach = step(61.0, r) * (1.0 - step(75.0, q.y)) * (1.0 - step(13.6, q.x));
	stone = mix(stone, limestone.rgb * 1.07, approach * .45);
	float ring = max(line(r - 61.0, .20), line(r - 63.4, .40));
	float compass = line(r - 8.3 - 2.8 * cos(atan(p.y, p.x) * 8.0), .19);
	compass = max(compass, line(r - 12.5, .15));
	float boundary = max(line(edge + 5.0, .36), line(edge + 7.0, .22));
	float sector = line(fract((atan(p.y, p.x) + PI) * (18.0 / TAU)) - .5, .036);
	float ticks = sector * step(64.0, r) * step(r, 66.0);
	float tide = line(r - 68.5 - .65 * sin(atan(p.y, p.x) * 36.0), .16);
	stone = mix(stone, ink.rgb, clamp(tide + ring * .8, 0.0, 1.0) * .68);
	float outside_edge = smoothstep(-4.0, -2.0, edge);
	stone = mix(stone, ink.rgb, outside_edge * .78);
	stone = mix(stone, trim.rgb, clamp(ring + compass + boundary + .78 * paver + .8 * ticks, 0.0, 1.0) * .82);
	float wave = exp(-pow((length(p - wave_origin) - wave_radius) / 2.6, 2.0)) * wave_strength;
	ALBEDO = mix(stone, wave_color.rgb, wave * .48);
	EMISSION = stone * .16 + wave_color.rgb * wave * .64;
	ROUGHNESS = .95;
}
