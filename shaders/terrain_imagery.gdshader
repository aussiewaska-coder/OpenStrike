shader_type spatial;
// The ground is an aerial photograph, so it is drawn unshaded and everything
// the light does to it is painted here: day-night tint, drifting cloud
// shadows, the sea's sun glitter, and city lights after dark.
render_mode unshaded, cull_disabled;

#include "res://shaders/os_clouds.gdshaderinc"

global uniform sampler2D os_water_normal;
global uniform float os_cloud_shadow;   // how dark a cloud's shadow is
global uniform float os_night;          // 0 day .. 1 night
global uniform vec3 os_terrain_tint;    // white by day, dim blue by night
global uniform vec3 os_sky_horizon;     // what the sea reflects
global uniform vec3 os_sun_dir;         // unit vector toward the sun
global uniform vec3 os_sun_color;       // colour times energy
global uniform float os_lightning;

uniform sampler2D imagery : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool has_imagery = false;       // until the photo arrives, plain ground
uniform float sea_level_m = 0.75;       // vertices at or below this are water
uniform float lights_density = 0.12;    // fraction of land cells lit at night

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 col = has_imagery ? texture(imagery, UV * uv_scale + uv_offset).rgb : vec3(0.36, 0.38, 0.34);
	vec3 photo = col;

	float sea = 1.0 - smoothstep(sea_level_m, sea_level_m + 0.6, world_pos.y);

	// Sea: two scrolling normal tiles, a sun highlight, and a little sky.
	if (sea > 0.0) {
		vec2 flow = vec2(TIME * 0.9, TIME * 0.4);
		vec3 n1 = texture(os_water_normal, world_pos.xz / 60.0 + flow * 0.02).rgb * 2.0 - 1.0;
		vec3 n2 = texture(os_water_normal, world_pos.xz / 23.0 - flow.yx * 0.03).rgb * 2.0 - 1.0;
		vec3 normal = normalize(vec3(n1.x + n2.x, 3.0, n1.y + n2.y));
		vec3 to_eye = normalize(CAMERA_POSITION_WORLD - world_pos);
		vec3 half_dir = normalize(to_eye + os_sun_dir);
		float glitter = pow(max(dot(normal, half_dir), 0.0), 180.0) * max(os_sun_dir.y, 0.0);
		float fresnel = pow(1.0 - max(dot(to_eye, normal), 0.0), 4.0);
		vec3 water = mix(col, os_sky_horizon, fresnel * 0.4) + os_sun_color * glitter * 1.4;
		col = mix(col, water, sea);
	}

	col *= os_terrain_tint;
	col *= 1.0 - os_cloud_shadow * os_cloud_density(world_pos.xz);

	// City lights: scattered warm points after dark, but only where the
	// photograph looks built. The height grid samples every hundred metres or
	// so, far too coarse to tell a canal from its bank, which is why the sea
	// test alone left lights floating on the water. The imagery knows: roofs,
	// roads and carparks are bright and grey, bush and cane are green, and
	// water is dark. That one test keeps the lights off the Broadwater and out
	// of the hinterland at the same time.
	float lum = dot(photo, vec3(0.299, 0.587, 0.114));
	float green = photo.g - max(photo.r, photo.b);
	float built = smoothstep(0.10, 0.24, lum) * (1.0 - smoothstep(0.02, 0.10, green)) * float(has_imagery);
	if (os_night > 0.01 && sea < 0.5 && built > 0.0) {
		vec2 cell = floor(world_pos.xz / 14.0);
		float on = step(1.0 - lights_density, hash12(cell));
		vec2 in_cell = fract(world_pos.xz / 14.0) - 0.5;
		float point = 1.0 - smoothstep(0.08, 0.28, length(in_cell));
		col += vec3(1.0, 0.78, 0.5) * on * point * os_night * built * 1.1;
	}

	ALBEDO = col + photo * vec3(0.3, 0.4, 0.6) * os_lightning;
}
