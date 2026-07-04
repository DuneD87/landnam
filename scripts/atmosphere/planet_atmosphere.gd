@tool
extends CompositorEffect
class_name PlanetAtmosphere

const DEFAULT_SHADER_PATH := "res://shaders/atmosphere/planet_atmosphere.glsl"
const LOCAL_SIZE := 8
const PARAM_VEC4_COUNT := 24

@export var shader_file_path: String = DEFAULT_SHADER_PATH

@export_group("Planet")
@export var planet_center: Vector3 = Vector3.ZERO
@export var planet_radius: float = 1000.0
@export var atmosphere_radius: float = 1080.0
## Radio de la esfera de agua (0 = sin océano). La atmósfera se corta en la superficie del
## mar (que no está en el depth buffer) y se atenúa con la cámara sumergida.
@export var water_radius: float = 0.0

@export_group("Lighting")
@export var sun_direction: Vector3 = Vector3(1.0, 0.25, 0.1).normalized()

@export_group("Look")
@export var wavelengths: Vector3 = Vector3(700.0, 530.0, 440.0)
@export_range(0.1, 30.0, 0.01) var density_falloff: float = 4.0
@export_range(0.01, 30.0, 0.00015) var scattering_strength: float = 0.55
@export_range(0.0, 100.0, 0.01) var sun_intensity: float = 20.0

@export_group("Clouds")
@export var clouds_enabled: bool = true
@export_range(0.0, 5000.0, 1.0) var cloud_min_height: float = 400.0
@export_range(0.0, 5000.0, 1.0) var cloud_max_height: float = 600.0
@export_range(0.0, 5.0, 0.1) var cloud_density: float = 0.5
@export_range(0.0, 1.0, 0.01) var cloud_coverage: float = 0.55
@export_range(0.01, 1.0, 0.01) var cloud_absorption: float = 0.15
@export_range(0.0, 0.99, 0.01) var cloud_g: float = 0.9
@export_range(1.0, 10.0, 0.1) var cloud_noise_scale: float = 5
@export var cloud_wind_direction: Vector3 = Vector3(1.0, 0.0, 0.0)
@export_range(0.0, 1.0, 0.005) var cloud_wind_speed: float = 0.05
## Cuánto oscurecen las nubes el terreno bajo ellas (0 = sin sombra, 1 = máxima).
@export_range(0.0, 1.0, 0.01) var cloud_shadow_strength: float = 0.85
## Albedo de las nubes: 1 = blanco pleno, valores bajos = gris de tormenta. Lo fija el WeatherController.
@export_range(0.0, 1.0, 0.01) var cloud_albedo: float = 1.0

@export_group("Atmosphere")
## Multiplicador del in-scatter de Rayleigh (velo azul de perspectiva aérea). 1 = dispersión plena;
## valores bajos apagan el azul hacia un horizonte plomizo. El WeatherController lo fija por evento.
@export_range(0.0, 1.0, 0.01) var atmosphere_scatter: float = 1.0
## Destello de rayo (0..1) que el WeatherController empuja durante un relámpago: ilumina la base de
## las nubes como emisión breve (el compute no ve la luz auxiliar de escena). 0 = sin destello.
@export_range(0.0, 1.0, 0.01) var lightning_flash: float = 0.0

@export_group("Fog")
## Niebla a ras de suelo: capa volumétrica baja, independiente de las nubes. Su densidad
## la modula un ruido de gran escala advectado por el viento → el banco "llega de lejos".
@export var fog_enabled: bool = true
## Densidad global de la niebla. 0 = sin niebla. El WeatherController la sube/baja en las
## transiciones, así la niebla se desvanece en su sitio (no baja del cielo).
@export_range(0.0, 5.0, 0.05) var fog_density: float = 0.0
## Cobertura del banco: cuánta área cubre el frente (0 = parches sueltos, 1 = manto denso).
@export_range(0.0, 1.0, 0.01) var fog_coverage: float = 0.6
## Altura del suelo de la niebla sobre la superficie (m). Suele ser 0 = a ras.
@export_range(-50.0, 500.0, 1.0) var fog_floor_height: float = 0.0
## Altura del techo de la niebla sobre la superficie (m). Espesor = techo - suelo.
@export_range(10.0, 800.0, 1.0) var fog_top_height: float = 130.0
## Tinte de la niebla (se ilumina con el sol; más cálido en el terminador).
@export var fog_color: Color = Color(0.82, 0.84, 0.88)
## Velocidad con la que el banco de niebla viaja con el viento. Lo sobrescribe el WeatherController.
@export_range(0.0, 1.0, 0.005) var fog_wind_speed: float = 0.04
## Escala del ruido de gran escala del banco (bajo = masas grandes que se ven venir).
@export_range(0.2, 8.0, 0.1) var fog_noise_scale: float = 2.0
## Pasos de la marcha de la niebla. Más = transiciones más suaves en distancia, más coste.
@export_range(1, 64, 1) var fog_steps: int = 12
## Distancia de visibilidad de la niebla (m); mantenla bajo el radio de la rejilla de oclusión. 0 = sin límite.
@export_range(0.0, 400.0, 1.0) var fog_view_distance: float = 25.0
## Suavizado (m) del borde de oclusión de niebla en la boca de las cuevas (promedio 3x3).
@export_range(0.5, 30.0, 0.5) var fog_occlusion_softness: float = 15.0

