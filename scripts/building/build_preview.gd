class_name BuildPreview
extends Node3D

## Preview y control de colocación de bloques.
## Añadir como hijo del Player, al mismo nivel que BuildingSystem.
##
## Funcionalidad:
##   - Raycast desde el centro de la cámara cada frame
##   - Muestra un ghost block semitransparente en la celda candidata
##   - Click izquierdo: colocar bloque
##   - Click derecho: salir del modo construcción
##   - R: rotar bloque
##   - X: eliminar bloque apuntado
##   - Tab / Scroll: cambiar tipo de bloque
##
## Requiere:
##   - BuildingSystem como hermano (mismo padre = player)
##   - Camera3D como hijo del player

# ============================================================
#  CONFIGURACIÓN
# ============================================================

## Distancia máxima del raycast.
@export var ray_distance: float = 8.0

## Color del ghost cuando se puede colocar.
@export var ghost_color_valid: Color = Color(0.3, 0.8, 1.0, 0.35)

## Color del ghost cuando NO se puede colocar.
@export var ghost_color_invalid: Color = Color(1.0, 0.2, 0.2, 0.35)

## Collision mask para el raycast (ajustar según tus layers).
## Por defecto: layer 1 (terrain/world) + layer 2 (bloques colocados).
@export_flags_3d_physics var ray_collision_mask: int = 3

# ============================================================
#  ESTADO INTERNO
# ============================================================

var _building_system: BuildingSystem = null
var _camera: Camera3D = null

## Ghost block nodes
var _ghost_node: Node3D = null
var _ghost_mesh_instance: MeshInstance3D = null
var _ghost_material: StandardMaterial3D = null

## Raycast result del frame actual
var _ray_hit: Dictionary = {}
var _target_grid_pos: Vector3i = Vector3i.ZERO
var _target_world_pos: Vector3 = Vector3.ZERO
var _can_place: bool = false
var _is_aiming_at_block: bool = false  # true si apuntamos a un bloque existente


# ============================================================
#  LIFECYCLE
# ============================================================

func _ready() -> void:
	# Buscar hermanos necesarios
	_building_system = _find_sibling(BuildingSystem) as BuildingSystem
	if not _building_system:
		push_error("[BuildPreview] No se encontró BuildingSystem como hermano.")
		return
	
	# Buscar la cámara (hija del player)
	_camera = _find_camera_in_parent()
	if not _camera:
		push_error("[BuildPreview] No se encontró Camera3D en el player.")
		return
	
	_setup_ghost()
	
	# Escuchar cambios de bloque para actualizar el ghost
	_building_system.selected_block_changed.connect(_on_block_changed)
	_building_system.build_mode_changed.connect(_on_build_mode_changed)
	
	# Ocultar ghost inicialmente
	_ghost_node.visible = false


func _process(_delta: float) -> void:
	if not _building_system or not _building_system.build_mode:
		return
	
	_perform_raycast()
	_update_ghost()


func _unhandled_input(event: InputEvent) -> void:
	if not _building_system or not _building_system.build_mode:
		return
	
	# --- Click izquierdo: colocar bloque ---
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_block()
			get_viewport().set_input_as_handled()
		
		# --- Click derecho: salir de build mode ---
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_building_system.toggle_build_mode()
			get_viewport().set_input_as_handled()
		
		# --- Scroll: cambiar bloque ---
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_building_system.select_next_block()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_building_system.select_previous_block()
			get_viewport().set_input_as_handled()
	
	# --- Teclas ---
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				_building_system.rotate_block()
				_update_ghost_mesh()
				get_viewport().set_input_as_handled()
			KEY_X:
				_try_remove_block()
				get_viewport().set_input_as_handled()
			KEY_TAB:
				_building_system.select_next_block()
				get_viewport().set_input_as_handled()


# ============================================================
#  RAYCAST
# ============================================================

