extends SceneTree

## Árboles Branching: mallas por LOD, datos por vértice para viento/sombras/luz, atlas de
## impostor y registro en dos bandas del instancer.
##   godot --headless --path . -s res://tests/vegetation/test_trees.gd

## Presupuesto de triángulos por LOD (el pino, la especie más cargada, ronda 10,4k en LOD0).
const MAX_TRIANGLES := [11000, 4000, 1400, 500]

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := JSON.new()
	config.parse(FileAccess.get_file_as_string("res://data/planet/planet_earth.json"))
	var vegetation: Dictionary = config.data.vegetation_settings
	var tree_items: Array = []
	for item in vegetation.items:
		if item.has("tree_lods"):
			tree_items.append(item)
	_check(tree_items.size() == 9, "Nueve árboles con relevo de bandas (pinos, olivos, manzanos, almendros)")

	for item in tree_items:
		var scene_name: String = str(item.scene).get_file().get_basename()
		var root: Node = load(item.scene).instantiate()
		var tree: Tree3D = null
		for child in root.get_children():
			if child is Tree3D:
				tree = child
		_check(tree != null and tree.shape == Tree3D.SHAPE_BRANCHING, scene_name + ": forma Branching")
		if tree == null:
			root.free()
			continue
		var lods: Array = tree.bake_lods()
		_check_lods(scene_name, lods)
		_check(TreeOctaImpostor.has_atlases(scene_name), scene_name + ": atlas de impostor horneados")
		if TreeOctaImpostor.has_atlases(scene_name):
			var atlas: Texture2D = load(TreeOctaImpostor.atlas_paths(scene_name)[0])
			_check(atlas.get_width() == TreeOctaImpostor.FRAMES * TreeOctaImpostor.FRAME_PX,
				scene_name + ": atlas de %d vistas de %d px" % [TreeOctaImpostor.FRAMES, TreeOctaImpostor.FRAME_PX])
		_check(tree.get_collision_height() >= 1.0 and tree.get_collision_radius() > 0.05,
			scene_name + ": cilindro de colisión del tronco")
		root.free()

	await _check_registration(tree_items, vegetation.generators)
	print("TREE TESTS: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_lods(scene_name: String, lods: Array) -> void:
	_check(lods.size() == 4, scene_name + ": cuatro LODs")
	var size0: Vector3 = lods[0].get_aabb().size
	var previous := 1 << 30
	for lod in lods.size():
		var mesh: Mesh = lods[lod]
		var tris := 0
		for s in mesh.get_surface_count():
			tris += mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
		_check(tris <= MAX_TRIANGLES[lod], "%s: LOD%d con %d triángulos (máx %d)" % [scene_name, lod, tris, MAX_TRIANGLES[lod]])
		_check(tris < previous, "%s: LOD%d más ligero que el anterior" % [scene_name, lod])
		previous = tris
		# Misma silueta en los LODs que se dibujan: el esqueleto es el mismo. El LOD3 geométrico
		# no se usa con relevo de bandas (lejos va el impostor) y agranda mucho sus tarjetas.
		var size: Vector3 = mesh.get_aabb().size
		_check(lod == 3 or absf(size.y - size0.y) / size0.y < 0.15 and absf(size.x - size0.x) / size0.x < 0.3,
			"%s: LOD%d conserva el tamaño del LOD0" % [scene_name, lod])
	_check_vertex_data(scene_name, lods[0])


func _check_vertex_data(scene_name: String, mesh: Mesh) -> void:
	_check(mesh.get_surface_count() >= 2, scene_name + ": madera y follaje en superficies separadas")
	var wood := mesh.surface_get_arrays(0)
	var wood_colors: PackedColorArray = wood[Mesh.ARRAY_COLOR]
	var wood_uv2: PackedVector2Array = wood[Mesh.ARRAY_TEX_UV2]
	_check(not wood_colors.is_empty() and not wood_uv2.is_empty(), scene_name + ": madera con COLOR y UV2")
	var wood_ok := true
	for c in wood_colors:
		wood_ok = wood_ok and is_equal_approx(c.a, 1.0) and c.r > 0.0 and c.r <= 1.0
	_check(wood_ok, scene_name + ": madera marcada (COLOR.a = 1) con oclusión en (0, 1]")
	_check(not wood[Mesh.ARRAY_TANGENT].is_empty(), scene_name + ": madera con tangentes para el normal map")

	var leaves := mesh.surface_get_arrays(1)
	var verts: PackedVector3Array = leaves[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = leaves[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = leaves[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = leaves[Mesh.ARRAY_TEX_UV2]
	_check(colors.size() == verts.size() and uv2.size() == verts.size(), scene_name + ": tarjetas con COLOR y UV2")
	var center := Vector3.ZERO
	for v in verts:
		center += v
	center /= maxf(verts.size(), 1)
	var outward := 0
	var cards_ok := true
	var finite := true
	for k in verts.size():
		if normals[k].dot(verts[k] - center) > 0.0:
			outward += 1
		cards_ok = cards_ok and colors[k].a < 0.95 and colors[k].b >= 0.0 and colors[k].b <= 1.0 \
			and uv2[k].y >= 0.0 and uv2[k].y <= 1.0
		finite = finite and normals[k].is_finite() and is_equal_approx(normals[k].length(), 1.0)
	_check(cards_ok, scene_name + ": tarjetas con aleatorio < 0,9 en COLOR.a y pesos de viento en [0, 1]")
	_check(finite, scene_name + ": normales de tarjeta finitas y unitarias")
	_check(outward > verts.size() * 0.85, scene_name + ": normales de copa hacia fuera (%d %%)" % (100 * outward / maxi(verts.size(), 1)))


func _check_registration(tree_items: Array, generators: Array) -> void:
	var terrain := VoxelLodTerrain.new()
	var planet := Planet.new(terrain)
	planet.radius = 30000.0
	var item: Dictionary = tree_items[0].duplicate(true)
	item.generator = [item.generator[0]]
	await planet._load_vegetation_item(0, item, generators, [])
	# Item principal (banda 4: impostor, cuerpos y detalle, mismas posiciones cerca y lejos) e
	# items de impostores lejanos (bandas 5 y 6), registrados al final: no desplazan los ids.
	_check(planet._next_library_id == 1, "Los impostores lejanos se registran después del resto")
	planet._register_far_tree_items()
	_check(planet._next_library_id == 3, "Un árbol: item principal y dos de impostores lejanos")
	if planet._next_library_id != 3:
		return
	var far_id := 1
	var band = planet.voxel_instancer.library.get_item(0)
	_check(band.lod_index == 4, "Banda lejana 4")
	var far = planet.voxel_instancer.library.get_item(far_id)
	_check(far.lod_index == 5 and far.collision_shapes.is_empty() and not planet.planet_item_packed_scenes.has(far_id)
		and far.cast_shadow == RenderingServer.SHADOW_CASTING_SETTING_OFF,
		"Impostores lejanos en la banda 5, sin cuerpos, tala ni sombra")
	var near_out := Vector2(band.get_mesh(0).surface_get_material(0).get_shader_parameter("fade_out_start"),
		band.get_mesh(0).surface_get_material(0).get_shader_parameter("fade_out_end"))
	var far_in := Vector2(far.get_mesh(0).surface_get_material(0).get_shader_parameter("fade_in_start"),
		far.get_mesh(0).surface_get_material(0).get_shader_parameter("fade_in_end"))
	_check(near_out.y > near_out.x and near_out.is_equal_approx(far_in), "Los impostores lejanos entran donde salen los de la banda 4")
	var farther = planet.voxel_instancer.library.get_item(far_id + 1)
	var far_out := Vector2(far.get_mesh(0).surface_get_material(0).get_shader_parameter("fade_out_start"),
		far.get_mesh(0).surface_get_material(0).get_shader_parameter("fade_out_end"))
	var farther_in := Vector2(farther.get_mesh(0).surface_get_material(0).get_shader_parameter("fade_in_start"),
		farther.get_mesh(0).surface_get_material(0).get_shader_parameter("fade_in_end"))
	_check(farther.lod_index == 6 and far_out.is_equal_approx(farther_in) and far_out.x > near_out.y,
		"La banda 6 entra donde sale la 5")
	_check(farther.generator.snap_to_generator_sdf_search_distance > band.generator.snap_to_generator_sdf_search_distance,
		"La búsqueda del SDF crece con la banda")
	_check(band.generator.snap_to_generator_sdf_enabled,
		"Las instancias se ajustan al SDF del generador (la malla de LOD 4 se separa del suelo)")
	_check(not band.collision_shapes.is_empty() and planet.planet_item_packed_scenes.has(0),
		"Colisión y tala en el item del árbol")
	_check(band.collision_distance >= TreeDetailRenderer.LOD_FADES[2].y,
		"La colisión (cuerpos) cubre el último fundido del detalle")
	var mesh_height: float = planet.tree_detail_renderer.lod_meshes(0)[0].get_aabb().end.y
	var heights: Array = item.height_m
	_check(is_equal_approx(band.generator.min_scale * mesh_height, float(heights[0]))
		and is_equal_approx(band.generator.max_scale * mesh_height, float(heights[1])), "height_m fija la altura real")
	var impostor_material: ShaderMaterial = band.get_mesh(0).surface_get_material(0)
	_check(impostor_material.shader.resource_path.ends_with("tree_octa_impostor.gdshader"), "El item dibuja el impostor octaédrico")
	var renderer: TreeDetailRenderer = planet.tree_detail_renderer
	_check(renderer != null and renderer.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,
		"El detalle no se interpola: al rehacer una celda cada índice pasa a ser otro árbol")
	var detail: Array = renderer.lod_meshes(0) if renderer != null else []
	_check(detail.size() == 3, "Detalle registrado: tres LODs de geometría")
	if detail.size() != 3:
		return
	# Fundidos encadenados sobre el mismo árbol: cada LOD entra donde sale el anterior y el
	# impostor donde sale el LOD2.
	var previous_out := Vector2.ZERO
	for lod in 3:
		var material: ShaderMaterial = detail[lod].surface_get_material(1)
		var fade_in := Vector2(material.get_shader_parameter("fade_in_start") if lod > 0 else 0.0,
			material.get_shader_parameter("fade_in_end") if lod > 0 else 0.0)
		var fade_out := Vector2(material.get_shader_parameter("fade_out_start"), material.get_shader_parameter("fade_out_end"))
		_check(lod == 0 or fade_in.is_equal_approx(previous_out), "LOD%d entra donde sale el LOD%d" % [lod, lod - 1])
		previous_out = fade_out
	var imp_in := Vector2(impostor_material.get_shader_parameter("fade_in_start"), impostor_material.get_shader_parameter("fade_in_end"))
	_check(imp_in.is_equal_approx(previous_out), "El impostor entra donde sale el LOD2")
	# La sombra del impostor entra donde sale la del último LOD que proyecta (los siguientes no
	# proyectan): ni hueco ni doble sombra en el relevo.
	var last_shadow: ShaderMaterial = detail[TreeDetailRenderer.SHADOW_LODS - 1].surface_get_material(1)
	var imp_shadow_in := Vector2(impostor_material.get_shader_parameter("shadow_fade_in_start"),
		impostor_material.get_shader_parameter("shadow_fade_in_end"))
	_check(imp_shadow_in.is_equal_approx(Vector2(last_shadow.get_shader_parameter("fade_out_start"),
		last_shadow.get_shader_parameter("fade_out_end"))), "La sombra del impostor entra donde sale la del LOD%d" % (TreeDetailRenderer.SHADOW_LODS - 1))
	var registered := 0
	for entry in planet.item_transparent_materials:
		if entry.shader == impostor_material or entry.shader == detail[0].surface_get_material(1):
			registered += 1
	_check(registered == 2, "Impostor y detalle reciben sol, planeta y viento")
	planet.free()
	terrain.free()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		print("FAIL: ", label)
