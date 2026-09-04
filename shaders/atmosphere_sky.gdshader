shader_type sky;
// Gradient sky with a sun that blooms, a moon and stars after dark, and the
// same cloud field the ground is shadowed by. Single pass on purpose: the
// half-resolution subpass is unproven on the Compatibility renderer, and
// four noise reads per background pixel is within budget.

#include "res://shaders/os_clouds.gdshaderinc"

global uniform float os_night;
global uniform vec3 os_sun_color;

uniform vec3 sky_top_color : source_color = vec3(0.19, 0.5, 0.82);
uniform vec3 sky_horizon_color : source_color = vec3(0.78, 0.88, 0.96);
uniform vec3 ground_color : source_color = vec3(0.19, 0.24, 0.25);
uniform float sun_disc_size = 0.018;     // radians
uniform float cloud_altitude_m = 1800.0;
uniform float deck_radius_m = 30000.0;   // the cloud deck quad covers this
uniform float cloud_altitude_fade_m = 25000.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;

	// Gradient: pale at the horizon, deep overhead, dark ground below.
	vec3 col;
	if (up >= 0.0) {
		col = mix(sky_horizon_color, sky_top_color, pow(clamp(up, 0.0, 1.0), 0.45));
	} else {
		col = mix(sky_horizon_color, ground_color, smoothstep(0.0, 0.12, -up));
	}

	// Sun or moon: LIGHT0 is whichever the day cycle has aimed at us.
	float night = smoothstep(0.4, 0.6, os_night);
	float cosang = dot(dir, LIGHT0_DIRECTION);
	float disc_size = mix(sun_disc_size, sun_disc_size * 0.6, night);
	float disc = smoothstep(cos(disc_size + 0.003), cos(disc_size), cosang);
	float glow = pow(max(cosang, 0.0), 48.0) * 0.45 + pow(max(cosang, 0.0), 6.0) * 0.12;
	vec3 light_col = LIGHT0_COLOR * LIGHT0_ENERGY;
	col += light_col * (disc * mix(4.0, 1.5, night) + glow * mix(1.0, 0.15, night));

	// Stars: a sparse hash on the view direction, only after dark.
	if (night > 0.0 && up > 0.0) {
		vec3 cell = floor(dir * 220.0);
		float star = step(0.994, hash13(cell)) * smoothstep(0.0, 0.3, up);
		col += vec3(star) * 1.4 * night;
	}

	// Clouds on a sheet at cloud_altitude_m. When the camera is under the
	// sheet the deck quad draws the near part, so the sky only draws beyond
	// its radius; above the sheet the sky has no clouds overhead at all.
	float height_above = cloud_altitude_m - POSITION.y;
	if (height_above > 0.0 && up > 0.005) {
		float t = height_above / up;
		if (t > deck_radius_m) {
			vec2 world_xz = POSITION.xz + dir.xz * t;
			float density = os_cloud_density(world_xz);
			float lit = os_cloud_lit(world_xz, density, LIGHT0_DIRECTION);
			vec3 cloud_bright = mix(vec3(0.9, 0.92, 0.95), light_col, 0.5);
			vec3 cloud_dark = mix(sky_horizon_color, vec3(0.45, 0.5, 0.6), 0.5);
			vec3 cloud = mix(cloud_dark, cloud_bright, lit) * mix(1.0, 0.12, night);
			float edge = smoothstep(deck_radius_m, deck_radius_m * 1.15, t);
			float far_fade = 1.0 - smoothstep(cloud_altitude_fade_m * 3.0, cloud_altitude_fade_m * 6.0, t);
			col = mix(col, cloud, density * edge * far_fade);
		}
	}

	COLOR = col;
}