func _perform_raycast() -> void:
	_ray_hit = {}
	_can_place = false
	_is_aiming_at_block = false
	
	if not _camera or not _camera.current:
		return
	
	var viewport := get_viewport()
	var screen_center := viewport.get_visible_rect().size * 0.5
	var space_state := get_world_3d().direct_space_state
	
	var player := get_parent()
	var player_rid: RID = player.get_rid() if player is CollisionObject3D else RID()
	
	# Paso 1: Ray desde la cámara para encontrar qué apunta el crosshair
	var cam_origin := _camera.project_ray_origin(screen_center)
	var cam_dir := _camera.project_ray_normal(screen_center)
	var cam_end := cam_origin + cam_dir * (ray_distance + _camera.global_position.distance_to(player.global_position))
	
	var cam_query := PhysicsRayQueryParameters3D.create(cam_origin, cam_end)
	cam_query.collision_mask = ray_collision_mask
	if player_rid.is_valid():
		cam_query.exclude = [player_rid]
	
	var cam_hit := space_state.intersect_ray(cam_query)
	if cam_hit.is_empty():
		return
	
	# Paso 2: Verificar que el player puede "ver" ese punto (no hay obstáculo entre medias)
	var target_point: Vector3 = cam_hit["position"]
	var player_eye: Vector3 = player.global_position + player.global_transform.basis.y * 1.0  # altura ojos
	
	var check_query := PhysicsRayQueryParameters3D.create(player_eye, target_point)
	check_query.collision_mask = ray_collision_mask
	if player_rid.is_valid():
		check_query.exclude = [player_rid]
	
	var check_hit := space_state.intersect_ray(check_query)
	
	# Usar el hit de la cámara (es lo que apunta el crosshair)
	_ray_hit = cam_hit
	
	var hit_pos: Vector3 = _ray_hit["position"]
	var hit_normal: Vector3 = _ray_hit["normal"]
	var hit_collider: Object = _ray_hit["collider"]
	
	# Comprobar distancia desde el player
	if player.global_position.distance_to(hit_pos) > ray_distance:
		_ray_hit = {}
		return
	
	_is_aiming_at_block = hit_collider is StaticBody3D and hit_collider.has_meta("block_id")
	
	# Misma lógica para terreno y bloques:
	# desplazar el hit_pos en dirección de la normal para caer en la celda adyacente
	var cell := _building_system.cell_size
	var adjusted_pos := hit_pos + hit_normal * (cell * 0.5)
	_target_grid_pos = _building_system.world_to_grid(adjusted_pos)
	
	_target_world_pos = _building_system.grid_to_world(_target_grid_pos)
	_can_place = not _building_system.has_block_at(_target_grid_pos)
	
	if player.global_position.distance_to(_target_world_pos) > _building_system.max_build_distance:
		_can_place = false


# ============================================================
#  GHOST BLOCK
# ============================================================

func _setup_ghost() -> void:
	_ghost_node = Node3D.new()
	_ghost_node.name = "GhostBlock"
	
	_ghost_mesh_instance = MeshInstance3D.new()
	_ghost_mesh_instance.name = "GhostMesh"
	
	# Material semitransparente
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.albedo_color = ghost_color_valid
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.no_depth_test = false
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mesh_instance.material_override = _ghost_material
	
	_ghost_node.add_child(_ghost_mesh_instance)
	
	# Añadir al nivel raíz (no como hijo del player, para que no se mueva con él)
	add_child(_ghost_node)
	
	# Cargar la mesh del bloque seleccionado
	_update_ghost_mesh()


func _update_ghost() -> void:
	if _ray_hit.is_empty():
		_ghost_node.visible = false
		return
	
	_ghost_node.visible = true
	
	# Calcular el transform del ghost en world space
	var block_data := _building_system.get_selected_block()
	var rotation_deg := _building_system.get_current_rotation_deg()
	var local_basis := _building_system.get_local_basis()
	
	# Basis alineado a la superficie + rotación del bloque
	var ghost_basis := local_basis
	if rotation_deg != 0.0:
		ghost_basis = ghost_basis * Basis(Vector3.UP, deg_to_rad(rotation_deg))
	
	_ghost_node.global_transform = Transform3D(ghost_basis, _target_world_pos)
	
	# Color según si se puede colocar o no
	_ghost_material.albedo_color = ghost_color_valid if _can_place else ghost_color_invalid


func _update_ghost_mesh() -> void:
	if not _building_system:
		return
	var block_data := _building_system.get_selected_block()
	if block_data:
		_ghost_mesh_instance.mesh = block_data.mesh


func _on_block_changed(_block_data: BlockData) -> void:
	_update_ghost_mesh()


func _on_build_mode_changed(active: bool) -> void:
	if _ghost_node:
		_ghost_node.visible = active
	if active:
		_update_ghost_mesh()


# ============================================================
#  ACCIONES
# ============================================================

func _try_place_block() -> void:
	if not _can_place or _ray_hit.is_empty():
		return
	
	var block := _building_system.place_block_at_transform(_target_grid_pos, _ghost_node.global_transform)
	if block:
		pass


func _try_remove_block() -> void:
	if _ray_hit.is_empty() or not _is_aiming_at_block:
		return
	
	var hit_pos: Vector3 = _ray_hit["position"]
	_building_system.remove_block(hit_pos)


# ============================================================
#  HELPERS
# =====================================================## Determina la celda adyacente basándose en qué cara del bloque se impactó.

## Busca un hermano (hijo del mismo padre) de un tipo específico.
func _find_sibling(type: Variant) -> Node:
	var parent := get_parent()
	if not parent:
		return null
	for child in parent.get_children():
		if is_instance_of(child, type):
			return child
	return null


## Busca una Camera3D en el subárbol del padre (player).
func _find_camera_in_parent() -> Camera3D:
	var parent := get_parent()
	if not parent:
		return null
	return _find_camera_recursive(parent)


func _find_camera_recursive(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for child in node.get_children():
		# No buscar dentro del BuildPreview ni BuildingSystem
		if child == self or child is BuildingSystem:
			continue
		var found := _find_camera_recursive(child)
		if found:
			return found
	return null
