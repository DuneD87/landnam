class_name SkyLighting
extends Node

## Iluminación día/noche del sistema planetario. Los planetas son esferas pequeñas y el sol gira a
## su alrededor, así que la hora no es global: depende de dónde esté el observador. Cada frame se
## resuelve para la cámara activa en qué cuerpo está y a qué altura tiene el sol y la luna sobre SU
## horizonte, y con eso se gobierna:
##   · el sol: color y energía con la misma transmitancia del modelo de cielo del compute (blanco
##     cálido arriba, dorado, naranja rasante, apagado al hundirse el disco bajo el horizonte),
##   · la luz de luna: dirección real desde el observador, fase por el ángulo sol-luna-observador,
##     luz fría, y las sombras cuando el sol ya no está,
##   · el ambiente de cielo: el cubemap de radiancia del Sky, reconstruido a partir del MISMO modelo
##     de dispersión que pinta el compute de atmósfera (el relleno de las sombras sale del cielo que
##     se ve: azul a mediodía, rosado en la hora dorada, naranja al ponerse, luz de luna de noche),
##   · la adaptación de exposición al anochecer,
##   · uniforms globales para los shaders con iluminación propia (agua, impostores).
## El clima no toca las luces: pide sus escalas con set_weather_scales() y se componen aquí.

const GROUP := &"sky_lighting"

const SKY_STEPS := 10
## Anisotropía de Mie para las muestras de ambiente: seis direcciones representan cada una un trozo
## grande de cielo, y con el lóbulo estrecho del halo del sol la muestra del horizonte del lado del
## sol se lo llevaba entero en la hora dorada. Ancho, reparte la misma luz.
const AMBIENT_MIE_G := 0.4
## Muestras de cielo en el marco local: (elevación, azimut respecto al sol) en grados. El orden es
## el de los uniforms amb_* de space_sky.gdshader.
const SKY_SAMPLES := [
	Vector2(90.0, 0.0),
	Vector2(35.0, 0.0),
	Vector2(35.0, 180.0),
	Vector2(4.0, 0.0),
	Vector2(4.0, 90.0),
	Vector2(4.0, 180.0),
]
const SKY_UNIFORMS := [
	&"amb_zenith", &"amb_mid_sun", &"amb_mid_anti", &"amb_hor_sun", &"amb_hor_side", &"amb_hor_anti",
]
## Peso del coseno de cada banda de elevación sobre una cara horizontal: cenit (60-90°), media
## altura (20-60°) y horizonte (0-20°). Da la radiancia media que recibe el suelo.
const BAND_WEIGHTS := Vector3(0.25, 0.63, 0.12)
## Tono del cielo iluminado por la luna (dispersión de Rayleigh, como el de día).
const MOON_SKY_TINT := Vector3(0.55, 0.7, 1.0)

@export var sun_light: DirectionalLight3D
@export var moon_light: DirectionalLight3D
@export var world_environment: WorldEnvironment
## Contenedor de los planet_loader: cada hijo con su `planet` cargado es un cuerpo.
@export var planets: Node3D

@export_group("Sun")
## Energía del sol alto con el aire limpio. El color y la caída hacia el horizonte los pone la
## transmitancia del modelo de cielo de la atmósfera (sun_path_scale, ozone_strength, sky_curvature
## en PlanetAtmosphere); el clima la escala por encima.
@export_range(0.0, 4.0, 0.01) var sun_energy: float = 1.1
## Radio angular del disco solar del cielo (grados). La luz se funde mientras el disco cruza el
## horizonte, no de golpe cuando lo cruza su centro.
@export_range(0.1, 10.0, 0.1) var sun_disc_radius_deg: float = 2.9

@export_group("Moon")
## Energía de la luz de luna llena en lo alto. La real es 1/400000 del sol: esta está comprimida
## para que la noche se lea (y la exposición la sube un poco más).
@export_range(0.0, 1.0, 0.005) var moon_energy: float = 0.17
## Color de la luz de luna. Frío a propósito: así se percibe de noche (efecto Purkinje).
@export var moon_color: Color = Color(0.62, 0.73, 1.0)
## Contraste de la fase: 1 = esfera lambertiana (media luna = 32% de la llena, como en el cielo
## real), menos = curva más plana. Por debajo de 1 una media luna sigue dejando la noche legible.
@export_range(0.2, 1.5, 0.05) var moon_phase_contrast: float = 0.6
## Techo de la luz reflejada por otro cuerpo. Desde la luna la tierra llena es ~40 veces más
## brillante que la luna llena desde la tierra; sin techo la noche lunar sería de día.
@export_range(0.0, 2.0, 0.01) var secondary_max_energy: float = 0.25
## Luz de cielo que aporta la luna, como fracción de su luz directa.
@export_range(0.0, 1.0, 0.01) var moon_sky_fraction: float = 0.45
## Brillo del lado nocturno de la luna por la luz que le devuelve la tierra, con tierra llena.
@export_range(0.0, 0.3, 0.005) var earthshine: float = 0.035
## Albedo de los cuerpos para la luz que reflejan: con atmósfera (nubes, océano) y sin ella.
@export_range(0.0, 1.0, 0.01) var atmosphere_body_albedo: float = 0.3
@export_range(0.0, 1.0, 0.01) var airless_body_albedo: float = 0.12

