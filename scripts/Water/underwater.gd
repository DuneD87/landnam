extends Node3D
class_name Underwater

## Captura los parámetros del agua para el compositor POST_TRANSPARENT.
## La óptica se resuelve después de la atmósfera, sin geometría ni profundidad ficticia.

@export_group("Fog Settings")
@export var fog_density: float = 1.0
@export var fog_color: Color = Color("245661")
@export var deep_fog_color: Color = Color("0f303f")
@export var abyss_fog_color: Color = Color("030c16")
@export var deep_transition_depth: float = 100.0
@export var abyss_transition_depth: float = 250.0
@export var absorption_coefficients: Vector3 = Vector3(0.45, 0.18, 0.06)
@export_range(0.0, 2.0, 0.01) var absorption_scale: float = 0.4
@export var scattering_coefficients: Vector3 = Vector3(0.015, 0.022, 0.020)
@export_range(0.0, 2.0, 0.01) var surface_exposure: float = 0.95
@export_range(0.0, 1.0, 0.01) var surface_saturation: float = 0.65
@export var distance_depth_gain: float = 0.7
@export var distance_depth_max: float = 120.0
@export var sun_glow_intensity: float = 0.35
@export var sun_glow_power: float = 8.0
@export var waterline_seal_distance: float = 3.0
@export var waterline_seal_band: float = 0.06
@export var surface_search_distance: float = 80.0
## 0 desactiva la refracción; 1.5 es la intensidad base; valores mayores amplifican las ondulaciones.
@export_range(0.0, 8.0, 0.1) var underside_refraction: float = 4.5
## Distancia en metros hasta la superficie: alcance del cielo proyectado sobre ella.
@export_range(1.0, 100.0, 0.5) var surface_projection_distance: float = 18.0
## Predominio de reflexión al mirar la superficie de lado; transición continua sin cono visible.
@export_range(0.0, 1.0, 0.01) var surface_reflection_strength: float = 1.0
## Tamaño de la ondulación del techo, relativo al detalle del material exterior.
## Por encima de 1 el techo queda más liso que el mar visto desde arriba; por debajo, más picado.
@export_range(0.05, 6.0, 0.05) var surface_ripple_scale: float = 1.0
## Fuerza de esa ondulación. Va aparte de normal_intensity, que la comparte el mar exterior.
@export_range(0.0, 6.0, 0.05) var surface_ripple_strength: float = 4.0
## 0 = transición ancha por toda la bóveda; 1 = ángulo crítico real. Es lo que le da borde
## a la ventana de Snell para que las ondas puedan romperla en fragmentos.
@export_range(0.0, 1.0, 0.01) var surface_window_sharpness: float = 0.8

@export_group("Caustics")
## La textura, escala y velocidad se heredan del material del agua; la intensidad y
## el alcance no, porque aquí modulan el color del receptor y allí se suman al fondo.
@export var caustics_intensity: float = 0.8
@export var caustics_depth_fade: float = 0.18
@export var caustics_near_fade: float = 1.5

@export_group("Debug")
## 0 = off | 1 = clasificación de píxel | 2 = columna de agua | 3 = normal del techo | 4 = búsqueda de salida
## 5 = ganancia de cáusticas | 6 = regiones de la ventana | 7 = elevación de salida del rayo
@export_range(0, 7) var debug_mode: int = 0
@export var debug_scale: float = 20.0

@export_group("Godray Settings")
@export var godray_intensity: float = 1.0
@export var godray_samples: int = 24
@export var godray_max_distance: float = 40.0
@export var godray_pattern_scale: float = 0.1
@export var godray_pattern_speed: float = 1.0
@export var godray_sharpness: float = 6.0
@export var godray_phase_power: float = 6.0
@export var godray_min_phase: float = 0.15
## Ata los haces a la ola. A 0 por defecto: los ata también a su velocidad (~10 m/s), y
## entonces o viajan a esa velocidad o el patrón se desliza contra ellos y eso se ve como
## parpadeo. Las cuchillas ya las dibuja la textura.
@export var godray_surface_focus: float = 0.0

var sun_direction: Vector3
var material: ShaderMaterial
var water_material: ShaderMaterial
var _atmosphere: PlanetAtmosphere

