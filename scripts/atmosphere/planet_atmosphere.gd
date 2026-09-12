@tool
extends CompositorEffect
class_name PlanetAtmosphere

const DEFAULT_SHADER_PATH := "res://shaders/atmosphere/planet_atmosphere.glsl"
const NOISE_GEN_SHADER_PATH := "res://shaders/atmosphere/cloud_noise_gen.glsl"
## Segundo pase (god rays screen-space). Comparte el UBO de params de este efecto.
const GOD_RAYS_SHADER_PATH := "res://shaders/atmosphere/god_rays.glsl"
const LOCAL_SIZE := 8
const PARAM_VEC4_COUNT := 33
## Lado de la textura 3D de ruido de nubes (RGBA8 → size³ × 4 bytes; 128 ≈ 8.4 MB de VRAM).
const NOISE_TEX_SIZE := 128
## local_size del generador de ruido (4×4×4, ver cloud_noise_gen.glsl).
const NOISE_GEN_LOCAL_SIZE := 4
## Mapa lat-long de agrupación planetaria de nubes (RG8 → 64 KB; R = cobertura, G = densidad).
## Envuelve el planeta una sola vez: sin repetición de patrón desde el espacio. 2:1 = proporción
## equirectangular.
const GROUP_TEX_W := 256
const GROUP_TEX_H := 128

@export var shader_file_path: String = DEFAULT_SHADER_PATH

@export_group("Planet")
@export var planet_center: Vector3 = Vector3.ZERO
@export var planet_radius: float = 1000.0
@export var atmosphere_radius: float = 1080.0

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
## Frecuencia del DETALLE de la nube (bordes, coliflor). Sube = borde más fino y picado.
@export_range(1.0, 600.0, 0.1) var cloud_noise_scale: float = 5
## Tamaño de la masa de nube, como fracción de cloud_noise_scale: 0.1 = nubes ~10× más grandes
## que el detalle que las erosiona, 1.0 = masa y detalle a la misma escala (todas del tamaño del
## noise scale, que era el comportamiento anterior). Es el parámetro para tener nubes GRANDES sin
## perder granularidad: baja esto en vez de bajar cloud_noise_scale.
@export_range(0.05, 0.95, 0.01) var cloud_shape_ratio: float = 0.2
## Cuánto varía el TAMAÑO de nube entre regiones del planeta: 0 = todas del mismo tamaño,
## 1 = de borregos sueltos a masas enormes según la zona. Reparte amplitud entre la banda de
## forma y la de detalle, así que no altera la cobertura ni cuesta un tap más.
@export_range(0.0, 1.0, 0.01) var cloud_size_variation: float = 0.6
@export var cloud_wind_direction: Vector3 = Vector3(1.0, 0.0, 0.0)
@export_range(0.0, 1.0, 0.005) var cloud_wind_speed: float = 0.05
## Cuánto oscurecen las nubes el terreno bajo ellas (0 = sin sombra, 1 = máxima).
@export_range(0.0, 1.0, 0.01) var cloud_shadow_strength: float = 0.85
## Albedo de las nubes: 1 = blanco pleno, valores bajos = gris de tormenta. Lo fija el WeatherController.
@export_range(0.0, 1.0, 0.01) var cloud_albedo: float = 1.0
@export_range(0.01, 0.5, 0.01) var cloud_edge_softness: float = 0.08

## Desviación típica del campo de ruido de nubes. Calibra el mapeo cobertura → umbral: con el
## valor correcto, cloud_coverage 0.95 cubre ~95% del cielo. Si la tormenta no cierra, SUBE esto;
## si el cielo despejado sale demasiado nublado, bájalo. El error casi no se nota en coberturas
## medias y es máximo en los extremos, así que calíbralo mirando una tormenta, no un cielo raso.
@export_range(0.1, 0.8, 0.005) var cloud_field_sigma: float = 0.455
## Agrupación planetaria: 0 = cobertura uniforme en todo el planeta (comportamiento clásico),
## 1 = las nubes solo existen dentro de las celdas del mapa de agrupación (cielo despejado entre ellas).
@export_range(0.0, 10.0, 0.01) var cloud_group_strength: float = 0.0
## Nº aproximado de celdas de agrupación alrededor del planeta. Cambiarlo regenera el mapa.
@export_range(1.0, 120.0, 0.1) var cloud_group_scale: float = 3.0:
	set(v):
		cloud_group_scale = v
		_group_dirty = true
## Contraste del borde de las celdas: 0 = transición larga y gradual entre celda y claro (cielos
## que se van cerrando poco a poco), 1 = frontera casi binaria. Cambiarlo regenera el mapa.
@export_range(0.0, 1.0, 0.01) var cloud_group_contrast: float = 0.6:
	set(v):
		cloud_group_contrast = v
		_group_dirty = true
## Cuánto mandan los frentes de gran escala sobre las celdas: 0 = celdas sueltas todas iguales,
## 1 = regiones enteras del planeta cuajadas de celdas frente a regiones casi vacías. Cambiarlo
## regenera el mapa.
@export_range(0.0, 1.0, 0.01) var cloud_group_front_strength: float = 0.5:
	set(v):
		cloud_group_front_strength = v
		_group_dirty = true
