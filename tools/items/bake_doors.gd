extends SceneTree

## Iconos de la puerta y la trampilla de madera desde su misma malla (DoorMesh.make), por la
## cara de los travesaños, con el estudio de luz del inventario.
## godot --path . --script res://tools/items/bake_doors.gd -- --background
const Renderer = preload("res://tools/ui/item_icon_renderer.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var door := MeshInstance3D.new()
	door.mesh = DoorMesh.make(Vector2i(1, 3))
	await Renderer.render(self, door, [-24.0, 205.0], "res://textures/icons/items/survival/wooden_door.png",
		false, 8.0)
	var trapdoor := MeshInstance3D.new()
	trapdoor.mesh = DoorMesh.make(Vector2i(1, 1))
	await Renderer.render(self, trapdoor, [0.0, 215.0], "res://textures/icons/items/survival/wooden_trapdoor.png",
		false, 40.0)
	quit()
