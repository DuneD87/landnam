extends Node3D
class_name OceanSystem
@export var enable_wireframe: bool = false
@export var quadtree_material: Material
@export var wireframe_material: Material

var quadtree_manager: QuadTreeManager
var mesh_manager: QuadTreeMeshManager

func _ready():
	_setup_managers()
	
	if !enable_wireframe:
		mesh_manager.default_material = quadtree_material
	else:
		mesh_manager.default_material = wireframe_material
	
			
func _setup_managers():
	quadtree_manager = QuadTreeManager.new()
	mesh_manager = QuadTreeMeshManager.new()
	
	add_child(quadtree_manager)
	add_child(mesh_manager)
	
	mesh_manager.initialize(quadtree_manager)
