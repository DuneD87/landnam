class_name CreatureGrid

## Rejilla espacial de las criaturas con esqueleto (NPCController) en juego. La percepción y los
## avisos de manada preguntan por las que tienen cerca, en vez de recorrer el grupo "npc" entero:
## eso era todas contra todas, cada 0,2 s por criatura. Solo están las activas: las que vuelven al
## pool salen al desactivarse, y así nadie detecta a un depredador escondido donde se quedó.
## Las celdas se rehacen como mucho una vez por fotograma de física, con las posiciones de ese
## momento. No hay que seguir cada movimiento, y un rebase del origen flotante (que mueve a todas,
## también a las dormidas, que no corren su física) no deja celdas viejas.

## Lado de la celda (m). Las visiones van de 12 a 80 m: con 64, una consulta mira de 8 a 64 celdas.
const CELL := 64.0

static var _members: Array[NPCController] = []
static var _cells: Dictionary = {} # Vector3i -> Array[NPCController]
static var _built_frame: int = -1


static func add(creature: NPCController) -> void:
	if not _members.has(creature):
		_members.append(creature)
		_built_frame = -1


static func remove(creature: NPCController) -> void:
	var i := _members.find(creature)
	if i >= 0:
		_members.remove_at(i)
		_built_frame = -1


## Las criaturas de las celdas que toca la esfera de [radius] alrededor de [center]. Salen también
## algunas algo más lejos (las esquinas de las celdas), así que quien pregunta mide la distancia.
static func near(center: Vector3, radius: float) -> Array[NPCController]:
	_build()
	var found: Array[NPCController] = []
	var lo := _cell_of(center - Vector3.ONE * radius)
	var hi := _cell_of(center + Vector3.ONE * radius)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var cell: Variant = _cells.get(Vector3i(x, y, z))
				if cell != null:
					found.append_array(cell)
	return found


static func _build() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _built_frame:
		return
	_built_frame = frame
	_cells.clear()
	for creature in _members:
		var key := _cell_of(creature.global_position)
		var cell: Variant = _cells.get(key)
		if cell == null:
			var fresh: Array[NPCController] = [creature]
			_cells[key] = fresh
		else:
			cell.append(creature)


static func _cell_of(point: Vector3) -> Vector3i:
	return Vector3i((point / CELL).floor())
