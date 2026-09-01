extends SceneTree

# Turret articulation and the R1 aim path (spec section 82).

const AIM := preload("res://scripts/weapons/cannon_aim.gd")
const RESOLVER := preload("res://scripts/world/world_surface_resolver.gd")
const SURFACES := preload("res://scripts/world/surface_types.gd")


func _initialize() -> void:
	var aim: RefCounted = AIM.new()

	# Nose is local +X, so a point straight ahead is zero yaw and zero pitch.
	assert(aim.local_aim_for(Vector3.ZERO, Vector3(100.0, 0.0, 0.0), 0.0).is_equal_approx(Vector2.ZERO), "forward is zero")
	# A yaw of theta about +Y maps the nose to (cos, 0, -sin): -Z is 90 degrees left.
	assert(is_equal_approx(aim.local_aim_for(Vector3.ZERO, Vector3(0.0, 0.0, -100.0), 0.0).x, 90.0), "-Z is +90")
	assert(is_equal_approx(aim.local_aim_for(Vector3.ZERO, Vector3(0.0, 0.0, 100.0), 0.0).x, -90.0), "+Z is -90")
	# Aim is relative to the hull, so yawing the airframe cancels the offset.
	var hull: Vector2 = aim.local_aim_for(Vector3.ZERO, Vector3(0.0, 0.0, -100.0), deg_to_rad(90.0))
	assert(absf(hull.x) < 0.001, "a point off the nose is zero yaw whatever the hull heading")
	assert(is_equal_approx(aim.local_aim_for(Vector3.ZERO, Vector3(100.0, -100.0, 0.0), 0.0).y, -45.0), "45 down")

	# Articulation limits.
	assert(aim.clamp_aim(Vector2(170.0, 0.0)).x == aim.max_yaw_right, "yaw must clamp right")
	assert(aim.clamp_aim(Vector2(-170.0, 0.0)).x == -aim.max_yaw_left, "yaw must clamp left")
	assert(aim.clamp_aim(Vector2(0.0, 80.0)).y == aim.max_pitch_up, "the M230 barely elevates")
	assert(aim.clamp_aim(Vector2(0.0, -80.0)).y == -aim.max_pitch_down, "pitch must clamp down")

	# A target behind the aircraft parks the turret at its limit and flags it,
	# rather than firing sideways through the airframe.
	aim.set_look_provider(func() -> Variant: return Vector3(-100.0, 0.0, 0.0))
	for _step in range(400):
		aim.update(1.0 / 60.0, Vector3.ZERO, 0.0)
	assert(aim.at_limit, "an unreachable target must raise the limit flag")
	assert(absf(aim.yaw_degrees) <= aim.max_yaw_left + 0.001, "the turret must not exceed its limit")
	assert(absf(aim.yaw_degrees) > aim.max_yaw_left - 1.0, "the turret should sit at the limit")

	# A reachable point is tracked, and the traverse is visible rather than instant.
	var tracking: RefCounted = AIM.new()
	tracking.set_look_provider(func() -> Variant: return Vector3(100.0, 0.0, -100.0))
	tracking.update(1.0 / 60.0, Vector3.ZERO, 0.0)
	assert(tracking.yaw_degrees < 20.0, "the turret must traverse, not snap")
	for _step in range(400):
		tracking.update(1.0 / 60.0, Vector3.ZERO, 0.0)
	assert(absf(tracking.yaw_degrees - 45.0) < 0.5, "the turret must settle on 45 degrees")
	assert(not tracking.at_limit, "45 degrees is well inside the limit")
	assert(tracking.aim_source == AIM.AimSource.FREE_LOOK, "free look must be the aim source")

	# Releasing R1 returns the gun forward smoothly.
	tracking.set_look_provider(Callable())
	for _step in range(600):
		tracking.update(1.0 / 60.0, Vector3.ZERO, 0.0)
	assert(absf(tracking.yaw_degrees) < 0.5, "the gun must return forward, got %f" % tracking.yaw_degrees)
	assert(tracking.aim_source == AIM.AimSource.FORWARD, "with no providers the source is forward")

	# An explicit target outranks free look.
	var priority: RefCounted = AIM.new()
	priority.set_look_provider(func() -> Variant: return Vector3(0.0, 0.0, -100.0))
	priority.set_target_provider(func() -> Variant: return Vector3(100.0, 0.0, 0.0))
	priority.update(1.0 / 60.0, Vector3.ZERO, 0.0)
	assert(priority.aim_source == AIM.AimSource.TARGET, "an explicit target wins")

	# Splat weights are the authoritative ground material.
	var resolver: RefCounted = RESOLVER.new()
	resolver.configure(func(_x: float, _z: float) -> float: return 100.0, 0.0)
	assert(not resolver.has_splat_data(), "no provider means no splat data")
	assert(resolver.resolve(0.0, 0.0) == SURFACES.Surface.ROCK, "the elevation fallback stands in")
	resolver.set_splat_provider(func(_x: float, _z: float) -> Dictionary:
		return {"grass": 0.03, "sand": 0.91, "soil": 0.05, "urban": 0.01}
	)
	assert(resolver.has_splat_data(), "provider must register")
	assert(resolver.resolve(0.0, 0.0) == SURFACES.Surface.SAND, "91 percent sand must read as sand")
	var blend: Dictionary = resolver.resolve_blend(0.0, 0.0)
	assert(is_equal_approx(float(blend[SURFACES.Surface.SAND]), 0.91), "blend must preserve weights")

	print("CANNON_AIM_TEST_PASS")
	quit()
