@tool
class_name Planet extends Node3D

## Nodo de un planeta: configura el terreno voxel y su shader de biomas, genera la vegetación
## (VoxelInstancer) con sus colisiones, y parchea el VoxelGraph (radio, ores) desde datos JSON.

const GrassGeometryLods = preload("res://scripts/planet/grass_geometry_lods.gd")
var _grass_lod_cache: Dictionary = {}
## Campo de ríos para la vegetación, con la distancia reducida. Ver _vegetation_river_field.
var _vegetation_field: Dictionary = {}
@export var definition: PlanetDefinition = PlanetDefinition.new()

@export_group("Terrain Settings")
@export var radius: float

@export var wind_direction : Vector3

@export var item_transparent_materials : Array[Dictionary]
## Materiales planetarios ajenos a la vegetación (ver register_planet_material). Van en una
## lista aparte porque _load_vegetation vacía item_transparent_materials en cada carga del
## planeta y estos tienen que sobrevivir a ella (el jugador se registra una sola vez).
var external_planet_materials: Array[ShaderMaterial] = []
var _material_uniforms_initialized := false
var _last_material_sun := Vector3.ZERO
var _last_material_position := Vector3.ZERO
var _last_material_wind := Vector3.ZERO
var _last_external_material_count := -1
var _last_material_count := -1
var _last_wind_multiplier := -1.0
## Materiales de la vegetación cuyo shader declara light_direction (ver _update_planet).
var _sun_materials: Array[ShaderMaterial] = []
var _frames_to_sweep := 0
const MATERIAL_SWEEP_FRAMES := 60
var _sun_parameter_shaders: Dictionary = {}
@export var shader_material: ShaderMaterial
@export var caustics_material: ShaderMaterial
@export var multi_mesh_array: Array[Dictionary] = []

@export var sun_dir: Vector3
@export var planet_position: Vector3
@export var voxel_terrain: VoxelLodTerrain
@export var voxel_instancer: VoxelInstancer
@export var sun : DirectionalLight3D
@export var has_water: bool
@export var water_radius: float
## Identificador del planeta, para nombrar el caché del campo de ríos.
@export var entity_id: String = ""
## Campo de frío del planeta, la réplica en CPU del de los shaders. Siempre existe; sin
## climate_settings está apagado (enabled = false).
var climate: ClimateField = ClimateField.new()

## Campo de ríos horneado. Lo consume el terreno y también los grafos de densidad de vegetación,
## que sin él confunden un cauce hondo con una cueva.
var _river_field: Dictionary = {}

var planet_item_scenes: Dictionary
## library_id -> PackedScene plantilla de los items interactivos (los que se talan) sin instanciar
## nada en el módulo (ver _register_multi_mesh_item).
var planet_item_packed_scenes: Dictionary
## library_id -> baked local branch anchors and wood BVH, shared across instances.
var tree_perch_catalog: Dictionary = {}
## library_id -> id del item que da al recogerlo con la tecla de acción ("pickup" y "pickup_item" en
## el JSON: ramas caídas y piedras pequeñas). Llevan colisión solo cerca, en PhysicsLayers.PICKUP.
var pickup_library_ids: Dictionary = {}
## Geometría cercana de los árboles Branching (ver _register_tree_item).
var tree_detail_renderer: TreeDetailRenderer = null
## Tala de los árboles: hachazos, caídas y tocones.
var tree_felling: TreeFelling = null
## Picar las rocas: se parten en trozos que se pican en piedras.
var rock_mining: RockMining = null
var _next_library_id: int = 0
## Items de impostores lejanos pendientes: se registran al final (ver _register_far_tree_items).
var _far_tree_items: Array[Callable] = []

## Shader de follaje de doble cara (LOD cercano) y su variante de una cara (LOD lejano).
const _TWIG_SHADER_PATH := "res://shaders/transparent_material_shader.gdshader"
var _twig_singleside_shader: Shader = null

var _vegetation_baker: VegetationBaker

## Multiplicador global de viento sobre la vegetación, controlado por el WeatherController.
var weather_wind_multiplier: float = 1.0

## VoxelTool propio de get_underground_depth: cambia de canal en cada lectura y no debe pisar el de
## nadie.
var _depth_tool: VoxelTool = null

func _build_generator(generator_config: Dictionary, graph_functions: Array, lod_index: int = 0) -> VoxelInstanceGenerator:
	var generator : VoxelInstanceGenerator = VoxelInstanceGenerator.new()

	# El modo llega como string del JSON y se resuelve contra el enum real del módulo, así
	# quedan disponibles también los modos por área (EMIT_FROM_FACES*), que reparten por
	# superficie en vez de por vértice. Vía ClassDB para no romper el script si la build
	# del módulo no trae alguno de los modos.
	var mode_name: String = generator_config.get("emit_mode", "EMIT_FROM_VERTICES")
	if ClassDB.class_has_integer_constant("VoxelInstanceGenerator", mode_name):
		generator.emit_mode = ClassDB.class_get_integer_constant("VoxelInstanceGenerator", mode_name)
	else:
		push_error("Vegetación: emit_mode '%s' no existe en VoxelInstanceGenerator." % mode_name)
	# Ojo: la unidad de 'density' depende del modo. Por vértices es la fracción de
	# vértices del bloque (y entonces cae 4x por m² en cada banda de LOD); por área es
	# instancias por m², independiente de la resolución de la malla.
	if generator_config.has("density"):
		var density: float = generator_config.density
		if lod_index > 0:
			var falloff: float = generator_config.get("lod_density_falloff", 0.5)
			density *= pow(falloff, lod_index)
		generator.density = density

	if generator_config.has("offset_along_normal"):
		generator.offset_along_normal = generator_config.offset_along_normal
	if generator_config.has("max_height"):
		generator.max_height = radius + generator_config.max_height
	if generator_config.has("min_height"):
		generator.min_height = radius + generator_config.min_height
	if generator_config.has("max_slope_degrees"):
		generator.max_slope_degrees = generator_config.max_slope_degrees
	if generator_config.has("vertical_alignment"):
		generator.vertical_alignment = generator_config.vertical_alignment
	# Las instancias salen sobre la malla del LOD de su item. En LOD 4 esa malla se separa del
	# terreno que se ve de cerca (LOD 0) hasta ~1,5 m: los árboles flotaban o se hundían.
	# El módulo puede buscar la superficie del SDF del generador a lo largo de la normal.
	# "snap_to_sdf": {"search_distance": 4.0, "samples": 8}
	if generator_config.has("snap_to_sdf"):
		var snap: Dictionary = generator_config.snap_to_sdf
		generator.snap_to_generator_sdf_enabled = true
		generator.snap_to_generator_sdf_search_distance = float(snap.get("search_distance", 4.0))
		generator.snap_to_generator_sdf_sample_count = int(snap.get("samples", 8))
	# Un bloque de LOD N tiene los mismos vóxeles pero cubre 4x más área, así que
	# EMIT_FROM_VERTICES da 4x menos instancias por m² en cada banda. lod_scale_gain
	# las agranda para compensar parte de esa pérdida de cobertura (1.0 = sin cambio).
	var scale_gain: float = pow(float(generator_config.get("lod_scale_gain", 1.0)), lod_index)
	if generator_config.has("min_scale"):
		generator.min_scale = generator_config.min_scale * scale_gain
	if generator_config.has("max_scale"):
		generator.max_scale = generator_config.max_scale * scale_gain
	# Ruido simple de parcheo: praderas y manchas sin montar un grafo de vóxel entero.
	# "noise": {"frequency": 0.01, "octaves": 2, "dimension": "2D", "on_scale": 0.3}
	# threshold (-1..1) desplaza qué parte del suelo queda dentro de las manchas y
	# falloff suaviza su borde: la densidad baja hacia fuera en vez de cortarse.
	if generator_config.has("noise"):
		var noise_config: Dictionary = generator_config.noise
		var noise := FastNoiseLite.new()
		noise.seed = int(noise_config.get("seed", 0))
		noise.frequency = float(noise_config.get("frequency", 0.01))
		noise.fractal_octaves = int(noise_config.get("octaves", 2))
		generator.noise = noise
		generator.noise_dimension = (VoxelInstanceGenerator.DIMENSION_3D
				if noise_config.get("dimension", "2D") == "3D"
				else VoxelInstanceGenerator.DIMENSION_2D)
		if noise_config.has("on_scale"):
			generator.noise_on_scale = float(noise_config.on_scale)
		if noise_config.has("threshold"):
			generator.noise_threshold = float(noise_config.threshold)
		if noise_config.has("falloff"):
			generator.noise_falloff = float(noise_config.falloff)
	var noise_graph: VoxelGraphFunction = null
	if generator_config.has("noise_graph"):
		for graph_func in graph_functions:
			if graph_func.name == generator_config.noise_graph:
				noise_graph = _load_vegetation_graph(graph_func.path)
	# Con noise_threshold puesto, el módulo deja de aplicar el noise_graph (y el propio ruido): la
	# máscara de bioma no filtraba nada y la hierba y los árboles del bioma verde salían en el
	# desierto y en la nieve. Esas manchas se evalúan entonces dentro del grafo.
	if noise_graph != null and generator.noise != null and generator.noise_threshold != 0.0:
		noise_graph = _with_patch_noise(noise_graph, generator_config.noise)
		generator.noise = null
		generator.noise_threshold = 0.0
		generator.noise_falloff = 0.0
	# Banda del campo de frío: "climate": {"min": 41, "max": 53, "soft": 1.5} (grados, ver
	# ClimateField). Sin "min" o "max" ese lado queda abierto: el bioma verde lleva solo "max" y se
	# para donde empieza la taiga.
	if noise_graph != null and generator_config.has("climate") and climate.enabled:
		var band: Dictionary = generator_config.climate
		noise_graph = ClimateGraph.gate(noise_graph, climate, float(band.get("min", -100.0)),
			float(band.get("max", 200.0)), float(band.get("soft", 1.5)))
	# Se asigna ya terminado: el módulo compila el grafo al asignarlo y no ve cambios posteriores.
	generator.noise_graph = noise_graph

	var graph_function = generator.noise_graph
	if graph_function:
		var noise_id = graph_function.find_node_by_name(&"Noise_01")
		if noise_id:
			if graph_function.get_node_type_id(noise_id) != VoxelGraphFunction.NODE_FAST_NOISE_3D:
				push_error("El nodo 'Noise_01' no es de tipo FastNoise3D")
				return

	return generator

func _build_tree_collision(trunk_inst: MeshInstance3D, radius: float) -> CollisionShape3D:

	var aabb: AABB = trunk_inst.mesh.get_aabb()
	var height: float = aabb.size.y

	var shape := CylinderShape3D.new()
	shape.height = height
	shape.radius = radius
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.shape = shape

	return collision_shape


func _build_rock_collision(rock_inst: MeshInstance3D) -> CollisionShape3D:
	var shape: ConvexPolygonShape3D = rock_inst.mesh.create_convex_shape(true, false)
	if shape == null:
		return null
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.shape = shape

	return collision_shape


