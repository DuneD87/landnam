class_name BlueprintPlacer
extends Node3D

## Colocación de blueprints apuntando con el ratón: mantiene un ghost translúcido pegado al punto
## al que miras, orientado al "arriba" gravitatorio y girable alrededor de él, y lo instancia al
## confirmar. Los blueprints grandes muestran solo su caja envolvente: mallar un barco entero
## para elegir sitio cuesta más de lo que aporta.
##
## Al confirmar queda una obra (BlueprintSite) en la pose del ghost, sin pagar nada: se le aportan los
## materiales después y se levanta con el martillo. Cuesta lo mismo que poner cada bloque y cada
## colocable a mano (BuildCost). No se puede si choca con otra construcción o si queda demasiado
## lejos; el ghost se pone rojo y un panel (Saga) dice lo que costará, lo que se lleva y por qué no se
## puede. Construyendo gratis (BuildingSystem.free_build) se construye entera al confirmar, sin
## límite de distancia.

## Se emite al salir del modo colocación, por confirmación o por cancelación.
signal finished()

## Por qué no se puede colocar donde apunta.
enum Problem { NONE, OVERLAP, TOO_FAR }

## Por encima de este nº de bloques el ghost es una caja en vez de la geometría real.
const GHOST_BLOCK_LIMIT := 4000
## Alcance del rayo de colocación, y distancia a la que flota el ghost si no golpea nada.
const AIM_DISTANCE := 400.0
const FALLBACK_DISTANCE := 40.0
const YAW_STEP := deg_to_rad(15.0)
## El paso de desplazamiento manual sale del tamaño del blueprint: 1 m por muesca es cómodo en
## una cabaña y desesperante en un barco de 120 m.
const MOVE_STEP_FACTOR := 0.05
const MOVE_STEP_MIN := 0.5
const MOVE_STEP_MAX := 5.0
## Hasta dónde se puede colocar: el centro del blueprint a esto del jugador, más la mitad de su
## diagonal (un barco se coloca desde su borde).
const PLACE_REACH := 24.0
## Cada cuánto se mira si choca con otra construcción (s), y con cuántos bloques del blueprint como
## mucho; al confirmar se miran todos.
const CHECK_INTERVAL := 0.15
const CHECK_SAMPLES := 600

@export var ghost_color: Color = Color(0.3, 0.8, 1.0, 0.35)
@export var blocked_color: Color = Color(1.0, 0.3, 0.25, 0.4)
@export_flags_3d_physics var aim_collision_mask: int = 3

var _data: Dictionary = {}
var _planet: Node3D = null
var _player: Node3D = null
var _camera: Camera3D = null
var _ghost: Node3D = null
var _material: StandardMaterial3D = null
var _size: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _depth_offset: float = 0.0
var _height_offset: float = 0.0
var _move_step: float = 1.0
var _placement: Transform3D = Transform3D.IDENTITY
var _as_static: bool = false
var _active: bool = false
var _name: String = ""
var _inventory: Inventory = null
var _cost: Dictionary = {}
var _blocked_material: StandardMaterial3D = null
## Centro (en metros del blueprint) de cada bloque, para mirar si choca con otra construcción.
var _block_centers := PackedVector3Array()
var _problem := Problem.NONE
var _check_left := 0.0
var _hud: CanvasLayer = null
var _hud_root: Control = null
var _hud_costs: VBoxContainer = null
var _hud_state: Label = null
var _hud_title: Label = null
var _hud_hint: Label = null
var _hud_signature := ""
## Caja de cada grid (id → [edit_version, AABB]): un barco entero no se recorre cada vez.
var _bounds_cache := {}


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.render_priority = 5
	_material.albedo_color = ghost_color
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_blocked_material = _material.duplicate()
	_blocked_material.albedo_color = blocked_color

	_ghost = Node3D.new()
	_ghost.name = "BlueprintGhost"
	_ghost.top_level = true
	# El ghost se recoloca desde _process: con physics_interpolation activa en el proyecto,
	# interpolarlo lo dejaría un frame por detrás del punto al que apuntas.
	_ghost.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ghost.visible = false
	add_child(_ghost)


func is_active() -> bool:
	return _active


