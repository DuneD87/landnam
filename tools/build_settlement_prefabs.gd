extends Node

## Genera los prefabs provisionales de los poblados: el blueprint de cada construcción
## (data/settlements/prefabs/<id>.json, en el formato de GridBlueprint.capture) y su ficha (<id>.tres,
## SettlementPrefab), y las plantillas de data/settlements/templates/ que falten (con --templates las
## rehace todas). Un blueprint hecho con el martillo sustituye a uno de estos copiando su JSON encima (y
## ajustando la puerta en la ficha).
##   godot --headless --path . res://tools/build_settlement_prefabs.tscn [-- --templates]
##
## Son casas de celdas de 1 m como la cabaña de tests/building/thatch_roof_preview.gd: suelo, paredes,
## tejado de paja a dos aguas con la cumbrera a lo largo de X y frontones de madera por fuera de las
## paredes de los extremos. Las paredes miden 3 m: con 2, el alero bajaba hasta el dintel y tapaba la
## puerta del lado largo. Las ventanas son paneles de cristal en la cara de fuera de la pared.
##
## Las puertas (wooden_door) se ponen como con el martillo: la casa se levanta en una grid de verdad, cada
## hoja se encaja con WoodenDoor.fit apuntando a su jamba desde fuera y el blueprint sale de
## GridBlueprint.capture, como al guardar uno. Por eso es una escena y no un script de -s: hacen falta los
## autoloads.

const DB := preload("res://scripts/autoload/block_database.gd")
const PREFAB_DIR := "res://data/settlements/prefabs/"
const TEMPLATE_DIR := "res://data/settlements/templates/"

const PREFABS := ["choza", "casa", "casa_larga", "granero", "iglesia"]
## id, nombre, peso, principal, las demás, cuántas, plaza y corona (m).
const TEMPLATES := [
	["granja", "SETTLEMENT_FARM", 0.4, "casa", ["granero", "choza"], 1, 2, 8.0, 10.0],
	["aldea", "SETTLEMENT_HAMLET", 0.4, "casa_larga", ["choza", "choza", "casa", "granero"], 3, 5, 10.0, 14.0],
	["poblado", "SETTLEMENT_VILLAGE", 0.2, "iglesia", ["choza", "casa", "casa", "casa_larga", "granero"], 6, 9,
		14.0, 22.0],
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(PREFAB_DIR)
	DirAccess.make_dir_recursive_absolute(TEMPLATE_DIR)
	var prefabs := {}
	for id: String in PREFABS:
		var b: Dictionary = call("_" + id)
		var data := _capture(b)
		if data.is_empty():
			push_error("%s: no se pudo montar" % id)
			continue
		var path: String = PREFAB_DIR + id + ".json"
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(data))
		file.close()
		var prefab := SettlementPrefab.new()
		prefab.id = StringName(id)
		prefab.kind = b.kind
		prefab.blueprint_path = path
		prefab.door = b.door
		prefab.door_cell = b.door_cell
		prefab.beds = b.get("beds", [] as Array[Transform3D])
		var work: Array[SettlementWorkplace] = []
		work.assign(b.get("workplaces", []))
		prefab.workplaces = work
		_save(prefab, PREFAB_DIR + id + ".tres")
		prefabs[id] = load(PREFAB_DIR + id + ".tres")
		print("%s: %d bloques, %d puertas, %s" % [id, int(data.block_count), int(data.prop_count),
			str(data.bounds_max)])
	var redo := "--templates" in OS.get_cmdline_user_args()
	for t in TEMPLATES:
		var path: String = TEMPLATE_DIR + t[0] + ".tres"
		if FileAccess.file_exists(path) and not redo:
			continue
		var template := SettlementTemplate.new()
		template.id = StringName(t[0])
		template.display_name = t[1]
		template.weight = t[2]
		template.center = prefabs[t[3]]
		var pool: Array[SettlementPrefab] = []
		for id: String in t[4]:
			pool.append(prefabs[id])
		template.buildings = pool
		template.count_min = t[5]
		template.count_max = t[6]
		template.plaza_radius = t[7]
		template.ring_depth = t[8]
		_save(template, path)
	get_tree().quit()