## Variación de DENSIDAD entre cúmulos: 0 = todos igual de gruesos, 1 = van de casi transparentes
## al doble de densos. Es un ruido independiente de la cobertura, así que una zona muy nublada no
## es automáticamente una zona de nubes densas. Se escala por cloud_group_strength.
@export_range(0.0, 1.0, 0.01) var cloud_group_density_variation: float = 0.45

@export_group("Atmosphere")
## Multiplicador del in-scatter de Rayleigh (velo azul de perspectiva aérea). 1 = dispersión plena;
## valores bajos apagan el azul hacia un horizonte plomizo. El WeatherController lo fija por evento.
@export_range(0.0, 1.0, 0.01) var atmosphere_scatter: float = 1.0
## Destello de rayo (0..1) que el WeatherController empuja durante un relámpago: ilumina la base de
## las nubes como emisión breve (el compute no ve la luz auxiliar de escena). 0 = sin destello.
@export_range(0.0, 1.0, 0.01) var lightning_flash: float = 0.0

@export_group("Night")
## Efecto Purkinje: en penumbra la visión humana (bastones) pierde saturación y vira a azul.
## Fuerza del viraje cuando el observador está en plena noche. 0 = desactivado.
@export_range(0.0, 1.0, 0.01) var purkinje_strength: float = 0.65
## Tinte escotópico hacia el que deriva la escena nocturna (azul lunar).
@export var purkinje_tint: Color = Color(0.45, 0.6, 1.0)

@export_group("Fog")
## Niebla a ras de suelo: capa volumétrica baja, independiente de las nubes. Su densidad
## la modula un ruido de gran escala advectado por el viento → el banco "llega de lejos".
@export var fog_enabled: bool = true
## Densidad global de la niebla. 0 = sin niebla. El WeatherController la sube/baja en las
## transiciones, así la niebla se desvanece en su sitio (no baja del cielo).
@export_range(0.0, 5.0, 0.05) var fog_density: float = 0.0
## Cobertura del banco: cuánta área cubre el frente (0 = parches sueltos, 1 = manto denso).
@export_range(0.0, 1.0, 0.01) var fog_coverage: float = 0.6
## Cuánto confina la niebla a la celda de agrupación de nubes: 0 = manto global (niebla de valle),
## 1 = solo cuaja bajo las nubes (bruma de tormenta). Se multiplica por cloud_group_strength.
@export_range(0.0, 1.0, 0.01) var fog_group_strength: float = 0.0
## Altura del suelo de la niebla sobre la superficie (m). Suele ser 0 = a ras.
@export_range(-50.0, 500.0, 1.0) var fog_floor_height: float = 0.0
## Altura del techo de la niebla sobre la superficie (m). Espesor = techo - suelo.
@export_range(10.0, 800.0, 1.0) var fog_top_height: float = 130.0
## Tinte de la niebla (se ilumina con el sol; más cálido en el terminador).
@export var fog_color: Color = Color(0.82, 0.84, 0.88)
## Brillo de la niebla en el lado nocturno (resplandor del cielo). 0 = se apaga del todo con el
## sol bajo el horizonte. Es luminancia ABSOLUTA, independiente de sun_intensity, así que subirla
## poco a poco es seguro: de día la niebla anda por ~2.6, valores sobre ~0.15 ya se leen lechosos.
@export_range(0.0, 0.3, 0.005) var fog_night_ambient: float = 0.03
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