## Cilindro con el ancho y el alto de [mesh] (una mata), para encontrarla al recogerla.
static func _pickup_shape(mesh: Mesh) -> Array:
	var box := mesh.get_aabb()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(0.1, maxf(box.size.x, box.size.z) * 0.4)
	shape.height = maxf(0.1, box.size.y)
	return [shape, Transform3D(Basis.IDENTITY, Vector3(0.0, box.get_center().y, 0.0))]

func _build_item_shared_data(i: int, item) -> Dictionary:
	var scene: PackedScene = load(item.scene)
	var scene_instantiated: Node = scene.instantiate()
	var source_node = scene_instantiated.get_child(0)

	var result: Dictionary = {
		"packed_scene": null,
		"effective_mesh": null,
		"registered_scene": null,
		"lod_meshes": [],
		"collision_shapes": [],
	}

	if source_node is MeshInstance3D:
		result.packed_scene = scene
		result.effective_mesh = (source_node as MeshInstance3D).mesh
		if item.has("understory_lods") and source_node.has_method("bake_lods"):
			result.lod_meshes = source_node.bake_lods()
		if item.has("material_type"):
			result.registered_scene = scene_instantiated
		else:
			scene_instantiated.queue_free()

	elif source_node is Tree3D or source_node is Bush3D:
		var tree_data := _build_tree_packed_scene(scene_instantiated, source_node)
		result.packed_scene = tree_data.scene
		result.effective_mesh = tree_data.mesh
		result.lod_meshes = tree_data.get("lod_meshes", [])
		result.collision_shapes = tree_data.get("collision_shapes", [])
		result.perch_data = tree_data.get("perch_data", {})
		result.registered_scene = tree_data.scene.instantiate()

	elif source_node is Rock3D:
		var rock_data := _build_rock_packed_scene(scene_instantiated, source_node)
		result.packed_scene = rock_data.scene
		result.effective_mesh = rock_data.mesh
		result.registered_scene = rock_data.scene.instantiate()
	else:
		push_error("Tipo de vegetación desconocido en item %d: %s" % [i, source_node])
		scene_instantiated.queue_free()
		return {}

	return result
	
## Escribe los 4 mesh_lodN_distance_ratio tal cual, sin conversión ni clamp.
## Sirve para calibrar empíricamente cómo interpreta el módulo estos ratios.
func _apply_mesh_lod_ratios_raw(multi_mesh_item, lod_index: int, r: Array) -> void:
	_set_mesh_lod_ratios(multi_mesh_item, r)


## El módulo recorta cada ratio al intervalo [anterior, siguiente] con los valores que
## tiene en ese momento. Asignados en orden, un ratio mayor que el valor por defecto del
## siguiente quedaba recortado (la hierba pedía LOD0 hasta 40 m y usaba 0,35 · 48 m).
## Una pasada inversa y otra directa dejan cualquier secuencia creciente tal cual.
func _set_mesh_lod_ratios(multi_mesh_item, ratios: Array) -> void:
	for order in [[3, 2, 1, 0], [0, 1, 2, 3]]:
		for k in order:
			multi_mesh_item.set("mesh_lod%d_distance_ratio" % k, float(ratios[k]))
	for k in 4:
		if not is_equal_approx(multi_mesh_item.get("mesh_lod%d_distance_ratio" % k), float(ratios[k])):
			push_error("Vegetación: el módulo no aceptó los ratios de LOD %s" % str(ratios))
			return
	

## Alcance en metros de una banda de voxel-LOD. Prefiere get_lod_distances() del
## módulo (es lo que el propio módulo usa para cortar) y cae al cálculo manual.
func _get_lod_view_distance(lod_index: int) -> float:
	if voxel_terrain.has_method("get_lod_distances"):
		var d = voxel_terrain.get_lod_distances()
		if d != null and lod_index < d.size():
			return float(d[lod_index])
	return float(voxel_terrain.lod_distance) * float(1 << lod_index)

## Fija los 4 mesh_lodN_distance_ratio del item a partir de distancias de salto en metros.
## distances_m: [fin_LOD0, fin_LOD1, fin_LOD2] y opcionalmente [.., corte_LOD3].
## El módulo elige el mesh-LOD por bloque (cam->centro del bloque) y corta en
## ratio · get_lod_distances()[lod_index]. clamp a [0,1] y orden estrictamente creciente.
func _apply_mesh_lod_distances(multi_mesh_item, lod_index: int, distances_m: Array) -> void:
	if voxel_terrain == null:
		return
	var view_distance: float = _get_lod_view_distance(lod_index)
	if view_distance <= 0.0:
		return

	# 4º ratio por defecto = 1.0 (LOD3 hasta el final del alcance de este lod_index)
	var ratios: Array = [1.0, 1.0, 1.0, 1.0]
	for k in range(min(distances_m.size(), 4)):
		ratios[k] = float(distances_m[k]) / view_distance

	# clamp y forzar creciente para no romper el orden que espera el módulo
	var prev := 0.0
	for k in 4:
		var r: float = clampf(ratios[k], 0.0, 1.0)
		if r <= prev:
			r = minf(prev + 0.001, 1.0)
		ratios[k] = r
		prev = r

	_set_mesh_lod_ratios(multi_mesh_item, ratios)

func _register_multi_mesh_item(i: int, item, shared_data: Dictionary, generator: VoxelInstanceGenerator, lod_index: int) -> void:
	var multi_mesh_item := VoxelInstanceLibraryMultiMeshItem.new()
	multi_mesh_item.generator = generator
	multi_mesh_item.lod_index = lod_index

	# 'instance_as_scene': false marca decorado estático: hierba y parches, que no se talan ni se
	# recogen. Los items que no traen la clave son interactivos, como hasta ahora.
	var interactive: bool = item.get("instance_as_scene", true)

	var lm: Array = shared_data.get("lod_meshes", [])
	if lm.size() == 4:
		# 4 mesh-LOD: cerca lm[0], lejos lm[3] (geometría simple o impostor según item).
		# El near->far lo hace el módulo
		# eligiendo la malla por bloque según distancia (cuidado: por CENTRO de bloque -> salta a
		# saltos, más notorio cuanto mayor el lod_index; es by-design del multimesh).
		multi_mesh_item.set_mesh(lm[0], 0)
		multi_mesh_item.set_mesh(lm[1], 1)
		multi_mesh_item.set_mesh(lm[2], 2)
		multi_mesh_item.set_mesh(lm[3], 3)

		var cs: Array = shared_data.get("collision_shapes", [])
		if item.get("pickup", false):
			# Se recoge (los arbustos dan fibra): solo cerca (collision_distance_m), un cuerpo en
			# PhysicsLayers.PICKUP del tamaño de la mata, para encontrarla y quitarla al cogerla. La
			# envolvente de sus miles de triángulos no hace falta.
			multi_mesh_item.collision_shapes = _pickup_shape(lm[0])
			multi_mesh_item.collision_layer = PhysicsLayers.PICKUP
			multi_mesh_item.collision_mask = 0
		elif not cs.is_empty():
			multi_mesh_item.collision_shapes = cs

		# Hierba y sotobosque traen los ratios de su banda ya calculados (ver
		# _build_grass_band). "mesh_lod_ratios" (4 valores) se escribe crudo, para
		# calibrar la semántica real del módulo sin la conversión desde metros.
		var band_ratios: Array = shared_data.get("lod_ratios", [])
		var raw_ratios: Array = item.get("mesh_lod_ratios", [])
		if band_ratios.size() == 4:
			_set_mesh_lod_ratios(multi_mesh_item, band_ratios)
			multi_mesh_item.hide_beyond_max_lod = true
		elif raw_ratios.size() == 4:
			_apply_mesh_lod_ratios_raw(multi_mesh_item, lod_index, raw_ratios)
		else:
			# Los árboles no traen distancias: son las que venían usando de hecho. Antes
			# se pedían [384, 768, 2500], pero el orden de asignación de los ratios las
			# recortaba a 0,35 / 0,6 / 1,0 de su banda (768 m).
			var dists: Array = item.get("mesh_lod_distances_m", [270, 460, 768])
			_apply_mesh_lod_distances(multi_mesh_item, lod_index, dists)
	else:
		# items sin LOD (MeshInstance directa, Rock3D): sin collision_shapes, dependen de
		# 'scene' para que el módulo instancie el nodo físico cerca del jugador.
		if item.get("pickup", false):
			# Se recoge: la malla y, solo cerca (collision_distance_m), un cuerpo en PhysicsLayers.PICKUP que
			# no estorba a nadie, para encontrarla y quitarla de la multimalla al cogerla.
			var mesh: Mesh = shared_data.effective_mesh
			multi_mesh_item.set_mesh(mesh, 0)
			multi_mesh_item.collision_shapes = [mesh.create_convex_shape(true, true), Transform3D.IDENTITY]
			multi_mesh_item.collision_layer = PhysicsLayers.PICKUP
			multi_mesh_item.collision_mask = 0
		elif item.get("collision", true):
			multi_mesh_item.scene = shared_data.packed_scene
		else:
			# Decorado sin física: solo la malla. Con la escena, el módulo crea un cuerpo por
			# instancia al cargar cada bloque: unas 2300 piedras pequeñas solo alrededor del spawn.
			multi_mesh_item.set_mesh(shared_data.effective_mesh, 0)


	# Opciones gráficas: sin sombras de vegetación, o solo las de los árboles cercanos (las del
	# impostor, que es lo que proyecta a partir del LOD2, se quitan; ver TreeDetailRenderer).
	var shadows_level: int = SettingsManager.vegetation_shadows()
	var casts: bool = item.get("cast_shadow", true) and shadows_level > 0 \
		and not (shadows_level == 1 and item.has("tree_lods"))
	if not casts:
		if "cast_shadow" in multi_mesh_item:
			multi_mesh_item.cast_shadow = RenderingServer.SHADOW_CASTING_SETTING_OFF
		else:
			push_warning("VoxelInstanceLibraryMultiMeshItem sin 'cast_shadow' en esta versión del módulo")

	# Radio (m) dentro del cual el módulo crea colliders, independiente del alcance visual: un
	# árbol de la banda 4 se sigue viendo a 700 m pero deja de llevar cuerpo físico. Además pasa
	# el alta y baja de colliders a la vía presupuestada por distancia
	# (collision_update_budget_microseconds del instancer), que la reparte entre frames en vez de
	# tirar miles de nodos en uno. El módulo compara contra la distancia al CHUNK, no a la
	# instancia, así que el corte real es más grueso que este número.
	var collision_distance: float = float(item.get("collision_distance_m", -1.0))
	if collision_distance > 0.0:
		if "collision_distance" in multi_mesh_item:
			multi_mesh_item.collision_distance = collision_distance
		else:
			push_warning("VoxelInstanceLibraryMultiMeshItem sin 'collision_distance' en esta versión del módulo")

	var library_id = _next_library_id
	_next_library_id += 1
	voxel_instancer.library.add_item(library_id, multi_mesh_item)
	if not shared_data.get("perch_data", {}).is_empty():
		tree_perch_catalog[library_id] = shared_data.perch_data
	if item.get("pickup", false):
		pickup_library_ids[library_id] = StringName(item.get("pickup_item", "stone_01"))

	# Plantilla del item, que marca lo que se tala (TreeFelling). Va en un dict aparte
	# y NO en multi_mesh_item.scene: ponerla ahí haría que el módulo instancie un nodo por
	# árbol cercano en cada banda de LOD (bajón de rendimiento). La colisión de los árboles
	# con LOD ya la dan collision_shapes. El decorado estático no se registra: sin plantilla,
	# no se tala aunque se le dé un hachazo.
	if interactive:
		planet_item_packed_scenes[library_id] = shared_data.packed_scene

	var wind_speed: float = item.wind_speed if item.has("wind_speed") else 0.0
	multi_mesh_array.append({"mesh_item": multi_mesh_item, "wind_speed": wind_speed})

	if shared_data.registered_scene != null:
		planet_item_scenes[library_id] = shared_data.registered_scene

	if shared_data.effective_mesh:
		for surface_idx in shared_data.effective_mesh.get_surface_count():
			var mat = shared_data.effective_mesh.surface_get_material(surface_idx)
			if mat is ShaderMaterial:
				item_transparent_materials.append({"shader": mat as ShaderMaterial, "wind_speed": wind_speed})

