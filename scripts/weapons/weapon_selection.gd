extends RefCounted

## Which weapon the trigger belongs to. Deliberately ignorant of the weapons
## themselves: adding phase 3's guided missiles means adding one enum entry.
##
## Selection gates rather than rebinds. The cannon keeps L3 and the rockets keep
## L1, and the selector decides which one is live, so a wrong selection shows up
## as a weapon that will not fire rather than as a trigger that does nothing.

signal changed(weapon: int)

enum Weapon {CANNON, ROCKETS}

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
	return "UNKNOWN"
