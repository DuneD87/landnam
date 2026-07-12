class_name DynamicGridBody
extends RigidBody3D

## RigidBody3D de una grid dinámica: gravedad planetaria + flotación de Arquímedes (empuje
## por volumen sumergido de las cajas de colisión fusionadas; masa por densidad de bloque),
## inundación por compartimentos interiores (analizados en worker thread) y movimiento
## según movement_type (barco; vehículo y nave pendientes).

enum MovementType { BOAT, LAND_VEHICLE, SPACESHIP }

@export var movement_type: MovementType = MovementType.BOAT
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

const WAKE_SPACING := 3.0
const WAKE_LIFETIME := 12.0
const WAKE_MAX_POINTS := 64
const WAKE_MIN_SPEED := 2.0

# Segundos sin ediciones antes de relanzar el análisis de interiores (coalesce de ráfagas).
const INTERIOR_DEBOUNCE := 0.3

var planet_node: Node3D = null

var _water_sampler: WaterHeightSampler = null
var _wake_points: Array = []

var _grids: Array = []
var _buoyancy_boxes: Array = []
var _aggregate_box: Dictionary = {}
var _drag_length_sq: float = 1.0
var _recalc_boxes: bool = true
var _is_being_controlled: bool = false

var _flood_volume: float = 0.0
var _flood_capacity: float = 0.0
var _compartments: Array = []
var _breached_comps: Array = []
var _interior_cell_size: float = 0.0
var _interior_dirty: bool = false
var _interior_debounce: float = 0.0
var _analysis_running: bool = false
var _analysis_task_id: int = -1

var _boat_speed_levels: Array[float] = [0.0, 5.0, 10.0, 20.0]
var _boat_speed_index: int = 0
var _boat_target_speed: float = 0.0
var _boat_current_speed: float = 0.0
@export var boat_acceleration: float = 3.0
@export var boat_deceleration: float = 5.0

signal speed_changed(level: int, speed: float)

func on_block_removed(_grid_pos: Vector3i, _grid: GridBase = null) -> void:
	mark_points_dirty()

func on_block_placed(_grid_pos: Vector3i, _block_id: int, _grid: GridBase = null) -> void:
	mark_points_dirty()

func mark_points_dirty() -> void:
	_recalc_boxes = true
	_interior_dirty = true
	_interior_debounce = INTERIOR_DEBOUNCE

## Reconstruye la lista de cajas de volumen del casco desde los colliders del body:
## cajas fusionadas de cubos tal cual, rampas/esquinas como caja de su celda a medio volumen.
func _recalculate_buoyancy_boxes() -> void:
	_recalc_boxes = false
	_buoyancy_boxes.clear()
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
		_buoyancy_boxes.append({"pos": pos, "half": half, "volume": volume})
		total_volume += volume

		if first:
			aabb = AABB(pos - half, half * 2.0)
			first = false
		else:
			aabb = aabb.expand(pos - half)
			aabb = aabb.expand(pos + half)

	if _buoyancy_boxes.is_empty():
		return

	_aggregate_box = {"pos": aabb.get_center(), "half": aabb.size * 0.5, "volume": total_volume}
	_drag_length_sq = maxf(1.0, (aabb.size * 0.5).length_squared())

	# Capacidad provisional (AABB − bloques); el análisis la sustituye por el volumen real.
	var box_volume := aabb.size.x * aabb.size.y * aabb.size.z
	_flood_capacity = maxf((box_volume - total_volume) * flood_capacity_factor, 0.0)


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
	add_to_group("floating_origin")
	add_to_group("dynamic_grid_body")
	_setup_water_sampler()

func _setup_water_sampler() -> void:
	if not planet_node:
		return
	if not planet_node.planet.has_water:
		return
	_water_sampler = WaterHeightSampler.new()
	add_child(_water_sampler)
	var mat: ShaderMaterial = planet_node.water_sphere.mesh_manager.default_material as ShaderMaterial
	if mat:
		_water_sampler.setup(mat)