## Choza de 6 × 5 con esquinas de piedra, la puerta en el frontón y una ventana en cada pared.
func _choza() -> Dictionary:
	var b := {}
	var corners := func(x: int, _y: int, z: int) -> String:
		return "stone" if (x == 1 or x == 6) and (z == 1 or z == 5) else "wood"
	_house(b, 6, 5, 3, "wood", corners)
	_door(b, 6, 3)
	for cell in [Vector3i(3, 2, 1), Vector3i(4, 2, 5), Vector3i(1, 2, 3)]:
		_window(b, 6, 5, cell)
	# Dos lechos a lo largo, con la cabecera contra la pared del fondo, a los lados del paso.
	return {"blocks": b, "kind": &"house", "door": Vector3i(1, 0, 0), "door_cell": Vector2i(6, 3),
		"leaves": [_leaf(Vector3i(6, 2, 2), Vector3i(0, 0, 1), Vector3.LEFT, Vector2i(1, 2))],
		"beds": _beds([Vector3(3.1, 1.0, 2.5), Vector3(3.1, 1.0, 4.5)], PI * 0.5),
		# La leñera contra el frontón de atrás.
		"workplaces": [_woodpile(Vector3(-0.5, 0.0, 3.5), -PI * 0.5)]}


## Casa de 9 × 7: zócalo y esquinas de piedra, la puerta en el centro del lado largo entre dos ventanas,
## tres ventanas detrás, una en un frontón y la chimenea de piedra contra el otro.
func _casa() -> Dictionary:
	var b := {}
	var walls := func(x: int, y: int, z: int) -> String:
		return "stone" if y == 1 or ((x == 1 or x == 9) and (z == 1 or z == 7)) else "wood"
	_house(b, 9, 7, 3, "wood", walls)
	_door(b, 5, 7)
	for x in [3, 7]:
		_window(b, 9, 7, Vector3i(x, 2, 7))
	for x in [3, 5, 7]:
		_window(b, 9, 7, Vector3i(x, 2, 1))
	_window(b, 9, 7, Vector3i(9, 2, 4))
	_gable_window(b, 10, 3, 5, 4)
	_chimney(b, 2, 4, 3 + 4 + 1)
	# Tres lechos contra la pared del fondo, apartados de la chimenea.
	return {"blocks": b, "kind": &"house", "door": Vector3i(0, 0, 1), "door_cell": Vector2i(5, 7),
		"leaves": [_leaf(Vector3i(4, 2, 7), Vector3i(1, 0, 0), Vector3.FORWARD, Vector2i(1, 2))],
		"beds": _beds([Vector3(3.7, 1.0, 3.1), Vector3(7.0, 1.0, 3.1), Vector3(8.2, 1.0, 3.1)], 0.0),
		# El huerto detrás, a lo largo de la casa.
		"workplaces": [_garden(Vector3(5.5, 0.0, -1.0), 0.0, Vector2(7.0, 3.0), 2)]}


