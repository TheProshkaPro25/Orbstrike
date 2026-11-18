shader_type canvas_item;
render_mode unshaded;

uniform sampler2D coast_atlas : source_color, repeat_disable, filter_linear_mipmap;
uniform sampler2D terrain_atlas : source_color, repeat_disable, filter_linear_mipmap;
uniform sampler2D map_atlas : repeat_disable, filter_linear;
uniform vec3 eye;
uniform vec3 forward;
uniform vec3 up;
uniform vec3 left;
uniform vec2 wind;
uniform vec4 zenith : source_color = vec4(.27, .65, .91, 1.0);
uniform vec4 horizon : source_color = vec4(.72, .88, .90, 1.0);
uniform vec4 offshore : source_color = vec4(.12, .46, .61, 1.0);
uniform vec4 foam : source_color = vec4(.86, .96, .90, 1.0);
uniform vec4 shaded_water : source_color = vec4(.10, .34, .49, 1.0);

const float MAP_SPAN = 3200.0;
const float WATER_LEVEL = -8.0;
const float LAND_HEIGHT = 70.2;

vec2 atlas_uv(vec2 p) {
	return p / MAP_SPAN + vec2(.5);
}

float hash(vec2 point) {
	vec3 p = fract(vec3(point.xyx) * .1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec2 p) {
	vec2 tile = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(tile), hash(tile + vec2(1.0, 0.0)), f.x),
		mix(hash(tile + vec2(0.0, 1.0)), hash(tile + vec2(1.0)), f.x), f.y);
}

float hill_height(vec2 world) {
	vec2 uv = atlas_uv(world);
	if (max(abs(uv.x - .5), abs(uv.y - .5)) >= .493) {
		return WATER_LEVEL;
	}
	// Bilinear continuous elevation, shared with the painted island field.
	vec4 field = texture(map_atlas, uv);
	return WATER_LEVEL + (field.r * (256.0 / 257.0) + field.a / 257.0) * LAND_HEIGHT;
}

vec3 water_color(vec2 p, float travel, vec3 ray) {
	vec2 uv = atlas_uv(p);
	vec3 data = texture(map_atlas, uv).rgb;
	float edge = smoothstep(.41, .49, max(abs(uv.x - .5), abs(uv.y - .5)));
	vec3 color = mix(texture(coast_atlas, uv).rgb, offshore.rgb, edge);
	float shadow = texture(map_atlas, atlas_uv(p - wind)).g;
	color = mix(color, shaded_water.rgb, shadow * .16 * (1.0 - edge));
	// Fine crossing ripples bend a sky reflection; long, blurred paint ribbons
	// have no place in the material. Filter detail before it becomes subpixel.
	vec2 screen_footprint = fwidth(p);
	float detail = 1.0 - smoothstep(1.2, 4.0, max(screen_footprint.x, screen_footprint.y));
	float fade = detail * (1.0 - smoothstep(400.0, 1250.0, travel));
	vec2 current = p * .19 + vec2(TIME * .065, TIME * -.09);
	vec3 normal = normalize(vec3((noise(current) - .5) * .07 * fade,
		1.0, (noise(current + vec2(27.3, 5.8)) - .5) * .09 * fade));
	vec3 reflected = reflect(ray, normal);
	float fresnel = pow(1.0 - max(dot(-ray, normal), 0.0), 3.0);
	vec3 sky_reflection = mix(horizon.rgb, zenith.rgb, smoothstep(0.0, .9, reflected.y));
	color = mix(color, sky_reflection, .10 + fresnel * .36);
	// Individual short wavelets leave large uninterrupted blue areas between.
	vec2 swell = p + vec2(TIME * .28, TIME * .65);
	vec2 cell = floor(swell / vec2(29.0, 19.0));
	float seed = hash(cell);
	vec2 local = mod(swell, vec2(29.0, 19.0)) - vec2(14.5, 9.5);
	local -= vec2((seed - .5) * 13.0, (hash(cell + vec2(41.0)) - .5) * 13.0);
	float crest_distance = abs(local.y + .12 * cos(local.x * .65) - sin(TIME * .7 + seed * 9.0) * .16);
	float width = max(fwidth(local.y), .08);
	float crest = (1.0 - smoothstep(.04, .12 + width, crest_distance))
		* (1.0 - smoothstep(2.5, 4.6, abs(local.x))) * step(.86, seed);
	color = mix(color, foam.rgb, crest * .28 * fade);
	float sheen = pow(max(dot(reflected, normalize(vec3(-.55, .65, -.43))), 0.0), 110.0);
	color += vec3(.035, .038, .029) * sheen * fade;
	// A narrow contact line and one broken advancing wave. The shelf carries
	// the turquoise colour; foam does not illuminate a broad halo around land.
	float shore = data.b * 18.0 - 9.0;
	float antialias = max(fwidth(shore), .025);
	float surf = 1.0 - smoothstep(.035, .065 + antialias, abs(shore + .06));
	float wash_distance = abs(shore + .60 + sin(TIME * .9) * .13);
	float wash = 1.0 - smoothstep(.015, .04 + antialias, wash_distance);
	float lace = smoothstep(.36, .63, noise(p * .32 + vec2(TIME * .07, 0.0)));
	color = mix(color, foam.rgb, (surf * .87 + wash * lace * .34) * (1.0 - edge));
	return mix(color, horizon.rgb, smoothstep(1600.0, 3600.0, travel));
}

