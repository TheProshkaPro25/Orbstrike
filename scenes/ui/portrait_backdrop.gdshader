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
	float vignette = 1.0 - smoothstep(0.38, 0.78, length(UV - vec2(0.5)));
	// A soft wash dissolves into the containing panel, with no square border,
	// hard ring or grid competing with the creature silhouette.
	vec2 edge = smoothstep(vec2(0.0), vec2(0.24), UV) * smoothstep(vec2(0.0), vec2(0.24), vec2(1.0) - UV);
	float opacity = edge.x * edge.y * halo * (0.56 + device_style * 0.04);
	COLOR = vec4(color * (0.72 + vignette * 0.28), opacity);
}
