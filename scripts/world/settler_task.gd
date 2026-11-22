class_name SettlerTask extends RefCounted

## Un oficio de colono que no es talar ni picar (SettlerWork lleva esos): construir (SettlerBuild),
## hacer guardia (SettlerGuard), cazar (SettlerHunt), pescar (SettlerFish) o cocinar (SettlerCook).
## SettlerWork lo crea al mandar el trabajo y le pasa cada paso: cerca del jugador, step (de verdad,
## andando y golpeando); lejos, away (sin moverse, a su ritmo). Aquí va lo común: andar hasta un
## sitio, los cofres de la base y lo que hay en ellos, y las herramientas del morral. Ver
## docs/villagers.md.

enum Walk {GOING, THERE, GAVE_UP}

var w: SettlerWork
var c: Companion
## Hacia dónde anda tras walk() (mundo, unitario).
var heading := Vector3.ZERO


func _init(work: SettlerWork) -> void:
	w = work
	c = work._c


## Al mandarle el trabajo y al dejarlo.
func start() -> void:
	pass


func stop() -> void:
	pass


## Dónde guardarlo si está en algo que no se guarda (el andamio del constructor), o Vector3.INF.
func ground_spot() -> Vector3:
	return Vector3.INF


## Ha dejado de darle pasos (duerme, pelea, charla, se ha alejado el jugador): suelta lo que tenga a la
## vista (la caña lanzada).
func paused() -> void:
	pass


## Un paso cerca del jugador: [hacia dónde, a qué velocidad].
func step(_delta: float) -> Array:
	return still()


## Un paso lejos del jugador (sin moverse), a la hora [hour] de la base.
func away(_delta: float, _hour: float) -> void:
	w.status = SettlerWork.Status.AWAY


## Si le toca trabajar a la hora [hour], y si a esa hora duerme.
func on_duty(hour: float) -> bool:
	return Villager._work_hour(hour)


func sleeps(hour: float) -> bool:
	return Villager._is_night(hour)


## Cómo va, para la charla y el trono (ya traducido).
func describe() -> String:
	return ""


## Lo que guarda además del trabajo y la zona, y cómo lo recupera.
func save_data() -> Dictionary:
	return {}


func restore(_data: Dictionary) -> void:
	pass


func still() -> Array:
	return [Vector3.ZERO, 0.0]


# --- Dónde ----------------------------------------------------------------------------------------

## El centro de su zona (mundo): la marcada o su base.
func center() -> Vector3:
	return c._terrain.global_transform * (w.zone if w.zone.is_finite() else c.base)


## Lo que le falta en el plano hasta [dest] (m).
func flat_to(dest: Vector3) -> float:
	return (dest - c.global_position).slide(c.up_direction).length()


## Anda hacia [dest] (mundo) hasta quedar a [reach] m en el plano; deja en heading hacia dónde. [key]
## dice a qué va: si en SettlerWork.GIVE_UP s no se acerca, lo da por imposible.
func walk(dest: Vector3, reach: float, delta: float, key: Object) -> Walk:
	if flat_to(dest) <= reach:
		w._approach_for = null
		return Walk.THERE
	heading = c.steer(dest, reach * 0.8, delta)
	if not w._approaching(key, c.steer_remaining(dest), delta):
		w._approach_for = null
		return Walk.GAVE_UP
	return Walk.GOING


# --- Cofres ---------------------------------------------------------------------------------------

## Los cofres de la base (en campo, los de cerca de la zona: SettlerWork.home) que aceptan el oficio
## [id] (&"": todos, también los comederos), del más cercano a él al más lejano; con [marked_first], antes los marcados con ese
## oficio.
func chests(id: StringName = &"", marked_first := false) -> Array[Storage]:
	var out: Array[Storage] = []
	var home := w.home()
	if not home.is_finite():
		return out
	var reach := w.chest_reach()
	for node in c.get_tree().get_nodes_in_group(Storage.GROUP):
		var chest := node as Storage
		if chest == null or not chest.is_inside_tree() or chest.is_queued_for_deletion() \
				or chest.global_position.distance_to(home) > reach:
			continue
		if id == &"" or chest.accepts_job(id):
			out.append(chest)
	var here := c.global_position
	out.sort_custom(func(a: Storage, b: Storage) -> bool:
		var da := a.global_position.distance_to(here) + (0.0 if not marked_first or a.jobs.has(id) else 1000.0)
		var db := b.global_position.distance_to(here) + (0.0 if not marked_first or b.jobs.has(id) else 1000.0)
		return da < db)
	return out


