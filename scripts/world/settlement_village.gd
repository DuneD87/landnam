class_name SettlementVillage extends RefCounted

## Un poblado con gente (SettlementVillagers): su plaza con su hoguera y, de cada casa con lechos o
## sitios de trabajo, la puerta, los lechos y los sitios, todo en el marco del terreno (el del plano);
## quién anda por él, dónde está el jugador y si ronda una fiera. Es lo que los aldeanos (Villager)
## consultan: van de un sitio a la puerta por dentro, a la puerta por fuera y a la plaza, en línea recta
## (las casas miran a la plaza).

## Lo que se aparta de la puerta (m), por dentro y por fuera, el sitio desde el que se cruza.
const INSIDE := 1.0
const OUTSIDE := 1.6
## Al lecho se llega por los pies (m más allá de su centro).
const BED_FOOT := 1.3
## La plaza que se pisa, respecto a su radio; y el corro de la tarde, en m del centro.
const PLAZA_USE := 0.75
const RING := Vector2(2.2, 3.4)
## Los paseos no llegan a menos de esto del centro (la hoguera).
const PLAZA_HOLE := 2.0
## Las fieras que asustan, a menos de esto (m) más allá de lo más lejano del poblado; y el rato (s) sin
## ver ninguna que tarda en volver la calma.
const THREATS: Array[StringName] = [&"Wolf", &"Bear", &"PolarBear", &"Boar", &"Lion", &"Lioness", &"Puma",
	&"Lynx", &"Hyena", &"Alligator"]
const DANGER_REACH := 25.0
const CALM_TIME := 15.0
const DANGER_INTERVAL := 1.0
## La hora del sitio se vuelve a mirar cada tanto (s).
const HOUR_INTERVAL := 2.0
## El tiempo (WeatherController.get_local_precipitation: el del jugador, que está cerca) se mira cada
## tanto (s). Con lluvia desde RAIN corren a casa y la hoguera se apaga; con nieve desde SNOW nadie se
## sienta fuera y la hoguera se enciende también de día. Se acaba cuando baja de la mitad.
const WEATHER_INTERVAL := 2.0
const RAIN := 0.3
const SNOW := 0.4

var index := -1
## Su nombre (SettlementPopulation.village_name).
var name := ""
var plan: Dictionary
## La confianza del jugador en cada poblado (la de SettlementManager).
var relations: SettlementRelations
## El poblado más cercano: {"name", "toward": hacia él (tangente, unitario, marco del terreno),
## "distance": m}; vacío si no hay otro.
var neighbour := {}
## La plaza, en el suelo, y su radio.
var center := Vector3.ZERO
var plaza_radius := 8.0
var terrain: Node3D
var villagers: Array[Villager] = []
## Casa con lechos o sitios de trabajo (índice en el plano) -> {"door": el umbral, "out": hacia fuera
## (unitario), "inside", "outside", "beds": Array[Transform3D] (cabecera hacia -Z), "work": sus sitios
## (SettlementLayout._workplace)}.
var homes := {}
var player: Node3D
var fire: SettlementFire
## Ronda una fiera (THREATS): todo el mundo a casa.
var danger := false
var _danger_age := INF
var _calm := 0.0
## Llueve (RAIN) o nieva (SNOW) en el poblado; si las dos, cuenta la lluvia.
var raining := false
var snowing := false
var _weather_age := INF
## Casa -> WoodenDoor de su puerta, o null (lo da SettlementManager: la casa puede no estar levantada).
var door_of: Callable
## Una hora fija en vez de la del sol (las pruebas). NAN: la del sol.
var hour_override := NAN
var _door_users := {}
var _hour := 12.0
var _hour_age := INF


## [plan]: el del poblado [v]; [prefabs]: SettlementPrefab por id.
func _init(v: int, village_plan: Dictionary, prefabs: Dictionary, terrain_node: Node3D) -> void:
	index = v
	plan = village_plan
	terrain = terrain_node
	center = (plan.center as Vector3) * float(plan.ground)
	var template: SettlementTemplate = SettlementField.template(StringName(plan.template))
	if template != null:
		plaza_radius = template.plaza_radius
	var buildings: Array = plan.buildings
	for b in buildings.size():
		var info: Dictionary = buildings[b]
		var prefab: SettlementPrefab = prefabs.get(info.prefab)
		var work: Array = info.get("work", [])
		if prefab == null or (prefab.beds.is_empty() and work.is_empty()):
			continue
		var pose := Transform3D(info.basis, info.origin)
		var door: Vector3 = info.door
		var out := (pose.basis * Vector3(prefab.door)).normalized()
		var beds: Array[Transform3D] = []
		for bed in prefab.beds:
			beds.append(pose * bed)
		homes[b] = {"door": door, "out": out, "inside": door - out * INSIDE, "outside": door + out * OUTSIDE,
			"beds": beds, "work": work}


func frame() -> Transform3D:
	return terrain.global_transform


## Hora solar del poblado (0..24). Sin sol, mediodía.
func hour(delta := 0.0) -> float:
	if not is_nan(hour_override):
		return hour_override
	_hour_age += delta
	if _hour_age >= HOUR_INTERVAL:
		_hour_age = 0.0
		var h := Seasons.solar_hour(center)
		_hour = 12.0 if is_nan(h) else h
	return _hour


