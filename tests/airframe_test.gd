extends SceneTree

## The Raptor profile must reproduce aero_model.gd's constants exactly. This is
## what makes moving them into a profile a move and not a retune.

const AIRFRAME := preload("res://scripts/jet/airframe.gd")
const AERO := preload("res://scripts/jet/aero_model.gd")

func _init(): call_deferred("_run")

func _run():
	var raptor = AIRFRAME.raptor()
	assert(raptor.cl_slope == AERO.CL_SLOPE, "cl_slope must match")
	assert(raptor.stall_alpha_degrees == AERO.STALL_ALPHA_DEGREES, "stall alpha must match")
	assert(raptor.cl_decay_degrees == AERO.CL_DECAY_DEGREES, "cl decay must match")
	assert(raptor.post_stall_alpha_degrees == AERO.POST_STALL_ALPHA_DEGREES, "post stall must match")
	assert(raptor.cd0 == AERO.CD0, "cd0 must match")
	assert(raptor.k_induced == AERO.K_INDUCED, "k induced must match")
	assert(raptor.cd_wave == AERO.CD_WAVE, "cd wave must match")
	assert(raptor.drag_divergence_mps == AERO.DRAG_DIVERGENCE_MPS, "drag divergence must match")
	assert(raptor.cd_stalled == AERO.CD_STALLED, "cd stalled must match")
	assert(raptor.cd_stall_full_degrees == AERO.CD_STALL_FULL_DEGREES, "cd stall full must match")
	assert(raptor.aero_authority == AERO.AERO_AUTHORITY, "aero authority must match")
	assert(raptor.side_force_coefficient == AERO.SIDE_FORCE_COEFFICIENT, "side force must match")
	assert(raptor.load_limit_g == AERO.LOAD_LIMIT_G, "load limit must match")
	assert(raptor.thrust_military_g == AERO.THRUST_MILITARY_G, "military thrust must match")
	assert(raptor.thrust_afterburner_g == AERO.THRUST_AFTERBURNER_G, "afterburner thrust must match")
	assert(raptor.thrust_idle_g == AERO.THRUST_IDLE_G, "idle thrust must match")
	assert(raptor.control_authority_floor == AERO.CONTROL_AUTHORITY_FLOOR, "authority floor must match")
	assert(raptor.thrust_vector_authority == AERO.THRUST_VECTOR_AUTHORITY, "vector authority must match")
	assert(is_equal_approx(raptor.cl_max(), AERO.CL_MAX), "cl_max must derive the same")
	assert(is_equal_approx(raptor.corner_speed_mps(), AERO.CORNER_SPEED_MPS), "corner speed must derive the same")
	print("AIRFRAME_TEST_PASS")
	quit()