## Los comederos de la base (Storage.feeder; en campo, los de cerca de la zona), del más cercano a él.
func feeders() -> Array[Storage]:
	var home := w.home()
	if not home.is_finite():
		return []
	return Storage.feeders(c.get_tree(), home, w.chest_reach(), c.global_position)


## Dónde dejar [data] que trae a la base: sin cocinero (has_cook), lo que se come va al comedero con
## sitio más cercano, porque de los cofres no come nadie; con cocinero, al cofre, que él lo asa y lo
## pone en el comedero. null: al cofre como siempre (también en campo y con los comederos llenos).
func food_drop(data: ItemData) -> Storage:
	if w.field or data == null or not _edible(data) or has_cook():
		return null
	return chest_with_room(feeders(), data)


## Si en la base hay un colono cocinero (otro o él mismo).
func has_cook() -> bool:
	var home := w.home()
	if not home.is_finite():
		return false
	for node in c.get_tree().get_nodes_in_group(Companion.GROUP):
		var other := node as Companion
		if other == null or other.dead or other.mode != Companion.Mode.SETTLE or other.work.job != SettlerWork.Job.COOK:
			continue
		var there := other.work.home()
		if there.is_finite() and there.distance_to(home) <= w.chest_reach():
			return true
	return false


static func _edible(data: ItemData) -> bool:
	var edible := data.get_trait(EdibleTrait) as EdibleTrait
	return edible != null and edible.hunger > 0.0


## Cuánto hay de [data] entre [from].
static func stock(from: Array[Storage], data: ItemData) -> int:
	var count := 0
	for chest in from:
		count += chest.inventory.get_item_count(data)
	return count


## El primero de [from] con sitio para [data], o null.
static func chest_with_room(from: Array[Storage], data: ItemData) -> Storage:
	for chest in from:
		if SettlerWork._room(chest.inventory, data):
			return chest
	return null


## Pasa hasta [amount] de [data] de [from] a [to]. Devuelve lo que ha pasado (lo que no cabe se queda).
static func move(from: Inventory, to: Inventory, data: ItemData, amount: int) -> int:
	var taken := from.remove_item(data, mini(amount, from.get_item_count(data)))
	if taken <= 0:
		return 0
	var left := to.add_item(data, taken)
	if left > 0:
		from.add_item(data, left)
	return taken - left


## Lo que lleva de [data] en el morral.
func carried(data: ItemData) -> int:
	return c.pack.get_item_count(data)


## Lo mejor del morral según [score] (de ItemData a puntos; 0 o menos no vale), o null.
func best_in_pack(score: Callable) -> ItemData:
	var best: ItemData
	var best_score := 0.0
	for item in c.pack.get_all_items():
		if item == null:
			continue
		var points := float(score.call(item.data))
		if points > best_score:
			best = item.data
			best_score = points
	return best


## El nombre del colono, para los avisos.
func who() -> String:
	return String(c.resident.get("name", ""))

# --- La orilla ------------------------------------------------------------------------------------

## La orilla (find_shore): anillos cada RING_STEP m con ANGLES tanteos; del agua hacia tierra, pasos de
## SHORE_STEP m (hasta SHORE_STEPS). El agua tiene que cubrir WATER_DEPTH m.
const RING_STEP := 3.0
const ANGLES := 16
const SHORE_STEP := 0.75
const SHORE_STEPS := 16
const WATER_DEPTH := 0.6
## Los tanteos por anillo de map_water.
const MAP_ANGLES := 8


## La orilla de su zona más cercana a él: el agua más cercana (con [fresh], solo la dulce: ríos, lagos y
## charcas, WaterAccess.kind_at) y, de ella hacia el centro de la zona, el primer sitio seco. Devuelve
## [dónde ponerse, el agua a la que mira] (marco del terreno) o [] si no hay (o el terreno aún no está
## cargado).
func find_shore(fresh := false) -> Array:
	var terrain := c._terrain as VoxelLodTerrain
	var sea := _sea_radius()
	if terrain == null or sea <= 0.0:
		return []
	var tool := terrain.get_voxel_tool() as VoxelToolLodTerrain
	tool.channel = VoxelBuffer.CHANNEL_SDF
	var origin := terrain.global_position
	var middle := center()
	var up := (middle - origin).normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	var best := Vector3.INF
	var best_d := INF
	var r := RING_STEP
	while r <= w.zone_radius:
		for k in ANGLES:
			var point := middle + side.rotated(up, TAU * k / ANGLES) * r
			if not _wet(terrain, tool, origin, point, sea) or (fresh and not _fresh(point, terrain, sea)):
				continue
			var d := point.distance_to(c.global_position)
			if d < best_d:
				best = point
				best_d = d
		r += RING_STEP
	if not best.is_finite():
		return []
	var inland := (middle - best).slide(up)
	if inland.length() < 0.1:
		return []
	inland = inland.normalized()
	for i in range(1, SHORE_STEPS + 1):
		var point := best + inland * SHORE_STEP * i
		if _wet(terrain, tool, origin, point, sea):
			continue
		var to_local := terrain.global_transform.affine_inverse()
		# Un paso más adentro: los pies, en seco.
		return [to_local * (point + inland * SHORE_STEP), to_local * best]
	return []


