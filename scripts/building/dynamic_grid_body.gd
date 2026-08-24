class_name DynamicGridBody
extends RigidBody3D

## RigidBody3D de una grid dinámica: gravedad planetaria + flotación de Arquímedes (empuje
## por volumen sumergido de las cajas de colisión fusionadas; masa por densidad de bloque),
## inundación por compartimentos interiores (analizados en worker thread) y movimiento
## según movement_type (barco; vehículo y nave pendientes).

enum MovementType { BOAT, LAND_VEHICLE, SPACESHIP }

@export var movement_type: MovementType = MovementType.BOAT
@export var damage_enabled: bool = true
@export var turn_speed: float = 2.0
@export var buoyancy_lod_distance: float = 150.0
@export var linear_drag: float = 0.3
@export var heave_drag: float = 1.0
@export var angular_drag: float = 0.15
@export var flood_capacity_factor: float = 0.9

const BLOCK_DENSITY := 500.0
const WATER_DENSITY := 1000.0
const MIN_MASS := 10.0
const MAX_WAVE_SAMPLES := 16
## Sondas de ola cuando el casco tiene más cajas que MAX_WAVE_SAMPLES: una por cuadrante, que es el
## mínimo para que haya par de cabeceo y de balance.
const WAVE_PROBES := 4
## Cajas en que se agrega el casco para la flotación lejana (cuadrantes manga × eslora).
const LOD_QUADRANTS := 4

const WAKE_SPACING := 3.0
const WAKE_LIFETIME := 12.0
const WAKE_MAX_POINTS := 64
# Velocidad mínima RESPECTO AL AGUA para abrir estela. Con corriente, la velocidad sobre el fondo y
# la que corta el agua difieren mucho, y un umbral alto enciende y apaga la estela según el rumbo.
const WAKE_MIN_SPEED := 1.0

# Segundos sin ediciones antes de relanzar el análisis de interiores (coalesce de ráfagas).
const INTERIOR_DEBOUNCE := 0.3

# Frames de física entre reevaluaciones del estado de inundación, y desplazamiento radial
# (m) que fuerza una reevaluación antes de tiempo (caídas o hundimientos rápidos).
const FLOOD_RECALC_FRAMES := 4
const FLOOD_RECALC_HEAVE := 0.25

## Velocidad de cierre (m/s) por debajo de la cual un contacto no hace daño. El umbral va sobre la
## velocidad, no sobre el impulso: un casco posado en tierra genera contactos permanentes cuyo
## impulso es el peso del barco entero, y con ese criterio se autodestruiría al varar.
const IMPACT_MIN_SPEED := 6.0
## Fracción de la energía cinética del cierre que se convierte en destrucción.
const IMPACT_ENERGY_FACTOR := 0.35
## Masa (kg) máxima que cuenta como concentrada en el punto de impacto. Con la masa entera, el daño
## escala con el tamaño del casco y un carguero que roza el suelo se abre en canal: lo que rompe es
## la parte que choca, no el barco completo.
const IMPACT_MAX_EFFECTIVE_MASS := 20000.0
## Frames de física de espera tras un impacto, para que un rebote no siga triturando el casco.
const IMPACT_COOLDOWN_FRAMES := 8
## Parte de la energía que se lleva la estructura estática golpeada. No conserva energía: es un
## mando independiente para decidir cuánto aguanta un muelle frente a un barco.
const IMPACT_VICTIM_SHARE := 0.6

## Fracción de la capacidad de inundación a la que un casco perforado se queda SIN la grúa de
## escora (ver _heel_assist). Más bajo = se tumba antes.
const HEEL_ASSIST_FLOOD_LIMIT := 0.4
const MAX_CONTACTS_REPORTED := 8

## Segundos sin ediciones antes de comprobar si el casco se ha partido. Solo quitar bloques puede
## desconectar algo, así que el análisis se marca desde on_block_removed y no desde mark_points_dirty.
const SPLIT_DEBOUNCE := 0.35
## Piezas con menos bloques que esto no merecen un cuerpo propio: se disuelven en cascotes. Un
## RigidBody3D por cada cubo suelto de un naufragio sale carísimo y no aporta nada.
const SPLIT_MIN_BLOCKS := 4

## Retirada de restos. can_sleep está desactivado a propósito (dormido no recibiría las fuerzas
## custom), así que cada pieza desprendida se integra para siempre: una batalla dejaba cascos a la
## deriva que nunca se iban. Solo se retiran piezas nacidas de una rotura, nunca lo que construyó
## el jugador, y solo si son pequeñas, están quietas y lejos.
const DERELICT_MAX_BLOCKS := 12
const DERELICT_DISTANCE := 3.0
const DERELICT_SPEED := 1.0
const DERELICT_SETTLE_TIME := 5.0

var planet_node: Node3D = null

## Corriente que vio el casco en el último paso de física y masa de agua desplazada. Solo diagnóstico:
## los lee el comando 'drift' para comparar la velocidad del agua con la del barco.
var last_water_flow: Vector3 = Vector3.ZERO
var last_displaced_mass: float = 0.0
## Muestras de ola independientes usadas en el último paso: con una sola, el casco flota sobre un
## plano y no cabecea. Solo diagnóstico.
var last_wave_samples: int = 0

var _water_sampler: WaterHeightSampler = null
var _wake_points: Array = []
## Popa en coordenadas locales del casco, para recalcular la cabeza de la estela en cada frame
## renderizado. Ver get_wake_head_offset.
var _wake_stern_local: Vector3 = Vector3.ZERO
var _wake_active: bool = false

var _grids: Array = []
var _box_pos := PackedVector3Array()
var _box_half := PackedVector3Array()
var _box_vol := PackedFloat32Array()
var _agg_pos := PackedVector3Array()
var _agg_half := PackedVector3Array()
var _agg_vol := PackedFloat32Array()
var _aggregate_box: Dictionary = {}
var _drag_length_sq: float = 1.0
var _recalc_boxes: bool = true
var _is_being_controlled: bool = false

var _flood_volume: float = 0.0
var _flood_capacity: float = 0.0
var _flood_local_centroid: Vector3 = Vector3.ZERO
var _flood_recalc_countdown: int = 0
var _flood_last_radius: float = 0.0
var _flood_dirty: bool = true
var _dry_boxes_cache: Array = []
var _dry_boxes_dirty: bool = true
var _compartments: Array = []
var _breached_comps: Array = []
var _interior_cell_size: float = 0.0
var _interior_dirty: bool = false
var _interior_debounce: float = 0.0
var _analysis_running: bool = false
var _analysis_task_id: int = -1

var _boat_speed_levels: Array[float] = [0.0, 50.0, 100.0, 200.0]
var _boat_speed_index: int = 0
var _boat_target_speed: float = 0.0
var _boat_current_speed: float = 0.0
@export var boat_acceleration: float = 3.0
@export var boat_deceleration: float = 5.0

