shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float power : hint_range(0.0, 1.0) = 0.0;
varying float exhaust_distance;
void vertex() {
	exhaust_distance = VERTEX.y + 0.5;
}
void fragment() {
	float along = clamp(exhaust_distance, 0.0, 1.0);
	float fade = pow(1.0 - along, 1.2) * smoothstep(0.0, 0.08, along);
	float diamonds = pow(0.5 + 0.5 * cos(along * 44.0 - TIME * 8.0), 8.0);
	float ripple = 0.87 + 0.13 * sin(along * 60.0 - TIME * 31.0);
	vec3 colour = mix(vec3(0.015, 0.055, 1.0), vec3(1.0, 0.10, 0.005), smoothstep(0.2, 0.75, along));
	ALBEDO = colour * (1.2 + diamonds * 0.8);
	EMISSION = colour * 0.3;
	ALPHA = clamp(power * fade * ripple * (0.65 + diamonds * 0.35), 0.0, 0.8);
}
