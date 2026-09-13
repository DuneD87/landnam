extends SceneTree

const FISH := preload("res://scripts/fauna/simple_fish_mesh.gd")

## Bakes SimpleFishMesh.build_mesh() into data/fauna/meshes/fish. Run after editing TYPES:
## godot --headless --path . --script res://tools/fauna/bake_fish_meshes.gd
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/fauna/meshes/fish")
	for kind in FISH.TYPES.size():
		var start := Time.get_ticks_usec()
		var mesh: ArrayMesh = FISH.build_mesh(kind)
		var elapsed := (Time.get_ticks_usec() - start) / 1000.0
		var error := ResourceSaver.save(mesh, "res://data/fauna/meshes/fish/%d.res" % kind, ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			push_error("Cannot bake fish %d" % kind)
			quit(1)
			return
		print("FISH_BAKE kind=%d generation_ms=%.3f" % [kind, elapsed])
	print("FISH_BAKE_DONE")
	quit()
