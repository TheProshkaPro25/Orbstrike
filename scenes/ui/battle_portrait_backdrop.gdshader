shader_type canvas_item;
render_mode unshaded;

uniform vec4 element_color : source_color = vec4(0.28, 0.66, 0.80, 1.0);
uniform int element = 0;

#include "res://scenes/shaders/sigils.gdshaderinc"

void fragment() {
	vec3 tint = element_color.rgb;
	vec3 matte = mix(vec3(0.024, 0.038, 0.050), tint, 0.30 + 0.16 * (1.0 - UV.y));

	// Etched bands and the familiar element emblem stay behind the silhouette.
	float band = smoothstep(0.23, 0.26, UV.x + UV.y * 0.45);
	float trace = 1.0 - smoothstep(0.004, 0.013, abs(UV.x + UV.y * 0.45 - 0.29));
	matte += tint * (0.046 * band + 0.078 * trace);
	float aspect = abs(dFdy(UV.y)) / max(abs(dFdx(UV.x)), 0.0001);
	vec2 mark = (UV - vec2(0.18, 0.53)) * vec2(aspect, 1.0);
	float ring = 1.0 - smoothstep(0.005, 0.017, abs(length(mark) - 0.209));
	float sigil = sigil_mask(mark * 0.75, element);
	matte = mix(matte, mix(tint, vec3(0.82, 0.88, 0.90), 0.37), sigil * 0.38 + ring * 0.14);
	COLOR = vec4(matte, 1.0) * COLOR;
}