## Casa larga de 17 × 7 de piedra, con la puerta en el centro del lado largo enmarcada en madera y una
## hilera de ventanas pequeñas a cada lado.
func _casa_larga() -> Dictionary:
	var b := {}
	var walls := func(x: int, y: int, z: int) -> String:
		# El marco de la puerta: las jambas y el dintel.
		if z == 7 and ((absi(x - 9) == 1 and y <= 3) or (x == 9 and y == 3)):
			return "wood"
		return "stone"
	_house(b, 17, 7, 3, "stone", walls)
	_door(b, 9, 7)
	for x in [3, 6, 9, 12, 15]:
		_window(b, 17, 7, Vector3i(x, 2, 1))
	for x in [3, 6, 12, 15]:
		_window(b, 17, 7, Vector3i(x, 2, 7))
	for x in [1, 17]:
		_window(b, 17, 7, Vector3i(x, 2, 4))
	# Seis lechos contra la pared del fondo, tres a cada lado de la puerta.
	return {"blocks": b, "kind": &"longhouse", "door": Vector3i(0, 0, 1), "door_cell": Vector2i(9, 7),
		"leaves": [_leaf(Vector3i(8, 2, 7), Vector3i(1, 0, 0), Vector3.FORWARD, Vector2i(1, 2))],
		"beds": _beds([Vector3(3.0, 1.0, 3.1), Vector3(4.2, 1.0, 3.1), Vector3(5.4, 1.0, 3.1),
			Vector3(13.6, 1.0, 3.1), Vector3(14.8, 1.0, 3.1), Vector3(16.0, 1.0, 3.1)], 0.0),
		# El banco contra la pared del fondo, entre los lechos, y la leñera detrás.
		"workplaces": [_bench(Vector3(9.5, 1.0, 2.3), 0.0), _woodpile(Vector3(13.5, 0.0, -0.5), PI)]}


## Granero de 7 × 5 con suelo de piedra, el portón de tres celdas en el frontón (una hoja de 3 × 2), un
## ventanuco a cada lado y otro arriba en el frontón de atrás.
func _granero() -> Dictionary:
	var b := {}
	var walls := func(x: int, y: int, z: int) -> String:
		return "stone" if y == 1 or ((x == 1 or x == 7) and (z == 1 or z == 5)) else "wood"
	_house(b, 7, 5, 3, "stone", walls)
	for z in [2, 3, 4]:
		_door(b, 7, z)
	for z in [1, 5]:
		_window(b, 7, 5, Vector3i(4, 2, z))
	_gable_window(b, 0, 3, 4, 3)
	# El banco contra el frontón del fondo, de cara al portón.
	return {"blocks": b, "kind": &"storage", "door": Vector3i(1, 0, 0), "door_cell": Vector2i(7, 3),
		"leaves": [_leaf(Vector3i(7, 2, 1), Vector3i(0, 0, 1), Vector3.LEFT, Vector2i(3, 2))],
		"workplaces": [_bench(Vector3(2.3, 1.0, 3.5), PI * 0.5)]}


## Iglesia: nave de piedra de 13 × 7 con paredes de 5 m, ventanales de dos celdas, el altar al fondo bajo
## una ventana y una vidriera en el frontón; delante, el campanario de 3 × 3 con la entrada (una puerta de
## tres celdas de alto), los vanos de las campanas arriba, un chapitel de piedra y la cruz.
func _iglesia() -> Dictionary:
	var b := {}
	var length := 13
	var depth := 7
	var height := 5
	var stone := func(_x: int, _y: int, _z: int) -> String: return "stone"
	_house(b, length, depth, height, "stone", stone)
	for x in [3, 6, 9, 12]:
		for z in [1, depth]:
			for y in [2, 3]:
				_window(b, length, depth, Vector3i(x, y, z))
	for y in [3, 4]:
		_window(b, length, depth, Vector3i(1, y, 4))
	for y in [height + 1, height + 2]:
		_gable_window(b, 0, height, y, 4)
	for z in [3, 4, 5]:
		_put(b, 2, 1, z, DB.BLOCK_CUBE_ID, "stone")
	_door(b, length, 4)

	# El campanario, pegado al frontón de la entrada: tapa esa parte del frontón.
	var x0 := length + 1
	var top := height + (depth + 1) / 2 + 3
	for x in range(x0, x0 + 3):
		for z in range(3, 6):
			_put(b, x, 0, z, DB.BLOCK_CUBE_ID, "stone")
			if x == x0 + 1 and z == 4:
				continue
			for y in range(1, top + 1):
				_put(b, x, y, z, DB.BLOCK_CUBE_ID, "stone")
	_door(b, x0, 4)
	_door(b, x0 + 2, 4, 3)
	for y in [top - 1, top]:
		for cell in [Vector2i(x0, 4), Vector2i(x0 + 2, 4), Vector2i(x0 + 1, 3), Vector2i(x0 + 1, 5)]:
			b.erase(_key(cell.x, y, cell.y))
	# Chapitel: rampas por los lados y esquinas con el pico hacia dentro, y la cruz encima.
	var cap := top + 1
	_put(b, x0 + 1, cap, 4, DB.BLOCK_CUBE_ID, "stone")
	for side in [[Vector2i(x0 + 1, 3), 0.0], [Vector2i(x0 + 1, 5), PI], [Vector2i(x0, 4), PI * 0.5],
			[Vector2i(x0 + 2, 4), -PI * 0.5]]:
		_put(b, side[0].x, cap, side[0].y, DB.BLOCK_SLOPE_ID, "stone", Basis(Vector3.UP, side[1]))
	for corner in [[Vector2i(x0, 3), PI * 0.5], [Vector2i(x0 + 2, 3), 0.0], [Vector2i(x0 + 2, 5), -PI * 0.5],
			[Vector2i(x0, 5), PI]]:
		_put(b, corner[0].x, cap, corner[0].y, DB.BLOCK_CORNER_ID, "stone", Basis(Vector3.UP, corner[1]))
	for y in range(cap + 1, cap + 4):
		_put(b, x0 + 1, y, 4, DB.BLOCK_CUBE_ID, "wood")
	for z in [3, 5]:
		_put(b, x0 + 1, cap + 2, z, DB.BLOCK_CUBE_ID, "wood")
	return {"blocks": b, "kind": &"church", "door": Vector3i(1, 0, 0), "door_cell": Vector2i(x0 + 2, 4),
		"leaves": [_leaf(Vector3i(x0 + 2, 2, 3), Vector3i(0, 0, 1), Vector3.LEFT, Vector2i(1, 3))]}


