shader_type sky;
// Atmosphere and a thin high cirrus sheet; low clouds use the volume pass.
#include "res://shaders/os_clouds.gdshaderinc"

global uniform float os_night;
global uniform vec3 os_sun_color;
global uniform float os_lightning;

uniform vec3 sky_top_color : source_color = vec3(0.19, 0.5, 0.82);
uniform vec3 sky_horizon_color : source_color = vec3(0.78, 0.88, 0.96);
uniform vec3 ground_color : source_color = vec3(0.19, 0.24, 0.25);
uniform float sun_disc_size = 0.018;     // radians

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;

	// Broad horizon haze on both sides hides the finite terrain edge.
	// Avoid an abrupt dark lower hemisphere just below the distant skyline.
	vec3 col;
	if (up >= 0.0) {
		col = mix(sky_horizon_color, sky_top_color, pow(smoothstep(0.0, 0.85, up), 0.65));
	} else {
		col = mix(sky_horizon_color, ground_color, smoothstep(0.12, 0.65, -up));
	}

	// Sun or moon: LIGHT0 is whichever the day cycle has aimed at us.
	float night = smoothstep(0.4, 0.6, os_night);
	float cosang = dot(dir, LIGHT0_DIRECTION);
	float disc_size = mix(sun_disc_size, sun_disc_size * 0.6, night);
	float disc = smoothstep(cos(disc_size + 0.003), cos(disc_size), cosang);
	float glow = pow(max(cosang, 0.0), 48.0) * 0.45 + pow(max(cosang, 0.0), 6.0) * 0.12;
	vec3 light_col = LIGHT0_COLOR * LIGHT0_ENERGY;
	col += light_col * (disc * mix(4.0, 1.5, night) + glow * mix(1.0, 0.15, night));

	// Two texture reads for a distant cirrus sheet, with world-space parallax.
	// It is drawn behind the lower volume, without another ray march.
	if (abs(up) > 0.015) {
		float cirrus_t = (6500.0 - POSITION.y) / up;
		if (cirrus_t > 0.0 && cirrus_t < 120000.0) {
			vec2 at = POSITION.xz + dir.xz * cirrus_t + os_cloud_wind * 1.6;
			vec2 stretched = vec2(at.x + at.y * 0.35, at.y - at.x * 0.2) / vec2(22000.0, 2600.0);
			float strands = textureLod(os_cloud_noise, stretched, 0.0).r;
			float patches = textureLod(os_cloud_noise, at / 18000.0 + vec2(0.19, 0.63), 0.0).r;
			float veil = smoothstep(0.46, 0.70, strands) * smoothstep(0.40, 0.65, patches);
			veil *= smoothstep(0.015, 0.12, abs(up)) * (1.0 - smoothstep(60000.0, 120000.0, cirrus_t));
			vec3 ice = mix(vec3(0.94, 0.95, 1.0), sky_horizon_color, 0.35) * mix(1.0, 0.15, night);
			col = mix(col, ice, veil * 0.42);
		}
	}

	// Stars: a sparse hash on the view direction, only after dark.
	if (night > 0.0 && up > 0.0) {
		vec3 cell = floor(dir * 220.0);
		float star = step(0.994, hash13(cell)) * smoothstep(0.0, 0.3, up);
		col += vec3(star) * 1.4 * night;
	}


	COLOR = col + vec3(0.3, 0.4, 0.6) * os_lightning;
}
