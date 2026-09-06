@tool
class_name Planet extends Node3D

## Nodo de un planeta: configura el terreno voxel y su shader de biomas, genera la vegetación
## (VoxelInstancer) con sus colisiones, y parchea el VoxelGraph (radio, ores) desde datos JSON.

const config = preload("res://scripts/config.gd")
@export_group("Terrain Settings")
@export var radius: float
@export var terrain_generator_path: String

@export_group("Biome Settings")
@export var biome_count: int
@export var textures_per_biome: int
@export var biome_latitude_ranges: Array[float] = []
@export var biome_transition_smoothness: float
@export var max_heights: Array[float] = []
@export var biome_texture_indices: Array[int] = []
@export var biome_noise_enabled: Array[int] = []
@export var biome_noise_source_texture_indices: Array[int] = []
@export var biome_noise_target_texture_indices: Array[int] = []
@export var biome_noise_scales: Array[float] = []
@export var biome_noise_thresholds: Array[float] = []
@export var biome_noise_smoothness: Array[float] = []
@export var biome_noise_seeds: Array[float] = []
@export var biome_noise_invert: Array[int] = []
@export var biome_noise_abs_latitude_mins: Array[float] = []
@export var biome_noise_abs_latitude_maxs: Array[float] = []
@export var biome_noise_latitude_smoothness: Array[float] = []
@export var textures: Array[Texture2D] = []
@export var normal_textures: Array[Texture2D] = []
@export var roughness_textures: Array[Texture2D] = []
@export var ao_textures: Array[Texture2D] = []
@export var height_textures: Array[Texture2D] = []

## Familia de sonido de cada textura de terreno, en el mismo orden que "textures". La usan
## las pisadas (ver SurfaceAudio): sin ella, todo el planeta suena a la familia por defecto.
@export var sound_materials: Array[StringName] = []
## Familia de sonido de la textura de pendiente.
@export var slope_sound_material: StringName = &"rock"
@export var slope_texture: Texture2D
@export var slope_normal_texture: Texture2D
@export var slope_roughness_texture: Texture2D
@export var slope_ao_texture: Texture2D
@export var slope_height_texture: Texture2D
@export var slope_threshold: float = 0.35
@export var slope_smoothness: float = 0.18
@export var slope_height_blend_strength: float = 0.0
@export var slope_height_blend_sharpness: float = 0.2
@export var slope_breakup_scale: float = 0.025
@export var slope_breakup_strength: float = 0.0
@export var slope_breakup_anisotropy: float = 2.5
@export var slope_strata_thickness: float = 18.0
@export var slope_strata_strength: float = 0.0
@export var slope_strata_warp: float = 0.35
@export var parallax_enabled: bool = false
@export var parallax_strength: float = 0.09
@export var transition_smoothness: float = 10.0
@export var height_transition_noise_scale: float = 0.015
@export var height_transition_noise_strength: float = 12.0
@export var macro_variation_scale: float = 0.006
@export var macro_variation_strength: float = 0.18
@export var vegetation: Dictionary
@export var wind_direction : Vector3

@export var item_transparent_materials : Array[Dictionary]
## Materiales planetarios ajenos a la vegetación (ver register_planet_material). Van en una
## lista aparte porque _load_vegetation vacía item_transparent_materials en cada carga del
## planeta y estos tienen que sobrevivir a ella (el jugador se registra una sola vez).
var external_planet_materials: Array[ShaderMaterial] = []
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
@export var ore_settings: Array[Dictionary] = []
## Bloque "river_settings" del JSON. Vacío = planeta sin ríos (el grafo lleva imágenes neutras que
## no tallan nada, así que no hace falta desconectar nada).
@export var river_settings: Dictionary = {}
## Bloque "reef_settings" del JSON: los escollos de la franja costera. Vacío = valores por defecto
## de coastal_reefs.tres; "enabled": false los apaga sin tocar el grafo.
@export var reef_settings: Dictionary = {}
## Identificador del planeta, para nombrar el caché del campo de ríos.
@export var entity_id: String = ""

## Campo de ríos horneado. Lo consume el terreno y también los grafos de densidad de vegetación,
## que sin él confunden un cauce hondo con una cueva.
var _river_field: Dictionary = {}

var planet_item_scenes: Dictionary
## library_id -> PackedScene plantilla, para clonar el item al talarlo sin instanciar
## nada en el módulo (ver _register_multi_mesh_item).
var planet_item_packed_scenes: Dictionary
var _next_library_id: int = 0

## Shader de follaje de doble cara (LOD cercano) y su variante de una cara (LOD lejano).
const _TWIG_SHADER_PATH := "res://shaders/transparent_material_shader.gdshader"
var _twig_singleside_shader: Shader = null

## Shader del impostor (aspa LOD3): unshaded pero con terminador día/noche.
const _IMPOSTOR_SHADER_PATH := "res://shaders/tree_impostor.gdshader"
var _impostor_shader: Shader = null

## Shaders de la tarjeta de parche de hierba: el de horneado (albedo plano dentro
## del SubViewport) y el de la tarjeta ya instanciada. Ver _bake_grass_patch.
const _GRASS_PATCH_SHADER_PATH := "res://shaders/grass_patch_impostor.gdshader"
const _GRASS_PATCH_BAKE_SHADER_PATH := "res://shaders/grass_patch_bake.gdshader"
var _grass_patch_shader: Shader = null
var _grass_patch_bake_shader: Shader = null

## Multiplicador global de viento sobre la vegetación, controlado por el WeatherController.
var weather_wind_multiplier: float = 1.0

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
	# Un bloque de LOD N tiene los mismos vóxeles pero cubre 4x más área, así que
	# EMIT_FROM_VERTICES da 4x menos instancias por m² en cada banda. lod_scale_gain
	# las agranda para compensar parte de esa pérdida de cobertura (1.0 = sin cambio).
	var scale_gain: float = pow(float(generator_config.get("lod_scale_gain", 1.0)), lod_index)
	if generator_config.has("min_scale"):
		generator.min_scale = generator_config.min_scale * scale_gain
	if generator_config.has("max_scale"):
		generator.max_scale = generator_config.max_scale * scale_gain
	if generator_config.has("noise_graph"):
		for graph_func in graph_functions:
			if graph_func.name == generator_config.noise_graph:
				generator.noise_graph = _load_vegetation_graph(graph_func.path)

	var graph_function = generator.noise_graph
	if graph_function:
		var noise_id = graph_function.find_node_by_name(&"Noise_01")
		if noise_id:
			if graph_function.get_node_type_id(noise_id) != VoxelGraphFunction.NODE_FAST_NOISE_3D:
				push_error("El nodo 'Noise_01' no es de tipo FastNoise3D")
				return

			var noise: ZN_FastNoiseLite = graph_function.get_node_param(noise_id, 0)
			print(noise)
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


