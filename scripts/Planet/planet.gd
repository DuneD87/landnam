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

@export var sun_dir: Vector3
@export var planet_position: Vector3
@export var voxel_terrain: VoxelLodTerrain
@export var voxel_instancer: VoxelInstancer
@export var sun : DirectionalLight3D
@export var has_water: bool
@export var water_radius: float
@export var ore_settings: Array[Dictionary] = []

var planet_item_scenes: Dictionary
var _next_library_id: int = 0

## Multiplicador global de viento sobre la vegetación, controlado por el WeatherController.
var weather_wind_multiplier: float = 1.0

func _build_generator(generator_config: Dictionary, graph_functions: Array, lod_index: int = 0) -> VoxelInstanceGenerator:
	var generator : VoxelInstanceGenerator = VoxelInstanceGenerator.new()

	if generator_config.emit_mode == "EMIT_FROM_VERTICES":
		generator.emit_mode = VoxelInstanceGenerator.EMIT_FROM_VERTICES
	elif generator_config.emit_mode == "EMIT_ONE_PER_TRIANGLE":
		generator.emit_mode = VoxelInstanceGenerator.EMIT_ONE_PER_TRIANGLE
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
	
## Fija los 4 mesh_lodN_distance_ratio del item a partir de distancias de salto en metros.
## distances_m: [fin_LOD0, fin_LOD1, fin_LOD2] y opcionalmente [.., corte_LOD3].
## ratio = metros / (lod_distance · 2^lod_index); clamp a [0,1] y orden estrictamente creciente.
func _apply_mesh_lod_distances(multi_mesh_item, lod_index: int, distances_m: Array) -> void:
	if voxel_terrain == null:
		return
	var lod_distance: float = voxel_terrain.lod_distance
	var view_distance: float = lod_distance * float(1 << lod_index)
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

	var lm: Array = shared_data.get("lod_meshes", [])
	if lm.size() == 4:
		# CLAVE: nada de .scene aquí. 'scene' se usa EN LUGAR de las propiedades manuales,
		# así que anula los mesh_lod1..3 -> por eso nunca veías diferencia.
		multi_mesh_item.set_mesh(lm[0], 0)
		multi_mesh_item.set_mesh(lm[1], 1)
		multi_mesh_item.set_mesh(lm[2], 2)
		multi_mesh_item.set_mesh(lm[3], 3)

		var cs: Array = shared_data.get("collision_shapes", [])
		if not cs.is_empty():
			multi_mesh_item.collision_shapes = cs

		var dists: Array = item.get("mesh_lod_distances_m", [200.0, 350.0, 500.0])
		_apply_mesh_lod_distances(multi_mesh_item, lod_index, dists)
	else:
		# items sin LOD (MeshInstance directa, Rock3D): la escena sirve tal cual
		multi_mesh_item.scene = shared_data.packed_scene

	if not item.get("cast_shadow", true):
		if "cast_shadow" in multi_mesh_item:
			multi_mesh_item.cast_shadow = RenderingServer.SHADOW_CASTING_SETTING_OFF
		else:
			push_warning("VoxelInstanceLibraryMultiMeshItem sin 'cast_shadow' en esta versión del módulo")

	var library_id = _next_library_id
	_next_library_id += 1
	voxel_instancer.library.add_item(library_id, multi_mesh_item)

	var wind_speed: float = item.wind_speed if item.has("wind_speed") else 0.0
	multi_mesh_array.append({"mesh_item": multi_mesh_item, "wind_speed": wind_speed})

	if shared_data.registered_scene != null:
		planet_item_scenes[library_id] = shared_data.registered_scene

	if shared_data.effective_mesh:
		for surface_idx in shared_data.effective_mesh.get_surface_count():
			var mat = shared_data.effective_mesh.surface_get_material(surface_idx)
			if mat is ShaderMaterial:
				item_transparent_materials.append({"shader": mat as ShaderMaterial, "wind_speed": wind_speed})

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
	multi_mesh_array.clear()
	item_transparent_materials.clear()
	_next_library_id = 0

	for i in vegetation.items.size():
		_load_vegetation_item(i, vegetation.items[i], generators, graph_functions)


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

	shader_material.set_shader_parameter("transition_smoothness", 10)
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
	var all_functions: Array = [graph_generator_function]
	_gather_subfunctions(graph_generator_function, all_functions)

	var needs_compile := false
	for fn in all_functions:
		if _apply_radius(fn, radius):
			needs_compile = true

	if not ore_settings.is_empty():
		_apply_ore_params(all_functions, ore_settings)
		needs_compile = true

	if needs_compile:
		var compile_result = graph_generator.compile()
		if compile_result is Dictionary and not compile_result.get("success", true):
			push_error("Planet: VoxelGraph compile falló: %s (nodo %s)" % [
				compile_result.get("message", ""), compile_result.get("node_id", -1)])

	if not ore_settings.is_empty():
		_publish_ore_drop_table()

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
