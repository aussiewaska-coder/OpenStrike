extends RefCounted

## One aircraft's numbers, in one place.
##
## These were constants in aero_model.gd, which is where the reasoning for each
## of them still lives, at length. They moved here so a second aircraft can hold
## different ones; the formulas that consume them did not change, because they
## are generic aerodynamics and only the coefficients are aircraft-specific.

class_name Airframe

var display_name := "F-22 RAPTOR"

# Lift curve
var cl_slope := 4.6
var stall_alpha_degrees := 32.0
var cl_decay_degrees := 45.0
var post_stall_alpha_degrees := 55.0

# Drag polar
var cd0 := 0.067962
var k_induced := 0.055
var cd_wave := 0.076438
var drag_divergence_mps := 180.0
var cd_stalled := 1.10
var cd_stall_full_degrees := 70.0

# Airframe
var aero_authority := 0.00190657
var side_force_coefficient := 0.75
var load_limit_g := 9.0

# Thrust, as a multiple of gravity
var thrust_military_g := 0.55
var thrust_afterburner_g := 1.10
var thrust_idle_g := 0.05

# Control
var control_authority_floor := 0.10
var thrust_vector_authority := 0.38


## Peak lift coefficient, at the stall angle. aero_model.gd wrote this as
## CL_SLOPE * 0.55850536, the radian value of 32 degrees spelled out.
func cl_max() -> float:
	return cl_slope * deg_to_rad(stall_alpha_degrees)


## Where the wing's lift limit and the load limit cross: best turn rate, and
## the speed the whole model is pinned to. Derived, not chosen, so moving the
## stall angle moves this with it.
func corner_speed_mps() -> float:
	return sqrt(load_limit_g * 9.80665 / (aero_authority * cl_max()))


static func raptor() -> Airframe:
	return Airframe.new()
