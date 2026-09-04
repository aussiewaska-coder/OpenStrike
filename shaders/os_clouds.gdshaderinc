// The one cloud field. The sky draws it overhead, the terrain darkens under
// it, the deck quad shows it up close: all three sample this, so clouds,
// their shadows and the deck line up. World XZ in metres.

global uniform sampler2D os_cloud_noise;
global uniform vec2 os_cloud_wind;      // metres of drift so far
global uniform float os_cloud_coverage; // 0 clear .. 1 overcast

const float OS_CLOUD_SCALE_M = 6000.0;

float os_cloud_density(vec2 world_xz) {
	vec2 uv = (world_xz + os_cloud_wind) / OS_CLOUD_SCALE_M;
	float n = texture(os_cloud_noise, uv).r * 0.7
		+ texture(os_cloud_noise, uv * 3.1 + vec2(0.37, 0.11)).r * 0.3;
	// Coverage slides the threshold: at 0 nothing passes, at 1 nearly all.
	float threshold = mix(0.78, 0.28, os_cloud_coverage);
	return smoothstep(threshold, threshold + 0.22, n);
}

// How lit a cloud pixel is: thinner toward the sun means the sun reaches it.
float os_cloud_lit(vec2 world_xz, float density, vec3 sun_dir) {
	vec2 toward_sun = normalize(sun_dir.xz + vec2(1e-4, 0.0));
	float upstream = os_cloud_density(world_xz + toward_sun * 400.0);
	return clamp(1.0 - (upstream - density) * 2.5, 0.35, 1.0);
}