@export_group("God Rays")
## Shafts de luz screen-space (Mitchell): por cada píxel se marcha hacia el sol en pantalla
## acumulando cuánto del trayecto es cielo abierto. Segundo pase de compute, después de las nubes.
@export var god_rays_enabled: bool = true
## Fracción de sun_intensity que alcanza un píxel con el camino al sol totalmente despejado.
## Los rayos escalan con el sol, así que subir sun_intensity no obliga a re-tunear esto.
@export_range(0.0, 0.5, 0.001) var god_rays_exposure: float = 0.05
## Tinte de los shafts. Cálido por defecto (la luz que rasa la atmósfera se enrojece).
@export var god_rays_tint: Color = Color(1.0, 0.92, 0.78)
## Ángulo (grados) entre el eje de cámara y el sol al que los shafts se apagan del todo. El techo
## son 89°: a 90° el sol cruza el plano de cámara y deja de tener proyección en pantalla.
@export_range(10.0, 89.0, 1.0) var god_rays_max_angle: float = 85.0
## Forma de ese fundido. 1 = casi igual de fuertes de lado que de frente, 3 = concentrado
## alrededor del sol. Es el mando para "se ven poco salvo mirando al sol".
@export_range(0.2, 5.0, 0.05) var god_rays_angle_falloff: float = 1.2
## Longitud del trayecto marchado, como fracción de la distancia al sol en pantalla: 1 = hasta el
## sol (rayos largos), 0.5 = medio camino. Bajar acorta los rayos y junta las muestras.
@export_range(0.1, 1.0, 0.01) var god_rays_density: float = 0.85
## Tope absoluto de esa longitud, en fracción de pantalla: mantiene las muestras juntas cuando el
## sol se va lejos del encuadre. Subirlo alarga los rayos, y hay que compensar con más samples.
@export_range(0.1, 2.0, 0.05) var god_rays_max_length: float = 0.6
## Atenuación por paso. Más bajo = rayos que se apagan rápido cerca del sol; cerca de 1 = shafts
## largos que cruzan la pantalla. No afecta al brillo de pico (la acumulación va normalizada).
@export_range(0.5, 1.0, 0.005) var god_rays_decay: float = 0.96
## Muestras por píxel. Cada una es un tap a la máscara: es el único coste real del efecto.
## Por debajo de ~32 aparecen bandas radiales en las siluetas grandes.
@export_range(4, 128, 1) var god_rays_samples: int = 48
## Ancho del desparramo de las muestras a lo ancho del rayo, en fracción de pantalla. Difumina el
## borde de los shafts y crece con la distancia recorrida (penumbra). 0 = bordes de sierra.
@export_range(0.0, 0.05, 0.001) var god_rays_blur: float = 0.006
## Cuánto varía el brillo de un haz a otro. 0 = abanico plano y muerto.
@export_range(0.0, 1.0, 0.01) var god_rays_shimmer: float = 0.35
## Tamaño del patrón de haces EN METROS: el ruido está anclado al mundo y hace paralaje al
## desplazarte. Bajo = muchos haces finos.
@export_range(2.0, 400.0, 1.0) var god_rays_shimmer_size: float = 60.0
## Velocidad a la que deriva ese patrón. Muy bajo a propósito: por encima de ~0.3 se lee como
## interferencia en vez de como aire en movimiento.
@export_range(0.0, 1.0, 0.005) var god_rays_shimmer_speed: float = 0.05
## Ondulación de los haces, en radianes. Los curva como aire caliente; sobre ~0.06 empiezan a
## despegarse de su oclusor.
@export_range(0.0, 0.15, 0.001) var god_rays_wobble: float = 0.02
## Distancia (m) en la que el aire acumula el grueso de la dispersión: a esta distancia un píxel
## recibe el 63% del shaft y a un cuarto de ella, el 22%. Es lo que hace que los rayos se lean
## como haces en el espacio y no como una calca. También ancla la profundidad del shimmer.
@export_range(5.0, 2000.0, 5.0) var god_rays_scatter_distance: float = 150.0
## Distancia (m) a la que un oclusor pasa a bloquear del todo. Lo muy cercano se descuenta porque
## solo ensombrece el aire que tiene detrás, no la columna entera: es el mando contra los abanicos
## de sombra que salen de la borda o del marco de una escotilla.
@export_range(1.0, 300.0, 1.0) var god_rays_occluder_distance: float = 20.0
## Fracción de pantalla en la que se apagan las muestras que caen fuera del encuadre (leen el píxel
## del borde y lo convertirían en una raya dura). Bajarlo mata la raya y acorta los rayos.
@export_range(0.01, 1.0, 0.01) var god_rays_edge_fade: float = 0.15
## 0 = normal, 1 = máscara de oclusión cruda (incluye nubes) + cruz en la posición proyectada del
## sol (verde = activo, rojo = gateado), 2 = solo los rayos sobre negro, 3 = solo la atenuación
## por distancia (negro = primer plano, blanco = cielo).
@export_enum("Off:0", "Occlusion mask:1", "Rays only:2", "Depth falloff:3") var god_rays_debug: int = 0

## Escalas por evento climático que empuja el WeatherController. Sin exportar a propósito: así el
## inspector sigue siendo la referencia y un guardado del .tres no puede pisar el tuning.
var god_rays_weather_strength: float = 1.0
var god_rays_weather_reach: float = 1.0

var underwater_pass := UnderwaterRenderPass.new()

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var depth_sampler: RID
var params_buffers: Array[RID] = []

var noise_tex: RID
var noise_sampler: RID
var _noise_gen_shader: RID
var _noise_gen_pipeline: RID

var _god_rays_shader: RID
var _god_rays_pipeline: RID
## Máscara de oclusión (R8) que escribe el pase de atmósfera y lee el de god rays. Una por vista,
## recreadas al cambiar el tamaño interno del render.
var _mask_textures: Array[RID] = []
var _mask_size := Vector2i.ZERO
var _mask_sampler: RID

var group_tex: RID
var group_sampler: RID
## Copia CPU del mapa de agrupación: la consulta el weather system (get_cloud_group_envelope)
## sin readback de GPU. Es EXACTAMENTE lo que muestrea el shader (misma Image que se sube).
var _group_image: Image = null
var _group_dirty := false

var _params_mutex := Mutex.new()

var _occ_enabled: bool = false
var _occ_center: Vector3 = Vector3.ZERO
var _occ_x: Vector3 = Vector3.RIGHT
var _occ_z: Vector3 = Vector3.BACK
var _occ_up: Vector3 = Vector3.UP
var _occ_half_size: float = 50.0
var _occ_span: float = 140.0
var _occ_below: float = 60.0
# Franja extra sin niebla por encima del techo. En 0: el campo sondea de arriba abajo, así que la
# altura que llega ya es la cara superior de la roca. Subirlo abre agujeros de niebla sobre el suelo.
var _occ_margin: float = 0.0
var _occ_texture: Texture2D = null


func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT

	access_resolved_color = true
	access_resolved_depth = true

	rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(_initialize_compute)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd != null:
		# At refcount zero calling another instance method is invalid. Capture only
		# owned resources and release them on the render thread through a static helper.
		var resources: Array[RID] = []
		resources.append_array(params_buffers)
		resources.append_array(_mask_textures)
		resources.append_array([depth_sampler, noise_sampler, noise_tex, group_sampler,
			group_tex, _noise_gen_shader, _god_rays_shader, _mask_sampler, shader])
		RenderingServer.call_on_render_thread(
			UnderwaterRenderPass.release_owned_resources.bind(rd, underwater_pass, resources))


