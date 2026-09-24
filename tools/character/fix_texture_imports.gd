extends SceneTree

## Import settings for the human's textures, after the editor has created
## their .import files (godot --headless --editor --quit):
##
##   godot --headless --path . --script res://tools/character/fix_texture_imports.gd
##
## Everything gets VRAM compression and mipmaps (hair without mipmaps
## flickers); normal maps are imported as such. Run the editor once more so
## the textures are reimported.

const ROOT := "res://textures/character/human"


func _initialize() -> void:
	var changed := 0
	for path in _imports(ROOT):
		var config := ConfigFile.new()
		if config.load(path) != OK:
			continue
		var normal := path.get_file().begins_with("normal_") or path.get_file().contains("_normal.")
		var wanted := {"compress/mode": 2, "mipmaps/generate": true, "detect_3d/compress_to": 0,
				"compress/normal_map": 1 if normal else 0}
		var dirty := false
		for key in wanted:
			if config.get_value("params", key, null) != wanted[key]:
				config.set_value("params", key, wanted[key])
				dirty = true
		if dirty:
			config.save(path)
			changed += 1
	print("Updated %d import files" % changed)
	quit()


func _imports(folder: String) -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(folder)
	if dir == null:
		return result
	for file in dir.get_files():
		if file.ends_with(".import"):
			result.append(folder.path_join(file))
	for sub in dir.get_directories():
		result.append_array(_imports(folder.path_join(sub)))
	return result
