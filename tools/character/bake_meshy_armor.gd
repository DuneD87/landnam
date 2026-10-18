extends SceneTree

## Builds the equipable armour fitted by tools/character/blender/fit_meshy_armor.py:
## per piece its textures, its skinned mesh (the garment and, if it has one,
## its lining, each with its material) and an
## equipable scene, a MeshItem with the piece's ItemData (ITEMS/<id>.tres,
## which must exist), laid out like the player's other armour. The mesh is in
## the space of the player scan's skin and uses that Skin, so ArmorFit carries
## it from the scan onto each body as it does every armour.
##
##   godot --headless --path . --script res://tools/character/bake_meshy_armor.gd -- <fit output dir> [piece ...]
##
## A piece whose textures are not there yet only gets them (and their import
## settings): import them (godot --headless --import) and run it again.
##
## A skirt that hangs from the skirt's bones (SkirtBones) gets SKIRT_SKIN: the
## scan's Skin with their binds, from their rest on the character's skeleton.

const SKIN := "res://models/player/xavivar/firstage_human_male_player_skin.tres"
const SKIRT_SKIN := "res://models/player/xavivar/firstage_human_male_player_skirt_skin.tres"
const MODEL := "res://scenes/character/character_model.tscn"
const MODELS := "res://models/equipable/stone_age/"
const SCENES := "res://scenes/items/armor/stone_age/"
const ITEMS := "res://data/items/Armor/StoneAge/"
const MESH_ITEM := "res://scripts/items/mesh_item.gd"
## Side of each map, and its JPEG quality.
const MAPS := {albedo = [2048, 0.9], normal = [2048, 0.95], roughness = [1024, 0.9]}
## Meshy's roughness (0.6-0.7) shines like latex on fur and rawhide: it is
## squeezed into this range, keeping its pattern.
const ROUGHNESS_RANGE := Vector2(0.8, 1.0)
## Less shine and a softer relief than Meshy's maps, which glint on every tuft.
const SPECULAR := 0.25
const NORMAL_SCALE := 0.7


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source: String = args[0]
	var only := args.slice(1)
	var skins := {false: load(SKIN) as Skin, true: _skirt_skin(load(SKIN))}
	DirAccess.make_dir_recursive_absolute(MODELS)
	DirAccess.make_dir_recursive_absolute(SCENES)
	var waiting := []
	for file in DirAccess.get_files_at(source):
		if file.get_extension() != "json":
			continue
		var id := file.get_basename()
		if not only.is_empty() and id not in only:
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join(file)))
		# The scan dump (body.json) can share the folder.
		if not data.has("textures"):
			continue
		if not _textures(id, data.textures):
			waiting.append(id)
			continue
		var skin: Skin = skins[_hangs(data)]
		var binds := {}
		for b in skin.get_bind_count():
			binds[skin.get_bind_name(b)] = b
		var mesh := _mesh(id, data, binds)
		var path := MODELS + id + ".res"
		if ResourceSaver.save(mesh, path) != OK:
			push_error("Could not save " + path)
			continue
		_scene(id, load(path), skin)
	if not waiting.is_empty():
		print("Textures written for %s: import them (godot --headless --import) and run this again." % ", ".join(waiting))
	quit()


## The scan's Skin with the skirt's bones, saved as SKIRT_SKIN. A bind takes
## a vertex from the skin's space to its bone's; the scan's all do it with
## their bone at rest, so the skin's space is where the hips' bind puts it.
func _skirt_skin(skin: Skin) -> Skin:
	var model: Node3D = load(MODEL).instantiate()
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var hips := skeleton.find_bone(SkirtBones.HIPS)
	var to_skeleton := Transform3D.IDENTITY
	for b in skin.get_bind_count():
		if skin.get_bind_name(b) == SkirtBones.HIPS:
			to_skeleton = BodyMeasurements.rest_globals(skeleton)[hips] * skin.get_bind_pose(b)
	var result: Skin = skin.duplicate()
	var rests := SkirtBones.rests(skeleton)
	for name: StringName in rests:
		result.add_named_bind(name, (rests[name][1] as Transform3D).affine_inverse() * to_skeleton)
	model.free()
	if ResourceSaver.save(result, SKIRT_SKIN) != OK:
		push_error("Could not save " + SKIRT_SKIN)
	return load(SKIRT_SKIN)


