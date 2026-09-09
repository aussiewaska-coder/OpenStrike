shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

global uniform float os_night;
global uniform float os_lightning;
uniform float intensity = 0.0;
uniform vec3 travel_direction = vec3(0.0, -1.0, 0.0);
uniform float streak_length = 0.85;
varying float seed;
varying float distance_to_eye;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 to_eye = CAMERA_POSITION_WORLD - centre;
	vec3 across = cross(travel_direction, to_eye);
	if (length(across) < 0.001) {
		across = INV_VIEW_MATRIX[0].xyz;
	}
	across = normalize(across);
	vec3 world = centre + across * VERTEX.x + travel_direction * VERTEX.y * streak_length;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	seed = COLOR.r;
	distance_to_eye = length(to_eye);
}

void fragment() {
	if (seed > intensity) { discard; }
	float edge = 1.0 - smoothstep(0.2, 0.5, abs(UV.x - 0.5));
	float tip = 1.0 - smoothstep(0.25, 0.5, abs(UV.y - 0.5));
	float distance_fade = smoothstep(2.0, 5.0, distance_to_eye) * (1.0 - smoothstep(25.0, 40.0, distance_to_eye));
	ALBEDO = mix(vec3(0.68, 0.78, 0.86), vec3(0.25, 0.32, 0.43), os_night) + vec3(os_lightning * 0.3);
	ALPHA = edge * tip * distance_fade * 0.42;
}
