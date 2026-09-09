extends SceneTree
const HEROES = preload("res://scripts/entities/hero_towers.gd")
class Terrain:
	extends Node
	func world_from_coordinate(_lat: float, _lon: float) -> Vector2: return Vector2.ZERO
func _init(): call_deferred("run")
func run():
	var terrain = Terrain.new()
	root.add_child(terrain)
	var heroes = HEROES.new()
	root.add_child(heroes)
	heroes.populate(HEROES.CORRIDOR_REGION, terrain)
	var failed = false
	for model in heroes._instances:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var arrays = mi.mesh.surface_get_arrays(s)
				var normals = arrays[Mesh.ARRAY_NORMAL]
				if normals == null or normals.size() != arrays[Mesh.ARRAY_VERTEX].size():
					push_error("%s has no lighting normals" % model.name)
					failed = true
				else:
					var usable = 0
					for normal in normals:
						if normal.length() > 0.99: usable += 1
					if usable < normals.size() * 0.95:
						push_error("%s has degenerate lighting normals" % model.name)
						failed = true
				var mat = mi.get_active_material(s)
				if not mat is ShaderMaterial or mat.get_shader_parameter("facade") == null:
					push_error("%s needs its textured day/night facade material" % model.name)
					failed = true
				else:
					var source = load(HEROES.layout_for(HEROES.CORRIDOR_REGION)[heroes._instances.find(model)]["scene"]).instantiate()
					var original = source.find_children("*", "MeshInstance3D", true, false)[0]
					if mat.get_shader_parameter("facade") != original.get_active_material(s).albedo_texture:
						push_error("%s lost its original facade texture" % model.name)
						failed = true
					if arrays[Mesh.ARRAY_TEX_UV] != original.mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]:
						push_error("%s changed its facade UVs" % model.name)
						failed = true
					source.free()
	heroes.free()
	terrain.free()
	if not failed: print("HERO_TOWER_MATERIALS_TEST_PASS")
	quit(1 if failed else 0)