## LOD0 conserva la doble cara; LOD1/2 usan una cara. LOD3 tiene su propio material.
## Registra los duplicados para actualizar el sol y el viento.
func _apply_lod_material_variants(lm: Array, wind_speed: float) -> void:
	if _twig_singleside_shader == null:
		_twig_singleside_shader = load("res://shaders/transparent_material_shader_singleside.gdshader")
	# clave: [material original, lod] -> duplicado, para no crear uno por superficie
	var cache: Dictionary = {}
	for lod_i in range(min(3, lm.size())):
		var mesh: Mesh = lm[lod_i]
		if mesh == null:
			continue
		var want_singleside: bool = lod_i > 0 and _twig_singleside_shader != null
		if not want_singleside:
			continue  # LOD0 conserva el material original.
		for s in mesh.get_surface_count():
			var mat = mesh.surface_get_material(s)
			if not (mat is ShaderMaterial):
				continue
			var sm := mat as ShaderMaterial
			if sm.shader == null or sm.shader.resource_path != _TWIG_SHADER_PATH:
				continue  # tronco u otro shader: no tocar
			var key: Array = [sm, lod_i]
			var dup: ShaderMaterial = cache.get(key)
			if dup == null:
				dup = sm.duplicate()
				if want_singleside:
					dup.shader = _twig_singleside_shader
				cache[key] = dup
				item_transparent_materials.append({"shader": dup, "wind_speed": wind_speed})
			mesh.surface_set_material(s, dup)

func _register_scene_item(item, shared_data: Dictionary, generator: VoxelInstanceGenerator, lod_index: int) -> void:
	var scene_item := VoxelInstanceLibrarySceneItem.new()
	scene_item.generator = generator
	scene_item.lod_index = lod_index
	scene_item.scene = shared_data.packed_scene

	var library_id = _next_library_id
	_next_library_id += 1
	voxel_instancer.library.add_item(library_id, scene_item)

func _load_vegetation() -> void:
	var generators = definition.vegetation.generators
	var graph_functions = definition.vegetation.hemisphere_graph_function
	voxel_instancer.library.clear()
	planet_item_scenes.clear()
	planet_item_packed_scenes.clear()
	tree_perch_catalog.clear()
	pickup_library_ids.clear()
	tree_felling.clear_species()
	if tree_detail_renderer != null:
		tree_detail_renderer.queue_free()
		tree_detail_renderer = null
	multi_mesh_array.clear()
	item_transparent_materials.clear()
	_grass_lod_cache.clear()
	_vegetation_field = {}
	_next_library_id = 0
	_far_tree_items.clear()

	# async: _load_vegetation_item hornea el impostor LOD3 de los árboles con await
	# (render-to-texture). _load_vegetation se lanza como corrutina desde planet_loader
	# (fire-and-forget): la vegetación se registra en los primeros frames sin bloquear la
	# carga del planeta. Los items sin impostor (rocas, arbustos, grass) no suspenden.
	for i in definition.vegetation.items.size():
		await _load_vegetation_item(i, definition.vegetation.items[i], generators, graph_functions)
	_register_far_tree_items()
	rock_mining.prepare()


func _load_vegetation_item(i: int, item, generators, graph_functions) -> void:
	var generator_names: Array = []
	if item.generator is Array:
		generator_names = item.generator
	else:
		generator_names = [item.generator]

	var lod_indices: Array = _normalize_lod_indices(item.get("lod_index", 0))

	var shared_data = _build_item_shared_data(i, item)
	if shared_data.is_empty():
		return

	# Item de tarjeta de parche: la malla registrada no es la mata sino el parche
	# horneado, y su material ya se registra dentro del bake. La mata original solo
	# sirve de fuente para el horneado, así que deja de registrarse.
	var patch_cfg: Dictionary = item.get("grass_patch", {})
	# El sotobosque trae sus propias mallas; comparte con la hierba solo el relevo
	# de bandas, material, viento e iluminación.
	var grass_cfg: Dictionary = item.get("grass_lods", item.get("understory_lods", {}))
	if item.has("grass_lods"):
		var source_mesh: Mesh = shared_data.effective_mesh
		if not _grass_lod_cache.has(source_mesh):
			_grass_lod_cache[source_mesh] = GrassGeometryLods.build(source_mesh)
		shared_data.lod_meshes = _grass_lod_cache[source_mesh]
		if shared_data.lod_meshes.size() != 4:
			return
	if item.has("understory_lods") and shared_data.lod_meshes.size() != 4:
		push_error("El sotobosque necesita cuatro LODs: " + str(item.scene))
		return
	if not patch_cfg.is_empty():
		var card := await _vegetation_baker.bake_grass_patch(shared_data.effective_mesh, patch_cfg)
		if card == null:
			return
		shared_data.lod_meshes = [card, card, card, card]
		shared_data.effective_mesh = null

	# Fuera de las rutas de hierba, LOD3 = impostor (aspa) para árboles Tree3D.
	# Se hornea UNA vez por item, antes del bucle
	# de registro, para que set_mesh(lm[3], 3) instale el impostor directamente (sin hot-swap).
	var lm: Array = shared_data.lod_meshes
	if patch_cfg.is_empty() and grass_cfg.is_empty():
		var octa_impostor: bool = item.has("tree_lods") \
			and TreeOctaImpostor.has_atlases(str(item.scene).get_file().get_basename())
		if lm.size() == 4 and item.get("lod3_impostor", true) and not octa_impostor:
			var impostor := await _vegetation_baker.bake_tree_impostor(lm[0])
			if impostor != null:
				lm[3] = impostor

		# Variantes de material por mesh-LOD (una cara en los lejanos, tinte de debug).
		# Aquí y no en el registro: el item se registra una vez por banda y duplicaría.
		if lm.size() == 4 and not item.has("tree_lods"):
			_apply_lod_material_variants(lm, item.wind_speed if item.has("wind_speed") else 0.0)

	var emit_as_scene: bool = item.get("instance_as_scene", false)

	# Hierba y sotobosque siguen las opciones gráficas: menos densidad y, de cerca a lejos, se
	# quitan bandas enteras (la última que queda ya se desvanece en su propio alcance).
	var ground_cover: bool = not grass_cfg.is_empty() or not patch_cfg.is_empty()
	var cover_density: float = 1.0
	if ground_cover:
		cover_density = SettingsManager.grass_density_scale()
		lod_indices = lod_indices.filter(func(lod: int) -> bool: return lod <= SettingsManager.grass_max_band())
		if lod_indices.is_empty():
			return

	for generator_name in generator_names:
		var generator_config = null
		for gc in generators:
			if gc.name == generator_name:
				generator_config = gc
				break
		if generator_config == null:
			push_error("Error parsing vegetation, generator with name %s not found." % generator_name)
			continue

		if item.has("tree_lods"):
			_register_tree_item(i, item, shared_data, generator_config, graph_functions)
			continue

		for lod_index in lod_indices:
			var generator: VoxelInstanceGenerator = _build_generator(generator_config, graph_functions, lod_index)
			generator.density *= cover_density
			_apply_item_height(generator, item, shared_data)
			var band_data: Dictionary = shared_data
			if not grass_cfg.is_empty():
				band_data = shared_data.duplicate()
				var band: Dictionary = _build_grass_band(shared_data.lod_meshes, grass_cfg, lod_index,
					float(item.get("wind_speed", 0.2)),
					GrassGeometryLods.WIDTH_GROWTH if item.has("grass_lods") else -1.0)
				band_data.lod_meshes = band.meshes
				band_data.lod_ratios = band.ratios
				# El material de la banda ya se ha registrado en _build_grass_band.
				band_data.effective_mesh = null
			if emit_as_scene:
				_register_scene_item(item, band_data, generator, lod_index)
			else:
				_register_multi_mesh_item(i, item, band_data, generator, lod_index)


## Árboles Branching ("tree_lods": {}): un solo item en la banda lejana (4) con el impostor
## octaédrico, la colisión, la tala y los posaderos. La geometría cercana la dibuja
## TreeDetailRenderer en las posiciones de los cuerpos que el instancer crea para cada árbol
## cercano, con el LOD elegido por la distancia real de cada árbol y fundidos por árbol
## (TreeDetailRenderer.LOD_FADES, impostor más allá).
## Más allá del alcance de la banda 4, items solo de impostores en las bandas siguientes (sin
## colisión ni sombra) siguen el bosque: "far_bands" en tree_lods (por defecto 2: bandas 5 y
## 6, hasta ~2,2 km; 0 = sin ellos).
## Antes había una banda cercana aparte: el instancer genera posiciones distintas en cada
## item (su semilla lleva el id), así que en el relevo unos árboles se cambiaban por otros.
## La distancia de colisión (por chunk) debe cubrir el último fundido del detalle.
func _register_tree_item(i: int, item: Dictionary, shared_data: Dictionary, generator_config: Dictionary,
		graph_functions: Array) -> void:
	var lm: Array = shared_data.lod_meshes
	if lm.size() != 4:
		push_error("Árbol sin cuatro LODs: " + str(item.scene))
		return
	var wind_speed: float = float(item.get("wind_speed", 0.0))
	var band: int = int(item.tree_lods.get("band", 4))
	var impostor: Mesh = lm[3]
	var scene_name: String = str(item.scene).get_file().get_basename()
	if TreeOctaImpostor.has_atlases(scene_name):
		var foliage: ShaderMaterial = null
		for s in lm[0].get_surface_count():
			var material = lm[0].surface_get_material(s)
			if material is ShaderMaterial and material.shader.resource_path.ends_with("tree_foliage.gdshader"):
				foliage = material
		impostor = TreeOctaImpostor.build_mesh(lm[0], scene_name, foliage)
	var far_bands: int = SettingsManager.forest_far_bands(int(item.tree_lods.get("far_bands", 2)))
	var fade: Dictionary = TreeDetailRenderer.impostor_fade()
	if far_bands > 0:
		var handoff: Vector2 = _tree_band_reach(band)
		fade["fade_out_start"] = handoff.x
		fade["fade_out_end"] = handoff.y
	var data: Dictionary = shared_data.duplicate()
	data.lod_meshes = _tree_band_meshes([impostor, impostor, impostor, impostor], fade, wind_speed)
	data.lod_ratios = [0.997, 0.998, 0.999, 1.0]
	data.effective_mesh = null
	var generator := _build_generator(generator_config, graph_functions, band)
	_apply_item_height(generator, item, shared_data)
	var library_id: int = _next_library_id
	_register_multi_mesh_item(i, item, data, generator, band)

	var far_density: Array = item.tree_lods.get("far_density", FAR_TREE_DENSITY)
	for k in far_bands:
		_far_tree_items.append(_register_far_tree_item.bind(i, item, shared_data, generator_config,
			graph_functions, impostor, band, band + k + 1, float(far_density[mini(k, far_density.size() - 1)])))

	var detail: Array = []
	for lod in 3:
		detail.append(_tree_band_meshes([lm[lod]], TreeDetailRenderer.lod_fade(lod), wind_speed)[0])
	if tree_detail_renderer == null:
		tree_detail_renderer = TreeDetailRenderer.new(voxel_instancer)
		voxel_terrain.add_child(tree_detail_renderer)
	tree_detail_renderer.register_item(library_id, detail)


