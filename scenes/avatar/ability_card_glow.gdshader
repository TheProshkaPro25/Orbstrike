shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 element_color : source_color = vec4(1.0);
uniform float strength = 0.0;
void fragment() {
	vec2 p = abs(UV-.5)*2.0;
	float halo = pow(max(0.0,1.0-length(p)),1.8);
	float ring = exp(-pow((length(p)-.58)*12.0,2.0))*.22;
	ALBEDO = element_color.rgb*1.6;
	ALPHA = (halo+ring)*strength*.65;
}
