class_name PlanetWorldMap extends Node

## Dueño del mapa precomputado de un planeta: lo carga del caché o lo hornea, y traduce posiciones
## de mundo a consultas sobre él. Es el punto de entrada tanto de la UI del mapa (tecla M) como de
## cualquier sistema que necesite saber sobre qué está el jugador ("¿mar o lago?, ¿qué profundidad?").
##
## Las posiciones se convierten a dirección desde el centro VIVO del planeta (el VoxelLodTerrain),
## así el origen flotante no descuadra nada: el mapa es de direcciones, no de coordenadas absolutas.

signal map_ready(map: WorldMapData)

const CACHE_DIR := "user://maps/"
## Profundidades (en metros) entre las que el temporal entra progresivamente. El degradado evita
## una línea dura entre mar abierto y orilla. Se empujan como uniforms al agua para que GPU y CPU
## calculen exactamente la misma exposición: si divergen, los barcos flotan sobre olas que no se
## ven (ver WaterHeightSampler).
const STORM_DEPTH_START := 30.0
const STORM_DEPTH_FULL := 150.0
## Tope que admite el shader (uniform int storm_body_ids[8]).
const MAX_STORM_BODIES := 8

## Sube esto SIEMPRE que cambie el formato o el criterio de horneado. La clave del caché mira la
## fecha del generador, no la de este código: sin subirlo, un mapa horneado con reglas viejas se
## sigue leyendo tal cual y el cambio no se ve por ningún lado.
const BAKE_VERSION := 2

var map: WorldMapData

var _center_node: Node3D
var _cache_path: String
var _cache_key: String
var _thread: Thread
var _pending: WorldMapData
var _storm_flags: PackedByteArray = PackedByteArray()


func _ready() -> void:
	add_to_group("world_map")


## Deja el mapa listo: si hay caché válido se usa tal cual; si no, se hornean las alturas aquí
## (toca el generador vivo) y el etiquetado del agua se va a un hilo. Emite map_ready al terminar.
func setup(planet: Planet, entity_id: String, size: Vector2i, height_range: float) -> void:
	_center_node = planet.voxel_terrain
	var sea_level_radius := planet.radius - planet.water_radius

	_cache_key = _build_cache_key(planet, size, height_range)
	_cache_path = "%s%s.map" % [CACHE_DIR, entity_id if entity_id != "" else "planet"]

	var cached := WorldMapData.load_from(_cache_path, _cache_key)
	if cached != null and cached.is_valid():
		map = cached
		_build_storm_flags()
		print("[world-map] '%s' leído del caché (%s, %d cuerpos de agua)"
			% [entity_id, cached.size, cached.bodies.size()])
		map_ready.emit(map)
		return

	var baked := WorldMapBaker.bake_heights(
		planet.voxel_terrain.generator, size, planet.radius,
		sea_level_radius, planet.has_water, height_range)
	if baked == null:
		return

	_pending = baked
	_thread = Thread.new()
	if _thread.start(_classify_task) != OK:
		# Sin hilo se hace aquí mismo: mejor un tirón en la carga que quedarse sin mapa.
		push_warning("[world-map] no se pudo lanzar el hilo de clasificación; va en el principal.")
		_classify_task()


func _classify_task() -> void:
	WorldMapBaker.classify_water(_pending)
	call_deferred("_on_classified")


func _on_classified() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null
	map = _pending
	_pending = null
	_build_storm_flags()
	map.save_to(_cache_path, _cache_key)
	map_ready.emit(map)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null


func is_ready() -> bool:
	return map != null and map.is_valid()


func get_planet_center() -> Vector3:
	return _center_node.global_position if is_instance_valid(_center_node) else Vector3.ZERO


## Dirección unitaria desde el centro del planeta, que es la clave de todas las consultas.
func direction_of(world_pos: Vector3) -> Vector3:
	var d := world_pos - get_planet_center()
	return d.normalized() if d.length_squared() > 0.0 else Vector3.UP


func get_uv(world_pos: Vector3) -> Vector2:
	return WorldMapData.dir_to_uv(direction_of(world_pos))


## Latitud/longitud en grados: x = latitud (+N), y = longitud (+E).
func get_latlon(world_pos: Vector3) -> Vector2:
	return WorldMapData.dir_to_latlon(direction_of(world_pos))


## Radio de la superficie del terreno bajo esa posición, desde el centro del planeta.
func get_surface_radius(world_pos: Vector3) -> float:
	return map.surface_radius_at_dir(direction_of(world_pos)) if is_ready() else 0.0


## Altura del terreno sobre el nivel del mar bajo esa posición (negativa si es fondo sumergido).
func get_ground_altitude(world_pos: Vector3) -> float:
	if not is_ready():
		return 0.0
	return map.surface_radius_at_dir(direction_of(world_pos)) - map.sea_level_radius