func register_grid(grid) -> void:
	if not _grids.has(grid):
		_grids.append(grid)
	mark_points_dirty()

func unregister_grid(grid) -> void:
	_grids.erase(grid)
	update_mass_from_grids()
	mark_points_dirty()

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


func _physics_process(delta: float) -> void:
	if not planet_node or not is_inside_tree():
		return

	_handle_input(delta)
	_process_interior_analysis(delta)

	var planet_pos: Vector3 = planet_node.global_pos
	var dir: Vector3 = (planet_pos - global_position).normalized()
	var up: Vector3 = -dir
	var gravity: float = planet_node.gravity_strength

	apply_central_force(dir * gravity * mass)

	if not planet_node.planet.has_water or not _water_sampler:
		return

	if _recalc_boxes:
		_recalculate_buoyancy_boxes()

	if _buoyancy_boxes.is_empty():
		return

	var mat: ShaderMaterial = planet_node.water_sphere.mesh_manager.default_material as ShaderMaterial
	var water_time: float = WaterHeightSampler.get_water_time(mat)
	var base_water_radius: float = planet_node.planet.radius - planet_node.planet.water_radius

	var boxes: Array = _buoyancy_boxes
	var camera := get_viewport().get_camera_3d()
	if camera and camera.global_position.distance_squared_to(global_position) > buoyancy_lod_distance * buoyancy_lod_distance:
		boxes = [_aggregate_box]

	var shared_wave := boxes.size() > MAX_WAVE_SAMPLES
	var wave_h_shared := 0.0
	if shared_wave:
		wave_h_shared = _water_sampler.get_height_at(global_position, water_time, planet_pos)

	var basis_w := global_transform.basis
	var submerged_volume := 0.0
	var weighted_buoyancy_pos := Vector3.ZERO

	for box: Dictionary in boxes:
		var half: Vector3 = box["half"]
		var world_center: Vector3 = global_transform * (box["pos"] as Vector3)

		var h_half: float = absf((basis_w.x * half.x).dot(up)) \
			+ absf((basis_w.y * half.y).dot(up)) \
			+ absf((basis_w.z * half.z).dot(up))
		h_half = maxf(h_half, 0.05)

		var wave_h: float = wave_h_shared if shared_wave else _water_sampler.get_height_at(world_center, water_time, planet_pos)
		var water_r: float = base_water_radius + wave_h
		var dist: float = (world_center - planet_pos).length()

		var frac: float = clampf((water_r - (dist - h_half)) / (2.0 * h_half), 0.0, 1.0)
		if frac <= 0.0:
			continue

		var displaced: float = box["volume"] * frac
		var centroid: Vector3 = world_center + up * h_half * (frac - 1.0)
		apply_force(up * WATER_DENSITY * gravity * displaced, centroid - global_position)
		submerged_volume += displaced
		weighted_buoyancy_pos += centroid * displaced

	if submerged_volume > 0.0:
		var displaced_mass: float = submerged_volume * WATER_DENSITY
		apply_central_force(-linear_velocity * linear_drag * displaced_mass)
		var radial_vel: float = linear_velocity.dot(up)
		apply_central_force(-up * radial_vel * heave_drag * displaced_mass)
		apply_torque(-angular_velocity * angular_drag * displaced_mass * minf(_drag_length_sq, 10.0))

		# Corrección de inclinación: aplica un torque suave si el barco está muy inclinado.
		# Previene que se quede fijado pero sin ser tan agresivo como para volcar.
		var body_up := -global_transform.basis.y
		var angle_to_vertical := acos(clampf(body_up.dot(up), -1.0, 1.0))
		if angle_to_vertical > deg_to_rad(5.0):
			var corrective_axis := up.cross(body_up).normalized()
			var correction_strength := (angle_to_vertical - deg_to_rad(5.0)) * displaced_mass * gravity * 0.1
			apply_torque(corrective_axis * correction_strength)

	_update_flooding(delta, up, planet_pos, base_water_radius, water_time, gravity)
	_update_wake(submerged_volume, up, planet_pos, base_water_radius)


