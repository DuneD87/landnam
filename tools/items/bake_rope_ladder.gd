extends SceneTree

## Icono de la escala de cuerda desde su misma malla (un tramo corto, derecho), con el estudio de luz
## del inventario.
## godot --path . --script res://tools/items/bake_rope_ladder.gd -- --background
const Renderer = preload("res://tools/ui/item_icon_renderer.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model := MeshInstance3D.new()
	model.mesh = RopeLadder.make_mesh(1.3, 2.2)
	# La malla cuelga hacia +Y: se le da la vuelta.
	model.rotation = Vector3(0.0, 0.0, PI)
	await Renderer.render(self, model, [-32.0, -30.0],
		"res://textures/icons/items/survival/rope_ladder.png", false, 12.0)
	quit()