## Suelo de [floor_mat], paredes y tejado de una casa de [length] × [depth] celdas de suelo (depth impar)
## con paredes de [height]: [walls] da el material de cada celda de pared (x, y, z). Ocupa de 0 a
## length + 1 en X (los frontones van por fuera de las paredes de los extremos) y de 0 a depth + 1 en Z
## (los aleros).
static func _house(b: Dictionary, length: int, depth: int, height: int, floor_mat: String, walls: Callable) -> void:
	var ridge := (depth + 1) / 2
	for x in range(1, length + 1):
		for z in range(1, depth + 1):
			_put(b, x, 0, z, DB.BLOCK_CUBE_ID, floor_mat)
			if x == 1 or x == length or z == 1 or z == depth:
				for y in range(1, height + 1):
					_put(b, x, y, z, DB.BLOCK_CUBE_ID, walls.call(x, y, z))
		# Faldones de abajo arriba hasta la cumbrera; el de enfrente girado 180°.
		for k in ridge:
			_put(b, x, height + k, k, DB.BLOCK_THATCH_SLOPE_ID, "thatch")
			_put(b, x, height + k, depth + 1 - k, DB.BLOCK_THATCH_SLOPE_ID, "thatch", Basis(Vector3.UP, PI))
		_put(b, x, height + ridge, ridge, DB.BLOCK_THATCH_RIDGE_ID, "thatch")
	# Frontones en las celdas de fuera de las paredes de los extremos, como en la cabaña de prueba: el
	# triángulo cierra cada faldón y los cuadrados rellenan el centro.
	for x in [0, length + 1]:
		var rising := _gable_facing(x) if x != 0 else _gable_facing(x) * Basis(Vector3.BACK, PI * 0.5)
		var falling := _gable_facing(x) * Basis(Vector3.BACK, PI * 0.5) if x != 0 else _gable_facing(x)
		for k in range(1, ridge):
			_put(b, x, height + k, k, DB.BLOCK_PANE_TRIANGLE_ID, "wood", rising)
			_put(b, x, height + k, depth + 1 - k, DB.BLOCK_PANE_TRIANGLE_ID, "wood", falling)
			for z in range(k + 1, depth + 1 - k):
				_put(b, x, height + k, z, DB.BLOCK_PANE_ID, "wood", _gable_facing(x))