func set_planet_data(
	p_center: Vector3,
	p_planet_radius: float,
	p_atmosphere_radius: float,
	p_sun_direction: Vector3
) -> void:
	_params_mutex.lock()

	planet_center = p_center
	planet_radius = max(p_planet_radius, 0.001)
	atmosphere_radius = max(p_atmosphere_radius, planet_radius + 0.001)

	if p_sun_direction.length_squared() > 0.000001:
		sun_direction = p_sun_direction.normalized()

	_params_mutex.unlock()


## La empuja el WeatherController por evento: aire con más vapor o polvo dispersa más (shafts más
## marcados) y a menos distancia (shafts que ya se ven en el primer plano, como en la niebla).
func set_god_ray_weather(strength: float, reach: float) -> void:
	_params_mutex.lock()
	god_rays_weather_strength = maxf(strength, 0.0)
	god_rays_weather_reach = maxf(reach, 0.01)
	_params_mutex.unlock()


## La empuja el WeatherController con el estado del WeatherOcclusionField; enabled=false rellena niebla en todas partes.
func set_fog_occlusion(
	enabled: bool,
	center: Vector3, x_axis: Vector3, z_axis: Vector3, up: Vector3,
	half_size: float, span: float, below: float,
	height_tex: Texture2D, margin: float = 0.0
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


func _load_compute_spirv(path: String) -> RDShaderSPIRV:
	print("PlanetAtmosphere: loading shader from: ", path)

	# El importador de RDShaderFile NO rastrea las dependencias #include: editar un
	# .glslinc no marca sucio al .glsl que lo incluye, así que el juego sigue corriendo el
	# SPIR-V viejo sin avisar de nada. Eso hace que un cambio de shader parezca no existir
	# mientras los cambios de GDScript sí se ven, que es imposible de depurar a ciegas.
	# Corriendo desde el editor se compila del texto, que relee los includes del disco.
	# En un export NO se puede: las plantillas de release no llevan glslang, así que allí
	# manda el recurso importado, que además está garantizado al día por la exportación.
	var resource: Resource = null
	if not OS.has_feature("editor"):
		resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	else:
		print("PlanetAtmosphere: editor run, compiling from source to pick up #include edits.")

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

	var shader_code := FileAccess.get_file_as_string(path)

	if shader_code.is_empty():
		push_error("PlanetAtmosphere: shader file is empty or could not be read: %s" % path)
		return null

	shader_code = shader_code.replace("#[compute]", "")
	shader_code = shader_code.replace('#include "../liquid/underwater_optics.glslinc"', FileAccess.get_file_as_string("res://shaders/liquid/underwater_optics.glslinc"))
	shader_code = shader_code.replace('#include "../liquid/underwater_params.glslinc"', FileAccess.get_file_as_string("res://shaders/liquid/underwater_params.glslinc"))

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

	var shader_spirv := _load_compute_spirv(shader_file_path)
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

	var noise_state := RDSamplerState.new()
	noise_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	noise_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	noise_state.mip_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	noise_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	noise_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	noise_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	noise_sampler = rd.sampler_create(noise_state)

	# Mapa de agrupación: REPEAT en u (la costura de longitud es continua por construcción)
	# pero CLAMP en v (los polos no deben mezclarse entre sí al filtrar).
	var group_state := RDSamplerState.new()
	group_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	group_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	group_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	group_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	group_sampler = rd.sampler_create(group_state)

	# Máscara de oclusión: LINEAR para que el filtrado bilineal suavice el rayo gratis, y CLAMP
	# para que los taps que se salen de pantalla (sol fuera del encuadre) repitan el borde.
	var mask_state := RDSamplerState.new()
	mask_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	mask_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	mask_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	mask_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_mask_sampler = rd.sampler_create(mask_state)

	_generate_cloud_noise()
	_create_group_texture()
	_initialize_god_rays()

	print("PlanetAtmosphere: compute initialized OK.")


## Segundo pase de god rays. Su fallo NO tumba el efecto: el pipeline queda inválido y
## _render_callback se salta el dispatch, así que la atmósfera sigue funcionando sin shafts.
func _initialize_god_rays() -> void:
	var spirv := _load_compute_spirv(GOD_RAYS_SHADER_PATH)
	if spirv == null or spirv.compile_error_compute != "" or spirv.bytecode_compute.is_empty():
		push_error("PlanetAtmosphere: god rays deshabilitados (shader no compiló).")
		return

	_god_rays_shader = rd.shader_create_from_spirv(spirv)
	if not _god_rays_shader.is_valid():
		push_error("PlanetAtmosphere: shader de god rays inválido.")
		return

	_god_rays_pipeline = rd.compute_pipeline_create(_god_rays_shader)
	if not _god_rays_pipeline.is_valid():
		push_error("PlanetAtmosphere: pipeline de god rays inválido.")


## Máscara de oclusión, una por vista, al tamaño interno del render. La necesita SIEMPRE el pase
## de atmósfera (declara el binding 6 incondicionalmente), no solo los god rays. Devuelve false si
## no se pudo crear, y entonces no hay dispatch que valga.
func _ensure_masks(size: Vector2i, view_count: int) -> bool:
	if _mask_size == size and _mask_textures.size() >= view_count:
		return true

	for tex in _mask_textures:
		if tex.is_valid():
			rd.free_rid(tex)
	_mask_textures.clear()
	_mask_size = Vector2i.ZERO

	var format := RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	format.width = size.x
	format.height = size.y
	format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	)

	if not rd.texture_is_format_supported_for_usage(format.format, format.usage_bits):
		push_error("PlanetAtmosphere: R8_UNORM no soporta storage+sampling en esta GPU.")
		return false

	var view := RDTextureView.new()
	for i in view_count:
		var tex := rd.texture_create(format, view, [])
		if not tex.is_valid():
			push_error("PlanetAtmosphere: no se pudo crear la máscara de oclusión.")
			return false
		_mask_textures.append(tex)

	_mask_size = size
	return true


