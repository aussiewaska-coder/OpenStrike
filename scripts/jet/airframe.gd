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

# Rigging
var scene_path := "res://3dassets/f-22_raptor_-_fighter_jet_-_free.glb"
## Applied to the visual root before anything is measured, so every aircraft
## presents its length on X, its up on Y and its span on Z -- the convention
## aero_model.alpha_beta() documents and _scale_to_reference() depends on.
## The Raptor's GLB already arrives that way, so its basis is identity and it
## is what defines the convention.
var model_basis := Basis.IDENTITY
var reference_wingspan_m := 13.56
var hull_clearance_m := 2.5
## Where the pilot sits, as fractions of the airframe in the engine's
## convention: along the length, and up through it.
var cockpit_seat_fraction := 0.60
var cockpit_eye_height_fraction := 0.80
var cockpit_pitch_degrees := -8.0
## The Raptor's parts have names -- "canopy", "landingon" -- and the
## Nighthawk's are all Object_N, so each model's canopy and gear are found the
## way that model allows.
var parts_are_named := true
## jet_effects.gd partitions the Raptor's trailing wing panels into ailerons
## and hangs plumes off its nozzles. That is Raptor geometry, not a general
## capability, so an aircraft it was not written for opts out.
var has_jet_effects := true


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


## The F-117A Nighthawk.
##
## The Raptor's tuned numbers scaled by the ratio between the two real
## aircraft. aero_model.gd is explicit that its speed envelope is compressed
## and its drag constants are game-feel rather than F-22 numbers, so dropping
## measured F-117 coefficients into it would be a lie dressed as rigour. What
## is preserved instead is the relationship: a subsonic bomber against a
## supercruising fighter, each ratio recorded beside the value it produced.
static func nighthawk() -> Airframe:
	var f := Airframe.new()
	f.display_name = "F-117 NIGHTHAWK"

	# Real thrust-to-weight is 0.47 against the Raptor's 0.82, so 0.57 of it.
	# Two F404s with no reheat, hauling an aircraft that is mostly angles.
	f.thrust_military_g = 0.31
	# There is no afterburner on the airframe at all. Equal values make the
	# burner inert without a branch anywhere in the input path.
	f.thrust_afterburner_g = 0.31
	f.thrust_idle_g = 0.03

	# The real airframe limit, against the Raptor's 9. It is a bomber.
	f.load_limit_g = 6.0

	# Mach 0.92 flat out and no supercruise, so the compressibility rise
	# arrives well below where the Raptor's does and there is no running away.
	f.drag_divergence_mps = 130.0

	# A 67.5-degree swept faceted wing lifts poorly per degree and gives up
	# earlier. No vortex lift to hold on to past the stall, and no nozzles to
	# point the nose with, so the post-stall range is narrow and unrewarding.
	f.cl_slope = 3.6
	f.stall_alpha_degrees = 26.0
	f.cl_decay_degrees = 22.0
	f.post_stall_alpha_degrees = 30.0

	# Faceting is not free: every flat panel that defeats a radar also spoils
	# the airflow over it. More parasite drag than the Raptor carries.
	f.cd0 = 0.082
	f.k_induced = 0.075

	# Lighter wing loading than the Raptor, which would flatter its turn if the
	# lift curve and the thrust were not both against it.
	f.aero_authority = 0.00205

	# No vectoring nozzles. Both triggers stays an airbrake and nothing more.
	f.thrust_vector_authority = 0.0

	f.scene_path = "res://3dassets/f117_nighthawk.glb"
	# The GLB arrives span on X, length on Y and up on Z, so it needs turning
	# onto the Raptor's convention: length on X, up on Y, span on Z. Found by
	# trying every proper rotation and keeping the one that measures 20.24 m
	# long and 3.70 m tall against a real 20.09 by 3.78, rather than by
	# reasoning about which way round Basis takes its arguments.
	f.model_basis = Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(0, 0, 1).cross(Vector3(0, 1, 0)))
	f.reference_wingspan_m = 13.20
	f.hull_clearance_m = 1.6

	# There is no cockpit interior in this model at all: from the seat you see
	# the inside of the canopy facets and the back of the exterior skin, with
	# no seat, panel or consoles. The view is the seat point, the aircraft's
	# own faceted canopy frame, and the drawn helmet HUD.
	f.cockpit_seat_fraction = 0.62
	f.cockpit_eye_height_fraction = 0.72
	f.cockpit_pitch_degrees = -7.0
	f.parts_are_named = false
	f.has_jet_effects = false
	return f
