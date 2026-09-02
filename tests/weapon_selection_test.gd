extends SceneTree

## Selection knows nothing about the weapons themselves -- it is an enum and a
## cycle. Phase 3 adds MISSILES to the same enum and nothing here changes.

const SELECTION := preload("res://scripts/weapons/weapon_selection.gd")


func _init() -> void:
	var selection = SELECTION.new()
	if selection.current != SELECTION.Weapon.CANNON:
		_fail("the gun is the default weapon")

	var seen: Array[int] = []
	for _i in range(SELECTION.Weapon.size()):
		seen.append(selection.current)
		selection.cycle()
	if selection.current != SELECTION.Weapon.CANNON:
		_fail("cycling through every weapon must return to the first")
	if seen.size() != SELECTION.Weapon.size():
		_fail("the cycle must visit every weapon exactly once")
	for weapon in SELECTION.Weapon.values():
		if not seen.has(weapon):
			_fail("the cycle skipped weapon %d" % weapon)
		if selection.name_of(weapon).is_empty():
			_fail("every weapon needs a name for the HUD, %d has none" % weapon)

	# The signal is how the HUD learns, so it must actually fire.
	var fired: Array[int] = []
	selection.changed.connect(func(weapon: int) -> void: fired.append(weapon))
	selection.cycle()
	if fired.size() != 1:
		_fail("cycling must announce the new weapon exactly once, got %d" % fired.size())
	if fired[0] != selection.current:
		_fail("the announced weapon must be the current one")

	print("WEAPON_SELECTION_TEST_PASS")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