## Registra los items de impostores lejanos después de toda la vegetación. La semilla del
## instancer lleva el id del item: intercalados, desplazaban los ids de los siguientes y
## cambiaban las posiciones de todos los árboles (y de lo que se registra después) al añadir o
## quitar bandas lejanas. Con ids fuera de la secuencia (10000+) el instancer no generaba nada.
func _register_far_tree_items() -> void:
	for register in _far_tree_items:
		register.call()
	_far_tree_items.clear()


## Densidad de cada banda de impostores lejanos respecto a la del bosque (la última se repite).
const FAR_TREE_DENSITY := [1.0, 1.0]


## Tramo [inicio, fin] en que un item de árboles de la banda `band` se desvanece árbol a
## árbol: termina antes de que pueda faltar un bloque. hide_beyond_max_lod oculta bloques
## enteros por la distancia a su centro, así que el borde real del item es escalonado entre
## alcance - media diagonal del bloque y alcance + media diagonal.
func _tree_band_reach(band: int) -> Vector2:
	var end: float = _get_lod_view_distance(band) - float(_instancer_block_size(band)) * sqrt(3.0) * 0.5
	return Vector2(end - 40.0, end)


## Impostores de la banda `far_band`: mismos generador y malla que el item principal, sin
## colisión, tala ni sombra. Entra donde sale la banda anterior y sale en su alcance, donde
## entra la siguiente (la última deja así un borde redondo, sin los escalones de sus bloques). Sus árboles están en otras posiciones (la semilla lleva el id del item),
## pero el relevo más cercano es a ~500 m, donde cada árbol son unos pocos píxeles, y con el
## mismo tramado complementario que los LODs cercanos.
func _register_far_tree_item(i: int, item: Dictionary, shared_data: Dictionary,
		generator_config: Dictionary, graph_functions: Array, impostor: Mesh, band: int, far_band: int, density_factor: float) -> void:
	var handoff: Vector2 = _tree_band_reach(far_band - 1)
	var reach: Vector2 = _tree_band_reach(far_band)
	var fade := {"fade_in_start": handoff.x, "fade_in_end": handoff.y,
		"fade_out_start": reach.x, "fade_out_end": reach.y}
	var data: Dictionary = shared_data.duplicate()
	data.lod_meshes = _tree_band_meshes([impostor, impostor, impostor, impostor], fade, 0.0)
	data.lod_ratios = [0.997, 0.998, 0.999, 1.0]
	data.effective_mesh = null
	data.collision_shapes = []
	data.perch_data = {}
	var far_item: Dictionary = item.duplicate()
	far_item.erase("collision_distance_m")
	far_item.instance_as_scene = false
	far_item.cast_shadow = false
	var generator := _build_generator(generator_config, graph_functions, far_band)
	_apply_item_height(generator, item, shared_data)
	# La malla de cada banda se separa del SDF el doble que la anterior: la búsqueda de la
	# superficie crece igual o los árboles lejanos flotaban sobre las lomas.
	if generator.snap_to_generator_sdf_enabled:
		generator.snap_to_generator_sdf_search_distance *= float(1 << (far_band - band))
	# Menos árboles y más grandes, con la misma cobertura (densidad x escala²): la caja de la
	# banda llega hasta la cámara y la mayoría de sus instancias quedan colapsadas fuera de su
	# tramo, pero cuestan igual en la GPU.
	if density_factor <= 0.0:
		generator.density = 0.0
	elif density_factor < 1.0:
		generator.density *= density_factor
		generator.min_scale /= sqrt(density_factor)
		generator.max_scale /= sqrt(density_factor)
	_register_multi_mesh_item(i, far_item, data, generator, far_band)


## Copia las mallas con materiales propios (fundido por distancia) y los registra para
## recibir sol, planeta y viento. Una malla repetida comparte copia.
func _tree_band_meshes(meshes: Array, fade: Dictionary, wind_speed: float) -> Array:
	var mesh_copies: Dictionary = {}
	var material_copies: Dictionary = {}
	var result: Array = []
	for mesh in meshes:
		if mesh_copies.has(mesh):
			result.append(mesh_copies[mesh])
			continue
		var copy: ArrayMesh = mesh.duplicate()
		for s in copy.get_surface_count():
			var material = copy.surface_get_material(s)
			if not (material is ShaderMaterial):
				continue
			var dup: ShaderMaterial = material_copies.get(material)
			if dup == null:
				dup = material.duplicate()
				for key in fade:
					dup.set_shader_parameter(key, fade[key])
				material_copies[material] = dup
				item_transparent_materials.append({"shader": dup, "wind_speed": wind_speed})
			copy.surface_set_material(s, dup)
		mesh_copies[mesh] = copy
		result.append(copy)
	return result


## Las bandas del instancer son cajas anidadas que llegan todas hasta la cámara: la
## banda 2 genera matas a 5 m aunque solo se vean a partir de 64 m. Cada banda recibe
## su propio material para entrar cuando sale la anterior, sin duplicar densidad, y
## los bloques más allá de su último relevo no se dibujan.
## Cada banda usa UNA sola malla en sus cuatro slots de LOD: la del nivel que se ve
## cuando la banda ya ha entrado del todo. El morph del shader simplifica más allá (una
## malla más detallada imita las siguientes). Cambiar la malla de un bloque es muy caro
## en este motor: al volar a 20 m/s los cambios de LOD de hierba y sotobosque costaban
## ~9 ms por fotograma en el VoxelInstancer (de 110 a 50 fps); con una malla por banda
## no hay cambios y la GPU paga menos de 1 ms más quieta.
func _build_grass_band(lods: Array, cfg: Dictionary, lod_index: int, wind_speed: float,
		width_growth: float) -> Dictionary:
	var material: ShaderMaterial = lods[0].surface_get_material(0).duplicate()
	var limits: Dictionary = _grass_band_limits(cfg, lod_index)
	material.set_shader_parameter("fade_in_start", limits.in_start)
	material.set_shader_parameter("fade_in_end", limits.in_end)
	material.set_shader_parameter("fade_start", limits.out_start)
	material.set_shader_parameter("fade_end", limits.out_end)
	var morph_start: Array = cfg.get("lod_morph_start_m", [])
	var morph_end: Array = cfg.get("lod_morph_end_m", [])
	var morph: bool = morph_start.size() == 3 and morph_end.size() == 3
	material.set_shader_parameter("lod_morph_enabled", morph)
	if morph:
		material.set_shader_parameter("lod_morph_start", Vector3(morph_start[0], morph_start[1], morph_start[2]))
		material.set_shader_parameter("lod_morph_end", Vector3(morph_end[0], morph_end[1], morph_end[2]))
	if width_growth > 0.0:
		material.set_shader_parameter("lod_width_growth", width_growth)
	# Cada material decide su suavizado de normales; no imponer el de la hierba
	# a las hojas y ramas del sotobosque. El shader conserva 0.25 por defecto.
	item_transparent_materials.append({"shader": material, "wind_speed": wind_speed})

	# Del centro del bloque a su esquina más lejana: una mata puede estar así de lejos
	# (o de cerca) de la distancia con la que el instancer elige la malla del bloque.
	var block: float = float(_instancer_block_size(lod_index))
	var reach: float = block * 0.866 + 2.0
	var hide_distance: float = limits.out_end + reach
	# Sin morph (configuración incompleta) los niveles cambian a distancias fijas.
	var lod_ends: Array = morph_end if morph else cfg.get("mesh_lod_distances_m", [24, 55, 100])
	var band_lod: int = 0
	while band_lod < 3 and float(lod_ends[band_lod]) <= limits.in_end:
		band_lod += 1
	var mesh: ArrayMesh = _band_mesh(lods[band_lod], material)
	var view: float = _get_lod_view_distance(lod_index)
	var ratios: Array = []
	for k in 4:
		ratios.append(maxf(hide_distance / view, 0.004) - 0.001 * (3 - k))
	return {"meshes": [mesh, mesh, mesh, mesh], "ratios": ratios}


func _band_mesh(original: ArrayMesh, material: Material) -> ArrayMesh:
	var mesh: ArrayMesh = original.duplicate()
	mesh.surface_set_material(0, material)
	return mesh


## Lado de los bloques del instancer en una banda (mesh_block_size · 2^banda).
func _instancer_block_size(lod_index: int) -> int:
	return int(voxel_terrain.mesh_block_size) << lod_index


## Relevo de una banda: entra mientras sale la anterior. La banda 0 cede a la 1 en
## split_m; las demás terminan en max_distance_m o 8 m antes de su alcance. Medido con
## la cámara en distintos puntos de su bloque, la caja de la banda N cubre en todas
## direcciones al menos ese alcance (banda 1 ≥ 132 m, 2 ≥ 196 m, 3 ≥ 388 m).
func _grass_band_limits(cfg: Dictionary, lod_index: int) -> Dictionary:
	var ends: Array = []
	var widths: Array = []
	for band in lod_index + 1:
		var end: float
		var width: float = float(cfg.get("fade_width_m", 24.0))
		if band == 0:
			end = float(cfg.get("split_m", 40.0))
			width = float(cfg.get("split_fade_m", 12.0))
		elif band == 1:
			end = _get_lod_view_distance(1) - 8.0
		else:
			end = minf(float(cfg.get("max_distance_m", 320.0)), _get_lod_view_distance(band) - 8.0)
		ends.append(end)
		widths.append(minf(width, end - 1.0))
	var limits := {"in_start": 0.0, "in_end": 0.0,
		"out_start": maxf(ends[lod_index] - widths[lod_index], 1.0), "out_end": ends[lod_index]}
	if lod_index > 0:
		limits.in_start = maxf(ends[lod_index - 1] - widths[lod_index - 1], 1.0)
		limits.in_end = ends[lod_index - 1]
	return limits


