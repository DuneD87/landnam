extends Node3D
class_name FloatingOrigin

## Origen flotante (rebasing). Mantiene al jugador cerca del origen del mundo
## desplazando todo el mundo cuando se aleja más de 'rebase_threshold'. Sin esto,
## a decenas de miles de unidades del origen la precisión de float32 (~mm) hace que
## las matrices de modelo de los mesh-blocks no casen y aparezcan grietas finas
## parpadeantes entre chunks del VoxelLodTerrain.
##
## Marco "canónico" = el original de la escena (planetas en su ancla del .tscn).
## En cualquier momento:  global_canónico = global_actual + total_offset.

@export var player_path: NodePath
@export var planets_path: NodePath
## A cuántas unidades del origen dejamos llegar al jugador antes de rebasar. Más alto =
## menos rebases (más barato), pero más distancia al origen. Las grietas aparecían a
## ~30000, así que 4000 deja precisión de sobra (ULP ~0.5 mm) rebasando 4x menos.
@export var rebase_threshold: float = 4000.0
## Imprime en consola cada rebase (útil para verificar; desactívalo en producción).
@export var debug_log: bool = true

## Desplazamiento acumulado respecto al marco canónico.
var total_offset: Vector3 = Vector3.ZERO

@onready var _player: Node3D = get_node_or_null(player_path)
@onready var _planets: Node3D = get_node_or_null(planets_path)

func _ready() -> void:
	add_to_group("floating_origin_manager")
	# Correr DESPUÉS del jugador (que se mueve en su propio _physics_process).
	process_physics_priority = 100
	# Estado inicial del offset global que lee el shader del terreno (planet_biomes).
	RenderingServer.global_shader_parameter_set("u_world_offset", total_offset)

func _physics_process(_delta: float) -> void:
	if _player == null or _planets == null:
		return
	# Solo rebasar en juego activo: evita interferir con la cinemática de entrada,
	# que interpola global_position hacia un spawn_point anclado al mundo.
	if GameManager.current_state != GameManager.State.PLAYING:
		return
	var pos := _player.global_position
	if pos.length() <= rebase_threshold:
		return
	_rebase(pos)

## Resta 'offset' a todo el mundo, devolviendo al jugador cerca del origen.
## Todo se desplaza por el MISMO vector → las posiciones relativas y la física no cambian.
func _rebase(offset: Vector3) -> void:
	# Planetas: desplazamos su .position (LOCAL). El nodo 'Planets' se queda en el
	# origen, así que planet.position sigue == su global (asunción del player_controller).
	for child in _planets.get_children():
		if child is Node3D:
			child.position -= offset

	_player.global_position -= offset
	
	if _player.has_method("shift_origin"):
		_player.shift_origin(offset)

	# Objetos sueltos bajo current_scene (osos, bloques colocados): se etiquetan al spawnear.
	for node in get_tree().get_nodes_in_group("floating_origin"):
		if node is Node3D and node != _player:
			node.global_position -= offset
			node.reset_physics_interpolation()

	# Evitar el tirón visual de un frame con interpolación de física activa.
	_player.reset_physics_interpolation()
	for child in _planets.get_children():
		if child is Node3D:
			child.reset_physics_interpolation()

	# Refrescar uniforms/cachés que guardan el centro del planeta en absoluto.
	for child in _planets.get_children():
		if child.has_method("refresh_world_anchors"):
			child.refresh_world_anchors()

	total_offset += offset
	# El terreno (material por-bloque) lee este global para reconstruir el centro real:
	# centro_desplazado = center_canónico - u_world_offset. Así NO hay que tocar 'center'
	# por bloque tras cada rebase.
	RenderingServer.global_shader_parameter_set("u_world_offset", total_offset)

	if debug_log:
		print("[FloatingOrigin] rebase offset=", offset, "  total_offset=", total_offset)

## Convierte una posición del marco actual (desplazado) al marco canónico original.
## Úsalo al GUARDAR posiciones del mundo para que sobrevivan a una recarga (donde el
## mundo se reconstruye en su ancla con total_offset = 0).
func to_canonical(pos: Vector3) -> Vector3:
	return pos + total_offset