@export_group("Sky Ambient")
## Radiancia del modelo de dispersión → luz ambiente. El cielo del compute es muy brillante (su
## sun_intensity está afinado para verse, no para iluminar): a 0.6 el mediodía deja las sombras a
## ~1/3 del suelo al sol (con la opacidad de sombra 0.85 de las luces).
@export_range(0.0, 4.0, 0.01) var ambient_scale: float = 0.6
## Saturación del ambiente respecto al cielo. El modelo es dispersión simple y sale muy saturado;
## la luz de cielo real está mucho más lavada por la dispersión múltiple.
@export_range(0.0, 1.0, 0.01) var ambient_saturation: float = 0.3
## Peso del horizonte en el ambiente, hacia el color de media altura. El horizonte del modelo es
## varias veces más brillante que el resto del cielo, y sin oclusión del entorno (no hay GI) una
## pared o un tronco en mitad del bosque lo recibiría entero: salían azules a mediodía.
@export_range(0.0, 1.0, 0.01) var ambient_horizon_weight: float = 0.45
## Radiancia del cielo que se refleja (agua, cristal), respecto a la del cielo visible.
@export_range(0.0, 2.0, 0.01) var reflection_scale: float = 0.45
@export_range(0.0, 1.0, 0.01) var reflection_saturation: float = 0.75
## Halo del sol en los reflejos (la corona del cielo), como fracción de su luz. Es lo que tiñe de
## naranja el agua hacia el ocaso.
@export_range(0.0, 2.0, 0.01) var sun_glow_reflection: float = 0.6
## Albedo medio del suelo: la luz que rebota hacia arriba y rellena las caras que miran abajo.
@export var ground_albedo: Color = Color(0.2, 0.19, 0.15)
## Suelo de la noche sin luna: luz de estrellas y resplandor del aire.
@export var night_sky_radiance: Color = Color(0.011, 0.015, 0.025)

@export_group("Exposure")
## Adaptación del ojo: por debajo de esta luminancia de escena la exposición empieza a subir.
@export var auto_exposure: bool = true
@export_range(0.01, 2.0, 0.01) var exposure_key: float = 0.35
## Cuánto compensa la adaptación (0 = nada, 1 = todo). Parcial a propósito: la noche debe verse
## oscura, solo que legible.
@export_range(0.0, 1.0, 0.01) var exposure_adaptation: float = 0.4
@export_range(1.0, 8.0, 0.05) var max_exposure: float = 3.0
## Velocidad de adaptación (1/s).
@export_range(0.05, 10.0, 0.05) var adaptation_speed: float = 1.5

## Escalas del clima (las pide el WeatherController): luz directa, ambiente y cuánto encapotado
## está el cielo sobre el observador (desatura el ambiente hacia el gris de las nubes).
var _weather_sun := 1.0
var _weather_ambient := 1.0
var _weather_overcast := 0.0
## Cuerpo (planet_loader) cuyo clima envía las escalas: solo se aplican con el observador en él.
var _weather_source: Node = null

class Body:
	var loader: Node
	var center_node: Node3D
	var radius: float
	var atmosphere: PlanetAtmosphere
	var terrain_material: ShaderMaterial
	var albedo: float

	func center() -> Vector3:
		return center_node.global_position

var _bodies: Array[Body] = []
var _sky_raw: Array[Vector3] = []
var _sky_cursor := 0
var _sky_primed := false
## Dónde y sobre qué cuerpo se muestreó el cielo: un salto grande (teletransporte, cambio de
## cuerpo) rehace todas las muestras en el mismo frame en vez de repartirlas.
var _sky_anchor := Vector3.INF
var _sky_home: Body = null
# Modelo de cielo de la atmósfera del cuerpo actual (planet_atmosphere.glsl::make_sky), fijado una
# vez por frame para el integrador y la transmitancia.
var _p_body: Body = null
var _p_planet_r := 1.0
var _p_atmo_r := 2.0
var _p_falloff := 4.0
var _p_coeffs := Vector3.ZERO
var _p_intensity := 0.0
var _p_sig_m := 0.0
var _p_falloff_m := 12.0
var _p_h_r := 750.0
var _p_h_m := 250.0
var _p_curvature := 1.0
var _p_k_sun := 1.0
var _p_view_scale := 1.0
var _p_ozone := Vector3.ZERO
var _p_oz_h1 := 0.0
var _p_oz_h2 := 1.0
var _p_g := 0.8
var _p_ms := 0.0
var _p_ms_tint := Vector3.ONE
var _exposure := 1.0
## Cuánto se ve el cielo nocturno (estrellas, luz cenicienta): 0 de día, 1 con el cielo oscuro. La
## luz cenicienta se actualiza antes que el cielo y usa la del frame anterior.
var _night_visibility := 1.0
var _env: Environment
var _sky_material: ShaderMaterial
## Último estado resuelto, para diagnóstico (consola, capturas de prueba). Solo se rellena con
## collect_debug_state activo: construirlo cada frame son varias reservas que el juego no necesita.
var debug_state: Dictionary = {}
var collect_debug_state := false
## Radiancias efectivas del último frame (color × energía, clima incluido), para lo que se ilumina
## a mano sin pasar por las luces: partículas, efectos.
var sun_radiance := Vector3.ONE
var moon_radiance := Vector3.ZERO
var ambient_radiance := Vector3(0.2, 0.25, 0.33)


