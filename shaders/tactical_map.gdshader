shader_type canvas_item;
render_mode unshaded;

// The battle map's ground. Every pixel is turned back into a point on the
// terrain by inverting the same pinhole camera the CPU projection in
// battle_map_view.gd uses, so imagery and markers agree at any pan, zoom,
// bearing or tilt. At tilt 0 the depth term is constant and this is exactly the
// flat map it always was.

uniform sampler2D aerial : filter_linear;
uniform sampler2D elevation : filter_linear;
uniform bool has_aerial = false;
uniform bool has_elevation = false;
uniform int map_style = 1;
uniform vec2 centre_world = vec2(0.0);
uniform float world_size = 50000.0;
uniform float focal = 1000.0;
uniform float view_distance = 10000.0;
uniform float tilt_sine = 0.0;
uniform float tilt_cosine = 1.0;
uniform float bearing_cosine = 1.0;
uniform float bearing_sine = 0.0;
uniform vec2 viewport_size = vec2(1000.0);
uniform vec2 elevation_texel = vec2(0.002);
uniform float elevation_min = 0.0;
uniform float elevation_max = 1000.0;
// 0.0 flattens the terrain back to a plain map image.
uniform float relief = 1.0;

float terrain_height(vec2 uv) {
	return mix(elevation_min, elevation_max, texture(elevation, uv).r);
}

vec2 map_to_world(vec2 offset) {
	return vec2(offset.x * bearing_cosine - offset.y * bearing_sine, offset.x * bearing_sine + offset.y * bearing_cosine);
}

vec2 region_uv(vec2 world) {
	return world / world_size + vec2(0.5);
}

// Solves the ground point whose raised surface lands on this screen pixel.
// Surface height comes from the flat answer and is applied once; a second pass
// buys little for four more fetches per pixel.
vec2 ground_offset(vec2 pixel, out bool hit, out float depth) {
	vec2 along = (pixel - viewport_size * 0.5) / focal;
	float denominator = tilt_cosine + along.y * tilt_sine;
	hit = denominator > 0.0001;
	depth = view_distance;
	if (!hit) {
		return vec2(0.0);
	}
	vec2 level = vec2(along.x * view_distance, along.y * view_distance / denominator);
	depth = view_distance - level.y * tilt_sine;
	if (!has_elevation || relief <= 0.0001) {
		return level;
	}
	vec2 raised = level;
	vec2 probe = region_uv(centre_world + map_to_world(level));
	if (probe.x >= 0.0 && probe.x <= 1.0 && probe.y >= 0.0 && probe.y <= 1.0) {
		// Relief is weighted by the tilt, which keeps a top-down view of the map
		// geometrically identical to the unprojected flat map.
		float height = terrain_height(probe) * relief * tilt_sine;
		raised.y = (along.y * (view_distance - height * tilt_cosine) - height * tilt_sine) / denominator;
		depth = view_distance - raised.y * tilt_sine - height * tilt_cosine;
	}
	return raised;
}

void fragment() {
	bool hit = false;
	float depth = view_distance;
	vec2 map = ground_offset(UV * viewport_size, hit, depth);
	vec2 uv = region_uv(centre_world + map_to_world(map));
	bool inside = hit && all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));
	vec3 colour = vec3(0.025, 0.07, 0.075);
	float height = 0.0;
	if (inside) {
		height = has_elevation ? terrain_height(uv) : 0.0;
		if (has_elevation) {
			// The gradient is measured in ground metres, not screen pixels, so the
			// sun stays put as the map turns. The step opens with distance to keep
			// far relief from crawling, and the shading is normalised back against
			// it so a widening sample does not also brighten the slope.
			vec2 foot = max(elevation_texel, fwidth(uv) * 1.5);
			float west = terrain_height(uv - vec2(foot.x, 0.0));
			float east = terrain_height(uv + vec2(foot.x, 0.0));
			float north = terrain_height(uv - vec2(0.0, foot.y));
			float south = terrain_height(uv + vec2(0.0, foot.y));
			float span = max(elevation_max - elevation_min, 1.0);
			float widen = max(foot.x / max(elevation_texel.x, 0.0000001), 1.0);
			float shade = clamp(0.76 + ((west - east + north - south) / span) * 9.0 / widen, 0.32, 1.15);
			float contour = smoothstep(0.03, 0.09, abs(fract(height / 100.0) - 0.5));
			if (map_style == 2) {
				vec3 low = vec3(0.15, 0.32, 0.24);
				vec3 high = vec3(0.62, 0.49, 0.30);
				colour = mix(low, high, clamp(height / 1300.0, 0.0, 1.0)) * shade * mix(0.65, 1.0, contour);
			} else {
				colour = vec3(0.06, 0.18, 0.15) * mix(0.62, 1.0, contour);
			}
			if (height < 1.0) {
				colour = vec3(0.025, 0.09, 0.14);
			}
		} else {
			colour = vec3(0.06, 0.18, 0.15);
		}
		if (map_style == 0 && has_aerial) {
			colour = texture(aerial, uv).rgb * vec3(0.72, 0.88, 0.81);
		}
		// Ground reaching for the horizon lies under more air than the map's
		// haze was tuned for; washing it out reads as distance instead of noise.
		float recede = clamp((depth / max(view_distance, 1.0) - 1.4) / 3.0, 0.0, 0.72);
		colour = mix(colour, vec3(0.16, 0.24, 0.30), recede);
	} else if (hit) {
		// Past the edge of the surveyed region: the same waterless dark the flat
		// map used, so panning off the data still looks intentional.
		colour = vec3(0.02, 0.05, 0.055);
	} else {
		// Beyond the horizon the ground plane has no answer at all.
		colour = mix(vec3(0.03, 0.07, 0.09), vec3(0.10, 0.16, 0.22), clamp(UV.y * 3.0, 0.0, 1.0));
	}
	float vignette = 1.0 - 0.23 * dot(UV - 0.5, UV - 0.5);
	float scan = 0.97 + 0.03 * sin(FRAGCOORD.y * 3.14159);
	COLOR = vec4(colour * vignette * scan, 1.0);
}