func _build_scene_collision(scene_instantiated: Node) -> Array:
	var result: Array = []
	for child in scene_instantiated.get_children():
		if child is StaticBody3D:
			for sub in child.get_children():
				if sub is CollisionShape3D and sub.shape:
					result.append(sub.shape)
					result.append(sub.transform)
			if not result.is_empty():
				return result

	var mesh_child = scene_instantiated.get_child(0)
	if mesh_child is MeshInstance3D and mesh_child.mesh:
		var shape: ConvexPolygonShape3D = mesh_child.mesh.create_convex_shape(true, false)
		if shape:
			return [shape, Transform3D.IDENTITY]

	return []

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
	multi_mesh_item.mesh_lod0_distance_ratio = float(r[0])
	multi_mesh_item.mesh_lod1_distance_ratio = float(r[1])
	multi_mesh_item.mesh_lod2_distance_ratio = float(r[2])
	multi_mesh_item.mesh_lod3_distance_ratio = float(r[3])
	

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

	multi_mesh_item.mesh_lod0_distance_ratio = ratios[0]
	multi_mesh_item.mesh_lod1_distance_ratio = ratios[1]
	multi_mesh_item.mesh_lod2_distance_ratio = ratios[2]
	multi_mesh_item.mesh_lod3_distance_ratio = ratios[3]

func _register_multi_mesh_item(i: int, item, shared_data: Dictionary, generator: VoxelInstanceGenerator, lod_index: int) -> void:
	var multi_mesh_item := VoxelInstanceLibraryMultiMeshItem.new()
	multi_mesh_item.generator = generator
	multi_mesh_item.lod_index = lod_index

	# 'instance_as_scene': false marca decorado estático: hierba y parches, que no se talan ni se
	# recogen. Los items que no traen la clave son interactivos, como hasta ahora.
	var interactive: bool = item.get("instance_as_scene", true)

	var lm: Array = shared_data.get("lod_meshes", [])
	if lm.size() == 4:
		# 4 mesh-LOD: cerca lm[0] (full), lejos lm[3] (impostor). El near->far lo hace el módulo
		# eligiendo la malla por bloque según distancia (cuidado: por CENTRO de bloque -> salta a
		# saltos, más notorio cuanto mayor el lod_index; es by-design del multimesh).
		multi_mesh_item.set_mesh(lm[0], 0)
		multi_mesh_item.set_mesh(lm[1], 1)
		multi_mesh_item.set_mesh(lm[2], 2)
		multi_mesh_item.set_mesh(lm[3], 3)

		var cs: Array = shared_data.get("collision_shapes", [])
		if not cs.is_empty():
			multi_mesh_item.collision_shapes = cs

		# "mesh_lod_ratios" (4 valores) tiene prioridad: se escriben crudos, para
		# calibrar la semántica real del módulo sin mi conversión desde metros.
		var raw_ratios: Array = item.get("mesh_lod_ratios", [])
		if raw_ratios.size() == 4:
			_apply_mesh_lod_ratios_raw(multi_mesh_item, lod_index, raw_ratios)
		else:
			var dists: Array = item.get("mesh_lod_distances_m", [384, 768, 2500])
			_apply_mesh_lod_distances(multi_mesh_item, lod_index, dists)
	else:
		# items sin LOD (MeshInstance directa, Rock3D): sin collision_shapes, dependen de
		# 'scene' para que el módulo instancie el nodo físico cerca del jugador.
		multi_mesh_item.scene = shared_data.packed_scene


	if not item.get("cast_shadow", true):
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

	# Plantilla para clonar el item al talarlo (action_controller). Va en un dict aparte
	# y NO en multi_mesh_item.scene: ponerla ahí haría que el módulo instancie un nodo por
	# árbol cercano en cada banda de LOD (bajón de rendimiento). La colisión de los árboles
	# con LOD ya la dan collision_shapes. El decorado estático no se registra: sin plantilla,
	# handle_attack sale sin hacer nada aunque algo llegue a apuntarle.
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

## Asigna a cada mesh-LOD su variante de material: LOD0 conserva la doble cara
## (volumen de cerca) y LOD1/LOD2 pasan a una cara (mitad de fill). Con
## debug_lod_colors además tiñe cada LOD para ver in-game cuál se usa y dónde.
## Los duplicados se registran en item_transparent_materials o se quedarían sin el
## push de sol/viento. LOD3 es el impostor (otro shader): esta función no lo toca;
## su material se crea y registra aparte en _build_impostor_cross_mesh.
## Se llama UNA vez por item, antes de registrar sus bandas.
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
			continue  # LOD0 sin debug: se queda con el material original
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
	var generators = vegetation.generators
	var graph_functions = vegetation.hemisphere_graph_function
	voxel_instancer.library.clear()
	planet_item_scenes.clear()
	planet_item_packed_scenes.clear()
	multi_mesh_array.clear()
	item_transparent_materials.clear()
	_next_library_id = 0

	# Alcance real de cada banda de voxel-LOD: es lo que hay que mirar para calibrar
	# lod_index, los fade de la hierba y los mesh_lod_distances_m de los árboles.
	if voxel_terrain != null and voxel_terrain.has_method("get_lod_distances"):
		print("[vegetation] alcance por lod_index (m): ", voxel_terrain.get_lod_distances())
	elif voxel_terrain != null:
		# Sin get_lod_distances() en esta versión del módulo, el mismo cálculo de respaldo que usa
		# _get_lod_view_distance: sin esto no hay forma de calibrar lod_index con números.
		var fallback: Array[float] = []
		for n in voxel_terrain.lod_count:
			fallback.append(float(voxel_terrain.lod_distance) * float(1 << n))
		print("[vegetation] alcance por lod_index (m, estimado lod_distance=%s): %s"
			% [voxel_terrain.lod_distance, fallback])

	# async: _load_vegetation_item hornea el impostor LOD3 de los árboles con await
	# (render-to-texture). _load_vegetation se lanza como corrutina desde planet_loader
	# (fire-and-forget): la vegetación se registra en los primeros frames sin bloquear la
	# carga del planeta. Los items sin impostor (rocas, arbustos, grass) no suspenden.
	for i in vegetation.items.size():
		await _load_vegetation_item(i, vegetation.items[i], generators, graph_functions)


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
	if not patch_cfg.is_empty():
		var card := await _bake_grass_patch(shared_data.effective_mesh, patch_cfg)
		if card == null:
			return
		shared_data.lod_meshes = [card, card, card, card]
		shared_data.effective_mesh = null

	# LOD3 = impostor (aspa) solo para árboles Tree3D: son los únicos con lod_meshes de 4
	# entradas (Bush3D/Rock/MeshInstance -> []). Se hornea UNA vez por item, antes del bucle
	# de registro, para que set_mesh(lm[3], 3) instale el impostor directamente (sin hot-swap).
	var lm: Array = shared_data.lod_meshes
	if patch_cfg.is_empty():
		if lm.size() == 4 and item.get("lod3_impostor", true):
			var impostor := await _bake_tree_impostor(lm[0])
			if impostor != null:
				lm[3] = impostor

		# Variantes de material por mesh-LOD (una cara en los lejanos, tinte de debug).
		# Aquí y no en el registro: el item se registra una vez por banda y duplicaría.
		if lm.size() == 4:
			_apply_lod_material_variants(lm, item.wind_speed if item.has("wind_speed") else 0.0)

	var emit_as_scene: bool = item.get("instance_as_scene", false)

	for generator_name in generator_names:
		var generator_config = null
		for gc in generators:
			if gc.name == generator_name:
				generator_config = gc
				break
		if generator_config == null:
			push_error("Error parsing vegetation, generator with name %s not found." % generator_name)
			continue

		for lod_index in lod_indices:
			var generator: VoxelInstanceGenerator = _build_generator(generator_config, graph_functions, lod_index)
			if emit_as_scene:
				_register_scene_item(item, shared_data, generator, lod_index)
			else:
				_register_multi_mesh_item(i, item, shared_data, generator, lod_index)


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

	var col_radius: float = (tree3d.get_stem_origin_radius() * 1.1) if tree3d is Bush3D else (tree3d.trunk_max_radius * 1.1)
	var collision_child := _build_tree_collision(trunk, col_radius)
	new_root.add_child(collision_child)
	_set_owner_recursive(collision_child, new_root)

	# collision_shapes = lista alternada [Shape3D, Transform3D, ...]
	var collision_shapes: Array = []
	if collision_child.shape != null:
		collision_shapes = [collision_child.shape, collision_child.transform]

	var tree_scene := PackedScene.new()
	var err := tree_scene.pack(new_root)
	if err != OK:
		push_error("No se pudo empaquetar el árbol: %s" % err)
	new_root.queue_free()

	return {
		"scene": tree_scene,
		"mesh": combined_mesh,
		"lod_meshes": lod_meshes,
		"collision_shapes": collision_shapes,
	}