vec3 land_color(vec3 p, float travel) {
	float epsilon = 12.0;
	vec3 normal = normalize(vec3(hill_height(p.xz - vec2(epsilon, 0.0)) - hill_height(p.xz + vec2(epsilon, 0.0)),
		2.0 * epsilon, hill_height(p.xz - vec2(0.0, epsilon)) - hill_height(p.xz + vec2(0.0, epsilon))));
	vec3 paint = texture(terrain_atlas, atlas_uv(p.xz)).rgb;
	float stone = (1.0 - smoothstep(.64, .90, normal.y)) * smoothstep(WATER_LEVEL + 5.0, WATER_LEVEL + 16.0, p.y);
	paint = mix(paint, vec3(.30, .35, .27), stone * .30);
	float light = max(dot(normal, normalize(vec3(-.55, .85, -.43))), 0.0);
	paint *= .67 + smoothstep(.42, .49, light) * .18 + smoothstep(.74, .80, light) * .17;
	float shade = texture(map_atlas, atlas_uv(p.xz - wind)).g;
	paint *= 1.0 - shade * .16;
	// Colour the beach by continuous elevation. A narrow stripe baked into
	// the top-down texture stretches into sawteeth on the steep coastal slope.
	float beach = 1.0 - smoothstep(WATER_LEVEL + 3.4, WATER_LEVEL + 6.3, p.y);
	paint = mix(paint, vec3(.76, .71, .48) * (.88 + light * .12), beach);
	return mix(paint, horizon.rgb, smoothstep(1250.0, 2850.0, travel) * .70);
}

void fragment() {
	vec3 ray = normalize(forward + up * (1.0 - UV.y * 2.0) + left * (1.0 - UV.x * 2.0));
	vec3 color = mix(horizon.rgb, zenith.rgb, smoothstep(-.03, .76, ray.y));
	float glare = max(dot(ray, normalize(vec3(-.55, .65, -.43))), 0.0);
	color = mix(color, vec3(1.0, .96, .81), pow(glare, 48.0) * .25);
	float safe_y = abs(ray.y) < .0001 ? (ray.y < 0.0 ? -.0001 : .0001) : ray.y;
	float distance_to_water = (WATER_LEVEL - eye.y) / safe_y;
	float hit_distance = 50000.0;
	if (ray.y < 0.0 && distance_to_water < hit_distance) {
		color = water_color(eye.xz + ray.xz * distance_to_water, distance_to_water, ray);
		hit_distance = distance_to_water;
	}
	// Trace a single smooth height field through its bounded vertical band.
	float top_crossing = (WATER_LEVEL + LAND_HEIGHT - eye.y) / safe_y;
	float start = max(6.0, min(distance_to_water, top_crossing));
	float stop = min(min(hit_distance, 2200.0), max(distance_to_water, top_crossing));
	if (stop > start) {
		int samples = int(clamp(ceil((stop - start) / 3.5), 8.0, 512.0));
		float stride_length = (stop - start) / float(samples);
		for (int i = 1; i <= 512; i++) {
			if (i > samples) { break; }
			float travel = start + float(i) * stride_length;
			vec3 p = eye + ray * travel;
			float height = hill_height(p.xz);
			if (height > WATER_LEVEL + .12 && height >= p.y) {
				float near_side = travel - stride_length;
				for (int refine = 0; refine < 8; refine++) {
					float middle = (near_side + travel) * .5;
					vec3 sample_position = eye + ray * middle;
					if (hill_height(sample_position.xz) >= sample_position.y) { travel = middle; }
					else { near_side = middle; }
				}
				color = land_color(eye + ray * travel, travel);
				break;
			}
		}
	}
	COLOR = vec4(color, 1.0);
}