@export_group("Cloud Quality")
## Pasos de la marcha de vista: más = menos banding y detalle más fino, más coste.
@export_range(1, 64, 1) var cloud_steps: int = 10
## Pasos de la marcha de luz (auto-sombra interna de la nube).
@export_range(1, 32, 1) var cloud_light_steps: int = 4
## Pasos de la marcha de la sombra proyectada sobre el suelo.
@export_range(1, 32, 1) var cloud_shadow_steps: int = 8

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var depth_sampler: RID
var params_buffers: Array[RID] = []

var _params_mutex := Mutex.new()

var _occ_enabled: bool = false
var _occ_center: Vector3 = Vector3.ZERO
var _occ_x: Vector3 = Vector3.RIGHT
var _occ_z: Vector3 = Vector3.BACK
var _occ_up: Vector3 = Vector3.UP
var _occ_half_size: float = 50.0
var _occ_span: float = 140.0
var _occ_below: float = 60.0
var _occ_margin: float = 4.0
var _occ_texture: Texture2D = null


func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT

	access_resolved_color = true
	access_resolved_depth = true

	rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(_initialize_compute)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_compute()


func set_planet_data(
	p_center: Vector3,
	p_planet_radius: float,
	p_atmosphere_radius: float,
	p_sun_direction: Vector3,
	p_water_radius: float = 0.0
) -> void:
	_params_mutex.lock()

	planet_center = p_center
	planet_radius = max(p_planet_radius, 0.001)
	atmosphere_radius = max(p_atmosphere_radius, planet_radius + 0.001)
	water_radius = max(p_water_radius, 0.0)

	if p_sun_direction.length_squared() > 0.000001:
		sun_direction = p_sun_direction.normalized()

	_params_mutex.unlock()


## La empuja el WeatherController con el estado del WeatherOcclusionField; enabled=false rellena niebla en todas partes.
func set_fog_occlusion(
	enabled: bool,
	center: Vector3, x_axis: Vector3, z_axis: Vector3, up: Vector3,
	half_size: float, span: float, below: float,
	height_tex: Texture2D, margin: float = 4.0
) -> void:
	_params_mutex.lock()
	_occ_enabled = enabled and height_tex != null
	_occ_center = center
	_occ_x = x_axis
	_occ_z = z_axis
	_occ_up = up
	_occ_half_size = max(half_size, 0.001)
	_occ_span = max(span, 0.001)
	_occ_below = below
	_occ_margin = margin
	_occ_texture = height_tex
	_params_mutex.unlock()


func _load_compute_spirv() -> RDShaderSPIRV:
	print("PlanetAtmosphere: loading shader from: ", shader_file_path)

	var resource := ResourceLoader.load(shader_file_path, "", ResourceLoader.CACHE_MODE_IGNORE)

	if resource != null:
		print("PlanetAtmosphere: loaded resource class: ", resource.get_class())
	else:
		print("PlanetAtmosphere: resource is null")

	if resource is RDShaderFile:
		print("PlanetAtmosphere: using RDShaderFile import.")
		var spirv: RDShaderSPIRV = (resource as RDShaderFile).get_spirv()

		print("PlanetAtmosphere: RDShaderFile compute error: ", spirv.compile_error_compute)
		print("PlanetAtmosphere: RDShaderFile compute bytecode size: ", spirv.bytecode_compute.size())

		return spirv

	print("PlanetAtmosphere: compiling manually from text.")

	var shader_code := FileAccess.get_file_as_string(shader_file_path)

	if shader_code.is_empty():
		push_error("PlanetAtmosphere: shader file is empty or could not be read: %s" % shader_file_path)
		return null

	shader_code = shader_code.replace("#[compute]", "")

	var shader_source := RDShaderSource.new()
	shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	shader_source.source_compute = shader_code

	var spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(shader_source)

	print("PlanetAtmosphere: manual compile error: ", spirv.compile_error_compute)
	print("PlanetAtmosphere: manual bytecode size: ", spirv.bytecode_compute.size())

	if spirv.compile_error_compute != "":
		push_error("PlanetAtmosphere shader compile error:\n%s" % spirv.compile_error_compute)
		return null

	if spirv.bytecode_compute.is_empty():
		push_error("PlanetAtmosphere: shader compiled but compute bytecode is empty.")
		return null

	return spirv

