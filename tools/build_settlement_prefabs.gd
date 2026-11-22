extends Node

## Genera los prefabs de los poblados: el blueprint de cada construcción (data/settlements/prefabs/<id>.json,
## en el formato de GridBlueprint.capture) y su ficha (<id>.tres, SettlementPrefab), y las plantillas de
## data/settlements/templates/ que falten (con --templates las rehace todas). Un blueprint hecho con el
## martillo sustituye a uno de estos copiando su JSON encima (y ajustando la puerta en la ficha).
##   godot --headless --path . res://tools/build_settlement_prefabs.tscn [-- --templates]
##
## Son casas de celdas de 1 m como la cabaña de tests/building/thatch_roof_preview.gd: suelo, paredes,
## tejado a dos aguas (faldones de paja, tejuelas o tepe) con la cumbrera a lo largo de X y frontones por
## fuera de las paredes de los extremos. Las paredes miden 3 m: con 2, el alero bajaba hasta el dintel y
## tapaba la puerta del lado largo. Las ventanas son paneles de cristal en la cara de fuera de la pared.
##
## El entramado y los marcos de puertas y ventanas son listones de fachada (BlockDatabase.BLOCK_BEAM_ID y
## la escuadra) en las celdas de fuera del muro, pegados a él: las líneas van por los cantos de las celdas
## (_frame). El decorado (barriles, mercancía, letreros...) son SettlementProp.
##
## Las puertas (wooden_door) se ponen como con el martillo: la casa se levanta en una grid de verdad, cada
## hoja se encaja con WoodenDoor.fit apuntando a su jamba desde fuera y el blueprint sale de
## GridBlueprint.capture, como al guardar uno. Por eso es una escena y no un script de -s: hacen falta los
## autoloads.

const DB := preload("res://scripts/autoload/block_database.gd")
const PREFAB_DIR := "res://data/settlements/prefabs/"
const TEMPLATE_DIR := "res://data/settlements/templates/"

const PREFABS := ["choza", "casa", "casa_tablas", "casa_turba", "casa_alta", "casa_larga", "granero", "tienda",
	"herreria", "puesto_comida", "puesto_pieles", "puesto_cacharros", "iglesia"]
## id, nombre, peso, principal, las demás, cuántas, plaza y corona (m), cerca.
const TEMPLATES := [
	["granja", "SETTLEMENT_FARM", 0.4, "casa", ["granero", "choza", "casa_turba", "casa_tablas"], 1, 3, 8.0, 10.0,
		&"fence"],
	["aldea", "SETTLEMENT_HAMLET", 0.4, "casa_larga", ["choza", "casa", "casa_tablas", "casa_turba", "granero",
		"herreria", "puesto_comida"], 4, 6, 10.0, 16.0, &"palisade"],
	["poblado", "SETTLEMENT_VILLAGE", 0.2, "iglesia", ["casa", "casa_alta", "casa_tablas", "casa_larga", "granero",
		"tienda", "herreria", "puesto_comida", "puesto_pieles", "puesto_cacharros", "casa_turba"], 8, 12, 15.0, 24.0,
		&"palisade"],
]

const BEAM := DB.BLOCK_BEAM_ID
const BEAM_L := DB.BLOCK_BEAM_L_ID
const BRACE := DB.BLOCK_BRACE_ID
const CUBE := DB.BLOCK_CUBE_ID
const SLAB := DB.BLOCK_SLAB_ID
## El material del entramado: tablas oscuras.
const TIMBER := "planks"


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
		var props: Array[SettlementProp] = []
		props.assign(b.get("props", []))
		prefab.props = props
		_save(prefab, PREFAB_DIR + id + ".tres")
		prefabs[id] = load(PREFAB_DIR + id + ".tres")
		print("%s: %d bloques, %d puertas, %s" % [id, int(data.block_count), int(data.prop_count),
			str(data.bounds_max)])
	# Los prefabs de antes que ya no se generan.
	for f in DirAccess.get_files_at(PREFAB_DIR):
		var id := f.get_basename()
		if not id in PREFABS and (f.ends_with(".json") or f.ends_with(".tres")):
			DirAccess.remove_absolute(PREFAB_DIR + f)
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
		template.wall = t[9]
		_save(template, path)
	get_tree().quit()


# --- Construcciones ------------------------------------------------------------------------------

## Choza de 6 × 5 de troncos con esquinas de piedra, tejado de tepe y frontones de tablas; la puerta en
## el frontón, enmarcada, y una ventana en cada pared.
func _choza() -> Dictionary:
	var b := {}
	var walls := func(x: int, _y: int, z: int) -> String:
		return "stone" if (x == 1 or x == 6) and (z == 1 or z == 5) else "wood"
	_house(b, 6, 5, 3, "wood", walls, "turf", "planks")
	_door(b, 6, 3)
	var windows := [Vector3i(3, 2, 1), Vector3i(4, 2, 5), Vector3i(1, 2, 3)]
	for cell in windows:
		_window(b, 6, 5, cell)
	for f in _facades(6, 5):
		_frame_openings(b, f, 3)
	return {"blocks": b, "kind": &"house", "door": Vector3i(1, 0, 0), "door_cell": Vector2i(6, 3),
		"leaves": [_leaf(Vector3i(6, 2, 2), Vector3i(0, 0, 1), Vector3.LEFT, Vector2i(1, 2))],
		"beds": _beds([Vector3(3.1, 1.0, 2.5), Vector3(3.1, 1.0, 4.5)], PI * 0.5),
		"workplaces": [_woodpile(Vector3(-0.5, 0.0, 3.5), -PI * 0.5)],
		"props": [_prop(&"barrel", Vector3(7.6, 0.0, 1.6), 0.0, true), _prop(&"sack", Vector3(5.5, 1.0, 2.4), 0.3),
			_prop(&"sack", Vector3(5.4, 1.0, 4.6), 1.2)]}