## Devuelve el array de materiales del foliage según el tipo (Tree3D/Bush3D).
func _get_twig_materials_array(tree3d) -> Array:
	if tree3d is Bush3D:
		var arr = tree3d.foliage_materials
		return arr if arr != null else []
	else:
		var arr = tree3d.twig_materials
		return arr if arr != null else []


## Genera un impostor billboard en aspa (2 quads perpendiculares) como LOD3 de un árbol.
## Renderiza 'source_mesh' de lado a una textura RGBA (con alfa) usando un SubViewport de
## mundo propio, y construye el aspa mapeando esa textura. El AABB del aspa coincide con el
## del árbol para que no haya "pop" de tamaño al cruzar LOD2->LOD3.
## Async: espera 2 frames a que el render-target se dibuje antes de leer la imagen.
func _bake_tree_impostor(source_mesh: Mesh, tex_size: int = 256) -> Mesh:
	if source_mesh == null or voxel_instancer == null or not voxel_instancer.is_inside_tree():
		return null

	var aabb: AABB = source_mesh.get_aabb()
	var center: Vector3 = aabb.get_center()
	# lado del encuadre ortográfico cuadrado (+5% de margen); el árbol queda centrado.
	var view_size: float = maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z)) * 1.05
	if view_size <= 0.0:
		return null

	# --- SubViewport aislado: renderiza SOLO el árbol + sus luces, no la escena real ---
	var vp := SubViewport.new()
	vp.size = Vector2i(tex_size, tex_size)
	vp.transparent_bg = true                 # imprescindible para capturar el alfa del follaje
	vp.own_world_3d = true                    # mundo propio -> sin fondo de la escena real
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = source_mesh
	vp.add_child(mesh_inst)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-45, -30, 0)
	key_light.light_energy = 1.2
	key_light.shadow_enabled = false
	vp.add_child(key_light)

	# relleno suave para que la cara en sombra no quede completamente negra en la captura.
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20, 150, 0)
	fill_light.light_energy = 0.4
	fill_light.shadow_enabled = false
	vp.add_child(fill_light)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_size
	var cam_dist: float = view_size * 2.0
	cam.near = maxf(cam_dist - view_size, 0.05)
	cam.far = cam_dist + view_size
	cam.position = center + Vector3(0.0, 0.0, cam_dist)
	cam.look_at_from_position(cam.position, center, Vector3.UP)
	vp.add_child(cam)

	voxel_instancer.add_child(vp)            # el viewport debe estar en el árbol para renderizar
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img: Image = vp.get_texture().get_image()
	vp.queue_free()

	if img == null or img.is_empty():
		push_warning("Planet: bake de impostor devolvió imagen vacía; se mantiene la geometría LOD3.")
		return null

	var tex := ImageTexture.create_from_image(img)
	return _build_impostor_cross_mesh(aabb, tex, view_size)


## Construye el aspa (2 quads perpendiculares) que abarca el AABB del árbol y mapea la textura
## del impostor. Como la textura es cuadrada (lado view_size) y el árbol ocupa solo su parte
## central, las UV recortan justo esa región (sin deformar y sin cambiar de tamaño aparente).
func _build_impostor_cross_mesh(aabb: AABB, tex: Texture2D, view_size: float) -> ArrayMesh:
	var center: Vector3 = aabb.get_center()
	var h: float = aabb.size.y
	var w: float = maxf(aabb.size.x, aabb.size.z)      # ancho común de ambos quads
	var hw: float = w * 0.5
	var y0: float = aabb.position.y                    # base (y~0)
	var y1: float = aabb.position.y + h                # copa

	# fracción central de la textura ocupada por el árbol (el resto es margen transparente)
	var fu: float = (w / view_size) if view_size > 0.0 else 1.0
	var fv: float = (h / view_size) if view_size > 0.0 else 1.0
	var u0: float = 0.5 - fu * 0.5
	var u1: float = 0.5 + fu * 0.5
	var v0: float = 0.5 - fv * 0.5                      # arriba (Y alto)
	var v1: float = 0.5 + fv * 0.5                      # abajo (Y bajo)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Quad en el plano XY (normal Z), centrado en X
	_add_impostor_quad(st,
		[Vector3(center.x - hw, y1, center.z), Vector3(center.x + hw, y1, center.z),
		 Vector3(center.x + hw, y0, center.z), Vector3(center.x - hw, y0, center.z)],
		[Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)],
		Vector3.BACK)
	# Quad en el plano ZY (normal X), centrado en Z (reutiliza la misma vista de lado)
	_add_impostor_quad(st,
		[Vector3(center.x, y1, center.z - hw), Vector3(center.x, y1, center.z + hw),
		 Vector3(center.x, y0, center.z + hw), Vector3(center.x, y0, center.z - hw)],
		[Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)],
		Vector3.RIGHT)

	# Shader propio: unshaded (barato) pero respeta el terminador día/noche del
	# planeta. Con StandardMaterial3D unshaded el impostor brillaba a albedo pleno
	# de noche, ignorando la sombra planetaria del resto de la vegetación.
	if _impostor_shader == null:
		_impostor_shader = load(_IMPOSTOR_SHADER_PATH)
	var mat := ShaderMaterial.new()
	mat.shader = _impostor_shader
	mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("alpha_scissor_threshold", 0.5)
	# Registrar para recibir el push de sol (light_direction/planet_position) cada
	# frame; sin viento (wind_speed 0). item_transparent_materials ya está limpio
	# en este punto de la carga (_load_vegetation lo vació antes de registrar items).
	item_transparent_materials.append({"shader": mat, "wind_speed": 0.0})

	st.set_material(mat)

	return st.commit()


## Añade un quad (2 triángulos) a un SurfaceTool. corners/uvs en orden TL, TR, BR, BL.
func _add_impostor_quad(st: SurfaceTool, corners: Array, uvs: Array, normal: Vector3) -> void:
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_uv(uvs[idx])
		st.add_vertex(corners[idx])


