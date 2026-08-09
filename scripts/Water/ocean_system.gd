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

@export_group("Shore swash")
## Lámina de la rompiente sobre la playa. La pinta el TERRENO, no el agua: allí la altura sobre el
## nivel del mar es exacta y no hay que deducir la línea de agua de ningún buffer. Ver u_shore_swash
## en planet_biomes.gdshader. Recorrido VERTICAL del frente; 0 apaga el efecto.
@export_range(0.0, 6.0, 0.05) var swash_rise: float = 1.2
## Grosor de la lámina de espuma detrás del frente, en metros de altura.
@export_range(0.05, 4.0, 0.05) var swash_sheet: float = 0.8
## Metros de adelanto SOBRE el automático. El automático ya compensa la franja donde el agua apaga su
## propia ola (shoreline_fade en gerstner_waves.gdshaderinc): sin él la lámina sube cuando la cresta
## alcanza el litoral horneado, varios segundos después de que se la haya visto morir. Sube esto si
## aún llega tarde, bájalo (negativo) si se adelanta a la ola.
@export_range(-40.0, 40.0, 0.5) var swash_lead_extra: float = 0.0

@export_group("Debug")
## Marca roja sobre la superficie que calcula la CPU bajo el jugador. Sirve para separar tres fallos
## que se confunden entre sí cuando "el nado no va al unísono":
##   - la marca cabalga el agua visible  -> el sampler está bien; el problema es el umbral de nado
##     (swimming_offset, o dónde cae global_position en el cuerpo)
##   - la marca flota o se hunde de forma constante -> desacuerdo de radio base, no de oleaje
##   - la marca va en otra fase que las crestas -> la réplica CPU diverge del shader de verdad
@export var debug_water_marker: bool = false

@export var underwater: Underwater
var quadtree_manager: QuadTreeManager
var mesh_manager: QuadTreeMeshManager
var stats_label: Label
var current_water_time := 0.0
var planet: Planet
var _last_sun_dir := Vector3.INF
var _stats_accum := 0.0
var _waterline_sampler: WaterHeightSampler
var _water_marker: MeshInstance3D
var _swim_marker: MeshInstance3D
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
	_update_shore_swash()
	_update_water_marker()

	if show_stats and stats_label:
		_stats_accum += delta
		if _stats_accum >= STATS_INTERVAL:
			_stats_accum = 0.0
			_update_stats()

## Posa una marca sobre la superficie que calcula la CPU bajo el jugador, para poder comparar a ojo
## la réplica con la superficie que dibuja el shader. Ver debug_water_marker para leer el resultado.
func _update_water_marker() -> void:
	if not debug_water_marker:
		if _water_marker != null:
			_water_marker.visible = false
		if _swim_marker != null:
			_swim_marker.visible = false
		return
	if player == null or not is_instance_valid(player) or _waterline_sampler == null:
		return
	if _water_marker == null:
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.15, 0.1)
		# Sin test de profundidad se ve también desde bajo el agua, que es justo cuando interesa.
		mat.no_depth_test = true
		sphere.material = mat
		_water_marker = MeshInstance3D.new()
		_water_marker.mesh = sphere
		_water_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# La interpolación de física está activada en el proyecto y recolocar esto desde _process
		# sin desactivarla mete un frame de retraso, justo el error que venimos a medir.
		_water_marker.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_water_marker)
	_water_marker.visible = true

	if mesh_manager == null or mesh_manager.default_material == null:
		return
	var mat_w := mesh_manager.default_material as ShaderMaterial
	if mat_w == null:
		return
	var center: Vector3 = mat_w.get_shader_parameter(&"planet_center")
	var surface := _waterline_sampler.get_surface_at(
		player.global_position, WaterHeightSampler.get_water_time(mat_w), center)
	_water_marker.global_position = surface.point

	# Segunda marca: el UMBRAL de nado, no la superficie. Se lee del propio jugador, así que además
	# compara los dos samplers: si la azul no cuelga justo swimming_offset por debajo de la roja, es
	# que el sampler del jugador y el de aquí no están calculando la misma superficie.
	var swim_r: Variant = player.get("_water_surface_radius")
	var swim_off: Variant = player.get("swimming_offset")
	if swim_r == null or swim_off == null:
		return
	if _swim_marker == null:
		_swim_marker = _water_marker.duplicate() as MeshInstance3D
		var swim_mesh := (_swim_marker.mesh as SphereMesh).duplicate() as SphereMesh
		var swim_mat := (swim_mesh.material as StandardMaterial3D).duplicate() as StandardMaterial3D
		swim_mat.albedo_color = Color(0.2, 0.6, 1.0)
		swim_mesh.material = swim_mat
		_swim_marker.mesh = swim_mesh
		add_child(_swim_marker)
	_swim_marker.visible = true
	var up := (player.global_position - center).normalized()
	_swim_marker.global_position = center + up * (float(swim_r) - float(swim_off))