## Casa de 9 × 7 con entramado: muros enlucidos entre listones de tablas oscuras, tejado de paja, la
## puerta en el centro del lado largo entre dos ventanas, tres ventanas detrás, una en un frontón y la
## chimenea de piedra contra el otro.
func _casa() -> Dictionary:
	var b := {}
	var walls := func(_x: int, _y: int, _z: int) -> String: return "plaster"
	_house(b, 9, 7, 3, "wood", walls, "thatch", "plaster")
	_door(b, 5, 7)
	for x in [3, 7]:
		_window(b, 9, 7, Vector3i(x, 2, 7))
	for x in [3, 5, 7]:
		_window(b, 9, 7, Vector3i(x, 2, 1))
	_window(b, 9, 7, Vector3i(9, 2, 4))
	_gable_window(b, 10, 3, 5, 4)
	_chimney(b, 2, 4, 3 + 4 + 1)
	_half_timber(b, 9, 7, 3, 1)
	return {"blocks": b, "kind": &"house", "door": Vector3i(0, 0, 1), "door_cell": Vector2i(5, 7),
		"leaves": [_leaf(Vector3i(4, 2, 7), Vector3i(1, 0, 0), Vector3.FORWARD, Vector2i(1, 2))],
		"beds": _beds([Vector3(3.7, 1.0, 3.1), Vector3(7.0, 1.0, 3.1), Vector3(8.2, 1.0, 3.1)], 0.0),
		"workplaces": [_garden(Vector3(5.5, 0.0, -1.0), 0.0, Vector2(7.0, 3.0), 2)],
		"props": [_prop(&"barrel", Vector3(7.8, 0.0, 8.6), 0.0, true), _prop(&"crate", Vector3(2.3, 0.0, 8.7), 0.2, true),
			_prop(&"chest", Vector3(8.0, 1.0, 6.3), PI)]}


## Casa de tablas de 8 × 7: tablas oscuras con esquinas de piedra, tejado de tejuelas y frontones de
## tablas con un ventanuco; la puerta en el lado largo, enmarcada como las ventanas.
func _casa_tablas() -> Dictionary:
	var b := {}
	var walls := func(x: int, _y: int, z: int) -> String:
		return "stone" if (x == 1 or x == 8) and (z == 1 or z == 7) else "planks"
	_house(b, 8, 7, 3, "planks", walls, "shingles", "planks")
	_door(b, 3, 7)
	for x in [5, 7]:
		_window(b, 8, 7, Vector3i(x, 2, 7))
	for x in [2, 4, 6]:
		_window(b, 8, 7, Vector3i(x, 2, 1))
	_window(b, 8, 7, Vector3i(8, 2, 4))
	_gable_window(b, 0, 3, 5, 4)
	_gable_window(b, 9, 3, 5, 4)
	for f in _facades(8, 7):
		_frame_openings(b, f, 3)
	return {"blocks": b, "kind": &"house", "door": Vector3i(0, 0, 1), "door_cell": Vector2i(3, 7),
		"leaves": [_leaf(Vector3i(2, 2, 7), Vector3i(1, 0, 0), Vector3.FORWARD, Vector2i(1, 2))],
		"beds": _beds([Vector3(2.4, 1.0, 3.1), Vector3(5.0, 1.0, 3.1), Vector3(7.2, 1.0, 3.1)], 0.0),
		"workplaces": [_woodpile(Vector3(-0.5, 0.0, 4.0), -PI * 0.5)],
		"props": [_prop(&"hide_rack", Vector3(10.2, 0.0, 4.0), PI * 0.5, true),
			_prop(&"barrel", Vector3(5.5, 0.0, 8.7), 0.0, true), _prop(&"barrel", Vector3(6.2, 0.0, 8.8), 0.0, true)]}


## Casa de tepe de 8 × 7, a la islandesa: muros de piedra abajo y tepe encima, tejado de tepe y el
## frontón de delante todo de tablas, con la puerta en el centro y dos ventanas.
func _casa_turba() -> Dictionary:
	var b := {}
	var walls := func(x: int, y: int, _z: int) -> String:
		if x == 8:
			return "planks"
		return "stone" if y == 1 else "turf"
	_house(b, 8, 7, 3, "wood", walls, "turf", "planks")
	_door(b, 8, 4)
	for z in [2, 6]:
		_window(b, 8, 7, Vector3i(8, 2, z))
	_gable_window(b, 9, 3, 5, 4)
	var front: Dictionary = _facades(8, 7)[3]
	_frame(b, front, [0, 7], [1], 1, 3, false)
	_frame_openings(b, front, 3)
	return {"blocks": b, "kind": &"house", "door": Vector3i(1, 0, 0), "door_cell": Vector2i(8, 4),
		"leaves": [_leaf(Vector3i(8, 2, 3), Vector3i(0, 0, 1), Vector3.LEFT, Vector2i(1, 2))],
		"beds": _beds([Vector3(3.1, 1.0, 2.4), Vector3(3.1, 1.0, 4.4), Vector3(3.1, 1.0, 6.4)], PI * 0.5),
		"workplaces": [_garden(Vector3(4.5, 0.0, -1.0), 0.0, Vector2(6.0, 3.0), 1)],
		"props": [_prop(&"fish_rack", Vector3(4.5, 0.0, 9.6), 0.0, true), _prop(&"sack", Vector3(7.3, 1.0, 2.5), 0.5)]}