## Hornea la tarjeta que sustituye a un parche entero de hierba a distancia: reparte
## 'clump_count' matas en un cuadrado de 'size_m' y fotografía el clúster dos veces
## (de lado y en cenital) a las dos capas de un Texture2DArray. Devuelve el aspa +
## quad horizontal que las mapean, o null si el render falla.
## Una tarjeta vale por decenas de matas: es lo que compensa que las bandas de LOD
## altas den 4x menos instancias por m² cada una.
## La escala se multiplica en dos sitios y hay que cuadrar los dos o el parche sale de
## otro tamaño que la hierba real: 'clump_scale' ± 'clump_scale_jitter' debe reproducir
## el min_scale/max_scale del generador de HIERBA al que releva, y el generador de la
## TARJETA debe ir a min_scale = max_scale = 1.0 (la tarjeta ya trae sus metros).
## Async: cada vista espera 2 frames a que el render-target se dibuje.
func _bake_grass_patch(source_mesh: Mesh, cfg: Dictionary) -> Mesh:
	if source_mesh == null or voxel_instancer == null or not voxel_instancer.is_inside_tree():
		return null

	# Lo que importa es la resolución por metro: el encuadre cubre el parche entero, así
	# que a 256 px sobre 5 m las briznas caen por debajo del píxel y los mips las borran.
	var tex_size: int = int(cfg.get("tex_size", 512))
	var scatter_size: float = float(cfg.get("size_m", 4.0))
	var clump_scale: float = float(cfg.get("clump_scale", 1.0))
	var scale_jitter: float = clampf(float(cfg.get("clump_scale_jitter", 0.35)), 0.0, 1.0)
	var aabb: AABB = source_mesh.get_aabb()
	var max_clump: float = clump_scale * (1.0 + scale_jitter)
	if scatter_size <= 0.0 or aabb.size.y <= 0.0 or max_clump <= 0.0:
		return null

	# Encuadre: peor caso teórico (las matas del borde sobresalen del cuadrado de reparto)
	# para no recortar nada. La tarjeta NO usa estas medidas, se ajusta luego a lo que de
	# verdad se haya dibujado: con reparto aleatorio el contenido se queda bastante corto.
	var frame_size: float = scatter_size + maxf(aabb.size.x, aabb.size.z) * max_clump
	var frame_height: float = aabb.size.y * max_clump
	var view_size: float = maxf(frame_size, frame_height) * 1.05
	var side_cam_y: float = frame_height * 0.5

	var cluster := _build_grass_patch_cluster(source_mesh, cfg)
	if cluster == null:
		return null

	# Lateral: alimenta el aspa. Centrada a media altura para que el parche quede
	# centrado también en vertical dentro de la textura.
	var side_img := await _render_ortho_to_image(cluster,
		Vector3(0.0, side_cam_y, view_size), Vector3(0.0, side_cam_y, 0.0),
		Vector3.UP, view_size, tex_size)
	# Cenital pura: es la única proyección que mapea EXACTO sobre el quad horizontal
	# (ortográfica = afín, el cuadrado del suelo cae en un rectángulo sin deformar).
	var top_img := await _render_ortho_to_image(cluster,
		Vector3(0.0, view_size, 0.0), Vector3.ZERO,
		Vector3.FORWARD, view_size, tex_size)

	cluster.queue_free()

	if side_img == null or top_img == null:
		push_warning("Planet: bake de parche de hierba devolvió imagen vacía; el item se queda sin tarjeta.")
		return null

	# Recuadro realmente pintado en cada vista: de ahí salen las medidas y las UV de la
	# tarjeta, en vez del peor caso, que dejaba ~0.5 m de margen transparente por lado.
	var side_rect: Rect2i = side_img.get_used_rect()
	var top_rect: Rect2i = top_img.get_used_rect()
	if side_rect.size.x <= 0 or side_rect.size.y <= 0 or top_rect.size.x <= 0 or top_rect.size.y <= 0:
		push_warning("Planet: el parche de hierba se horneó vacío; el item se queda sin tarjeta.")
		return null

	# Volcado de las dos vistas tal cual salen del render, antes de mipmaps y UVs:
	# es la única forma de separar "la textura sale mal" de "la tarjeta la mapea mal".
	if bool(cfg.get("debug_dump", false)):
		var tag: String = str(int(cfg.get("seed", 0)))
		side_img.save_png("user://grass_patch_%s_side.png" % tag)
		top_img.save_png("user://grass_patch_%s_top.png" % tag)
		print("[grass_patch] volcado %s: encuadre %.2f m a %d px/m | pintado %.2f x %.2f m (lateral), %.2f x %.2f m (cenital)" % [
			tag, view_size, int(tex_size / view_size),
			side_rect.size.x * view_size / tex_size, side_rect.size.y * view_size / tex_size,
			top_rect.size.x * view_size / tex_size, top_rect.size.y * view_size / tex_size])

	side_img = _fill_transparent_rgb(side_img)
	top_img = _fill_transparent_rgb(top_img)
	side_img.generate_mipmaps()
	top_img.generate_mipmaps()
	# Texture2DArray y no un atlas en una sola imagen: con atlas los mips mezclan las
	# dos vistas entre sí y el aspa acaba con manchas de la cenital.
	var atlas := Texture2DArray.new()
	if atlas.create_from_images([side_img, top_img]) != OK:
		push_warning("Planet: no se pudo crear el Texture2DArray del parche de hierba.")
		return null

	var card := _build_grass_patch_card(side_rect, top_rect, tex_size, view_size, side_cam_y, atlas, cfg)
	_apply_grass_handoff(card, source_mesh, cfg)
	return card


## Reparte el relevo hierba->tarjeta a partir del corte duro de la banda de LOD de la
## hierba: pasado ese alcance el instancer ya no tiene esos bloques y la hierba se corta
## en seco, así que TODO el relevo tiene que terminar antes. El orden es tarjeta primero:
## cuando la hierba empieza a irse, la tarjeta ya está entera, y nunca hay una franja con
## las dos a medias.
## Escribe los dos materiales desde el mismo sitio para que no puedan desincronizarse; el
## de la mata es el mismo recurso que usa el item de hierba (los dos cargan esa escena),
## así que esto también fija el fade de la hierba cercana y manda sobre el .tscn.
func _apply_grass_handoff(card: Mesh, source_mesh: Mesh, cfg: Dictionary) -> void:
	var card_width: float = float(cfg.get("fade_width_m", 20.0))
	var grass_width: float = float(cfg.get("grass_fade_width_m", 20.0))

	# 'handoff_end_m' pincha el final a mano; si no, se deduce del alcance real de la
	# banda menos un margen, para cerrar antes de que empiecen a caerse bloques.
	var grass_end: float = float(cfg.get("handoff_end_m", 0.0))
	if grass_end <= 0.0:
		var band: float = _get_lod_view_distance(int(cfg.get("handoff_lod_index", 1)))
		grass_end = band - float(cfg.get("handoff_margin_m", 8.0))
	var grass_start: float = maxf(grass_end - grass_width, 1.0)

	var grass_mat := source_mesh.surface_get_material(0) as ShaderMaterial
	if grass_mat != null:
		grass_mat.set_shader_parameter("fade_start", grass_start)
		grass_mat.set_shader_parameter("fade_end", grass_end)

	var card_mat := card.surface_get_material(0) as ShaderMaterial
	if card_mat != null:
		card_mat.set_shader_parameter("fade_start", maxf(grass_start - card_width, 1.0))
		card_mat.set_shader_parameter("fade_width", card_width)

	print("[grass_patch] relevo: tarjeta %.0f->%.0f m, hierba %.0f->%.0f m" % [
		maxf(grass_start - card_width, 1.0), grass_start, grass_start, grass_end])


