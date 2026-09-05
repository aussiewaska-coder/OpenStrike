shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
global uniform sampler2D os_cloud_noise;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float edge = pow(max(1.0 - abs(UV.y * 2.0 - 1.0), 0.0), 1.5);
	float noise = texture(os_cloud_noise, world_position.xz * 0.035 + world_position.y * 0.02).r;
	ALBEDO = COLOR.rgb * mix(0.7, 1.12, noise);
	ALPHA = COLOR.a * edge * mix(0.35, 0.85, noise);
}