## Casa alta de 7 × 7 y dos plantas: abajo piedra, arriba enlucido con entramado; tejado de tejuelas.
## Dentro, una escalera de rampas de madera contra la pared del fondo sube al piso de tablas.
func _casa_alta() -> Dictionary:
	var b := {}
	var h := 6
	var walls := func(_x: int, y: int, _z: int) -> String: return "stone" if y <= 3 else "plaster"
	_house(b, 7, 7, h, "stone", walls, "shingles", "plaster")
	# El piso de arriba (su cara de arriba a 5 m) y el hueco de la escalera.
	for x in range(2, 7):
		for z in range(2, 7):
			_put(b, x, 4, z, CUBE, "planks")
	for k in 4:
		_put(b, 2 + k, 1 + k, 2, DB.BLOCK_SLOPE_ID, "wood", Basis(Vector3.UP, PI * 0.5))
		if k < 3:
			b.erase(_key(2 + k, 4, 2))
	_door(b, 4, 7)
	for x in [2, 6]:
		_window(b, 7, 7, Vector3i(x, 2, 7))
	for x in [2, 4, 6]:
		_window(b, 7, 7, Vector3i(x, 5, 7))
		_window(b, 7, 7, Vector3i(x, 5, 1))
	for z in [3, 5]:
		_window(b, 7, 7, Vector3i(1, 5, z))
		_window(b, 7, 7, Vector3i(7, 5, z))
	_window(b, 7, 7, Vector3i(7, 2, 4))
	_gable_window(b, 0, h, 8, 4)
	_gable_window(b, 8, h, 8, 4)
	_chimney(b, 6, 4, h + 4 + 1)
	_half_timber(b, 7, 7, h, 4)
	for f in _facades(7, 7):
		_frame_openings(b, f, 3)
	return {"blocks": b, "kind": &"house", "door": Vector3i(0, 0, 1), "door_cell": Vector2i(4, 7),
		"leaves": [_leaf(Vector3i(3, 2, 7), Vector3i(1, 0, 0), Vector3.FORWARD, Vector2i(1, 2))],
		"beds": _beds([Vector3(3.1, 1.0, 5.4), Vector3(5.6, 1.0, 4.0), Vector3(5.6, 1.0, 5.4)], PI * 0.5),
		"props": [_prop(&"barrel", Vector3(1.5, 0.0, 8.6), 0.0, true), _prop(&"crate", Vector3(2.3, 5.0, 4.0), 0.3)]}


## Casa larga de 17 × 7: zócalo de piedra y troncos, tejado de tejuelas y frontones de tablas; la puerta
## en el centro del lado largo con su marco, y una hilera de ventanas pequeñas a cada lado.
func _casa_larga() -> Dictionary:
	var b := {}
	var walls := func(x: int, y: int, z: int) -> String:
		return "stone" if y == 1 or ((x == 1 or x == 17) and (z == 1 or z == 7)) else "wood"
	_house(b, 17, 7, 3, "wood", walls, "shingles", "planks")
	_door(b, 9, 7)
	for x in [3, 6, 9, 12, 15]:
		_window(b, 17, 7, Vector3i(x, 2, 1))
	for x in [3, 6, 12, 15]:
		_window(b, 17, 7, Vector3i(x, 2, 7))
	for x in [1, 17]:
		_window(b, 17, 7, Vector3i(x, 2, 4))
	_gable_window(b, 0, 3, 5, 4)
	_gable_window(b, 18, 3, 5, 4)
	for f in _facades(17, 7):
		_frame_openings(b, f, 3)
	return {"blocks": b, "kind": &"longhouse", "door": Vector3i(0, 0, 1), "door_cell": Vector2i(9, 7),
		"leaves": [_leaf(Vector3i(8, 2, 7), Vector3i(1, 0, 0), Vector3.FORWARD, Vector2i(1, 2))],
		"beds": _beds([Vector3(3.0, 1.0, 3.1), Vector3(4.2, 1.0, 3.1), Vector3(5.4, 1.0, 3.1),
			Vector3(13.6, 1.0, 3.1), Vector3(14.8, 1.0, 3.1), Vector3(16.0, 1.0, 3.1)], 0.0),
		"workplaces": [_bench(Vector3(9.5, 1.0, 2.3), 0.0), _woodpile(Vector3(13.5, 0.0, -0.5), PI)],
		"props": [_prop(&"barrel", Vector3(7.4, 0.0, 8.7), 0.0, true), _prop(&"barrel", Vector3(10.6, 0.0, 8.7), 0.0, true),
			_prop(&"crate", Vector3(16.3, 1.0, 6.2), 0.2), _prop(&"chest", Vector3(2.7, 1.0, 6.3), PI)]}


