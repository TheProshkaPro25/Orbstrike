// REEBOO Stylized VFX - glowing particles (fire, sparks, flashes, magic).
// Additive: overlapping particles get brighter and feed the WorldEnvironment glow.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "vfx_particle.gdshaderinc"
