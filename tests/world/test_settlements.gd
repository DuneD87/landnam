extends Node

## Los poblados (SettlementSites, SettlementLayout, SettlementField, SettlementManager) sin el planeta:
## los prefabs y su puerta, las puntas sueltas y los sitios junto a unas sendas inventadas, el trazado sobre un llano, una
## ladera, un risco y el mar, la imagen del claro y lo que aparta de los árboles, la caché, y el gestor
## levantando y quitando casas con las grids de verdad: que no se guardan, que al tocarlas pasan a la
## partida y que una partida cargada no las cuenta como tocadas; y su gente (Villager).
##   godot --headless --path . res://tests/world/test_settlements.tscn

const RADIUS := 30000.0
const GROUND := 120.0
const LAT := 40.0
const LON := 20.0

var failures := 0
var origin: Vector3
var east: Vector3
var north: Vector3
## Pendiente del relieve inventado hacia el este (desnivel / distancia).
var slope := 0.0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	var lat := deg_to_rad(LAT)
	var lon := deg_to_rad(LON)
	origin = Vector3(cos(lat) * cos(lon), sin(lat), -cos(lat) * sin(lon))
	east = Vector3(-sin(lon), 0.0, -cos(lon))
	north = origin.cross(east).normalized()

	_check_prefabs()
	_check_sites()
	_check_layout()
	_check_clearance()
	await _check_manager()
	await _check_villagers()
	print("SETTLEMENT TESTS: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check_prefabs() -> void:
	var templates := SettlementField.load_templates()
	check(templates.size() >= 3, "hay plantillas (%d)" % templates.size())
	var seen := {}
	for t in templates:
		var prefabs: Array = [t.center]
		prefabs.append_array(t.buildings)
		for p: SettlementPrefab in prefabs:
			if p == null or seen.has(p.id):
				continue
			seen[p.id] = true
			var m := p.measure()
			var blocks := GridBlueprint.blocks_dict((p.load_data().grids as Array)[0])
			var floor_y: int = m.floor_y
			var door := Vector3i(p.door_cell.x, floor_y, p.door_cell.y)
			var gap := not blocks.has(door + Vector3i.UP) and not blocks.has(door + Vector3i.UP * 2)
			var outside := door + Vector3i(p.door.x, 0, p.door.z)
			check(not (m.floor as Array).is_empty() and blocks.has(door) and gap and not blocks.has(outside),
				"%s: suelo, hueco de puerta de dos celdas sobre él y nada delante" % p.id)
			# Lo que tenía mal la primera tanda: el alero a la altura de la cabeza delante de la puerta.
			check(not blocks.has(outside + Vector3i.UP) and not blocks.has(outside + Vector3i.UP * 2),
				"%s: delante de la puerta no hay tejado hasta los 2 m" % p.id)
			var reach := _walkable_from(blocks, door, floor_y)
			check(reach >= (m.floor as Array).size() * 0.3,
				"%s: desde la puerta se entra andando (%d de %d celdas de suelo)" % [p.id, reach, (m.floor as Array).size()])
			var windows := 0
			var outward := true
			for c: Vector3i in blocks:
				var info: Dictionary = blocks[c]
				if info.material_id != "glass":
					continue
				windows += 1
				# El panel va en la cara -Z de su celda: girado, tiene que dar a fuera (sin suelo).
				if blocks.has(Vector3i(c.x, floor_y, c.z)):
					var face: Vector3 = (info.rotation_basis as Basis) * Vector3(0, 0, -1)
					var beyond := Vector3i(c.x + roundi(face.x), floor_y, c.z + roundi(face.z))
					if blocks.has(beyond):
						outward = false
			check(windows >= 2 and outward, "%s: %d paneles de ventana, todos por fuera" % [p.id, windows])
			# La hoja de la puerta (wooden_door) cierra el hueco de la puerta, de pie y hasta el suelo.
			var closes := false
			for prop: Dictionary in (p.load_data().grids as Array)[0].get("props", []):
				if StringName(prop.item_id) != DoorDesign.DOOR:
					continue
				var size := DoorDesign.cells(DoorDesign.normalize(prop.state, DoorDesign.DOOR))
				var slots := WoodenDoor.slot_cells(GridBase._array_to_transform(prop.local_transform), size, m.cell)
				closes = closes or (slots.has(door + Vector3i.UP) and slots.has(door + Vector3i.UP * 2))
			check(closes, "%s: una puerta cierra el hueco de la entrada" % p.id)
	check(SettlementField.signature(templates) == SettlementField.signature(templates),
		"la firma de las plantillas es estable")


## Cuántas celdas de suelo se alcanzan andando desde [door]: con suelo debajo y dos celdas libres encima.
func _walkable_from(blocks: Dictionary, door: Vector3i, floor_y: int) -> int:
	var seen := {door: true}
	var open: Array[Vector3i] = [door]
	while not open.is_empty():
		var c: Vector3i = open.pop_back()
		for step in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n: Vector3i = c + step
			if seen.has(n) or not blocks.has(n) or n.y != floor_y:
				continue
			if blocks.has(n + Vector3i.UP) or blocks.has(n + Vector3i.UP * 2):
				continue
			seen[n] = true
			open.append(n)
	return seen.size()


## Una senda que sigue (de oeste a este), otra que acaba en ella y un ramal que acaba suelto.
func _check_sites() -> void:
	var main := _line(Vector2(-900, 0), Vector2(1800, 0))
	var branch := _line(Vector2(100, 600), Vector2(0, -600))
	var spur := _line(Vector2(-400, -100), Vector2(0, -500))
	var ends := SettlementSites.dead_ends([main, branch, spur], RADIUS)
	var tips: Array = []
	for e: Dictionary in ends:
		tips.append(_local(e.dir))
	# Puntas sueltas: las dos de la que sigue, la de arriba de la que llega y la de abajo del ramal (la
	# de arriba del ramal está a 100 m de la que sigue: también es suelta).
	var bottom := false
	var into_ok := false
	for i in ends.size():
		if (tips[i] as Vector2).distance_to(Vector2(-400, -600)) < 1.0:
			bottom = true
			var into: Vector3 = ends[i].into
			into_ok = into.dot(-north) > 0.99
	check(bottom and into_ok, "la punta suelta del ramal, con la senda siguiendo hacia el sur")
	var at_main := false
	for t: Vector2 in tips:
		if t.distance_to(Vector2(100, 0)) < 1.0:
			at_main = true
	check(not at_main and ends.size() == 5, "la punta que acaba en otra senda no cuenta (%d puntas)" % ends.size())

	# A un lado de la senda, uno cada 400 m: en la que sigue a -696, -300 y 504 (el de 100 cae en el
	# cruce), uno en la que llega y otro en el ramal.
	var road := SettlementSites.roadside([main, branch, spur], RADIUS, 400.0, 14.0)
	var axes := [[Vector2(-900, 0), Vector2(900, 0)], [Vector2(100, 600), Vector2(100, 0)],
		[Vector2(-400, -100), Vector2(-400, -600)]]
	var beside := true
	var sides := {}
	for r: Dictionary in road:
		var q := _local(r.dir)
		var foot := Vector2.INF
		for axis: Array in axes:
			var f := Geometry2D.get_closest_point_to_segment(q, axis[0], axis[1])
			if q.distance_to(f) < q.distance_to(foot):
				foot = f
		var out := (q - foot).normalized()
		var into := Vector2((r.into as Vector3).dot(east), (r.into as Vector3).dot(north))
		var alt := _local(r.alt.dir)
		beside = beside and absf(q.distance_to(foot) - 14.0) < 0.5 and into.dot(out) > 0.99 \
			and alt.distance_to(foot * 2.0 - q) < 0.5 and foot.distance_to(Vector2(100, 0)) > 150.0
		sides[signf(out.x + out.y)] = true
	check(road.size() == 5 and beside and sides.size() == 2,
		"junto a la senda: %d sitios a 14 m del eje, mirando hacia fuera, a los dos lados y lejos del cruce" % road.size())

	var chances := PackedFloat32Array()
	chances.resize(40)
	chances.fill(0.33)
	var a := SettlementSites.roll(chances, 7)
	var b := SettlementSites.roll(chances, 7)
	var none_first := chances.duplicate()
	for i in 10:
		none_first[i] = 0.0
	var later := PackedInt32Array()
	for i in a:
		if i >= 10:
			later.append(i)
	check(a == b and a.size() > 2 and a.size() < 30 and SettlementSites.roll(none_first, 7) == later,
		"el sorteo es siempre el mismo, de unos pocos, y la suerte de un sitio no depende de los de antes (%d de 40)" % a.size())
	var dirs: Array = []
	for i in 40:
		dirs.append(_dir(Vector2(i * 300.0, 0)))
	var kept := SettlementSites.space(dirs, RADIUS, 1000.0)
	var spaced := kept.size() > 0 and kept[0] == 0
	for i in 40:
		# Queda si no hay otro de los que quedan antes que él a menos de la separación.
		var blocked := false
		for j in kept:
			if j < i and (i - j) * 300.0 < 1000.0:
				blocked = true
		spaced = spaced and ((i in kept) != blocked)
	check(spaced and kept.size() == 10, "los primeros mandan y quedan separados (%d de 40)" % kept.size())


func _check_layout() -> void:
	var cfg := {"radius": RADIUS, "sea_radius": RADIUS + 50.0, "max_slope": 0.25, "max_step": 3.0}
	var site := {"dir": _dir(Vector2.ZERO), "into": north}
	var measures := _measures()
	var road := func(dir: Vector3) -> float:
		var p := _local(dir)
		return absf(p.x) if p.y < 0.0 else p.length()
	for s in [0.0, 0.12]:
		slope = s
		var center := SettlementLayout.find_center(site, _ground, cfg)
		check(not center.is_empty() and _local(center.dir).y > 0.0,
			"con pendiente %.2f hay plaza, más allá de la punta" % s)
		for t in SettlementField.load_templates():
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			var plan := SettlementLayout.plan(t, center, north, measures, _ground, road, cfg, rng)
			check(not plan.is_empty() and (plan.buildings as Array).size() >= mini(t.count_min + 1, 4),
				"%s con pendiente %.2f: %d construcciones" % [t.id, s, (plan.get("buildings", []) as Array).size()])
			if plan.is_empty():
				continue
			_check_plan(plan, t, measures, s)
	slope = 0.6
	check(SettlementLayout.find_center(site, _ground, cfg).is_empty(), "en un risco no hay plaza")
	slope = 0.0
	var wet := cfg.duplicate()
	wet.sea_radius = RADIUS + GROUND + 10.0
	check(SettlementLayout.find_center(site, _ground, wet).is_empty(), "bajo el mar no hay plaza")


## Que [plan] no solape, mire a la plaza, deje libre la llegada y apoye en el suelo.
func _check_plan(plan: Dictionary, t: SettlementTemplate, measures: Dictionary, s: float) -> void:
	var buildings: Array = plan.buildings
	var centers: Array = []
	var facing := true
	var grounded := true
	var footed := true
	var free_entry := true
	var c := _local(plan.center)
	for b: Dictionary in buildings:
		var m: Dictionary = measures[b.prefab]
		var basis: Basis = b.basis
		var o: Vector3 = b.origin
		var cell: float = m.cell
		var mid := o + basis * Vector3((m.min.x + m.max.x) * 0.5, 0.0, (m.min.z + m.max.z) * 0.5)
		centers.append(_local(mid.normalized()))
		var door := _local((b.door as Vector3).normalized())
		var to_center: Vector2 = (c - _local(mid.normalized())).normalized()
		facing = facing and (door - _local(mid.normalized())).normalized().dot(to_center) > 0.7
		if (_local(mid.normalized()) - c).normalized().dot(Vector2(0, -1)) > cos(deg_to_rad(30.0)):
			free_entry = false
		# La cara de arriba del suelo, sobre el terreno y a menos de un escalón de lo más alto.
		var top := -INF
		var floor_m := (int(m.floor_y) + 1) * cell
		for f: Vector2i in m.floor:
			var p := o + basis * Vector3((f.x + 0.5) * cell, floor_m, (f.y + 0.5) * cell)
			var above: float = p.length() - _ground.call(p.normalized())
			top = maxf(top, -above)
			if above < 0.0:
				grounded = false
		if -top > 0.55:
			grounded = false
		# El pie de cada columna de zócalo, bajo el terreno.
		var extra: PackedInt32Array = b.extra
		var lowest := {}
		for i in range(0, extra.size(), 5):
			var k := Vector2i(extra[i], extra[i + 2])
			lowest[k] = mini(lowest.get(k, 1 << 20), extra[i + 1])
		for k: Vector2i in lowest:
			var p := o + basis * Vector3((k.x + 0.5) * cell, lowest[k] * cell, (k.y + 0.5) * cell)
			if p.length() > _ground.call(p.normalized()):
				footed = false
	var apart := true
	for i in centers.size():
		for j in range(i + 1, centers.size()):
			if (centers[i] as Vector2).distance_to(centers[j]) < 4.0:
				apart = false
	check(apart and facing and free_entry, "%s (%.2f): separadas, con la puerta a la plaza y la llegada libre" % [t.id, s])
	check(grounded and footed, "%s (%.2f): el suelo a menos de un escalón sobre el terreno y el zócalo dentro de él" % [t.id, s])
	check(float(plan.extent) > t.plaza_radius and float(plan.extent) < t.plaza_radius + t.ring_depth + 30.0,
		"%s (%.2f): ocupa %.0f m" % [t.id, s, plan.extent])


func _check_clearance() -> void:
	var field := {"radius": RADIUS, "villages": [{"center": _dir(Vector2.ZERO), "extent": 30.0}]}
	var img := SettlementField.clearance_image(field, 10.0)
	var inside := SettlementField.clearance_distance(img, _dir(Vector2(0, 0)))
	var edge := SettlementField.clearance_distance(img, _dir(Vector2(40, 0)))
	var edge2 := SettlementField.clearance_distance(img, _dir(Vector2(0, -40)))
	var far := SettlementField.clearance_distance(img, _dir(Vector2(200, 0)))
	check(inside < -20.0 and absf(edge) < 14.0 and absf(edge2) < 14.0 and far >= SettlementField.CLEAR_FAR - 1.0,
		"la imagen del claro: dentro %.1f, en el borde %.1f y %.1f, lejos %.1f" % [inside, edge, edge2, far])
	var density := VoxelGraphFunction.new()
	density.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
	density.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
	density.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
	var one := density.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2())
	density.set_node_param(one, 0, 1.0)
	var out := density.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2())
	density.set_node_name(out, "density")
	density.add_connection(one, 0, out, 0)
	density.set("input_definitions", [["x", "InputX", 0], ["y", "InputY", 0], ["z", "InputZ", 0]])
	density.set("output_definitions", [["density", "CustomOutput", 0]])
	var cleared := SettlementField.clear_vegetation(density, img, RADIUS)
	var at_center := _density_at(cleared, _dir(Vector2(5, 5)))
	var away := _density_at(cleared, _dir(Vector2(150, 0)))
	check(at_center < 0.05 and away > 0.95, "los árboles no brotan en el poblado (%.2f) y sí lejos (%.2f)" % [at_center, away])

	var path := "user://test_settlements.bin"
	SettlementField.save_to(field, path, "clave")
	var back := SettlementField.load_from(path, "clave")
	check(not back.is_empty() and (back.villages as Array).size() == 1 and SettlementField.load_from(path, "otra").is_empty(),
		"la caché vuelve con su clave y no con otra")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## El gestor con un poblado en un llano: levanta, no guarda, quita, y al tocar una casa es de la partida.
