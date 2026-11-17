class_name InstancerBodyIndex
extends RefCounted

## Los cuerpos de un VoxelInstancer (árboles y rocas con colisión) en una rejilla de celdas de
## CELL m, en coordenadas locales del instancer: el origen flotante mueve el terreno entero y no
## las cambia. Se mantiene sola con las altas y bajas de hijos del instancer.
##
## Para buscar cuerpos cerca de un punto sin recorrer todos los hijos del instancer: con ventana
## son ~19.000, y leer la posición de cada uno costaba ~30 ms en un tick (los colonos buscando qué
## talar o picar, SettlerWork._find). Una consulta de física no sirve: árboles, rocas y terreno
## comparten capa, y los trozos de terreno se comen el cupo de resultados.
##
## Límite: si el módulo reutiliza un cuerpo para otra instancia (repoblar un bloque ya poblado le
## cambia la transformada sin sacarlo del árbol), sigue en su celda vieja hasta que una consulta
## pase por ella y lo recoloque; mientras tanto una consulta en su sitio nuevo no lo ve.

const CELL := 32.0
const META := &"instancer_body_index"

var _instancer: VoxelInstancer
## Vector3i -> Array[Node3D]
var _cells := {}
## instance_id -> Vector3i
var _cell_of := {}
## Altas aún sin colocar: el módulo pone la transformada después de añadir el cuerpo. Se colocan al
## final del fotograma en que entran (unos 1,2 us cada una), no todas en la primera consulta.
var _pending: Array[Node3D] = []
var _flush_queued := false


## El índice de [instancer], creado la primera vez que se pide.
static func of(instancer: VoxelInstancer) -> InstancerBodyIndex:
	if instancer.has_meta(META):
		return instancer.get_meta(META) as InstancerBodyIndex
	var index := InstancerBodyIndex.new()
	index._attach(instancer)
	instancer.set_meta(META, index)
	return index


func _attach(instancer: VoxelInstancer) -> void:
	_instancer = instancer
	instancer.child_entered_tree.connect(_on_entered)
	instancer.child_exiting_tree.connect(_on_exiting)
	for child in instancer.get_children():
		_on_entered(child)


## Cuerpos a [radius] m o menos de [center] (global).
func query(center: Vector3, radius: float) -> Array[Node3D]:
	_flush()
	var out: Array[Node3D] = []
	if not is_instance_valid(_instancer) or not _instancer.is_inside_tree():
		return out
	var local := _instancer.to_local(center)
	var reach := Vector3.ONE * radius
	var lo := _key(local - reach)
	var hi := _key(local + reach)
	var moved: Array[Node3D] = []
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var cell: Array = _cells.get(Vector3i(x, y, z), [])
				for i in range(cell.size() - 1, -1, -1):
					var body: Node3D = cell[i]
					if not is_instance_valid(body):
						cell.remove_at(i)
						continue
					if _key(body.position) != Vector3i(x, y, z):
						moved.append(body)
						continue
					if body.position.distance_to(local) <= radius:
						out.append(body)
	for body in moved:
		_remove(body)
		_insert(body)
		if body.position.distance_to(local) <= radius:
			out.append(body)
	return out


func _on_entered(node: Node) -> void:
	if node is Node3D:
		_pending.append(node)
		if not _flush_queued:
			_flush_queued = true
			_flush.call_deferred()


func _on_exiting(node: Node) -> void:
	if _cell_of.has(node.get_instance_id()):
		_remove(node as Node3D)
	else:
		_pending.erase(node)


func _flush() -> void:
	_flush_queued = false
	for body in _pending:
		if is_instance_valid(body) and body.is_inside_tree():
			_insert(body)
	_pending.clear()


func _insert(body: Node3D) -> void:
	var key := _key(body.position)
	if not _cells.has(key):
		_cells[key] = []
	(_cells[key] as Array).append(body)
	_cell_of[body.get_instance_id()] = key


func _remove(body: Node3D) -> void:
	var id := body.get_instance_id()
	var key: Variant = _cell_of.get(id)
	if key == null:
		return
	_cell_of.erase(id)
	var cell: Array = _cells.get(key, [])
	cell.erase(body)
	if cell.is_empty():
		_cells.erase(key)


static func _key(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))
