shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 base = COLOR.rgb * 0.92;
	float wall = 1.0 - smoothstep(0.55, 0.82, abs(world_normal.y));
	float horizontal_position = mix(world_position.x, world_position.z, step(abs(world_normal.x), abs(world_normal.z)));
	vec2 facade_cell = vec2(fract(horizontal_position / 5.2), fract(world_position.y / 3.25));
	float window_x = step(0.14, facade_cell.x) * (1.0 - step(0.83, facade_cell.x));
	float window_y = step(0.20, facade_cell.y) * (1.0 - step(0.69, facade_cell.y));
	float window_mask = wall * window_x * window_y;
	float roof_variation = 0.88 + 0.12 * abs(world_normal.y);
	vec3 glass = vec3(0.20, 0.34, 0.40);
	ALBEDO = mix(base * roof_variation, glass, window_mask * 0.86);
	METALLIC = mix(0.08, 0.32, window_mask);
	ROUGHNESS = mix(0.72, 0.24, window_mask);
}
