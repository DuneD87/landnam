@tool
class_name Planet extends Node3D
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
@export var biome_noise_strengths: Array[float] = []
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
@export var slope_texture: Texture2D
@export var slope_normal_texture: Texture2D
@export var slope_roughness_texture: Texture2D
@export var slope_ao_texture: Texture2D
@export var slope_height_texture: Texture2D
@export var vegetation: Dictionary
@export var wind_direction : Vector3

@export var item_transparent_materials : Array[Dictionary]
@export var shader_material: ShaderMaterial
@export var caustics_material: ShaderMaterial
@export var multi_mesh_array: Array[Dictionary] = []

@export_group("Atmosphere settings")
@export var atmosphere_radius: float
@export var atmosphere_density: float
@export var atmosphere_height: float
@export var atmosphere_scattering: Vector3
@export var atmosphere_modulate: Vector3
@export var has_clouds: bool

@export var sun_dir: Vector3
@export var planet_position: Vector3
@export var voxel_terrain: VoxelLodTerrain
@export var atmosphere_node: Node3D
@export var voxel_instancer: VoxelInstancer
@export var sun : DirectionalLight3D
@export var has_water: bool
@export var water_radius: float
@export var ore_settings: Array[Dictionary] = []

var planet_item_scenes: Dictionary
var _next_library_id: int = 0

func _build_generator(generator_config: Dictionary, graph_functions: Array) -> VoxelInstanceGenerator:
	var generator : VoxelInstanceGenerator = VoxelInstanceGenerator.new()

	if generator_config.emit_mode == "EMIT_FROM_VERTICES":
		generator.emit_mode = VoxelInstanceGenerator.EMIT_FROM_VERTICES
		generator.density = generator_config.density
	elif generator_config.emit_mode == "EMIT_ONE_PER_TRIANGLE":
		generator.emit_mode = VoxelInstanceGenerator.EMIT_ONE_PER_TRIANGLE

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
	if generator_config.has("min_scale"):
		generator.min_scale = generator_config.min_scale
	if generator_config.has("max_scale"):
		generator.max_scale = generator_config.max_scale
	if generator_config.has("noise_graph"):
		for graph_func in graph_functions:
			if graph_func.name == generator_config.noise_graph:
				generator.noise_graph = load(graph_func.path)

	var graph_function = generator.noise_graph
	if graph_function:
		var noise_id = graph_function.find_node_by_name(&"Noise_01")
		if noise_id:
			# (Opcional pero recomendable) Verificar que efectivamente es un FastNoise3D
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


func _register_multi_mesh_item(i: int, item, shared_data: Dictionary, generator: VoxelInstanceGenerator) -> void:
	var multi_mesh_item := VoxelInstanceLibraryMultiMeshItem.new()
	multi_mesh_item.generator = generator
	multi_mesh_item.lod_index = item.lod_index
	multi_mesh_item.scene = shared_data.packed_scene

	var library_id = _next_library_id
	_next_library_id += 1
	voxel_instancer.library.add_item(library_id, multi_mesh_item)

	var wind_speed: float = item.wind_speed if item.has("wind_speed") else 0.0
	multi_mesh_array.append({
		"mesh_item": multi_mesh_item,
		"wind_speed": wind_speed,
	})

	# planet_item_scenes usa el library_id en lloc de l'índex de l'item
	if shared_data.registered_scene != null:
		planet_item_scenes[library_id] = shared_data.registered_scene

	if shared_data.effective_mesh:
		for surface_idx in shared_data.effective_mesh.get_surface_count():
			var mat = shared_data.effective_mesh.surface_get_material(surface_idx)
			if mat is ShaderMaterial:
				item_transparent_materials.append({
					"shader": mat as ShaderMaterial,
					"wind_speed": wind_speed,
				})

func _load_vegetation() -> void:
	var generators = vegetation.generators
	var graph_functions = vegetation.hemisphere_graph_function
	voxel_instancer.library.clear()
	planet_item_scenes.clear()
	multi_mesh_array.clear()
	item_transparent_materials.clear()
	_next_library_id = 0

	for i in vegetation.items.size():
		_load_vegetation_item(i, vegetation.items[i], generators, graph_functions)


func _load_vegetation_item(i: int, item, generators, graph_functions) -> void:
	# Normalitza generator a array (compatibilitat amb items antics)
	var generator_names: Array = []
	if item.generator is Array:
		generator_names = item.generator
	else:
		generator_names = [item.generator]

	# Construeix el PackedScene i el mesh una sola vegada (és compartit)
	var shared_data = _build_item_shared_data(i, item)
	if shared_data.is_empty():
		return

	# Crea una entrada a la library per cada generator
	for generator_name in generator_names:
		var generator: VoxelInstanceGenerator = null
		for generator_config in generators:
			if generator_config.name == generator_name:
				generator = _build_generator(generator_config, graph_functions)
				break
		if generator == null:
			push_error("Error parsing vegetation, generator with name %s not found." % generator_name)
			continue

		_register_multi_mesh_item(i, item, shared_data, generator)