## Entra en modo colocación con el blueprint ya leído de disco. Con as_static, un blueprint
## dinámico se ancla al planeta en vez de reconstruirse como cuerpo dinámico. El panel compara lo
## que costará con lo que hay en [inventory].
func begin(data: Dictionary, planet: Node3D, player: Node3D, camera: Camera3D,
	as_static: bool = false, bp_name: String = "", inventory: Inventory = null) -> void:

	if data.is_empty() or not planet or not player or not camera:
		return

	_data = data
	_as_static = as_static
	_name = bp_name
	_inventory = inventory
	_cost = BuildCost.of_blueprint(data)
	_block_centers = _collect_block_centers(data)
	_problem = Problem.NONE
	_check_left = 0.0
	_planet = planet
	_player = player
	_camera = camera
	_size = GridBlueprint.get_size(data)
	_yaw = 0.0
	_depth_offset = 0.0
	_height_offset = 0.0
	_move_step = clampf(maxf(_size.x, maxf(_size.y, _size.z)) * MOVE_STEP_FACTOR,
		MOVE_STEP_MIN, MOVE_STEP_MAX)
	_active = true

	_build_ghost()
	_ghost.visible = true
	_show_hud()
	update_aim()


## Recoloca el ghost en el punto al que apunta la cámara. Se llama cada frame mientras está activo.
func update_aim() -> void:
	if not _active or not _camera or not _camera.current:
		return

	_placement = _compute_placement(_aim_point())
	_ghost.global_transform = _placement
	_check_left -= get_process_delta_time()
	if _check_left <= 0.0:
		_check_left = CHECK_INTERVAL
		_set_problem(_find_problem(CHECK_SAMPLES))


func add_yaw(steps: int) -> void:
	if not _active:
		return
	_yaw = wrapf(_yaw + steps * YAW_STEP, -PI, PI)
	update_aim()


## Aleja (+) o acerca (-) el blueprint respecto a la cámara, sobre el plano del suelo.
func move_depth(steps: int) -> void:
	if not _active:
		return
	_depth_offset += steps * _move_step
	update_aim()


## Sube (+) o baja (-) el blueprint a lo largo del "arriba" gravitatorio.
func move_height(steps: int) -> void:
	if not _active:
		return
	_height_offset += steps * _move_step
	update_aim()


## Lo que cuesta construirlo (id de objeto → cantidad).
func get_cost() -> Dictionary:
	return _cost


## Pone la obra en la pose del ghost (construyendo gratis, el blueprint entero) y sale del modo
## colocación. Si no se puede, sigue colocando y devuelve por qué (traducido); "" si se ha colocado.
func confirm() -> String:
	if not _active:
		return ""

	var problem := _find_problem(-1)
	_set_problem(problem)
	if problem != Problem.NONE:
		return _problem_text(problem)

	var t0 := Time.get_ticks_msec()
	if BuildingSystem.free_build:
		var grids := GridBlueprint.instantiate(_data, _planet, _placement.origin, _placement.basis,
			_as_static)
		var blocks := 0
		for grid: GridBase in grids:
			blocks += grid.get_block_count()
		print("[BlueprintPlacer] Colocado: %d grids, %d bloques en %d ms" % [
			grids.size(), blocks, Time.get_ticks_msec() - t0])
	else:
		BlueprintSite.create(_data, _planet, _placement, _name, _as_static)
		print("[BlueprintPlacer] Obra '%s' puesta en %d ms" % [_name, Time.get_ticks_msec() - t0])

	_end()
	return ""


func cancel() -> void:
	if not _active:
		return
	_end()


func _end() -> void:
	_active = false
	_ghost.visible = false
	_clear_ghost_meshes()
	_data = {}
	_cost = {}
	_block_centers = PackedVector3Array()
	_bounds_cache.clear()
	if _hud:
		_hud.visible = false
	finished.emit()


# --- Si se puede colocar ---------------------------------------------------------------------------

## El primer problema de colocarlo donde está el ghost. [samples] limita los bloques que se miran
## contra otras construcciones (-1, todos).
func _find_problem(samples: int) -> Problem:
	if not BuildingSystem.free_build:
		var center := _placement * (_size * 0.5)
		if _player.global_position.distance_to(center) > PLACE_REACH + _size.length() * 0.5:
			return Problem.TOO_FAR
	if _overlaps(samples):
		return Problem.OVERLAP
	return Problem.NONE


func _set_problem(problem: Problem) -> void:
	if problem == _problem:
		_refresh_hud()
		return
	_problem = problem
	var material := _material if problem == Problem.NONE else _blocked_material
	for child in _ghost.get_children():
		(child as MeshInstance3D).material_override = material
	_refresh_hud()