## "height_m": [min, max] fija la altura real del item en metros y sustituye la escala del
## generador. Los árboles comparten generador y sus mallas miden de 3 a 14 m: una escala
## común de 2,5 a 7,5 dejaba pinos de 90 m y olivos de 22 m, con la corteza y las hojas
## estiradas en la misma proporción.
func _apply_item_height(generator: VoxelInstanceGenerator, item: Dictionary, shared_data: Dictionary) -> void:
	var heights: Array = item.get("height_m", [])
	if heights.size() != 2:
		return
	var lm: Array = shared_data.get("lod_meshes", [])
	var mesh: Mesh = lm[0] if not lm.is_empty() else shared_data.get("effective_mesh")
	if mesh == null or mesh.get_aabb().end.y <= 0.0:
		push_warning("Vegetación: height_m sin malla con altura en " + str(item.scene))
		return
	var mesh_height: float = mesh.get_aabb().end.y
	generator.min_scale = float(heights[0]) / mesh_height
	generator.max_scale = float(heights[1]) / mesh_height


## Normaliza un entero o lista de enteros a una lista de enteros no vacía.
func _normalize_lod_indices(raw) -> Array:
	var result: Array = []
	if raw is Array:
		for v in raw:
			result.append(int(v))
	else:
		result.append(int(raw))
	if result.is_empty():
		result.append(0)
	return result

func _build_tree_packed_scene(scene_instantiated: Node, tree3d) -> Dictionary:
	var trunk: MeshInstance3D = tree3d.get_trunk_instance()
	var twig: MeshInstance3D = tree3d.get_twig_instance()

	var lod_meshes: Array = []
	var combined_mesh: ArrayMesh
	if tree3d is Tree3D:
		lod_meshes = tree3d.bake_lods()
		combined_mesh = lod_meshes[0]
	else:
		combined_mesh = ArrayMesh.new()
		if trunk and trunk.mesh:
			combined_mesh.add_surface_from_arrays(
				Mesh.PRIMITIVE_TRIANGLES, trunk.mesh.surface_get_arrays(0))
			var trunk_mat = tree3d.get_material_trunk()
			if trunk_mat:
				combined_mesh.surface_set_material(combined_mesh.get_surface_count() - 1, trunk_mat)
		if twig and twig.mesh:
			var twig_mesh: Mesh = twig.mesh
			for i in range(twig_mesh.get_surface_count()):
				combined_mesh.add_surface_from_arrays(
					Mesh.PRIMITIVE_TRIANGLES, twig_mesh.surface_get_arrays(i))
				var dst_idx := combined_mesh.get_surface_count() - 1
				var twig_mats := _get_twig_materials_array(tree3d)
				if i < twig_mats.size() and twig_mats[i] != null:
					combined_mesh.surface_set_material(dst_idx, twig_mats[i])


	var new_root := scene_instantiated.duplicate(4) as Node3D
	var tree_mesh_child := MeshInstance3D.new()
	tree_mesh_child.name = "TreeMesh"
	tree_mesh_child.mesh = combined_mesh
	new_root.add_child(tree_mesh_child)
	tree_mesh_child.owner = new_root

	var collision_child: CollisionShape3D
	if tree3d is Tree3D and tree3d.shape == Tree3D.SHAPE_BRANCHING:
		# Solo el tronco, del suelo a la copa: el cilindro con la altura de toda la malla,
		# centrado en el origen, dejaba media colisión bajo tierra y cortaba el paso bajo la copa.
		var height: float = tree3d.get_collision_height()
		var shape := CylinderShape3D.new()
		shape.height = height
		shape.radius = tree3d.get_collision_radius()
		collision_child = CollisionShape3D.new()
		collision_child.shape = shape
		collision_child.position.y = height * 0.5
	else:
		var col_radius: float = (tree3d.get_stem_origin_radius() * 1.1) if tree3d is Bush3D else (tree3d.trunk_max_radius * 1.1)
		collision_child = _build_tree_collision(trunk, col_radius)
	new_root.add_child(collision_child)
	_set_owner_recursive(collision_child, new_root)

	# collision_shapes = lista alternada [Shape3D, Transform3D, ...]
	var collision_shapes: Array = []
	if collision_child.shape != null:
		collision_shapes = [collision_child.shape, collision_child.transform]

	var tree_scene := PackedScene.new()
	var perch_data: Dictionary = {}
	if tree3d is Tree3D:
		var manual: Array[Vector3] = []
		for marker in scene_instantiated.find_children("BirdPerch*", "Marker3D", true, false):
			var xf := (marker as Node3D).transform
			var parent := marker.get_parent()
			while parent != scene_instantiated and parent is Node3D:
				xf = (parent as Node3D).transform * xf
				parent = parent.get_parent()
			manual.append(xf.origin)
		perch_data = TreePerchBaker.bake(combined_mesh, manual)
	var err := tree_scene.pack(new_root)
	if err != OK:
		push_error("No se pudo empaquetar el árbol: %s" % err)
	new_root.queue_free()

	return {
		"scene": tree_scene,
		"mesh": combined_mesh,
		"lod_meshes": lod_meshes,
		"collision_shapes": collision_shapes,
		"perch_data": perch_data,
	}


## Devuelve el array de materiales del foliage según el tipo (Tree3D/Bush3D).
func _get_twig_materials_array(tree3d) -> Array:
	if tree3d is Bush3D:
		var arr = tree3d.foliage_materials
		return arr if arr != null else []
	else:
		var arr = tree3d.twig_materials
		return arr if arr != null else []


func _build_rock_packed_scene(scene_instantiated: Node, rock3d) -> Dictionary:
	var rock: MeshInstance3D = rock3d.get_rock_instance()
	var new_root := scene_instantiated.duplicate(4) as Node3D
	var rock_child := rock.duplicate() as MeshInstance3D
	if rock_child.mesh:
		rock_child.mesh = rock_child.mesh.duplicate()
		rock_child.mesh.surface_set_material(0, rock3d.material_rock)
	new_root.add_child(rock_child)
	rock_child.owner = new_root

	var collision_child := _build_rock_collision(rock_child)
	new_root.add_child(collision_child)
	_set_owner_recursive(collision_child, new_root)

	var rock_scene := PackedScene.new()
	var err := rock_scene.pack(new_root)
	if err != OK:
		push_error("No se pudo empaquetar la roca: %s" % err)
	new_root.queue_free()

	return {
		"scene": rock_scene,
		"mesh": rock_child.mesh,
	}

func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	node.owner = new_owner
	for child in node.get_children():
		_set_owner_recursive(child, new_owner)


func _init(_voxel_terrain: VoxelLodTerrain) -> void:
	_vegetation_baker = VegetationBaker.new(self)
	voxel_terrain = _voxel_terrain
	voxel_instancer = VoxelInstancer.new()
	voxel_instancer.library = VoxelInstanceLibrary.new()
	voxel_instancer.up_mode = VoxelInstancer.UP_MODE_SPHERE
	voxel_terrain.add_child(voxel_instancer)
	tree_felling = TreeFelling.new(self)
	voxel_terrain.add_child(tree_felling)
	rock_mining = RockMining.new(self)
	voxel_terrain.add_child(rock_mining)
	shader_material = ShaderMaterial.new()
	shader_material.shader = load("res://shaders/terrain/planet_biomes.gdshader")


func setup_shader_parameters() -> void:
	voxel_terrain.material = shader_material
	definition.apply_shader_parameters(shader_material)

	update_world_center()

	shader_material.set_shader_parameter("center", planet_position)
	shader_material.set_shader_parameter("radius", radius)
	# Con esto el shader estima el vóxel de cada LOD para no leer profundidad bajo tierra en laderas
	# lejanas (ver UndergroundDepth y el vertex() del shader).
	shader_material.set_shader_parameter("underground_lod_distance",
		minf(voxel_terrain.lod_distance, voxel_terrain.secondary_lod_distance))

	var means := PackedFloat32Array()
	means.resize(8)
	for i in mini(definition.textures.size(), means.size()):
		means[i] = TerrainMaterialData.mean_luma(definition.textures[i])
	shader_material.set_shader_parameter("texture_mean_luma", means)
	shader_material.set_shader_parameter("slope_mean_luma", TerrainMaterialData.mean_luma(definition.slope_texture))
	shader_material.set_shader_parameter("albedo_means_ready", true)

	# El uniform es un array fijo de MAX_TEXTURES (8): sin rellenar, las que falten valdrían 0 (negro).
	var albedo_adjust := definition.texture_albedo_adjust.duplicate()
	while albedo_adjust.size() < 8:
		albedo_adjust.append(Vector4.ONE)
	shader_material.set_shader_parameter("texture_albedo_adjust", albedo_adjust)

	shader_material.set_shader_parameter("has_water", 1 if has_water else 0)
	shader_material.set_shader_parameter("water_radius", radius - water_radius)

	climate = ClimateField.new(definition.climate_settings, radius)
	if climate.enabled:
		climate.push_shader_globals()
	shader_material.set_shader_parameter("climate_enabled", climate.enabled)
	# Índices en "textures" de la nieve que pinta el frío y del hielo glaciar de las laderas.
	var climate_terrain: Dictionary = definition.climate_settings.get("terrain", {})
	shader_material.set_shader_parameter("snow_texture_index", int(climate_terrain.get("snow_texture", 2)))
	# Cuánto sigue cada textura a la pradera con las estaciones (índice en "textures": peso).
	var meadow := PackedFloat32Array()
	meadow.resize(8)
	var meadow_cfg: Dictionary = climate_terrain.get("meadow_textures", {})
	for key in meadow_cfg:
		meadow[int(key)] = float(meadow_cfg[key])
	shader_material.set_shader_parameter("texture_meadow", meadow)
	shader_material.set_shader_parameter("glacier_texture_index", int(climate_terrain.get("glacier_texture", -1)))
	# Vista de depuración de la nieve (ver planet_biomes.gdshader). Tiene que ir antes del primer
	# mallado: los bloques ya mallados guardan su copia del material y no ven cambios posteriores.
	if OS.get_cmdline_user_args().has("--debug-snow"):
		shader_material.set_shader_parameter("debug_snow_view", 1)

	_setup_reef_shader_parameters()
	_setup_ore_shader_parameters()


