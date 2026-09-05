extends SceneTree

## The Raptor's coefficients, asserted as literals.
##
## These lived as constants in aero_model.gd until they moved onto a profile so
## a second aircraft could hold different ones. This test is what makes that a
## move rather than a retune: the numbers are spelled out here, so nothing can
## drift without a failure. The reasoning behind each one is still in
## aero_model.gd, beside the formula that uses it.

const AIRFRAME := preload("res://scripts/jet/airframe.gd")
const AERO := preload("res://scripts/jet/aero_model.gd")

func _init(): call_deferred("_run")

func _run():
	var raptor = AIRFRAME.raptor()
	assert(raptor.display_name == "F-22 RAPTOR")
	assert(raptor.cl_slope == 4.6, "cl_slope")
	assert(raptor.stall_alpha_degrees == 32.0, "stall alpha")
	assert(raptor.cl_decay_degrees == 45.0, "cl decay")
	assert(raptor.post_stall_alpha_degrees == 55.0, "post stall alpha")
	assert(raptor.cd0 == 0.067962, "cd0")
	assert(raptor.k_induced == 0.055, "k induced")
	assert(raptor.cd_wave == 0.076438, "cd wave")
	assert(raptor.drag_divergence_mps == 180.0, "drag divergence")
	assert(raptor.cd_stalled == 1.10, "cd stalled")
	assert(raptor.cd_stall_full_degrees == 70.0, "cd stall full")
	assert(raptor.aero_authority == 0.00190657, "aero authority")
	assert(raptor.side_force_coefficient == 0.75, "side force")
	assert(raptor.load_limit_g == 9.0, "load limit")
	assert(raptor.thrust_military_g == 0.55, "military thrust")
	assert(raptor.thrust_afterburner_g == 1.10, "afterburner thrust")
	assert(raptor.thrust_idle_g == 0.05, "idle thrust")
	assert(raptor.control_authority_floor == 0.10, "authority floor")
	assert(raptor.thrust_vector_authority == 0.38, "vector authority")

	# CL_MAX was written as CL_SLOPE * 0.55850536, the radian value of 32
	# degrees spelled out. deg_to_rad must reach the same place.
	assert(is_equal_approx(raptor.cl_max(), 4.6 * 0.55850536), "cl_max derivation")
	# Corner speed is where aerodynamic_load_limit() reaches the load limit.
	var aero = AERO.new(raptor)
	assert(is_equal_approx(aero.aerodynamic_load_limit(raptor.corner_speed_mps()), raptor.load_limit_g),
		"corner speed must be where the wing reaches the load limit")
	# Constructed with no argument, it is still the Raptor.
	assert(AERO.new().airframe.cl_slope == raptor.cl_slope, "the default airframe is the Raptor")
	print("AIRFRAME_TEST_PASS")
	quit()