func _ready() -> void:
	add_to_group(GROUP)
	# Después del sun_controller (que mueve el sol en su _process) y antes de dibujar.
	process_priority = 50
	_sky_raw.resize(SKY_SAMPLES.size())
	_sky_raw.fill(Vector3.ZERO)
	if world_environment != null:
		_env = world_environment.environment
		if _env != null and _env.sky != null:
			_sky_material = _env.sky.sky_material as ShaderMaterial
	if _env != null:
		# El ambiente lo da el cielo del observador (pase de cubemap de space_sky.gdshader).
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		_env.ambient_light_sky_contribution = 1.0
		_env.ambient_light_energy = 1.0
	_refresh_bodies()


## Escalas de luz del clima local. `overcast` 0..1 = cuánto cubren las nubes al observador.
## `source` es el planet_loader del clima: en otro cuerpo (la luna) sus nubes no tapan nada.
func set_weather_scales(sun_scale: float, ambient_scale_mult: float, overcast: float,
		source: Node = null) -> void:
	_weather_sun = maxf(sun_scale, 0.0)
	_weather_ambient = maxf(ambient_scale_mult, 0.0)
	_weather_overcast = clampf(overcast, 0.0, 1.0)
	_weather_source = source


func _refresh_bodies() -> void:
	_bodies.clear()
	if planets == null:
		return
	for child in planets.get_children():
		var planet := child.get("planet") as Planet
		if planet == null or not is_instance_valid(planet) or planet.voxel_terrain == null:
			continue
		var body := Body.new()
		body.loader = child
		body.center_node = planet.voxel_terrain
		body.radius = planet.radius
		var ctrl := child.get_node_or_null("PlanetAtmosphereController") as PlanetAtmosphereController
		body.atmosphere = ctrl.effect if ctrl != null else null
		body.albedo = atmosphere_body_albedo if body.atmosphere != null else airless_body_albedo
		body.terrain_material = planet.shader_material
		_bodies.append(body)
	# El relleno de las sombras lo pone el ambiente de cielo; la opacidad de las luces (0.85) solo
	# deja pasar un poco de luz cálida, como el rebote que no simulamos. El terreno remapea
	# ATTENUATION con esta misma opacidad para que las cuevas queden a oscuras: tienen que coincidir.
	var opacity := sun_light.shadow_opacity if sun_light != null else 1.0
	for body in _bodies:
		if body.terrain_material != null:
			body.terrain_material.set_shader_parameter(&"sun_shadow_opacity", opacity)


func _bodies_valid() -> bool:
	for body in _bodies:
		if not is_instance_valid(body.center_node):
			return false
	return true


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if _bodies.is_empty() or not _bodies_valid():
		_refresh_bodies()
	var cam := get_viewport().get_camera_3d()
	if cam == null or _bodies.is_empty() or sun_light == null:
		return
	_update(cam.global_position, delta)
	var cost := Time.get_ticks_usec() - t0
	if collect_debug_state:
		debug_state["cost_usec"] = cost
	DebugStats.report_cost(&"cielo:iluminacion", cost)


