shader_type spatial;
render_mode specular_disabled, cull_disabled;
uniform vec4 albedo_color : source_color = vec4(.8,.6,.45,1.0);
uniform vec4 accent : source_color = vec4(.85,.65,.25,1.0);
uniform bool upper_lashes = false;
uniform int role = 0;
uniform sampler2D cutout_texture : hint_default_white, filter_linear_mipmap;
void fragment() {
 vec3 color = albedo_color.rgb;
 if (role == 2) {
  // Broad restrained brush-like streaks along each sculpted hair plane.
  float stripe = smoothstep(.30,.43,UV.x)*(1.0-smoothstep(.53,.68,UV.x));
  stripe *= smoothstep(.12,.28,UV.y)*(1.0-smoothstep(.53,.67,UV.y));
  color = mix(color,color*1.45+vec3(.025,.015,.01),stripe*.55);
 }
 if (role == 3) { ALPHA = texture(cutout_texture,UV).a; ALPHA_SCISSOR_THRESHOLD = .4; }
 ALBEDO = color;
 ROUGHNESS = 1.0;
 SPECULAR = 0.0;
 EMISSION = color * .16;
}
void light() {
 float angle = dot(NORMAL,LIGHT);
 float shade = role == 0 ? .76 : .57;
 float band = mix(shade,1.0,smoothstep(.15,.23,angle));
 DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * band / PI;
}