## Velocidad del paso de física anterior, para medir la aproximación de un contacto antes de que
## el solver la absorba. Ver _detect_impact.
var _prev_lin_vel: Vector3 = Vector3.ZERO
var _prev_ang_vel: Vector3 = Vector3.ZERO
var _impact_cooldown: int = 0

var _split_dirty: bool = false
var _split_debounce: float = 0.0
var _split_running: bool = false
var _split_task_id: int = -1
## Grids tal y como estaban al lanzar el análisis. El reparto viene indexado por posición, y si
## _grids cambia mientras el worker trabaja los índices apuntarían a otra grid.
var _split_grids: Array = []

## True solo en los cuerpos nacidos de una rotura. Lo que colocó el jugador nunca se autorretira,
## por pequeño que quede: borrar propiedad del jugador sin avisar es peor que acumular cuerpos.
## OJO: no se serializa, así que tras cargar una partida los restos vuelven como si los hubiera
## construido el jugador y ya no se retiran nunca. Es deliberado —cargar no debe borrar nada—,
## pero significa que la limpieza solo actúa dentro de la sesión en la que se rompió el casco.
var spawned_from_split: bool = false
var _derelict_timer: float = 0.0

signal speed_changed(level: int, speed: float)
signal blocks_destroyed(world_pos: Vector3, count: int)

func on_block_removed(_grid_pos: Vector3i, _grid: GridBase = null) -> void:
	mark_points_dirty()
	# Solo quitar bloques puede partir el casco; colocarlos únicamente puede unir piezas.
	_split_dirty = true
	_split_debounce = SPLIT_DEBOUNCE

func on_block_placed(_grid_pos: Vector3i, _block_id: int, _grid: GridBase = null) -> void:
	mark_points_dirty()

func mark_points_dirty() -> void:
	_recalc_boxes = true
	_interior_dirty = true
	_interior_debounce = INTERIOR_DEBOUNCE

## Reconstruye las cajas de volumen del casco desde los colliders del body: cajas fusionadas
## de cubos tal cual, rampas/esquinas como caja de su celda a medio volumen. En arrays
## empaquetados paralelos: el bucle de flotación los recorre entero cada frame de física.
func _recalculate_buoyancy_boxes() -> void:
	_recalc_boxes = false
	_box_pos.clear()
	_box_half.clear()
	_box_vol.clear()
	_aggregate_box = {}
	_flood_capacity = 0.0

	var aabb := AABB()
	var first := true
	var total_volume := 0.0

	for child in get_children():
		if not (child is CollisionShape3D) or child.is_queued_for_deletion():
			continue
		var col := child as CollisionShape3D

		var half: Vector3
		var volume: float
		if col.shape is BoxShape3D:
			half = (col.shape as BoxShape3D).size * 0.5
			volume = half.x * half.y * half.z * 8.0
		else:
			half = Vector3.ONE * 0.5 * col.scale.x
			volume = col.scale.x * col.scale.x * col.scale.x * 0.5

		var pos: Vector3 = col.transform.origin
		_box_pos.append(pos)
		_box_half.append(half)
		_box_vol.append(volume)
		total_volume += volume

		if first:
			aabb = AABB(pos - half, half * 2.0)
			first = false
		else:
			aabb = aabb.expand(pos - half)
			aabb = aabb.expand(pos + half)

	if _box_vol.is_empty():
		return

	_aggregate_box = {"pos": aabb.get_center(), "half": aabb.size * 0.5, "volume": total_volume}
	_build_lod_boxes(aabb.get_center())
	_drag_length_sq = maxf(1.0, (aabb.size * 0.5).length_squared())

	# Capacidad provisional (AABB − bloques); el análisis la sustituye por el volumen real.
	var box_volume := aabb.size.x * aabb.size.y * aabb.size.z
	_flood_capacity = maxf((box_volume - total_volume) * flood_capacity_factor, 0.0)


## Agrega el casco en los cuatro cuadrantes del AABB (mitades de manga y de eslora) para el LOD
## lejano. Con una sola caja el empuje caía siempre en la misma vertical del cuerpo: ni par
## adrizante al escorar, ni coincidencia con el centro de masas —que la gravedad sí usa—, y el
## barco se quedaba tumbado de un lado. Cada cuadrante guarda su volumen real y su centroide
## ponderado, así que el reparto del empuje sigue al de la masa.
func _build_lod_boxes(center: Vector3) -> void:
	var vols := [0.0, 0.0, 0.0, 0.0]
	var weighted := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var mins := [Vector3.INF, Vector3.INF, Vector3.INF, Vector3.INF]
	var maxs := [-Vector3.INF, -Vector3.INF, -Vector3.INF, -Vector3.INF]

	# Las cajas vienen fusionadas y muchas cruzan el corte de lado a lado: cada una se reparte
	# por solape con los cuadrantes, no por dónde caiga su centro, o una sola caja que abarque
	# toda la manga volvería a descentrar el empuje.
	for i in _box_vol.size():
		var pos: Vector3 = _box_pos[i]
		var half: Vector3 = _box_half[i]
		var vol: float = _box_vol[i]
		var split_x := _split_axis(pos.x - half.x, pos.x + half.x, center.x)
		var split_z := _split_axis(pos.z - half.z, pos.z + half.z, center.z)

		for ix in 2:
			for iz in 2:
				var part_x: Dictionary = split_x[ix]
				var part_z: Dictionary = split_z[iz]
				var weight: float = part_x["frac"] * part_z["frac"]
				if weight <= 0.0:
					continue

				var q: int = ix + iz * 2
				var part_vol: float = vol * weight
				vols[q] += part_vol
				weighted[q] += Vector3(
					(part_x["lo"] + part_x["hi"]) * 0.5,
					pos.y,
					(part_z["lo"] + part_z["hi"]) * 0.5) * part_vol
				mins[q] = (mins[q] as Vector3).min(Vector3(part_x["lo"], pos.y - half.y, part_z["lo"]))
				maxs[q] = (maxs[q] as Vector3).max(Vector3(part_x["hi"], pos.y + half.y, part_z["hi"]))

	_agg_pos.clear()
	_agg_half.clear()
	_agg_vol.clear()

	for q in LOD_QUADRANTS:
		var vol: float = vols[q]
		if vol <= 0.0:
			continue
		var centroid: Vector3 = (weighted[q] as Vector3) / vol
		# Semiejes medidos desde el centroide y no desde el centro geométrico: la caja debe
		# quedar centrada donde está el volumen, que es lo que moja el agua primero.
		var lo: Vector3 = mins[q]
		var hi: Vector3 = maxs[q]
		var half := (hi - centroid).max(centroid - lo).max(Vector3.ONE * 0.05)

		_agg_pos.append(centroid)
		_agg_half.append(half)
		_agg_vol.append(vol)


