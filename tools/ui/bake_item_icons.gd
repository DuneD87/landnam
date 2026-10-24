extends SceneTree

## Iconos Saga desde las mallas del juego: luz de estudio común, materiales originales y alfa.
## No modifica mallas ni escenas. Requiere ventana y GPU.
## godot --path . --script res://tools/ui/bake_item_icons.gd -- --background [--only=flint_knife,...]

const Renderer = preload("res://tools/ui/item_icon_renderer.gd")
const SIZE := Renderer.SIZE
## [giro sobre Z de cámara, guiñada] y, si hace falta, la inclinación hacia la cámara (grados): la
## azada se inclina para que se vea la cara de la hoja y no su canto.
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
	"stone_axe_01": [-35.0, 82.0], "stone_pickaxe_01": [-35.0, 82.0],
	"stone_hammer_01": [-35.0, 82.0], "stone_hoe_01": [-35.0, 82.0, -40.0],
}
const TOOL_ICONS := ["stone_axe_01", "stone_pickaxe_01", "stone_hammer_01", "stone_hoe_01"]
const TOOLS := {
	"torch": ["res://scenes/items/torches/torch.tscn", -35.0, -12.0],
}
## Armadura equipable (en el espacio de la piel del jugador: Y arriba, +Z al frente): giro,
## guiñada, qué se ve y, si va, la exposición. Los pares (manos, pies) muestran solo la pieza
## izquierda; la manopla, además, derecha con los dedos arriba y el dorso al frente. Las pieles
## con pelo, claras y mates, se queman con la luz de los demás objetos.
const ARMOR_SCENES := "res://scenes/items/armor/stone_age/%s_equipable.tscn"
const ARMOR := {
	"fur_mantle": [0.0, -20.0, "", 0.55], "fur_loincloth": [0.0, -20.0, "", 0.55],
	"fur_mittens": [0.0, -15.0, "hand", 0.55], "fur_moccasins": [0.0, -65.0, "foot", 0.55],
	"hide_tunic": [0.0, -20.0, ""], "hide_trousers": [0.0, -20.0, ""],
	"hide_mittens": [0.0, -15.0, "hand"], "hide_boots": [0.0, -65.0, "foot"],
}
const PLAYER_SKIN := "res://models/player/xavivar/firstage_human_male_player_skin.tres"
const CHEST = preload("res://scripts/world/wooden_chest_visual.gd")
const BACKPACK = preload("res://scripts/items/hide_backpack_visual.gd")


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
		var folder := "tools" if weapon in TOOL_ICONS else "weapons"
		var angles: Array = WEAPONS[weapon]
		await Renderer.render(self, model, angles,
			"res://textures/icons/items/%s/%s.png" % [folder, weapon], weapon == "hunting_bow",
			angles[2] if angles.size() > 2 else 0.0)
	for tool in TOOLS:
		if not only.is_empty() and tool not in only:
			continue
		var entry: Array = TOOLS[tool]
		# Extrae solo la malla raíz: no activa luces, fuego, audio ni scripts del objeto.
		var scene := load(entry[0]) as PackedScene
		var source := scene.instantiate() as MeshInstance3D
		var model := MeshInstance3D.new()
		model.mesh = source.mesh
		source.free()
		await Renderer.render(self, model, [entry[1], entry[2]],
			"res://textures/icons/items/tools/%s.png" % tool, false)
	for armor in ARMOR:
		if not only.is_empty() and armor not in only:
			continue
		var entry: Array = ARMOR[armor]
		var source := (load(ARMOR_SCENES % armor) as PackedScene).instantiate() as MeshInstance3D
		var model := MeshInstance3D.new()
		model.mesh = _left_piece(source.mesh) if entry[2] != "" else source.mesh
		if entry[2] == "hand":
			model.basis = _upright_hand()
		source.free()
		await Renderer.render(self, model, [entry[0], entry[1]],
			"res://textures/icons/items/armor/stone_age/%s.png" % armor, false, 0.0,
			entry[3] if entry.size() > 3 else 1.0)
	if only.is_empty() or "wooden_chest" in only:
		var model := MeshInstance3D.new()
		model.mesh = CHEST.make_mesh()
		await Renderer.render(self, model, [0.0, -30.0],
			"res://textures/icons/items/survival/wooden_chest.png", false, 20.0)
	if only.is_empty() or "hide_backpack" in only:
		var model := MeshInstance3D.new()
		model.mesh = BACKPACK.make_mesh()
		await Renderer.render(self, model, [-8.0, 155.0],
			"res://textures/icons/items/survival/hide_backpack.png", false, 8.0)
	print("Iconos Saga: horneado terminado.")
	quit()


## La pieza del lado izquierdo (+X) de un par, sin piel: el icono la encuadra sola. Conserva
## todas sus superficies y sus colores de vértice (las prendas de pieles con pelo se tiñen así).
func _left_piece(mesh: Mesh) -> ArrayMesh:
	var piece := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var remap := PackedInt32Array()
		remap.resize(vertices.size())
		var kept := 0
		for i in vertices.size():
			remap[i] = kept if vertices[i].x > 0.0 else -1
			kept += 1 if vertices[i].x > 0.0 else 0
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		for kind in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR]:
			var source = arrays[kind]
			if source == null:
				continue
			var per: int = source.size() / vertices.size()
			var packed = source.duplicate()
			packed.resize(kept * per)
			for i in vertices.size():
				if remap[i] >= 0:
					for k in per:
						packed[remap[i] * per + k] = source[i * per + k]
			out[kind] = packed
		var indices := PackedInt32Array()
		var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, source_indices.size(), 3):
			var a := remap[source_indices[t]]
			var b := remap[source_indices[t + 1]]
			var c := remap[source_indices[t + 2]]
			if a >= 0 and b >= 0 and c >= 0:
				indices.append_array([a, b, c])
		if indices.is_empty():
			continue
		out[Mesh.ARRAY_INDEX] = indices
		piece.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		piece.surface_set_material(piece.get_surface_count() - 1, mesh.surface_get_material(s))
	return piece


## Pone derecha la mano izquierda del cuerpo de referencia: dedos arriba, pulgar a la derecha
## y el dorso a cámara (sus articulaciones en el espacio de la piel, como las armaduras).
func _upright_hand() -> Basis:
	var skin: Skin = load(PLAYER_SKIN)
	var joints := {}
	for b in skin.get_bind_count():
		joints[skin.get_bind_name(b)] = skin.get_bind_pose(b).affine_inverse().origin
	var fingers: Vector3 = (joints[&"mixamorig_LeftHandMiddle4"] - joints[&"mixamorig_LeftHand"]).normalized()
	var thumb: Vector3 = joints[&"mixamorig_LeftHandThumb2"] - joints[&"mixamorig_LeftHand"]
	thumb = (thumb - fingers * fingers.dot(thumb)).normalized()
	var palm := fingers.cross(thumb)
	return Basis(Vector3.UP, Vector3.RIGHT, Vector3.FORWARD) * Basis(fingers, thumb, palm).inverse()
