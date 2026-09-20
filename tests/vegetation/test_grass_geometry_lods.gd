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
		_check(lods[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != original[Mesh.ARRAY_VERTEX], "LOD0 reconstruye las cintas curvas")
		var previous_count: int = 1000000
		for level in 4:
			var arrays: Array = lods[level].surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			_check(uv2s.size() == vertices.size(), "Cada vértice tiene altura de hoja")
			for uv in uv2s:
				_check_once(uv.x >= 0.0 and uv.x <= 1.0 and uv.y == 1.0, "Altura y marca de geometría válidas")
			_check(indices.size() > 0 and indices.size() < previous_count, "LOD%d reduce triángulos" % level)
			_check(normals.size() == vertices.size(), "Todas las hojas conservan normales")
			_check(uvs.size() == vertices.size(), "Todas las hojas llevan UV horneada en LOD%d" % level)
			# U es la transversal de la hoja y tiene que recorrer de borde a borde:
			# es lo que usa el shader para fingir la sección curva de la brizna.
			var min_u: float = 1.0
			var max_u: float = 0.0
			var seeds: Dictionary = {}
			for uv in uvs:
				min_u = minf(min_u, uv.x)
				max_u = maxf(max_u, uv.x)
				_check_once(uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0,
					"UV dentro de rango en LOD%d" % level)
				seeds[snappedf(uv.y, 0.0001)] = true
			_check(min_u < 0.02 and max_u > 0.98, "La U cubre el ancho de la hoja en LOD%d" % level)
			# Una semilla distinta por hoja: es lo que descorrelaciona su color.
			_check(seeds.size() == maxi(64 >> level, 1),
				"Una semilla por hoja en LOD%d (%d)" % [level, seeds.size()])
			# Todas las puntas siguen en el asset original, incluso las hojas elegidas
			# para LOD3: el refinado no cambia la altura ni la silueta exterior.
			for vertex_index in vertices.size():
				if uv2s[vertex_index].x == 1.0:
					_check_once(vertices[vertex_index] in original[Mesh.ARRAY_VERTEX],
						"Las puntas conservan las posiciones del modelo")
			_check(lods[level].surface_get_material(0) == material, "Se mantiene el material y el viento del modelo")
			_check(absf(lods[level].get_aabb().end.y - source.get_aabb().end.y) < 0.002, "Se conserva la altura de la mata")
			var valid: bool = true
			for index in indices:
				valid = valid and index >= 0 and index < vertices.size()
			for offset in range(0, indices.size(), 3):
				var a: int = indices[offset]
				var b: int = indices[offset + 1]
				var c: int = indices[offset + 2]
				var face: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
				valid = valid and face.length_squared() > 0.0000000001
				valid = valid and face.dot(normals[a] + normals[b] + normals[c]) < 0.0
			for index in vertices.size():
				valid = valid and vertices[index].is_finite() and normals[index].is_finite()
				valid = valid and normals[index].length_squared() > 0.9
				if index > 0 and uvs[index].y == uvs[index - 1].y:
					_check_once(normals[index].dot(normals[index - 1]) > 0.0,
						"Las normales no se invierten a lo largo de la hoja")
			_check(valid, "Geometría y normales válidas en LOD%d" % level)
			print("LOD", level, ": ", vertices.size(), " vertices, ", indices.size() / 3, " triangles")
			previous_count = indices.size()
		_check(previous_count <= 24, "El último LOD cuesta como máximo 8 triángulos")
		_check(source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == original[Mesh.ARRAY_VERTEX], "No se modifica la malla fuente")
		# El modelo trae UVs propias, pero ningún shader de hierba las muestrea (no hay
		# textura) y no codifican ni la transversal ni una semilla por hoja. Las mallas
		# LOD llevan las horneadas; la fuente se queda como estaba.
		_check(source.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] == original[Mesh.ARRAY_TEX_UV],
			"No se modifican las UVs de la malla fuente")
		# Las semillas de LOD1 tienen que ser un subconjunto de las de LOD0: si no, una
		# hoja cambiaría de color al cambiar el instancer de malla.
		var seeds_lod0: Dictionary = {}
		for uv in lods[0].surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]:
			seeds_lod0[snappedf(uv.y, 0.0001)] = true
		var stable: bool = true
		for uv in lods[1].surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]:
			stable = stable and seeds_lod0.has(snappedf(uv.y, 0.0001))
		_check(stable, "La semilla de cada hoja no cambia entre LODs")
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


## Igual que _check pero sin inundar la salida: solo informa del primer fallo.
var _reported: Dictionary = {}

func _check_once(condition: bool, message: String) -> void:
	if condition or _reported.has(message):
		return
	_reported[message] = true
	_check(condition, message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