func _update(observer: Vector3, delta: float) -> void:
	var home := _home_body(observer)
	var local_weather := _weather_source == null or _weather_source == home.loader
	var weather_sun := _weather_sun if local_weather else 1.0
	var weather_ambient := _weather_ambient if local_weather else 1.0
	var weather_overcast := _weather_overcast if local_weather else 0.0
	var rel := observer - home.center()
	var dist := maxf(rel.length(), home.radius + 0.01)
	var up := rel / maxf(rel.length(), 0.0001)
	var altitude := dist - home.radius
	# Depresión del horizonte geométrico: desde altura se ve el sol aunque esté bajo el horizontal.
	var ratio := clampf(home.radius / dist, 0.0, 1.0)
	var horizon_sin := -sqrt(1.0 - ratio * ratio)
	var dip_deg := rad_to_deg(asin(-horizon_sin))

	if home.atmosphere != null:
		_set_atmosphere_params(home)

	# --- Sol ---
	var sun_dir := sun_light.global_transform.basis.z.normalized()
	var sun_sin := up.dot(sun_dir)
	var sun_elev := rad_to_deg(asin(clampf(sun_sin, -1.0, 1.0)))
	var sun_disc := smoothstep(-sun_disc_radius_deg, sun_disc_radius_deg, sun_elev + dip_deg)
	var sun_trans := _observer_transmittance(home, altitude, sun_sin)
	var sun_rgb := sun_trans * (sun_energy * sun_disc * weather_sun)
	_apply_light(sun_light, sun_rgb)
	if home.atmosphere != null:
		# Tono de los god rays: el del sol que se ve, sin su energía. Tras la puesta los haces aún
		# duran un poco (los funde planet_atmosphere) y conservan el color del sol al tocar el
		# horizonte en vez de apagarse a blanco.
		var ray_col := _observer_transmittance(home, altitude, maxf(sun_sin, 0.03))
		var peak := maxf(ray_col.x, maxf(ray_col.y, ray_col.z))
		var tint := ray_col / peak if peak > 0.0001 else Vector3(1.0, 0.3, 0.1)
		home.atmosphere.set_sun_tint(Color(tint.x, tint.y, tint.z))

	# --- Luna (o el cuerpo que más luz refleje en el cielo del observador) ---
	var moon_rgb := Vector3.ZERO
	var moon_dir := Vector3.UP
	var moon_sin := -1.0
	var moon_raw := 0.0
	var moon := _secondary_body(home, observer)
	if moon != null:
		var to_moon := moon.center() - observer
		var moon_dist := to_moon.length()
		moon_dir = to_moon / moon_dist
		moon_sin = up.dot(moon_dir)
		var moon_elev := rad_to_deg(asin(clampf(moon_sin, -1.0, 1.0)))
		moon_raw = _reflected_energy(moon, moon_dist, sun_dir.dot(-moon_dir))
		var moon_radius_deg := rad_to_deg(asin(clampf(moon.radius / moon_dist, 0.0, 1.0)))
		var moon_disc := smoothstep(-moon_radius_deg, moon_radius_deg, moon_elev + dip_deg)
		# De día la luna no se nota: entra cuando el disco del sol ya se ha hundido entero, así que
		# en tierra nunca coinciden las dos luces y la luna tiene siempre sus sombras (sin ellas
		# iluminaría el interior de las cuevas). Desde órbita se ven a la vez la cara de día y la de
		# noche: ahí se queda encendida, sin sombras (las lleva el sol), para que la cara nocturna
		# no sea un disco negro.
		var night_gate := clampf((-(sun_elev + dip_deg) - sun_disc_radius_deg) / 3.0, 0.0, 1.0)
		night_gate = night_gate * night_gate * (3.0 - 2.0 * night_gate)
		if home.atmosphere != null:
			var thickness := maxf(home.atmosphere.atmosphere_radius - home.radius, 1.0)
			night_gate = maxf(night_gate, smoothstep(thickness, thickness * 3.0, altitude))
		var moon_col := Vector3(moon_color.r, moon_color.g, moon_color.b)
		moon_rgb = _observer_transmittance(home, altitude, moon_sin) * moon_col \
			* (moon_raw * moon_disc * night_gate * weather_sun)
		_update_earthshine(home, moon, sun_dir, _night_visibility)
	_apply_light(moon_light, moon_rgb)
	if moon_light != null and moon != null:
		var hint := up if absf(up.dot(moon_dir)) < 0.99 else Vector3.RIGHT
		moon_light.global_basis = Basis.looking_at(-moon_dir, hint)
	# Una sola luz con sombras a la vez: la luna las toma cuando el sol ya no alumbra, si el sol
	# las tiene (las opciones gráficas las apagan en el sol).
	if moon_light != null:
		var moon_shadows := sun_light.shadow_enabled and not sun_light.visible
		if moon_light.shadow_enabled != moon_shadows:
			moon_light.shadow_enabled = moon_shadows

	# --- Cielo ---
	var sun_ref := sun_dir - up * sun_sin
	sun_ref = sun_ref.normalized() if sun_ref.length_squared() > 1e-8 else _any_perpendicular(up)
	_sample_sky(home, rel, up, sun_ref, sun_dir)

	var moon_sky := MOON_SKY_TINT * (_luminance(moon_rgb) * moon_sky_fraction)
	var night := Vector3(night_sky_radiance.r, night_sky_radiance.g, night_sky_radiance.b)
	var ambient: Array[Vector3] = []
	var reflected: Array[Vector3] = []
	for i in _sky_raw.size():
		var base := _overcast(_sky_raw[i], weather_overcast)
		var refl := _saturate(base, reflection_saturation) * reflection_scale
		if i >= 3:
			# Horizonte (muestras 3-5) hacia la media altura de su lado.
			var mid_ref: Vector3 = _sky_raw[1] if i == 3 else (_sky_raw[2] if i == 5 else (_sky_raw[1] + _sky_raw[2]) * 0.5)
			base = _overcast(mid_ref, weather_overcast).lerp(base, ambient_horizon_weight)
		var amb := _saturate(base, ambient_saturation) * ambient_scale
		# La luna y la noche no escalan con ambient_scale: están afinadas ya como luz ambiente.
		ambient.append((amb + moon_sky + night) * weather_ambient)
		reflected.append((refl + moon_sky + night) * weather_ambient)
	var ambient_up := ambient[0] * BAND_WEIGHTS.x \
		+ (ambient[1] + ambient[2]) * (0.5 * BAND_WEIGHTS.y) \
		+ (ambient[3] + ambient[4] * 2.0 + ambient[5]) * (0.25 * BAND_WEIGHTS.z)
	var ground_col := Vector3(ground_albedo.r, ground_albedo.g, ground_albedo.b)
	var ground := ground_col * (sun_rgb * maxf(sun_sin, 0.0) + moon_rgb * maxf(moon_sin, 0.0) + ambient_up)

	if _sky_material != null:
		_sky_material.set_shader_parameter(&"amb_up", up)
		_sky_material.set_shader_parameter(&"amb_sun_ref", sun_ref)
		for i in SKY_UNIFORMS.size():
			_sky_material.set_shader_parameter(SKY_UNIFORMS[i], ambient[i])
		_sky_material.set_shader_parameter(&"amb_ground", ground)
		_sky_material.set_shader_parameter(&"amb_horizon_sin", horizon_sin)
		# Las estrellas asoman al oscurecerse el cielo (crepúsculo náutico) y una luna brillante
		# apaga las más débiles. Sin atmósfera o desde el espacio el cielo es negro: siempre.
		var sky_lum := _luminance(_sky_raw[0] * BAND_WEIGHTS.x + (_sky_raw[1] + _sky_raw[2]) * 0.5 * BAND_WEIGHTS.y)
		_night_visibility = 1.0 - smoothstep(0.002, 0.05, sky_lum)
		var moon_up := smoothstep(-0.05, 0.05, moon_sin)
		var stars := _night_visibility * (1.0 - 0.35 * clampf(moon_raw / maxf(moon_energy, 0.0001), 0.0, 1.0) * moon_up)
		_sky_material.set_shader_parameter(&"night_sky_visibility", clampf(stars, 0.0, 1.0))
		_sky_material.set_shader_parameter(&"aurora_intensity",
			_aurora_intensity(home, up, weather_overcast) if home.atmosphere != null else 0.0)

	sun_radiance = sun_rgb
	moon_radiance = moon_rgb
	ambient_radiance = ambient_up
	RenderingServer.global_shader_parameter_set(&"sky_sun_radiance", sun_rgb)
	RenderingServer.global_shader_parameter_set(&"sky_sun_direction", sun_dir)
	RenderingServer.global_shader_parameter_set(&"sky_moon_radiance", moon_rgb)
	RenderingServer.global_shader_parameter_set(&"sky_moon_direction", moon_dir)
	RenderingServer.global_shader_parameter_set(&"sky_ambient_radiance", ambient_up)
	RenderingServer.global_shader_parameter_set(&"sky_zenith_radiance", reflected[0])
	RenderingServer.global_shader_parameter_set(&"sky_horizon_sun_radiance", reflected[3])
	RenderingServer.global_shader_parameter_set(&"sky_horizon_side_radiance", reflected[4])
	RenderingServer.global_shader_parameter_set(&"sky_horizon_anti_radiance", reflected[5])
	RenderingServer.global_shader_parameter_set(&"sky_sun_glow_radiance", sun_rgb * sun_glow_reflection)

	_update_atmosphere_moons(home, moon_dir, moon_raw * weather_sun, sun_dir)

	if collect_debug_state:
		debug_state = {
			"sun_elev": sun_elev, "sun_rgb": sun_rgb, "moon_rgb": moon_rgb, "moon_raw": moon_raw,
			"moon_elev": rad_to_deg(asin(clampf(moon_sin, -1.0, 1.0))), "ambient_up": ambient_up,
			"sky_raw": _sky_raw.duplicate(), "ambient": ambient, "ground": ground, "reflected": reflected,
			"exposure": _exposure, "altitude": altitude,
		}
	if _env != null:
		if auto_exposure:
			var key := _luminance(sun_rgb) * 0.5 + _luminance(ambient_up) + _luminance(moon_rgb) * 0.5
			var target := clampf(pow(exposure_key / maxf(key, 0.0001), exposure_adaptation), 1.0, max_exposure)
			_exposure = lerpf(_exposure, target, 1.0 - exp(-delta * adaptation_speed)) if _sky_primed else target
			_env.tonemap_exposure = _exposure
	_sky_primed = true