func _initialize_compute() -> void:
	print("PlanetAtmosphere: _initialize_compute()")

	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("PlanetAtmosphere: RenderingDevice no disponible. ¿Renderer Compatibility activo?")
		return

	var shader_spirv := _load_compute_spirv()
	if shader_spirv == null:
		push_error("PlanetAtmosphere: no shader SPIR-V.")
		return

	if shader_spirv.compile_error_compute != "":
		push_error("PlanetAtmosphere shader compile error:\n%s" % shader_spirv.compile_error_compute)
		return

	if shader_spirv.bytecode_compute.is_empty():
		push_error("PlanetAtmosphere: compute bytecode vacío.")
		return

	shader = rd.shader_create_from_spirv(shader_spirv)
	print("PlanetAtmosphere: shader RID valid: ", shader.is_valid())

	if not shader.is_valid():
		push_error("PlanetAtmosphere: shader RID inválido.")
		return

	pipeline = rd.compute_pipeline_create(shader)
	print("PlanetAtmosphere: pipeline RID valid: ", pipeline.is_valid())

	if not pipeline.is_valid():
		push_error("PlanetAtmosphere: pipeline RID inválido.")
		return

	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	depth_sampler = rd.sampler_create(sampler_state)

	print("PlanetAtmosphere: compute initialized OK.")


func _free_compute() -> void:
	if rd == null:
		return

	for buffer in params_buffers:
		if buffer.is_valid():
			rd.free_rid(buffer)
	params_buffers.clear()

	if depth_sampler.is_valid():
		rd.free_rid(depth_sampler)
	depth_sampler = RID()

	if shader.is_valid():
		rd.free_rid(shader)
	shader = RID()
	pipeline = RID()


func _render_callback(p_effect_callback_type: EffectCallbackType, p_render_data: RenderData) -> void:
	if not enabled:
		return

	if p_effect_callback_type != effect_callback_type:
		return

	if rd == null or not pipeline.is_valid() or not shader.is_valid():
		return

	var render_scene_buffers := p_render_data.get_render_scene_buffers()
	if render_scene_buffers == null:
		return

	var scene_data := p_render_data.get_render_scene_data()
	if scene_data == null:
		return

	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return

	var view_count: int = render_scene_buffers.get_view_count()
	_ensure_params_buffers(view_count)

	@warning_ignore("integer_division")
	var x_groups: int = (size.x - 1) / LOCAL_SIZE + 1
	@warning_ignore("integer_division")
	var y_groups: int = (size.y - 1) / LOCAL_SIZE + 1

	for view in view_count:
		var projection: Projection = scene_data.get_view_projection(view)

		if projection.is_orthogonal():
			continue

		var color_image: RID = render_scene_buffers.get_color_layer(view, false)
		var depth_image: RID = render_scene_buffers.get_depth_layer(view, false)

		if not color_image.is_valid() or not depth_image.is_valid():
			continue

		var params_bytes := _build_params_bytes(size, scene_data, projection, view)
		rd.buffer_update(params_buffers[view], 0, params_bytes.size(), params_bytes)

		var color_uniform := RDUniform.new()
		color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		color_uniform.binding = 0
		color_uniform.add_id(color_image)

		var depth_uniform := RDUniform.new()
		depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		depth_uniform.binding = 1
		depth_uniform.add_id(depth_sampler)
		depth_uniform.add_id(depth_image)

		var params_uniform := RDUniform.new()
		params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		params_uniform.binding = 2
		params_uniform.add_id(params_buffers[view])

		_params_mutex.lock()
		var occ_on := _occ_enabled
		var occ_tex_ref := _occ_texture
		_params_mutex.unlock()
		var occ_rd_tex: RID = depth_image
		if occ_on and occ_tex_ref != null:
			var rid := RenderingServer.texture_get_rd_texture(occ_tex_ref.get_rid())
			if rid.is_valid():
				occ_rd_tex = rid

		var occ_uniform := RDUniform.new()
		occ_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		occ_uniform.binding = 3
		occ_uniform.add_id(depth_sampler)
		occ_uniform.add_id(occ_rd_tex)

		var uniform_set := UniformSetCacheRD.get_cache(
			shader,
			0,
			[color_uniform, depth_uniform, params_uniform, occ_uniform]
		)

		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()