# Uniforms del material del agua que definen la superficie y se replican cada frame.
const _SYNCED_WATER_PARAMS: Array[StringName] = [
	&"wave_direction", &"wave_speed", &"wave_amplitude", &"wave_base_length",
	&"wave_steepness", &"wave_pole",
	&"spectrum_spread",
	&"water_time", &"planet_center", &"water_radius",
	&"texture_normal", &"texture_normal2", &"normal_scale1", &"normal_scale2",
	&"normal_intensity", &"normal_slope_limit",
	# Máscara de temporal: la niebla submarina evalúa la MISMA superficie, así que si no recibe la
	# máscara su corte se separa del de la superficie justo en lagos y orilla.
	&"storm_mask_enabled", &"storm_height_map", &"storm_body_map",
	&"storm_height_min", &"storm_height_range", &"storm_sea_height",
	&"storm_body_ids", &"storm_body_count",
	&"storm_depth_start", &"storm_depth_full",
	&"wave_calm_amplitude", &"wave_calm_steepness",
	# Olas de orilla: idem, forman parte de la misma superficie.
	&"shore_waves_enabled", &"shore_offset_map",
	&"shore_amplitude", &"shore_length", &"shore_speed", &"shore_steepness",
	&"shore_depth_fade", &"shore_shoal_max", &"shore_incidence",
	&"shore_reach", &"shore_range", &"shore_fade", &"shore_handover", &"shore_chop",
	# Plano de la línea de flotación: los dos shaders TIENEN que recibir el mismo, es lo que hace
	# que el corte de la niebla y el de la superficie caigan en el mismo sitio.
	&"waterline_point", &"waterline_normal",
	&"interior_count", &"interior_center",
	&"interior_axis_x", &"interior_axis_y", &"interior_axis_z",
]

# Lo que necesita el shader de los bloques traslúcidos (cristal) para nieblarse solo cuando queda
# bajo el agua. Se copian del material de parámetros: así los tres leen el
# mismo valor y el corte no puede divergir aunque alguien retoque la niebla en caliente.
const _TRANSLUCENT_BLOCK_PARAMS: Array[StringName] = [
	&"planet_center", &"water_radius",
	&"waterline_point", &"waterline_normal", &"interior_count", &"interior_center",
	&"interior_axis_x", &"interior_axis_y", &"interior_axis_z",
	&"absorption_coefficients", &"fog_density",
	&"fog_color", &"deep_fog_color", &"abyss_fog_color",
	&"deep_transition_depth", &"abyss_transition_depth",
	&"distance_depth_gain", &"distance_depth_max",
	&"sun_direction", &"sun_glow_intensity", &"sun_glow_power",
]

# Colores del cielo sintético, que el cristal refleja igual que la superficie del agua. Estos NO
# los tiene el material de parámetros: su origen es el material del agua, que es donde están afinados.
const _SKY_PARAMS_FROM_WATER: Array[StringName] = [
	&"sky_color_horizon", &"sky_color_zenith",
	&"sky_color_horizon_night", &"sky_color_zenith_night",
	&"sky_gradient_power",
]

# Patrón de cáusticas espejado del water_shader una sola vez en el setup (no lo muta el weather).
const _CAUSTICS_PARAMS: Array[StringName] = [
	&"caustics_texture", &"caustics_scale", &"caustics_speed",
]

func setup_underwater(source_water_material: ShaderMaterial, water_radius: float) -> void:
	water_material = source_water_material
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/liquid/underwater.gdshader")
	material.set_shader_parameter(&"water_radius", water_radius)
	# La absorción manda la del material del agua (puede venir ajustada en el .tres).
	var water_absorption: Variant = water_material.get_shader_parameter(&"absorption_coefficients")
	if water_absorption != null:
		absorption_coefficients = water_absorption

	for param in _CAUSTICS_PARAMS:
		var value: Variant = water_material.get_shader_parameter(param)
		if value != null:
			material.set_shader_parameter(param, value)

	_apply_settings()