## Parte el intervalo [lo, hi] por el corte c y devuelve, para el trozo bajo y el alto, qué
## fracción de la longitud se lleva y dónde empieza y acaba.
static func _split_axis(lo: float, hi: float, c: float) -> Array:
	var length := maxf(hi - lo, 0.0001)
	var cut := clampf(c, lo, hi)
	return [
		{"frac": (cut - lo) / length, "lo": lo, "hi": cut},
		{"frac": (hi - cut) / length, "lo": cut, "hi": hi},
	]


## Lanza el análisis de compartimentos en un worker thread con debounce de ediciones.
func _process_interior_analysis(delta: float) -> void:
	if _analysis_running or not _interior_dirty:
		return
	_interior_debounce -= delta
	if _interior_debounce > 0.0:
		return
	_interior_dirty = false
	_analysis_running = true

	var grids_data: Array = []
	for grid in _grids:
		grids_data.append({
			"cells": grid.get_all_blocks().keys(),
			"cell_size": grid.cell_size,
		})
	_analysis_task_id = WorkerThreadPool.add_task(
		_run_interior_analysis.bind(grids_data), false, "ShipInteriorAnalysis")


## Cuerpo de la tarea en el worker thread; el resultado se aplica en el main thread.
func _run_interior_analysis(grids_data: Array) -> void:
	var result := ShipInteriorAnalyzer.analyze(grids_data)
	call_deferred("_apply_interior_analysis", result)


## Aplica el resultado del análisis: compartimentos, capacidad real y flags de inundación
## (inmediatos: GridManager puede empujar la máscara antes del siguiente frame de física).
func _apply_interior_analysis(result: Array) -> void:
	if _analysis_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_analysis_task_id)
		_analysis_task_id = -1
	_analysis_running = false

	# Cambiar la resolución de la rejilla fina invalida la identidad de celdas entre análisis.
	var finest: float = result[0]["cell_size"] if not result.is_empty() else 0.0
	if finest != _interior_cell_size:
		_breached_comps.clear()
	_interior_cell_size = finest

	# Compartimento previo cuyas celdas pasaron a ser exteriores = PERFORADO: conserva su
	# geometría congelada y su volumen bajo el mar pesa como agua embarcada (sin esto, un
	# casco acribillado pierde sus compartimentos y flota como un corcho). Al resellarlo,
	# el reanálisis vuelve a solapar sus celdas y lo recupera como compartimento seco.
	var still_breached: Array = []
	for old: Dictionary in _compartments + _breached_comps:
		if _find_overlapping_comp(old, result).is_empty():
			still_breached.append(old)
	_breached_comps = still_breached

	_compartments = result
	_flood_dirty = true
	_dry_boxes_dirty = true

	var total := 0.0
	for comp: Dictionary in _compartments:
		total += comp["volume"]
	if total > 0.0:
		_flood_capacity = total * flood_capacity_factor

	if planet_node and planet_node.planet.has_water:
		var planet_pos: Vector3 = planet_node.global_pos
		var base_r: float = planet_node.planet.radius - planet_node.planet.water_radius
		for comp: Dictionary in _compartments:
			comp["flooded"] = _is_comp_flooded(comp, planet_pos, base_r)


## Compartimentos interiores del último análisis (ver ShipInteriorAnalyzer.analyze).
func get_compartments() -> Array:
	return _compartments


## Lanza el análisis de componentes conexas si hubo bajas de bloques y ya pasó el debounce.
func _process_split_analysis(delta: float) -> void:
	if _split_running or not _split_dirty:
		return
	_split_debounce -= delta
	if _split_debounce > 0.0:
		return
	_split_dirty = false
	_split_running = true

	_split_grids = _grids.duplicate()
	var grids_data: Array = []
	for grid in _split_grids:
		grids_data.append({
			"cells": grid.get_all_blocks().keys(),
			"cell_size": grid.cell_size,
		})
	_split_task_id = WorkerThreadPool.add_task(
		_run_split_analysis.bind(grids_data), false, "GridSplitAnalysis")


func _run_split_analysis(grids_data: Array) -> void:
	var result := GridSplitAnalyzer.analyze(grids_data)
	call_deferred("_apply_split", result)


## Reparte las piezas desprendidas en cuerpos nuevos. La mayor se queda con este body —y con
## el control del jugador, si lo había—; las demás se llevan sus bloques y props a uno propio.
func _apply_split(pieces: Array) -> void:
	if _split_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_split_task_id)
		_split_task_id = -1
	_split_running = false

	if pieces.size() <= 1 or not is_inside_tree():
		return

	# El casco pudo cambiar entre el lanzamiento del análisis y ahora (otro impacto, el jugador
	# construyendo). Repartir con datos viejos dejaría bloques fantasma, así que se reintenta.
	if not _pieces_still_valid(pieces):
		_split_dirty = true
		_split_debounce = SPLIT_DEBOUNCE
		return

	var old_lin := linear_velocity
	var old_ang := angular_velocity
	var whole_centroid := _centroid_of_pieces(pieces)

	for i in range(1, pieces.size()):
		var piece: Dictionary = pieces[i]
		if int(piece["count"]) < SPLIT_MIN_BLOCKS:
			_dissolve_piece(piece)
		else:
			_spawn_piece(piece, whole_centroid, old_lin, old_ang)

	# El centro de masas de lo que queda también se ha movido.
	var kept := _centroid_of_pieces([pieces[0]])
	linear_velocity = old_lin + old_ang.cross(global_transform.basis * (kept - whole_centroid))
	angular_velocity = old_ang
	_impact_cooldown = IMPACT_COOLDOWN_FRAMES

	# Las bajas de los detach_block acaban de re-marcar el análisis; las piezas ya son conexas.
	_split_dirty = false


## True si el reparto sigue siendo aplicable: las grids que vio el análisis siguen en el body y
## todas sus celdas siguen donde estaban.
func _pieces_still_valid(pieces: Array) -> bool:
	for piece: Dictionary in pieces:
		for group: Dictionary in piece["groups"]:
			var gi: int = group["grid_index"]
			if gi >= _split_grids.size():
				return false
			var grid = _split_grids[gi]
			if not _grids.has(grid):
				return false
			for cell: Vector3i in group["cells"]:
				if not grid.has_block(cell):
					return false
	return true


