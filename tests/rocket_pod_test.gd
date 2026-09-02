extends SceneTree

## A salvo is a ripple, not a burst: rockets leave one at a time, alternating
## sides. Emptying the pod in a single frame gives one puff of smoke and no
## sense of a salvo at all.

const POD := preload("res://scripts/weapons/rocket_pod.gd")
const SELECTION := preload("res://scripts/weapons/weapon_selection.gd")
const PROJECTILE_MANAGER := preload("res://scripts/weapons/projectile_manager.gd")
const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")


func _init() -> void:
	_ripples_rather_than_bursts()
	_alternates_hardpoints()
	_empties_and_reloads()
	_stays_silent_when_the_gun_is_selected()
	print("ROCKET_POD_TEST_PASS")
	quit()


func _build() -> Node3D:
	var manager = PROJECTILE_MANAGER.new()
	manager.ballistics = BALLISTICS.new()
	var pod = POD.new()
	pod.projectile_manager = manager
	pod.selection = SELECTION.new()
	pod.selection.current = SELECTION.Weapon.ROCKETS
	for index in range(2):
		var hardpoint := Node3D.new()
		hardpoint.position = Vector3(0.0, 0.0, -3.0 if index == 0 else 3.0)
		pod.add_child(hardpoint)
		pod.hardpoints.append(hardpoint)
	return pod


func _ripples_rather_than_bursts() -> void:
	var pod := _build()
	var fired := [0]
	pod.rocket_fired.connect(func(_r, _h) -> void: fired[0] += 1)
	# One long frame. A burst weapon would empty the pod here.
	pod.update(1.0, true)
	if fired[0] == 0:
		_fail("holding the trigger must launch a rocket")
	if fired[0] > 1:
		_fail("a single update must launch one rocket, got %d" % fired[0])

	fired[0] = 0
	var elapsed := 0.0
	while elapsed < POD.RIPPLE_INTERVAL * 3.5:
		pod.update(0.02, true)
		elapsed += 0.02
	if fired[0] < 3 or fired[0] > 4:
		_fail("expected three or four rockets in three and a half intervals, got %d" % fired[0])
	pod.free()


func _alternates_hardpoints() -> void:
	var pod := _build()
	var sides: Array[int] = []
	pod.rocket_fired.connect(func(_r, hardpoint: int) -> void: sides.append(hardpoint))
	for _i in range(4):
		pod.update(POD.RIPPLE_INTERVAL + 0.001, true)
	if sides.size() < 4:
		_fail("expected four launches, got %d" % sides.size())
	for index in range(1, sides.size()):
		if sides[index] == sides[index - 1]:
			_fail("consecutive rockets must leave from opposite hardpoints")
	pod.free()


func _empties_and_reloads() -> void:
	var pod := _build()
	for _i in range(POD.POD_CAPACITY + 2):
		pod.update(POD.RIPPLE_INTERVAL + 0.001, true)
	if pod.rockets_remaining != 0:
		_fail("the pod must empty, %d left" % pod.rockets_remaining)
	if not pod.is_reloading:
		_fail("an empty pod must start reloading on its own")
	if pod.can_fire():
		_fail("a reloading pod must refuse to fire")
	pod.update(POD.RELOAD_SECONDS + 0.1, false)
	if pod.rockets_remaining != POD.POD_CAPACITY:
		_fail("the reload must refill the pod, got %d" % pod.rockets_remaining)
	if pod.is_reloading:
		_fail("the reload must finish")
	pod.free()


func _stays_silent_when_the_gun_is_selected() -> void:
	var pod := _build()
	pod.selection.current = SELECTION.Weapon.CANNON
	var fired := [0]
	pod.rocket_fired.connect(func(_r, _h) -> void: fired[0] += 1)
	for _i in range(5):
		pod.update(POD.RIPPLE_INTERVAL + 0.001, true)
	if fired[0] != 0:
		_fail("rockets must not fire while the gun is selected, got %d" % fired[0])
	pod.free()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