## Granero de 7 × 5 de tablas con zócalo y esquinas de piedra, suelo de piedra y tejado de paja; el
## portón de tres celdas en el frontón (una hoja de 3 × 2), un ventanuco a cada lado y otro arriba detrás.
func _granero() -> Dictionary:
	var b := {}
	var walls := func(x: int, y: int, z: int) -> String:
		return "stone" if y == 1 or ((x == 1 or x == 7) and (z == 1 or z == 5)) else "planks"
	_house(b, 7, 5, 3, "stone", walls, "thatch", "planks")
	for z in [2, 3, 4]:
		_door(b, 7, z)
	for z in [1, 5]:
		_window(b, 7, 5, Vector3i(4, 2, z))
	_gable_window(b, 0, 3, 4, 3)
	for f in _facades(7, 5):
		_frame_openings(b, f, 3)
	return {"blocks": b, "kind": &"storage", "door": Vector3i(1, 0, 0), "door_cell": Vector2i(7, 3),
		"leaves": [_leaf(Vector3i(7, 2, 1), Vector3i(0, 0, 1), Vector3.LEFT, Vector2i(3, 2))],
		"workplaces": [_bench(Vector3(2.3, 1.0, 3.5), PI * 0.5)],
		"props": [_prop(&"sack", Vector3(5.6, 1.0, 2.4), 0.0), _prop(&"sack", Vector3(6.2, 1.0, 2.5), 0.8),
			_prop(&"sack", Vector3(5.9, 1.0, 4.6), 2.0), _prop(&"crate", Vector3(3.6, 1.0, 2.5), 0.1),
			_prop(&"crate", Vector3(3.6, 1.0, 4.6), 0.0)]}


## Tienda de 9 × 7 con entramado y tejado de tejuelas: en el lado largo de delante, un mostrador de
## tres celdas abierto a la calle (la pared de abajo hace de mostrador), con la mercancía encima, y la
## puerta del tendero al lado; el letrero, en el frontón. Dentro, cajas, barriles y sacos.
func _tienda() -> Dictionary:
	var b := {}
	var walls := func(_x: int, _y: int, _z: int) -> String: return "plaster"
	_house(b, 9, 7, 3, "planks", walls, "shingles", "plaster")
	# El mostrador: el hueco de arriba de la pared, de tres celdas.
	for x in [4, 5, 6]:
		b.erase(_key(x, 2, 7))
	_door(b, 8, 7)
	_window(b, 9, 7, Vector3i(2, 2, 7))
	for x in [3, 7]:
		_window(b, 9, 7, Vector3i(x, 2, 1))
	for x in [1, 9]:
		_window(b, 9, 7, Vector3i(x, 2, 4))
	_gable_window(b, 0, 3, 5, 4)
	_half_timber(b, 9, 7, 3, 1)
	var goods := [&"waterskin", &"torch_01", &"bedroll", &"fishing_rod"]
	var props := [_prop(&"sign", Vector3(10.0, 3.3, 5.6), PI * 0.5, false, &"waterskin"),
		_prop(&"crate", Vector3(2.6, 1.0, 2.5), 0.0), _prop(&"crate", Vector3(2.6, 1.55, 2.5), 0.4),
		_prop(&"barrel", Vector3(3.6, 1.0, 2.5), 0.0), _prop(&"sack", Vector3(7.6, 1.0, 2.4), 0.0),
		_prop(&"sack", Vector3(8.3, 1.0, 2.6), 1.0), _prop(&"chest", Vector3(6.0, 1.0, 2.4), 0.0),
		_prop(&"barrel", Vector3(3.0, 0.0, 8.6), 0.0, true)]
	for i in goods.size():
		var shown := _prop(&"goods", Vector3(4.2 + i * 0.85, 2.0, 7.5), 0.3 * i, false, goods[i])
		shown.scale = 1.4
		props.append(shown)
	return {"blocks": b, "kind": &"shop", "door": Vector3i(0, 0, 1), "door_cell": Vector2i(8, 7),
		"leaves": [_leaf(Vector3i(7, 2, 7), Vector3i(1, 0, 0), Vector3.FORWARD, Vector2i(1, 2))],
		"beds": _beds([Vector3(3.1, 1.0, 3.6), Vector3(7.0, 1.0, 3.6)], PI * 0.5),
		"workplaces": [_seller(&"shop", Vector3(5.5, 1.0, 6.2), Vector3(5.5, 1.0, 8.0))],
		"props": props}


## Herrería de 7 × 5 abierta por delante: tres muros de piedra, el frente con dos pilares en las esquinas
## y el dintel, tejado de tejuelas. Dentro, la fragua contra el fondo bajo la chimenea, el yunque delante,
## un barril para templar y el letrero en el frontón.
func _herreria() -> Dictionary:
	var b := {}
	var walls := func(_x: int, _y: int, _z: int) -> String: return "stone"
	_house(b, 7, 5, 3, "stone", walls, "shingles", "planks")
	for x in range(2, 7):
		_door(b, x, 5)
	_chimney(b, 4, 1, 3 + 3 + 2)
	_window(b, 7, 5, Vector3i(1, 2, 3))
	return {"blocks": b, "kind": &"smithy", "door": Vector3i(0, 0, 1), "door_cell": Vector2i(4, 5),
		"workplaces": [_smith(Vector3(4.5, 1.0, 3.4), Vector3(4.5, 1.0, 4.3))],
		"props": [_prop(&"forge", Vector3(4.5, 1.0, 2.35), 0.0), _prop(&"anvil", Vector3(4.5, 1.0, 4.3), 0.0),
			_prop(&"barrel", Vector3(6.3, 1.0, 4.4), 0.0), _prop(&"crate", Vector3(2.4, 1.0, 2.2), 0.2),
			_prop(&"goods", Vector3(2.4, 1.55, 2.2), 0.6, false, &"bronze_ingot"),
			_prop(&"sign", Vector3(8.0, 3.3, 3.5), PI * 0.5, false, &"bronze_axe")]}


