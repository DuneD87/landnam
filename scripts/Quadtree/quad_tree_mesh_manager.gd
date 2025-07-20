extends Node3D
class_name QuadTreeMeshManager

@export var default_material: Material

var active_quads: Dictionary = {}
var quad_tree_manager: Node3D

func initialize(quadtree_manager: Node3D):
	quad_tree_manager = quadtree_manager
	quad_tree_manager.quadtree_changed.connect(_on_quadtree_changed)

func _on_quadtree_changed(active_quad_data: Array):
	_update_quad_surfaces(active_quad_data)

func _create_quad_surface(quad_info: Dictionary):
	var quad_surface = QuadSurface.new()
   
	quad_surface.setup(
	   	quad_info.position,
	   	quad_info.size,
	   	quad_info.face_normal,
	   	quad_info.face_up,
	   	quad_info.face_right,
	   	quad_info.level
	)
	quad_surface.mesh.surface_set_material(0, default_material)
	add_child(quad_surface)
	active_quads[quad_info.id] = quad_surface

func _update_quad_surface(quad_info: Dictionary):
	var quad_surface = active_quads[quad_info.id]
   
	if quad_surface.global_position != quad_info.position or quad_surface.quad_size != quad_info.size:
		quad_surface.setup(
		  		quad_info.position,
		  		quad_info.size,
		  		quad_info.face_normal,
		  		quad_info.face_up,
		  		quad_info.face_right,
		  		quad_info.level
		)

func _remove_quad_surface(quad_id):
	if active_quads.has(quad_id):
		var quad_surface = active_quads[quad_id]
		quad_surface.queue_free()
		active_quads.erase(quad_id)

func _update_quad_surfaces(quad_data: Array):
	var current_ids = active_quads.keys()
	var new_ids = []
	
	for quad_info in quad_data:
		var quad_id = quad_info.id
		new_ids.append(quad_id)
		
		if not active_quads.has(quad_id):
			_create_quad_surface(quad_info)
		else:
			_update_quad_surface(quad_info)
	
	for current_id in current_ids:
		if not current_id in new_ids:
			_remove_quad_surface(current_id)
