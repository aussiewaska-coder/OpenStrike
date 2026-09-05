extends MeshInstance3D

## One quad at cloud height that follows the camera, so the F-22 can climb
## through the clouds the sky shows and the ground is shadowed by.

const DECK_SHADER := preload("res://shaders/cloud_deck.gdshader")

@export var camera_path: NodePath
@export var altitude_m := 1800.0
@export var size_m := 60000.0

var _camera: Camera3D


func _ready() -> void:
	# This sheet follows the rendered camera in _process, not a physics tick.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera = get_node_or_null(camera_path) as Camera3D
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_m, size_m)
	mesh = plane
	var material := ShaderMaterial.new()
	material.shader = DECK_SHADER
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad is world-sized; never let the culler drop it.
	extra_cull_margin = 16384.0


func _process(_delta: float) -> void:
	if _camera == null:
		return
	var origin := _camera.global_position
	global_position = Vector3(origin.x, altitude_m, origin.z)