## Genera la textura 3D de ruido de nubes en GPU, una sola vez. Si algo falla, noise_tex
## queda inválido y _render_callback no despacha (el efecto entero se apaga con error).
func _generate_cloud_noise() -> void:
	var spirv := _load_compute_spirv(NOISE_GEN_SHADER_PATH)
	if spirv == null:
		push_error("PlanetAtmosphere: no se pudo cargar el generador de ruido de nubes.")
		return

	_noise_gen_shader = rd.shader_create_from_spirv(spirv)
	if not _noise_gen_shader.is_valid():
		push_error("PlanetAtmosphere: shader del generador de ruido inválido.")
		return

	_noise_gen_pipeline = rd.compute_pipeline_create(_noise_gen_shader)
	if not _noise_gen_pipeline.is_valid():
		push_error("PlanetAtmosphere: pipeline del generador de ruido inválido.")
		return

	var fmt := RDTextureFormat.new()
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.width = NOISE_TEX_SIZE
	fmt.height = NOISE_TEX_SIZE
	fmt.depth = NOISE_TEX_SIZE
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	noise_tex = rd.texture_create(fmt, RDTextureView.new())
	if not noise_tex.is_valid():
		push_error("PlanetAtmosphere: no se pudo crear la textura 3D de ruido.")
		return

	var img_uniform := RDUniform.new()
	img_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	img_uniform.binding = 0
	img_uniform.add_id(noise_tex)
	var gen_set := rd.uniform_set_create([img_uniform], _noise_gen_shader, 0)

	@warning_ignore("integer_division")
	var groups: int = NOISE_TEX_SIZE / NOISE_GEN_LOCAL_SIZE
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, _noise_gen_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, gen_set, 0)
	rd.compute_list_dispatch(compute_list, groups, groups, groups)
	rd.compute_list_end()

	rd.free_rid(gen_set)
	print("PlanetAtmosphere: cloud noise 3D texture generated (%d³)." % NOISE_TEX_SIZE)


