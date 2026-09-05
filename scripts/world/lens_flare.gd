extends Node

## Puts the glare where the sun is on screen and fades it as the sun leaves
## the frame or sets. No occlusion test: from the air the sun is rarely
## behind anything.

const FLARE_SHADER := preload("res://shaders/lens_flare.gdshader")

@export var camera_path: NodePath
@export var sun_path: NodePath
@export var ui_path: NodePath
@export var max_strength := 0.9

var _camera: Camera3D
var _sun: DirectionalLight3D
var _rect: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	var ui := get_node_or_null(ui_path) as CanvasItem
	_rect = ColorRect.new()
	_rect.name = "LensFlareRect"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = FLARE_SHADER
	_rect.material = _material
	if ui != null:
		ui.add_child(_rect)
		ui.move_child(_rect, 0)
	else:
		add_child(_rect)


func _process(_delta: float) -> void:
	if _camera == null or _sun == null:
		_material.set_shader_parameter("strength", 0.0)
		return
	# A directional light shines along -Z; its source is in the +Z direction.
	var towards_sun := _sun.global_transform.basis.z
	var strength := 0.0
	var sun_uv := Vector2(0.5, 0.5)
	if towards_sun.y > 0.0:
		var point := _camera.global_position + towards_sun * 1000.0
		if not _camera.is_position_behind(point):
			var screen := _camera.unproject_position(point)
			var size := _camera.get_viewport().get_visible_rect().size
			sun_uv = screen / size
			# Full inside the frame, gone a little way outside it.
			var edge := 1.0 - smoothstep(0.0, 0.25, maxf(absf(sun_uv.x - 0.5), absf(sun_uv.y - 0.5)) - 0.5)
			var low_sun := smoothstep(0.0, 0.08, towards_sun.y)
			strength = max_strength * edge * low_sun * clampf(_sun.light_energy, 0.0, 1.0)
			_material.set_shader_parameter("aspect", size.x / size.y)
	_material.set_shader_parameter("sun_uv", sun_uv)
	_material.set_shader_parameter("strength", strength)