func _build_tree_packed_scene(scene_instantiated: Node, tree3d) -> Dictionary:
	var trunk: MeshInstance3D = tree3d.get_trunk_instance()
	var twig: MeshInstance3D = tree3d.get_twig_instance()

	var combined_mesh := ArrayMesh.new()

	# Trunk: encara és una sola surface
	if trunk and trunk.mesh:
		combined_mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			trunk.mesh.surface_get_arrays(0)
		)
		var trunk_mat = tree3d.get_material_trunk()
		if trunk_mat:
			combined_mesh.surface_set_material(combined_mesh.get_surface_count() - 1, trunk_mat)

	# Twig/foliage: ara pot tenir N surfaces amb materials propis
	if twig and twig.mesh:
		var twig_mesh: Mesh = twig.mesh
		for i in range(twig_mesh.get_surface_count()):
			combined_mesh.add_surface_from_arrays(
				Mesh.PRIMITIVE_TRIANGLES,
				twig_mesh.surface_get_arrays(i)
			)
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

	if tree3d is Bush3D:
		var collision_child := _build_tree_collision(trunk, tree3d.get_stem_origin_radius() * 1.1)
		new_root.add_child(collision_child)
		_set_owner_recursive(collision_child, new_root)
	else:
		var collision_child := _build_tree_collision(trunk, tree3d.trunk_max_radius * 1.1)
		new_root.add_child(collision_child)
		_set_owner_recursive(collision_child, new_root)

	var tree_scene := PackedScene.new()
	var err := tree_scene.pack(new_root)
	if err != OK:
		push_error("No se pudo empaquetar el árbol: %s" % err)
	new_root.queue_free()

	return {
		"scene": tree_scene,
		"mesh": combined_mesh,
	}


# Helper: obté l'array de materials del foliage independentment del tipus
func _get_twig_materials_array(tree3d) -> Array:
	if tree3d is Bush3D:
		var arr = tree3d.foliage_materials
		return arr if arr != null else []
	else:
		# Tree3D
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


func _init(_voxel_terrain: VoxelLodTerrain, _atmosphere_node: Node3D) -> void:
	voxel_terrain = _voxel_terrain
	atmosphere_node = _atmosphere_node
	voxel_instancer = VoxelInstancer.new()
	voxel_instancer.library = VoxelInstanceLibrary.new()
	voxel_instancer.up_mode = VoxelInstancer.UP_MODE_SPHERE
	voxel_terrain.add_child(voxel_instancer)
	shader_material = ShaderMaterial.new()
	shader_material.shader = load("res://shaders/terrain/planet_biomes.gdshader")


func setup_shader_parameters() -> void:
	voxel_terrain.material = shader_material

	shader_material.set_shader_parameter("transition_smoothness", 10)
	shader_material.set_shader_parameter("biome_transition_smoothness", biome_transition_smoothness)
	planet_position = voxel_terrain.get_parent().position
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
	shader_material.set_shader_parameter("biome_noise_strengths", biome_noise_strengths)
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

	shader_material.set_shader_parameter("has_water", 1 if has_water else 0)
	shader_material.set_shader_parameter("water_radius", radius - water_radius)

	_setup_ore_shader_parameters()

func _setup_ore_shader_parameters() -> void:
	# El shader solo necesita las texturas y el contador: el blending de ore lo lee del
	# voxel (CUSTOM1 / canal INDICES-WEIGHTS), que ahora rellena el VoxelGraph. El índice
	# guardado es el type_id (1=iron...), la textura es ore_*_textures[type_id - 1].
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
	if !terrain_generator_path.is_empty():
		voxel_terrain.generator = load(terrain_generator_path).duplicate(true)
	else:
		voxel_terrain.generator = voxel_terrain.generator.duplicate(true)

	var graph_generator: VoxelGeneratorGraph = voxel_terrain.generator

	if not graph_generator is VoxelGeneratorGraph:
		return

	var graph_generator_function: VoxelGraphFunction = graph_generator.get_main_function()
	for node_id in graph_generator_function.get_node_ids():
		var node_type = graph_generator_function.get_node_type_id(node_id)
		var node_data = graph_generator_function.get_node_type_info(node_type)
		var radius_found: bool = false
		for key in node_data:
			if key == "inputs":
				var value = node_data[key]
				for params in value:
					for param in params:
						if params[param] is String && params[param] == "radius":
							radius_found = true
							break
		if radius_found:
			graph_generator_function.set_node_param_by_name(node_id, "radius", radius)
			graph_generator.compile()

	if not ore_settings.is_empty():
		_apply_ore_params(graph_generator_function, ore_settings)
		var compile_result = graph_generator.compile()
		if compile_result is Dictionary and not compile_result.get("success", true):
			push_error("Planet: VoxelGraph compile falló: %s (nodo %s)" % [
				compile_result.get("message", ""), compile_result.get("node_id", -1)])
		_publish_ore_drop_table()