## Empuja al terreno la fase de la rompiente para que pinte la lámina de swash en la playa.
##
## Va por global uniform y no por el material del terreno porque el VoxelLodTerrain copia el material
## por bloque y set_shader_parameter no alcanza a los ya mallados. El término temporal de la fase se
## calcula AQUÍ, a partir de los mismos shore_speed/shore_length del material del agua: así la espuma
## de la arena y las crestas de la ola no pueden desincronizarse aunque se tuneen los uniforms en
## vivo, que es justo lo que pasaría replicando la fórmula en el shader del terreno.
func _update_shore_swash() -> void:
	if mesh_manager == null or mesh_manager.default_material == null:
		return
	var mat := mesh_manager.default_material as ShaderMaterial
	if mat == null:
		return
	var shore_on: Variant = mat.get_shader_parameter(&"shore_waves_enabled")
	if shore_on == null or not bool(shore_on) or swash_rise <= 0.0:
		RenderingServer.global_shader_parameter_set(&"u_shore_swash", Vector4.ZERO)
		return

	# get_shader_parameter devuelve null para lo que el .tres no fije explícitamente, aunque el shader
	# declare un default. Sin este relevo un material recién creado tumbaría el _process entero.
	var length_v: Variant = mat.get_shader_parameter(&"shore_length")
	var speed_v: Variant = mat.get_shader_parameter(&"shore_speed")
	if length_v == null or speed_v == null:
		RenderingServer.global_shader_parameter_set(&"u_shore_swash", Vector4.ZERO)
		return
	var length: float = length_v
	var speed: float = speed_v
	var time := WaterHeightSampler.get_water_time(mat)
	var k := TAU / maxf(length, 0.1)
	# Adelanto de fase. La ola de orilla se apaga a shoreline_fade_end metros del litoral, así que la
	# cresta desaparece de la vista antes de llegar: disparar la lámina en w = 0 la deja esa distancia
	# entera de retraso (a shore_speed/sqrt(k) m/s, varios segundos). Evaluamos la fase como si el
	# frente estuviera ahí fuera, que es donde el jugador ve morir la cresta. Se lee de los mismos
	# uniforms que usa el agua para calcular esa franja, así que sigue cuadrando si los tuneas.
	var depth_fade_v: Variant = mat.get_shader_parameter(&"shore_depth_fade")
	var depth_fade: float = depth_fade_v if depth_fade_v != null else 0.0
	var lead := maxf(length * 0.25, depth_fade) + swash_lead_extra
	# El término temporal se envuelve a [0, TAU) aquí, donde las cuentas son en doble precisión. El
	# shader solo lo pasa por sin() y fract(), ambos periódicos, así que es exacto; y le evita operar
	# en float32 con un ángulo que crece sin límite durante toda la partida. El canal 'y' NO se
	# envuelve: lo consume shore_breakup, que avanza a dos ritmos distintos, y tocarlo separaría la
	# espuma de la playa de las crestas del agua.
	var phase := fmod(time * speed * sqrt(k) + k * lead, TAU)
	RenderingServer.global_shader_parameter_set(&"u_shore_swash",
		Vector4(phase, time, swash_rise, swash_sheet))


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