func _ensure_params_buffers(count: int) -> void:
	var zero_bytes := _zero_params_bytes()

	while params_buffers.size() < count:
		var buffer := rd.storage_buffer_create(zero_bytes.size(), zero_bytes)
		params_buffers.append(buffer)


func _zero_params_bytes() -> PackedByteArray:
	var floats := PackedFloat32Array()
	floats.resize(PARAM_VEC4_COUNT * 4)
	return floats.to_byte_array()


func _build_params_bytes(
	size: Vector2i,
	scene_data,
	projection: Projection,
	view: int
) -> PackedByteArray:
	var cam_transform: Transform3D = scene_data.get_cam_transform()
	var cam_origin: Vector3 = cam_transform.origin

	if scene_data.get_view_count() > 1:
		cam_origin += cam_transform.basis * scene_data.get_view_eye_offset(view)

	var inv_projection: Projection = projection.inverse()

	_params_mutex.lock()
	var local_center := planet_center
	var local_planet_radius : float = max(planet_radius, 0.001)
	var local_atmo_radius   : float = max(atmosphere_radius, local_planet_radius + 0.001)
	var local_sun_dir       := sun_direction.normalized()
	var local_water_radius  := water_radius
	var local_wavelengths   := wavelengths
	var local_density       := density_falloff
	var local_scattering    := scattering_strength / 10000.0
	var local_sun_intensity   := sun_intensity
	var local_clouds_enabled  := clouds_enabled
	var local_cloud_min_h     := cloud_min_height
	var local_cloud_max_h     := cloud_max_height
	var local_cloud_density   := cloud_density
	var local_cloud_coverage  := cloud_coverage
	var local_cloud_absorb    := cloud_absorption
	var local_cloud_g         := cloud_g
	var local_cloud_nscale    := cloud_noise_scale
	var local_wind_direction  := cloud_wind_direction
	var local_wind_speed      := cloud_wind_speed
	var local_cloud_shadow    := cloud_shadow_strength
	var local_cloud_albedo    := cloud_albedo
	var local_atmo_scatter    := atmosphere_scatter
	var local_lightning_flash := lightning_flash
	var local_cloud_steps     := cloud_steps
	var local_light_steps     := cloud_light_steps
	var local_shadow_steps    := cloud_shadow_steps
	var local_fog_enabled     := fog_enabled
	var local_fog_density     := fog_density
	var local_fog_coverage    := fog_coverage
	var local_fog_floor_h     := fog_floor_height
	var local_fog_top_h       := maxf(fog_top_height, fog_floor_height + 1.0)
	var local_fog_color       := fog_color
	var local_fog_wind_speed  := fog_wind_speed
	var local_fog_nscale      := fog_noise_scale
	var local_fog_steps       := fog_steps
	var local_fog_view_dist   := fog_view_distance
	var local_occ_soft        := fog_occlusion_softness
	var local_occ_enabled     := _occ_enabled
	var local_occ_center      := _occ_center
	var local_occ_x           := _occ_x
	var local_occ_z           := _occ_z
	var local_occ_up          := _occ_up
	var local_occ_half        := _occ_half_size
	var local_occ_span        := _occ_span
	var local_occ_below       := _occ_below
	var local_occ_margin      := _occ_margin
	_params_mutex.unlock()

	var floats := PackedFloat32Array()

	# 0: render size + radii.
	_append_vec4(floats, Vector4(size.x, size.y, local_planet_radius, local_atmo_radius))

	# 1-4: inverse projection.
	_append_vec4(floats, inv_projection.x)
	_append_vec4(floats, inv_projection.y)
	_append_vec4(floats, inv_projection.z)
	_append_vec4(floats, inv_projection.w)

	# 5-7: basis cámara (view -> world) + parámetros de scattering.
	_append_vec4(floats, Vector4(
		cam_transform.basis.x.x, cam_transform.basis.x.y, cam_transform.basis.x.z,
		local_density
	))
	_append_vec4(floats, Vector4(
		cam_transform.basis.y.x, cam_transform.basis.y.y, cam_transform.basis.y.z,
		local_scattering
	))
	_append_vec4(floats, Vector4(
		cam_transform.basis.z.x, cam_transform.basis.z.y, cam_transform.basis.z.z,
		local_sun_intensity
	))

	# 8: origen cámara relativo (siempre 0,0,0) + intensidad de sombra de nubes (w).
	_append_vec4(floats, Vector4(0.0, 0.0, 0.0, local_cloud_shadow))

	# 9: centro del planeta relativo a cámara (.xyz) + destello de rayo (.w, lightning_flash).
	var rel_center := local_center - cam_origin
	_append_vec4(floats, Vector4(rel_center.x, rel_center.y, rel_center.z, local_lightning_flash))

	# 10: dirección del sol (.xyz) + radio de la esfera de agua (.w, 0 = sin océano).
	_append_vec4(floats, Vector4(local_sun_dir.x, local_sun_dir.y, local_sun_dir.z, local_water_radius))

	# 11: wavelengths (nm) + enabled.
	_append_vec4(floats, Vector4(
		local_wavelengths.x, local_wavelengths.y, local_wavelengths.z, 1.0
	))

	# 12: capa de nubes — alturas sobre la superficie, densidad, cobertura.
	_append_vec4(floats, Vector4(
		local_cloud_min_h, local_cloud_max_h, local_cloud_density, local_cloud_coverage
	))

	# 13: absorción, factor g de Henyey-Greenstein, escala de ruido, habilitado.
	_append_vec4(floats, Vector4(
		local_cloud_absorb, local_cloud_g, local_cloud_nscale,
		1.0 if local_clouds_enabled else 0.0
	))

	# 14: viento — dirección (xyz normalizada) + offset acumulado (tiempo × velocidad).
	var wind_dir_n := local_wind_direction.normalized() if local_wind_direction.length_squared() > 0.0001 else Vector3.ZERO
	var wind_offset := (Time.get_ticks_msec() / 1000.0) * local_wind_speed
	_append_vec4(floats, Vector4(wind_dir_n.x, wind_dir_n.y, wind_dir_n.z, wind_offset))

	# 15: pasos de marcha de nubes — view (x), light (y), shadow (z).
	_append_vec4(floats, Vector4(local_cloud_steps, local_light_steps, local_shadow_steps, 0.0))

	# 16: niebla — suelo/techo sobre la superficie (m), densidad, cobertura.
	_append_vec4(floats, Vector4(
		local_fog_floor_h, local_fog_top_h, local_fog_density, local_fog_coverage
	))

	# 17: color de la niebla + habilitada.
	_append_vec4(floats, Vector4(
		local_fog_color.r, local_fog_color.g, local_fog_color.b,
		1.0 if local_fog_enabled else 0.0
	))

	# 18: niebla — escala de ruido (x), offset de viento acumulado (y), pasos de marcha (z),
	# distancia de visibilidad (w; 0 = sin límite). Reutiliza la dirección de viento de las nubes
	# P(14).xyz para que el banco viaje con él.
	var fog_wind_offset := (Time.get_ticks_msec() / 1000.0) * local_fog_wind_speed
	_append_vec4(floats, Vector4(local_fog_nscale, fog_wind_offset, local_fog_steps, local_fog_view_dist))

	# 19-23: oclusión de niebla en cuevas (rejilla del WeatherOcclusionField). El centro va
	# relativo a la cámara (como el del planeta); los ejes son direcciones (sin trasladar).
	var occ_rel_center := local_occ_center - cam_origin
	_append_vec4(floats, Vector4(
		occ_rel_center.x, occ_rel_center.y, occ_rel_center.z,
		1.0 if local_occ_enabled else 0.0
	))
	_append_vec4(floats, Vector4(local_occ_x.x, local_occ_x.y, local_occ_x.z, local_occ_half))
	_append_vec4(floats, Vector4(local_occ_z.x, local_occ_z.y, local_occ_z.z, local_occ_span))
	_append_vec4(floats, Vector4(local_occ_up.x, local_occ_up.y, local_occ_up.z, local_occ_below))
	# P(23): .x=margen oclusión, .y=suavizado oclusión, .z=albedo de nube, .w=multiplicador in-scatter.
	_append_vec4(floats, Vector4(local_occ_margin, local_occ_soft, local_cloud_albedo, local_atmo_scatter))

	return floats.to_byte_array()


func _append_vec4(array: PackedFloat32Array, value: Vector4) -> void:
	array.push_back(value.x)
	array.push_back(value.y)
	array.push_back(value.z)
	array.push_back(value.w)
