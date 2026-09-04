shader_type canvas_item;
// Screen-space sun glare: a soft halo at the sun and a few ghosts strung
// along the line through screen centre. Additive, so it only ever brightens.
render_mode blend_add, unshaded;

uniform vec2 sun_uv = vec2(0.5, 0.5);
uniform float strength = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.92, 0.8);
uniform float aspect = 1.777;

float disc(vec2 p, vec2 centre, float radius) {
	p.x *= aspect;
	centre.x *= aspect;
	return 1.0 - smoothstep(radius * 0.4, radius, length(p - centre));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 to_centre = vec2(0.5) - sun_uv;
	float halo = disc(uv, sun_uv, 0.22) * 0.55 + disc(uv, sun_uv, 0.06) * 0.6;
	float ghosts = disc(uv, sun_uv + to_centre * 0.7, 0.05) * 0.35
		+ disc(uv, sun_uv + to_centre * 1.25, 0.09) * 0.25
		+ disc(uv, sun_uv + to_centre * 1.7, 0.035) * 0.3;
	// Streak: thin horizontal line through the sun.
	float streak = exp(-abs(uv.y - sun_uv.y) * 220.0) * (1.0 - smoothstep(0.0, 0.5, abs(uv.x - sun_uv.x))) * 0.35;
	COLOR = vec4(tint * (halo + ghosts + streak) * strength, 1.0);
}