## Whether the piece hangs from the skirt's bones.
static func _hangs(data: Dictionary) -> bool:
	for surface: Dictionary in data.get("surfaces", [data]):
		var weights: Array = surface.weights
		var influences: Array = surface.influences
		for k in influences.size():
			if weights[k] > 0.0 and String(data.bones[int(influences[k])]).begins_with(SkirtBones.PREFIX):
				return true
	return false


## Writes the piece's maps if they are not there; whether they are imported.
func _textures(id: String, maps: Dictionary) -> bool:
	var ready := true
	for kind in MAPS:
		var path := MODELS + "%s_%s.jpg" % [id, kind]
		if ResourceLoader.exists(path):
			continue
		ready = false
		if FileAccess.file_exists(path):
			continue
		var image := Image.load_from_file(maps[kind])
		var size: int = MAPS[kind][0]
		if image.get_width() != size:
			image.resize(size, size, Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGB8)
		if kind == "roughness":
			for y in image.get_height():
				for x in image.get_width():
					var r := lerpf(ROUGHNESS_RANGE.x, ROUGHNESS_RANGE.y, image.get_pixel(x, y).r)
					image.set_pixel(x, y, Color(r, r, r))
		image.save_jpg(ProjectSettings.globalize_path(path), MAPS[kind][1])
		var options := ConfigFile.new()
		options.set_value("remap", "importer", "texture")
		options.set_value("remap", "type", "CompressedTexture2D")
		options.set_value("params", "compress/mode", 2)
		options.set_value("params", "compress/normal_map", 1 if kind == "normal" else 0)
		options.set_value("params", "mipmaps/generate", true)
		options.save(path + ".import")
	return ready


func _mesh(id: String, data: Dictionary, binds: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# The garment first, then its lining (a plain colour), if it has one.
	for surface: Dictionary in data.get("surfaces", [data]):
		var arrays := _arrays(surface, data.bones, binds)
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			var tool := SurfaceTool.new()
			tool.create_from_arrays(arrays)
			tool.generate_tangents()
			arrays = tool.commit_to_arrays()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var index := mesh.get_surface_count() - 1
		mesh.surface_set_material(index, _lining(id, surface.color) if surface.has("color") else _material(id))
	mesh.resource_name = id
	return mesh


func _arrays(surface: Dictionary, names: Array, binds: Dictionary) -> Array:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var p: Array = surface.positions
	var n: Array = surface.normals
	for i in p.size() / 3:
		positions.append(Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]))
		normals.append(Vector3(n[i * 3], n[i * 3 + 1], n[i * 3 + 2]))
	var bones := PackedInt32Array()
	var weights: Array = surface.weights
	var influences: Array = surface.influences
	for k in influences.size():
		# An empty influence may name a bone the skin has no bind for.
		bones.append(binds.get(StringName(names[int(influences[k])]), 0) if weights[k] <= 0.0
				else binds[StringName(names[int(influences[k])])])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	if surface.has("uvs"):
		var uvs := PackedVector2Array()
		var t: Array = surface.uvs
		for i in t.size() / 2:
			uvs.append(Vector2(t[i * 2], t[i * 2 + 1]))
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array(surface.weights)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(surface.indices)
	return arrays


## The lining: matte, of the garment's colour.
func _lining(id: String, color: Array) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = id + "_lining"
	material.albedo_color = Color(color[0], color[1], color[2])
	material.roughness = 1.0
	material.metallic_specular = SPECULAR
	return material


func _material(id: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = id
	# Meshy's garments are shells with open edges and loose flaps.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = load(MODELS + id + "_albedo.jpg")
	material.normal_enabled = true
	material.normal_texture = load(MODELS + id + "_normal.jpg")
	material.normal_scale = NORMAL_SCALE
	material.metallic_specular = SPECULAR
	material.roughness = 1.0
	material.roughness_texture = load(MODELS + id + "_roughness.jpg")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return material


func _scene(id: String, mesh: ArrayMesh, skin: Skin) -> void:
	var root := MeshInstance3D.new()
	root.name = id
	root.mesh = mesh
	root.skin = skin
	root.set_script(load(MESH_ITEM))
	root.set("item_data", load(ITEMS + id + ".tres"))
	var scene := PackedScene.new()
	scene.pack(root)
	var path := SCENES + id + "_equipable.tscn"
	if ResourceSaver.save(scene, path) != OK:
		push_error("Could not save " + path)
	else:
		print("%s: %d vertices -> %s" % [id, mesh.surface_get_array_len(0), path])
	root.free()