## Centroide en espacio del body de los bloques de un conjunto de piezas.
func _centroid_of_pieces(pieces: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for piece: Dictionary in pieces:
		for group: Dictionary in piece["groups"]:
			var cs: float = _split_grids[group["grid_index"]].cell_size
			for cell: Vector3i in group["cells"]:
				sum += (Vector3(cell) + Vector3.ONE * 0.5) * cs
				count += 1
	return sum / maxf(float(count), 1.0)


## Piezas demasiado pequeñas para un cuerpo propio: se borran y se van en cascotes.
func _dissolve_piece(piece: Dictionary) -> void:
	var world_pos := global_position
	for group: Dictionary in piece["groups"]:
		var grid = _split_grids[group["grid_index"]]
		grid.begin_batch_edit()
		for cell: Vector3i in group["cells"]:
			world_pos = grid.grid_to_world(cell)
			grid.remove_block(cell)
		grid.end_batch_edit()

	var up := Vector3.UP
	if planet_node:
		up = (world_pos - planet_node.global_pos).normalized()
	BlockDebris.burst(self, world_pos, up, int(piece["count"]))


## Traslada los bloques y props de una pieza a un DynamicGridBody nuevo, colocado en el mismo
## transform que este: así las coordenadas de grid se conservan tal cual y basta re-emparentar
## los nodos de colisión conservando su transform global.
func _spawn_piece(piece: Dictionary, whole_centroid: Vector3, old_lin: Vector3, old_ang: Vector3) -> void:
	var body_id := GridManager.generate_grid_id()

	var body := DynamicGridBody.new()
	body.name = "DynGrid_%s" % body_id
	body.planet_node = planet_node
	body.movement_type = movement_type
	body.damage_enabled = damage_enabled
	body.spawned_from_split = true
	body.mass = MIN_MASS
	body.gravity_scale = 0.0
	body.set_meta("grid_id", body_id)
	get_tree().current_scene.add_child(body)
	body.global_transform = global_transform

	var owns_body := true
	for group: Dictionary in piece["groups"]:
		var source = _split_grids[group["grid_index"]]

		var piece_grid := DynamicPlanetGrid.new()
		piece_grid.grid_id = body_id if owns_body else GridManager.generate_grid_id()
		piece_grid.body_id = body_id
		piece_grid.planet_node = planet_node
		piece_grid.cell_size = source.cell_size
		piece_grid.mesh_materials = source.mesh_materials.duplicate()
		piece_grid._body = body
		piece_grid._owns_body = owns_body
		owns_body = false

		var moving: Dictionary = {}
		for cell: Vector3i in group["cells"]:
			moving[cell] = true

		source.begin_batch_edit()
		piece_grid.begin_batch_edit()

		for key: String in source.get_prop_keys_in_cells(moving):
			var prop_info : Dictionary = source.detach_prop(key)
			var prop_node: Node3D = prop_info["node"]
			if prop_node and is_instance_valid(prop_node):
				prop_node.reparent(body, true)
				prop_node.set_meta("grid_id", piece_grid.grid_id)
			piece_grid.attach_prop(key, prop_info)

		for cell: Vector3i in group["cells"]:
			var info : Dictionary = source.detach_block(cell)
			if info.is_empty():
				continue
			var node: Node3D = info["node"]
			if node and is_instance_valid(node):
				node.reparent(body, true)
				node.set_meta("grid_id", piece_grid.grid_id)
			piece_grid.attach_block(cell, info)

		piece_grid.end_batch_edit()
		source.end_batch_edit()

		GridManager.register_runtime_grid(piece_grid, planet_node)
		body.register_grid(piece_grid)
		piece_grid.block_placed.connect(body.on_block_placed.bind(piece_grid))
		piece_grid.block_removed.connect(body.on_block_removed.bind(piece_grid))

	body.update_mass_from_grids()

	# Velocidad del sólido rígido en el centroide de la pieza, con la rotación del original.
	var piece_centroid := _centroid_of_pieces([piece])
	var arm := global_transform.basis * (piece_centroid - whole_centroid)
	body.linear_velocity = old_lin + old_ang.cross(arm)
	body.angular_velocity = old_ang
	body._impact_cooldown = IMPACT_COOLDOWN_FRAMES

func _is_ground_ready() -> bool:
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 5,
		planet_node.global_pos
	)
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	return not result.is_empty()

func _ready() -> void:
	collision_layer = 3
	collision_mask = 1
	# Dormido ignoraría las fuerzas custom (flotación, gravedad planetaria, inundación).
	can_sleep = false
	# Sin esto get_contact_count() devuelve siempre 0 y no hay detección de impactos.
	contact_monitor = true
	max_contacts_reported = MAX_CONTACTS_REPORTED
	add_to_group("floating_origin")
	add_to_group("dynamic_grid_body")
	_setup_water_sampler()
	BlockDebris.prewarm(self)

func _setup_water_sampler() -> void:
	if not planet_node:
		return
	if not planet_node.planet.has_water:
		return
	_water_sampler = WaterHeightSampler.new()
	add_child(_water_sampler)
	var mat: ShaderMaterial = planet_node.water_sphere.mesh_manager.default_material as ShaderMaterial
	if mat:
		_water_sampler.setup(mat, planet_node.world_map)

func register_grid(grid) -> void:
	if not _grids.has(grid):
		_grids.append(grid)
	mark_points_dirty()

func unregister_grid(grid) -> void:
	_grids.erase(grid)
	update_mass_from_grids()
	mark_points_dirty()

## Bloques de todas las grids del body.
func get_block_count() -> int:
	var total := 0
	for grid in _grids:
		total += grid.get_block_count()
	return total


## Cuenta el tiempo que un resto lleva cumpliendo las condiciones de retirada y lo elimina al
## agotarlo. Devuelve true si el cuerpo se ha ido, para que el llamante no siga simulándolo.
func _update_derelict(delta: float) -> bool:
	if not spawned_from_split or _is_being_controlled:
		return false

	var settled := linear_velocity.length_squared() < DERELICT_SPEED * DERELICT_SPEED \
		and angular_velocity.length_squared() < DERELICT_SPEED * DERELICT_SPEED

	var far := true
	var camera := get_viewport().get_camera_3d()
	if camera:
		far = camera.global_position.distance_squared_to(global_position) > DERELICT_DISTANCE * DERELICT_DISTANCE

	if not (settled and far) or get_block_count() > DERELICT_MAX_BLOCKS:
		_derelict_timer = 0.0
		return false

	_derelict_timer += delta
	if _derelict_timer < DERELICT_SETTLE_TIME:
		return false

	_despawn_as_derelict()
	return true


## Estado de la retirada de restos, para el comando de consola 'derelicts'. Son cinco condiciones
## y desde fuera son indistinguibles: un resto que no se va puede estar fallando cualquiera.
func get_derelict_state() -> Dictionary:
	var dist := -1.0
	var camera := get_viewport().get_camera_3d()
	if camera:
		dist = camera.global_position.distance_to(global_position)
	return {
		"from_split": spawned_from_split,
		"controlled": _is_being_controlled,
		"blocks": get_block_count(),
		"speed": linear_velocity.length(),
		"spin": angular_velocity.length(),
		"distance": dist,
		"timer": _derelict_timer,
	}


## Retira el resto del mundo. Quitar sus grids del GridManager libera ya el cuerpo, porque la
## que lo posee hace queue_free() al limpiarse.
func _despawn_as_derelict() -> void:
	var up := Vector3.UP
	if planet_node:
		up = (global_position - planet_node.global_pos).normalized()
	BlockDebris.burst(self, global_position, up, get_block_count())

	for grid in _grids.duplicate():
		GridManager.remove_grid(grid.grid_id)
	if is_instance_valid(self) and not is_queued_for_deletion():
		queue_free()