## Textura de los escollos y la franja en que manda. Sin las cuatro texturas se queda apagado: la
## roca sale con la arena de la orilla, que es lo que había antes, y no con samplers sin enlazar.
func _setup_reef_shader_parameters() -> void:
	if not has_water:
		shader_material.set_shader_parameter("reef_enabled", 0)
		shader_material.set_shader_parameter("reef_packed_material", false)
		return
	var albedo := load(definition.reef_settings.get("texture", "")) as Texture2D
	var nrm := load(definition.reef_settings.get("normal_texture", "")) as Texture2D
	var packed_path: String = definition.reef_settings.get("packed_material_texture", "")
	var packed := not packed_path.is_empty()
	var rough := load(packed_path if packed else definition.reef_settings.get("roughness_texture", "")) as Texture2D
	var ao: Texture2D = null
	if not packed:
		ao = load(definition.reef_settings.get("ao_texture", "")) as Texture2D
	var ready: bool = has_water and albedo != null and nrm != null and rough != null and (packed or ao != null)
	shader_material.set_shader_parameter("reef_enabled", 1 if ready else 0)
	shader_material.set_shader_parameter("reef_packed_material", packed)
	if not ready:
		return

	shader_material.set_shader_parameter("reef_texture", albedo)
	shader_material.set_shader_parameter("reef_normal_texture", nrm)
	shader_material.set_shader_parameter("reef_roughness_texture", rough)
	if not packed:
		shader_material.set_shader_parameter("reef_ao_texture", ao)
	# Por defecto la franja cubre el arrecife entero: desde el borde hondo hasta un poco por encima
	# de la cresta, para que la punta emergida no vuelva a ser arena justo al salir del agua.
	var depth_max: float = maxf(float(definition.reef_settings.get("depth_max", 45.0)), 1.0)
	var crest: float = float(definition.reef_settings.get("crest_height", 14.0))
	shader_material.set_shader_parameter("reef_band_low",
		float(definition.reef_settings.get("band_low", -depth_max)))
	shader_material.set_shader_parameter("reef_band_high",
		float(definition.reef_settings.get("band_high", crest + 4.0)))
	shader_material.set_shader_parameter("reef_slope_threshold",
		float(definition.reef_settings.get("texture_slope_threshold", 0.10)))
	shader_material.set_shader_parameter("reef_slope_softness",
		float(definition.reef_settings.get("texture_slope_softness", 0.14)))

func _setup_ore_shader_parameters() -> void:
	var ore_albedo: Array[Texture2D] = []
	var ore_normal: Array[Texture2D] = []
	var ore_roughness: Array[Texture2D] = []

	for ore in definition.ore_settings:
		var albedo := load(ore.get("texture", "")) as Texture2D
		var nrm := load(ore.get("normal_texture", "")) as Texture2D
		var rough := load(ore.get("roughness_texture", "")) as Texture2D
		if albedo and nrm and rough:
			ore_albedo.append(albedo)
			ore_normal.append(nrm)
			ore_roughness.append(rough)
		else:
			push_warning("OreSettings: missing texture for ore '%s'" % ore.get("name", "?"))

	shader_material.set_shader_parameter("ore_count", ore_albedo.size())
	if not ore_albedo.is_empty():
		shader_material.set_shader_parameter("ore_albedo_textures", ore_albedo)
		shader_material.set_shader_parameter("ore_normal_textures", ore_normal)
		shader_material.set_shader_parameter("ore_roughness_textures", ore_roughness)


func setup_voxel_generator() -> void:
	# El generador se prepara ENTERO antes de colgarlo del terreno. Los ríos necesitan hornear el
	# relieve del propio generador para deducir por dónde corren, y si el terreno ya estuviera
	# mallando se vería el planeta rehacerse a medias.
	#
	# La copia tiene que ser DEEP_DUPLICATE_ALL, no duplicate(true): en Godot 4.6 duplicate(true)
	# equivale a DEEP_DUPLICATE_INTERNAL y NO copia las subfunciones que vienen de otro fichero, así
	# que el grafo preparado comparte river_carve.tres con la caché del ResourceLoader. Al aplicarle
	# RiverGenerator.apply, las imágenes horneadas se escriben en el recurso de DISCO: el editor lo
	# ve sucio, lo guarda, y river_carve.tres acabó pesando 173 MB en el repositorio.
	var prepared: VoxelGenerator
	if !definition.terrain_generator_path.is_empty():
		prepared = load(definition.terrain_generator_path).duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	else:
		prepared = voxel_terrain.generator.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)

	if not prepared is VoxelGeneratorGraph:
		voxel_terrain.generator = prepared
		return

	var graph_generator: VoxelGeneratorGraph = prepared

	var graph_generator_function: VoxelGraphFunction = graph_generator.get_main_function()
	var all_functions: Array = [graph_generator_function]
	_gather_subfunctions(graph_generator_function, all_functions)

	var needs_compile := false
	for fn in all_functions:
		if _apply_radius(fn, radius):
			needs_compile = true

	if not definition.ore_settings.is_empty():
		_apply_ore_params(all_functions, definition.ore_settings)
		needs_compile = true

	if _apply_reef_params(all_functions):
		needs_compile = true

	if _setup_rivers(graph_generator):
		needs_compile = true

	if needs_compile:
		var compile_result = graph_generator.compile()
		if compile_result is Dictionary and not compile_result.get("success", true):
			push_error("Planet: VoxelGraph compile falló: %s (nodo %s)" % [
				compile_result.get("message", ""), compile_result.get("node_id", -1)])

	voxel_terrain.generator = graph_generator

	if not definition.ore_settings.is_empty():
		_publish_ore_drop_table()


## Hornea (o recupera del caché) el campo de ríos y lo enchufa al grafo. Devuelve true si el grafo
## cambió y hay que recompilar.
##
## Red de cauces horneada, o {} si este planeta no tiene rios. Trae la sopa de segmentos en
## coordenadas del mapa de hidrologia y su semianchura, que es lo que consume el audio del agua.
func get_river_network() -> Dictionary:
	return _river_field


## Metros de roca sobre `world_pos` contra la superficie sin cuevas (ver UndergroundDepth): 0 al aire
## libre, en valles y cumbres incluidos; -1 si el terreno de ahí no está cargado a LOD 0.
func get_underground_depth(world_pos: Vector3) -> float:
	if voxel_terrain == null:
		return -1.0
	if _depth_tool == null:
		_depth_tool = voxel_terrain.get_voxel_tool()
	return UndergroundDepth.at(voxel_terrain, _depth_tool, world_pos)


## El horneado necesita el relieve del propio generador, así que se hace sobre una copia limpia: la
## que se hornea lleva las imágenes neutras y no talla nada, que es justo el terreno "sin ríos" del
## que hay que deducir por dónde corre el agua.
func _setup_rivers(graph_generator: VoxelGeneratorGraph) -> bool:
	if definition.river_settings.is_empty() or not bool(definition.river_settings.get("enabled", true)):
		return false
	if not has_water:
		push_warning("Planet: los ríos necesitan mar como nivel base; se quedan sin generar.")
		return false

	var height_range := float(definition.river_settings.get("height_range", 2000.0))
	var sea_level_radius := radius - water_radius
	var key := _river_cache_key(height_range)
	var path := "user://maps/%s_rivers.bin" % (entity_id if entity_id != "" else "planet")

	var field := RiverField.load_from(path, key)
	if field.is_empty():
		var started := Time.get_ticks_msec()
		var source: VoxelGeneratorGraph = graph_generator.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		_disable_reefs(source)
		source.compile()
		field = RiverGenerator.build_field(source, radius, sea_level_radius, height_range,
			definition.river_settings)
		if field.is_empty():
			push_warning("Planet: no salió ningún cauce; el terreno se queda sin ríos.")
			return false
		RiverField.save_to(field, path, key)
		print("[rivers] %d tramos horneados en %.1f s"
			% [int(field.get("segments", 0)), (Time.get_ticks_msec() - started) / 1000.0])

	_river_field = field
	return RiverGenerator.apply(graph_generator, field)


## Copia del grafo de densidad con las manchas de "noise" multiplicadas a su salida, para los
## generadores con threshold (ver _build_generator). Reproduce la regla que aplica el módulo al
## ruido cuando no hay grafo, medida contando instancias: cada punto se queda con probabilidad
## clamp((ruido + threshold) / falloff, 0, 1)², o si ruido + threshold > 0 cuando falloff es 0.
## El azar por punto sale de un hash de la posición. Se pierde "on_scale": el grafo solo filtra.
static func _with_patch_noise(source: VoxelGraphFunction, noise_config: Dictionary) -> VoxelGraphFunction:
	var graph := source
	# Sin campo de ríos llega el recurso cacheado del ResourceLoader, que no se puede tocar.
	if graph.resource_path != "":
		graph = source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var output := -1
	var inputs := {}
	for id in graph.get_node_ids():
		var type := graph.get_node_type_id(id)
		if type == VoxelGraphFunction.NODE_CUSTOM_OUTPUT:
			output = id
		elif type in [VoxelGraphFunction.NODE_INPUT_X, VoxelGraphFunction.NODE_INPUT_Y, VoxelGraphFunction.NODE_INPUT_Z]:
			inputs[type] = id
	var mask := {}
	for c in graph.get_connections():
		if c.dst_node_id == output:
			mask = c
	if mask.is_empty() or inputs.size() != 3:
		push_error("Vegetación: el grafo de densidad no tiene salida o entradas x, y, z; manchas sin aplicar.")
		return source
	graph.remove_connection(mask.src_node_id, mask.src_port_index, output, mask.dst_port_index)
	var x: int = inputs[VoxelGraphFunction.NODE_INPUT_X]
	var y: int = inputs[VoxelGraphFunction.NODE_INPUT_Y]
	var z: int = inputs[VoxelGraphFunction.NODE_INPUT_Z]

	# Mismo ruido que el FastNoiseLite de _build_generator (OpenSimplex2S, FBm, lacunarity 2, gain 0.5).
	var noise := ZN_FastNoiseLite.new()
	noise.noise_type = ZN_FastNoiseLite.TYPE_OPEN_SIMPLEX_2S
	noise.seed = int(noise_config.get("seed", 0))
	noise.period = 1.0 / float(noise_config.get("frequency", 0.01))
	noise.fractal_type = ZN_FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = int(noise_config.get("octaves", 2))
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	var noise_node: int
	if noise_config.get("dimension", "2D") == "3D":
		noise_node = graph.create_node(VoxelGraphFunction.NODE_FAST_NOISE_3D, Vector2())
		graph.add_connection(x, 0, noise_node, 0)
		graph.add_connection(y, 0, noise_node, 1)
		graph.add_connection(z, 0, noise_node, 2)
	else:
		noise_node = graph.create_node(VoxelGraphFunction.NODE_FAST_NOISE_2D, Vector2())
		graph.add_connection(x, 0, noise_node, 0)
		graph.add_connection(z, 0, noise_node, 1)
	graph.set_node_param(noise_node, 0, noise)
	var patch := _graph_op(graph, VoxelGraphFunction.NODE_ADD, noise_node, float(noise_config.get("threshold", 0.0)))

	var falloff := float(noise_config.get("falloff", 0.0))
	if falloff > 0.0:
		var ramp := _graph_op(graph, VoxelGraphFunction.NODE_MULTIPLY, patch, 1.0 / falloff)
		ramp = _graph_op(graph, VoxelGraphFunction.NODE_MIN, _graph_op(graph, VoxelGraphFunction.NODE_MAX, ramp, 0.0), 1.0)
		var chance := _graph_op(graph, VoxelGraphFunction.NODE_MULTIPLY, ramp, ramp)
		# fract(sin(x·12.9898 + y·78.233 + z·37.719) · 43758.5453), en [0, 1).
		var h := _graph_op(graph, VoxelGraphFunction.NODE_ADD,
			_graph_op(graph, VoxelGraphFunction.NODE_MULTIPLY, x, 12.9898),
			_graph_op(graph, VoxelGraphFunction.NODE_MULTIPLY, y, 78.233))
		h = _graph_op(graph, VoxelGraphFunction.NODE_ADD, h, _graph_op(graph, VoxelGraphFunction.NODE_MULTIPLY, z, 37.719))
		h = _graph_op(graph, VoxelGraphFunction.NODE_MULTIPLY, _graph_op(graph, VoxelGraphFunction.NODE_SIN, h), 43758.5453)
		var dice := _graph_op(graph, VoxelGraphFunction.NODE_SUBTRACT, h, _graph_op(graph, VoxelGraphFunction.NODE_FLOOR, h))
		patch = _graph_op(graph, VoxelGraphFunction.NODE_SUBTRACT, chance, dice)

	# La máscara nunca es negativa: el signo del producto es el de la mancha y fuera del bioma da 0.
	var result := _graph_op(graph, VoxelGraphFunction.NODE_MULTIPLY, mask.src_node_id, patch,
		mask.src_port_index)
	graph.add_connection(result, 0, output, 0)
	return graph


