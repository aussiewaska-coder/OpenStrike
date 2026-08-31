extends RefCounted

## Maps the single zoom scalar onto camera distance, height and field of view.
##
## At or above `attack_zoom_start` this is the original uniform scaling, so the
## established framing is untouched. Below it the height is compressed harder
## than the distance, sinking the camera from a top-down tactical view toward the
## aircraft's own level, while the field of view widens for forced perspective.

var zoom_min := 0.17
var attack_zoom_start := 0.68
var attack_height_bias := 0.35
var base_fov := 42.0
var attack_fov := 78.0


## 0.0 at the tightest attack zoom, 1.0 at or above the old close limit.
func blend(zoom: float) -> float:
	if attack_zoom_start <= zoom_min:
		return 1.0
	return clampf((zoom - zoom_min) / (attack_zoom_start - zoom_min), 0.0, 1.0)


func distance_multiplier(zoom: float) -> float:
	return zoom


func height_multiplier(zoom: float) -> float:
	return zoom * lerpf(attack_height_bias, 1.0, blend(zoom))


func fov(zoom: float) -> float:
	return lerpf(attack_fov, base_fov, blend(zoom))


## Zoom steps by a ratio rather than a fixed amount: subtracting a constant over
## an 8.5x range would nearly halve the distance in a single press at the tight
## end.
func step(zoom: float, ratio: float, closer: bool, zoom_max: float) -> float:
	var next := zoom * ratio if closer else zoom / ratio
	return clampf(next, zoom_min, zoom_max)
