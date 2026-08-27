extends Node3D
class_name Underwater

## Niebla submarina: quad a pantalla completa cuya frontera es la misma superficie Gerstner
## del agua (include compartido con water_shader). Cada frame copia del material del agua los
## parámetros de ola que weather y player mutan en caliente, y reaplica sus propios ajustes
## de niebla/godrays para poder afinarlos en vivo desde el inspector remoto.

@export_group("Fog Settings")
@export var fog_density: float = 1.0
@export var fog_color: Color = Color(0.7, 0.8, 0.9, 1.0)
@export var deep_fog_color: Color = Color(0.1, 0.2, 0.3, 1.0)
@export var abyss_fog_color: Color = Color(0.1, 0.1, 0.15, 1.0)
@export var deep_transition_depth: float = 100.0
@export var abyss_transition_depth: float = 250.0
@export var absorption_coefficients: Vector3 = Vector3(0.45, 0.18, 0.06)
@export var distance_depth_gain: float = 0.7
@export var distance_depth_max: float = 120.0
@export var sun_glow_intensity: float = 0.35
@export var sun_glow_power: float = 8.0
@export var atmosphere_leak_distance: float = 250.0
@export var atmosphere_leak_falloff: float = 0.08
@export var waterline_seal_distance: float = 3.0
@export var waterline_seal_band: float = 0.06
@export var waterline_seal_depth_bias: float = 0.0
@export var surface_search_distance: float = 80.0
@export var underside_refraction: float = 1.5

@export_group("Debug")
## 0 = off | 1 = clasificación de píxel | 2 = columna de agua | 3 = normal del techo | 4 = búsqueda de salida
@export_range(0, 4) var debug_mode: int = 0
@export var debug_scale: float = 20.0

@export_group("Godray Settings")
@export var godray_intensity: float = 3.0
@export var godray_samples: int = 12
@export var godray_max_distance: float = 40.0
@export var godray_pattern_scale: float = 0.01
@export var godray_pattern_speed: float = 0.01
@export var godray_sharpness: float = 2.5
@export var godray_phase_power: float = 6.0
@export var godray_min_phase: float = 0.15

var sun_direction: Vector3
var material: ShaderMaterial
var water_material: ShaderMaterial
var _mesh_instance: MeshInstance3D

# Uniforms del material del agua que definen la superficie y se replican cada frame.
const _SYNCED_WATER_PARAMS: Array[StringName] = [
	&"wave_direction", &"wave_speed", &"wave_amplitude", &"wave_base_length",
	&"wave_steepness", &"wave_octaves", &"wave_pole",
	&"water_time", &"planet_center", &"water_radius",
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
# bajo el agua. Se copian del material del quad, NO del material del agua: así los tres leen el
# mismo valor y el corte no puede divergir aunque alguien retoque la niebla en caliente.
const _TRANSLUCENT_BLOCK_PARAMS: Array[StringName] = [
	&"planet_center", &"water_radius",
	&"absorption_coefficients", &"fog_density",
	&"fog_color", &"deep_fog_color", &"abyss_fog_color",
	&"deep_transition_depth", &"abyss_transition_depth",
	&"distance_depth_gain", &"distance_depth_max",
	&"sun_direction", &"sun_glow_intensity", &"sun_glow_power",
	&"atmosphere_leak_distance", &"atmosphere_leak_falloff",
]

# Colores del cielo sintético, que el cristal refleja igual que la superficie del agua. Estos NO
# los tiene el quad: su origen es el material del agua, que es donde están afinados.
const _SKY_PARAMS_FROM_WATER: Array[StringName] = [
	&"sky_color_horizon", &"sky_color_zenith",
	&"sky_color_horizon_night", &"sky_color_zenith_night",
	&"sky_gradient_power",
]

# Parámetros de cáusticas espejados del water_shader una sola vez en el setup (no los muta el weather).
const _CAUSTICS_PARAMS: Array[StringName] = [
	&"caustics_texture", &"caustics_scale", &"caustics_speed",
	&"caustics_intensity", &"caustics_depth_fade", &"caustics_near_fade",
]

func setup_underwater(source_water_material: ShaderMaterial, water_radius: float) -> void:
	water_material = source_water_material
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/liquid/underwater.gdshader")
	# La niebla se dibuja antes que la superficie del agua para que esta se vea desde abajo.
	material.render_priority = -1

	var quad_mesh := QuadMesh.new()
	quad_mesh.orientation = PlaneMesh.FACE_Z
	quad_mesh.size = Vector2(2.0, 2.0)
	quad_mesh.flip_faces = true

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.material_override = material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# extra_cull_margin se clampa a 16384: con radios de agua mayores el quad se llegaba a
	# cullear. Un AABB custom enorme garantiza que el quad de pantalla completa nunca se corte.
	_mesh_instance.custom_aabb = AABB(Vector3(-1, -1, -1) * water_radius * 2.0, Vector3(2, 2, 2) * water_radius * 2.0)
	_mesh_instance.mesh = quad_mesh
	add_child(_mesh_instance)

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
	material.set_shader_parameter(&"atmosphere_leak_distance", atmosphere_leak_distance)
	material.set_shader_parameter(&"atmosphere_leak_falloff", atmosphere_leak_falloff)
	material.set_shader_parameter(&"waterline_seal_distance", waterline_seal_distance)
	material.set_shader_parameter(&"waterline_seal_band", waterline_seal_band)
	material.set_shader_parameter(&"waterline_seal_depth_bias", waterline_seal_depth_bias)
	material.set_shader_parameter(&"debug_mode", debug_mode)
	material.set_shader_parameter(&"debug_scale", debug_scale)
	material.set_shader_parameter(&"surface_search_distance", surface_search_distance)
	material.set_shader_parameter(&"underside_refraction", underside_refraction)
	material.set_shader_parameter(&"godray_intensity", godray_intensity)
	material.set_shader_parameter(&"godray_samples", godray_samples)
	material.set_shader_parameter(&"godray_max_distance", godray_max_distance)
	material.set_shader_parameter(&"godray_pattern_scale", godray_pattern_scale)
	material.set_shader_parameter(&"godray_pattern_speed", godray_pattern_speed)
	material.set_shader_parameter(&"godray_sharpness", godray_sharpness)
	material.set_shader_parameter(&"godray_phase_power", godray_phase_power)
	material.set_shader_parameter(&"godray_min_phase", godray_min_phase)

func _process(_delta: float) -> void:
	if material == null or water_material == null:
		return
	for param in _SYNCED_WATER_PARAMS:
		material.set_shader_parameter(param, water_material.get_shader_parameter(param))
	material.set_shader_parameter(&"sun_direction", sun_direction)
	_apply_settings()
	_sync_translucent_block_materials()


## Empuja al material de los bloques traslúcidos los parámetros de agua y niebla del quad. Hace
## falta porque el quad se descarta entero con la cámara dentro de un compartimento seco
## (underwater.gdshader: inside_ship_interior), y entonces una ventana sumergida es lo único que
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