func _puesto_comida() -> Dictionary:
	return _stall(&"stall_food", [&"raw_fish", &"cooked_fish", &"cooked_meat", &"raw_fish", &"raw_meat"],
		[_prop(&"barrel", Vector3(0.45, 1.0, 0.45), 0.0), _prop(&"fish_rack", Vector3(1.5, 0.0, -1.3), 0.0, true)])


func _puesto_pieles() -> Dictionary:
	return _stall(&"stall_hides", [&"fur_mittens", &"antler", &"fur_moccasins", &"sinew", &"fur_hood"],
		[_prop(&"hide_rack", Vector3(1.5, 1.0, 0.12), 0.0), _prop(&"sack", Vector3(2.6, 1.0, 0.45), 0.4)])


func _puesto_cacharros() -> Dictionary:
	return _stall(&"stall_wares", [&"waterskin", &"flint_knife", &"torch_01", &"bone", &"fishing_hook"],
		[_prop(&"crate", Vector3(0.5, 1.0, 0.45), 0.2), _prop(&"crate", Vector3(0.5, 1.55, 0.45), 0.6),
			_prop(&"sack", Vector3(2.5, 1.0, 0.5), 0.0)])


## Puesto de mercadillo de 3 × 3: suelo de tablas, un mostrador de dos losas en la fila del medio con la
## mercancía [goods] y el paso entre ellas, cuatro postes en las esquinas y un toldo de lona a dos aguas.
## [props]: lo de detrás, en metros desde la esquina del suelo. El que vende ([kind]) atiende detrás del
## mostrador. El suelo empieza en x = 1 como el de las casas: el blueprint se guarda con su caja desde 0,
## y los frontones del toldo van en x = 0 y x = 4.
func _stall(kind: StringName, goods: Array, props: Array) -> Dictionary:
	var b := {}
	for x in range(1, 4):
		for z in range(0, 3):
			_put(b, x, 0, z, CUBE, "planks")
	for x in [1, 3]:
		_put(b, x, 1, 1, SLAB, "planks")
	# Postes en las esquinas de fuera, hasta el toldo.
	for corner: Vector3i in [Vector3i(1, 0, 0), Vector3i(3, 0, 0), Vector3i(1, 0, 2), Vector3i(3, 0, 2)]:
		var sx := -1 if corner.x == 1 else 1
		var sz := -1 if corner.z == 0 else 1
		for y in [1, 2]:
			if not b.has(_key(corner.x, y, corner.z)):
				_corner_post(b, Vector3i(corner.x, y, corner.z), sx, sz)
	# El toldo: dos faldones de lona y la tira de arriba, con los extremos cerrados por triángulos.
	for x in range(1, 4):
		_put(b, x, 3, 0, DB.BLOCK_PANE_SLOPE_ID, "cloth")
		_put(b, x, 3, 2, DB.BLOCK_PANE_SLOPE_ID, "cloth", Basis(Vector3.UP, PI))
		_put(b, x, 4, 1, DB.BLOCK_PANE_ID, "cloth", Basis(Vector3.RIGHT, -PI * 0.5))
	for x in [0, 4]:
		var facing := _gable_facing(x)
		var rising := facing if x != 0 else facing * Basis(Vector3.BACK, PI * 0.5)
		var falling := facing * Basis(Vector3.BACK, PI * 0.5) if x != 0 else facing
		_put(b, x, 3, 0, DB.BLOCK_PANE_TRIANGLE_ID, "cloth", rising)
		_put(b, x, 3, 2, DB.BLOCK_PANE_TRIANGLE_ID, "cloth", falling)
		_put(b, x, 3, 1, DB.BLOCK_PANE_ID, "cloth", facing)
	var all: Array = []
	for prop: SettlementProp in props:
		prop.pose.origin.x += 1.0
		all.append(prop)
	for i in goods.size():
		var x := (1.2 + i * 0.3) if i < 3 else (3.3 + (i - 3) * 0.4)
		var shown := _prop(&"goods", Vector3(x, 1.5, 1.45 + (i % 2) * 0.2), 0.6 * i, false, goods[i])
		shown.scale = 1.5
		all.append(shown)
	return {"blocks": b, "kind": &"stall", "door": Vector3i(0, 0, 1), "door_cell": Vector2i(2, 2),
		"workplaces": [_seller(kind, Vector3(2.5, 1.0, 0.65), Vector3(2.5, 1.0, 3.5))], "props": all}


