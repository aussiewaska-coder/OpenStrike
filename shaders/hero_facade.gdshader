shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Landmark UVs already tile the supplied three-floor facade.
uniform sampler2D facade : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 facade_grid = vec2(8.0, 3.0);
global uniform float os_night;
global uniform float os_wet;
varying vec3 local_normal;

float hash12(vec2 p) {
 vec3 p3 = fract(vec3(p.xyx) * 0.1031);
 p3 += dot(p3, p3.yzx + 33.33);
 return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
 local_normal = NORMAL;
}

void fragment() {
 vec3 tex = texture(facade, UV).rgb;
 ALBEDO = tex;
 METALLIC = 0.0;
 ROUGHNESS = mix(0.65, 0.2, os_wet);
 SPECULAR = 0.35;
 // Keep roof, mullions and balcony slabs dark. Only inset glass panes emit.
 vec2 cell_uv = UV * facade_grid;
 vec2 pane_uv = fract(cell_uv);
 float pane = step(0.15, pane_uv.x) * step(pane_uv.x, 0.85)
  * step(0.2, pane_uv.y) * step(pane_uv.y, 0.8);
 float wall = 1.0 - step(0.7, abs(local_normal.y));
 float lit = step(0.58, hash12(floor(cell_uv)));
 EMISSION = vec3(1.0, 0.8, 0.5) * pane * wall * lit * os_night * 0.7;
}
