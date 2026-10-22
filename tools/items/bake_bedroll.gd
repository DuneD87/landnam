extends SceneTree

## Icono desde la misma malla del lecho, con el estudio de luz del inventario.
## godot --path . --script res://tools/items/bake_bedroll.gd -- --background
const Visual = preload("res://scripts/world/bedroll_visual.gd")
const Renderer = preload("res://tools/ui/item_icon_renderer.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model := MeshInstance3D.new()
	model.mesh = Visual.make_mesh()
	await Renderer.render(self, model, [-12.0, -28.0],
		"res://textures/icons/items/survival/bedroll.png", false, 58.0)
	quit()
