extends SceneTree

const AIRFRAME_VISUALS := preload("res://scripts/helicopter/airframe_visuals.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var imported_filter := BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var imported := StandardMaterial3D.new()
	imported.texture_filter = imported_filter
	var sharpened := AIRFRAME_VISUALS.sharpen_material(imported)
	assert(sharpened != imported, "the shared imported material must not be changed in place")
	assert(imported.texture_filter == imported_filter, "the imported material must remain unchanged")
	assert(
		sharpened.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,
		"hero materials must retain detail at the external camera angle"
	)
	print("AIRFRAME_VISUALS_TEST_PASS")
	quit()
