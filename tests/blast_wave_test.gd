extends SceneTree
const FX := preload("res://scripts/effects/impact_fx_manager.gd")
func _init() -> void: call_deferred("run")
func run() -> void:
	var fx := FX.new()
	root.add_child(fx)
	fx.set_process(false)
	fx.spawn_explosion(Vector3(100, 20, 50))
	var wave: Dictionary = fx._waves[0]
	assert(wave.mesh.visible and wave.mesh.position.is_equal_approx(Vector3(100, 21, 50)))
	fx._process(0.3)
	var radius: float = wave.mesh.scale.x
	var opacity: float = wave.mesh.material_override.get_shader_parameter("opacity")
	fx._process(0.4)
	assert(wave.mesh.scale.x > radius and wave.mesh.material_override.get_shader_parameter("opacity") < opacity, "shockwave expands and thins")
	fx._process(1.0)
	assert(not wave.mesh.visible, "shockwave retires")
	for i in 20: fx.spawn_explosion(Vector3(i * 50, 0, 0))
	assert(fx._waves.size() == 8, "repeated blasts reuse a bounded shockwave pool")
	fx.free()
	await process_frame
	print("BLAST_WAVE_TEST_PASS")
	quit()
