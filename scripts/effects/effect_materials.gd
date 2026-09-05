extends RefCounted

static var _disc: GradientTexture2D

## A soft radial sprite generated once, shared by smoke, flashes and exhaust.
static func soft_disc() -> GradientTexture2D:
	if _disc != null:
		return _disc
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	_disc = GradientTexture2D.new()
	_disc.width = 64
	_disc.height = 64
	_disc.gradient = gradient
	_disc.fill = GradientTexture2D.FILL_RADIAL
	_disc.fill_from = Vector2(0.5, 0.5)
	_disc.fill_to = Vector2(1.0, 0.5)
	return _disc

static func smoke_ramp() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.65, 1.0])
	gradient.colors = PackedColorArray([Color(0.8, 0.78, 0.72, 0), Color(0.8, 0.78, 0.72, 0.5), Color(0.55, 0.56, 0.58, 0.2), Color(0.55, 0.56, 0.58, 0)])
	return gradient
