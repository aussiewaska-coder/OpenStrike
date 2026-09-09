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


static var _billow: ImageTexture

## Overlapping soft lobes approximate a shaded smoke volume on a small sprite.
## Generated once; rotation and scale vary independently per emitted puff.
static func smoke_billow() -> ImageTexture:
	if _billow != null:
		return _billow
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	var lobes: Array[Vector3] = [Vector3(-0.23, -0.12, 0.52), Vector3(0.24, -0.2, 0.45), Vector3(0.05, 0.26, 0.49), Vector3(-0.3, 0.26, 0.34), Vector3(0.34, 0.21, 0.32)]
	for y in 96:
		for x in 96:
			var uv := Vector2(x / 95.0, y / 95.0) * 2.0 - Vector2.ONE
			var density := 0.0
			var light := 0.0
			for lobe in lobes:
				var local := (uv - Vector2(lobe.x, lobe.y)) / lobe.z
				var radial := local.length_squared()
				if radial >= 1.0:
					continue
				var thickness := sqrt(1.0 - radial)
				var contribution := smoothstep(0.0, 0.55, thickness) * thickness
				density += contribution
				light += contribution * clampf(0.55 + thickness * 0.35 - local.y * 0.22 - local.x * 0.12, 0.25, 1.0)
			var shade := light / maxf(density, 0.001)
			image.set_pixel(x, y, Color(shade, shade, shade, 1.0 - exp(-density * 2.2)))
	image.generate_mipmaps()
	_billow = ImageTexture.create_from_image(image)
	return _billow