## Iglesia de madera: nave de 13 × 7 de tablas oscuras sobre un zócalo de sillería, paredes de 5 m,
## tejado de tejuelas, ventanales de dos celdas, el altar al fondo bajo una ventana y una vidriera en el
## frontón; delante, el campanario de tablas con la entrada (una puerta de tres celdas de alto), los
## vanos de las campanas, un chapitel de tejuelas y la cruz.
func _iglesia() -> Dictionary:
	var b := {}
	var length := 13
	var depth := 7
	var height := 5
	var walls := func(x: int, y: int, z: int) -> String:
		return "ashlar" if y == 1 or ((x == 1 or x == length) and (z == 1 or z == depth)) else "planks"
	_house(b, length, depth, height, "ashlar", walls, "shingles", "planks")
	for x in [3, 6, 9, 12]:
		for z in [1, depth]:
			for y in [2, 3]:
				_window(b, length, depth, Vector3i(x, y, z))
	for y in [3, 4]:
		_window(b, length, depth, Vector3i(1, y, 4))
	for y in [height + 1, height + 2]:
		_gable_window(b, 0, height, y, 4)
	for z in [3, 4, 5]:
		_put(b, 2, 1, z, CUBE, "ashlar")
	_door(b, length, 4)
	for f in _facades(length, depth):
		_frame_openings(b, f, height)

	# El campanario, pegado al frontón de la entrada: tapa esa parte del frontón.
	var x0 := length + 1
	var top := height + (depth + 1) / 2 + 3
	for x in range(x0, x0 + 3):
		for z in range(3, 6):
			_put(b, x, 0, z, CUBE, "ashlar")
			if x == x0 + 1 and z == 4:
				continue
			for y in range(1, top + 1):
				_put(b, x, y, z, CUBE, "ashlar" if y == 1 else "planks")
	_door(b, x0, 4)
	_door(b, x0 + 2, 4, 3)
	for y in [top - 1, top]:
		for cell in [Vector2i(x0, 4), Vector2i(x0 + 2, 4), Vector2i(x0 + 1, 3), Vector2i(x0 + 1, 5)]:
			b.erase(_key(cell.x, y, cell.y))
	# Chapitel de tejuelas: rampas por los lados y esquinas con el pico hacia dentro, y encima la cruz.
	var cap := top + 1
	_put(b, x0 + 1, cap, 4, CUBE, "planks")
	for side in [[Vector2i(x0 + 1, 3), 0.0], [Vector2i(x0 + 1, 5), PI], [Vector2i(x0, 4), PI * 0.5],
			[Vector2i(x0 + 2, 4), -PI * 0.5]]:
		_put(b, side[0].x, cap, side[0].y, DB.BLOCK_SLOPE_ID, "shingles", Basis(Vector3.UP, side[1]))
	for corner in [[Vector2i(x0, 3), PI * 0.5], [Vector2i(x0 + 2, 3), 0.0], [Vector2i(x0 + 2, 5), -PI * 0.5],
			[Vector2i(x0, 5), PI]]:
		_put(b, corner[0].x, cap, corner[0].y, DB.BLOCK_CORNER_ID, "shingles", Basis(Vector3.UP, corner[1]))
	_put(b, x0 + 1, cap + 1, 4, DB.BLOCK_POST_ID, "wood")
	# El marco de la entrada del campanario.
	var tower := {"n": Vector3i(1, 0, 0), "a": Vector3i(0, 0, -1), "start": Vector3i(x0 + 2, 0, 5), "width": 3}
	_frame_openings(b, tower, 4)
	return {"blocks": b, "kind": &"church", "door": Vector3i(1, 0, 0), "door_cell": Vector2i(x0 + 2, 4),
		"leaves": [_leaf(Vector3i(x0 + 2, 2, 3), Vector3i(0, 0, 1), Vector3.LEFT, Vector2i(1, 3))],
		"props": [_prop(&"cross", Vector3(x0 + 1.5, cap + 2.0, 4.5), PI * 0.5)]}


# --- Piezas --------------------------------------------------------------------------------------

## Suelo de [floor_mat], paredes y tejado de una casa de [length] × [depth] celdas de suelo (depth impar)
## con paredes de [height]: [walls] da el material de cada celda de pared (x, y, z); [roof], el de los
## faldones y la cumbrera ("thatch", "shingles" o "turf"); [gable], el de los frontones. Ocupa de 0 a
## length + 1 en X (los frontones van por fuera de las paredes de los extremos) y de 0 a depth + 1 en Z
## (los aleros).
static func _house(b: Dictionary, length: int, depth: int, height: int, floor_mat: String, walls: Callable,
		roof := "thatch", gable := "wood") -> void:
	var ridge := (depth + 1) / 2
	for x in range(1, length + 1):
		for z in range(1, depth + 1):
			_put(b, x, 0, z, CUBE, floor_mat)
			if x == 1 or x == length or z == 1 or z == depth:
				for y in range(1, height + 1):
					_put(b, x, y, z, CUBE, walls.call(x, y, z))
		# Faldones de abajo arriba hasta la cumbrera; el de enfrente girado 180°.
		for k in ridge:
			_put(b, x, height + k, k, DB.BLOCK_THATCH_SLOPE_ID, roof)
			_put(b, x, height + k, depth + 1 - k, DB.BLOCK_THATCH_SLOPE_ID, roof, Basis(Vector3.UP, PI))
		_put(b, x, height + ridge, ridge, DB.BLOCK_THATCH_RIDGE_ID, roof)
	# Frontones en las celdas de fuera de las paredes de los extremos, como en la cabaña de prueba: el
	# triángulo cierra cada faldón y los cuadrados rellenan el centro.
	for x in [0, length + 1]:
		var rising := _gable_facing(x) if x != 0 else _gable_facing(x) * Basis(Vector3.BACK, PI * 0.5)
		var falling := _gable_facing(x) * Basis(Vector3.BACK, PI * 0.5) if x != 0 else _gable_facing(x)
		for k in range(1, ridge):
			_put(b, x, height + k, k, DB.BLOCK_PANE_TRIANGLE_ID, gable, rising)
			_put(b, x, height + k, depth + 1 - k, DB.BLOCK_PANE_TRIANGLE_ID, gable, falling)
			for z in range(k + 1, depth + 1 - k):
				_put(b, x, height + k, z, DB.BLOCK_PANE_ID, gable, _gable_facing(x))


