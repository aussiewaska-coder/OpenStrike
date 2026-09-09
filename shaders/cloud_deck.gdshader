shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

#include "res://shaders/os_clouds.gdshaderinc"

global uniform float os_night;
global uniform vec3 os_sun_dir;
global uniform vec3 os_sun_color;
global uniform vec3 os_sky_horizon;
global uniform float os_lightning;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float cloud_base_m = 1000.0;
uniform float cloud_top_m = 2600.0;
uniform float max_distance_m = 8000.0;
uniform int march_steps : hint_range(16, 128) = 48;
uniform int shadow_steps : hint_range(0, 5) = 0;
uniform float extinction = 0.009;
uniform float jitter_strength : hint_range(0.0, 1.0) = 1.0;

// Four neighboring rounded volumes have compact support, so grid boundaries
// cannot expose a vertical wall. The weather map modulates their opacity.
vec3 puff_hash(vec2 cell) {
 vec3 h = fract(vec3(cell.x, cell.y, cell.x) * vec3(0.1031, 0.1030, 0.0973));
 h += dot(h, h.yxz + 33.33);
 return fract((h.xxy + h.yzz) * h.zyx);
}

float storm_development() {
 return smoothstep(0.95, 1.0, os_cloud_coverage);
}

float volume_top() {
 return mix(cloud_top_m, 5600.0, storm_development());
}

float volume_density(vec3 p, float footprint_m) {
 float band = cloud_top_m - cloud_base_m;
 float h = (p.y - cloud_base_m) / band;
 if (p.y <= cloud_base_m || p.y >= volume_top()) { return 0.0; }
 float mip = max(log2(max(footprint_m, 1.0) * 512.0 / OS_CLOUD_SCALE_M), 0.0);
 float coverage = os_cloud_density_lod(p.xz, mip);
 if (coverage < 0.015) { return 0.0; }
 vec2 drift = p.xz + os_cloud_wind;
 const float spacing = 1500.0;
 vec2 cell = floor(drift / spacing);
 float body = 0.0;
 for (int x = 0; x < 2; x++) {
  for (int z = 0; z < 2; z++) {
   vec2 id = cell + vec2(float(x), float(z));
   vec3 random = puff_hash(id);
   vec3 variant = puff_hash(id + vec2(71.3, 29.7));
   // Stable empty cells break up the rows without popping during flight.
   if (variant.z > mix(0.70, 0.98, os_cloud_coverage)) { continue; }
   vec2 centre = (id + (random.xy - 0.5) * 0.36) * spacing;
   float radius = mix(0.57, 0.76, random.z) * spacing;
   // Bank altitude changes gradually across neighboring clouds; thickness
   // and small altitude offsets vary independently within each bank.
   float vertical_radius = band * mix(0.075, 0.23, variant.x);
   float bank_height = 0.5 + 0.22 * sin(dot(id, vec2(0.57, 0.41)));
   float local_height = bank_height + (random.y - 0.5) * 0.16;
   float margin = vertical_radius / band + 0.03;
   float centre_y = cloud_base_m + band * clamp(local_height, margin, 1.0 - margin);
   vec2 horizontal = drift - centre;
   // Swap the long axis and vary thickness across cloud groups.
   vec2 axes = mix(vec2(1.0, 0.88), vec2(0.88, 1.0), step(0.5, variant.y));
   vec3 relative = vec3(horizontal.x / (radius * axes.x),
    (p.y - centre_y) / vertical_radius, horizontal.y / (radius * axes.y));
   float base = 1.0 - length(relative);
   // Mix thin and solid clouds using a stable per-cloud choice, not screen noise.
   float opacity = mix(0.22, 0.90, step(0.5, variant.y)) * mix(0.8, 1.1, random.x);
   float puff = clamp(smoothstep(0.0, 0.30, base) * opacity, 0.0, 1.0);
   float development = storm_development();
   if (development > 0.01 && variant.z < 0.20) {
    // Localized rising storm body and a broad, shallow anvil. Compact XZ
    // support stays inside the same four-candidate neighborhood.
    float rise = mix(850.0, 1700.0, variant.x) * development;
    float tower_y = centre_y + rise * 0.8;
    vec3 tower = vec3(horizontal.x / (radius * 0.55),
     (p.y - tower_y) / max(rise, 1.0), horizontal.y / (radius * 0.60));
    vec3 anvil = vec3(horizontal.x / radius,
     (p.y - tower_y - rise * 0.7) / max(300.0 * development, 1.0), horizontal.y / (radius * 0.85));
    float storm_body = max(1.0 - length(tower), 1.0 - length(anvil));
    puff = max(puff, smoothstep(0.0, 0.30, storm_body) * development * 0.95);
   }
   // Smoothly combine overlapping puffs into banks, preserving thin edges.
   body += (1.0 - body) * puff;
  }
 }
 // Broad, soft boundaries avoid the sharp crown and erosion streaks.
 return body * smoothstep(0.015, 0.25, coverage);
}

