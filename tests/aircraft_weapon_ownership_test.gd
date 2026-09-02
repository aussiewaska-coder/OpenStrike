extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main.tscn"


func _init() -> void:
	var file := FileAccess.open(MAIN_SCENE_PATH, FileAccess.READ)
	assert(file != null, "the main scene must be readable")
	var source := file.get_as_text()
	assert(
		source.contains("[node name=\"CannonWeapon\" type=\"Node3D\" parent=\".\"]"),
		"the shared cannon must not be disabled with either parked aircraft"
	)
	assert(not source.contains("[node name=\"CannonWeapon\" type=\"Node3D\" parent=\"HelicopterAnchor\"]"))
	print("AIRCRAFT_WEAPON_OWNERSHIP_TEST_PASS")
	quit()