## Las cuatro fachadas de una casa de [length] × [depth]: {"n": hacia fuera, "a": hacia la derecha de
## quien la mira desde fuera, "start": la celda de pared de su izquierda (y = 0), "width": celdas}. La
## columna u de la fachada es start + a · u; la de fuera, una más hacia n. Orden: -Z, +Z, -X, +X.
static func _facades(length: int, depth: int) -> Array[Dictionary]:
	return [
		{"n": Vector3i(0, 0, -1), "a": Vector3i(-1, 0, 0), "start": Vector3i(length, 0, 1), "width": length},
		{"n": Vector3i(0, 0, 1), "a": Vector3i(1, 0, 0), "start": Vector3i(1, 0, depth), "width": length},
		{"n": Vector3i(-1, 0, 0), "a": Vector3i(0, 0, 1), "start": Vector3i(1, 0, 1), "width": depth},
		{"n": Vector3i(1, 0, 0), "a": Vector3i(0, 0, -1), "start": Vector3i(length, 0, depth), "width": depth},
	]


## El giro de las piezas de fachada de [f]: su -Z contra el muro y su -X a la izquierda.
static func _facade_basis(f: Dictionary) -> Basis:
	return Basis(Vector3(f.a), Vector3.UP, Vector3(f.n))


## Entramado en las fachadas de una casa de [length] × [depth] con paredes de [height], desde la fila
## [from]: postes en las esquinas y cada dos o tres celdas, la solera abajo, un travesaño a media altura
## y riostras bajo el de arriba en los frontones; y el marco de cada puerta y ventana.
static func _half_timber(b: Dictionary, length: int, depth: int, height: int, from: int) -> void:
	var faces := _facades(length, depth)
	for i in faces.size():
		var f := faces[i]
		var w: int = f.width
		var lines: Array = [0, w]
		var step := 2 if w <= 7 else 3
		for u in range(step, w - 1, step):
			lines.append(u)
		var gable := i >= 2
		# Los largos acaban bajo el alero (la fila height de fuera es el faldón); los frontones, arriba.
		var last := height if gable else height - 1
		var rails: Array = [from, last] if gable and last - from >= 2 else [from, from + 1]
		_frame(b, f, lines, rails, from, last, gable)
		_frame_openings(b, f, height)


## Listones en la fachada [f]: líneas de pie en los cantos [lines] (u, de 0 a width) y tumbadas en los
## cantos de abajo de las filas [rails], en las filas [from]..[to]. Con [braces], una riostra bajo cada
## travesaño de arriba, a la izquierda de cada línea de pie. No se pisa nada ni se pone delante de un
## hueco de puerta.
static func _frame(b: Dictionary, f: Dictionary, lines: Array, rails: Array, from: int, to: int, braces: bool) -> void:
	var w: int = f.width
	var basis := _facade_basis(f)
	var rail_basis := basis * Basis(Vector3.BACK, PI * 0.5)
	for y in range(from, to + 1):
		for u in range(0, w + 1):
			var wall: Vector3i = f.start + f.a * u + Vector3i(0, y, 0)
			var out: Vector3i = wall + f.n
			if b.has(_key(out.x, out.y, out.z)):
				continue
			var in_wall := u < w
			var door := in_wall and _is_gap(b, wall)
			var vertical: bool = u in lines and not door
			var rail: bool = y in rails and in_wall and not door
			if vertical and rail:
				_put(b, out.x, out.y, out.z, BEAM_L, TIMBER, basis)
			elif vertical:
				_put(b, out.x, out.y, out.z, BEAM, TIMBER, basis)
			elif rail:
				_put(b, out.x, out.y, out.z, BEAM, TIMBER, rail_basis)
			elif braces and in_wall and not door and (y + 1) in rails and (u + 1) in lines and y + 1 <= to \
					and not _is_window(b, wall) and y > from:
				# De la esquina de arriba a la izquierda (en el travesaño) a la de abajo a la derecha.
				_put(b, out.x, out.y, out.z, BRACE, TIMBER, basis * Basis(Vector3.BACK, PI * 0.5))


## Marcos de las puertas y ventanas de la fachada [f] (paredes de [height]): jambas a los dos lados (la
## de la derecha, reflejada), peana y dintel. Lo que ya esté puesto se respeta.
static func _frame_openings(b: Dictionary, f: Dictionary, height: int) -> void:
	var w: int = f.width
	var basis := _facade_basis(f)
	var rail_basis := basis * Basis(Vector3.BACK, PI * 0.5)
	for u in range(0, w):
		for y in range(1, height + 1):
			var wall: Vector3i = f.start + f.a * u + Vector3i(0, y, 0)
			var door := _is_gap(b, wall)
			if not door and not _is_window(b, wall):
				continue
			# Jamba izquierda: el canto derecho de la celda de al lado, si es muro.
			var left: Vector3i = wall - f.a
			if u > 0 and _is_solid_wall(b, left):
				_put_if_free(b, left + f.n, BEAM, TIMBER, basis, 0)
			var right: Vector3i = wall + f.a
			if u < w - 1 and _is_solid_wall(b, right):
				_put_if_free(b, right + f.n, BEAM, TIMBER, basis)
			# Dintel: el canto de abajo de la celda de encima; peana (solo ventanas): la de la propia celda.
			var above: Vector3i = wall + Vector3i.UP
			if _is_solid_wall(b, above):
				_put_if_free(b, above + f.n, BEAM, TIMBER, rail_basis)
			var below: Vector3i = wall - Vector3i.UP
			if not door and not _is_gap(b, below) and not _is_window(b, below):
				_put_if_free(b, wall + f.n, BEAM, TIMBER, rail_basis)


