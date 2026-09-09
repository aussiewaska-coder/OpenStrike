extends Node3D

## Production weather scripts and shared environment, without loading aircraft
## and terrain assets from main.tscn just to render a cloud regression.
const ENVIRONMENT := preload("res://assets/environments/flight_environment.tres")
const DAY := preload("res://scripts/world/day_cycle.gd")
const WEATHER := preload("res://scripts/world/weather.gd")
const CLOUDS := preload("res://scripts/world/cloud_deck.gd")
var camera: Camera3D
var day: Node
var weather: Node
var clouds: MeshInstance3D
var environment: Environment
var sun: DirectionalLight3D


func _ready() -> void:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	environment = ENVIRONMENT.duplicate(true)
	world.environment = environment
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 6500.0
	sun.directional_shadow_split_1 = 0.025
	add_child(sun)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.far = 40000.0
	camera.fov = 65.0
	add_child(camera)
	camera.position = Vector3(0, 800, 0)
	camera.make_current()
	day = DAY.new()
	day.name = "DayCycle"
	day.sun_path = NodePath("../Sun")
	day.environment_path = NodePath("../WorldEnvironment")
	add_child(day)
	day.set_process(false)
	day.mode = day.Mode.NOON
	day.refresh()
	weather = WEATHER.new()
	weather.name = "Weather"
	weather.camera_path = NodePath("../Camera3D")
	weather.day_cycle_path = NodePath("../DayCycle")
	add_child(weather)
	weather.set_process(false)
	clouds = CLOUDS.new()
	clouds.name = "CloudDeck"
	add_child(clouds)
	clouds.set_process(false)


func _exit_tree() -> void:
	# Release duplicated environment resources and camera references on teardown.
	environment = null
	camera = null
	sun = null
	day = null
	weather = null
	clouds = null
