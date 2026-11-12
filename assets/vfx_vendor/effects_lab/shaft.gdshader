shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Cheap fake light shaft for renderers without volumetric fog: an additive
// quad that fades towards its ends and its sides and flickers with noise.

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float intensity = 0.12;
uniform sampler2D noise_texture : repeat_enable, filter_linear;

void fragment() {
	float along = smoothstep(0.0, 0.3, UV.y) * (1.0 - smoothstep(0.6, 1.0, UV.y));
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float flicker = texture(noise_texture, vec2(UV.x * 0.5, UV.y * 0.2 - TIME * 0.03)).r;
	float fresnel = abs(dot(NORMAL, VIEW));
	ALBEDO = color.rgb * intensity * along * across * fresnel * (0.6 + 0.6 * flicker);
}