## Construye la Image lat-long de agrupación en CPU. Ruido FastNoiseLite muestreado SOBRE la
## esfera (dirección unitaria × escala) → sin costura en longitud. Domain warp + estiramiento
## zonal moldean las celdas como frentes curvos alargados este-oeste (sistemas meteorológicos)
## en vez de manchas redondas. Seed fija: las celdas son deterministas entre ejecuciones, así
## el weather system podrá confiar en sus posiciones. La curva S hornea el contraste (celda
## sólida / cielo despejado con borde suave); shader y CPU leen el valor ya moldeado.
## R = envolvente de cobertura, G = variación de densidad (ruido aparte, ver más abajo).
func _build_group_image() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.seed = 0
	# 1/TAU compensa la circunferencia (2π·radio): así cloud_group_scale = nº de longitudes
	# de onda (celdas grandes) alrededor del ecuador, tal como promete el export.
	noise.frequency = 1.0 / TAU
	# Domain warp: arremolina las celdas en frentes curvos. La longitud de onda de una celda
	# es TAU en unidades de entrada → amplitud 2.2 ≈ 1/3 de celda: retuerce la silueta sin
	# desintegrarla. Subir la amplitud = espirales más agresivas.
	noise.domain_warp_enabled = true
	noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	noise.domain_warp_amplitude = 2.2
	noise.domain_warp_frequency = 0.12
	noise.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	noise.domain_warp_fractal_octaves = 3
	var freq := maxf(cloud_group_scale, 0.1)
	# Estiramiento zonal: comprime las celdas en latitud → bandas alargadas este-oeste, como
	# los sistemas frontales reales. 1.0 = celdas isótropas (comportamiento antiguo).
	var lat_stretch := 1.8

	# Frente de gran escala: sesga el ruido de celda ANTES de la curva S, así que no borra
	# celdas — desplaza cuántas cuajan en cada región. Con una sola frecuencia todas las celdas
	# salían del mismo tamaño y repartidas por igual; con el frente hay zonas del planeta
	# cuajadas y zonas casi limpias, que es la jerarquía que se ve desde órbita.
	var front := FastNoiseLite.new()
	front.noise_type = FastNoiseLite.TYPE_SIMPLEX
	front.fractal_type = FastNoiseLite.FRACTAL_FBM
	front.fractal_octaves = 2
	front.seed = 1701
	front.frequency = 1.0 / TAU
	var front_freq := freq * 0.27
	var front_bias := clampf(cloud_group_front_strength, 0.0, 1.0) * 0.45

	# Densidad: ruido INDEPENDIENTE (otra seed, frecuencia entre celda y frente). Separarlo de la
	# cobertura es lo que hace que un cielo muy cubierto pueda ser de estratos finos y un claro
	# pueda tener un cúmulo aislado y espeso. La curva S es simétrica en 0.5 para no desplazar la
	# media: el multiplicador que reconstruye el shader queda centrado en 1.
	var dens := FastNoiseLite.new()
	dens.noise_type = FastNoiseLite.TYPE_SIMPLEX
	dens.fractal_type = FastNoiseLite.FRACTAL_FBM
	dens.fractal_octaves = 3
	dens.seed = 907
	dens.frequency = 1.0 / TAU
	var dens_freq := freq * 0.6

	# Semianchura de la curva S de cobertura. Contraste 0.6 reproduce el smoothstep(0.35, 0.65)
	# original; hacia 1 la frontera celda/claro se vuelve un corte, hacia 0 se disuelve en degradado.
	var edge := lerpf(0.32, 0.03, clampf(cloud_group_contrast, 0.0, 1.0))

	var img := Image.create_empty(GROUP_TEX_W, GROUP_TEX_H, false, Image.FORMAT_RG8)
	for y in GROUP_TEX_H:
		# Mapeo inverso EXACTO de latlong_uv() del shader: v = colatitud/PI, u = atan(z,x)/TAU + 0.5.
		var polar := (float(y) + 0.5) / float(GROUP_TEX_H) * PI
		var sp := sin(polar)
		var cp := cos(polar)
		for x in GROUP_TEX_W:
			var azimuth := ((float(x) + 0.5) / float(GROUP_TEX_W) - 0.5) * TAU
			var dir := Vector3(sp * cos(azimuth), cp * lat_stretch, sp * sin(azimuth))
			var n: float = noise.get_noise_3dv(dir * freq) * 0.5 + 0.5
			n += front.get_noise_3dv(dir * front_freq) * 0.5 * front_bias
			var env := smoothstep(0.5 - edge, 0.5 + edge, n)
			var d: float = dens.get_noise_3dv(dir * dens_freq) * 0.5 + 0.5
			img.set_pixel(x, y, Color(env, smoothstep(0.25, 0.75, d), 0.0))
	_group_image = img


func _create_group_texture() -> void:
	_build_group_image()

	var fmt := RDTextureFormat.new()
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8_UNORM
	fmt.width = GROUP_TEX_W
	fmt.height = GROUP_TEX_H
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	group_tex = rd.texture_create(fmt, RDTextureView.new(), [_group_image.get_data()])
	if not group_tex.is_valid():
		push_error("PlanetAtmosphere: no se pudo crear el mapa de agrupación de nubes.")


## Envolvente de agrupación (0..1) en una posición del mundo — el MISMO valor que ve el shader
## (misma Image, mismo mapeo lat-long), ya escalado por cloud_group_strength. Pensada para que
## el WeatherController decida dónde llueve, sin readback de GPU. 1 = zona de nubes plena.
func get_cloud_group_envelope(world_pos: Vector3) -> float:
	if _group_image == null:
		return 1.0
	var offset := world_pos - planet_center
	if offset.length_squared() < 0.000001:
		return 1.0
	var dir := offset.normalized()
	var u := atan2(dir.z, dir.x) / TAU + 0.5
	var v := acos(clampf(dir.y, -1.0, 1.0)) / PI
	var x := clampi(int(u * GROUP_TEX_W), 0, GROUP_TEX_W - 1)
	var y := clampi(int(v * GROUP_TEX_H), 0, GROUP_TEX_H - 1)
	return lerpf(1.0, _group_image.get_pixel(x, y).r, clampf(cloud_group_strength, 0.0, 1.0))


