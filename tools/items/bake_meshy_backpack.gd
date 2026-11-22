extends SceneTree

## Hornea las mochilas hechas con Meshy (tools/character/blender/fit_meshy_backpack.py): sus
## texturas, su malla (models/equipable/back/<id>.res) y su escena (scenes/items/equipment/<id>.tscn),
## que BackEquipment cuelga de la espalda como la mochila de pieles. El ajuste les quita las correas
## de Meshy, que colgaban como de un clavo; aquí se les ponen otras que rodean los hombros, por donde
## van las de la mochila de pieles (hide_backpack_visual.gd), con el cuero de las suyas
## ("strap_uv"). En metros; Y arriba, +Z hacia la espalda del portador.
##   godot --headless --path . --script res://tools/items/bake_meshy_backpack.gd -- <dir del ajuste> [id ...]
## Si sus texturas aún no están, solo las escribe: importarlas (godot --headless --import) y volver
## a pasarlo.

const MODELS := "res://models/equipable/back/"
const SCENES := "res://scenes/items/equipment/"
## Tamaño y calidad JPG de cada mapa: una mochila no necesita los de una armadura.
const MAPS := {albedo = [1024, 0.9], normal = [1024, 0.95], roughness = [512, 0.9], metallic = [512, 0.9]}
const NORMAL_SCALE := 0.8
const SPECULAR := 0.3
## Cada correa, de abajo arriba: desde el fondo (STRAP_BOTTOM sobre él), por el costado bajo el
## brazo, por delante del pecho, por encima del hombro entre el cuello y el deltoides y de vuelta a la
## boca de la mochila. La espalda queda a unos 0,125 m del origen (BackEquipment) y el pecho, unos
## 0,24 m más allá.
const STRAP_BOTTOM := 0.065
const STRAP := [Vector3(0.11, 0.0, 0.08), Vector3(0.15, -0.07, 0.25), Vector3(0.14, 0.07, 0.345),
	Vector3(0.13, 0.175, 0.3), Vector3(0.115, 0.215, 0.185), Vector3(0.095, 0.17, 0.07)]
## Medio ancho y medio grueso de la correa (m), y lados de su sección.
const STRAP_SIZE := Vector2(0.018, 0.0045)
const STRAP_SEGMENTS := 8


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Falta el directorio del ajuste")
		quit(1)
		return
	var source: String = args[0]
	var only := args.slice(1)
	DirAccess.make_dir_recursive_absolute(MODELS)
	var waiting := []
	for file in DirAccess.get_files_at(source):
		if file.get_extension() != "json":
			continue
		var id := file.get_basename()
		if not only.is_empty() and id not in only:
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join(file)))
		if not _textures(id, data.textures):
			waiting.append(id)
			continue
		var mesh := _mesh(id, data)
		var path := MODELS + id + ".res"
		if ResourceSaver.save(mesh, path) != OK:
			push_error("No se pudo guardar " + path)
			continue
		_scene(id, load(path))
		print("%s: %s" % [id, mesh.get_aabb()])
	if not waiting.is_empty():
		print("Texturas escritas para %s: importarlas (godot --headless --import) y volver a pasarlo." % ", ".join(waiting))
	quit()


func _textures(id: String, maps: Dictionary) -> bool:
	var ready := true
	for kind in MAPS:
		if not maps.has(kind):
			continue
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
		image.save_jpg(ProjectSettings.globalize_path(path), MAPS[kind][1])
		var options := ConfigFile.new()
		options.set_value("remap", "importer", "texture")
		options.set_value("remap", "type", "CompressedTexture2D")
		options.set_value("params", "compress/mode", 2)
		options.set_value("params", "compress/normal_map", 1 if kind == "normal" else 0)
		options.set_value("params", "mipmaps/generate", true)
		options.save(path + ".import")
	return ready


func _mesh(id: String, data: Dictionary) -> ArrayMesh:
	var material := _material(id)
	var tool := SurfaceTool.new()
	tool.create_from_arrays(_arrays(data))
	tool.generate_tangents()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tool.commit_to_arrays())
	mesh.surface_set_material(0, material)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _straps(data))
	mesh.surface_set_material(1, material)
	mesh.resource_name = id
	MeshLods.add_to(mesh)
	return mesh


func _arrays(data: Dictionary) -> Array:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var p: Array = data.positions
	var n: Array = data.normals
	var t: Array = data.uvs
	for i in p.size() / 3:
		positions.append(Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]))
		normals.append(Vector3(n[i * 3], n[i * 3 + 1], n[i * 3 + 2]))
		uvs.append(Vector2(t[i * 2], t[i * 2 + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(data.indices)
	return arrays


## Las dos correas, con las UV en el trozo de cuero de las de Meshy.
func _straps(data: Dictionary) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		var points := PackedVector3Array()
		for k in STRAP.size():
			var point: Vector3 = STRAP[k]
			if k == 0:
				point.y = float(data.bottom) + STRAP_BOTTOM
			points.append(Vector3(point.x * side, point.y, point.z))
		var curve := _curve(points)
		var radii := PackedVector2Array()
		for i in curve.size():
			radii.append(STRAP_SIZE * Vector2(1.0 + 0.15 * sin(PI * i / (curve.size() - 1.0)), 1.0))
		ProcMesh.tube(st, curve, radii, STRAP_SEGMENTS)
	st.generate_normals()
	var arrays := st.commit_to_arrays()
	var patch: Array = data.strap_uv
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for i in uvs.size():
		uvs[i] = Vector2(lerpf(patch[0], patch[2], uvs[i].x), lerpf(patch[1], patch[3], fposmod(uvs[i].y, 1.0)))
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var tool := SurfaceTool.new()
	tool.create_from_arrays(arrays)
	tool.generate_tangents()
	return tool.commit_to_arrays()


## Catmull-Rom por los puntos, seis tramos entre cada dos.
static func _curve(points: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in points.size() - 1:
		var a := points[maxi(0, i - 1)]
		var b := points[i]
		var c := points[i + 1]
		var d := points[mini(points.size() - 1, i + 2)]
		for j in 6:
			result.append(b.cubic_interpolate(c, a, d, j / 6.0))
	result.append(points[-1])
	return result


func _material(id: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = id
	# Meshy deja bordes abiertos en solapas y bolsillos.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = load(MODELS + id + "_albedo.jpg")
	material.normal_enabled = true
	material.normal_texture = load(MODELS + id + "_normal.jpg")
	material.normal_scale = NORMAL_SCALE
	material.metallic_specular = SPECULAR
	material.roughness = 1.0
	material.roughness_texture = load(MODELS + id + "_roughness.jpg")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if ResourceLoader.exists(MODELS + id + "_metallic.jpg"):
		# Las hebillas.
		material.metallic = 1.0
		material.metallic_texture = load(MODELS + id + "_metallic.jpg")
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return material


func _scene(id: String, mesh: ArrayMesh) -> void:
	var root := Node3D.new()
	root.name = id.to_pascal_case()
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	root.add_child(instance)
	instance.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	var path := SCENES + id + ".tscn"
	if ResourceSaver.save(scene, path) != OK:
		push_error("No se pudo guardar " + path)
	root.free()