float sun_transmittance(vec3 p, vec3 sun, float footprint_m) {
	// Integrate only the part of the sun ray inside the cloud band. Fixed
	// expanding strides clipped by the top plane created bright marching bands.
	float distance_m = min((volume_top() - p.y) / max(sun.y, 0.15), 1400.0);
	float stride = max(distance_m, 0.0) / float(shadow_steps);
	float optical_depth = 0.0;
	for (int i = 0; i < 5; i++) {
		if (i >= shadow_steps) { break; }
		optical_depth += volume_density(p + sun * (float(i) + 0.5) * stride, footprint_m) * stride;
	}
	return exp(-optical_depth * extinction);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 view_position = view.xyz / view.w;
	float scene_distance = length(view_position);
	vec3 ray = normalize((INV_VIEW_MATRIX * vec4(normalize(view_position), 0.0)).xyz);
	vec3 origin = CAMERA_POSITION_WORLD;
	float entry = 0.0;
	float end = min(scene_distance, max_distance_m);
	if (abs(ray.y) < 0.00001) {
		if (origin.y <= cloud_base_m || origin.y >= volume_top()) { discard; }
	} else {
		float a = (cloud_base_m - origin.y) / ray.y;
		float b = (volume_top() - origin.y) / ray.y;
		entry = max(0.0, min(a, b));
		end = min(end, max(a, b));
	}
	if (end <= entry) { discard; }
	float stride = (end - entry) / float(march_steps);
	// A different low-discrepancy phase in each stratum avoids both aligned
	// horizontal slices and the coherent streaks of one offset for a whole ray.
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float t = entry + stride * mix(0.5, jitter, jitter_strength);
	float pixel_angle = 2.0 * abs(INV_PROJECTION_MATRIX[1][1]) / VIEWPORT_SIZE.y;
	float transmittance = 1.0;
	vec3 radiance = vec3(0.0);
	vec3 sun = normalize(os_sun_dir + vec3(0.0, 0.00001, 0.0));
	float night = smoothstep(0.4, 0.6, os_night);
	float forward_scatter = pow(max(dot(ray, sun), 0.0), 12.0);
	vec3 sunlight = mix(vec3(1.0, 0.97, 0.91), os_sun_color, 0.45) * mix(1.0, 0.12, night);
	for (int i = 0; i < 128; i++) {
		if (i >= march_steps || transmittance < 0.01) { break; }
		float phase = fract(jitter + float(i) * 0.61803398875);
		// Allocate more intervals near the aircraft; coarse far intervals fade out.
		float u0 = float(i) / float(march_steps);
		float u1 = float(i + 1) / float(march_steps);
		float near_t = entry + (end - entry) * u0 * u0;
		float far_t = entry + (end - entry) * u1 * u1;
		stride = far_t - near_t;
		t = mix(near_t, far_t, mix(0.5, phase, jitter_strength));
		vec3 p = origin + ray * t;
		float footprint = max(t * pixel_angle, stride * 0.5);
		float density = volume_density(p, footprint);
		if (density > 0.001) {
			float height = clamp((p.y - cloud_base_m) / (volume_top() - cloud_base_m), 0.0, 1.0);
			float light = mix(0.40, 0.85, height);
			float shadow_weight = 1.0 - smoothstep(2500.0, 5000.0, t);
			if (shadow_steps > 0 && shadow_weight > 0.01) {
				light = mix(light, sun_transmittance(p, sun, footprint), shadow_weight);
			}
			vec3 ambient = mix(vec3(0.19, 0.24, 0.32), vec3(0.42, 0.50, 0.60), height) * mix(1.0, 0.12, night);
			vec3 scattering = ambient + sunlight * (light * (0.4 + forward_scatter * 0.6) + 0.08);
			scattering += vec3(0.55, 0.65, 0.9) * os_lightning;
			float haze = 1.0 - exp(-t * 0.000055);
			scattering = mix(scattering, os_sky_horizon, haze);
			float fade = 1.0 - smoothstep(max_distance_m * 0.55, max_distance_m, t);
			float alpha = 1.0 - exp(-density * extinction * stride * fade);
			radiance += transmittance * alpha * scattering;
			transmittance *= 1.0 - alpha;
		}
	}
	ALPHA = 1.0 - transmittance;
	ALBEDO = radiance / max(ALPHA, 0.0001);
}