func _render_callback(p_effect_callback_type: EffectCallbackType, p_render_data: RenderData) -> void:
	if not enabled:
		return

	if p_effect_callback_type != effect_callback_type:
		return

	if rd == null or not pipeline.is_valid() or not shader.is_valid():
		return

	# Sin textura de ruido no hay uniform set completo: mejor no dibujar nada que crashear.
	if not noise_tex.is_valid() or not group_tex.is_valid():
		return

	# Regenera el mapa de agrupación si cambió cloud_group_scale (solo al tunear; ~32k
	# muestras de ruido en CPU, asumible en el hilo de render como evento puntual).
	if _group_dirty:
		_group_dirty = false
		_build_group_image()
		rd.texture_update(group_tex, 0, _group_image.get_data())

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

	# El pase de atmósfera declara la máscara de oclusión en el binding 6, así que sin ella no se
	# puede completar el uniform set y no hay nada que despachar.
	if not _ensure_masks(size, view_count):
		return

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

		var water_images := underwater_pass.prepare(rd, size, scene_data, projection, view, depth_image, color_image)
		if water_images.is_empty():
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
		params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
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

		var noise_uniform := RDUniform.new()
		noise_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		noise_uniform.binding = 4
		noise_uniform.add_id(noise_sampler)
		noise_uniform.add_id(noise_tex)

		var group_uniform := RDUniform.new()
		group_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		group_uniform.binding = 5
		group_uniform.add_id(group_sampler)
		group_uniform.add_id(group_tex)

		# Binding 6: la escribe este pase como writeonly image, la lee el siguiente filtrada.
		var mask_tex: RID = _mask_textures[view]

		var mask_image_uniform := RDUniform.new()
		mask_image_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		mask_image_uniform.binding = 6
		mask_image_uniform.add_id(mask_tex)

		var uniform_set := UniformSetCacheRD.get_cache(
			shader,
			0,
			[
				color_uniform, depth_uniform, params_uniform,
				occ_uniform, noise_uniform, group_uniform, mask_image_uniform
			]
		)

		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_bind_uniform_set(compute_list, underwater_pass.bind_optics(shader, water_images), 1)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()

		# Pase 2: god rays. En su PROPIA compute list para que la barrera implícita del
		# compute_list_end() de arriba garantice que la máscara ya está escrita.
		if god_rays_enabled and _god_rays_pipeline.is_valid():
			var mask_sampled_uniform := RDUniform.new()
			mask_sampled_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			mask_sampled_uniform.binding = 1
			mask_sampled_uniform.add_id(_mask_sampler)
			mask_sampled_uniform.add_id(mask_tex)

			# Binding 3: el depth, para la atenuación por distancia. El 1 lo ocupa la máscara.
			var rays_depth_uniform := RDUniform.new()
			rays_depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			rays_depth_uniform.binding = 3
			rays_depth_uniform.add_id(depth_sampler)
			rays_depth_uniform.add_id(depth_image)

			var rays_set := UniformSetCacheRD.get_cache(
				_god_rays_shader,
				0,
				[color_uniform, mask_sampled_uniform, params_uniform, rays_depth_uniform]
			)
			var rays_list := rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(rays_list, _god_rays_pipeline)
			rd.compute_list_bind_uniform_set(rays_list, rays_set, 0)
			rd.compute_list_bind_uniform_set(rays_list, underwater_pass.bind_optics(_god_rays_shader, water_images), 1)
			rd.compute_list_dispatch(rays_list, x_groups, y_groups, 1)
			rd.compute_list_end()



func _ensure_params_buffers(count: int) -> void:
	var zero_bytes := _zero_params_bytes()

	# Uniform buffer (no storage): lectura uniforme por todos los hilos → constant cache.
	# El shader declara vec4 data[N]; PARAM_VEC4_COUNT debe coincidir con esa N.
	while params_buffers.size() < count:
		var buffer := rd.uniform_buffer_create(zero_bytes.size(), zero_bytes)
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
	var local_shape_ratio     := cloud_shape_ratio
	var local_size_variation  := cloud_size_variation
	var local_wind_direction  := cloud_wind_direction
	var local_wind_speed      := cloud_wind_speed
	var local_cloud_shadow    := cloud_shadow_strength
	var local_cloud_albedo    := cloud_albedo
	var local_cloud_edge      := cloud_edge_softness
	var local_field_sigma     := cloud_field_sigma
	var local_group_strength  := cloud_group_strength
	var local_group_dens_var  := cloud_group_density_variation
	var local_atmo_scatter    := atmosphere_scatter
	var local_lightning_flash := lightning_flash
	var local_purkinje        := purkinje_strength
	var local_purkinje_tint   := purkinje_tint
	var local_cloud_steps     := cloud_steps
	var local_light_steps     := cloud_light_steps
	var local_shadow_steps    := cloud_shadow_steps
	var local_fog_enabled     := fog_enabled
	var local_fog_density     := fog_density
	var local_fog_coverage    := fog_coverage
	var local_fog_group       := fog_group_strength
	var local_fog_floor_h     := fog_floor_height
	var local_fog_top_h       := maxf(fog_top_height, fog_floor_height + 1.0)
	var local_fog_color       := fog_color
	var local_fog_night_amb   := fog_night_ambient
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
	var local_ray_strength    := god_rays_weather_strength
	var local_ray_reach       := god_rays_weather_reach
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

	# 10: dirección del sol (.xyz) + anchura del borde de nube (.w, cloud_edge_softness).
	_append_vec4(floats, Vector4(local_sun_dir.x, local_sun_dir.y, local_sun_dir.z, local_cloud_edge))

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

	# 15: pasos de marcha de nubes — view (x), light (y), shadow (z) + fuerza de agrupación (w).
	_append_vec4(floats, Vector4(local_cloud_steps, local_light_steps, local_shadow_steps, local_group_strength))

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

	# P(24): efecto Purkinje — tinte escotópico (.rgb) + fuerza (.w).
	_append_vec4(floats, Vector4(
		local_purkinje_tint.r, local_purkinje_tint.g, local_purkinje_tint.b, local_purkinje
	))

	# P(25): .x=sigma del campo de nubes, .y=agrupación de la niebla, .z=variación de densidad
	# entre cúmulos (canal G del mapa de agrupación), .w=fracción de noise_scale a la que va la
	# banda de forma (cloud_shape_ratio).
	_append_vec4(floats, Vector4(
		local_field_sigma, local_fog_group, local_group_dens_var, local_shape_ratio
	))

	# P(26): .x=variación de tamaño de nube entre regiones, .y=brillo nocturno de la niebla
	# (absoluto, sin escalar por sun_intensity). .zw libres.
	_append_vec4(floats, Vector4(local_size_variation, local_fog_night_amb, 0.0, 0.0))

	# P(27-32): god rays. Los consume god_rays.glsl salvo P(32).x, que lo aplica el shader de
	# atmósfera al escribir la máscara.
	# P(27): tinte (.rgb) + exposición (.w), escalada por el clima.
	_append_vec4(floats, Vector4(
		god_rays_tint.r, god_rays_tint.g, god_rays_tint.b,
		god_rays_exposure * local_ray_strength
	))

	# P(28): .x=densidad (fracción del trayecto al sol), .y=decay por paso, .z=nº de muestras,
	# .w=ancho del desparramo perpendicular (blur).
	_append_vec4(floats, Vector4(
		god_rays_density, god_rays_decay, god_rays_samples, god_rays_blur
	))

	# P(29): .xy=posición del sol en pantalla, .z=visibilidad [0,1], .w=habilitado.
	var sun_screen := _build_god_ray_sun(cam_transform, cam_origin, projection, local_sun_dir, local_center)
	_append_vec4(floats, Vector4(
		sun_screen.x, sun_screen.y, sun_screen.z, 1.0 if god_rays_enabled else 0.0
	))

	# P(30): .x=modo debug, .y=fuerza del shimmer, .z=frecuencia del patrón (ciclos por metro, de
	# ahí la inversa del tamaño), .w=deriva acumulada (tiempo × velocidad).
	var shimmer_offset := (Time.get_ticks_msec() / 1000.0) * god_rays_shimmer_speed
	_append_vec4(floats, Vector4(
		god_rays_debug, god_rays_shimmer,
		1.0 / maxf(god_rays_shimmer_size, 0.1), shimmer_offset
	))

	# P(31): .x=ondulación de los haces (radianes), .y=tope de longitud del trayecto,
	# .z=distancia de dispersión (m), acortada por el clima. .w libre.
	_append_vec4(floats, Vector4(
		god_rays_wobble, god_rays_max_length,
		god_rays_scatter_distance * local_ray_reach, 0.0
	))

	# P(32): .x=distancia de descuento de oclusores cercanos (m), .y=fundido de los taps fuera de
	# encuadre. .zw libres.
	_append_vec4(floats, Vector4(
		god_rays_occluder_distance, god_rays_edge_fade, 0.0, 0.0
	))

	return floats.to_byte_array()


