extends Resource

# Single source of truth for 30 mm behaviour (spec section 75). The HUD pipper
# and the live rounds both read this; they must never drift apart.

@export var muzzle_velocity := 805.0
@export var drag_per_second := 0.08
@export var gravity := 9.80665
@export var maximum_range := 4000.0
@export var maximum_flight_seconds := 20.0
# Shared by prediction and live simulation. Tighter than the sight's original
# 0.05 s, which put 40 m between samples - too coarse to place a round on a
# facade (spec section 16). Collision is a swept segment either way.
@export var simulation_step := 0.02

@export_group("Fire Control")
@export var rate_of_fire_rpm := 625.0
@export var ammo_capacity := 1200
@export var tracer_interval := 3
@export var maximum_rounds_per_frame := 4

@export_group("Dispersion")
@export var base_dispersion_mrad := 2.2
@export var movement_dispersion_multiplier := 0.9
@export var high_rate_dispersion_multiplier := 0.55
@export var turret_limit_dispersion_multiplier := 1.8


func shot_interval() -> float:
	return 60.0 / maxf(rate_of_fire_rpm, 1.0)