## Pinta de color medio el RGB de los píxeles transparentes, conservando el alfa.
## Cada nivel de mipmap promedia RGB sin mirar el alfa, así que con el fondo negro del
## render la tarjeta se ensucia hacia negro según se aleja, y peor cuanto más hueco
## tenga la vista (la cenital, llena de claros, se ennegrecía antes que la lateral).
## El color se saca de la propia imagen y no de los uniforms del material para no tener
## que adivinar en qué espacio de color viene el render.
func _fill_transparent_rgb(img: Image) -> Image:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = img.get_data()

	var sum_r: int = 0
	var sum_g: int = 0
	var sum_b: int = 0
	var opaque: int = 0
	var i: int = 0
	while i < data.size():
		if data[i + 3] >= 128:
			sum_r += data[i]
			sum_g += data[i + 1]
			sum_b += data[i + 2]
			opaque += 1
		i += 4
	if opaque == 0:
		return img

	var avg_r: int = sum_r / opaque
	var avg_g: int = sum_g / opaque
	var avg_b: int = sum_b / opaque
	i = 0
	while i < data.size():
		if data[i + 3] < 128:
			data[i] = avg_r
			data[i + 1] = avg_g
			data[i + 2] = avg_b
		i += 4

	return Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## Nodo temporal con 'clump_count' copias de la mata repartidas en un cuadrado de
## 'size_m' (rejilla con jitter), con giro y escala deterministas ('seed'). Apoyadas en y=0.
func _build_grass_patch_cluster(source_mesh: Mesh, cfg: Dictionary) -> Node3D:
	var bake_mat := _build_grass_patch_bake_material(source_mesh, cfg)
	if bake_mat == null:
		return null

	var half: float = float(cfg.get("size_m", 4.0)) * 0.5
	var count: int = maxi(int(cfg.get("clump_count", 36)), 1)
	var clump_scale: float = float(cfg.get("clump_scale", 1.0))
	var scale_jitter: float = clampf(float(cfg.get("clump_scale_jitter", 0.35)), 0.0, 1.0)
	var base_y: float = source_mesh.get_aabb().position.y

	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 1337))

	# Rejilla con jitter en vez de azar puro: con dos docenas de muestras el azar deja
	# calvas grandes (la vista cenital horneada salía con un mordisco). Los recuentos que
	# llenan la rejilla entera (16, 20, 25...) reparten mejor que los que dejan coja la
	# última fila.
	var cols: int = int(ceil(sqrt(float(count))))
	var rows: int = int(ceil(float(count) / float(cols)))
	var cell_x: float = half * 2.0 / float(cols)
	var cell_z: float = half * 2.0 / float(rows)

	var root := Node3D.new()
	for i in count:
		var inst := MeshInstance3D.new()
		inst.mesh = source_mesh
		inst.material_override = bake_mat
		var s: float = clump_scale * rng.randf_range(1.0 - scale_jitter, 1.0 + scale_jitter)
		var t := Transform3D.IDENTITY.scaled(Vector3(s, s, s)).rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		# El AABB del modelo no arranca en y=0: se sube para apoyarlo en el suelo.
		t.origin = Vector3(
			-half + (float(i % cols) + rng.randf()) * cell_x,
			-base_y * s,
			-half + (float(i / cols) + rng.randf()) * cell_z)
		inst.transform = t
		root.add_child(inst)
	return root


## Material de horneado del parche: hereda el degradado del shader de hierba del item
## para que cada variante (verde / verde-amarillo / amarillo) hornee su propio color.
func _build_grass_patch_bake_material(source_mesh: Mesh, cfg: Dictionary) -> ShaderMaterial:
	if _grass_patch_bake_shader == null:
		_grass_patch_bake_shader = load(_GRASS_PATCH_BAKE_SHADER_PATH)
	if _grass_patch_bake_shader == null:
		return null

	var mat := ShaderMaterial.new()
	mat.shader = _grass_patch_bake_shader
	var src := source_mesh.surface_get_material(0) as ShaderMaterial
	if src != null:
		for param in ["base_color", "tip_color", "grass_height"]:
			var value = src.get_shader_parameter(param)
			if value != null:
				mat.set_shader_parameter(param, value)
	mat.set_shader_parameter("ao_strength", float(cfg.get("bake_ao", 0.35)))
	return mat


## Fotografía 'content' con una cámara ortográfica que encuadra 'view_size' metros,
## sobre fondo transparente y en un mundo 3D propio (no se cuela la escena real).
## 'content' entra y sale del viewport: el llamante conserva su propiedad.
## No añade luces: el material de horneado es unshaded.
func _render_ortho_to_image(content: Node3D, eye: Vector3, target: Vector3, up: Vector3,
		view_size: float, tex_size: int) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(tex_size, tex_size)
	vp.transparent_bg = true                  # imprescindible para capturar el alfa
	vp.own_world_3d = true                    # mundo propio -> sin fondo de la escena real
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.add_child(content)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_size
	cam.near = 0.05
	cam.far = eye.distance_to(target) + view_size * 2.0
	cam.look_at_from_position(eye, target, up)
	vp.add_child(cam)

	voxel_instancer.add_child(vp)             # el viewport debe estar en el árbol para renderizar
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img: Image = vp.get_texture().get_image()
	vp.remove_child(content)
	vp.queue_free()

	if img == null or img.is_empty():
		return null
	return img