func _problem_text(problem: Problem) -> String:
	match problem:
		Problem.OVERLAP:
			return tr("BP_PLACE_OVERLAP")
		Problem.TOO_FAR:
			return tr("BP_PLACE_TOO_FAR")
	return ""


## Centro de cada bloque en metros del blueprint (la esquina de su grid en el origen).
static func _collect_block_centers(data: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	for grid_data: Dictionary in data.get("grids", []):
		var cell := float(grid_data.get("cell_size", 1.0))
		for key: String in (grid_data.get("blocks", {}) as Dictionary):
			var parts := key.split(",")
			if parts.size() >= 3:
				out.append((Vector3(int(parts[0]), int(parts[1]), int(parts[2])) + Vector3.ONE * 0.5) * cell)
	return out


## true si algún bloque del blueprint, puesto donde está el ghost, cae en una celda ocupada de otra
## construcción del planeta. Se mira primero si la caja del blueprint toca la de cada grid.
func _overlaps(samples: int) -> bool:
	if _block_centers.is_empty() or not _planet:
		return false
	var stride := 1 if samples < 0 or _block_centers.size() <= samples else ceili(float(_block_centers.size()) / samples)
	var box := AABB(Vector3.ZERO, _size)
	for grid: GridBase in GridManager.get_grids_for_planet(_planet):
		if grid.get_block_count() == 0:
			continue
		var to_grid := grid.get_grid_world_transform().affine_inverse() * _placement
		if not (to_grid * box).intersects(_grid_bounds_cached(grid)):
			continue
		for i in range(0, _block_centers.size(), stride):
			if grid.has_block(grid.world_to_cell(_placement * _block_centers[i])):
				return true
	return false


func _grid_bounds_cached(grid: GridBase) -> AABB:
	var cached: Array = _bounds_cache.get(grid.grid_id, [])
	if cached.is_empty() or cached[0] != grid.edit_version:
		cached = [grid.edit_version, _grid_bounds(grid)]
		_bounds_cache[grid.grid_id] = cached
	return cached[1]


## Caja de los bloques de una grid en su espacio (metros), con un margen de media celda.
static func _grid_bounds(grid: GridBase) -> AABB:
	var lo := Vector3i.MAX
	var hi := Vector3i.MIN
	for grid_pos: Vector3i in grid.get_all_blocks():
		lo = lo.min(grid_pos)
		hi = hi.max(grid_pos)
	return AABB(Vector3(lo) * grid.cell_size, Vector3(hi - lo + Vector3i.ONE) * grid.cell_size).grow(grid.cell_size * 0.5)


# --- Panel ------------------------------------------------------------------------------------------

func _show_hud() -> void:
	if _hud == null:
		_build_hud()
	var ui_scale := GameTheme.scale_for(get_viewport())
	_hud_root.theme = GameTheme.build(ui_scale)
	_hud_hint.custom_minimum_size.x = 640.0 * ui_scale
	_hud_title.text = _name if _name != "" else tr("BP_PLACE_TITLE")
	_hud_signature = ""
	_hud.visible = true
	_refresh_hud()


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 9
	add_child(_hud)
	_hud_root = Control.new()
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hud_root)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 24.0
	_hud_root.add_child(panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	_hud_title = Label.new()
	_hud_title.theme_type_variation = &"HeaderLabel"
	_hud_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hud_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hud_title)
	_hud_costs = VBoxContainer.new()
	_hud_costs.add_theme_constant_override("separation", 4)
	column.add_child(_hud_costs)
	_hud_state = Label.new()
	_hud_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hud_state)
	_hud_hint = Label.new()
	_hud_hint.theme_type_variation = &"HintLabel"
	_hud_hint.text = "GRID_PLACE_HINT"
	_hud_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hud_hint)