## Masa total del body: volumen de bloques de TODAS las grids (multi-size) por densidad de bloque.
func update_mass_from_grids() -> void:
	var total_volume := 0.0
	for grid in _grids:
		total_volume += grid.get_total_volume()
	mass = maxf(MIN_MASS, total_volume * BLOCK_DENSITY)


func _handle_input(delta: float) -> void:
	if not _is_being_controlled:
		return

	match movement_type:
		MovementType.BOAT:
			_handle_boat_input(delta)
		MovementType.LAND_VEHICLE:
			_handle_land_input(delta)
		MovementType.SPACESHIP:
			_handle_spaceship_input(delta)

func _handle_boat_input(delta: float) -> void:
	if Input.is_action_just_pressed("ui_up"):
		_boat_speed_index = mini(_boat_speed_index + 1, _boat_speed_levels.size() - 1)
		_boat_target_speed = _boat_speed_levels[_boat_speed_index]
		speed_changed.emit(_boat_speed_index, _boat_target_speed)

	if Input.is_action_just_pressed("ui_down"):
		_boat_speed_index = maxi(_boat_speed_index - 1, 0)
		_boat_target_speed = _boat_speed_levels[_boat_speed_index]
		speed_changed.emit(_boat_speed_index, _boat_target_speed)

	if _boat_current_speed < _boat_target_speed:
		_boat_current_speed = minf(_boat_current_speed + boat_acceleration * delta, _boat_target_speed)
	elif _boat_current_speed > _boat_target_speed:
		_boat_current_speed = maxf(_boat_current_speed - boat_deceleration * delta, _boat_target_speed)

	if _boat_current_speed > 0.01:
		var forward := global_transform.basis.z
		var current_forward_speed := linear_velocity.dot(forward)
		if current_forward_speed < _boat_current_speed:
			var speed_deficit := _boat_current_speed - current_forward_speed
			var force_factor := clampf(speed_deficit / _boat_current_speed, 0.0, 1.0)
			apply_central_force(forward * _boat_current_speed * mass * force_factor)

	if Input.is_action_pressed("ui_left"):
		angular_velocity += global_transform.basis.y * turn_speed * delta
	if Input.is_action_pressed("ui_right"):
		angular_velocity -= global_transform.basis.y * turn_speed * delta

## Sin implementar: movimiento de vehículo terrestre.
func _handle_land_input(_delta: float) -> void:
	pass

## Sin implementar: movimiento de nave espacial.
func _handle_spaceship_input(_delta: float) -> void:
	pass


## Detecta el impacto del paso y guarda la velocidad para el siguiente. La medida usa la
## velocidad ANTERIOR: cuando _integrate_forces corre, el solver ya ha absorbido el choque y la
## velocidad actual de un golpe seco es casi cero.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _impact_cooldown > 0:
		_impact_cooldown -= 1
	elif damage_enabled:
		_detect_impact(state)
	_prev_lin_vel = state.linear_velocity
	_prev_ang_vel = state.angular_velocity


## Busca el contacto más violento del paso y, si supera el umbral, encola la destrucción.
func _detect_impact(state: PhysicsDirectBodyState3D) -> void:
	var contacts := state.get_contact_count()
	if contacts == 0:
		return

	var com := state.transform.origin + state.center_of_mass
	var best_speed := 0.0
	var best_pos := Vector3.ZERO
	var best_other: Object = null

	for i in contacts:
		var pos := state.get_contact_collider_position(i)
		var arm := pos - com
		if arm.length_squared() < 0.0001:
			continue
		# Cierre = velocidad del punto de contacto contra el obstáculo, sobre la normal. El signo de
		# la normal reportada depende de quién sea el cuerpo local, así que se orienta hacia fuera
		# del centro de masas: medida convención-independiente que da ~0 en un casco solo apoyado.
		# (Sobre el brazo en vez de la normal, el término ω × r se anularía por construcción y la
		# rotación no contaría.)
		var normal := state.get_contact_local_normal(i)
		if normal.dot(arm) < 0.0:
			normal = -normal
		var vel: Vector3 = _prev_lin_vel + _prev_ang_vel.cross(arm)
		var rel: Vector3 = vel - state.get_contact_collider_velocity_at_position(i)
		var closing := rel.dot(normal)
		if closing > best_speed:
			best_speed = closing
			best_pos = pos
			best_other = state.get_contact_collider_object(i)

	if best_speed <= IMPACT_MIN_SPEED:
		return

	# Solo el excedente sobre el umbral cuenta, para que un golpe justo en el límite no rompa nada.
	var excess := best_speed - IMPACT_MIN_SPEED
	var effective_mass := minf(mass, IMPACT_MAX_EFFECTIVE_MASS)
	var energy := 0.5 * effective_mass * excess * excess * IMPACT_ENERGY_FACTOR
	_impact_cooldown = IMPACT_COOLDOWN_FRAMES
	# Editar la grid libera CollisionShape3D del propio body mientras el servidor está pisando: diferido.
	call_deferred("_apply_impact", best_pos, energy, _victim_grid_id(best_other))


## Id de la grid ESTÁTICA golpeada, o "" si no lo es. Si la víctima es otro DynamicGridBody se
## devuelve "" a propósito: ese cuerpo detecta el choque en su propio _integrate_forces, y
## dañarlo también desde aquí sería contarlo dos veces.
func _victim_grid_id(other: Object) -> String:
	if not (other is Node) or other is DynamicGridBody:
		return ""
	var node := other as Node
	return str(node.get_meta("grid_id")) if node.has_meta("grid_id") else ""


## Reparte la energía del impacto entre las grids del body (multi-size), con un solo rebuild por
## grid, y lanza los escombros. Se llama diferido desde _detect_impact.
func _apply_impact(world_pos: Vector3, energy: float, victim_grid_id: String = "") -> void:
	if not is_inside_tree():
		return

	_damage_static_victim(world_pos, energy, victim_grid_id)

	var destroyed := 0
	var damaged := 0
	var budget := energy
	var debris_cell := 1.0

	for grid in _grids:
		if budget <= 0.0:
			break
		grid.begin_batch_edit()
		var result: Dictionary = grid.damage_sphere(world_pos, budget)
		grid.end_batch_edit()
		budget -= result["spent"]
		var hit: int = (result["destroyed"] as Array).size()
		damaged += int(result.get("damaged", 0))
		if hit > 0:
			destroyed += hit
			debris_cell = grid.cell_size

	# Un golpe que solo mella también tiene que verse, o el jugador no sabe que está haciendo algo.
	if destroyed == 0:
		if damaged > 0:
			var up_chip := Vector3.UP
			if planet_node:
				up_chip = (world_pos - planet_node.global_pos).normalized()
			BlockDebris.burst(self, world_pos, up_chip, 1, debris_cell)
		return

	# La masa y las cajas de flotación ya las invalida block_removed; aquí solo el efecto.
	var up := Vector3.UP
	if planet_node:
		up = (global_position - planet_node.global_pos).normalized()
	BlockDebris.burst(self, world_pos, up, destroyed, debris_cell)
	blocks_destroyed.emit(world_pos, destroyed)


