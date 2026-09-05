extends "res://scripts/terrain/streamed_terrain.gd"
var requested := []
func _ready(): set_process(false)
func _apply_memory_budget(): pass
func sample_height_world(_x: float, _z: float) -> float: return 1000.0
func _ensure_chunk_buildings(_chunk: Dictionary): pass
func _request_chunk_detail(_chunk: Dictionary, tier_px: int = 0): requested.append(tier_px)