## Lechos en [centers] (m de la grid, en lo alto del suelo), con la cabecera (-Z del lecho) girada
## [yaw] alrededor de +Y: 0 hacia -Z, PI / 2 hacia -X.
static func _beds(centers: Array, yaw: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for c: Vector3 in centers:
		out.append(Transform3D(Basis(Vector3.UP, yaw), c))
	return out


## Leñera (SettlementDecor.woodpile): la pila de troncos a lo largo de X de su pose, detrás (-Z), el
## tajo delante y el leñador más allá, mirándolo. [at]: su centro a ras de suelo (m de la grid);
## [yaw]: el giro que lleva su -Z (la pila) hacia la pared.
static func _woodpile(at: Vector3, yaw: float) -> SettlementWorkplace:
	var w := SettlementWorkplace.new()
	w.kind = &"woodpile"
	w.pose = Transform3D(Basis(Vector3.UP, yaw), at)
	w.size = Vector2(2.6, 3.2)
	w.stands = PackedVector3Array([Vector3(0.0, 0.0, 1.25)])
	w.looks = PackedVector3Array([Vector3(0.0, 0.0, 0.45)])
	return w


## Huerto de [size] (m) centrado en [at] (a ras de suelo) y girado [yaw], con surcos a lo largo de X y
## [workers] granjeros entre ellos, mirando a lo largo del surco.
static func _garden(at: Vector3, yaw: float, size: Vector2, workers: int) -> SettlementWorkplace:
	var w := SettlementWorkplace.new()
	w.kind = &"garden"
	w.pose = Transform3D(Basis(Vector3.UP, yaw), at)
	w.size = size
	for i in workers:
		var x := lerpf(-size.x * 0.5 + 1.0, size.x * 0.5 - 1.0, (i + 0.5) / workers)
		var z := 0.5 if i % 2 == 0 else -0.5
		w.stands.append(Vector3(x, 0.0, z))
		w.looks.append(Vector3(x + 1.0, 0.0, z))
	return w


## Banco de trabajo (el de la edad de piedra, con el lado de trabajo a +Z) en el suelo de la casa: su
## centro en [at] (m de la grid, en lo alto del suelo), girado [yaw]; el artesano delante.
static func _bench(at: Vector3, yaw: float) -> SettlementWorkplace:
	var w := SettlementWorkplace.new()
	w.kind = &"bench"
	w.pose = Transform3D(Basis(Vector3.UP, yaw), at)
	w.indoor = true
	w.size = Vector2(1.3, 0.6)
	w.stands = PackedVector3Array([Vector3(0.0, 0.0, 0.75)])
	w.looks = PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	return w


## Giro de los paneles del frontón de la celda [x] (0 o length + 1): a la cara que da a la pared.
static func _gable_facing(x: int) -> Basis:
	return Basis(Vector3.UP, -PI * 0.5 if x == 0 else PI * 0.5)


## Hueco de puerta de [height] celdas de alto en la pared, en la columna (x, z).
static func _door(b: Dictionary, x: int, z: int, height := 2) -> void:
	for y in range(1, height + 1):
		b.erase(_key(x, y, z))


## Una hoja de puerta de [cells] (ancho, alto) con las bisagras en la jamba [jamb], apuntada en su cara
## [face] (hacia el hueco) mirando hacia [view]: desde fuera, para que quede a ras de fuera.
static func _leaf(jamb: Vector3i, face: Vector3i, view: Vector3, cells: Vector2i) -> Dictionary:
	return {"jamb": jamb, "face": face, "view": view, "cells": cells}


## Ventana: un panel de cristal en la cara de fuera de la celda de pared [cell] de una casa de
## [length] × [depth] (el panel va de serie en la cara -Z de su celda).
static func _window(b: Dictionary, length: int, depth: int, cell: Vector3i) -> void:
	var rot := Basis.IDENTITY
	if cell.z == depth:
		rot = Basis(Vector3.UP, PI)
	elif cell.x == 1:
		rot = Basis(Vector3.UP, PI * 0.5)
	elif cell.x == length:
		rot = Basis(Vector3.UP, -PI * 0.5)
	_put(b, cell.x, cell.y, cell.z, DB.BLOCK_PANE_ID, "glass", rot)


## Ventana en el frontón de la celda [x] (0 o length + 1) de una casa con paredes de [height], a la
## altura [y] y en la fila [z]: un cuadrado de cristal en vez de madera.
static func _gable_window(b: Dictionary, x: int, height: int, y: int, z: int) -> void:
	if y > height:
		_put(b, x, y, z, DB.BLOCK_PANE_ID, "glass", _gable_facing(x))


## Chimenea de piedra en la columna (x, z) desde el suelo hasta [top], atravesando la cumbrera.
static func _chimney(b: Dictionary, x: int, z: int, top: int) -> void:
	for y in range(1, top + 1):
		_put(b, x, y, z, DB.BLOCK_CUBE_ID, "stone")


## Pone un bloque en [b] (las claves y el formato de GridBlueprint), con el giro redondeado.
static func _put(b: Dictionary, x: int, y: int, z: int, id: int, material: String, rot := Basis.IDENTITY) -> void:
	var basis := []
	for axis in [rot.x, rot.y, rot.z]:
		for i in 3:
			basis.append(snappedf(axis[i], 0.000001))
	b[_key(x, y, z)] = {"block_id": id, "material_id": material, "rotation_basis": basis}


static func _key(x: int, y: int, z: int) -> String:
	return "%d,%d,%d" % [x, y, z]


## El blueprint de la construcción [b] ({"blocks", "leaves"}) como lo guardaría el martillo: se levanta
## en una grid, se le ponen las puertas como las pondría el jugador y se captura. {} si alguna no cabe.
func _capture(b: Dictionary) -> Dictionary:
	var planet := Node3D.new()
	add_child(planet)
	var grids := GridBlueprint.instantiate(_blueprint(b.blocks), planet, Vector3.ZERO, Basis.IDENTITY, true)
	var grid: GridBase = grids[0]
	var ok := true
	for leaf: Dictionary in b.get("leaves", []):
		var jamb: Vector3i = leaf.jamb
		var face: Vector3i = leaf.face
		var aim := (Vector3(jamb) + Vector3.ONE * 0.5 + Vector3(face) * 0.5) * grid.cell_size
		var fit := WoodenDoor.fit(grid, jamb, face, aim, leaf.view, leaf.cells, true)
		if fit.is_empty() or not fit.ok:
			push_error("la puerta de la jamba %s no cabe" % jamb)
			ok = false
			continue
		ok = grid.place_prop(jamb, face, DoorDesign.DOOR, fit.transform, {"hinge": fit.hinge,
			"cell": grid.cell_size, "width": leaf.cells.x, "height": leaf.cells.y}) and ok
	var data := GridBlueprint.capture(grids)
	# Sin la fecha: el blueprint solo cambia si cambia la construcción (va en la firma de la caché).
	data.erase("created")
	for g: GridBase in grids:
		GridManager.remove_grid(g.grid_id)
	planet.queue_free()
	return data if ok else {}


## El blueprint de los bloques [b] (de una sola grid de celdas de 1 m), con su caja.
static func _blueprint(b: Dictionary) -> Dictionary:
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := -lo
	for key: String in b:
		var p := key.split(",")
		var c := Vector3i(int(p[0]), int(p[1]), int(p[2]))
		lo = lo.min(c)
		hi = hi.max(c)
	return {"version": 1, "dynamic": false, "bounds_min": [lo.x, lo.y, lo.z],
		"bounds_max": [hi.x + 1, hi.y + 1, hi.z + 1], "block_count": b.size(), "prop_count": 0,
		"grids": [{"cell_size": 1.0, "blocks": b, "materials": {}, "props": []}]}


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("no se pudo guardar %s: %s" % [path, error_string(err)])