## Luz para materiales sin sombreado que no tienen normal que valga (gotas, copos): la mitad de
## la directa (el disco del sol y la luna solo ilumina una cara) más el cielo.
func get_particle_light() -> Color:
	var c := (sun_radiance + moon_radiance) * 0.55 + ambient_radiance
	return Color(c.x, c.y, c.z)


## Cuerpo en el que está el observador: el de superficie más cercana.
func _home_body(observer: Vector3) -> Body:
	var best: Body = _bodies[0]
	var best_d := INF
	for body in _bodies:
		var d := observer.distance_to(body.center()) - body.radius
		if d < best_d:
			best_d = d
			best = body
	return best


## El otro cuerpo que más luz refleja hacia el observador (la luna desde la tierra; la tierra
## desde la luna). Null si solo hay uno.
func _secondary_body(home: Body, observer: Vector3) -> Body:
	var best: Body = null
	var best_b := 0.0
	for body in _bodies:
		if body == home:
			continue
		var d := observer.distance_to(body.center())
		var b := body.albedo * pow(body.radius / maxf(d, body.radius), 2.0)
		if b > best_b:
			best_b = b
			best = body
	return best


## Energía de la luz que refleja `body` hacia el observador. cos_phase = coseno del ángulo de fase
## (en el cuerpo, entre el sol y el observador): 1 = lleno, -1 = nuevo. Fase de esfera lambertiana,
## aplanada con moon_phase_contrast. Escalada para que la luna llena vista desde la superficie de la
## tierra valga moon_energy, con techo en secondary_max_energy.
func _reflected_energy(body: Body, dist: float, cos_phase: float) -> float:
	var alpha := acos(clampf(cos_phase, -1.0, 1.0))
	var phase := (sin(alpha) + (PI - alpha) * cos(alpha)) / PI
	var brightness := body.albedo * pow(body.radius / maxf(dist, body.radius), 2.0)
	return minf(moon_energy * brightness / _moon_reference(), secondary_max_energy) \
		* pow(maxf(phase, 0.0), moon_phase_contrast)


