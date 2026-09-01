extends Resource

# Damage carried by the round rather than baked into building code
# (spec section 49). A 30 mm impact is a direct hit, not a small bomb.

@export var direct_damage := 34.0
@export var structural_damage := 18.0
@export var penetration_class := 2
@export var impact_energy_scale := 1.0
@export var blast_radius := 0.0
@export var incendiary_probability := 0.04
