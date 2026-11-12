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

## Los cofres de la base que aceptan el oficio [id] (&"": todos), del más cercano a él al más lejano;
## con [marked_first], antes los marcados con ese oficio.
func chests(id: StringName = &"", marked_first := false) -> Array[Storage]:
	var out: Array[Storage] = []
	if not c.base.is_finite():
		return out
	var home := c._terrain.global_transform * c.base
	for node in c.get_tree().get_nodes_in_group(Storage.GROUP):
		var chest := node as Storage
		if chest == null or not chest.is_inside_tree() or chest.is_queued_for_deletion() \
				or chest.global_position.distance_to(home) > SettlerWork.CHEST_REACH:
			continue
		if id == &"" or chest.accepts_job(id):
			out.append(chest)
	var here := c.global_position
	out.sort_custom(func(a: Storage, b: Storage) -> bool:
		var da := a.global_position.distance_to(here) + (0.0 if not marked_first or a.jobs.has(id) else 1000.0)
		var db := b.global_position.distance_to(here) + (0.0 if not marked_first or b.jobs.has(id) else 1000.0)
		return da < db)
	return out


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
