extends Node3D
class_name OceanSystem

## Sistema de océano de un planeta: monta el quadtree de agua (QuadTreeManager + mesh manager) y la
## niebla submarina (Underwater), propaga sus ajustes y muestra estadísticas opcionales.

@export_group("Underwater settings")
@export var sun_dir: Vector3

@export_group("Water settings")
@export var player: CharacterBody3D
@export var radius: float = 40000;
@export var sub_divisions: int = 32
@export var subdivision_factor: float = 2.0
@export var max_lod: int = 5
@export var atmosphere_height: float = 1000.0
@export var enable_wireframe: bool = false
@export var use_gpu_compute: bool = true
@export var camera: Camera3D
@export var debug: bool = false
@export var quadtree_material: Material
@export var wireframe_material: Material
@export var show_stats: bool = false
## Vista de depuración del campo de orilla; ver shore_debug_color en gerstner_waves.gdshaderinc.
## 0 = off | 1 = peso | 2 = fase | 3 = sentido contra la batimetría | 4 = relevo | 5 = amplitud
@export_range(0, 5) var shore_debug_mode: int = 0

@export var underwater: Underwater
var quadtree_manager: QuadTreeManager
var mesh_manager: QuadTreeMeshManager
var stats_label: Label
var current_water_time := 0.0
var planet: Planet
var _last_sun_dir := Vector3.INF
var _stats_accum := 0.0
var _waterline_sampler: WaterHeightSampler
## Mapa del planeta, que llega cuando termina de hornearse. Sin él la línea de flotación de CPU no
## vería ni la máscara de temporal ni las olas de orilla, y se separaría de la que dibuja el shader.
var world_map: PlanetWorldMap

const STATS_INTERVAL := 0.25

func _ready() -> void:
	if debug:
		load_watersphere(null)

func load_watersphere(_planet: Planet):
	if !Engine.is_editor_hint():
		planet = _planet
		underwater = Underwater.new()
		add_child(underwater)
		underwater.setup_underwater(quadtree_material as ShaderMaterial, radius)

	_setup_managers()
	_setup_ui()
	if !enable_wireframe:
		mesh_manager.default_material = quadtree_material
	else:
		mesh_manager.default_material = wireframe_material
	
	mesh_manager.compute_mode = (
		QuadTreeMeshManager.ComputeMode.GPU 
		if use_gpu_compute 
		else QuadTreeMeshManager.ComputeMode.CPU
	)
	
func _setup_managers():
	quadtree_manager = QuadTreeManager.new()
	mesh_manager = QuadTreeMeshManager.new()
	
	mesh_manager.sub_divisions = sub_divisions
	mesh_manager.atmosphere_height = atmosphere_height
	mesh_manager.player = player
	quadtree_manager.radius = radius
	quadtree_manager.max_lod = max_lod
	quadtree_manager.subdivision_factor = subdivision_factor
	quadtree_manager.player = player
	mesh_manager.radius = radius

	add_child(quadtree_manager)
	add_child(mesh_manager)
	
	mesh_manager.initialize(quadtree_manager)

func _setup_ui():
	if show_stats:
		var canvas_layer = CanvasLayer.new()
		add_child(canvas_layer)
		
		stats_label = Label.new()
		stats_label.position = Vector2(10, 10)
		stats_label.add_theme_font_size_override("font_size", 16)
		stats_label.add_theme_color_override("font_color", Color.WHITE)
		stats_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		stats_label.add_theme_constant_override("shadow_offset_x", 2)
		stats_label.add_theme_constant_override("shadow_offset_y", 2)
		canvas_layer.add_child(stats_label)

func _process(delta):
	# El sol se mueve en vivo (día/noche): leemos la dirección actual del planeta en lugar
	# del export, que solo se fijaba al cargar y dejaba el agua iluminada como de día siempre.
	# to_sun apunta HACIA el sol. La superficie niega sun_direction internamente (espera la
	# dirección de la luz saliente), el underwater no; por eso los alimentamos con signo opuesto.
	var to_sun := planet.sun_dir if planet else sun_dir

	if to_sun.distance_squared_to(_last_sun_dir) > 0.0000001:
		_last_sun_dir = to_sun
		if mesh_manager && mesh_manager.default_material:
			var mat = mesh_manager.default_material as ShaderMaterial
			mat.set_shader_parameter(&"sun_direction", -to_sun)
		if underwater:
			underwater.sun_direction = to_sun

	# Cada frame, para poder cambiar de vista en vivo desde el inspector remoto.
	if mesh_manager && mesh_manager.default_material:
		(mesh_manager.default_material as ShaderMaterial).set_shader_parameter(
			&"shore_debug_mode", shore_debug_mode)
	_update_waterline()

	if show_stats and stats_label:
		_stats_accum += delta
		if _stats_accum >= STATS_INTERVAL:
			_stats_accum = 0.0
			_update_stats()

## Empuja el plano de la línea de flotación bajo la cámara. Antes lo calculaba el vertex shader del
## agua a partir de CAMERA_POSITION_WORLD: el mismo valor para todos los vértices, y cada uno pagaba
## tres evaluaciones completas de la superficie Gerstner. Aquí sale una vez por frame, y de paso la
## superficie y la niebla submarina reciben EL MISMO plano en vez de calcularlo cada una.
func _update_waterline() -> void:
	if mesh_manager == null or mesh_manager.default_material == null:
		return
	var mat := mesh_manager.default_material as ShaderMaterial
	var cam := camera if camera != null else get_viewport().get_camera_3d()
	if mat == null or cam == null:
		return

	if _waterline_sampler == null:
		_waterline_sampler = WaterHeightSampler.new()
		add_child(_waterline_sampler)
		# radius es el radio de agua autoritativo: leerlo del material daría 0.0 (el .tres) hasta que
		# el mesh manager lo reescribe por-frame, y el sampler lo cachea una sola vez en setup.
		_waterline_sampler.setup(mat, world_map, radius)
	# El mapa se hornea en un hilo y puede llegar después del primer frame.
	_waterline_sampler.world_map = world_map

	var center: Vector3 = mat.get_shader_parameter(&"planet_center")
	var surface := _waterline_sampler.get_surface_at(
		cam.global_position, WaterHeightSampler.get_water_time(mat), center)
	mat.set_shader_parameter(&"waterline_point", surface.point)
	mat.set_shader_parameter(&"waterline_normal", surface.normal)


func _update_stats():
	var stats = mesh_manager.get_statistics()
	var fps = Engine.get_frames_per_second()
	
	var text = "FPS: %d\n" % fps
	text += "Mode: %s\n" % stats.compute_mode
	text += "Active Quads: %d\n" % stats.active_quads
	text += "Total Vertices: %s\n" % _format_number(stats.total_vertices)
	text += "Total Triangles: %s" % _format_number(stats.total_triangles)
	
	stats_label.text = text

func _format_number(num: int) -> String:
	if num >= 1000000:
		return "%.2fM" % (num / 1000000.0)
	elif num >= 1000:
		return "%.1fK" % (num / 1000.0)
	else:
		return str(num)