## Proyecta el sol (direccional, a distancia infinita) a coordenadas de pantalla y devuelve
## (uv.x, uv.y, visibilidad). La visibilidad funde en un solo escalar los tres casos en los que
## los shafts no deben dibujarse: sol a la espalda, sol fuera de pantalla y sol bajo el horizonte.
func _build_god_ray_sun(
	cam_transform: Transform3D,
	cam_origin: Vector3,
	projection: Projection,
	sun_dir: Vector3,
	center: Vector3
) -> Vector3:
	# Mundo -> vista. La base de una cámara es ortonormal, así que la inversa es la transpuesta.
	var sun_view: Vector3 = cam_transform.basis.inverse() * sun_dir

	# La cámara mira a -Z: con z >= 0 el sol está detrás y la proyección lo devolvería ESPEJADO
	# dentro de la pantalla, o sea rayos saliendo del sitio equivocado.
	if sun_view.z >= -0.0001:
		return Vector3(0.5, 0.5, 0.0)

	var clip: Vector4 = projection * Vector4(sun_view.x, sun_view.y, sun_view.z, 0.0)
	if absf(clip.w) < 0.0001:
		return Vector3(0.5, 0.5, 0.0)

	# Misma convención de uv que el compute (ndc * 0.5 + 0.5, fila 0 arriba). El clamp es una red
	# contra el sol casi tangente al plano de cámara, y por eso deja tanto sitio fuera de pantalla:
	# a ángulos medios el sol cae a varios encuadres y de ahí sale la DIRECCIÓN de los shafts.
	var uv := Vector2(clip.x / clip.w, clip.y / clip.w) * 0.5 + Vector2(0.5, 0.5)
	uv.x = clampf(uv.x, -64.0, 65.0)
	uv.y = clampf(uv.y, -64.0, 65.0)

	# Fundido angular, no por cuánto se sale el sol de pantalla: medirlo en uv ata el efecto al FOV
	# y al aspecto, y dejaba los rayos muertos a pocos grados del borde.
	var forward := -cam_transform.basis.z
	var angle := acos(clampf(forward.dot(sun_dir), -1.0, 1.0))
	var t := clampf(angle / deg_to_rad(maxf(god_rays_max_angle, 1.0)), 0.0, 1.0)
	var visibility: float = pow(1.0 - t, maxf(god_rays_angle_falloff, 0.05))

	# Fundido bajo el horizonte, medido en el OBSERVADOR. El margen negativo deja que el atardecer,
	# cuando mejor lucen, llegue hasta un poco después de la puesta.
	var up := cam_origin - center
	if up.length_squared() > 0.000001:
		visibility *= smoothstep(-0.12, 0.02, up.normalized().dot(sun_dir))

	return Vector3(uv.x, uv.y, visibility)


func _append_vec4(array: PackedFloat32Array, value: Vector4) -> void:
	array.push_back(value.x)
	array.push_back(value.y)
	array.push_back(value.z)
	array.push_back(value.w)
