extends Node

## Hornea los atlas de impostor octaédrico de los árboles Branching a partir de sus escenas
## (LOD0 con los materiales de juego). Necesita renderer: no usar --headless.
##   godot --path . res://tools/vegetation/bake_tree_impostors.tscn [-- --only=olive_01]
## Rehornear tras cambiar los presets o las texturas de un árbol. Los caducos hornean también
## el atlas sin hoja (<escena>_bare_*.png).

const Presets = preload("res://tools/vegetation/tree_presets.gd")
const TREE_DIR := "res://scenes/planet/planet_items/vegetation/trees/"


func _ready() -> void:
	var only: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(TreeOctaImpostor.ATLAS_DIR)
	await get_tree().process_frame
	for scene_name in Presets.SCENES:
		if not only.is_empty() and scene_name not in only:
			continue
		var root: Node = load(TREE_DIR + scene_name + ".tscn").instantiate()
		add_child(root)
		var tree: Tree3D = null
		for child in root.get_children():
			if child is Tree3D:
				tree = child
		var lod0: Mesh = tree.bake_lods()[0]
		# Los caducos llevan además el atlas sin hoja del invierno.
		var variants := [false, true] if Presets.is_deciduous(scene_name) else [false]
		for bare in variants:
			var atlases: Dictionary = await TreeOctaImpostor.bake(lod0, self, bare)
			var paths := TreeOctaImpostor.atlas_paths(scene_name, bare)
			atlases.albedo.save_png(paths[0])
			atlases.normal.save_png(paths[1])
			print("IMPOSTOR ", scene_name, " bare" if bare else "", " ", atlases.albedo.get_used_rect())
		root.queue_free()
		await get_tree().process_frame
	print("BAKE TREE IMPOSTORS COMPLETE")
	get_tree().quit()