## Altura de la propia posición sobre el nivel del mar.
func get_altitude(world_pos: Vector3) -> float:
	if not is_ready():
		return 0.0
	return (world_pos - get_planet_center()).length() - map.sea_level_radius


## True si el terreno de esa vertical está bajo el nivel del mar, esté el jugador donde esté.
func is_water_at(world_pos: Vector3) -> bool:
	return is_ready() and map.is_water_at_dir(direction_of(world_pos))


## Cuerpo de agua sobre esa vertical, o {} si es tierra. Ver WorldMapBaker._measure_bodies.
func get_water_body_at(world_pos: Vector3) -> Dictionary:
	return map.water_body_at_dir(direction_of(world_pos)) if is_ready() else {}


## Tipo de cuerpo de agua (WorldMapData.WaterType) o -1 si ahí no hay agua.
func get_water_type_at(world_pos: Vector3) -> int:
	var body := get_water_body_at(world_pos)
	return int(body.type) if not body.is_empty() else -1


## Profundidad del agua sobre el terreno en esa vertical; <= 0 en tierra firme.
func get_water_depth_at(world_pos: Vector3) -> float:
	return map.depth_at_dir(direction_of(world_pos)) if is_ready() else 0.0


func get_water_bodies() -> Array[Dictionary]:
	if not is_ready():
		return []
	return map.bodies


## Ids de los cuerpos que reciben temporal: océanos y mares, los mayores primero. Un lago o una
## charca no levantan oleaje de mar abierto por mucho que truene.
func storm_body_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	if not is_ready():
		return out
	var eligible: Array[Dictionary] = []
	for body in map.bodies:
		if int(body.type) <= WorldMapData.WaterType.SEA:
			eligible.append(body)
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.area > b.area)
	for body in eligible:
		if out.size() >= MAX_STORM_BODIES:
			push_warning("[world-map] hay %d mares con temporal y el shader admite %d; los más " %
				[eligible.size(), MAX_STORM_BODIES] + "pequeños se quedan en calma.")
			break
		out.append(int(body.id))
	return out


## 0 donde la tormenta no debe levantar oleaje (lagos, charcas y orilla), 1 en mar abierto. Es la
## réplica exacta de storm_exposure() en gerstner_waves.gdshaderinc: tocar una obliga a tocar la otra.
func storm_exposure_at(world_pos: Vector3) -> float:
	return storm_exposure_local(world_pos - get_planet_center())


## Igual pero en coordenadas ya relativas al centro del planeta, que es lo que maneja el oleaje.
func storm_exposure_local(local: Vector3) -> float:
	if not is_ready() or not map.has_water:
		return 1.0
	return map.storm_exposure_at_dir(
		local.normalized(), _storm_flags, STORM_DEPTH_START, STORM_DEPTH_FULL)


## Tabla de 1 byte por id de cuerpo: 1 = recibe temporal. Evita resolver el tipo por diccionario en
## cada consulta, que en la flotabilidad de un barco son decenas por frame de física.
func _build_storm_flags() -> void:
	_storm_flags = PackedByteArray()
	if not is_ready():
		return
	_storm_flags.resize(map.bodies.size())
	for id in storm_body_ids():
		if id >= 0 and id < _storm_flags.size():
			_storm_flags[id] = 1


## Clave que identifica la configuración con la que se horneó el mapa. Incluye la huella del
## generador y de TODAS sus subfunciones, así tocar el grafo del terreno invalida el caché solo.
func _build_cache_key(planet: Planet, size: Vector2i, height_range: float) -> String:
	var parts := PackedStringArray([
		"v%d" % BAKE_VERSION,
		"%dx%d" % [size.x, size.y],
		"r%.3f" % planet.radius,
		"w%.3f" % planet.water_radius,
		"h%.3f" % height_range,
		"aq%d" % (1 if planet.has_water else 0),
		_resource_fingerprint(planet.terrain_generator_path),
	])
	return "|".join(parts).sha256_text()


## Ruta y fecha de un recurso y de todo lo que arrastra, en orden estable.
static func _resource_fingerprint(path: String) -> String:
	var seen := {}
	var pending: Array[String] = [path]
	var parts := PackedStringArray()
	while not pending.is_empty():
		var p: String = pending.pop_back()
		if p == "" or seen.has(p):
			continue
		seen[p] = true
		parts.append("%s@%d" % [p, FileAccess.get_modified_time(p)])
		for dep in ResourceLoader.get_dependencies(p):
			# El formato de cada dependencia varía ("uid::tipo::ruta", "ruta::tipo"...): se busca
			# el trozo que es una ruta de recurso en vez de asumir una posición.
			for slice in dep.split("::"):
				if slice.begins_with("res://"):
					pending.append(slice)
	parts.sort()
	return "|".join(parts)
