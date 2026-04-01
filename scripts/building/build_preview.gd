class_name BuildPreview
extends Node3D

## Preview y control de colocación. Hijo del Player.
## Usa GridManager/PlanetGrid para colocar bloques en grids estables.
##
## Controles:
##   Click izquierdo / P: colocar bloque
##   Click derecho: salir de build mode
##   R: rotar
##   X: eliminar bloque apuntado
##   Tab / Scroll: cambiar tipo de bloque

# ============================================================
#  CONFIGURACIÓN
# ============================================================

@export var ray_distance: float = 8.0
@export var ghost_color_valid: Color = Color(0.3, 0.8, 1.0, 0.35)
@export var ghost_color_invalid: Color = Color(1.0, 0.2, 0.2, 0.35)
@export_flags_3d_physics var ray_collision_mask: int = 3

# ============================================================
#  ESTADO INTERNO
# ============================================================

var _building_system: BuildingSystem = null
var _camera: Camera3D = null

var _ghost_node: Node3D = null
var _ghost_mesh_instance: MeshInstance3D = null
var _ghost_material: StandardMaterial3D = null

var _ray_hit: Dictionary = {}
var _target_world_pos: Vector3 = Vector3.ZERO
var _target_basis: Basis = Basis.IDENTITY
var _can_place: bool = false
var _is_aiming_at_block: bool = false
var is_ctrl_held: bool = false

var _target_grid: PlanetGrid = null
var _target_grid_pos: Vector3i = Vector3i.ZERO


# ============================================================
#  LIFECYCLE
# ============================================================

func _ready() -> void:
	_building_system = _find_sibling(BuildingSystem) as BuildingSystem
	if not _building_system:
		push_error("[BuildPreview] No se encontró BuildingSystem como hermano.")
		return
	
	_camera = _find_camera_recursive(get_parent())
	if not _camera:
		push_error("[BuildPreview] No se encontró Camera3D.")
		return
	
	_setup_ghost()
	_building_system.selected_block_changed.connect(_on_block_changed)
	_building_system.build_mode_changed.connect(_on_build_mode_changed)
	_building_system.rotation_changed.connect(_on_rotation_changed)
	_building_system.cell_size_changed.connect(_on_cell_size_changed)

	_ghost_node.visible = false

func _on_rotation_changed() -> void:
	_update_ghost_mesh()
	
func _process(_delta: float) -> void:
	if Input.is_action_pressed("left_shift"):
		is_ctrl_held = true
	else:
		is_ctrl_held = false
	if not _building_system or not _building_system.build_mode:
		return
	
	_perform_raycast()
	_update_ghost()


func _unhandled_input(event: InputEvent) -> void:
	if not _building_system or not _building_system.build_mode:
		return
	
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_try_place_block()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				_building_system.toggle_build_mode()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				if is_ctrl_held:
					_building_system.increase_cell_size()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if is_ctrl_held:
					_building_system.decrease_cell_size()
				get_viewport().set_input_as_handled()
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_X:
				_try_remove_block()
				get_viewport().set_input_as_handled()
			KEY_TAB:
				_building_system.select_next_block()
				get_viewport().set_input_as_handled()
			KEY_P:
				_try_place_block()
				get_viewport().set_input_as_handled()
			KEY_L:
				if _ray_hit.is_empty() or not _is_aiming_at_block:
					return
				
				var hit_collider := _ray_hit["collider"] as Node3D
				var grid: PlanetGrid = GridManager.get_grid_for_block(hit_collider)
				print(grid.get_block_count(), ": ",grid.grid_id)
		if event.is_action_pressed("rotate_block_x"):
			_building_system.rotate_block_x()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("rotate_block_y"):
			_building_system.rotate_block_y()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("rotate_block_z"):
			_building_system.rotate_block_z()
			get_viewport().set_input_as_handled()


# ============================================================
#  RAYCAST (tercera persona, dos pasos)
# ============================================================

