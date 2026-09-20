extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := JSON.new()
	config.parse(FileAccess.get_file_as_string("res://data/planet/planet_earth.json"))
	var vegetation: Dictionary = config.data.vegetation_settings
	var planet := Planet.new(VoxelLodTerrain.new())
	planet.radius = 30000.0
	var items: int = 0
	for item in vegetation.items:
		if not item.has("grass_lods"):
			continue
		# Sin generar el mundo ni hornear texturas: comprobar el registro real de items.
		await planet._load_vegetation_item(items, item, vegetation.generators, [])
		items += 1
	_check(planet._next_library_id == 12, "Registradas las 12 bandas de las tres variantes")
	_check(planet.item_transparent_materials.size() == 12, "Cada banda recibe luz y viento")
	for id in planet._next_library_id:
		var item = planet.voxel_instancer.library.get_item(id)
		var material: ShaderMaterial = item.get_mesh(0).surface_get_material(0)
		for lod in 4:
			_check(item.get_mesh(lod) != null, "LOD geométrico registrado")
			_check(item.get_mesh(lod).surface_get_material(0) == material, "Material compartido dentro de la banda")
		_check(material.shader.resource_path.ends_with("grass_wind.gdshader"), "Todas las bandas usan el shader del modelo")
		_check(item.scene == null, "No se crean nodos ni colisiones por mata")
		_check(item.cast_shadow == RenderingServer.SHADOW_CASTING_SETTING_OFF, "Sombras desactivadas como en LOD0")
		var end: float = material.get_shader_parameter("fade_end")
		if item.lod_index >= 2:
			_check(item.generator.emit_mode == VoxelInstanceGenerator.EMIT_FROM_FACES, "Generación por superficie")
			_check(material.get_shader_parameter("fade_in_end") > 0.0, "La banda lejana se oculta cerca")
			_check(end <= planet._get_lod_view_distance(item.lod_index), "Desaparición antes del límite del terreno")
	# Los dos relevos usan exactamente el mismo rango de distancia.
	var near_mat: ShaderMaterial = planet.voxel_instancer.library.get_item(1).get_mesh(0).surface_get_material(0)
	var mid_mat: ShaderMaterial = planet.voxel_instancer.library.get_item(6).get_mesh(0).surface_get_material(0)
	var far_mat: ShaderMaterial = planet.voxel_instancer.library.get_item(7).get_mesh(0).surface_get_material(0)
	for pair in [[near_mat, mid_mat], [mid_mat, far_mat]]:
		_check(is_equal_approx(pair[0].get_shader_parameter("fade_start"), pair[1].get_shader_parameter("fade_in_start")), "Relevo sin hueco al empezar")
		_check(is_equal_approx(pair[0].get_shader_parameter("fade_end"), pair[1].get_shader_parameter("fade_in_end")), "Relevo sin hueco al terminar")
	planet.voxel_instancer.free()
	planet.voxel_terrain.free()
	planet.free()
	await process_frame
	print("GRASS INSTANCER TESTS: %d failures" % _failures)
	quit(1 if _failures else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