## Abre el boquete en la estructura estática golpeada. El reparto no conserva energía a propósito:
## cada lado gasta su presupuesto contra su propia dureza, que es mucho más fácil de tunear que
## un reparto físico. Quitarle bloques dispara además su revisión de derrumbe.
func _damage_static_victim(world_pos: Vector3, energy: float, victim_grid_id: String) -> void:
	if victim_grid_id == "":
		return
	var victim := GridManager.get_grid(victim_grid_id)
	if not (victim is PlanetGrid):
		return

	victim.begin_batch_edit()
	var result: Dictionary = victim.damage_sphere(world_pos, energy * IMPACT_VICTIM_SHARE)
	victim.end_batch_edit()

	var count: int = (result["destroyed"] as Array).size()
	if count == 0:
		return

	var up := Vector3.UP
	if planet_node:
		up = (world_pos - planet_node.global_pos).normalized()
	BlockDebris.burst(self, world_pos, up, count, victim.cell_size)


func _physics_process(delta: float) -> void:
	if not planet_node or not is_inside_tree():
		return

	if _update_derelict(delta):
		return

	_handle_input(delta)
	_process_interior_analysis(delta)
	_process_split_analysis(delta)

	var planet_pos: Vector3 = planet_node.global_pos
	var dir: Vector3 = (planet_pos - global_position).normalized()
	var up: Vector3 = -dir
	var gravity: float = planet_node.gravity_strength

	apply_central_force(dir * gravity * mass)

	if not planet_node.planet.has_water or not _water_sampler:
		return

	if _recalc_boxes:
		_recalculate_buoyancy_boxes()

	if _box_vol.is_empty():
		return

	var mat: ShaderMaterial = planet_node.water_sphere.mesh_manager.default_material as ShaderMaterial
	var water_time: float = WaterHeightSampler.get_water_time(mat)
	var base_water_radius: float = planet_node.planet.radius - planet_node.planet.water_radius

	var pos_arr := _box_pos
	var half_arr := _box_half
	var vol_arr := _box_vol
	var camera := get_viewport().get_camera_3d()
	if camera and camera.global_position.distance_squared_to(global_position) > buoyancy_lod_distance * buoyancy_lod_distance:
		pos_arr = _agg_pos
		half_arr = _agg_half
		vol_arr = _agg_vol

	var xf := global_transform

	# Con más cajas que presupuesto de muestras el oleaje se resolvía en UN punto para todo el casco,
	# y un barco sobre un plano horizontal ni cabecea ni balancea: el mar solo se notaba al alejarse,
	# porque el LOD de cuadrantes sí muestrea en cuatro sitios. Aquí se hace lo mismo siempre, con
	# sondas en los cuatro cuadrantes del casco y cada caja tomando la del suyo.
	var probed := vol_arr.size() > MAX_WAVE_SAMPLES
	var probe_h := PackedFloat32Array()
	var probe_flow := PackedVector3Array()
	var probe_center := Vector3.ZERO
	last_wave_samples = WAVE_PROBES if probed else vol_arr.size()
	if probed:
		probe_center = _aggregate_box["pos"]
		var quarter: Vector3 = (_aggregate_box["half"] as Vector3) * 0.5
		probe_h.resize(WAVE_PROBES)
		probe_flow.resize(WAVE_PROBES)
		for q in WAVE_PROBES:
			var probe_local := probe_center + Vector3(
				quarter.x if (q & 1) != 0 else -quarter.x, 0.0,
				quarter.z if (q & 2) != 0 else -quarter.z)
			probe_h[q] = _water_sampler.get_height_at(xf * probe_local, water_time, planet_pos)
			probe_flow[q] = _water_sampler.last_flow

	var basis_w := xf.basis
	var origin := xf.origin
	var submerged_volume := 0.0
	var weighted_buoyancy_pos := Vector3.ZERO
	# Corriente media que ve el casco, ponderada por volumen desplazado: la parte sumergida es la
	# que el agua empuja, y así la ola que baña solo la proa no arrastra como si bañara el barco entero.
	var weighted_flow := Vector3.ZERO

	for i in vol_arr.size():
		var half: Vector3 = half_arr[i]
		var world_center: Vector3 = xf * pos_arr[i]

		var h_half: float = absf((basis_w.x * half.x).dot(up)) \
			+ absf((basis_w.y * half.y).dot(up)) \
			+ absf((basis_w.z * half.z).dot(up))
		h_half = maxf(h_half, 0.05)

		var wave_h: float
		var flow: Vector3
		if probed:
			var local_c: Vector3 = pos_arr[i]
			var q := (1 if local_c.x > probe_center.x else 0) \
				+ (2 if local_c.z > probe_center.z else 0)
			wave_h = probe_h[q]
			flow = probe_flow[q]
		else:
			wave_h = _water_sampler.get_height_at(world_center, water_time, planet_pos)
			flow = _water_sampler.last_flow
		var water_r: float = base_water_radius + wave_h
		var dist: float = (world_center - planet_pos).length()

		var frac: float = clampf((water_r - (dist - h_half)) / (2.0 * h_half), 0.0, 1.0)
		if frac <= 0.0:
			continue

		var displaced: float = vol_arr[i] * frac
		submerged_volume += displaced
		weighted_buoyancy_pos += (world_center + up * h_half * (frac - 1.0)) * displaced
		weighted_flow += flow * displaced

	var water_vel := Vector3.ZERO
	if submerged_volume > 0.0:
		# Todos los empujes son paralelos a up: una única fuerza en el centro de carena es
		# exactamente equivalente a una por caja, y ahorra N llamadas al servidor de física.
		var buoyancy_center: Vector3 = weighted_buoyancy_pos / submerged_volume
		apply_force(up * WATER_DENSITY * gravity * submerged_volume, buoyancy_center - origin)

		var displaced_mass: float = submerged_volume * WATER_DENSITY
		# El rozamiento se mide contra el agua, no contra el suelo: un casco quieto en un mar que se
		# mueve recibe la misma fuerza que uno navegando en un mar quieto, y acaba arrastrado con la
		# ola. Con linear_drag = 0.3 el casco tarda unos 3 s en igualar la corriente.
		water_vel = weighted_flow / submerged_volume
		last_water_flow = water_vel
		last_displaced_mass = displaced_mass
		var rel_vel: Vector3 = linear_velocity - water_vel
		apply_central_force(-rel_vel * linear_drag * displaced_mass)
		var radial_vel: float = rel_vel.dot(up)
		apply_central_force(-up * radial_vel * heave_drag * displaced_mass)
		apply_torque(-angular_velocity * angular_drag * displaced_mass * minf(_drag_length_sq, 10.0))

		# Corrección de inclinación. OJO: el eje Y va negado a propósito. El eje resultante es el
		# correcto (negar el vector niega también el producto vectorial), pero el ángulo sale
		# 'π − escora', así que el par es máximo con el barco a plomo y decrece al inclinarse:
		# de facto una grúa permanente que lo mantiene derecho. Escrito "bien" (proporcional a la
		# escora real) el par se anula cerca del equilibrio, los barcos escoran, embarcan agua
		# por la banda baja y se hunden. Es feo, pero sostiene la flota: no lo toques sin
		# sustituirlo por estabilidad de verdad (metacentro).
		#
		# Lo que sí se hace es RETIRARLA cuando el casco está herido, en vez de arreglarla: con el
		# casco sano el par es idéntico al de siempre, y la flota se comporta igual que siempre.
		var assist := _heel_assist()
		var body_up := -global_transform.basis.y
		var angle_to_vertical := acos(clampf(body_up.dot(up), -1.0, 1.0))
		if assist > 0.0 and angle_to_vertical > deg_to_rad(5.0):
			var corrective_axis := up.cross(body_up).normalized()
			var correction_strength := (angle_to_vertical - deg_to_rad(5.0)) * displaced_mass * gravity * 0.1
			apply_torque(corrective_axis * correction_strength * assist)

	_update_flooding(up, planet_pos, base_water_radius, gravity)
	_update_wake(submerged_volume, up, planet_pos, base_water_radius, water_vel)