## Nodo conectado a `a` por su primera entrada; `b` (segunda entrada) es un id de nodo si es int,
## una constante si es float y nada en los nodos de una entrada (Sin, Floor).
static func _graph_op(graph: VoxelGraphFunction, type: int, a: int, b = null, a_port: int = 0) -> int:
	var node := graph.create_node(type, Vector2())
	graph.add_connection(a, a_port, node, 0)
	if b is int:
		graph.add_connection(b, 0, node, 1)
	elif b != null:
		graph.set_node_default_input(node, 1, float(b))
	return node


## Carga un grafo de densidad de vegetación con el campo de ríos ya metido. Se duplica porque
## varios generadores comparten el mismo recurso y aquí se le escriben parámetros: sin duplicar, el
## parcheo se propagaría al recurso cacheado por el ResourceLoader.
##
## Una copia por generador, aunque el grafo sea el mismo: compartida, asignarla a un generador nuevo
## espera a los hilos que ya generan instancias con ella, y en el arranque (con el terreno cargando
## alrededor del spawn) eso multiplicaba por tres el coste total.
func _load_vegetation_graph(path: String) -> VoxelGraphFunction:
	var graph: VoxelGraphFunction = load(path)
	if graph == null or _river_field.is_empty():
		return graph
	var copy: VoxelGraphFunction = graph.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	if RiverGenerator.apply(copy, _vegetation_river_field()):
		return copy
	return graph


## El campo de ríos con la imagen de distancias reducida, para los grafos de vegetación. El módulo
## procesa la imagen entera cada vez que se asigna el grafo a un generador (~0.44 s a 16384x8192,
## ~0.03 s a 4096x2048) y hay unos 60 generadores. La vegetación solo reconstruye la ladera del valle
## para sus compuertas de profundidad, y esa reconstrucción ya la limita la imagen del lecho, mucho
## más gruesa: la resolución fina solo le hace falta al tallado del terreno.
func _vegetation_river_field() -> Dictionary:
	if _vegetation_field.is_empty():
		_vegetation_field = _river_field.duplicate()
		var width := int(definition.river_settings.get("vegetation_dist_width", 4096))
		var dist: Image = _river_field.dist
		if width > 0 and width < dist.get_width():
			var small: Image = dist.duplicate()
			small.resize(width, width * dist.get_height() / dist.get_width(), Image.INTERPOLATE_BILINEAR)
			_vegetation_field.dist = small
	return _vegetation_field


## Identifica la configuración con la que se horneó el campo. Incluye la huella del generador, así
## que tocar el grafo del terreno invalida el caché de los ríos por su cuenta.
func _river_cache_key(height_range: float) -> String:
	var parts := PackedStringArray([
		"v%d" % RiverField.FILE_VERSION,
		"r%.3f" % radius,
		"w%.3f" % water_radius,
		"h%.3f" % height_range,
		JSON.stringify(definition.river_settings),
		PlanetWorldMap._resource_fingerprint(definition.terrain_generator_path),
	])
	return "|".join(parts).sha256_text()

## Empuja los parámetros de ore del JSON a los nodos nombrados del VoxelGraph (earth_ore_field.tres lo
## genera tools/terrain/build_ore_field.py desde el mismo JSON; ver docs/terrain_materials.md#menas).
## Las vetas de un "spot_group" comparten manchas y profundidad (las pone la primera del grupo) y se
## reparten las alturas en franjas seguidas.
func _apply_ore_params(functions: Array, ores: Array) -> void:
	var groups := {}
	for ore in ores:
		if ore.has("spot_group"):
			var key := String(ore.spot_group)
			if not groups.has(key):
				groups[key] = []
			groups[key].append(ore)
			continue
		var type_id := int(ore.get("type_id", 1))
		_push_ore_spots(functions, "ore_spots_%d" % type_id, ore)
		if ore.has("depth_min"):
			_apply_cave_ore_band(functions, type_id, ore)
			continue
		_push_ore_depth(functions, "ore_depth_%d" % type_id, ore)
		if ore.has("min_height") or ore.has("max_height"):
			var soft: float = maxf(float(ore.get("height_softness", 20.0)), 0.001)
			var low: float = radius + float(ore.get("min_height", -1.0e6))
			var high: float = radius + float(ore.get("max_height", 1.0e6))
			_set_smoothstep(functions, "ore_alt_lo_%d" % type_id, low - soft, low)
			_set_smoothstep(functions, "ore_alt_hi_%d" % type_id, high + soft, high)
	for key: String in groups:
		var members: Array = groups[key]
		var first: Dictionary = members[0]
		_push_ore_spots(functions, "ore_spots_%s" % key, first)
		_push_ore_depth(functions, "ore_depth_%s" % key, first)
		var ordered := members.duplicate()
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("min_height", 0.0)) < float(b.get("min_height", 0.0)))
		var edges: Array[float] = []
		for ore: Dictionary in ordered:
			edges.append(float(ore.get("min_height", 0.0)))
		edges.append(float(ordered.back().get("max_height", 4000.0)))
		var soft: float = maxf(float(first.get("height_softness", 12.0)), 0.001)
		for k in edges.size():
			_set_smoothstep(functions, "ore_step_%s_%d" % [key, k], radius + edges[k] - soft * 0.5,
				radius + edges[k] + soft * 0.5)


func _push_ore_spots(functions: Array, spots_name: String, ore: Dictionary) -> void:
	var spots_fn := _find_owner(functions, spots_name)
	if spots_fn == null:
		push_warning("Planet: no se encontró el nodo Spots3D '%s' en ninguna función." % spots_name)
		return
	var spots := spots_fn.find_node_by_name(spots_name)
	_push_param(spots_fn, spots, VoxelGraphFunction.NODE_SPOTS_3D, "seed", int(ore.get("noise_seed", 0)))
	_push_param(spots_fn, spots, VoxelGraphFunction.NODE_SPOTS_3D, "cell_size", float(ore.get("cell_size", 40.0)))
	_push_param(spots_fn, spots, VoxelGraphFunction.NODE_SPOTS_3D, "spot_radius", float(ore.get("spot_radius", 12.0)))
	_push_param(spots_fn, spots, VoxelGraphFunction.NODE_SPOTS_3D, "jitter", float(ore.get("jitter", 0.9)))


## La profundidad bajo la superficie hasta la que llega la veta (el Divide del gate).
func _push_ore_depth(functions: Array, depth_name: String, ore: Dictionary) -> void:
	var depth_fn := _find_owner(functions, depth_name)
	if depth_fn == null:
		push_warning("Planet: no se encontró el nodo Divide '%s' del gate de profundidad." % depth_name)
		return
	var depth_node := depth_fn.find_node_by_name(depth_name)
	var depth: float = maxf(float(ore.get("surface_depth", 10.0)), 0.001)
	_push_param(depth_fn, depth_node, VoxelGraphFunction.NODE_DIVIDE, "b", depth)

## Empuja los params de un ore de cueva: banda de profundidad radial + gate de proximidad a la cueva.
func _apply_cave_ore_band(functions: Array, type_id: int, ore: Dictionary) -> void:
	var depth_min: float = maxf(float(ore.get("depth_min", 10.0)), 0.0)
	var depth_max: float = maxf(float(ore.get("depth_max", 60.0)), depth_min + 0.001)
	var soft: float = maxf(float(ore.get("band_softness", 10.0)), 0.001)
	var alt_high: float = radius - depth_min
	var alt_low: float = radius - depth_max

	_set_smoothstep(functions, "ore_band_lo_%d" % type_id, alt_low, alt_low + soft)
	_set_smoothstep(functions, "ore_band_hi_%d" % type_id, alt_high + soft, alt_high)

	var shell: float = maxf(float(ore.get("cave_shell", 12.0)), 0.001)
	_set_smoothstep(functions, "cave_gate_%d" % type_id, -shell, 0.0)

## Margen (m) con que la cáscara radial de poda envuelve al arrecife por debajo y por encima.
## Tiene que dejar dentro la isosuperficie más un vóxel del LOD más lejano en que el arrecife aún se
## malla: por dentro la cáscara no cambia nada, y por fuera es lo único que evita evaluar el ruido.
const _REEF_SHELL_BELOW := 25.0
const _REEF_SHELL_ABOVE := 17.5


