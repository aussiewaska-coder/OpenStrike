extends Node3D

const SCOPE = preload("res://scripts/ui/cockpit_scope.gd")
const REFRESH_SECONDS := 1.0 / 15.0
var viewport: SubViewport
var scope: Control
var screen: MeshInstance3D
var _active := false
var _elapsed := 0.0

## Corners measured on the authored F-35 cockpit screen, in that mesh's local
## coordinates. Use the right half, inset inside its bezel. Parenting to the
## cockpit keeps the display in place through aircraft motion and head look.
static func attach(model: Node3D) -> Node3D:
	for part in model.find_children("*", "MeshInstance3D", true, false):
		if String(part.get_parent().name) != "F-35-cockpit_2":
			continue
		var display = load("res://scripts/jet/cockpit_mfd.gd").new()
		display.name = "CockpitMFD"
		part.add_child(display)
		return display
	return null

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(512, 416)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	scope = SCOPE.new()
	viewport.add_child(scope)
	var tl := Vector3(73.60506, -2.75, -6.15460)
	var tr := Vector3(73.60506, 2.75, -6.15460)
	var bl := Vector3(73.21332, -2.75, -3.93292)
	var br := Vector3(73.21332, 2.75, -3.93292)
	var normal := (bl - tl).cross(tr - tl).normalized()
	var corners := PackedVector3Array([
		tl.lerp(tr, 0.52).lerp(bl.lerp(br, 0.52), 0.035),
		tl.lerp(tr, 0.985).lerp(bl.lerp(br, 0.985), 0.035),
		tl.lerp(tr, 0.985).lerp(bl.lerp(br, 0.985), 0.965),
		tl.lerp(tr, 0.52).lerp(bl.lerp(br, 0.52), 0.965)])
	for i in corners.size():
		corners[i] += normal * 0.025
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = corners
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([normal, normal, normal, normal])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	material.disable_receive_shadows = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	screen = MeshInstance3D.new()
	screen.name = "LiveScreen"
	screen.mesh = mesh
	screen.material_override = material
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(screen)
	set_process(false)
	scope.set_process(false)

func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	set_process(active)
	scope.set_process(active)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = fmod(_elapsed, REFRESH_SECONDS)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_state(position: Vector3, heading: float, contacts: Array, locked: int, range_metres: float) -> void:
	scope.display_range = range_metres
	scope.set_contacts(position, heading, contacts, locked)

func set_layers(layers: Dictionary) -> void:
	scope.set_layers(layers)

func contains_screen_point(camera: Camera3D, point: Vector2) -> bool:
	if not _active:
		return false
	var polygon := PackedVector2Array()
	var transform := screen.get_global_transform_interpolated()
	var vertices: PackedVector3Array = screen.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		var world := transform * vertex
		if camera.is_position_behind(world):
			return false
		polygon.append(camera.unproject_position(world))
	return Geometry2D.is_point_in_polygon(point, polygon)
