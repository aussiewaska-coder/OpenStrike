shader_type canvas_item;
render_mode unshaded;
uniform sampler2D aerial : filter_linear;
uniform sampler2D elevation : filter_linear;
uniform bool has_aerial = false;
uniform bool has_elevation = false;
uniform int map_style = 1;
uniform vec2 centre_uv = vec2(0.5);
uniform vec2 span_uv = vec2(1.0);
uniform vec2 elevation_texel = vec2(0.002);
uniform float elevation_min = 0.0;
uniform float elevation_max = 1000.0;
void fragment() {
	vec2 uv = centre_uv + (UV - 0.5) * span_uv;
	bool inside = all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));
	vec3 colour = vec3(0.025, 0.07, 0.075);
	if (inside && has_elevation) {
		float h = mix(elevation_min, elevation_max, texture(elevation, uv).r);
		float west = texture(elevation, uv - vec2(elevation_texel.x, 0.0)).r;
		float east = texture(elevation, uv + vec2(elevation_texel.x, 0.0)).r;
		float north = texture(elevation, uv - vec2(0.0, elevation_texel.y)).r;
		float south = texture(elevation, uv + vec2(0.0, elevation_texel.y)).r;
		float shade = clamp(0.76 + (west - east + north - south) * 9.0, 0.32, 1.15);
		float contour = smoothstep(0.03, 0.09, abs(fract(h / 100.0) - 0.5));
		if (map_style == 2) {
			vec3 low = vec3(0.15, 0.32, 0.24);
			vec3 high = vec3(0.62, 0.49, 0.30);
			colour = mix(low, high, clamp(h / 1300.0, 0.0, 1.0)) * shade * mix(0.65, 1.0, contour);
		} else {
			colour = vec3(0.06, 0.18, 0.15) * mix(0.62, 1.0, contour);
		}
		if (h < 1.0) { colour = vec3(0.025, 0.09, 0.14); }
	}
	if (map_style == 0 && has_aerial && inside) {
		colour = texture(aerial, uv).rgb * vec3(0.72, 0.88, 0.81);
	}
	float vignette = 1.0 - 0.23 * dot(UV - 0.5, UV - 0.5);
	float scan = 0.97 + 0.03 * sin(FRAGCOORD.y * 3.14159);
	COLOR = vec4(colour * vignette * scan, 1.0);
}
