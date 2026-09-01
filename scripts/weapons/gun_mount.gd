extends Node3D

# HelicopterAnchor -> HeroHelicopter -> GunPivotYaw -> GunPivotPitch -> MuzzlePoint
#
# The imported AH-64D GLB is three merged static meshes with no bones and no
# separate cannon geometry, so the M230 assembly is built procedurally here and
# hung under the visual airframe. Recoil shake lives on a separate visual node
# so it can never move the logical muzzle the ballistics read.

const BARREL_LENGTH := 2.05
const RECOIL_TRAVEL := 0.16

# Fallback only. The airframe GLB is not to scale and the render size differs
# between theatres, so the mount measures the visual's bounds and derives the
# chin position from them; this is used only when nothing can be measured.
const FALLBACK_MOUNT_OFFSET := Vector3(6.5, -1.55, 0.0)
# Fraction of the nose extent to sit back from the tip, and of the hull depth to
# hang below the belly.
const NOSE_FRACTION := 0.66
const BELLY_DROP := 0.12

var yaw_pivot: Node3D
var pitch_pivot: Node3D
var muzzle_point: Marker3D

var _recoil_visual: Node3D
var _recoil_offset := 0.0
var _spin := 0.0


func _ready() -> void:
	var parent_node := get_parent() as Node3D
	var parent_scale := 1.0
	if parent_node != null and absf(parent_node.scale.x) > 0.0001:
		parent_scale = parent_node.scale.x
	# Cancel the airframe's scale so the gun geometry below is authored in world
	# units. Note this node's own `position` stays in the parent's local space.
	scale = Vector3.ONE / parent_scale
	position = _measure_mount_offset(parent_node, parent_scale)
	_build()


## The chin gun belongs under the forward fuselage. Measuring beats a constant:
## the GLB is not to scale, and how large it renders is a tuning value that
## differs between theatres. Returns an offset in the parent's local space.
func _measure_mount_offset(parent_node: Node3D, parent_scale: float) -> Vector3:
	if parent_node == null:
		return FALLBACK_MOUNT_OFFSET / parent_scale
	var bounds := AABB()
	var found := false
	for child in parent_node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance == null:
			continue
		var local: AABB = parent_node.global_transform.affine_inverse() * (
			instance.global_transform * instance.get_aabb()
		)
		bounds = local if not found else bounds.merge(local)
		found = true
	if not found or bounds.size.is_zero_approx():
		return FALLBACK_MOUNT_OFFSET / parent_scale
	# Nose is local +X. Sit back from the tip, and hang just under the belly.
	var nose_x: float = bounds.position.x + bounds.size.x
	var belly_y: float = bounds.position.y
	return Vector3(nose_x * NOSE_FRACTION, belly_y + bounds.size.y * BELLY_DROP, 0.0)


func _build() -> void:
	yaw_pivot = Node3D.new()
	yaw_pivot.name = "GunPivotYaw"
	add_child(yaw_pivot)

	pitch_pivot = Node3D.new()
	pitch_pivot.name = "GunPivotPitch"
	yaw_pivot.add_child(pitch_pivot)

	_recoil_visual = Node3D.new()
	_recoil_visual.name = "RecoilVisual"
	pitch_pivot.add_child(_recoil_visual)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.16, 0.17, 0.18)
	metal.metallic = 0.75
	metal.roughness = 0.42

	var receiver := MeshInstance3D.new()
	receiver.name = "Receiver"
	var receiver_mesh := BoxMesh.new()
	receiver_mesh.size = Vector3(1.15, 0.62, 0.66)
	receiver.mesh = receiver_mesh
	receiver.material_override = metal
	_recoil_visual.add_child(receiver)

	var barrel := MeshInstance3D.new()
	barrel.name = "Barrel"
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.075
	barrel_mesh.bottom_radius = 0.095
	barrel_mesh.height = BARREL_LENGTH
	barrel_mesh.radial_segments = 10
	barrel.mesh = barrel_mesh
	# CylinderMesh runs along +Y; the gun fires along +X.
	barrel.rotation_degrees = Vector3(0.0, 0.0, -90.0)
	barrel.position = Vector3(BARREL_LENGTH * 0.5 + 0.4, 0.0, 0.0)
	barrel.material_override = metal
	_recoil_visual.add_child(barrel)

	muzzle_point = Marker3D.new()
	muzzle_point.name = "MuzzlePoint"
	muzzle_point.position = Vector3(BARREL_LENGTH + 0.45, 0.0, 0.0)
	# Logical, not visual: parented to the pitch pivot so recoil never shifts it.
	pitch_pivot.add_child(muzzle_point)


func apply_aim(yaw_degrees: float, pitch_degrees: float) -> void:
	if yaw_pivot == null:
		return
	yaw_pivot.rotation.y = deg_to_rad(yaw_degrees)
	pitch_pivot.rotation.z = deg_to_rad(pitch_degrees)


func kick() -> void:
	_recoil_offset = RECOIL_TRAVEL


func _process(delta: float) -> void:
	if _recoil_visual == null:
		return
	_recoil_offset = move_toward(_recoil_offset, 0.0, RECOIL_TRAVEL * 9.0 * delta)
	_spin = fmod(_spin + delta * 26.0, TAU)
	_recoil_visual.position.x = -_recoil_offset
	_recoil_visual.rotation.x = _spin if _recoil_offset > 0.001 else 0.0


func get_muzzle_transform() -> Transform3D:
	if muzzle_point == null:
		return global_transform
	return muzzle_point.global_transform


func get_muzzle_direction() -> Vector3:
	# The whole airframe convention is nose = local +X, and the gun inherits it.
	return get_muzzle_transform().basis.x.normalized()