## Cuánta grúa de escora queda. La condición de entrada es binaria y sin ambigüedad —un casco sin
## compartimentos perforados devuelve 1.0 exacto— para que un barco sano no note absolutamente
## nada. Ya perforado, se va perdiendo con el agua embarcada hasta cero: entonces escora, se
## tumba y se hunde de costado en vez de irse a plomo.
func _heel_assist() -> float:
	if _breached_comps.is_empty() or _flood_capacity <= 0.0:
		return 1.0
	return clampf(1.0 - _flood_volume / (_flood_capacity * HEEL_ASSIST_FLOOD_LIMIT), 0.0, 1.0)


## Aplica el peso del agua embarcada como una única fuerza en el centroide cacheado. El estado
## de inundación solo se reevalúa cada FLOOD_RECALC_FRAMES o si el casco ha subido/bajado
## apreciablemente; la fuerza sí se aplica siempre (la física las limpia cada paso).
func _update_flooding(up: Vector3, planet_pos: Vector3, base_water_radius: float, gravity: float) -> void:
	var xf := global_transform
	var radius: float = (xf.origin - planet_pos).length()
	_flood_recalc_countdown -= 1

	if _flood_dirty or _flood_recalc_countdown <= 0 \
			or absf(radius - _flood_last_radius) > FLOOD_RECALC_HEAVE:
		_recalculate_flooding(xf, up, planet_pos, base_water_radius)
		_flood_recalc_countdown = FLOOD_RECALC_FRAMES
		_flood_last_radius = radius
		_flood_dirty = false

	if _flood_volume > 0.0:
		var centroid: Vector3 = xf * _flood_local_centroid
		apply_force(-up * gravity * _flood_volume * WATER_DENSITY, centroid - xf.origin)


## Reevalúa qué compartimentos están inundados y cachea el agua embarcada total y su
## centroide en espacio local del body (el casco se mueve, el centroide relativo no).
func _recalculate_flooding(xf: Transform3D, up: Vector3, planet_pos: Vector3, base_water_radius: float) -> void:
	var acc := Vector4.ZERO

	for comp: Dictionary in _compartments:
		var was_flooded: bool = comp.get("flooded", false)
		var flooded := _is_comp_flooded(comp, planet_pos, base_water_radius)
		comp["flooded"] = flooded
		if flooded != was_flooded:
			_dry_boxes_dirty = true
		if flooded:
			acc += _flood_weight(comp, xf, up, planet_pos, base_water_radius)

	for comp: Dictionary in _breached_comps:
		acc += _flood_weight(comp, xf, up, planet_pos, base_water_radius)

	_flood_volume = acc.w
	if acc.w > 0.0:
		_flood_local_centroid = xf.affine_inverse() * (Vector3(acc.x, acc.y, acc.z) / acc.w)


## Peso del agua de un compartimento (su volumen bajo el nivel del mar) como
## Vector4(centroide de la columna * m³, m³), para acumularlo en una sola fuerza.
func _flood_weight(comp: Dictionary, xf: Transform3D, up: Vector3, planet_pos: Vector3, base_water_radius: float) -> Vector4:
	var aabb: AABB = comp["aabb"]
	var half: Vector3 = aabb.size * 0.5
	var world_center: Vector3 = xf * aabb.get_center()
	var basis_w := xf.basis
	var h_half: float = absf((basis_w.x * half.x).dot(up)) \
		+ absf((basis_w.y * half.y).dot(up)) \
		+ absf((basis_w.z * half.z).dot(up))
	h_half = maxf(h_half, 0.05)

	var bottom_r: float = (world_center - planet_pos).length() - h_half
	var frac: float = clampf((base_water_radius - bottom_r) / (2.0 * h_half), 0.0, 1.0)
	if frac <= 0.0:
		return Vector4.ZERO

	var water: float = (comp["volume"] as float) * frac
	var centroid: Vector3 = world_center + up * h_half * (frac - 1.0)
	return Vector4(centroid.x * water, centroid.y * water, centroid.z * water, water)


## Compartimento del análisis nuevo que comparte celdas con uno previo (muestreo repartido
## por todo el compartimento: un resto vivo en cualquier zona cuenta como "sigue existiendo").
func _find_overlapping_comp(old: Dictionary, comps: Array) -> Dictionary:
	var old_cells: Dictionary = old["cells"]
	var stride: int = maxi(1, old_cells.size() / 64)
	var i := 0
	for cell: Vector3i in old_cells:
		if i % stride == 0:
			for comp: Dictionary in comps:
				if (comp["cells"] as Dictionary).has(cell):
					return comp
		i += 1
	return {}


## true si el compartimento tiene su apertura más baja bajo el nivel del mar (sin ola).
func _is_comp_flooded(comp: Dictionary, planet_pos: Vector3, base_water_radius: float) -> bool:
	if not comp.get("open", false):
		return false
	var sill_world: Vector3 = global_transform \
		* ((Vector3(comp["sill_cell"] as Vector3i) + Vector3.ONE * 0.5) * (comp["cell_size"] as float))
	return (sill_world - planet_pos).length() <= base_water_radius


