extends SceneTree

const GrassLods = preload("res://scripts/planet/grass_geometry_lods.gd")
const SCENES := ["low_poly_grass", "low_poly_grass_green_yellow", "low_poly_grass_yellow"]
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for scene_name in SCENES:
		var scene: Node = load("res://scenes/planet/planet_items/vegetation/grass/%s.tscn" % scene_name).instantiate()
		var source: Mesh = scene.get_child(0).mesh
		var original: Array = source.surface_get_arrays(0)
		var material: Material = source.surface_get_material(0)
		var started: int = Time.get_ticks_usec()
		var lods: Array = GrassLods.build(source)
		_check(lods.size() == 4, "Cuatro LODs geométricos para " + scene_name)
		if lods.size() != 4:
			scene.free()
			continue
		print("BUILD ", scene_name, " ", (Time.get_ticks_usec() - started) / 1000.0, " ms")
		_check(lods[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == original[Mesh.ARRAY_VERTEX], "LOD0 conserva todos los vértices")
		_check(lods[0].surface_get_arrays(0)[Mesh.ARRAY_INDEX] == original[Mesh.ARRAY_INDEX], "LOD0 conserva todos los triángulos")
		var previous_count: int = 1000000
		for level in 4:
			var arrays: Array = lods[level].surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			_check(indices.size() > 0 and indices.size() < previous_count, "LOD%d reduce triángulos" % level)
			_check(normals.size() == vertices.size(), "Todas las hojas conservan normales")
			_check(lods[level].surface_get_material(0) == material, "Se mantiene el material y el viento del modelo")
			_check(absf(lods[level].get_aabb().end.y - source.get_aabb().end.y) < 0.002, "Se conserva la altura de la mata")
			var valid: bool = true
			for index in indices:
				valid = valid and index >= 0 and index < vertices.size()
			for index in vertices.size():
				valid = valid and vertices[index].is_finite() and normals[index].is_finite()
				valid = valid and normals[index].length_squared() > 0.9
			_check(valid, "Geometría y normales válidas en LOD%d" % level)
			print("LOD", level, ": ", vertices.size(), " vertices, ", indices.size() / 3, " triangles")
			previous_count = indices.size()
		_check(previous_count <= 24, "El último LOD cuesta como máximo 8 triángulos")
		_check(source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == original[Mesh.ARRAY_VERTEX], "No se modifica la malla fuente")
		scene.free()
	_test_configuration()
	print("GRASS GEOMETRY TESTS: %d failures" % _failures)
	quit(1 if _failures else 0)


func _test_configuration() -> void:
	var json := JSON.new()
	_check(json.parse(FileAccess.get_file_as_string("res://data/planet/planet_earth.json")) == OK, "JSON del planeta válido")
	var vegetation: Dictionary = json.data.vegetation_settings
	var count: int = 0
	for item in vegetation.items:
		if item.has("grass_lods"):
			count += 1
			_check(not item.has("grass_patch"), "La hierba geométrica no se hornea como tarjeta")
			_check(item.wind_speed > 0.0, "La hierba lejana también recibe viento")
			_check(PackedFloat32Array(item.mesh_lod_distances_m) == PackedFloat32Array([40, 95, 180]), "Los niveles comparten distancias de relevo")
	_check(count == 6, "Las tres variantes tienen capa cercana y lejana")
	for generator in vegetation.generators:
		if str(generator.name).begins_with("grass_far_generator_"):
			_check(generator.emit_mode == "EMIT_FROM_FACES", "Densidad lejana independiente de resolución del terreno")
			_check(generator.lod_density_falloff == 1.0, "Las bandas lejanas conservan la densidad")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