# --- Parámetros de ore (data-driven sobre nodos creados a mano en el editor) --------------
# La ESTRUCTURA de nodos (Spots3D -> gate por SDF -> OutputWeight) se autora en el editor del
# VoxelGraph, porque add_node/add_connection no están expuestos a GDScript en este build.
# Aquí solo empujamos los params del JSON a los nodos NOMBRADOS, igual que el parcheo de 'radius':
#   - Spots3D nombrado "ore_spots_<type_id>"  <- seed, cell_size, spot_radius, jitter
#   - Divide  nombrado "ore_depth_<type_id>"  <- b = surface_depth   (gate = max(0, 1-|sdf|/depth))
func _apply_ore_params(fn: VoxelGraphFunction, ores: Array) -> void:
	# Volcado de introspección (una vez) para ver los nombres reales de inputs/params del build.
	print("[ore-graph] set_node_default_input disponible: ", fn.has_method("set_node_default_input"))
	_dump_node_info(fn, VoxelGraphFunction.NODE_SPOTS_3D, "Spots3D")
	_dump_node_info(fn, VoxelGraphFunction.NODE_DIVIDE, "Divide")
	_dump_node_info(fn, VoxelGraphFunction.NODE_OUTPUT_WEIGHT, "OutputWeight")

	for ore in ores:
		var type_id := int(ore.get("type_id", 1))
		var spots_name := "ore_spots_%d" % type_id
		var depth_name := "ore_depth_%d" % type_id

		var spots := fn.find_node_by_name(spots_name)
		if spots <= 0:
			push_warning("Planet: no se encontró el nodo Spots3D '%s'; ¿lo creaste y nombraste en el grafo?" % spots_name)
		else:
			_push_param(fn, spots, VoxelGraphFunction.NODE_SPOTS_3D, "seed", int(ore.get("noise_seed", 0)))
			_push_param(fn, spots, VoxelGraphFunction.NODE_SPOTS_3D, "cell_size", float(ore.get("cell_size", 40.0)))
			_push_param(fn, spots, VoxelGraphFunction.NODE_SPOTS_3D, "spot_radius", float(ore.get("spot_radius", 12.0)))
			_push_param(fn, spots, VoxelGraphFunction.NODE_SPOTS_3D, "jitter", float(ore.get("jitter", 0.9)))

		var depth_node := fn.find_node_by_name(depth_name)
		if depth_node <= 0:
			push_warning("Planet: no se encontró el nodo Divide '%s' del gate de profundidad." % depth_name)
		else:
			var depth: float = maxf(float(ore.get("surface_depth", 10.0)), 0.001)
			_push_param(fn, depth_node, VoxelGraphFunction.NODE_DIVIDE, "b", depth)

func _push_param(fn: VoxelGraphFunction, node_id: int, type_id: int, setting: String, value) -> void:
	# Distinguimos INPUT (con valor por defecto, p.ej. cell_size/spot_radius/jitter/b) de PARAM
	# (p.ej. seed/layer). set_node_param_by_name SOLO vale para params; los inputs van por
	# set_node_default_input(node, input_index, value).
	var info = fn.get_node_type_info(type_id)
	var in_idx := _input_index(info, setting)
	if in_idx >= 0:
		if fn.has_method("set_node_default_input"):
			fn.set_node_default_input(node_id, in_idx, value)
		else:
			push_warning("Planet: '%s' es input (idx %d) pero set_node_default_input no existe; ponlo a mano en el editor." % [setting, in_idx])
	else:
		# No es input -> asumimos param. set_node_param_by_name asertará si tampoco existe.
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
	# Reemplaza OreVoxelGenerator.get_ore_drop: publica type_id -> drop como meta del terreno,
	# que ActionController lee al minar.
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

func _update_planet() -> void:
	for mat_struct in item_transparent_materials:
		var mat = mat_struct.shader as ShaderMaterial
		mat.set_shader_parameter("light_direction", sun_dir)
		mat.set_shader_parameter("planet_position", planet_position)
		mat.set_shader_parameter("wind_direction", wind_direction)
		mat.set_shader_parameter("wind_speed", mat_struct.wind_speed)