## Va a su zona: el terreno (las orillas) y los animales solo están alrededor del jugador, no de él, así
## que con la zona lejos de la cámara (SettlerWork._zone_loaded) no ve en ella lo que busca, y desde la
## base se quedaba parado para siempre. Anda hasta la mitad de su radio del centro: lejos del jugador
## sigue en abstracto y, cerca, la ve al llegar. [hacia dónde, a qué velocidad], o [] si ya está (o
## no avanza).
func toward_zone(delta: float) -> Array:
	var target := center()
	var reach := w.zone_radius * 0.5
	if flat_to(target) <= reach:
		return []
	if walk(target, reach, delta, w) != Walk.GOING:
		return []
	return [heading, SettlerWork.WALK_SPEED]


## Si el mapa del mundo dice que en su zona hay agua (sin el terreno cargado, que lejos del jugador no
## lo está): el mar con WATER_DEPTH m o, con [fresh], un río o un lago. Para seguir lejos sin haber
## visto la orilla. El mapa tiene celdas de ~90 m: vale para la zona, no para la orilla.
func map_water(fresh := false) -> bool:
	var host: Variant = c._player.get("planet") if c._player != null and is_instance_valid(c._player) else null
	var core := (host as Node).get("planet") as Planet if host is Node else null
	var holder := (host as Node).get("world_map") as PlanetWorldMap if host is Node else null
	var map := holder.map if holder != null and holder.is_ready() else null
	if core == null or map == null or not map.has_water:
		return false
	var origin := c._terrain.global_position
	var middle := center()
	var up := (middle - origin).normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	var rivers := core.get_river_network() if fresh else {}
	for r: float in [0.0, w.zone_radius * 0.5, w.zone_radius]:
		for k in MAP_ANGLES:
			var dir := (middle + side.rotated(up, TAU * k / MAP_ANGLES) * r - origin).normalized()
			if not fresh:
				if map.depth_at_dir(dir) >= WATER_DEPTH:
					return true
				continue
			if not RiverField.nearby_channel_at(rivers, dir, WaterAccess.RIVER_REACH).is_empty():
				return true
			var body := map.water_body_at_dir(dir)
			if not body.is_empty() and int(body.type) >= WorldMapData.WaterType.LAKE:
				return true
	return false


## Si en la vertical de [point] hay agua que cubra WATER_DEPTH m (los vóxeles sin cargar no cuentan).
func _wet(terrain: VoxelLodTerrain, tool: VoxelToolLodTerrain, origin: Vector3, point: Vector3, sea: float) -> bool:
	var dir := (point - origin).normalized()
	return WaterAccess._has_water(terrain, tool, origin + dir * sea) \
		and WaterAccess._has_water(terrain, tool, origin + dir * (sea - WATER_DEPTH))


## Si el agua de [point] (a la altura del mar) es dulce.
func _fresh(point: Vector3, terrain: VoxelLodTerrain, sea: float) -> bool:
	var host: Variant = c._player.get("planet") if c._player != null and is_instance_valid(c._player) else null
	var core := (host as Node).get("planet") as Planet if host is Node else null
	if core == null:
		return false
	var holder := (host as Node).get("world_map") as PlanetWorldMap
	var map := holder.map if holder != null and holder.is_ready() else null
	return WaterAccess.kind_at(point, terrain, map, core.get_river_network(), sea) == &"fresh"


## El radio del mar del planeta, o 0 si no tiene agua.
func _sea_radius() -> float:
	var host: Variant = c._player.get("planet") if c._player != null and is_instance_valid(c._player) else null
	var core := (host as Node).get("planet") as Planet if host is Node else null
	if core == null or not core.has_water:
		return 0.0
	return core.radius - core.water_radius
