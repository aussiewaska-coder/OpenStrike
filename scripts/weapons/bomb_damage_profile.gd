extends Resource

## What a bomb does to a building. building_damage_system reads
## `structural_damage` and multiplies a roof strike by 1.35, so 320 puts one
## roof hit at 432 -- past the 420 smoke threshold -- while a facade graze at
## 320 does not. The raid's "building lost" line sits at twice this.

@export var structural_damage := 320.0