## Cajas de compartimentos no inundados (body-local): la máscara del océano. Ordenadas por
## volumen descendente para que un truncado en MAX_INTERIORS pierda solo cajas pequeñas.
## Cacheada: solo se rehace cuando cambian los compartimentos o el conjunto de inundados.
func get_dry_interior_boxes() -> Array:
	if not _dry_boxes_dirty:
		return _dry_boxes_cache
	_dry_boxes_dirty = false

	var out: Array = []
	for comp: Dictionary in _compartments:
		if comp.get("flooded", false):
			continue
		out.append_array(comp["boxes"])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ha: Vector3 = a["half"]
		var hb: Vector3 = b["half"]
		return ha.x * ha.y * ha.z > hb.x * hb.y * hb.z)
	_dry_boxes_cache = out
	return out


## Estado de inundación para UI/depuración.
func get_flood_state() -> Dictionary:
	var flooded := 0
	for comp: Dictionary in _compartments:
		if comp.get("flooded", false):
			flooded += 1
	return {
		"volume": _flood_volume,
		"capacity": _flood_capacity,
		"compartments": _compartments.size(),
		"flooded": flooded,
		"breached": _breached_comps.size(),
		"heel_assist": _heel_assist(),
	}


## Emite y caduca los puntos de estela de espuma. Se guardan como offset desde el centro del
## planeta (inmune al rebase del origen flotante); FoamWakeManager los recoge cada frame.
func _update_wake(submerged_volume: float, up: Vector3, planet_pos: Vector3, base_water_radius: float,
		water_vel: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while not _wake_points.is_empty() and now - _wake_points[0]["birth"] > WAKE_LIFETIME:
		_wake_points.pop_front()

	if submerged_volume <= 0.0:
		_wake_active = false
		return
	# Velocidad respecto al agua: un pecio a la deriva viaja con la ola y no abre estela.
	var rel_vel := linear_velocity - water_vel
	var horiz_vel := rel_vel - up * rel_vel.dot(up)
	if horiz_vel.length() < WAKE_MIN_SPEED:
		_wake_active = false
		return

	# La estela nace en la popa, no en el centro: emitida en el centro queda bajo el casco, y un barco
	# largo tarda en despejar su eslora más de lo que vive el punto, así que se apagaba sin asomar.
	# La popa es el extremo de la caja del casco en el sentido contrario a la marcha, no -Z: así vale
	# igual ciando o derivando de costado, y el término vertical solo aporta con el barco escorado.
	var back := -horiz_vel.normalized()
	var stern := get_hull_center_world()
	if _aggregate_box.has("half"):
		var h: Vector3 = _aggregate_box["half"]
		var b := global_transform.basis
		stern += back * (absf(b.x.dot(back)) * h.x
			+ absf(b.y.dot(back)) * h.y
			+ absf(b.z.dot(back)) * h.z)

	# La popa en local: con ella GridManager recoloca la cabeza en cada frame renderizado.
	_wake_stern_local = global_transform.affine_inverse() * stern
	_wake_active = true

	var surf_offset := (stern - planet_pos).normalized() * base_water_radius
	var spacing := maxf(WAKE_SPACING, horiz_vel.length() * WAKE_LIFETIME / float(WAKE_MAX_POINTS))

	# Manga del casco y nada más: el shader une los puntos por tramos, así que el radio no tiene que
	# estirarse para tapar el hueco hasta el siguiente punto.
	var beam := 2.0
	if _aggregate_box.has("half"):
		var h: Vector3 = _aggregate_box["half"]
		beam = clampf(minf(h.x, h.z), 1.5, 12.0)

	# El último punto es la cabeza y va pegada a la popa cada frame; los demás quedan fijos. Emitir
	# solo al cumplir 'spacing' hacía crecer la estela a tirones de 3 m en vez de salir del barco.
	if _wake_points.size() < 2:
		_wake_points.append({"offset": surf_offset, "birth": now, "width": beam})
		_wake_points.append({"offset": surf_offset, "birth": now, "width": beam})
		return

	var head: Dictionary = _wake_points.back()
	head["offset"] = surf_offset
	head["birth"] = now
	head["width"] = beam

	# La cabeza se congela y nace otra en cuanto se aleja lo suficiente del último punto fijo.
	var anchor: Vector3 = _wake_points[_wake_points.size() - 2]["offset"]
	if (surf_offset - anchor).length() >= spacing:
		_wake_points.append({"offset": surf_offset, "birth": now, "width": beam})
		if _wake_points.size() > WAKE_MAX_POINTS:
			_wake_points.pop_front()


func get_wake_points() -> Array:
	return _wake_points


## Popa en el frame renderizado, como offset desde el centro del planeta, o ZERO si el barco no abre
## estela. Los puntos se comprometen a ritmo de física mientras el casco se dibuja con la transform
## interpolada, y a velocidad alta esa diferencia se ve como que la estela se descuelga del barco.
func get_wake_head_offset() -> Vector3:
	if not _wake_active or planet_node == null:
		return Vector3.ZERO
	var stern: Vector3 = get_global_transform_interpolated() * _wake_stern_local
	var base_r: float = planet_node.planet.radius - planet_node.planet.water_radius
	return (stern - planet_node.global_pos).normalized() * base_r


## Centro geométrico del casco en mundo (centro de la bounding box de las cajas de colisión).
func get_hull_center_world() -> Vector3:
	if _recalc_boxes:
		_recalculate_buoyancy_boxes()
	if _aggregate_box.has("pos"):
		return global_transform * (_aggregate_box["pos"] as Vector3)
	return global_position


## Bounding box del casco en espacio local del body: {pos: centro, half: semiejes}.
func get_hull_bounds() -> Dictionary:
	if _recalc_boxes:
		_recalculate_buoyancy_boxes()
	return _aggregate_box


## true si el punto cae dentro de algún compartimento SECO (aire interior sin inundar).
func is_point_in_dry_interior(world_point: Vector3) -> bool:
	if _compartments.is_empty():
		return false
	var local: Vector3 = global_transform.affine_inverse() * world_point
	for comp: Dictionary in _compartments:
		if comp.get("flooded", false):
			continue
		if not (comp["aabb"] as AABB).grow(0.05).has_point(local):
			continue
		for box: Dictionary in comp["boxes"]:
			var d: Vector3 = (local - (box["pos"] as Vector3)).abs()
			var half: Vector3 = box["half"]
			if d.x <= half.x + 0.05 and d.y <= half.y + 0.05 and d.z <= half.z + 0.05:
				return true
	return false


## true si un punto world cae dentro de la bounding box del casco (opcionalmente ampliada).
func contains_point(world_point: Vector3, margin: float = 0.0) -> bool:
	if _recalc_boxes:
		_recalculate_buoyancy_boxes()
	if not _aggregate_box.has("pos"):
		return false
	var local := global_transform.affine_inverse() * world_point
	var d := (local - (_aggregate_box["pos"] as Vector3)).abs()
	var half: Vector3 = _aggregate_box["half"]
	return d.x <= half.x + margin and d.y <= half.y + margin and d.z <= half.z + margin


func get_current_speed_level() -> int:
	return _boat_speed_index

func get_current_speed() -> float:
	return _boat_current_speed

func stop() -> void:
	_boat_speed_index = 0
	_boat_target_speed = 0.0
