shader_type canvas_item;
render_mode unshaded;
uniform vec4 element_color : source_color = vec4(0.2, 0.5, 0.8, 1.0);
uniform float device_style = 0.0;
void fragment() {
	vec2 p = UV - vec2(0.5, 0.43);
	float halo = exp(-dot(p * vec2(1.2, 1.0), p * vec2(1.2, 1.0)) * 6.0);
	vec3 ink = vec3(0.025, 0.033, 0.048);
	vec3 tint = element_color.rgb;
	vec3 color = mix(ink, tint * 0.36, 0.40 + halo * 0.48);
	float ring = 1.0 - smoothstep(0.002, 0.007, abs(length(p * vec2(1.0, 0.92)) - 0.42));
	float grid_x = 1.0 - smoothstep(0.001, 0.003, abs(fract(UV.x * 8.0) - 0.5));
	float grid_y = 1.0 - smoothstep(0.001, 0.003, abs(fract(UV.y * 8.0) - 0.5));
	color += tint * (ring * 0.065 + min(grid_x, grid_y) * 0.07 * device_style);
	float vignette = 1.0 - smoothstep(0.38, 0.78, length(UV - vec2(0.5)));
	COLOR = vec4(color * (0.72 + vignette * 0.28), 1.0);
}
