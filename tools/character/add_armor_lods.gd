extends SceneTree

## Pone LODs (MeshLods) a la armadura ya horneada de models/equipable/stone_age/, sin tocar sus vértices,
## para no tener que volver a hornearla: lo nuevo ya sale con ellos (bake_meshy_armor.gd).
##   godot --headless --path . --script res://tools/character/add_armor_lods.gd [-- pieza ...]

const MODELS := "res://models/equipable/stone_age/"


func _initialize() -> void:
	var only := OS.get_cmdline_user_args()
	var failed := false
	for file in DirAccess.get_files_at(MODELS):
		if not file.ends_with(".res") or (not only.is_empty() and file.get_basename() not in only):
			continue
		var mesh := load(MODELS + file) as ArrayMesh
		if mesh == null:
			continue
		var started := Time.get_ticks_msec()
		var count := MeshLods.add_to(mesh)
		if ResourceSaver.save(mesh) != OK:
			push_error("No se puede guardar " + mesh.resource_path)
			failed = true
			continue
		print("%s: LODs en %d de %d superficies (%d ms)" % [file.get_basename(), count, mesh.get_surface_count(),
			Time.get_ticks_msec() - started])
	quit(1 if failed else 0)
