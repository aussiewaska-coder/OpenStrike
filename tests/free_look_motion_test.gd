extends SceneTree

const MOTION := preload("res://scripts/camera/free_look_motion.gd")


func _init() -> void:
	var reference := Vector2.ZERO
	for fps in [30, 60, 120]:
		var motion := MOTION.new()
		var delta: float = 1.0 / fps
		var distance := Vector2.ZERO
		var first := motion.advance(Vector2.RIGHT, delta)
		assert(first.x > 0.0 and first.x < 0.25, "look must ease into a turn")
		distance += first * delta
		for frame in range(fps - 1):
			distance += motion.advance(Vector2.RIGHT, delta) * delta
		assert(motion.velocity.x > 0.99, "sustained look must reach requested speed")
		var before_release := distance
		var braking := motion.advance(Vector2.ZERO, delta)
		assert(braking.x > 0.0 and braking.x < 1.0, "release must brake smoothly")
		distance += braking * delta
		for frame in range(fps - 1):
			distance += motion.advance(Vector2.ZERO, delta) * delta
		assert(distance.x - before_release.x < 0.043, "release must settle within a short head movement")
		assert(motion.velocity.is_zero_approx(), "released look must come to rest")
		assert(motion.advance(Vector2.ZERO, delta).is_zero_approx(), "settled glance must not drift")
		assert(motion.bob_basis(0.3).is_equal_approx(Basis.IDENTITY), "head bob must settle with the glance")
		if fps == 30:
			reference = distance
		else:
			assert(distance.distance_to(reference) < 0.00001, "turn distance must be independent of frame rate")
		motion.advance(Vector2.RIGHT, 0.3)
		var before_reverse := motion.velocity.x
		motion.advance(Vector2.LEFT, delta)
		assert(motion.velocity.x < before_reverse and motion.velocity.x > -0.9, "reversals must ease through the change of direction")
		for sample in [0.13, 0.3, 0.61, 1.7]:
			var bob := motion.bob_basis(sample)
			assert(bob.get_rotation_quaternion().get_angle() < deg_to_rad(0.4), "head bob must stay sub-degree")
		motion.reset()
		assert(motion.velocity.is_zero_approx(), "view changes must discard turn momentum")
	print("FREE_LOOK_MOTION_TEST_PASS")
	quit()
