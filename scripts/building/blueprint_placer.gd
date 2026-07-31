class_name BlueprintPlacer
extends Node3D

## Colocación de blueprints apuntando con el ratón: mantiene un ghost translúcido pegado al punto
## al que miras, orientado al "arriba" gravitatorio y girable alrededor de él, y lo instancia al
## confirmar. Los blueprints grandes muestran solo su caja envolvente: mallar un barco entero
## para elegir sitio cuesta más de lo que aporta.

## Se emite al salir del modo colocación, por confirmación o por cancelación.
signal finished()

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

@export var ghost_color: Color = Color(0.3, 0.8, 1.0, 0.35)
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
var _active: bool = false


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.render_priority = 5
	_material.albedo_color = ghost_color
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED

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


## Entra en modo colocación con el blueprint ya leído de disco.
func begin(data: Dictionary, planet: Node3D, player: Node3D, camera: Camera3D) -> void:
	if data.is_empty() or not planet or not player or not camera:
		return

	_data = data
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
	update_aim()


## Recoloca el ghost en el punto al que apunta la cámara. Se llama cada frame mientras está activo.
func update_aim() -> void:
	if not _active or not _camera or not _camera.current:
		return

	_placement = _compute_placement(_aim_point())
	_ghost.global_transform = _placement


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


## Instancia el blueprint en la pose del ghost y sale del modo colocación.
func confirm() -> void:
	if not _active:
		return

	var t0 := Time.get_ticks_msec()
	var grids := GridBlueprint.instantiate(_data, _planet, _placement.origin, _placement.basis)
	var blocks := 0
	for grid: GridBase in grids:
		blocks += grid.get_block_count()

	print("[BlueprintPlacer] Colocado: %d grids, %d bloques en %d ms" % [
		grids.size(), blocks, Time.get_ticks_msec() - t0])

	_end()


func cancel() -> void:
	if not _active:
		return
	_end()


func _end() -> void:
	_active = false
	_ghost.visible = false
	_clear_ghost_meshes()
	_data = {}
	finished.emit()


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