func _refresh_hud() -> void:
	if _hud == null or not _hud.visible:
		return
	# Solo se rehace si ha cambiado algo: lo que se lleva o el problema.
	var rows := BuildCost.rows(_cost, _inventory)
	var signature := "%d|%s|%s" % [_problem, BuildingSystem.free_build, str(rows.map(func(row: Array) -> int: return row[2]))]
	if signature == _hud_signature:
		return
	_hud_signature = signature
	for child in _hud_costs.get_children():
		_hud_costs.remove_child(child)
		child.queue_free()
	if BuildingSystem.free_build or _cost.is_empty():
		var free := Label.new()
		free.theme_type_variation = &"StatLabel"
		free.text = "BP_PLACE_FREE"
		free.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hud_costs.add_child(free)
	else:
		for row: Array in rows:
			var line := HBoxContainer.new()
			line.alignment = BoxContainer.ALIGNMENT_CENTER
			var icon := TextureRect.new()
			icon.texture = (row[0] as ItemData).icon
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(36, 36)
			line.add_child(icon)
			var item_name := Label.new()
			item_name.theme_type_variation = &"StatLabel"
			item_name.text = (row[0] as ItemData).get_display_name()
			line.add_child(item_name)
			var count := Label.new()
			count.theme_type_variation = &"BetterLabel" if row[2] >= row[1] else &"WorseLabel"
			count.text = "%d / %d" % [row[2], row[1]]
			line.add_child(count)
			_hud_costs.add_child(line)
	_hud_state.text = _problem_text(_problem) if _problem != Problem.NONE else tr("BP_PLACE_READY")
	_hud_state.theme_type_variation = &"WorseLabel" if _problem != Problem.NONE else &"BetterLabel"


## Punto del mundo al que apunta la cámara; si el rayo no golpea nada, un punto a media distancia
## para que el ghost siga siendo visible mientras buscas sitio.
func _aim_point() -> Vector3:
	var viewport := get_viewport()
	var screen_center := viewport.get_visible_rect().size * 0.5
	var origin := _camera.project_ray_origin(screen_center)
	var dir := _camera.project_ray_normal(screen_center)

	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * AIM_DISTANCE)
	query.collision_mask = aim_collision_mask
	if _player is CollisionObject3D:
		query.exclude = [(_player as CollisionObject3D).get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return origin + dir * FALLBACK_DISTANCE
	return hit["position"]


## Pose de la esquina de la grid para que el blueprint quede centrado sobre el punto apuntado y
## apoyado en él, con +Y contra la gravedad y +Z mirando a donde mira el jugador (más el yaw),
## desplazado por los offsets manuales de rueda.
func _compute_placement(point: Vector3) -> Transform3D:
	var up : Vector3 = -_planet.get_gravity_direction(point).normalized()

	# La profundidad se mide en la dirección de la vista, no en la del blueprint: girado 90º,
	# "hacia delante" tiene que seguir siendo alejarlo de ti.
	var anchor := point + _view_forward(up) * _depth_offset + up * _height_offset

	var forward := _player.global_transform.basis.z
	forward = (forward - up * forward.dot(up))
	if forward.length_squared() < 0.001:
		forward = _player.global_transform.basis.y
		forward = forward - up * forward.dot(up)
	forward = forward.normalized().rotated(up, _yaw)

	var right := up.cross(forward).normalized()
	var basis := Basis(right, up, forward)
	var origin := anchor - right * (_size.x * 0.5) - forward * (_size.z * 0.5)
	return Transform3D(basis, origin)


## Dirección de la cámara proyectada en el plano del suelo; si miras a plomo, el forward del
## jugador, que ahí sí está definido.
func _view_forward(up: Vector3) -> Vector3:
	var dir := -_camera.global_transform.basis.z
	dir = dir - up * dir.dot(up)
	if dir.length_squared() < 0.001:
		dir = _player.global_transform.basis.z
		dir = dir - up * dir.dot(up)
	return dir.normalized()


func _clear_ghost_meshes() -> void:
	for child in _ghost.get_children():
		child.queue_free()


## Construye el ghost: la geometría real de cada grid, o una caja envolvente si el blueprint
## tiene demasiados bloques como para mallarlo solo para colocarlo.
func _build_ghost() -> void:
	_clear_ghost_meshes()

	if int(_data.get("block_count", 0)) > GHOST_BLOCK_LIMIT:
		var box := BoxMesh.new()
		box.size = _size
		var instance := MeshInstance3D.new()
		instance.mesh = box
		instance.position = _size * 0.5
		instance.material_override = _material
		_ghost.add_child(instance)
		return

	for grid_data: Dictionary in _data.get("grids", []):
		var blocks := GridBlueprint.blocks_dict(grid_data)
		if blocks.is_empty():
			continue
		var mesh := ChunkMeshBuilder.build_mesh(blocks, float(grid_data.get("cell_size", 1.0)),
			Transform3D.IDENTITY)
		if not mesh:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _material
		_ghost.add_child(instance)
