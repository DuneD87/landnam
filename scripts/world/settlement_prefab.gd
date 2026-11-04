class_name SettlementPrefab extends Resource

## Una construcción de los poblados: un blueprint (el JSON de GridBlueprint.capture, guardado con el
## martillo o generado por tools/build_settlement_prefabs.tscn) y lo que el trazado del poblado necesita
## saber de él. La huella y el suelo salen del propio blueprint: su grid principal (la primera, la de
## más bloques) es la que se sube al terreno con un zócalo (SettlementLayout).

## Nombre corto y único: identifica la construcción en el plan y en sus grids (source_blueprint).
@export var id: StringName
## Para qué sirve ("house", "longhouse", "storage", "church"): lo que leerán los NPC del plan.
@export var kind: StringName = &"house"
## El blueprint.
@export_file("*.json") var blueprint_path: String
## Lado de la puerta en las celdas de la grid principal (±X o ±Z): el poblado lo gira hacia la plaza y
## le pone delante la rampa que haga falta.
@export var door: Vector3i = Vector3i(0, 0, 1)
## Celda (x, z) de la grid principal por la que se entra: la rampa sale de la de delante.
@export var door_cell: Vector2i = Vector2i.ZERO
## Material del zócalo y de la rampa.
@export var foundation_material: String = "stone"
## Los lechos de los vecinos (SettlementPopulation: uno por vecino): la pose de cada uno en la grid
## principal (m), en lo alto del suelo, con la cabecera hacia -Z. El poblado los pone (Bedroll sin
## guardar) y los aldeanos duermen en ellos (Villager).
@export var beds: Array[Transform3D] = []
## Sus sitios de trabajo (la leñera, el huerto, el banco): ver SettlementWorkplace.
@export var workplaces: Array[SettlementWorkplace] = []

static var _cache := {}


## El blueprint leído (se lee una vez por ruta). {} si no se puede.
func load_data() -> Dictionary:
	if _cache.has(blueprint_path):
		return _cache[blueprint_path]
	var data := {}
	var file := FileAccess.open(blueprint_path, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary and not (parsed.get("grids", []) as Array).is_empty():
			data = parsed
	if data.is_empty():
		push_warning("[settlements] no se puede leer el blueprint %s" % blueprint_path)
	_cache[blueprint_path] = data
	return data


## Lo que el trazado mide del blueprint: {"cell": lado de celda de la grid principal, "floor": sus
## celdas más bajas (Vector2i x, z), "floor_y": su altura en celdas, "min"/"max": la caja de todo el
## blueprint en metros (aleros y frontones incluidos) y de lo que ocupan sus sitios de trabajo de
## fuera}. {} si no hay blueprint.
func measure() -> Dictionary:
	var data := load_data()
	if data.is_empty():
		return {}
	var main: Dictionary = (data.grids as Array)[0]
	var cells := GridBlueprint.blocks_dict(main)
	var floor_y := 1 << 30
	for c: Vector3i in cells:
		floor_y = mini(floor_y, c.y)
	var floor_cells: Array[Vector2i] = []
	for c: Vector3i in cells:
		if c.y == floor_y:
			floor_cells.append(Vector2i(c.x, c.z))
	var lo := GridBase._array_to_vec3(data.get("bounds_min", [0, 0, 0]))
	var hi := GridBase._array_to_vec3(data.get("bounds_max", [0, 0, 0]))
	for work in workplaces:
		if work != null and not work.indoor:
			for corner in work.corners():
				lo = Vector3(minf(lo.x, corner.x), lo.y, minf(lo.z, corner.z))
				hi = Vector3(maxf(hi.x, corner.x), hi.y, maxf(hi.z, corner.z))
	return {"cell": float(main.get("cell_size", 1.0)), "floor": floor_cells, "floor_y": floor_y,
		"min": lo, "max": hi}
