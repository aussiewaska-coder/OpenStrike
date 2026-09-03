shader_type spatial;
// cull_disabled rather than the kit's cull_back: some OSM footprints wind the
// wrong way, and under back-face culling those buildings simply vanish. The
// previous shader made the same call for the same reason.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Batched-building facade shader, from openstrike_facade_kit_v3.
// One material for every building. Per-vertex data carried in the batched mesh:
//   COLOR.rgb  = per-building tint (from footprint hash, near-white)
//   COLOR.a    = facade layer index / 255.0  (0..8 in the Texture2DArray)
//   CUSTOM0.x  = horizontal metres along the wall (walls)
//   CUSTOM0.y  = roof layer index for this building
//   CUSTOM0.zw = footprint-normalised roof UV (0..1 across the building)
//   NORMAL     = used to pick wall vs roof mapping.
//
// The texture array is imported from textures/facade_array_strip.png as a
// Texture2DArray with NINE vertical slices, not the seven the kit's comments
// claimed: glass, balcony, dark curtain, render, brick, commercial, roof,
// pool roof, helipad roof.

uniform sampler2DArray facades : source_color, filter_linear_mipmap, repeat_enable;
uniform float module_size_m = 9.0;   // one tile = 9 m x 9 m (3 floors x 3 bays)
const float ROOF_PLAIN = 6.0;
uniform float roof_scale_m = 18.0;   // roof tile covers 18 m so clutter reads bigger
uniform float weathering = 0.15;     // darkens lower floors slightly

varying vec3 world_pos;
varying vec3 world_nrm;
varying vec4 v_col;
varying vec4 v_cust;                 // x=wall run m, y=roof layer, zw=roof UV

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
	v_cust = CUSTOM0;
}

void fragment() {
	float layer = floor(v_col.a * 255.0 + 0.5);
	bool is_roof = world_nrm.y > 0.7;

	vec2 uv;
	if (is_roof) {
		layer = floor(v_cust.y + 0.5);
		if (layer <= ROOF_PLAIN) {
			uv = world_pos.xz / roof_scale_m;   // concrete world-tiles
		} else {
			uv = v_cust.zw;                     // pool/helipad: one per roof
		}
	} else {
		// Horizontal metres along the wall (precomputed per vertex and
		// interpolated linearly, which is exact along a straight wall), vertical
		// from world Y so every floor lands on the texture's floor lines. The
		// kit shipped this line referencing an undeclared `wall_uv_x`; it meant
		// the run carried in CUSTOM0.x.
		uv = vec2(v_cust.x, -world_pos.y) / module_size_m;
	}

	vec4 tex = texture(facades, vec3(uv, layer));

	// per-building tint breaks repetition without a second texture
	vec3 col = tex.rgb * v_col.rgb;

	// cheap ambient weathering toward ground level
	float h = clamp(world_pos.y / 30.0, 0.0, 1.0);
	col *= mix(1.0 - weathering, 1.0, h);

	ALBEDO = col;

	// glass pixels are the darker blue-ish ones; cheap luminance-based gloss
	float glassiness = smoothstep(0.35, 0.15, dot(tex.rgb, vec3(0.333)));
	ROUGHNESS = mix(0.85, 0.25, glassiness);
	METALLIC = 0.0;
	SPECULAR = mix(0.3, 0.6, glassiness);
}
