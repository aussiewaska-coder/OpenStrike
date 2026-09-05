extends SceneTree

## The Nighthawk against the Raptor.
##
## These assert the shape of the difference rather than particular numbers, so
## retuning stays free as long as it is still the same aircraft: slower to roll,
## no afterburner, less lift, a lower limit, and nothing to vector with.

const AIRFRAME := preload("res://scripts/jet/airframe.gd")
const AERO := preload("res://scripts/jet/aero_model.gd")

func _init(): call_deferred("_run")

func _run():
	var raptor = AIRFRAME.raptor()
	var night = AIRFRAME.nighthawk()
	assert(night.display_name == "F-117 NIGHTHAWK")

	assert(night.thrust_afterburner_g == night.thrust_military_g, "the F-117 has no afterburner")
	assert(night.thrust_military_g < raptor.thrust_military_g, "and less thrust than the Raptor")
	assert(night.load_limit_g < raptor.load_limit_g, "a lower load limit")
	assert(night.thrust_vector_authority == 0.0, "and no vectoring nozzles")
	assert(night.drag_divergence_mps < raptor.drag_divergence_mps, "drag rises earlier: it is subsonic")
	assert(night.cl_slope < raptor.cl_slope, "a swept faceted wing lifts less per degree")
	assert(night.cd0 > raptor.cd0, "faceting is not free")

	var fast = AERO.new(raptor)
	var slow = AERO.new(night)

	# Same speed, same demand: the Nighthawk must be able to pull less.
	var speed := 155.0
	assert(slow.aerodynamic_load_limit(speed) < fast.aerodynamic_load_limit(speed),
		"at the same speed the Nighthawk can pull less")

	# Wide open, burner included, it must still be left behind.
	assert(slow.thrust_acceleration(1.0, 1.0) < fast.thrust_acceleration(1.0, 1.0),
		"full throttle and full burner still leaves it behind")
	# And its burner must buy it nothing over military power.
	assert(is_equal_approx(slow.thrust_acceleration(1.0, 1.0), slow.thrust_acceleration(1.0, 0.0)),
		"the afterburner must be inert, not merely weak")

	# Turning costs it more. Both at the same lift coefficient, so this is the
	# airframe's drag rather than a difference in how hard each is pulling.
	var alpha := deg_to_rad(12.0)
	var night_drag: float = slow.drag_acceleration(speed, alpha) / slow.lift_acceleration(speed, alpha)
	var raptor_drag: float = fast.drag_acceleration(speed, alpha) / fast.lift_acceleration(speed, alpha)
	assert(night_drag > raptor_drag, "the Nighthawk pays more drag for the same lift")

	# It cannot run: past its divergence speed the wave term is already biting
	# where the Raptor's has not started.
	assert(slow.wave_drag(160.0) > 0.0, "the Nighthawk is over its divergence speed at 160")
	assert(fast.wave_drag(160.0) == 0.0, "the Raptor is not")

	# The envelope has to be an aircraft, not just a worse set of numbers.
	# Top speed is where full thrust stops overcoming drag in level flight.
	var top := 0.0
	var push: float = slow.thrust_acceleration(1.0, 1.0)
	for step in range(40, 400):
		var v := float(step)
		if slow.drag_acceleration(v, slow.trim_alpha(v)) <= push:
			top = v
	assert(top > slow.mush_speed() * 2.0, "it must have a usable band above the mush, got %.0f" % top)
	assert(top < 0.6 * 260.0, "and must not approach the Raptor's 260, got %.0f" % top)

	# It is lift-limited everywhere: its top speed sits below its corner speed,
	# so it never reaches the load limit and never gets its best turn rate.
	# True of the real aircraft, and the reason it turns like a bomber.
	assert(top < night.corner_speed_mps(), "the Nighthawk is lift-limited across its whole envelope")
	assert(slow.aerodynamic_load_limit(top) < night.load_limit_g,
		"so it cannot pull its own structural limit even flat out")
	assert(slow.aerodynamic_load_limit(top) > 4.0, "but it is still an aeroplane, not a bus")

	# The turn that results must be clearly worse than the Raptor's.
	var night_rate: float = slow.aerodynamic_load_limit(top) * 9.80665 / top
	var raptor_rate: float = raptor.load_limit_g * 9.80665 / raptor.corner_speed_mps()
	assert(night_rate < raptor_rate * 0.8, "it must turn markedly worse, not marginally")

	print("NIGHTHAWK_AIRFRAME_TEST_PASS")
	quit()