## Aspa vertical + quad horizontal que mapean las dos capas del atlas del parche.
## COLOR.r marca la capa (0 = lateral en el aspa, 1 = cenital en el horizontal).
## Cada quad se ajusta al recuadro que la vista correspondiente pintó de verdad, así que
## no queda margen transparente y la escala es exacta: los píxeles del recuadro se
## deshacen a metros con la misma proyección ortográfica que los generó.
func _build_grass_patch_card(side_rect: Rect2i, top_rect: Rect2i, tex_size: int,
		view_size: float, side_cam_y: float, atlas: Texture2DArray, cfg: Dictionary) -> ArrayMesh:
	# Lateral: cámara en +Z mirando a -Z, centrada en (0, side_cam_y). u sigue a +X y v
	# baja en pantalla, así que v crece hacia Y bajo.
	var su0: float = float(side_rect.position.x) / tex_size
	var su1: float = float(side_rect.end.x) / tex_size
	var sv0: float = float(side_rect.position.y) / tex_size
	var sv1: float = float(side_rect.end.y) / tex_size
	var x_min: float = (su0 - 0.5) * view_size
	var x_max: float = (su1 - 0.5) * view_size
	var y_max: float = side_cam_y + (0.5 - sv0) * view_size
	var y_min: float = side_cam_y + (0.5 - sv1) * view_size

	# Cenital: cámara encima con up = FORWARD, así que u sigue a +X y v a +Z.
	var tu0: float = float(top_rect.position.x) / tex_size
	var tu1: float = float(top_rect.end.x) / tex_size
	var tv0: float = float(top_rect.position.y) / tex_size
	var tv1: float = float(top_rect.end.y) / tex_size
	var gx_min: float = (tu0 - 0.5) * view_size
	var gx_max: float = (tu1 - 0.5) * view_size
	var gz_min: float = (tv0 - 0.5) * view_size
	var gz_max: float = (tv1 - 0.5) * view_size

	# Medio píxel hacia dentro: evita arrastrar la fila transparente del borde al filtrar.
	var half_px: float = 0.5 / float(tex_size)
	var uvs_side: Array = [
		Vector2(su0 + half_px, sv0 + half_px), Vector2(su1 - half_px, sv0 + half_px),
		Vector2(su1 - half_px, sv1 - half_px), Vector2(su0 + half_px, sv1 - half_px)]
	var uvs_top: Array = [
		Vector2(tu0 + half_px, tv0 + half_px), Vector2(tu1 - half_px, tv0 + half_px),
		Vector2(tu1 - half_px, tv1 - half_px), Vector2(tu0 + half_px, tv1 - half_px)]
	var layer_side := Color(0.0, 0.0, 0.0, 1.0)
	var layer_top := Color(1.0, 0.0, 0.0, 1.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Aspa: quad en el plano XY y quad en el plano ZY, ambos con la vista lateral. El
	# segundo reutiliza el ancho del primero, girado 90º.
	_add_patch_quad(st,
		[Vector3(x_min, y_max, 0.0), Vector3(x_max, y_max, 0.0),
		 Vector3(x_max, y_min, 0.0), Vector3(x_min, y_min, 0.0)],
		uvs_side, Vector3.BACK, layer_side)
	_add_patch_quad(st,
		[Vector3(0.0, y_max, x_min), Vector3(0.0, y_max, x_max),
		 Vector3(0.0, y_min, x_max), Vector3(0.0, y_min, x_min)],
		uvs_side, Vector3.RIGHT, layer_side)

	# Quad horizontal, algo elevado para no pelearse con el terreno en el z-buffer.
	# Con vertical_alignment radial se apoya en el plano tangente, así que en
	# pendientes fuertes se hunde por un lado: limitar max_slope_degrees del generador.
	var gy: float = (y_max - y_min) * float(cfg.get("ground_quad_height", 0.25))
	_add_patch_quad(st,
		[Vector3(gx_min, gy, gz_min), Vector3(gx_max, gy, gz_min),
		 Vector3(gx_max, gy, gz_max), Vector3(gx_min, gy, gz_max)],
		uvs_top, Vector3.UP, layer_top)

	if _grass_patch_shader == null:
		_grass_patch_shader = load(_GRASS_PATCH_SHADER_PATH)
	var mat := ShaderMaterial.new()
	mat.shader = _grass_patch_shader
	mat.set_shader_parameter("patch_atlas", atlas)
	# Bajo a propósito: el alfa se promedia en cada mip, así que un umbral alto se come
	# las briznas finas de lejos y deja solo la base maciza.
	mat.set_shader_parameter("alpha_scissor_threshold", float(cfg.get("alpha_scissor", 0.25)))
	# Registrar para recibir el push de sol (light_direction/planet_position) cada
	# frame; sin viento (a esta distancia el balanceo es subpíxel).
	item_transparent_materials.append({"shader": mat, "wind_speed": 0.0})

	st.set_material(mat)
	return st.commit()


## Como _add_impostor_quad pero marcando la capa del atlas en el color del vértice.
func _add_patch_quad(st: SurfaceTool, corners: Array, uvs: Array, normal: Vector3, layer: Color) -> void:
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(layer)
		st.set_normal(normal)
		st.set_uv(uvs[idx])
		st.add_vertex(corners[idx])


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
	voxel_terrain = _voxel_terrain
	voxel_instancer = VoxelInstancer.new()
	voxel_instancer.library = VoxelInstanceLibrary.new()
	voxel_instancer.up_mode = VoxelInstancer.UP_MODE_SPHERE
	voxel_terrain.add_child(voxel_instancer)
	shader_material = ShaderMaterial.new()
	shader_material.shader = load("res://shaders/terrain/planet_biomes.gdshader")


func setup_shader_parameters() -> void:
	voxel_terrain.material = shader_material

	shader_material.set_shader_parameter("transition_smoothness", transition_smoothness)
	shader_material.set_shader_parameter("height_transition_noise_scale", height_transition_noise_scale)
	shader_material.set_shader_parameter("height_transition_noise_strength", height_transition_noise_strength)
	shader_material.set_shader_parameter("biome_transition_smoothness", biome_transition_smoothness)
	update_world_center()

	shader_material.set_shader_parameter("center", planet_position)
	shader_material.set_shader_parameter("radius", radius)

	shader_material.set_shader_parameter("max_heights", max_heights)
	shader_material.set_shader_parameter("biome_count", biome_count)
	shader_material.set_shader_parameter("textures_per_biome", textures_per_biome)
	shader_material.set_shader_parameter("biome_latitude_ranges", biome_latitude_ranges)

	shader_material.set_shader_parameter("textures", textures)
	shader_material.set_shader_parameter("normal_textures", normal_textures)
	shader_material.set_shader_parameter("roughness_textures", roughness_textures)
	shader_material.set_shader_parameter("ao_textures", ao_textures)
	shader_material.set_shader_parameter("height_textures", height_textures)

	shader_material.set_shader_parameter("biome_texture_indices", biome_texture_indices)
	shader_material.set_shader_parameter("biome_noise_enabled", biome_noise_enabled)
	shader_material.set_shader_parameter("biome_noise_source_texture_indices", biome_noise_source_texture_indices)
	shader_material.set_shader_parameter("biome_noise_target_texture_indices", biome_noise_target_texture_indices)
	shader_material.set_shader_parameter("biome_noise_scales", biome_noise_scales)
	shader_material.set_shader_parameter("biome_noise_thresholds", biome_noise_thresholds)
	shader_material.set_shader_parameter("biome_noise_smoothness", biome_noise_smoothness)
	shader_material.set_shader_parameter("biome_noise_seeds", biome_noise_seeds)
	shader_material.set_shader_parameter("biome_noise_invert", biome_noise_invert)
	shader_material.set_shader_parameter("biome_noise_abs_latitude_mins", biome_noise_abs_latitude_mins)
	shader_material.set_shader_parameter("biome_noise_abs_latitude_maxs", biome_noise_abs_latitude_maxs)
	shader_material.set_shader_parameter("biome_noise_latitude_smoothness", biome_noise_latitude_smoothness)

	shader_material.set_shader_parameter("slope_texture", slope_texture)
	shader_material.set_shader_parameter("slope_normal_texture", slope_normal_texture)
	shader_material.set_shader_parameter("slope_roughness_texture", slope_roughness_texture)
	shader_material.set_shader_parameter("slope_ao_texture", slope_ao_texture)
	shader_material.set_shader_parameter("slope_height_texture", slope_height_texture)
	shader_material.set_shader_parameter("slope_threshold", slope_threshold)
	shader_material.set_shader_parameter("slope_smoothness", slope_smoothness)
	shader_material.set_shader_parameter("slope_height_blend_strength", slope_height_blend_strength)
	shader_material.set_shader_parameter("slope_height_blend_sharpness", slope_height_blend_sharpness)
	shader_material.set_shader_parameter("slope_breakup_scale", slope_breakup_scale)
	shader_material.set_shader_parameter("slope_breakup_strength", slope_breakup_strength)
	shader_material.set_shader_parameter("slope_breakup_anisotropy", slope_breakup_anisotropy)
	shader_material.set_shader_parameter("slope_strata_thickness", slope_strata_thickness)
	shader_material.set_shader_parameter("slope_strata_strength", slope_strata_strength)
	shader_material.set_shader_parameter("slope_strata_warp", slope_strata_warp)
	shader_material.set_shader_parameter("parallax_enabled", parallax_enabled)
	shader_material.set_shader_parameter("parallax_strength", parallax_strength)
	shader_material.set_shader_parameter("macro_variation_scale", macro_variation_scale)
	shader_material.set_shader_parameter("macro_variation_strength", macro_variation_strength)

	shader_material.set_shader_parameter("has_water", 1 if has_water else 0)
	shader_material.set_shader_parameter("water_radius", radius - water_radius)

	_setup_reef_shader_parameters()
	_setup_ore_shader_parameters()


## Textura de los escollos y la franja en que manda. Sin las cuatro texturas se queda apagado: la
## roca sale con la arena de la orilla, que es lo que había antes, y no con samplers sin enlazar.
func _setup_reef_shader_parameters() -> void:
	var albedo := load(reef_settings.get("texture", "")) as Texture2D
	var nrm := load(reef_settings.get("normal_texture", "")) as Texture2D
	var rough := load(reef_settings.get("roughness_texture", "")) as Texture2D
	var ao := load(reef_settings.get("ao_texture", "")) as Texture2D
	var ready: bool = has_water and albedo != null and nrm != null and rough != null and ao != null
	shader_material.set_shader_parameter("reef_enabled", 1 if ready else 0)
	if not ready:
		return

	shader_material.set_shader_parameter("reef_texture", albedo)
	shader_material.set_shader_parameter("reef_normal_texture", nrm)
	shader_material.set_shader_parameter("reef_roughness_texture", rough)
	shader_material.set_shader_parameter("reef_ao_texture", ao)
	# Por defecto la franja cubre el arrecife entero: desde el borde hondo hasta un poco por encima
	# de la cresta, para que la punta emergida no vuelva a ser arena justo al salir del agua.
	var depth_max: float = maxf(float(reef_settings.get("depth_max", 45.0)), 1.0)
	var crest: float = float(reef_settings.get("crest_height", 14.0))
	shader_material.set_shader_parameter("reef_band_low",
		float(reef_settings.get("band_low", -depth_max)))
	shader_material.set_shader_parameter("reef_band_high",
		float(reef_settings.get("band_high", crest + 4.0)))
	shader_material.set_shader_parameter("reef_slope_threshold",
		float(reef_settings.get("texture_slope_threshold", 0.10)))
	shader_material.set_shader_parameter("reef_slope_softness",
		float(reef_settings.get("texture_slope_softness", 0.14)))

func _setup_ore_shader_parameters() -> void:
	var ore_albedo: Array[Texture2D] = []
	var ore_normal: Array[Texture2D] = []
	var ore_roughness: Array[Texture2D] = []

	for ore in ore_settings:
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
	if !terrain_generator_path.is_empty():
		prepared = load(terrain_generator_path).duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
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

	if not ore_settings.is_empty():
		_apply_ore_params(all_functions, ore_settings)
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

	if not ore_settings.is_empty():
		_publish_ore_drop_table()


## Hornea (o recupera del caché) el campo de ríos y lo enchufa al grafo. Devuelve true si el grafo
## cambió y hay que recompilar.
##
## Red de cauces horneada, o {} si este planeta no tiene rios. Trae la sopa de segmentos en
## coordenadas del mapa de hidrologia y su semianchura, que es lo que consume el audio del agua.
func get_river_network() -> Dictionary:
	return _river_field


## El horneado necesita el relieve del propio generador, así que se hace sobre una copia limpia: la
## que se hornea lleva las imágenes neutras y no talla nada, que es justo el terreno "sin ríos" del
## que hay que deducir por dónde corre el agua.
func _setup_rivers(graph_generator: VoxelGeneratorGraph) -> bool:
	if river_settings.is_empty() or not bool(river_settings.get("enabled", true)):
		return false
	if not has_water:
		push_warning("Planet: los ríos necesitan mar como nivel base; se quedan sin generar.")
		return false

	var height_range := float(river_settings.get("height_range", 2000.0))
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
			river_settings)
		if field.is_empty():
			push_warning("Planet: no salió ningún cauce; el terreno se queda sin ríos.")
			return false
		RiverField.save_to(field, path, key)
		print("[rivers] %d tramos horneados en %.1f s"
			% [int(field.get("segments", 0)), (Time.get_ticks_msec() - started) / 1000.0])

	_river_field = field
	return RiverGenerator.apply(graph_generator, field)


