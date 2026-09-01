class_name LauncherLayout
extends RefCounted

const SURFERS_REGION := "au_qld_surfers"


static func positions_for(region_id: String) -> PackedVector2Array:
	if region_id != SURFERS_REGION:
		return PackedVector2Array()
	return PackedVector2Array([
		Vector2(-20.0, -900.0),
		Vector2(-10.0, -700.0),
		Vector2(10.0, -500.0),
		Vector2(45.0, -300.0),
		Vector2(60.0, -100.0),
		Vector2(65.0, 100.0),
		Vector2(70.0, 300.0),
		Vector2(85.0, 500.0),
		Vector2(110.0, 700.0),
		Vector2(140.0, 900.0),
	])