func _perform_raycast() -> void:
	_ray_hit = {}
	_can_place = false
	_is_aiming_at_block = false
	_target_grid = null
	
	if not _camera or not _camera.current:
		return
	
	var viewport := get_viewport()
	var screen_center := viewport.get_visible_rect().size * 0.5
	var space_state := get_world_3d().direct_space_state
	
	var player := get_parent()
	var player_rid: RID = player.get_rid() if player is CollisionObject3D else RID()
	
	# Paso 1: Ray desde la cámara
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
	
	# Paso 2: Check distancia desde player
	var hit_pos: Vector3 = cam_hit["position"]
	if player.global_position.distance_to(hit_pos) > ray_distance:
		return
	
	_ray_hit = cam_hit
	var hit_normal: Vector3 = _ray_hit["normal"]
	var hit_collider: Object = _ray_hit["collider"]
	
	_is_aiming_at_block = hit_collider is StaticBody3D and hit_collider.has_meta("grid_id")
	
	var cell := _building_system.cell_size
	
	if _is_aiming_at_block:
		var hit_grid := GridManager.get_grid_for_block(hit_collider as Node3D)
		if not hit_grid:
			return
		
		var planet := _building_system.current_planet
		if not planet:
			return
		
		var block_transform := (hit_collider as Node3D).global_transform
		var block_basis := block_transform.basis
		var hit_grid_pos: Vector3i = hit_collider.get_meta("grid_pos")
		var hit_cell := hit_grid.cell_size
		var target_cell := _building_system.cell_size
		
		# --- Cara impactada (robusto, desde normal) ---
		var local_normal := block_basis.inverse() * hit_normal
		var abs_n := Vector3(abs(local_normal.x), abs(local_normal.y), abs(local_normal.z))
		var face_dir := Vector3.ZERO
		if abs_n.x >= abs_n.y and abs_n.x >= abs_n.z:
			face_dir.x = 1.0 if local_normal.x > 0 else -1.0
		elif abs_n.y >= abs_n.x and abs_n.y >= abs_n.z:
			face_dir.y = 1.0 if local_normal.y > 0 else -1.0
		else:
			face_dir.z = 1.0 if local_normal.z > 0 else -1.0
		
		# Face dir en espacio grid
		var hit_rot_basis: Basis = hit_collider.get_meta("rotation_basis")
		var grid_face_f := hit_rot_basis * face_dir
		var grid_face := Vector3i(
			roundi(grid_face_f.x),
			roundi(grid_face_f.y),
			roundi(grid_face_f.z)
		)
		
		if is_equal_approx(target_cell, hit_cell):
			# ========== MISMO TAMAÑO: aritmética pura ==========
			_target_grid_pos = hit_grid_pos + grid_face
			_target_grid = hit_grid
			_target_world_pos = _target_grid.grid_to_world(_target_grid_pos)
			_target_basis = _target_grid.get_basis_world()
			_can_place = not _target_grid.has_block(_target_grid_pos)
		else:
			# ========== DISTINTO TAMAÑO: híbrido ==========
			# Eje de la cara → aritmético (robusto)
			# Ejes tangentes → hit_pos snapped a target_cell (sub-celda)
			
			var face_axis: int = 0
			var face_sign: int = 1
			if abs(grid_face.x) > 0:
				face_axis = 0; face_sign = grid_face.x
			elif abs(grid_face.y) > 0:
				face_axis = 1; face_sign = grid_face.y
			else:
				face_axis = 2; face_sign = grid_face.z
			
			# hit_pos en espacio continuo de la grid (misma base que todas las grids alineadas)
			var planet_inv := planet.global_transform.affine_inverse()
			var hit_local := planet_inv * hit_pos
			var hit_continuous := hit_grid.basis_local.inverse() * (hit_local - hit_grid.origin_local)
			
			# Bounds del bloque impactado en espacio continuo
			var block_min := Vector3(hit_grid_pos) * hit_cell
			var block_max := block_min + Vector3.ONE * hit_cell
			
			# Calcular posición continua del target
			var target_continuous := Vector3.ZERO
			for i in 3:
				if i == face_axis:
					# Aritmético: justo fuera de la cara
					if face_sign > 0:
						target_continuous[i] = block_max[i]
					else:
						target_continuous[i] = block_min[i] - target_cell
				else:
					# Tangente: snap del hit_pos a resolución target
					target_continuous[i] = floor(hit_continuous[i] / target_cell) * target_cell
			
			_target_grid_pos = Vector3i(
				roundi(target_continuous.x / target_cell),
				roundi(target_continuous.y / target_cell),
				roundi(target_continuous.z / target_cell)
			)
			
			# World pos desde espacio continuo
			var snapped_local := hit_grid.origin_local + hit_grid.basis_local * target_continuous
			_target_world_pos = planet.global_transform * snapped_local
			_target_basis = hit_grid.get_basis_world()
			
			# Buscar grid del target_cell size
			_target_grid = GridManager.find_nearest_grid(planet, _target_world_pos, target_cell)
			
			_can_place = true
			if _target_grid and _target_grid.has_block(_target_grid_pos):
				_can_place = false
			if _can_place:
				var overlap_grid := _target_grid if _target_grid else hit_grid
				if GridManager.check_overlap(planet, _target_grid_pos, target_cell, overlap_grid):
					_can_place = false
		
	else:
		var player_basis := _building_system.get_player_basis()
		var adjusted_pos := hit_pos + hit_normal * (cell * 0.5)
		
		# Buscar grid cercana o preparar para crear una nueva
		var planet := _building_system.current_planet
		if planet:
			_target_grid = GridManager.find_nearest_grid(planet, adjusted_pos, _building_system.cell_size)
		
		if _target_grid:
			# Usar la grid existente
			_target_grid_pos = _target_grid.world_to_grid(adjusted_pos)
			_target_world_pos = _target_grid.grid_to_world(_target_grid_pos)
			_target_basis = _target_grid.get_basis_world()
			_can_place = not _target_grid.has_block(_target_grid_pos)
			
		else:
			# No hay grid cerca, se creará una nueva al colocar
			_target_basis = player_basis
			# Snap manual con el basis del player
			var relative := adjusted_pos - (planet.global_position if planet else Vector3.ZERO)
			var local_pos := _target_basis.inverse() * relative
			local_pos.x = snapped(local_pos.x, cell)
			local_pos.y = snapped(local_pos.y, cell)
			local_pos.z = snapped(local_pos.z, cell)
			_target_world_pos = (planet.global_position if planet else Vector3.ZERO) + _target_basis * local_pos
			_can_place = true
	
	# Check distancia final
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
	
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.render_priority = 5
	_ghost_material.albedo_color = ghost_color_valid
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.no_depth_test = false
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mesh_instance.material_override = _ghost_material
	
	_ghost_node.add_child(_ghost_mesh_instance)
	add_child(_ghost_node)
	_update_ghost_mesh()


