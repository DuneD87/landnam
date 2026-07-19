## Collider de un árbol del PlanetForest cercano al jugador. Duck-types
## queue_free_and_notify_instancer() para reutilizar el flujo de tala existente
## de action_controller sin cambios en on_timeout.
class_name ForestTreeBody extends StaticBody3D

var forest: PlanetForest
var cell_id: Vector3i
var type_index: int = 0
var tree_index: int = 0
var source_scene: PackedScene
var registered_scene: Node


func queue_free_and_notify_instancer() -> void:
	if is_instance_valid(forest):
		forest.remove_tree(cell_id, type_index, tree_index)
	queue_free()