## Carga un grafo de densidad de vegetación con el campo de ríos ya metido. Se duplica porque
## varios generadores comparten el mismo recurso y aquí se le escriben parámetros: sin duplicar, el
## parcheo se propagaría al recurso cacheado por el ResourceLoader.
func _load_vegetation_graph(path: String) -> VoxelGraphFunction:
	var graph: VoxelGraphFunction = load(path)
	if graph == null or _river_field.is_empty():
		return graph
	var copy: VoxelGraphFunction = graph.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	if RiverGenerator.apply(copy, _river_field):
		return copy
	return graph


## Identifica la configuración con la que se horneó el campo. Incluye la huella del generador, así
## que tocar el grafo del terreno invalida el caché de los ríos por su cuenta.
func _river_cache_key(height_range: float) -> String:
	var parts := PackedStringArray([
		"v%d" % RiverField.FILE_VERSION,
		"r%.3f" % radius,
		"w%.3f" % water_radius,
		"h%.3f" % height_range,
		JSON.stringify(river_settings),
		PlanetWorldMap._resource_fingerprint(terrain_generator_path),
	])
	return "|".join(parts).sha256_text()

## Empuja los parámetros de ore del JSON a los nodos nombrados del VoxelGraph (autorados en el editor).
func _apply_ore_params(functions: Array, ores: Array) -> void:
	var probe: VoxelGraphFunction = functions[0]
	print("[ore-graph] set_node_default_input disponible: ", probe.has_method("set_node_default_input"))
	_dump_node_info(probe, VoxelGraphFunction.NODE_SPOTS_3D, "Spots3D")
	_dump_node_info(probe, VoxelGraphFunction.NODE_DIVIDE, "Divide")
	_dump_node_info(probe, VoxelGraphFunction.NODE_OUTPUT_WEIGHT, "OutputWeight")

	for ore in ores:
		var type_id := int(ore.get("type_id", 1))
		var spots_name := "ore_spots_%d" % type_id

		var spots_fn := _find_owner(functions, spots_name)
		if spots_fn == null:
			push_warning("Planet: no se encontró el nodo Spots3D '%s' en ninguna función; ¿lo creaste y nombraste?" % spots_name)
		else:
			var spots := spots_fn.find_node_by_name(spots_name)
			_push_param(spots_fn, spots, VoxelGraphFunction.NODE_SPOTS_3D, "seed", int(ore.get("noise_seed", 0)))
			_push_param(spots_fn, spots, VoxelGraphFunction.NODE_SPOTS_3D, "cell_size", float(ore.get("cell_size", 40.0)))
			_push_param(spots_fn, spots, VoxelGraphFunction.NODE_SPOTS_3D, "spot_radius", float(ore.get("spot_radius", 12.0)))
			_push_param(spots_fn, spots, VoxelGraphFunction.NODE_SPOTS_3D, "jitter", float(ore.get("jitter", 0.9)))

		if ore.has("depth_min"):
			_apply_cave_ore_band(functions, type_id, ore)
		else:
			var depth_name := "ore_depth_%d" % type_id
			var depth_fn := _find_owner(functions, depth_name)
			if depth_fn == null:
				push_warning("Planet: no se encontró el nodo Divide '%s' del gate de profundidad." % depth_name)
			else:
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


