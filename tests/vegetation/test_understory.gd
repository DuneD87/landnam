extends SceneTree

const Builder = preload("res://scripts/planet/understory_geometry.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for species in Builder.SPECIES:
		var started: int = Time.get_ticks_usec()
		var meshes: Array = Builder.build(species)
		_check(meshes.size() == 4, "Cuatro LODs: " + species)
		_check(Builder.build(species)[0] == meshes[0], "Mallas compartidas, sin reconstrucción")
		var counts: Array = []
		var previous: int = 1000000
		for mesh in meshes:
			var arrays: Array = mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			_check(indices.size() < previous and indices.size() > 0, "LOD reduce triángulos: " + species)
			previous = indices.size()
			counts.append(indices.size() / 3)
			var valid: bool = vertices.size() == normals.size() and colors.size() == vertices.size()
			for i in vertices.size():
				valid = valid and vertices[i].is_finite() and normals[i].is_finite()
				valid = valid and normals[i].length_squared() > 0.9
				valid = valid and uv2[i].x >= 0.0 and uv2[i].x <= 1.0 and uv2[i].y == 1.0
				valid = valid and colors[i].a == 1.0
			for i in range(0, indices.size(), 3):
				var a: int = indices[i]
				var b: int = indices[i + 1]
				var c: int = indices[i + 2]
				valid = valid and a >= 0 and b >= 0 and c >= 0 and maxi(a, maxi(b, c)) < vertices.size()
				var face: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
				valid = valid and face.length_squared() > 1e-16
				valid = valid and face.dot(normals[a] + normals[b] + normals[c]) <= 0.0000001
			_check(valid, "Geometría, colores y atributos válidos: " + species)
			var custom = arrays[Mesh.ARRAY_CUSTOM0]
			var morph_valid: bool = custom is PackedFloat32Array and custom.size() == vertices.size() * 4
			if morph_valid:
				var level: int = counts.size() - 1
				for i in vertices.size():
					var packed: int = int(custom[i * 4 + 3])
					# Cada pieza conoce el LOD de su malla y sigue al menos hasta él.
					morph_valid = morph_valid and packed >> 2 == level and (packed & 3) >= level
			_check(morph_valid, "Datos de morph por vértice: " + species)
			_check(mesh.get_aabb().size.y > 0.25 and mesh.get_aabb().size.y < 2.0, "Escala en metros: " + species)
		var material: ShaderMaterial = meshes[0].surface_get_material(0)
		_check(material.get_shader_parameter("lod_width_growth") == Builder.WIDTH_GROWTH, "Morph con el ensanchado de la geometría")
		_check(counts[0] < 6000, "Presupuesto cercano: " + species)
		_check(counts[3] < counts[0] * 0.35, "Presupuesto lejano: " + species)
		var prefab: Node = load("res://scenes/planet/planet_items/vegetation/understory/%s.tscn" % species).instantiate()
		_check(prefab.get_child(0).mesh == meshes[0], "Prefab carga su especie sin entrar al árbol")
		prefab.free()
		print("UNDERSTORY ", species, " triangles=", counts, " build_ms=", (Time.get_ticks_usec() - started) / 1000.0)
	await _integration()
	print("UNDERSTORY TESTS: %d failures" % _failures)
	quit(1 if _failures else 0)


func _integration() -> void:
	var config := JSON.new()
	_check(config.parse(FileAccess.get_file_as_string("res://data/planet/planet_earth.json")) == OK, "JSON válido")
	var vegetation: Dictionary = config.data.vegetation_settings
	var planet := Planet.new(VoxelLodTerrain.new())
	planet.radius = 30000.0
	var count: int = 0
	for entry in vegetation.items:
		if entry.has("understory_lods"):
			await planet._load_vegetation_item(count, entry, vegetation.generators, vegetation.hemisphere_graph_function)
			count += 1
	_check(count == 16 and planet._next_library_id == 24, "Ocho especies, 24 bandas registradas")
	_check(planet.item_transparent_materials.size() == 24, "Materiales reciben el clima")
	for id in planet._next_library_id:
		var item = planet.voxel_instancer.library.get_item(id)
		_check(item.scene == null and item.collision_shapes.is_empty(), "Decoración sin nodos ni colliders")
		_check(item.generator.emit_mode == VoxelInstanceGenerator.EMIT_FROM_FACES, "Distribución por área")
		_check(item.generator.noise != null and item.generator.noise_dimension == VoxelInstanceGenerator.DIMENSION_3D, "Ruido de grupos sobre la esfera")
		_check(item.generator.noise_graph != null, "Máscara de bioma conectada")
		_check(item.generator.min_height > planet.radius - 50.0, "Vegetación por encima del mar")
		var material: ShaderMaterial = _band_material(item)
		_check(material.get_shader_parameter("use_vertex_color") == true, "Paleta de hojas, tallos y flores")
		_check(material.get_shader_parameter("lod_morph_enabled") == true, "Morph de LOD activo")
		_check(item.hide_beyond_max_lod, "Los bloques más allá del relevo no se dibujan")
		if item.lod_index >= 2:
			_check(material.get_shader_parameter("fade_end") <= planet._get_lod_view_distance(item.lod_index), "Fade dentro del alcance")
		for lod in 4:
			if item.get_mesh(lod).get_surface_count() > 0:
				_check(item.get_mesh(lod).surface_get_material(0) == material, "LOD mantiene material de banda")
	# Cada especie se registra en orden: banda 0, banda 1 y banda 2.
	for species in 8:
		for pair in [[0, 1], [1, 2]]:
			var out_mat: ShaderMaterial = _band_material(planet.voxel_instancer.library.get_item(species * 3 + pair[0]))
			var in_mat: ShaderMaterial = _band_material(planet.voxel_instancer.library.get_item(species * 3 + pair[1]))
			_check(out_mat.get_shader_parameter("fade_start") == in_mat.get_shader_parameter("fade_in_start"), "Relevo coordinado")
			_check(out_mat.get_shader_parameter("fade_end") == in_mat.get_shader_parameter("fade_in_end"), "Relevo sin hueco")
	planet.voxel_instancer.free()
	planet.voxel_terrain.free()
	planet.free()
	await process_frame


## La banda lejana puede empezar por una malla vacía (bloques ocultos por el relevo).
func _band_material(item) -> ShaderMaterial:
	for lod in 4:
		if item.get_mesh(lod).get_surface_count() > 0:
			return item.get_mesh(lod).surface_get_material(0)
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
