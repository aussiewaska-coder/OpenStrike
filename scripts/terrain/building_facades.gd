class_name BuildingFacades
extends RefCounted

## Facade styling for the batched building mesh, from openstrike_facade_kit_v3.
##
## Nothing here adds nodes or draw calls: it only changes what the SurfaceTool
## emits per vertex, plus a one-off Texture2DArray load. The style, roof and
## tint for a building come from a hash of its footprint, so they are stable
## across runs and across chunk reloads -- a tower does not change colour
## because the player flew away and back.
##
## Vertex channels (matches shaders/building_facade.gdshader):
##   COLOR.rgb  -- per-building tint
##   COLOR.a    -- facade layer index / 255.0
##   CUSTOM0.x  -- horizontal metres along the wall
##   CUSTOM0.y  -- roof layer for this building
##   CUSTOM0.zw -- footprint-normalised roof UV

const FLOOR_M := 3.0

enum Layer {GLASS_TOWER, BALCONY_TOWER, CURTAIN_DARK, RENDER_APT, BRICK, COMMERCIAL, ROOF, ROOF_POOL, ROOF_HELIPAD}


## Deterministic per-building hash from the footprint. FNV-1a over the
## decimetre-rounded vertices, masked positive.
static func footprint_hash(footprint: PackedVector2Array) -> int:
	var h := 2166136261
	for p in footprint:
		h = (h ^ int(p.x * 10.0)) * 16777619
		h = (h ^ int(p.y * 10.0)) * 16777619
	return h & 0x7fffffff


## Pick a facade layer from height and whatever OSM tags survived the build.
## The streamed records carry no tags today, so the commercial branch is
## dormant until tools/build_streamed_buildings.py emits `building`/`shop`;
## height and hash carry the variety on their own.
static func pick_layer(height_m: float, tags: Dictionary, h: int) -> int:
	var b := str(tags.get("building", ""))
	if b == "retail" or b == "commercial" or tags.has("shop"):
		return Layer.COMMERCIAL
	if height_m > 80.0:
		# Towers: mostly the Gold Coast balcony style, some glass, some dark.
		var r := h % 10
		if r < 5:
			return Layer.BALCONY_TOWER
		if r < 8:
			return Layer.GLASS_TOWER
		return Layer.CURTAIN_DARK
	if height_m > 25.0:
		return Layer.BALCONY_TOWER if h % 3 != 0 else Layer.GLASS_TOWER
	if height_m > 10.0:
		return Layer.RENDER_APT if h % 4 != 0 else Layer.BRICK
	return Layer.COMMERCIAL if h % 5 == 0 else Layer.RENDER_APT


## Roof pick: towers get pools, a few tall ones helipads, the rest concrete.
static func pick_roof(height_m: float, h: int) -> int:
	if height_m > 60.0:
		var r := (h >> 6) % 10
		if r < 6:
			return Layer.ROOF_POOL
		if r < 8:
			return Layer.ROOF_HELIPAD
		return Layer.ROOF
	if height_m > 25.0 and (h >> 6) % 4 == 0:
		return Layer.ROOF_POOL
	return Layer.ROOF


## Near-white tint; keeps the texture's own colour but kills the clone-stamp look.
static func pick_tint(h: int) -> Color:
	var r := 0.92 + float((h >> 3) % 100) / 100.0 * 0.08
	var g := 0.92 + float((h >> 9) % 100) / 100.0 * 0.08
	var b := 0.92 + float((h >> 15) % 100) / 100.0 * 0.08
	return Color(r, g, b)


## Snaps an extruded height to whole floors so slab lines land on the parapet.
## NOT applied to the streamed buildings: BuildingHitIndex reads the raw height,
## and a snapped visual over a raw collision volume is exactly the facade-in-
## the-wrong-place its own comment forbids. Kept for anything that owns both.
static func snap_height(height_m: float) -> float:
	return maxf(FLOOR_M, roundf(height_m / FLOOR_M) * FLOOR_M)


## Emit one extruded footprint with facade channels. `footprint` is the closed
## polygon in local XZ metres; `base_y` and `top_y` in metres.
static func emit_building(
	st: SurfaceTool,
	footprint: PackedVector2Array,
	base_y: float,
	top_y: float,
	tags: Dictionary
) -> void:
	var h := footprint_hash(footprint)
	var layer := pick_layer(top_y - base_y, tags, h)
	var roof := pick_roof(top_y - base_y, h)
	var tint := pick_tint(h)
	var col := Color(tint.r, tint.g, tint.b, float(layer) / 255.0)
	var mn := footprint[0]
	var mx := footprint[0]
	for p in footprint:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	var span := (mx - mn).max(Vector2(0.01, 0.01))

	# Walls. run_m accumulates horizontal distance round the perimeter so the
	# facade never mirrors or stretches at corners; both vertices of an edge
	# share the same start/end run, giving exact interpolation across the quad.
	var run_m := 0.0
	var n := footprint.size()
	for i in range(n):
		var a := footprint[i]
		var b := footprint[(i + 1) % n]
		var edge := b - a
		var len_m := edge.length()
		if len_m < 0.01:
			continue
		var nrm3 := Vector3(edge.y, 0.0, -edge.x).normalized()
		var v := [
			Vector3(a.x, base_y, a.y), Vector3(b.x, base_y, b.y),
			Vector3(b.x, top_y, b.y), Vector3(a.x, top_y, a.y),
		]
		var runs := [run_m, run_m + len_m, run_m + len_m, run_m]
		var order := [0, 1, 2, 0, 2, 3]
		for idx in order:
			st.set_color(col)
			st.set_normal(nrm3)
			st.set_custom(0, Color(runs[idx], float(roof), 0.0, 0.0))
			st.add_vertex(v[idx])
		run_m += len_m

	# Roof cap.
	var tris := Geometry2D.triangulate_polygon(footprint)
	for idx in tris:
		var p := footprint[idx]
		st.set_color(col)
		st.set_normal(Vector3.UP)
		var ruv := (p - mn) / span
		st.set_custom(0, Color(0.0, float(roof), ruv.x, ruv.y))
		st.add_vertex(Vector3(p.x, top_y, p.y))


## One material for every building. The strip must be imported as a
## Texture2DArray with nine vertical slices; see its .import file.
static func make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/building_facade.gdshader") as Shader
	mat.set_shader_parameter("facades", load("res://textures/facade_array_strip.png"))
	return mat