## Brillo de referencia: el cuerpo sin atmósfera (la luna) visto lleno desde la superficie del
## cuerpo con atmósfera (la tierra) en su punto más cercano.
func _moon_reference() -> float:
	var world: Body = null
	var satellite: Body = null
	for body in _bodies:
		if body.atmosphere != null and world == null:
			world = body
		elif body.atmosphere == null and satellite == null:
			satellite = body
	if world == null or satellite == null:
		return 0.001
	var d := maxf(world.center().distance_to(satellite.center()) - world.radius, satellite.radius)
	return maxf(satellite.albedo * pow(satellite.radius / d, 2.0), 1e-9)


## Luna de cada atmósfera (cielo nocturno, nubes, niebla y aureola del compute). La del cuerpo
## del observador usa su dirección desde él: la aureola tiene que quedar centrada en el disco que
## ve, y la paralaje de la luna llega a ~12° entre la superficie y el centro. En otro cuerpo (vista
## desde la luna o desde órbita lejana) vale la luna vista desde su centro.
func _update_atmosphere_moons(home: Body, home_moon_dir: Vector3, home_moon_energy: float,
		sun_dir: Vector3) -> void:
	var col := Vector3(moon_color.r, moon_color.g, moon_color.b)
	for body in _bodies:
		if body.atmosphere == null:
			continue
		if body == home:
			body.atmosphere.set_moon_light(home_moon_dir, home_moon_energy / maxf(sun_energy, 0.0001), col)
			continue
		var moon := _secondary_body(body, body.center())
		if moon == null:
			body.atmosphere.set_moon_light(Vector3.UP, 0.0, col)
			continue
		var to_moon := moon.center() - body.center()
		var d := to_moon.length()
		var energy := _reflected_energy(moon, d, sun_dir.dot(-to_moon / d))
		body.atmosphere.set_moon_light(to_moon / d, energy / maxf(sun_energy, 0.0001), col)


## Lado nocturno de la luna iluminado por la tierra: máximo con "tierra llena" desde la luna, que
## es cuando la luna está entre la tierra y el sol (luna nueva vista desde aquí). Solo se distingue
## con el cielo oscuro: de día el disco ceniciento quedaba más claro que el cielo que lo rodea.
func _update_earthshine(home: Body, moon: Body, sun_dir: Vector3, visibility: float) -> void:
	if moon.atmosphere != null or not ("impostor_night_light" in moon.loader):
		return
	var home_to_moon := (moon.center() - home.center()).normalized()
	var home_phase := (1.0 + sun_dir.dot(home_to_moon)) * 0.5
	moon.loader.set("impostor_night_light", earthshine * home_phase * visibility)


## Luz del sol (o de la luna) que llega al observador a `altitude` con `sin_elev` = coseno respecto
## a su vertical: la misma transmitancia que ilumina el cielo del compute. Fuera del aire la
## geometría efectiva se funde con la real, como el cielo: desde órbita el planeta tapa el sol donde
## lo tapa de verdad.
func _observer_transmittance(body: Body, altitude: float, sin_elev: float) -> Vector3:
	if body.atmosphere == null or body != _p_body:
		return Vector3.ONE
	var thick := _p_atmo_r - _p_planet_r
	var r_eff := _p_planet_r * lerpf(1.0, _p_curvature, _frame_weight(altitude, thick))
	return _sky_transmittance(altitude, sin_elev, r_eff)


## planet_atmosphere.glsl::sky_sun_transmittance (Chapman + Mie + capa de ozono).
func _sky_transmittance(h: float, mu: float, r_eff: float) -> Vector3:
	h = maxf(h, 0.0)
	var r := r_eff + h
	if mu < 0.0 and r * sqrt(maxf(1.0 - mu * mu, 0.0)) - r_eff < -4.0 * _p_h_r:
		return Vector3.ZERO
	var od_r := _p_h_r * _chapman(r_eff / _p_h_r, h / _p_h_r, mu)
	var od_m := _p_h_m * _chapman(r_eff / _p_h_m, h / _p_h_m, mu)
	var oz := _ball_path(r, mu, _p_oz_h2 - h) - _ball_path(r, mu, _p_oz_h1 - h)
	var tau := (_p_coeffs * od_r + Vector3.ONE * (_p_sig_m * 1.11 * od_m)) * _p_k_sun \
		+ _p_ozone * (oz / (_p_oz_h2 - _p_oz_h1))
	return _vexp(-tau)


## planet_atmosphere.glsl::chapman.
static func _chapman(x_planet: float, h: float, mu: float) -> float:
	var x := x_planet + h
	var c := sqrt(1.5707963 * x)
	if mu >= 0.0:
		return exp(-h) * c / ((c - 1.0) * mu + 1.0)
	var xt := x * sqrt(maxf(1.0 - mu * mu, 0.0))
	var ht := maxf(xt - x_planet, -30.0)
	var ct := sqrt(1.5707963 * maxf(xt, 0.001))
	return 2.0 * exp(-ht) * ct - exp(-h) * c / ((c - 1.0) * (-mu) + 1.0)


## planet_atmosphere.glsl::ball_path.
static func _ball_path(r: float, mu: float, dr: float) -> float:
	var disc := dr * (2.0 * r + dr) + r * r * mu * mu
	if dr >= 0.0:
		return -r * mu + sqrt(maxf(disc, 0.0))
	if mu >= 0.0 or disc <= 0.0:
		return 0.0
	return 2.0 * sqrt(disc)


