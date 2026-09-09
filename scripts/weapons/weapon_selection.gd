extends RefCounted

## Which secondary weapon L1 fires. L3 remains the cannon in every selection.
##
## Selection gates rather than rebinds: missile and rocket launchers each
## consult the same state, so one press cannot launch both.

signal changed(weapon: int)

enum Weapon {CANNON, ROCKETS, HEAT, RADAR, GUIDED_BOMB, GROUND_MISSILE}

var current: int = Weapon.CANNON


func cycle() -> int:
	current = (current + 1) % Weapon.size()
	changed.emit(current)
	return current


func name_of(weapon: int) -> String:
	match weapon:
		Weapon.CANNON:
			return "20MM"
		Weapon.ROCKETS:
			return "ROCKETS"
		Weapon.HEAT:
			return "HEAT SEEKER"
		Weapon.RADAR:
			return "RADAR MISSILE"
		Weapon.GUIDED_BOMB:
			return "GUIDED BOMB"
		Weapon.GROUND_MISSILE:
			return "GROUND MISSILE"
	return "UNKNOWN"


static func is_guided(weapon: int) -> bool:
	return weapon in [Weapon.HEAT, Weapon.RADAR, Weapon.GUIDED_BOMB, Weapon.GROUND_MISSILE]


static func is_ground(weapon: int) -> bool:
	return weapon in [Weapon.GUIDED_BOMB, Weapon.GROUND_MISSILE]
