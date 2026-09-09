shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D billow_texture : source_color, filter_linear_mipmap;
uniform sampler2D diffuse_texture : source_color, filter_linear_mipmap;
uniform float source_height = 0.0;
varying float rise;
void vertex() {
 rise = max(MODEL_MATRIX[3].y - source_height, 0.0);
 float angle = INSTANCE_CUSTOM.x;
 mat2 rotation = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
 VERTEX.xy = rotation * VERTEX.xy;
 vec3 dimensions = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
 MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * dimensions.x, INV_VIEW_MATRIX[1] * dimensions.y, INV_VIEW_MATRIX[2] * dimensions.z, MODEL_MATRIX[3]);
}
void fragment() {
 float diffusion = smoothstep(60.0, 380.0, rise);
 vec4 puff = texture(billow_texture, UV);
 vec4 mist = texture(diffuse_texture, UV);
 float density = mix(puff.a, mist.a * 0.55, diffusion);
 ALBEDO = mix(COLOR.rgb * puff.rgb, vec3(0.34, 0.35, 0.36), diffusion * 0.75);
 ALPHA = COLOR.a * density * mix(1.0, 0.28, diffusion) * (1.0 - smoothstep(400.0, 950.0, rise));
}