## Ajusta los arrecifes al nivel del mar y deriva la envolvente radial de su altura y profundidad.
## Devuelve true si el grafo necesita recompilarse.
func _apply_reef_params(functions: Array) -> bool:
	if _find_owner(functions, "reef_sea_offset") == null:
		return false

	# El grafo razona en altura sobre el mar, y el mar está en radius - water_radius.
	_set_graph_value(functions, "reef_sea_offset", "b", water_radius)
	# El radio se lo pone el arrecife, no _apply_radius: allí se busca entre los inputs pero se
	# escribe como param, y en SdfSphere el radio es un input, así que la escritura no llega nunca.
	_set_graph_value(functions, "reef_planet_sdf", "radius", radius)

	if not has_water or not bool(definition.reef_settings.get("enabled", true)):
		# Ventana radial vacía: el Select se queda siempre con el terreno y el ruido ni se evalúa.
		_set_graph_value(functions, "reef_shell_lo", "threshold", 1.0e9)
		_set_graph_value(functions, "reef_shell_hi", "threshold", -1.0e9)
		return true

	var depth_max: float = maxf(float(definition.reef_settings.get("depth_max", 45.0)), 1.0)
	var depth_soft: float = clampf(float(definition.reef_settings.get("depth_softness", 17.0)), 0.1, depth_max)
	var shore_margin: float = float(definition.reef_settings.get("shore_margin", 1.0))
	var shore_soft: float = maxf(float(definition.reef_settings.get("shore_softness", 4.0)), 0.1)
	var crest: float = float(definition.reef_settings.get("crest_height", 24.0))
	var threshold: float = float(definition.reef_settings.get("rock_threshold", 0.0))
	# Una cobertura saturada aplana las crestas; rock_softness regula esa saturación.
	var rock_soft: float = maxf(float(definition.reef_settings.get("rock_softness", 1.0)), 0.01)
	# Una potencia mayor estrecha las crestas y reduce su cobertura.
	var sharpness: int = maxi(int(definition.reef_settings.get("sharpness", 1)), 1)

	_set_smoothstep(functions, "reef_deep_gate", -depth_max, -(depth_max - depth_soft))
	_set_smoothstep(functions, "reef_land_gate", shore_margin, shore_margin - shore_soft)
	_set_smoothstep(functions, "reef_coverage", threshold, threshold + rock_soft)
	_set_graph_value(functions, "reef_sharpness", "power", sharpness)
	_set_graph_value(functions, "reef_crest", "b", crest)
	_set_graph_value(functions, "reef_shell_lo", "threshold", -(depth_max + _REEF_SHELL_BELOW))
	_set_graph_value(functions, "reef_shell_hi", "threshold", crest + _REEF_SHELL_ABOVE)

	if definition.reef_settings.has("head_size"):
		_set_noise_period(functions, "reef_noise", maxf(float(definition.reef_settings.head_size), 1.0))
	return true


## Excluye los arrecifes del generador de hidrología: son menores que la resolución del mapa
## y pueden desplazar artificialmente la costa y las desembocaduras.
func _disable_reefs(generator: VoxelGeneratorGraph) -> void:
	var main: VoxelGraphFunction = generator.get_main_function()
	var functions: Array = [main]
	_gather_subfunctions(main, functions)
	if _find_owner(functions, "reef_shell_lo") == null:
		return
	_set_graph_value(functions, "reef_shell_lo", "threshold", 1.0e9)
	_set_graph_value(functions, "reef_shell_hi", "threshold", -1.0e9)


## Modifica el recurso de ruido de la copia del generador, sin alterar el recurso de disco.
func _set_noise_period(functions: Array, node_name: String, period: float) -> void:
	var fn := _find_owner(functions, node_name)
	if fn == null:
		return
	var noise = fn.get_node_param(fn.find_node_by_name(node_name), 0)
	if noise != null:
		noise.period = period


## Localiza un nodo por nombre en cualquier (sub)función y le fija ese ajuste, sea un input por
## defecto o un param del nodo. Devuelve false si el nodo no está en ninguna.
func _set_graph_value(functions: Array, node_name: String, setting: String, value) -> bool:
	var fn := _find_owner(functions, node_name)
	if fn == null:
		push_warning("Planet: no se encontró el nodo '%s' del grafo." % node_name)
		return false
	var node_id := fn.find_node_by_name(node_name)
	_push_param(fn, node_id, fn.get_node_type_id(node_id), setting, value)
	return true


## Localiza un Smoothstep por nombre en cualquier (sub)función y le fija edge0/edge1.
func _set_smoothstep(functions: Array, node_name: String, edge0: float, edge1: float) -> void:
	var fn := _find_owner(functions, node_name)
	if fn == null:
		push_warning("Planet: no se encontró el Smoothstep '%s'." % node_name)
		return
	var node_id := fn.find_node_by_name(node_name)
	var tid := fn.get_node_type_id(node_id)
	_push_param(fn, node_id, tid, "edge0", edge0)
	_push_param(fn, node_id, tid, "edge1", edge1)

## Recorre la función principal y todas las sub-funciones (nodos Function) recursivamente.
func _gather_subfunctions(fn: VoxelGraphFunction, acc: Array) -> void:
	for node_id in fn.get_node_ids():
		var info = fn.get_node_type_info(fn.get_node_type_id(node_id))
		if not (info is Dictionary and info.get("name", "") == "Function"):
			continue
		var sub = fn.get_node_param(node_id, 0)
		if sub is VoxelGraphFunction and not acc.has(sub):
			acc.append(sub)
			_gather_subfunctions(sub, acc)

## Devuelve la (sub)función que contiene un nodo con ese nombre, o null.
func _find_owner(functions: Array, node_name: String) -> VoxelGraphFunction:
	for fn in functions:
		if fn.find_node_by_name(node_name) > 0:
			return fn
	return null

## Parchea el 'radius' del SdfSphere donde esté; devuelve true si parcheó algo.
func _apply_radius(fn: VoxelGraphFunction, radius_value: float) -> bool:
	var patched := false
	for node_id in fn.get_node_ids():
		var node_data = fn.get_node_type_info(fn.get_node_type_id(node_id))
		var radius_found := false
		for key in node_data:
			if key == "inputs":
				for params in node_data[key]:
					for param in params:
						if params[param] is String and params[param] == "radius":
							radius_found = true
							break
		if radius_found:
			fn.set_node_param_by_name(node_id, "radius", radius_value)
			patched = true
	return patched

func _push_param(fn: VoxelGraphFunction, node_id: int, type_id: int, setting: String, value) -> void:
	var info = fn.get_node_type_info(type_id)
	var in_idx := _input_index(info, setting)
	if in_idx >= 0:
		if fn.has_method("set_node_default_input"):
			fn.set_node_default_input(node_id, in_idx, value)
		else:
			push_warning("Planet: '%s' es input (idx %d) pero set_node_default_input no existe; ponlo a mano en el editor." % [setting, in_idx])
	else:
		fn.set_node_param_by_name(node_id, setting, value)

func _input_index(info, setting: String) -> int:
	if info is Dictionary and info.has("inputs"):
		var i := 0
		for desc in info["inputs"]:
			if _desc_name(desc) == setting:
				return i
			i += 1
	return -1

func _desc_name(desc) -> String:
	if desc is Dictionary:
		if desc.has("name") and desc["name"] is String:
			return desc["name"]
		for k in desc:
			if desc[k] is String:
				return desc[k]
	return ""

func _publish_ore_drop_table() -> void:
	var table := {}
	for ore in definition.ore_settings:
		var tid := int(ore.get("type_id", 0))
		if tid <= 0:
			continue
		table[tid] = {
			"item_id": StringName(ore.get("drop_item", "stone_01")),
			"min_count": int(ore.get("drop_count_min", 1)),
			"max_count": int(ore.get("drop_count_max", 1)),
		}
	voxel_terrain.set_meta("ore_drops", table)

func update_world_center() -> void:
	planet_position = voxel_terrain.get_parent().position

func _update_planet() -> void:
	var sun_changed := not _material_uniforms_initialized or sun_dir != _last_material_sun
	var position_changed := not _material_uniforms_initialized or planet_position != _last_material_position
	var wind_changed := not _material_uniforms_initialized or wind_direction != _last_material_wind
	# El sol se mueve en cada frame, y solo lo leen los shaders antiguos (_sun_materials). La lista
	# entera se recorre si cambia algo más o la propia lista, y cada MATERIAL_SWEEP_FRAMES por los
	# materiales sustituidos dentro de su entrada (desde el inspector).
	_frames_to_sweep -= 1
	var sweep := not _material_uniforms_initialized or position_changed or wind_changed \
		or weather_wind_multiplier != _last_wind_multiplier \
		or item_transparent_materials.size() != _last_material_count or _frames_to_sweep <= 0
	if sweep:
		_frames_to_sweep = MATERIAL_SWEEP_FRAMES
		_sun_materials.clear()
		for mat_struct in item_transparent_materials:
			var mat = mat_struct.shader as ShaderMaterial
			# Los materiales que se añaden o reemplazan reciben todo en su primer barrido.
			var fresh: bool = mat_struct.get("_updated_material") != mat or mat_struct.get("_updated_shader") != mat.shader
			var uses_sun := _shader_uses_sun_parameter(mat.shader)
			if uses_sun:
				_sun_materials.append(mat)
			if (fresh or sun_changed) and uses_sun:
				mat.set_shader_parameter("light_direction", sun_dir)
			if fresh or position_changed:
				mat.set_shader_parameter("planet_position", planet_position)
			if fresh or wind_changed:
				mat.set_shader_parameter("wind_direction", wind_direction)
			var speed: float = mat_struct.wind_speed * weather_wind_multiplier
			if fresh or speed != mat_struct.get("_updated_wind_speed"):
				mat.set_shader_parameter("wind_speed", speed)
				mat_struct["_updated_wind_speed"] = speed
			if fresh:
				mat_struct["_updated_material"] = mat
				mat_struct["_updated_shader"] = mat.shader
	elif sun_changed:
		for mat in _sun_materials:
			mat.set_shader_parameter("light_direction", sun_dir)
	_last_wind_multiplier = weather_wind_multiplier
	_last_material_count = item_transparent_materials.size()
	var external_changed := external_planet_materials.size() != _last_external_material_count
	if sun_changed or position_changed or external_changed:
		for mat in external_planet_materials:
			if (sun_changed or external_changed) and _shader_uses_sun_parameter(mat.shader):
				mat.set_shader_parameter("light_direction", sun_dir)
			if position_changed or external_changed:
				mat.set_shader_parameter("planet_position", planet_position)
	_last_material_sun = sun_dir
	_last_material_position = planet_position
	_last_material_wind = wind_direction
	_last_external_material_count = external_planet_materials.size()
	_material_uniforms_initialized = true


## Los shaders modernos usan LIGHT; los antiguos que declaran el uniform conservan
## su actualización. Consultar una vez por shader evita invalidar materiales que no lo usan.
func _shader_uses_sun_parameter(shader: Shader) -> bool:
	if not _sun_parameter_shaders.has(shader):
		var uses_sun := false
		if shader != null:
			for uniform in shader.get_shader_uniform_list():
				if uniform.name == "light_direction":
					uses_sun = true
					break
			var on_changed := _on_planet_shader_changed.bind(shader)
			if not shader.changed.is_connected(on_changed):
				shader.changed.connect(on_changed)
		_sun_parameter_shaders[shader] = uses_sun
	return _sun_parameter_shaders[shader]


func _on_planet_shader_changed(shader: Shader) -> void:
	_sun_parameter_shaders.erase(shader)
	_material_uniforms_initialized = false


## Da de alta un material con iluminación planetaria que no viene de la vegetación
## (equipo del jugador, props colocados). Recibe el centro del planeta y, en los shaders
## antiguos que la necesitan, la dirección del sol.
func register_planet_material(mat: ShaderMaterial) -> void:
	if mat != null and not external_planet_materials.has(mat):
		external_planet_materials.append(mat)
		if _shader_uses_sun_parameter(mat.shader):
			mat.set_shader_parameter("light_direction", sun_dir)
		mat.set_shader_parameter("planet_position", planet_position)


func unregister_planet_material(mat: ShaderMaterial) -> void:
	external_planet_materials.erase(mat)
