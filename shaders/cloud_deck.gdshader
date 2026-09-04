shader_type spatial;
// The cloud sheet you can fly through. One big quad at the cloud altitude,
// sampling the same field as the sky and the ground shadows.
render_mode unshaded, cull_disabled, depth_draw_never;

#include "res://shaders/os_clouds.gdshaderinc"

global uniform float os_night;
global uniform vec3 os_sun_dir;
global uniform vec3 os_sun_color;
global uniform vec3 os_sky_horizon;

uniform float fade_start_m = 22000.0;
uniform float fade_end_m = 30000.0;
uniform float band_half_height_m = 150.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float density = os_cloud_density(world_pos.xz);
	float lit = os_cloud_lit(world_pos.xz, density, os_sun_dir);
	float night = smoothstep(0.4, 0.6, os_night);
	vec3 bright = mix(vec3(0.9, 0.92, 0.95), os_sun_color, 0.5);
	vec3 dark = mix(os_sky_horizon, vec3(0.45, 0.5, 0.6), 0.5);
	vec3 col = mix(dark, bright, lit) * mix(1.0, 0.12, night);

	vec3 to_camera = CAMERA_POSITION_WORLD - world_pos;
	float distance_fade = 1.0 - smoothstep(fade_start_m, fade_end_m, length(to_camera.xz));
	// Soften while the camera passes through the sheet.
	float band_fade = smoothstep(0.0, band_half_height_m, abs(to_camera.y));

	ALBEDO = col;
	ALPHA = density * distance_fade * band_fade * 0.92;
}
