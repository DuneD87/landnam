class_name CombatDirector
extends RefCounted

## Reparte los turnos de ataque contra cada objetivo entre las criaturas que pelean con él: como
## mucho MAX_TURNS a la vez; las demás esperan en corro (CreatureCombatState, fase FLANK),
## repartidas alrededor gracias a la lista de quién pelea con quién. Estático: hay un solo reparto
## por mundo, y las criaturas muertas o liberadas se limpian solas al consultarlo.

## Criaturas que pueden atacar a la vez a un mismo objetivo.
const MAX_TURNS := 2

## id del objetivo → {id de la criatura: weakref}: las que pelean con él, y las que tienen turno.
static var _engaged: Dictionary = {}
static var _turns: Dictionary = {}


## [creature] empieza a pelear con [target].
static func join(target: Node, creature: Node) -> void:
	_add(_engaged, target, creature)


## [creature] deja de pelear con todos (y suelta los turnos que tuviera): al cambiar de objetivo,
## de estado o al morir. Vale aunque el objetivo ya no exista.
static func leave_all(creature: Node) -> void:
	var id := creature.get_instance_id()
	for table: Dictionary in [_engaged, _turns]:
		for key in table.keys():
			table[key].erase(id)
			if table[key].is_empty():
				table.erase(key)


## Pide turno para atacar a [target]: true si ya lo tenía o queda alguno libre.
static func request_turn(target: Node, creature: Node) -> bool:
	if has_turn(target, creature):
		return true
	if _alive(_turns, target).size() >= MAX_TURNS:
		return false
	_add(_turns, target, creature)
	return true


static func release_turn(target: Node, creature: Node) -> void:
	_remove(_turns, target, creature)


static func has_turn(target: Node, creature: Node) -> bool:
	if target == null or creature == null:
		return false
	return _turns.get(target.get_instance_id(), {}).has(creature.get_instance_id())


## Cuántas atacan ahora a [target].
static func turns(target: Node) -> int:
	return _alive(_turns, target).size()


## Las criaturas que pelean con [target] (con turno o esperándolo).
static func engaged(target: Node) -> Array[Node3D]:
	return _alive(_engaged, target)


## Olvida todos los repartos (pruebas).
static func reset() -> void:
	_engaged.clear()
	_turns.clear()


static func _add(table: Dictionary, target: Node, creature: Node) -> void:
	if target == null or creature == null:
		return
	var key := target.get_instance_id()
	if not table.has(key):
		table[key] = {}
	table[key][creature.get_instance_id()] = weakref(creature)


static func _remove(table: Dictionary, target: Node, creature: Node) -> void:
	if target == null or creature == null:
		return
	var key := target.get_instance_id()
	if table.has(key):
		table[key].erase(creature.get_instance_id())
		if table[key].is_empty():
			table.erase(key)


## Las criaturas de [table] contra [target] que siguen vivas y en el árbol; las demás se borran.
static func _alive(table: Dictionary, target: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if target == null or not table.has(target.get_instance_id()):
		return out
	var entries: Dictionary = table[target.get_instance_id()]
	for id in entries.keys():
		var creature := (entries[id] as WeakRef).get_ref() as Node3D
		var npc := creature as NPCController
		if creature == null or not creature.is_inside_tree() or (npc != null and npc.is_dead):
			entries.erase(id)
		else:
			out.append(creature)
	return out
