shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
uniform float opacity = 0.0;
void fragment() {
 float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
 ALBEDO = vec3(0.82, 0.80, 0.73);
 ALPHA = rim * opacity;
}
