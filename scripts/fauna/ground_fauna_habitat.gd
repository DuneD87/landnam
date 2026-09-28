class_name GroundFaunaHabitat extends AmbientFaunaHabitat

## Superficie sólida del planeta: elige puntos de spawn por banda de latitud, altura sobre el
## radio nominal y pendiente, sondeando con un rayo desde la atmósfera hacia el centro. El centro
## lo da el terreno vivo, así que al hábitat no hay que avisarle de los rebases del origen.

## Pendiente máxima admitida, en grados. Va atada al floor_max_angle que NPCController se pone
## a sí mismo: el filtro de spawn no debe rechazar suelo que la criatura pisa de sobra.
const MAX_SLOPE_DEGREES := 70.0
## Margen sobre el suelo al que aparece la criatura, sumado a su despeje. Corto, para que el
## golpe al caer no le haga daño.
const GROUND_MARGIN := 1.0

var terrain: Node3D
## Raíz de planetas que necesita PlanetaryBody para resolver su gravedad.
var planets: Node3D
## Mapa horneado, para descartar lo que asoma mar adentro. La banda de altura no basta: su suelo
## es justo el nivel del mar, así que una cresta de arrecife que rompe la superficie la pasa.
var world_map: PlanetWorldMap
var planet_radius: float = 0.0
var atmosphere_height: float = 1400.0
var latitude_ranges: Array[float] = []
## Campo de frío del planeta, para GroundFaunaProfile.climate_min/max. Null = sin filtro.
var climate: ClimateField

## Cuentas de aceptación y rechazo por motivo, para el comando `fauna` de la consola.
var accepted: int = 0
var rejected: Dictionary = {}

var _clearance_shape := SphereShape3D.new()


func setup(ground: Node3D, planets_root: Node3D, radius: float, atmosphere: float,
		bands: Array[float], map: PlanetWorldMap = null) -> void:
	terrain = ground
	planets = planets_root
	planet_radius = radius
	atmosphere_height = atmosphere
	latitude_ranges = bands
	world_map = map


func host() -> Node3D:
	return terrain


func sample_spawn(anchor: Vector3, profile: AmbientFaunaProfile,
		rng: RandomNumberGenerator) -> Variant:
	var settings := profile as GroundFaunaProfile
	if settings == null or not is_instance_valid(terrain) or not terrain.is_inside_tree():
		return null
	var origin := center()
	var up := (anchor - origin).normalized()
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var forward := up.cross(right)
	var angle := rng.randf_range(0.0, TAU)
	# Raíz del radio para repartir por área, o se apelotonan cerca del observador.
	var distance := profile.sample_spawn_distance(rng)
	var direction := (anchor + (right * cos(angle) + forward * sin(angle)) * distance - origin).normalized()
	if not _in_biome(direction, settings):
		_reject(&"bioma")
		return null
	return _surface_point(direction, settings, profile.clearance)


func is_spawn_valid(point: Vector3, clearance: float) -> bool:
	if not is_instance_valid(terrain) or not terrain.is_inside_tree():
		return false
	for body in nearby_ships():
		if is_instance_valid(body) and body is DynamicGridBody and body.contains_point(point, clearance + 0.5):
			_reject(&"barco")
			return false
	_clearance_shape.radius = clearance
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clearance_shape
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	if not terrain.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		_reject(&"sin_hueco")
		return false
	accepted += 1
	return true


## Punto sobre el terreno en esa dirección, o null si no hay suelo válido. El rayo sale de la
## atmósfera y baja al centro; solo la capa 1, que es donde está el terreno.
func _surface_point(direction: Vector3, settings: GroundFaunaProfile,
		clearance: float) -> Variant:
	var origin := center()
	var from := origin + direction * (planet_radius + atmosphere_height)
	var query := PhysicsRayQueryParameters3D.create(from, origin)
	query.collision_mask = 1
	var hit := terrain.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_reject(&"sin_suelo")
		return null
	var point: Vector3 = hit["position"]
	var height := point.distance_to(origin) - planet_radius
	if height < settings.min_height or height > settings.max_height:
		_reject(&"altura")
		return null
	if climate != null and climate.enabled \
			and (settings.climate_min > -1000.0 or settings.climate_max < 1000.0):
		var cold := climate.coldness(terrain.global_basis.inverse() * (point - origin))
		if cold < settings.climate_min or cold > settings.climate_max:
			_reject(&"clima")
			return null
	if (hit["normal"] as Vector3).dot(direction) < cos(deg_to_rad(MAX_SLOPE_DEGREES)):
		_reject(&"pendiente")
		return null
	# Mientras el mapa se hornea manda solo la banda de altura.
	if world_map != null and world_map.is_ready() and world_map.is_water_at(point):
		_reject(&"agua")
		return null
	return point + direction * (clearance + GROUND_MARGIN)


## La latitud se mide en el marco del planeta, no en el del mundo: es la misma convención que
## usa el mapa horneado (WorldMapData.dir_to_latlon).
func _in_biome(direction: Vector3, settings: GroundFaunaProfile) -> bool:
	var local := terrain.global_basis.inverse() * direction
	var latitude := rad_to_deg(asin(clampf(local.normalized().y, -1.0, 1.0)))
	if settings.hemisphere != 0 and signf(latitude) != float(settings.hemisphere):
		return false
	if settings.biomes.is_empty() or latitude_ranges.size() < 2:
		return true
	for index in settings.biomes:
		if index < 0 or index + 1 >= latitude_ranges.size():
			continue
		if latitude >= latitude_ranges[index] and latitude <= latitude_ranges[index + 1]:
			return true
	return false


func _reject(reason: StringName) -> void:
	rejected[reason] = int(rejected.get(reason, 0)) + 1


## Aceptados y descartes por motivo, en una línea, para el comando `fauna` de la consola.
func report() -> String:
	var reasons: Array[String] = []
	for reason in rejected:
		reasons.append("%s %d" % [reason, rejected[reason]])
	reasons.sort()
	var text := "aceptados %d" % accepted
	if not reasons.is_empty():
		text += "   descartes: " + "  ".join(reasons)
	return text
