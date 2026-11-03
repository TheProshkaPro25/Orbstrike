shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;
void vertex() { VERTEX += NORMAL * .0013; }
void fragment() { ALBEDO = vec3(.018,.023,.035); }
