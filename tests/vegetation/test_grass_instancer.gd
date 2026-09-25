extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_ratio_assignment()
	var config := JSON.new()
	config.parse(FileAccess.get_file_as_string("res://data/planet/planet_earth.json"))
	var vegetation: Dictionary = config.data.vegetation_settings
	var planet := Planet.new(VoxelLodTerrain.new())
	planet.radius = 30000.0
	var items: int = 0
	var cfg: Dictionary = {}
	for item in vegetation.items:
		if not item.has("grass_lods"):
			continue
		cfg = item.grass_lods
		# Sin generar el mundo ni hornear texturas: comprobar el registro real de items.
		await planet._load_vegetation_item(items, item, vegetation.generators, [])
		items += 1
	# Tres variantes: bandas cercanas 0 y 1, y lejana 2.
	_check(planet._next_library_id == 9, "Registradas las 9 bandas de las tres variantes")
	_check(planet.item_transparent_materials.size() == 9, "Cada banda recibe luz y viento")
	var morph_end: Array = cfg.lod_morph_end_m
	for id in planet._next_library_id:
		var item = planet.voxel_instancer.library.get_item(id)
		var material: ShaderMaterial = null
		for lod in 4:
			_check(item.get_mesh(lod) != null, "LOD geométrico registrado")
			if item.get_mesh(lod).get_surface_count() > 0:
				if material == null:
					material = item.get_mesh(lod).surface_get_material(0)
				_check(item.get_mesh(lod).surface_get_material(0) == material, "Material compartido dentro de la banda")
		_check(material.shader.resource_path.ends_with("grass_wind.gdshader"), "Todas las bandas usan el shader del modelo")
		_check(material.get_shader_parameter("lod_morph_enabled") == true, "Morph de LOD activo")
		_check(item.scene == null, "No se crean nodos ni colisiones por mata")
		_check(item.cast_shadow == RenderingServer.SHADOW_CASTING_SETTING_OFF, "Sombras desactivadas como en LOD0")
		_check(item.hide_beyond_max_lod, "Los bloques más allá del relevo no se dibujan")
		var end: float = material.get_shader_parameter("fade_end")
		_check(end <= planet._get_lod_view_distance(item.lod_index), "Desaparición antes del límite del terreno")
		if item.lod_index >= 1:
			_check(material.get_shader_parameter("fade_in_end") > 0.0, "La banda se oculta cerca: no repite la anterior")
		if item.lod_index >= 2:
			_check(item.generator.emit_mode == VoxelInstanceGenerator.EMIT_FROM_FACES, "Generación por superficie")
		_check_band_slots(planet, item, material, morph_end)
	# Relevos encadenados: cada banda entra exactamente mientras sale la anterior.
	var pairs: Array = [[0, 1], [1, 6]]
	for pair in pairs:
		var out_mat: ShaderMaterial = _band_material(planet, pair[0])
		var in_mat: ShaderMaterial = _band_material(planet, pair[1])
		_check(is_equal_approx(out_mat.get_shader_parameter("fade_start"), in_mat.get_shader_parameter("fade_in_start")), "Relevo sin hueco al empezar")
		_check(is_equal_approx(out_mat.get_shader_parameter("fade_end"), in_mat.get_shader_parameter("fade_in_end")), "Relevo sin hueco al terminar")
	planet.voxel_instancer.free()
	planet.voxel_terrain.free()
	planet.free()
	await process_frame
	print("GRASS INSTANCER TESTS: %d failures" % _failures)
	quit(1 if _failures else 0)


## El módulo recorta cada ratio con los valores que tiene en ese momento: asignados en
## orden, los de la hierba cercana acababan en los de por defecto desplazados.
func _test_ratio_assignment() -> void:
	var planet := Planet.new(VoxelLodTerrain.new())
	for ratios in [[0.8, 0.9, 0.95, 1.2], [0.02, 0.05, 0.1, 1.0], [0.4, 0.45, 0.5, 0.55]]:
		var item := VoxelInstanceLibraryMultiMeshItem.new()
		planet._set_mesh_lod_ratios(item, ratios)
		for k in 4:
			_check(is_equal_approx(item.get("mesh_lod%d_distance_ratio" % k), ratios[k]),
				"Ratio %d aplicado tal cual en %s" % [k, str(ratios)])
	planet.voxel_instancer.free()
	planet.voxel_terrain.free()
	planet.free()


## Sin saltos: un bloque solo pasa a una malla más simple cuando todas sus matas,
## hasta la esquina más lejana del bloque, han terminado el morph hacia ella. La
## malla vacía solo cubre bloques cuyas matas están todas dentro del relevo de entrada.
func _check_band_slots(planet: Planet, item, material: ShaderMaterial, morph_end: Array) -> void:
	var view: float = planet._get_lod_view_distance(item.lod_index)
	var reach: float = float(planet._instancer_block_size(item.lod_index)) * 0.866
	var previous_ratio: float = 0.0
	for slot in 4:
		var ratio: float = item.get("mesh_lod%d_distance_ratio" % slot)
		_check(ratio > previous_ratio, "Ratios de malla estrictamente crecientes")
		previous_ratio = ratio
		var mesh: Mesh = item.get_mesh(slot)
		if mesh.get_surface_count() == 0:
			_check(ratio * view + reach <= float(material.get_shader_parameter("fade_in_start")) + 0.01,
				"La malla vacía solo cubre bloques ocultos")
			continue
		if slot == 3:
			continue
		var next: Mesh = item.get_mesh(slot + 1)
		var this_lod: int = _mesh_lod(mesh)
		var next_lod: int = _mesh_lod(next)
		_check(next_lod >= this_lod, "Las mallas no ganan detalle con la distancia")
		if next_lod > this_lod:
			_check(ratio * view >= float(morph_end[next_lod - 1]) + reach - 0.01,
				"Banda %d: el bloque cambia a LOD%d con el morph terminado" % [item.lod_index, next_lod])


func _mesh_lod(mesh: Mesh) -> int:
	var custom: PackedFloat32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	return int(custom[3]) >> 2


func _band_material(planet: Planet, id: int) -> ShaderMaterial:
	var item = planet.voxel_instancer.library.get_item(id)
	for lod in 4:
		if item.get_mesh(lod).get_surface_count() > 0:
			return item.get_mesh(lod).surface_get_material(0)
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