## planet_atmosphere.glsl::sky_ms_brightness (con su realce de hora azul).
static func _ms_brightness(mu: float) -> float:
	var twilight := smoothstep(-0.25, -0.08, mu) * (1.0 - smoothstep(-0.06, 0.0, mu))
	return smoothstep(-0.25, 0.02, mu) + 1.5 * twilight


## Peso del marco de cielo terrestre: 1 a ras de suelo, 0 en el techo de la atmósfera (como el compute).
static func _frame_weight(altitude: float, thick: float) -> float:
	return 1.0 - smoothstep(0.3 * thick, thick, altitude)


static func _phase_mie(nu: float, g: float) -> float:
	var g2 := g * g
	var k := 1.5 * (1.0 - g2) / (2.0 + g2)
	return k * (1.0 + nu * nu) / pow(maxf(1.0 + g2 - 2.0 * g * nu, 0.0001), 1.5)


static func _vexp(v: Vector3) -> Vector3:
	return Vector3(exp(v.x), exp(v.y), exp(v.z))


## Color normalizado al canal mayor + energía: así el color del inspector sigue en [0,1] y la
## magnitud va entera a light_energy. Apagada (visible = false) no cuesta sombras.
func _apply_light(light: DirectionalLight3D, rgb: Vector3) -> void:
	if light == null:
		return
	var peak := maxf(rgb.x, maxf(rgb.y, rgb.z))
	var on := peak > 0.0005
	if light.visible != on:
		light.visible = on
	if not on:
		return
	light.light_color = Color(rgb.x / peak, rgb.y / peak, rgb.z / peak)
	light.light_energy = peak


## Evalúa el modelo de dispersión en las direcciones de muestreo. Si el cielo cambia poco (casi
## siempre: el sol gira 0.1°/s) basta con repartirlo, dos direcciones por frame.
func _sample_sky(home: Body, rel: Vector3, up: Vector3, sun_ref: Vector3, sun_dir: Vector3) -> void:
	if home.atmosphere == null:
		_sky_raw.fill(Vector3.ZERO)
		return
	var side := up.cross(sun_ref)
	var jumped := home != _sky_home or rel.distance_to(_sky_anchor) > 500.0
	var count := SKY_SAMPLES.size() if not _sky_primed or jumped else 2
	if jumped:
		_sky_home = home
		_sky_anchor = rel
	for n in count:
		var i := _sky_cursor
		_sky_cursor = (_sky_cursor + 1) % SKY_SAMPLES.size()
		var e := deg_to_rad(SKY_SAMPLES[i].x)
		var a := deg_to_rad(SKY_SAMPLES[i].y)
		var dir := up * sin(e) + (sun_ref * cos(a) + side * sin(a)) * cos(e)
		_sky_raw[i] = _sky_ray(rel, dir.normalized(), sun_dir)


func _set_atmosphere_params(body: Body) -> void:
	var atmo := body.atmosphere
	var wl := atmo.wavelengths
	_p_body = body
	_p_planet_r = body.radius
	_p_atmo_r = maxf(atmo.atmosphere_radius, body.radius + 1.0)
	_p_falloff = atmo.density_falloff
	var base := atmo.scattering_strength / 10000.0
	_p_coeffs = Vector3(
		pow(400.0 / maxf(wl.x, 1.0), 4.0),
		pow(400.0 / maxf(wl.y, 1.0), 4.0),
		pow(400.0 / maxf(wl.z, 1.0), 4.0)) * base
	_p_intensity = atmo.sun_intensity
	var thick := _p_atmo_r - _p_planet_r
	_p_sig_m = atmo.mie_strength * base
	_p_falloff_m = _p_falloff * maxf(atmo.mie_height_ratio, 1.0)
	_p_h_r = thick / maxf(_p_falloff, 0.1)
	_p_h_m = thick / maxf(_p_falloff_m, 0.1)
	_p_curvature = maxf(atmo.sky_curvature, 1.0)
	_p_k_sun = maxf(atmo.sun_path_scale, 0.0)
	_p_view_scale = maxf(atmo.sky_view_scale, 1.0)
	_p_ozone = PlanetAtmosphere.OZONE_COLUMN * atmo.ozone_strength
	_p_oz_h1 = thick * PlanetAtmosphere.OZONE_LAYER.x
	_p_oz_h2 = maxf(thick * PlanetAtmosphere.OZONE_LAYER.y, _p_oz_h1 + 1.0)
	_p_g = clampf(atmo.mie_g, 0.0, 0.99)
	_p_ms = maxf(atmo.multiple_scattering, 0.0)
	var peak := maxf(_p_coeffs.x, maxf(_p_coeffs.y, _p_coeffs.z))
	_p_ms_tint = Vector3.ONE.lerp(_p_coeffs / maxf(peak, 1e-12), 0.7)


