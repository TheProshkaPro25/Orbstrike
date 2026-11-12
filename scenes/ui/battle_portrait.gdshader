shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

float minimum_channel(vec3 rgb) {
	return min(rgb.r, min(rgb.g, rgb.b));
}

float luminance(vec3 rgb) {
	return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

vec4 covered_texel(sampler2D art, vec2 uv, vec2 texel) {
	vec4 pixel = texture(art, uv);
	float low = minimum_channel(pixel.rgb);
	float chroma = max(pixel.r, max(pixel.g, pixel.b)) - low;
	float pale = smoothstep(0.40, 0.66, low) * (1.0 - smoothstep(0.24, 0.46, chroma));
	if (pixel.a > 0.0 && pale > 0.0) {
		// Recolour the source texels before scaling. Diagonal transparent
		// neighbours matter even when the light boundary texel is opaque.
		float w = texture(art, uv - vec2(texel.x, 0.0)).a;
		float e = texture(art, uv + vec2(texel.x, 0.0)).a;
		float n = texture(art, uv - vec2(0.0, texel.y)).a;
		float s = texture(art, uv + vec2(0.0, texel.y)).a;
		float nw = texture(art, uv - texel).a;
		float ne = texture(art, uv + vec2(texel.x, -texel.y)).a;
		float sw = texture(art, uv + vec2(-texel.x, texel.y)).a;
		float se = texture(art, uv + texel).a;
		float around = min(min(min(w, e), min(n, s)), min(min(nw, ne), min(sw, se)));
		float outer = 1.0 - smoothstep(0.20, 0.79, around);
		vec2 inward = vec2(e - w + 0.5 * (ne + se - nw - sw), s - n + 0.5 * (sw + se - nw - ne));
		float gradient = length(inward);
		float band = outer;
		float limit = 0.52;
		if (outer < 0.01) {
			// Feather into the next texel toward the opaque interior.
			vec2 reach = texel * 2.0;
			float along = min(texture(art, uv - vec2(reach.x, 0.0)).a, texture(art, uv + vec2(reach.x, 0.0)).a);
			along = min(along, min(texture(art, uv - vec2(0.0, reach.y)).a, texture(art, uv + vec2(0.0, reach.y)).a));
			band = 0.68 * (1.0 - smoothstep(0.13, 0.67, along));
			limit = 0.62;
		}
		if (band > 0.0) {
			vec3 colour = pixel.rgb * min(1.0, limit / max(low, 0.001));
			if (outer > 0.0 && gradient > 0.30) {
				vec4 inside = texture(art, uv + texel * inward / gradient * 1.75);
				float body_low = minimum_channel(inside.rgb);
				float borrow = smoothstep(0.80, 0.99, inside.a) * smoothstep(0.11, 0.30, low - body_low) * 0.66;
				vec3 body = inside.rgb * min(1.0, limit / max(body_low, 0.001));
				colour = mix(colour, body, borrow);
			}
			pixel.rgb = mix(pixel.rgb, colour, pale * band);
		}
	}
	return vec4(pixel.rgb * pixel.a, pixel.a);
}

vec4 matte_screen_edge(sampler2D art, vec2 uv, vec2 dx, vec2 dy, vec4 pixel) {
	// A single screen pixel covers several texels at HUD sizes. Inspect the
	// rendered footprint so a light texel deeper in the texture cannot rim it.
	float w = texture(art, uv - dx).a;
	float e = texture(art, uv + dx).a;
	float n = texture(art, uv - dy).a;
	float s = texture(art, uv + dy).a;
	vec2 diagonal = dx + dy;
	vec2 other = dx - dy;
	float nw = texture(art, uv - diagonal).a;
	float ne = texture(art, uv + other).a;
	float sw = texture(art, uv - other).a;
	float se = texture(art, uv + diagonal).a;
	float around = min(min(min(w, e), min(n, s)), min(min(nw, ne), min(sw, se)));
	float edge = 1.0 - smoothstep(0.12, 0.91, around);
	if (edge <= 0.0) {
		return pixel;
	}

	vec2 inward = vec2(e - w + 0.5 * (ne + se - nw - sw), s - n + 0.5 * (sw + se - nw - ne));
	float gradient = length(inward);
	float core = 0.0;
	float limit = 0.63;
	if (gradient > 0.25) {
		vec2 ray = (dx * inward.x + dy * inward.y) / gradient;
		vec4 inside = texture(art, uv + ray * 1.45);
		core = smoothstep(0.76, 0.98, inside.a);
		limit = mix(limit, min(0.57, luminance(inside.rgb) + 0.055), core);
	}
	// Cap brightness independently of hue, with lighter coverage on the rim.
	// Narrow blades and wisps can have no opaque interior along the normal.
	float intensity = luminance(pixel.rgb) / max(pixel.a, 0.001);
	float chroma_scale = min(1.0, limit / max(intensity, 0.001));
	pixel.rgb *= mix(1.0, chroma_scale, edge);
	return pixel * (1.0 - edge * 0.18 * core);
}

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec2 dx = dFdx(UV);
	vec2 dy = dFdy(UV);
	vec2 pixel = UV / texel - 0.5;
	vec2 first = (floor(pixel) + 0.5) * texel;
	vec2 weight = fract(pixel);

	// Weight colour by coverage to keep transparent paper-white RGB out
	// of the resized silhouette. Preserve the original shape and alpha.
	vec4 top = mix(covered_texel(TEXTURE, first, texel), covered_texel(TEXTURE, first + vec2(texel.x, 0.0), texel), weight.x);
	vec4 bottom = mix(covered_texel(TEXTURE, first + vec2(0.0, texel.y), texel), covered_texel(TEXTURE, first + texel, texel), weight.x);
	vec4 art = mix(top, bottom, weight.y);
	if (art.a > 0.0) {
		art = matte_screen_edge(TEXTURE, UV, dx, dy, art);
	}
	COLOR = vec4(art.rgb * item_color.rgb, art.a) * item_color.a;
}