func _check_manager() -> void:
	slope = 0.0
	var cfg := {"radius": RADIUS, "sea_radius": RADIUS - 50.0, "max_slope": 0.25, "max_step": 3.0}
	var template := SettlementField.template(&"aldea")
	var center := SettlementLayout.find_center({"dir": _dir(Vector2.ZERO), "into": north}, _ground, cfg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var road := func(_d: Vector3) -> float: return 100.0
	var plan := SettlementLayout.plan(template, center, north, _measures(), _ground, road, cfg, rng)
	var field := {"radius": RADIUS, "villages": [plan]}
	var count := (plan.buildings as Array).size()

	var planet := Node3D.new()
	add_child(planet)
	var terrain := Node3D.new()
	planet.add_child(terrain)
	var player := Node3D.new()
	add_child(player)
	var manager := SettlementManager.new()
	manager.entity_id = "test_settlements"
	add_child(manager)
	manager.setup(planet, terrain, player, field, {"load_distance": 300.0, "unload_distance": 500.0,
		"villager_distance": 0.0})
	var center_world: Vector3 = (plan.center as Vector3) * (RADIUS + GROUND)
	var before := GridManager.get_all_grids().size()

	player.global_position = center_world + origin * 2.0
	await _settle(manager)
	var built := manager.get_built()
	var meshed := true
	for key: String in built:
		for grid: GridBase in built[key]:
			meshed = meshed and not grid.get_chunk_mesh_instances().is_empty()
	check(built.size() == count and meshed, "cerca se levantan las %d casas, malladas" % count)
	var saved: Dictionary = GridManager.get_save_data().grids
	var leaked := false
	for key: String in built:
		for grid: GridBase in built[key]:
			if saved.has(grid.grid_id) or grid.settlement != key:
				leaked = true
	check(not leaked, "las casas sin tocar no van en la partida")

	# Abrir su puerta no es tocarla.
	var opened := false
	for key: String in built:
		var grid: GridBase = built[key][0]
		var props := grid.get_all_props()
		for prop_key: String in props:
			# Como WoodenDoor.toggle: el estado entero, con "open" cambiado.
			var state: Dictionary = props[prop_key].get("state", {}).duplicate(true)
			state["open"] = 1
			grid.set_prop_state(prop_key, state)
			opened = true
	check(opened and manager.get_built().size() == count and (manager.get_save_data().claimed as Array).is_empty(),
		"las casas llevan puerta, y abrirla no las hace de la partida")

	# Tocar una: poner un bloque en su grid.
	var key0: String = built.keys()[0]
	var grid0: GridBase = built[key0][0]
	var free := Vector3i(0, 40, 0)
	grid0.place_block(free, BlockDatabase.get_block(0), Basis.IDENTITY,
		Transform3D(grid0.get_basis_world(), grid0.grid_to_world(free)), "wood")
	check(grid0.settlement == "" and GridManager.get_save_data().grids.has(grid0.grid_id)
		and not manager.get_built().has(key0), "al poner un bloque la casa pasa a la partida")
	# Otra desaparece por su cuenta (desmontada).
	var key1: String = manager.get_built().keys()[0]
	GridManager.remove_grid((manager.get_built()[key1][0] as GridBase).grid_id)
	manager._update()
	check(not manager.get_built().has(key1) and manager.get_save_data().claimed.has(key1),
		"una casa desmontada no vuelve a salir")

	player.global_position = center_world + east * 2000.0
	await _settle(manager)
	check(manager.get_built().is_empty() and GridManager.get_grid(grid0.grid_id) == grid0
		and GridManager.get_all_grids().size() == before + 1, "lejos se quitan, menos la tocada")

	player.global_position = center_world
	await _settle(manager)
	check(manager.get_built().size() == count - 2, "al volver salen otra vez, menos las dos que son de la partida")

	# Una partida cargada: GridManager quita todas las grids y no cuenta como tocarlas.
	var data := manager.get_save_data()
	manager.prepare_restore()
	GridManager.clear_all()
	manager.restore_save_data(data)
	check((manager.get_save_data().claimed as Array).size() == 2 and manager.get_built().is_empty(),
		"al cargar, las de la partida siguen siéndolo y ninguna más")
	await _settle(manager)
	check(manager.get_built().size() == count - 2, "y las demás se vuelven a levantar")
	GridManager.clear_all()
	manager.queue_free()
	planet.queue_free()
	player.queue_free()


## La gente: se viste en un hilo y aparece en la plaza (de día; sin sol es mediodía), con un lecho por
## vecino en su casa y los sitios de trabajo puestos; de noche entra por su puerta, que abre y cierra, y
## se tumba en su lecho; de día sale y los que tienen oficio trabajan en su sitio con su herramienta; a
## mediodía se sientan delante de casa; la hoguera se enciende al atardecer; saludan al jugador; se
## esquivan; con una fiera cerca corren a casa y salen cuando se va; dos se juntan a charlar; lejos se
## van. Los pasos de física se dan a mano, más deprisa.
func _check_villagers() -> void:
	slope = 0.0
	var cfg := {"radius": RADIUS, "sea_radius": RADIUS - 50.0, "max_slope": 0.25, "max_step": 3.0}
	var template := SettlementField.template(&"aldea")
	var center := SettlementLayout.find_center({"dir": _dir(Vector2.ZERO), "into": north}, _ground, cfg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var road := func(_d: Vector3) -> float: return 100.0
	var plan := SettlementLayout.plan(template, center, north, _measures(), _ground, road, cfg, rng)
	var field := {"radius": RADIUS, "villages": [plan]}
	var planet := Node3D.new()
	add_child(planet)
	var terrain := Node3D.new()
	planet.add_child(terrain)
	var player := Node3D.new()
	add_child(player)
	var manager := SettlementManager.new()
	manager.entity_id = "test_villagers"
	add_child(manager)
	var settings := {"seed": 9, "load_distance": 300.0, "unload_distance": 500.0, "villager_distance": 300.0}
	manager.setup(planet, terrain, player, field, settings)
	var center_world: Vector3 = (plan.center as Vector3) * (RADIUS + GROUND)
	# Lejos de la plaza (a 60 m) para que no saluden hasta que toque.
	player.global_position = center_world + east * 60.0
	await _settle(manager)

	var prefabs := {}
	var beds := 0
	for b: Dictionary in plan.buildings:
		var prefab := SettlementField.prefab(StringName(b.prefab))
		prefabs[prefab.id] = prefab
		beds += prefab.beds.size()
	var expected := SettlementPopulation.residents(plan, 0, prefabs, 9).size()
	var people := manager.get_people()
	var waited := 0.0
	while (people.get_villagers().size() < expected or people.pending() > 0) and waited < 120.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var villagers := people.get_villagers()
	check(expected > 0 and villagers.size() == expected,
		"aparece la gente del poblado (%d de %d, %.0f s vistiéndolos)" % [villagers.size(), expected, waited])
	check(planet.find_children("SettlementBed*", "", false, false).size() == beds,
		"cada casa lleva sus lechos (%d)" % beds)
	var works := 0
	for b: Dictionary in plan.buildings:
		works += (b.get("work", []) as Array).size()
	check(works > 0 and planet.find_children("SettlementWork*", "", false, false).size() == works,
		"y sus sitios de trabajo (%d)" % works)
	if villagers.is_empty():
		manager.queue_free()
		planet.queue_free()
		player.queue_free()
		return
	var village := villagers[0].village
	var in_plaza := true
	for v in villagers:
		in_plaza = in_plaza and v.local_position().distance_to(village.center) < village.plaza_radius
	check(in_plaza, "de día aparecen en la plaza")

	village.hour_override = 23.0
	for v in villagers:
		v._decide()
	var opened := await _run_villagers(villagers, village, 90.0)
	var in_bed := true
	for v in villagers:
		var bed := village.bed(v.resident.home, v.resident.bed)
		in_bed = in_bed and v.act == Villager.Act.SLEEP and v.local_position().distance_to(bed.origin) < 0.2
	check(in_bed and opened and _doors_shut(village),
		"de noche entran por su puerta, que abren y cierran, y se tumban en su lecho")

	village.hour_override = 9.0
	for v in villagers:
		v._decide()
	opened = await _run_villagers(villagers, village, 90.0)
	var out := true
	var working := 0
	var at_work := true
	for v in villagers:
		var job: Dictionary = v.resident.get("job", {})
		out = out and v.act != Villager.Act.SLEEP and (v._inside < 0 or (not job.is_empty() and v._inside == job.building))
		if v.act == Villager.Act.WORK:
			working += 1
			var stand: Vector3 = (village.workplace(job).stands as PackedVector3Array)[job.stand]
			# Sin la colisión del terreno (aquí no hay) fuera siguen a la altura que traían: se mide en el plano.
			var off := Villager._tangent_raw(v.local_position() - stand, stand).length()
			if off >= 0.4 or v._tool == null or not v._tool.visible:
				at_work = false
	check(out and opened and _doors_shut(village), "de día salen de casa y la puerta queda cerrada")
	check(working > 0 and at_work, "los de oficio trabajan en su sitio con la herramienta en la mano (%d)" % working)

	village.hour_override = 12.5
	for v in villagers:
		v._decide()
	await _run_villagers(villagers, village, 60.0)
	var lunching := 0
	for v in villagers:
		var home: Dictionary = village.homes[v.resident.home]
		if v.act == Villager.Act.SIT and v.local_position().distance_to(home.outside) < 3.5:
			lunching += 1
	check(lunching * 2 >= villagers.size(), "a mediodía se sientan delante de su casa (%d de %d)" % [lunching, villagers.size()])

	village.update(0.0)
	var lit_noon := village.fire.lit
	village.hour_override = 19.0
	village.update(0.0)
	check(not lit_noon and village.fire.lit, "la hoguera de la plaza se enciende al atardecer")
	village.hour_override = 10.0

	# El jugador a 4 m de uno de pie: lo saluda y luego sigue.
	var greeter: Villager
	for v in villagers:
		if v._inside < 0:
			greeter = v
			break
	greeter._stand(30.0)
	greeter._greet_left = 0.0
	var side := Villager._tangent(greeter._forward.cross(greeter.local_position()), greeter.local_position())
	player.global_position = terrain.global_transform * (greeter.local_position() + side * 4.0 + greeter.local_position().normalized())
	await _run_villagers([greeter] as Array[Villager], village, 1.0)
	var waved := greeter.act == Villager.Act.WAVE
	await _run_villagers([greeter] as Array[Villager], village, 3.0)
	check(waved and greeter.act == Villager.Act.STAND, "saluda al jugador cuando se acerca y luego sigue")
	player.global_position = center_world + east * 60.0

	# Dos que se cruzan de frente se esquivan.
	var a := villagers[0]
	var b := villagers[1]
	for v in [a, b]:
		v._decide()
		v._abort_leg()
		v._inside = -1
		v._set_solid(true)
	var from_a := village.plaza_spot(rng)
	var dir := Villager._tangent(village.center - from_a, from_a)
	var to_a := (from_a + dir * 8.0).normalized() * from_a.length()
	a._pos = from_a
	b._pos = to_a
	a._go_to(to_a, -1, func() -> void: a._stand(30.0))
	b._go_to(from_a, -1, func() -> void: b._stand(30.0))
	var closest := INF
	for i in 300:
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		closest = minf(closest, Villager._tangent_raw(a._pos - b._pos, a._pos).length())
	check(closest > 0.5 and a.act == Villager.Act.STAND and b.act == Villager.Act.STAND,
		"dos que se cruzan de frente se esquivan (%.2f m como poco)" % closest)

	# Una fiera: todos a casa, dentro y la puerta cerrada; cuando se va, salen.
	village.danger = true
	village._calm = -1.0e6
	for v in villagers:
		v.alarm()
	await _run_villagers(villagers, village, 60.0)
	var hidden := true
	for v in villagers:
		hidden = hidden and v.act == Villager.Act.HIDE and v._inside == v.resident.home
	check(hidden and _doors_shut(village), "con una fiera cerca corren a casa y cierran la puerta")
	village.danger = false
	await _run_villagers(villagers, village, 30.0)
	var calm := true
	for v in villagers:
		calm = calm and v.act != Villager.Act.HIDE
	check(calm, "cuando se va, vuelven a salir")

	var talker: Villager
	for v in villagers:
		v._stand(200.0)
	for v in villagers:
		if v._inside < 0:
			talker = v
			break
	var paired := talker._start_talk()
	var talking := false
	for i in 40:
		await _run_villagers(villagers, village, 1.0)
		if talker.act == Villager.Act.TALK:
			talking = talker._partner != null and talker._partner.act == Villager.Act.TALK \
				and talker._partner._partner == talker
			break
	check(paired and talking, "dos se juntan a charlar")

	player.global_position = center_world + east * 2000.0
	await _settle(manager)
	check(people.get_villagers().is_empty(), "lejos se van")
	GridManager.clear_all()
	manager.queue_free()
	planet.queue_free()
	player.queue_free()


## [seconds] de vida de [villagers] a pasos de 1/30 s. Si alguna puerta de [village] se ha abierto.
func _run_villagers(villagers: Array[Villager], village: SettlementVillage, seconds: float) -> bool:
	var opened := false
	for i in int(seconds * 30.0):
		for v in villagers:
			v._physics_process(1.0 / 30.0)
		for b: int in village.homes:
			var leaf := village._leaf(b)
			opened = opened or (leaf != null and leaf.open_side != 0)
		if i % 30 == 0:
			await get_tree().process_frame
	return opened


func _doors_shut(village: SettlementVillage) -> bool:
	for b: int in village.homes:
		var leaf := village._leaf(b)
		if leaf == null or leaf.open_side != 0:
			return false
	return true


## Deja al gestor mirar y levantar todo lo que tenga en cola.
func _settle(manager: SettlementManager) -> void:
	manager._update()
	for i in 80:
		await get_tree().process_frame


func _measures() -> Dictionary:
	var out := {}
	for t in SettlementField.load_templates():
		var prefabs: Array = [t.center]
		prefabs.append_array(t.buildings)
		for p: SettlementPrefab in prefabs:
			if p != null:
				out[p.id] = p.measure()
	return out


## El relieve inventado: GROUND m sobre el radio, subiendo hacia el este con [slope].
func _ground(dir: Vector3) -> float:
	return RADIUS + GROUND + _local(dir).x * slope


## Lo que da el grafo de densidad [density] en la dirección [dir] (como en test_trails).
func _density_at(density: VoxelGraphFunction, dir: Vector3) -> float:
	var values := []
	for with_density in [true, false]:
		var gen := VoxelGeneratorGraph.new()
		var f := gen.get_main_function()
		var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
		var y := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
		var z := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
		var sphere := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2())
		f.set_node_default_input_by_name(sphere, "radius", RADIUS + 120.0)
		f.add_connection(x, 0, sphere, 0)
		f.add_connection(y, 0, sphere, 1)
		f.add_connection(z, 0, sphere, 2)
		var sdf := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
		if with_density:
			var fn := f.create_function_node(density, Vector2())
			f.add_connection(x, 0, fn, 0)
			f.add_connection(y, 0, fn, 1)
			f.add_connection(z, 0, fn, 2)
			var scaled := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2())
			f.add_connection(fn, 0, scaled, 0)
			f.set_node_default_input(scaled, 1, 0.001)
			var sum := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2())
			f.add_connection(sphere, 0, sum, 0)
			f.add_connection(scaled, 0, sum, 1)
			f.add_connection(sum, 0, sdf, 0)
		else:
			f.add_connection(sphere, 0, sdf, 0)
		gen.compile()
		var b := VoxelBuffer.new()
		b.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
		b.create(1, 1, 1)
		gen.generate_block(b, Vector3i((dir * (RADIUS + 120.0)).round()), 0)
		values.append(b.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF))
	return (values[0] - values[1]) * 1000.0


func _dir(p: Vector2) -> Vector3:
	return (origin * RADIUS + east * p.x + north * p.y).normalized()


func _local(dir: Vector3) -> Vector2:
	var p := dir / dir.dot(origin) * RADIUS
	return Vector2(p.dot(east), p.dot(north))


func _line(from: Vector2, delta: Vector2) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := int(ceil(delta.length() / 12.0))
	for i in n + 1:
		out.append(_dir(from + delta * float(i) / n))
	return out
