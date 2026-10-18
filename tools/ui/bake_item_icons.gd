extends SceneTree

## Iconos Saga desde las mallas del juego: luz de estudio común, materiales originales y alfa.
## No modifica mallas ni escenas. Requiere ventana y GPU.
## godot --path . --script res://tools/ui/bake_item_icons.gd -- --background [--only=flint_knife,...]

const Renderer = preload("res://tools/ui/item_icon_renderer.gd")
const SIZE := Renderer.SIZE
const WEAPONS := {
	"iron_sword": [-40.0, 82.0], "battle_axe": [-35.0, 82.0],
	"iron_mace": [-35.0, 75.0], "spear": [-40.0, 82.0],
	"greatsword": [-40.0, 82.0], "great_axe": [-35.0, 82.0],
	"war_hammer": [-35.0, 75.0], "hunting_bow": [-30.0, 82.0],
	"slingshot": [-25.0, -12.0], "arrow": [-40.0, 82.0],
	"branch": [-40.0, 82.0], "wooden_shield": [-8.0, -12.0],
	"iron_shield": [-8.0, -12.0], "heater_shield": [-8.0, -12.0],
	"flint_sword": [-40.0, 82.0], "flint_spear": [-40.0, 82.0],
	"flint_knife": [-40.0, 82.0], "bone_dagger": [-40.0, 82.0],
	"obsidian_sword": [-40.0, 82.0], "stone_club": [-35.0, 75.0],
	"stone_maul": [-35.0, 75.0], "hide_shield": [-8.0, -12.0],
	"bone_shield": [-8.0, -12.0],
}
const TOOLS := {
	"stone_axe_01": ["res://scenes/items/weapons/stone_axe_01.tscn", -35.0, -12.0],
	"stone_pickaxe_01": ["res://scenes/items/weapons/stone_pickaxe_01.tscn", -35.0, -12.0],
	"torch": ["res://scenes/items/torches/torch.tscn", -35.0, -12.0],
}


func _initialize() -> void:
	if "--background" in OS.get_cmdline_user_args():
		root.unfocusable = true
		root.position = Vector2i(-4000, -4000)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(SIZE, SIZE)
	var only: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7).split(",")
	for weapon in WEAPONS:
		if not only.is_empty() and weapon not in only:
			continue
		var mesh := load("res://data/items/meshes/weapons/%s.res" % weapon) as Mesh
		var model := MeshInstance3D.new()
		model.mesh = mesh
		Renderer.prepare_model(model, weapon)
		await Renderer.render(self, model, WEAPONS[weapon],
			"res://textures/icons/items/weapons/%s.png" % weapon, weapon == "hunting_bow")
	for tool in TOOLS:
		if not only.is_empty() and tool not in only:
			continue
		var entry: Array = TOOLS[tool]
		# Extrae solo la malla raíz: no activa luces, fuego, audio ni scripts del objeto.
		var scene := load(entry[0]) as PackedScene
		var source := scene.instantiate() as MeshInstance3D
		var model := MeshInstance3D.new()
		model.mesh = source.mesh
		# Los modelos importados de herramientas tienen su eje largo en Z; la antorcha, en Y.
		model.basis = Basis.IDENTITY if tool == "torch" else Basis(Vector3.RIGHT, -PI * 0.5)
		source.free()
		await Renderer.render(self, model, [entry[1], entry[2]],
			"res://textures/icons/items/tools/%s.png" % tool, false)
	print("Iconos Saga: %d renders guardados." % (WEAPONS.size() + TOOLS.size()))
	quit()