## Lo de cada fotograma (SettlementVillagers): la hoguera según la hora y el tiempo, cada tanto el
## tiempo (si cambia, avisa a todos: Villager.weather_turned) y si ronda una fiera; si empieza, avisa
## a todos (Villager.alarm).
func update(delta: float) -> void:
	var h := hour(delta)
	_weather_age += delta
	if _weather_age >= WEATHER_INTERVAL:
		_weather_age = 0.0
		_read_weather()
	if fire != null and is_instance_valid(fire):
		fire.set_lit((SettlementFire.lit_at(h) or snowing) and not raining)
	_danger_age += delta
	if _danger_age < DANGER_INTERVAL:
		return
	_calm += _danger_age
	_danger_age = 0.0
	if _threat_near():
		_calm = 0.0
		if not danger:
			danger = true
			for v in villagers:
				if is_instance_valid(v):
					v.alarm()
	elif danger and _calm >= CALM_TIME:
		danger = false


func _read_weather() -> void:
	var weather := terrain.get_tree().get_first_node_in_group("weather") as WeatherController
	var fall := weather.get_local_precipitation() if weather != null else Vector2.ZERO
	var rain := fall.x >= (RAIN * 0.5 if raining else RAIN)
	var snow := not rain and fall.y >= (SNOW * 0.5 if snowing else SNOW)
	if rain == raining and snow == snowing:
		return
	raining = rain
	snowing = snow
	for v in villagers:
		if is_instance_valid(v):
			v.weather_turned()


func _threat_near() -> bool:
	var reach := float(plan.get("extent", plaza_radius)) + DANGER_REACH
	var to_local := frame().affine_inverse()
	for node in terrain.get_tree().get_nodes_in_group(AmbientAnimal.GROUP):
		var creature := node as NPCController
		if creature == null or not creature.active or creature.is_dead or creature.npc_type not in THREATS:
			continue
		if (to_local * creature.global_position).distance_to(center) < reach:
			return true
	return false


## El jugador en el marco del terreno, o un vector no finito si no hay.
func player_local() -> Vector3:
	if player == null or not is_instance_valid(player):
		return Vector3.INF
	return frame().affine_inverse() * player.global_position


## El sitio de trabajo de un puesto (SettlementPopulation: "job").
func workplace(job: Dictionary) -> Dictionary:
	return homes.get(job.building, {}).get("work", [])[job.work]


## Un sitio delante de la casa [b], a un par de pasos de la puerta.
func front_spot(b: int, rng: RandomNumberGenerator) -> Vector3:
	var home: Dictionary = homes[b]
	var out: Vector3 = home.out
	var outside: Vector3 = home.outside
	var side := out.cross(outside.normalized())
	return (outside + out * rng.randf_range(0.6, 1.6) + side * rng.randf_range(-1.5, 1.5)).normalized() \
		* outside.length()


## Un sitio al azar de la plaza, a la altura de su centro (el aldeano baja o sube al suelo andando),
## apartado de la hoguera.
func plaza_spot(rng: RandomNumberGenerator) -> Vector3:
	var r := lerpf(PLAZA_HOLE, plaza_radius * PLAZA_USE, sqrt(rng.randf()))
	return _around(rng.randf() * TAU, r)


## Un sitio del corro de la tarde alrededor del centro de la plaza.
func ring_spot(rng: RandomNumberGenerator) -> Vector3:
	return _around(rng.randf() * TAU, rng.randf_range(RING.x, RING.y))


func _around(angle: float, r: float) -> Vector3:
	var up := center.normalized()
	var east := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	var north := east.cross(up)
	return (center + (east * cos(angle) + north * sin(angle)) * r).normalized() * center.length()


## El lecho [bed] de la casa [b]: su pose, o la identidad si ya no está.
func bed(b: int, k: int) -> Transform3D:
	var beds: Array = homes.get(b, {}).get("beds", [])
	return beds[k] if k < beds.size() else Transform3D.IDENTITY


## Por dónde se llega al lecho y de dónde se levanta: a sus pies, en la casa.
func bed_foot(b: int, k: int) -> Vector3:
	var pose := bed(b, k)
	return pose.origin + pose.basis.z * BED_FOOT


## [who] va a cruzar la puerta de la casa [b] desde [from] (m, marco del terreno): la abre si está cerrada.
func open_door(b: int, who: Villager, from: Vector3) -> void:
	var users: Dictionary = _door_users.get_or_add(b, {})
	users[who] = true
	var leaf := _leaf(b)
	if leaf != null and leaf.open_side == 0:
		leaf.toggle(frame() * from)


## [who] ya la ha cruzado: la cierra si nadie más la está cruzando.
func release_door(b: int, who: Villager) -> void:
	var users: Dictionary = _door_users.get(b, {})
	users.erase(who)
	var leaf := _leaf(b)
	if users.is_empty() and leaf != null and leaf.open_side != 0:
		leaf.toggle(frame() * (homes[b].door as Vector3))


func _leaf(b: int) -> WoodenDoor:
	if not door_of.is_valid():
		return null
	var leaf: WoodenDoor = door_of.call(b)
	return leaf if is_instance_valid(leaf) else null


## Alguien con quien charlar: de pie en la plaza, sin pareja, a menos de [reach] m de [who].
func partner_for(who: Villager, reach := 25.0) -> Villager:
	var best: Villager
	var best_distance := reach
	for other in villagers:
		if other == who or not is_instance_valid(other) or not other.free_to_talk():
			continue
		var d := other.local_position().distance_to(who.local_position())
		if d < best_distance:
			best = other
			best_distance = d
	return best
