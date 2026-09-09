shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float strength = 0.0;
uniform float flow_time = 0.0;
uniform bool trail = false;
varying vec3 world_point;

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i+vec3(1,0,0)), f.x), mix(hash(i+vec3(0,1,0)), hash(i+vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i+vec3(0,0,1)), hash(i+vec3(1,0,1)), f.x), mix(hash(i+vec3(0,1,1)), hash(i+vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (trail) {
		float edge = pow(max(1.0 - abs(UV.y * 2.0 - 1.0), 0.0), 1.6);
		float texture_noise = noise(world_point * 0.8 + vec3(flow_time * 0.3, 0, 0));
		ALBEDO = vec3(0.9, 0.95, 1.0);
		ALPHA = COLOR.a * edge * mix(0.65, 1.0, texture_noise);
	} else {
		vec2 p = UV * 2.0 - 1.0;
		float edge = pow(max(1.0 - dot(p, p), 0.0), 0.8);
		float clouds = noise(vec3(UV.x * 8.0 + flow_time * 3.5, UV.y * 7.0, flow_time * 0.7));
		float fine = noise(vec3(UV * 22.0, flow_time * 1.3));
		ALBEDO = vec3(0.91, 0.95, 1.0);
		ALPHA = strength * edge * smoothstep(0.16, 0.82, clouds * 0.75 + fine * 0.25) * 0.62;
	}
}
