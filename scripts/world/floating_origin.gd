extends Node3D
class_name FloatingOrigin

## Origen flotante (rebasing): mantiene al jugador cerca del origen del mundo desplazando todo el
## mundo cuando se aleja más de 'rebase_threshold', para evitar grietas entre chunks por la
## precisión de float32 lejos del origen. Marco canónico = el original de la escena;
## global_canónico = global_actual + total_offset.

@export var player_path: NodePath
@export var planets_path: NodePath
## Distancia al origen a la que se rebasa. Más alto = menos rebases pero más distancia al origen.
@export var rebase_threshold: float = 4000.0
## Imprime en consola cada rebase.
@export var debug_log: bool = false

## Desplazamiento acumulado respecto al marco canónico.
var total_offset: Vector3 = Vector3.ZERO

@onready var _player: Node3D = get_node_or_null(player_path)
@onready var _planets: Node3D = get_node_or_null(planets_path)

func _ready() -> void:
	add_to_group("floating_origin_manager")
	process_physics_priority = 100
	RenderingServer.global_shader_parameter_set("u_world_offset", total_offset)

func _physics_process(_delta: float) -> void:
	if _player == null or _planets == null:
		return
	if GameManager.current_state != GameManager.State.PLAYING:
		return
	var pos := _player.global_position
	if pos.length() <= rebase_threshold:
		return
	_rebase(pos)

## Resta 'offset' a todo el mundo, devolviendo al jugador cerca del origen sin cambiar posiciones relativas.
func _rebase(offset: Vector3) -> void:
	for child in _planets.get_children():
		if child is Node3D:
			child.position -= offset

	_player.global_position -= offset

	if _player.has_method("shift_origin"):
		_player.shift_origin(offset)

	for node in get_tree().get_nodes_in_group("floating_origin"):
		if node is Node3D and node != _player:
			node.global_position -= offset
			node.reset_physics_interpolation()

	_player.reset_physics_interpolation()
	for child in _planets.get_children():
		if child is Node3D:
			child.reset_physics_interpolation()

	for child in _planets.get_children():
		if child.has_method("refresh_world_anchors"):
			child.refresh_world_anchors()

	total_offset += offset
	RenderingServer.global_shader_parameter_set("u_world_offset", total_offset)

	if debug_log:
		print("[FloatingOrigin] rebase offset=", offset, "  total_offset=", total_offset)

## Convierte una posición del marco actual (desplazado) al marco canónico original (para guardado).
func to_canonical(pos: Vector3) -> Vector3:
	return pos + total_offset