## Empuja al grafo la franja de escollos de la costa. Devuelve true si tocó algo y hay que recompilar.
##
## El offset del nivel del mar se escribe SIEMPRE, lo pida o no el JSON: lo dicta water_radius, y sin
## él el arrecife se sitúa a la altura equivocada. La cáscara radial de reef_shell_* se deriva de la
## propia franja en vez de dejarla fija, porque quedarse corta recortaría el arrecife por arriba o
## por abajo en cuanto se tocaran depth_max o crest_height.
func _apply_reef_params(functions: Array) -> bool:
	if _find_owner(functions, "reef_sea_offset") == null:
		return false

	# El grafo razona en altura sobre el mar, y el mar está en radius - water_radius.
	_set_graph_value(functions, "reef_sea_offset", "b", water_radius)
	# El radio se lo pone el arrecife, no _apply_radius: allí se busca entre los inputs pero se
	# escribe como param, y en SdfSphere el radio es un input, así que la escritura no llega nunca.
	_set_graph_value(functions, "reef_planet_sdf", "radius", radius)

	if not has_water or not bool(reef_settings.get("enabled", true)):
		# Ventana radial vacía: el Select se queda siempre con el terreno y el ruido ni se evalúa.
		_set_graph_value(functions, "reef_shell_lo", "threshold", 1.0e9)
		_set_graph_value(functions, "reef_shell_hi", "threshold", -1.0e9)
		return true

	var depth_max: float = maxf(float(reef_settings.get("depth_max", 45.0)), 1.0)
	var depth_soft: float = clampf(float(reef_settings.get("depth_softness", 17.0)), 0.1, depth_max)
	var shore_margin: float = float(reef_settings.get("shore_margin", 1.0))
	var shore_soft: float = maxf(float(reef_settings.get("shore_softness", 4.0)), 0.1)
	var crest: float = float(reef_settings.get("crest_height", 24.0))
	var threshold: float = float(reef_settings.get("rock_threshold", 0.0))
	# La altura de la roca es lerp(lecho, crest_height, cobertura), así que TODO punto donde la
	# cobertura sature a 1 queda exactamente a crest_height: mesetas planas a cota constante, y muy
	# visibles porque las crestas del ruido van agrupadas. La cura es que este borde alto quede por
	# encima del máximo del ruido (~0.8 con 4 octavas), para que la cobertura nunca llegue a tocar 1
	# y la altura siga siendo función estrictamente creciente del ruido: cada cabeza, una cima.
	var rock_soft: float = maxf(float(reef_settings.get("rock_softness", 1.0)), 0.01)
	# Afilado extra. No es lo que quita la meseta —eso lo hace rock_softness—: estrecha las puntas,
	# a cambio de comerse la cobertura muy deprisa.
	var sharpness: int = maxi(int(reef_settings.get("sharpness", 1)), 1)

	# Tramos francos. El ruido de zona reparte la costa en tramos con arrecife y tramos limpios por
	# los que se puede entrar; sin esto la roca orla el planeta entero por igual. gap_threshold es el
	# umbral: subirlo abre más costa, bajarlo la cierra.
	var gap_threshold: float = float(reef_settings.get("gap_threshold", -0.2))
	var gap_soft: float = maxf(float(reef_settings.get("gap_softness", 0.35)), 0.01)

	_set_smoothstep(functions, "reef_deep_gate", -depth_max, -(depth_max - depth_soft))
	_set_smoothstep(functions, "reef_land_gate", shore_margin, shore_margin - shore_soft)
	_set_smoothstep(functions, "reef_coverage", threshold, threshold + rock_soft)
	_set_smoothstep(functions, "reef_zone", gap_threshold, gap_threshold + gap_soft)
	_set_graph_value(functions, "reef_sharpness", "power", sharpness)
	_set_graph_value(functions, "reef_crest", "b", crest)
	_set_graph_value(functions, "reef_shell_lo", "threshold", -(depth_max + _REEF_SHELL_BELOW))
	_set_graph_value(functions, "reef_shell_hi", "threshold", crest + _REEF_SHELL_ABOVE)

	if reef_settings.has("head_size"):
		_set_noise_period(functions, "reef_noise", maxf(float(reef_settings.head_size), 1.0))
	if reef_settings.has("gap_scale"):
		_set_noise_period(functions, "reef_zone_noise", maxf(float(reef_settings.gap_scale), 1.0))
	return true


## Deja una copia del generador sin escollos. La hidrología se deduce de un equirect de 1024x512
## —unos 180 m por téxel—, donde una cabeza de arrecife no llega a ocupar un téxel: lo único que
## aportaría es picar la línea de costa y mover desembocaduras. Se apaga dejando vacía la ventana
## radial, igual que "enabled": false, que además ahorra el ruido durante todo el horneado.
func _disable_reefs(generator: VoxelGeneratorGraph) -> void:
	var main: VoxelGraphFunction = generator.get_main_function()
	var functions: Array = [main]
	_gather_subfunctions(main, functions)
	if _find_owner(functions, "reef_shell_lo") == null:
		return
	_set_graph_value(functions, "reef_shell_lo", "threshold", 1.0e9)
	_set_graph_value(functions, "reef_shell_hi", "threshold", -1.0e9)


## Escala de uno de los dos ruidos del arrecife: es el periodo del FastNoise2 colgado del nodo, no
## un param del nodo. Se puede escribir porque el generador llega deep-duplicado; sobre el recurso
## de disco ensuciaría el .tres.
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
	for ore in ore_settings:
		var tid := int(ore.get("type_id", 0))
		if tid <= 0:
			continue
		table[tid] = {
			"item_id": StringName(ore.get("drop_item", "stone_01")),
			"min_count": int(ore.get("drop_count_min", 1)),
			"max_count": int(ore.get("drop_count_max", 1)),
		}
	voxel_terrain.set_meta("ore_drops", table)

func _dump_node_info(fn: VoxelGraphFunction, type_id: int, label: String) -> void:
	print("[ore-graph] %s node_type_info: %s" % [label, fn.get_node_type_info(type_id)])

func _ready() -> void:
	pass

func update_world_center() -> void:
	planet_position = voxel_terrain.get_parent().position

func _update_planet() -> void:
	for mat_struct in item_transparent_materials:
		var mat = mat_struct.shader as ShaderMaterial
		mat.set_shader_parameter("light_direction", sun_dir)
		mat.set_shader_parameter("planet_position", planet_position)
		mat.set_shader_parameter("wind_direction", wind_direction)
		mat.set_shader_parameter("wind_speed", mat_struct.wind_speed * weather_wind_multiplier)
	for mat in external_planet_materials:
		mat.set_shader_parameter("light_direction", sun_dir)
		mat.set_shader_parameter("planet_position", planet_position)


## Da de alta un material con iluminación planetaria que no viene de la vegetación
## (equipo del jugador, props colocados). Sin esto se queda con el light_direction /
## planet_position por defecto del .tscn y el objeto se ve casi negro: toda la luz
## directa va multiplicada por el day_factor que sale de esos dos uniforms.
func register_planet_material(mat: ShaderMaterial) -> void:
	if mat != null and not external_planet_materials.has(mat):
		external_planet_materials.append(mat)


func unregister_planet_material(mat: ShaderMaterial) -> void:
	external_planet_materials.erase(mat)
