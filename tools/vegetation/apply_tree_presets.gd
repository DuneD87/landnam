extends SceneTree

## Escribe los presets de tools/vegetation/tree_presets.gd en las escenas de árbol:
## forma Branching, semilla, parámetros y materiales (corteza y follaje nuevos).
##   godot --headless --path . -s res://tools/vegetation/apply_tree_presets.gd [-- --only=olive_01]

const Presets = preload("res://tools/vegetation/tree_presets.gd")
const TREE_DIR := "res://scenes/planet/planet_items/vegetation/trees/"


func _initialize() -> void:
	var only: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7).split(",")
	var failures := 0
	for scene_name in Presets.SCENES:
		if not only.is_empty() and scene_name not in only:
			continue
		var path: String = TREE_DIR + scene_name + ".tscn"
		var root: Node = load(path).instantiate()
		var tree: Tree3D = null
		for child in root.get_children():
			if child is Tree3D:
				tree = child
		if tree == null:
			push_error("Sin Tree3D: " + path)
			failures += 1
			root.free()
			continue
		Presets.configure(tree, scene_name)
		var packed := PackedScene.new()
		var err := packed.pack(root)
		if err == OK:
			err = ResourceSaver.save(packed, path)
		if err != OK:
			push_error("No se pudo guardar %s: %s" % [path, err])
			failures += 1
		else:
			_strip_null_parameters(path)
			print("TREE PRESET ", path)
		root.free()
	print("APPLY TREE PRESETS: %d failures" % failures)
	quit(1 if failures > 0 else 0)


## En headless el shader no se compila y el guardado escribe "shader_parameter/x = null"
## por cada uniform sin valor: equivale al valor por defecto pero ensucia la escena.
func _strip_null_parameters(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var kept := PackedStringArray()
	for line in text.split("\n"):
		if line.begins_with("shader_parameter/") and line.ends_with(" = null"):
			continue
		kept.append(line)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(kept))