## Empuja los exports de niebla y godrays al material; se llama cada frame para tuning en vivo.
func _apply_settings() -> void:
	material.set_shader_parameter(&"absorption_scale", absorption_scale)
	material.set_shader_parameter(&"scattering_coefficients", scattering_coefficients)
	material.set_shader_parameter(&"surface_exposure", surface_exposure)
	material.set_shader_parameter(&"surface_saturation", surface_saturation)
	material.set_shader_parameter(&"fog_color", fog_color)
	material.set_shader_parameter(&"deep_fog_color", deep_fog_color)
	material.set_shader_parameter(&"abyss_fog_color", abyss_fog_color)
	material.set_shader_parameter(&"deep_transition_depth", deep_transition_depth)
	material.set_shader_parameter(&"abyss_transition_depth", abyss_transition_depth)
	material.set_shader_parameter(&"absorption_coefficients", absorption_coefficients)
	material.set_shader_parameter(&"fog_density", fog_density)
	material.set_shader_parameter(&"distance_depth_gain", distance_depth_gain)
	material.set_shader_parameter(&"distance_depth_max", distance_depth_max)
	material.set_shader_parameter(&"sun_glow_intensity", sun_glow_intensity)
	material.set_shader_parameter(&"sun_glow_power", sun_glow_power)
	material.set_shader_parameter(&"waterline_seal_distance", waterline_seal_distance)
	material.set_shader_parameter(&"waterline_seal_band", waterline_seal_band)
	material.set_shader_parameter(&"debug_mode", debug_mode)
	material.set_shader_parameter(&"debug_scale", debug_scale)
	material.set_shader_parameter(&"surface_search_distance", surface_search_distance)
	material.set_shader_parameter(&"underside_refraction", underside_refraction)
	material.set_shader_parameter(&"surface_projection_distance", surface_projection_distance)
	material.set_shader_parameter(&"surface_reflection_strength", surface_reflection_strength)
	material.set_shader_parameter(&"surface_ripple_scale", surface_ripple_scale)
	material.set_shader_parameter(&"surface_ripple_strength", surface_ripple_strength)
	material.set_shader_parameter(&"surface_window_sharpness", surface_window_sharpness)
	material.set_shader_parameter(&"godray_intensity", godray_intensity)
	material.set_shader_parameter(&"godray_samples", godray_samples)
	material.set_shader_parameter(&"godray_max_distance", godray_max_distance)
	material.set_shader_parameter(&"godray_pattern_scale", godray_pattern_scale)
	material.set_shader_parameter(&"godray_pattern_speed", godray_pattern_speed)
	material.set_shader_parameter(&"godray_sharpness", godray_sharpness)
	material.set_shader_parameter(&"godray_phase_power", godray_phase_power)
	material.set_shader_parameter(&"godray_min_phase", godray_min_phase)
	material.set_shader_parameter(&"godray_surface_focus", godray_surface_focus)
	material.set_shader_parameter(&"caustics_intensity", caustics_intensity)
	material.set_shader_parameter(&"caustics_depth_fade", caustics_depth_fade)
	material.set_shader_parameter(&"caustics_near_fade", caustics_near_fade)

func _process(_delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_step(_delta)
	DebugStats.report_cost(&"agua:underwater", Time.get_ticks_usec() - _t0)


func _process_step(_delta: float) -> void:
	if material == null or water_material == null:
		return
	for param in _SYNCED_WATER_PARAMS:
		material.set_shader_parameter(param, water_material.get_shader_parameter(param))
	material.set_shader_parameter(&"sun_direction", sun_direction)
	_apply_settings()
	_sync_translucent_block_materials()
	if _atmosphere == null:
		var ancestor: Node = get_parent()
		while ancestor != null:
			var controller := ancestor.get_node_or_null("PlanetAtmosphereController") as PlanetAtmosphereController
			if controller != null and controller.effect != null:
				_atmosphere = controller.effect
				break
			ancestor = ancestor.get_parent()
	if _atmosphere != null:
		_atmosphere.underwater_pass.update_material(material)


## Empuja al material de los bloques traslúcidos los parámetros de agua y niebla del compositor. Hace
## falta porque el compositor excluye el agua con la cámara dentro de un compartimento seco
## (UnderwaterRenderPass: _inside_interior), y entonces una ventana sumergida es lo único que
## puede nieblar lo que se ve por ella.
func _sync_translucent_block_materials() -> void:
	for block_material in BlockDatabase.get_translucent_materials():
		# El cristal son dos materiales encadenados (transmisión + reflejo) y los dos necesitan
		# saber dónde está el mar: si solo se le empuja al primero, sus tests de sumergido divergen.
		var pass_material: Material = block_material
		while pass_material != null:
			var shader_material := pass_material as ShaderMaterial
			if shader_material:
				for param in _TRANSLUCENT_BLOCK_PARAMS:
					shader_material.set_shader_parameter(param, material.get_shader_parameter(param))
				for param in _SKY_PARAMS_FROM_WATER:
					shader_material.set_shader_parameter(param, water_material.get_shader_parameter(param))
			pass_material = pass_material.next_pass


func _exit_tree() -> void:
	if _atmosphere != null:
		_atmosphere.underwater_pass.update_material(null)
