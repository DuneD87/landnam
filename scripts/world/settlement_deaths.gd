class_name SettlementDeaths
extends RefCounted

## Los aldeanos muertos (Villager._die): su poblado no los saca (ni de cuerpo ni de multitud) hasta que
## pasan RESPAWN_TIME s de juego (cuenta solo jugando, también lejos del poblado); entonces vuelven a
## salir, la primera vez en su cama (back), y de ahí a lo suyo. Va en la partida (SettlementManager).

const RESPAWN_TIME := 1200.0

## Vecino ("id" de SettlementPopulation) -> lo que le falta para volver (s).
var _left := {}
## Los que ya han vuelto y aún no han salido (id -> true): salen en su cama.
var _back := {}


func add(id: String) -> void:
	_left[id] = RESPAWN_TIME


func has(id: String) -> bool:
	return _left.has(id)


## Lo que le falta a [id] para volver (s); 0 si no está muerto.
func left(id: String) -> float:
	return float(_left.get(id, 0.0))


## Si [id] acaba de volver y aún no ha salido (sale en su cama: Villager.setup).
func is_back(id: String) -> bool:
	return _back.has(id)


## Ya ha salido.
func clear_back(id: String) -> void:
	_back.erase(id)


func count() -> int:
	return _left.size()


## Los muertos del poblado [v] que aún no han vuelto, y lo que le falta al primero en volver (s).
func of_village(v: int) -> Array:
	var prefix := "%d:" % v
	var n := 0
	var soonest := INF
	for id: String in _left:
		if id.begins_with(prefix):
			n += 1
			soonest = minf(soonest, float(_left[id]))
	return [n, soonest]


func advance(delta: float) -> void:
	for id: String in _left.keys():
		_left[id] = float(_left[id]) - delta
		if float(_left[id]) <= 0.0:
			_left.erase(id)
			_back[id] = true


func save_data() -> Dictionary:
	return _left.duplicate()


func restore(data: Dictionary) -> void:
	_left.clear()
	_back.clear()
	for id in data:
		var left := float(data[id])
		if left > 0.0:
			_left[str(id)] = minf(left, RESPAWN_TIME)