## Pone la pieza si la celda está libre; [mirror] refleja su eje local (0: X, el listón pasa al canto
## derecho).
static func _put_if_free(b: Dictionary, c: Vector3i, id: int, mat: String, rot: Basis, mirror := -1) -> void:
	if not b.has(_key(c.x, c.y, c.z)):
		_put(b, c.x, c.y, c.z, id, mat, rot, mirror)


## Si la celda de pared [c] está vacía (un hueco de puerta o de mostrador).
static func _is_gap(b: Dictionary, c: Vector3i) -> bool:
	return c.y >= 1 and not b.has(_key(c.x, c.y, c.z))


static func _is_window(b: Dictionary, c: Vector3i) -> bool:
	var info: Dictionary = b.get(_key(c.x, c.y, c.z), {})
	return info.get("material_id", "") == "glass"


static func _is_solid_wall(b: Dictionary, c: Vector3i) -> bool:
	var info: Dictionary = b.get(_key(c.x, c.y, c.z), {})
	return int(info.get("block_id", -1)) == CUBE and info.get("material_id", "") != "glass"


## Un poste de esquina (el listón) en la celda [c], en su esquina ([sx], [sz]) de fuera (-1 o 1).
static func _corner_post(b: Dictionary, c: Vector3i, sx: int, sz: int) -> void:
	if sx < 0 and sz < 0:
		_put(b, c.x, c.y, c.z, BEAM, TIMBER)
	elif sx > 0 and sz > 0:
		_put(b, c.x, c.y, c.z, BEAM, TIMBER, Basis(Vector3.UP, PI))
	elif sx > 0:
		_put(b, c.x, c.y, c.z, BEAM, TIMBER, Basis.IDENTITY, 0)
	else:
		_put(b, c.x, c.y, c.z, BEAM, TIMBER, Basis.IDENTITY, 2)


## Lechos en [centers] (m de la grid, en lo alto del suelo), con la cabecera (-Z del lecho) girada
## [yaw] alrededor de +Y: 0 hacia -Z, PI / 2 hacia -X.
static func _beds(centers: Array, yaw: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for c: Vector3 in centers:
		out.append(Transform3D(Basis(Vector3.UP, yaw), c))
	return out


## Un adorno (SettlementProp) de [kind] en [at] (m de la grid; con [grounded], en el terreno de fuera),
## girado [yaw]; [item]: la mercancía o la seña del letrero.
static func _prop(kind: StringName, at: Vector3, yaw: float, grounded := false, item := &"") -> SettlementProp:
	var p := SettlementProp.new()
	p.kind = kind
	p.pose = Transform3D(Basis(Vector3.UP, yaw), at)
	p.grounded = grounded
	p.item = item
	return p


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


## El que vende ([kind]: tienda o puesto) de pie en [stand] mirando a [look] (m de la grid, en lo alto
## del suelo), sin nada que se vea: el mostrador y la mercancía son de la casa.
static func _seller(kind: StringName, stand: Vector3, look: Vector3) -> SettlementWorkplace:
	var w := SettlementWorkplace.new()
	w.kind = kind
	w.pose = Transform3D(Basis.IDENTITY, stand)
	w.indoor = true
	w.size = Vector2(1.0, 1.0)
	w.stands = PackedVector3Array([Vector3.ZERO])
	w.looks = PackedVector3Array([look - stand])
	return w


## El herrero de pie en [stand] golpeando en el yunque de [anvil] (m de la grid, en lo alto del suelo).
static func _smith(stand: Vector3, anvil: Vector3) -> SettlementWorkplace:
	var w := _seller(&"forge", stand, anvil)
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
## altura [y] y en la fila [z]: un cuadrado de cristal en vez del panel.
static func _gable_window(b: Dictionary, x: int, height: int, y: int, z: int) -> void:
	if y > height:
		_put(b, x, y, z, DB.BLOCK_PANE_ID, "glass", _gable_facing(x))


## Chimenea de piedra en la columna (x, z) desde el suelo hasta [top], atravesando la cumbrera.
static func _chimney(b: Dictionary, x: int, z: int, top: int) -> void:
	for y in range(1, top + 1):
		_put(b, x, y, z, CUBE, "stone")


## Pone un bloque en [b] (las claves y el formato de GridBlueprint), con el giro redondeado; [mirror]:
## el eje local que se refleja (-1 ninguno).
static func _put(b: Dictionary, x: int, y: int, z: int, id: int, material: String, rot := Basis.IDENTITY,
		mirror := -1) -> void:
	var basis := []
	for axis in [rot.x, rot.y, rot.z]:
		for i in 3:
			basis.append(snappedf(axis[i], 0.000001))
	var info := {"block_id": id, "material_id": material, "rotation_basis": basis}
	if mirror >= 0:
		info.mirrored = true
		info.mirror_axis = mirror
	b[_key(x, y, z)] = info


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