func _update_ghost() -> void:
	if _ray_hit.is_empty():
		_ghost_node.visible = false
		return
	
	_ghost_node.visible = true
	_ghost_node.global_transform = Transform3D(_target_basis, _target_world_pos)
	
	var rot_basis := _building_system.get_rotation_basis()
	var s := _building_system.cell_size
	var center := Vector3(0, 0.5, 0) * s
	_ghost_mesh_instance.transform = Transform3D(
		rot_basis,
		center - rot_basis * center
	)
	
	_ghost_mesh_instance.scale = Vector3(s, s, s)
	_ghost_material.albedo_color = ghost_color_valid if _can_place else ghost_color_invalid


func _on_cell_size_changed(_new_size: float) -> void:
	_update_ghost_mesh()

func _update_ghost_mesh() -> void:
	if not _building_system:
		return
	var block_data := _building_system.get_selected_block()
	if block_data:
		_ghost_mesh_instance.mesh = block_data.mesh
		var s := _building_system.cell_size
		_ghost_mesh_instance.scale = Vector3(s, s, s)


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
	
	var planet := _building_system.current_planet
	if not planet:
		return
	
	var block_data := _building_system.get_selected_block()
	if not block_data:
		return
	
	# Resolver la grid: usar la existente o crear una nueva
	var grid := _target_grid
	if not grid:
		grid = GridManager.create_grid(
			planet,
			_target_world_pos,
			_target_basis,
			_building_system.cell_size
		)
		_target_grid_pos = grid.world_to_grid(_target_world_pos)
	
	# Colocar usando el transform exacto del ghost
	var block := grid.place_block(
		_target_grid_pos,
		block_data,
		_building_system.current_rotation_basis,
		_ghost_mesh_instance.global_transform   # ← mesh, no ghost_node
	)
	
	if block:
		pass  # feedback aquí


func _try_remove_block() -> void:
	if _ray_hit.is_empty() or not _is_aiming_at_block:
		return
	
	var hit_collider := _ray_hit["collider"] as Node3D
	var grid := GridManager.get_grid_for_block(hit_collider)
	if grid:
		var grid_pos: Vector3i = hit_collider.get_meta("grid_pos")
		grid.remove_block(grid_pos)


# ============================================================
#  HELPERS
# ============================================================

func _find_sibling(type: Variant) -> Node:
	var par := get_parent()
	if not par:
		return null
	for child in par.get_children():
		if is_instance_of(child, type):
			return child
	return null


func _find_camera_recursive(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for child in node.get_children():
		if child == self or child is BuildingSystem:
			continue
		var found := _find_camera_recursive(child)
		if found:
			return found
	return null