## Marca inundados los compartimentos con la fuga bajo el nivel del mar y aplica el peso del
## agua embarcada de inundados y perforados en el centroide de cada columna.
func _update_flooding(_delta: float, up: Vector3, planet_pos: Vector3, base_water_radius: float, _water_time: float, gravity: float) -> void:
	_flood_volume = 0.0

	for comp: Dictionary in _compartments:
		comp["flooded"] = _is_comp_flooded(comp, planet_pos, base_water_radius)
		if comp["flooded"]:
			_flood_volume += _apply_flood_weight(comp, up, planet_pos, base_water_radius, gravity)

	for comp: Dictionary in _breached_comps:
		_flood_volume += _apply_flood_weight(comp, up, planet_pos, base_water_radius, gravity)


## Peso del agua de un compartimento (su volumen bajo el nivel del mar) aplicado en el
## centroide de la columna; devuelve los m³ embarcados.
func _apply_flood_weight(comp: Dictionary, up: Vector3, planet_pos: Vector3, base_water_radius: float, gravity: float) -> float:
	var aabb: AABB = comp["aabb"]
	var half: Vector3 = aabb.size * 0.5
	var world_center: Vector3 = global_transform * aabb.get_center()
	var basis_w := global_transform.basis
	var h_half: float = absf((basis_w.x * half.x).dot(up)) \
		+ absf((basis_w.y * half.y).dot(up)) \
		+ absf((basis_w.z * half.z).dot(up))
	h_half = maxf(h_half, 0.05)

	var bottom_r: float = (world_center - planet_pos).length() - h_half
	var frac: float = clampf((base_water_radius - bottom_r) / (2.0 * h_half), 0.0, 1.0)
	if frac <= 0.0:
		return 0.0

	var water: float = (comp["volume"] as float) * frac
	var centroid: Vector3 = world_center + up * h_half * (frac - 1.0)
	apply_force(-up * gravity * water * WATER_DENSITY, centroid - global_position)
	return water


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
func get_dry_interior_boxes() -> Array:
	var out: Array = []
	for comp: Dictionary in _compartments:
		if comp.get("flooded", false):
			continue
		out.append_array(comp["boxes"])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ha: Vector3 = a["half"]
		var hb: Vector3 = b["half"]
		return ha.x * ha.y * ha.z > hb.x * hb.y * hb.z)
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
	}


## Emite y caduca los puntos de estela de espuma. Se guardan como offset desde el centro del
## planeta (inmune al rebase del origen flotante); FoamWakeManager los recoge cada frame.
func _update_wake(submerged_volume: float, up: Vector3, planet_pos: Vector3, base_water_radius: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while not _wake_points.is_empty() and now - _wake_points[0]["birth"] > WAKE_LIFETIME:
		_wake_points.pop_front()

	if submerged_volume <= 0.0:
		return
	var horiz_vel := linear_velocity - up * linear_velocity.dot(up)
	if horiz_vel.length() < WAKE_MIN_SPEED:
		return

	var surf_offset := (get_hull_center_world() - planet_pos).normalized() * base_water_radius
	var spacing := maxf(WAKE_SPACING, horiz_vel.length() * WAKE_LIFETIME / float(WAKE_MAX_POINTS))
	if not _wake_points.is_empty():
		var last: Vector3 = _wake_points.back()["offset"]
		if (surf_offset - last).length() < spacing:
			return

	var beam := 2.0
	if _aggregate_box.has("half"):
		var h: Vector3 = _aggregate_box["half"]
		beam = clampf(minf(h.x, h.z), 1.5, 12.0)
	beam = maxf(beam, spacing * 0.6)

	_wake_points.append({"offset": surf_offset, "birth": now, "width": beam})
	if _wake_points.size() > WAKE_MAX_POINTS:
		_wake_points.pop_front()


func get_wake_points() -> Array:
	return _wake_points


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