## In-scatter de un rayo de cielo que sale del observador (`o` relativo al centro del planeta): la
## misma integral que planet_atmosphere.glsl::calculate_light para los rayos de cielo, en el mismo
## planeta virtual (curvatura y espesor óptico de vista a escala terrestre a ras de suelo), con
## menos muestras y el halo de Mie ensanchado (AMBIENT_MIE_G).
func _sky_ray(o: Vector3, d: Vector3, light: Vector3) -> Vector3:
	var thick := _p_atmo_r - _p_planet_r
	var h_obs := maxf(o.length() - _p_planet_r, 0.0)
	var up_obs := o.normalized()
	var fw := _frame_weight(h_obs, thick)
	var r_v := _p_planet_r * lerpf(1.0, _p_curvature, fw)
	var view_scale := lerpf(1.0, _p_view_scale, fw)
	var r_eff := _p_planet_r * _p_curvature
	var ov := up_obs * (r_v + h_obs)
	# Bajo el horizonte virtual vale el horizonte (como el compute con los huecos del terreno).
	var sin_dip := sqrt(h_obs * (2.0 * r_v + h_obs)) / (r_v + h_obs)
	var e := d.dot(up_obs)
	if e < -sin_dip:
		var flat_dir := d - up_obs * e
		flat_dir = flat_dir.normalized() if flat_dir.length_squared() > 1e-10 else _any_perpendicular(up_obs)
		var e_v := -sin_dip * 0.999
		d = flat_dir * sqrt(1.0 - e_v * e_v) + up_obs * e_v
	var hit := _ray_sphere(ov, d, r_v + thick)
	if hit.y <= 0.0:
		return Vector3.ZERO
	var step := hit.y / float(SKY_STEPS - 1)
	var pos := ov + d * (hit.x + 0.001)
	var sig_me := _p_sig_m * 1.11
	var view_od := Vector3.ZERO
	var prev_r := 0.0
	var prev_m := 0.0
	var acc_r := Vector3.ZERO
	var acc_m := Vector3.ZERO
	var acc_ms := Vector3.ZERO
	for i in SKY_STEPS:
		var r := pos.length()
		var h := r - r_v
		var d_r := _density_h(h, thick, _p_falloff)
		var d_m := _density_h(h, thick, _p_falloff_m)
		if i > 0:
			view_od += (_p_coeffs * (prev_r + d_r) + Vector3.ONE * (sig_me * (prev_m + d_m))) * (0.5 * step)
		prev_r = d_r
		prev_m = d_m
		var view_t := _vexp(-view_od * view_scale)
		var w := (0.5 if i == 0 or i == SKY_STEPS - 1 else 1.0) * step
		var mu := pos.dot(light) / r
		var lit := view_t * _sky_transmittance(h, mu, r_eff) * w
		acc_r += lit * d_r
		acc_m += lit * d_m
		acc_ms += view_t * (_p_coeffs * d_r + Vector3.ONE * (_p_sig_m * d_m)) * (_ms_brightness(mu) * w)
		pos += d * step
	var nu := d.dot(light)
	var ins := _p_coeffs * acc_r * (0.75 * (1.0 + nu * nu)) \
		+ acc_m * (_p_sig_m * _phase_mie(nu, minf(_p_g, AMBIENT_MIE_G))) \
		+ acc_ms * _p_ms_tint * _p_ms
	return ins * _p_intensity


static func _density_h(h: float, thick: float, falloff: float) -> float:
	var h01 := clampf(h / thick, 0.0, 1.0)
	return exp(-h01 * falloff) * (1.0 - h01)


## (distancia hasta la esfera, distancia dentro de ella) desde `o` (relativo al centro).
static func _ray_sphere(o: Vector3, d: Vector3, radius: float) -> Vector2:
	var b := o.dot(d)
	var c := o.dot(o) - radius * radius
	var h := b * b - c
	if h < 0.0:
		return Vector2(INF, 0.0)
	h = sqrt(h)
	var t1 := -b + h
	if t1 < 0.0:
		return Vector2(INF, 0.0)
	var t0 := maxf(-b - h, 0.0)
	return Vector2(t0, t1 - t0)


## Cielo encapotado: las nubes lavan el azul hacia un gris con la misma luminancia.
func _overcast(c: Vector3, overcast: float) -> Vector3:
	return _saturate(c, 1.0 - 0.85 * overcast)


static func _saturate(c: Vector3, amount: float) -> Vector3:
	var l := _luminance(c)
	return Vector3(l, l, l).lerp(c, amount)


static func _luminance(c: Vector3) -> float:
	return c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722


static func _any_perpendicular(v: Vector3) -> Vector3:
	var ref := Vector3.RIGHT if absf(v.x) < 0.9 else Vector3.FORWARD
	return v.cross(ref).normalized()


## Aurora del cielo del observador: óvalo alrededor de los polos (|latitud| de ~55 a ~80 grados,
## en el marco del planeta), con una actividad que sube y baja en ciclos de decenas de minutos y
## que las nubes tapan. night_sky_visibility (el sol bajo el horizonte) la multiplica en el shader.
func _aurora_intensity(home: Body, up: Vector3, overcast: float) -> float:
	var local_up: Vector3 = up
	if home.loader != null and home.loader.get(&"voxel_terrain") is Node3D:
		local_up = (home.loader.voxel_terrain as Node3D).global_basis.inverse() * up
	var lat := rad_to_deg(asin(clampf(absf(local_up.normalized().y), 0.0, 1.0)))
	var oval := smoothstep(52.0, 62.0, lat) * (1.0 - smoothstep(80.0, 88.0, lat))
	if oval <= 0.0:
		return 0.0
	var t := Time.get_ticks_msec() / 1000.0
	var activity := 0.55 + 0.3 * sin(t * 0.0041) + 0.15 * sin(t * 0.0173 + 1.7)
	return clampf(oval * activity * (1.0 - clampf(overcast, 0.0, 1.0) * 0.85), 0.0, 1.0)
