extends SceneTree

## Iconos Saga desde las mallas del juego: luz de estudio común, materiales originales y alfa.
## No modifica mallas ni escenas. Requiere ventana y GPU.
## godot --path . --script res://tools/ui/bake_item_icons.gd -- --background [--only=flint_knife,...]

const Renderer = preload("res://tools/ui/item_icon_renderer.gd")
const SIZE := Renderer.SIZE
const WeaponBake = preload("res://tools/combat/bake_weapons.gd")
const TOOLS := {
	"torch": ["res://scenes/items/torches/torch.tscn", -35.0, -12.0],
}
## Armadura equipable (en el espacio de la piel del jugador: Y arriba, +Z al frente): giro,
## guiñada, qué se ve y, si va, la exposición. Los pares (manos, pies) muestran solo la pieza
## izquierda; la manopla, además, derecha con los dedos arriba y el dorso al frente. Las pieles
## con pelo, claras y mates, se queman con la luz de los demás objetos.
const ARMOR := {
	"fur_mantle": [0.0, -20.0, "", 0.55], "fur_loincloth": [0.0, -20.0, "", 0.55],
	"fur_mittens": [0.0, -15.0, "hand", 0.55], "fur_moccasins": [0.0, -65.0, "foot", 0.55],
	"fur_headdress": [0.0, -40.0, ""], "boar_headdress": [0.0, -40.0, ""],
	"deer_headdress": [0.0, -40.0, ""], "fur_hood": [0.0, -40.0, ""],
	"fur_coat": [0.0, -20.0, "", 0.55], "fur_breeches": [0.0, -20.0, "", 0.55],
	"fur_gauntlets": [0.0, -15.0, "hand", 0.55], "fur_boots": [0.0, -65.0, "foot", 0.55],
	"boar_mantle": [0.0, -20.0, "", 0.55], "boar_loincloth": [0.0, -20.0, "", 0.55],
	"boar_mittens": [0.0, -15.0, "hand", 0.55], "boar_moccasins": [0.0, -65.0, "foot", 0.55],
	"deer_mantle": [0.0, -20.0, "", 0.55], "deer_loincloth": [0.0, -20.0, "", 0.55],
	"deer_mittens": [0.0, -15.0, "hand", 0.55], "deer_moccasins": [0.0, -65.0, "foot", 0.55],
	"fox_mantle": [0.0, -20.0, "", 0.55], "fox_loincloth": [0.0, -20.0, "", 0.55],
	"fox_mittens": [0.0, -15.0, "hand", 0.55], "fox_moccasins": [0.0, -65.0, "foot", 0.55],
	"bison_coat": [0.0, -20.0, "", 0.55], "bison_breeches": [0.0, -20.0, "", 0.55],
	"bison_gauntlets": [0.0, -15.0, "hand", 0.55], "bison_boots": [0.0, -65.0, "foot", 0.55],
	"antler_coat": [0.0, -20.0, "", 0.55], "antler_breeches": [0.0, -20.0, "", 0.55],
	"antler_gauntlets": [0.0, -15.0, "hand", 0.55], "antler_boots": [0.0, -65.0, "foot", 0.55],
	"arctic_coat": [0.0, -20.0, "", 0.55], "arctic_breeches": [0.0, -20.0, "", 0.55],
	"arctic_gauntlets": [0.0, -15.0, "hand", 0.55], "arctic_boots": [0.0, -65.0, "foot", 0.55],
	"hide_tunic": [0.0, -20.0, ""], "hide_trousers": [0.0, -20.0, ""],
	"hide_mittens": [0.0, -15.0, "hand"], "hide_boots": [0.0, -65.0, "foot"],
}
const LEGACY_ARMOR := {
	"firstage_skin_boots": "foot", "firstage_skin_chest": "", "firstage_skin_hands": "hand",
	"firstage_skin_hood": "", "firstage_skin_pants": "", "leather_boots": "foot",
	"leather_chest": "", "leather_hands": "hand", "leather_hood": "", "leather_leggings": "",
	"leather_chest_01": "", "leather_pants_01": "",
}
const BRONZE_ARMOR := {
	"lionheart_cuirass": [-5.0, -15.0, "", 0.88], "lionguard_kilt": [-7.0, -15.0, "", 0.86],
	"lionheart_boots": [0.0, -32.0, "foot", 0.88], "lionguard_gauntlets": [0.0, -20.0, "hand", 0.86],
	"hoplite_helm": [0.0, -35.0, "", 0.82], "hoplite_cuirass": [0.0, -15.0, "", 0.88],
	"hoplite_pteruges": [0.0, -15.0, "", 0.86], "hoplite_bracers": [-27.0, -22.0, "arm", 0.88],
	"hoplite_greaves": [0.0, -32.0, "foot", 0.88],
	"sunscale_coat": [0.0, -16.0, "", 0.75], "sunscale_breeches": [0.0, -16.0, "", 0.75],
	"sunscale_gauntlets": [0.0, -16.0, "hand", 0.75], "sunscale_boots": [0.0, -35.0, "foot", 0.75],
}
## Constructor, giro, guiñada e inclinación de la miniatura.
var props := {
	"throne": [preload("res://scripts/world/throne_visual.gd").make_mesh, 0, -32, 20],
	"rowing_bench": [preload("res://scripts/world/rowing_bench_visual.gd").make_mesh, 0, -32, 20],
	"feeding_trough": [preload("res://scripts/world/feeding_trough_visual.gd").make_mesh, 0, -32, 20],
	"water_trough": [preload("res://scripts/world/water_trough_visual.gd").make_mesh, 0, -32, 20],
	"wooden_chest": [preload("res://scripts/world/wooden_chest_visual.gd").make_mesh, 0, -30, 20],
	"hide_backpack": [preload("res://scripts/items/hide_backpack_visual.gd").make_mesh, -8, 155, 8],
	"bedroll": [preload("res://scripts/world/bedroll_visual.gd").make_mesh, -12, -28, 58],
	"rope_ladder": [RopeLadder.make_mesh.bind(1.3, 2.2), -32, -30, 12],
	"wooden_door": [DoorMesh.make.bind(Vector2i(1, 3)), -24, 205, 8],
	"wooden_trapdoor": [DoorMesh.make.bind(Vector2i(1, 1)), 0, 215, 40],
}
const VISUAL_SCENES := {
	"fishing_rod": ["fishing", "res://scenes/items/survival/fishing/fishing_rod.tscn", -36.0, 45.0, 0.0],
	"fishing_hook": ["fishing", "res://scenes/items/survival/fishing/fishing_hook.tscn", -25.0, 15.0, 0.0],
	"fishing_bait": ["fishing", "res://scenes/items/survival/fishing/fishing_bait.tscn", 25.0, 10.0, 0.0],
	"raw_fish": ["fishing", "res://scenes/items/survival/fishing/raw_fish.tscn", 22.0, 70.0, 8.0],
	"cooked_fish": ["fishing", "res://scenes/items/survival/fishing/cooked_fish.tscn", 22.0, 70.0, 8.0],
	"hide_sail": ["survival", "res://scenes/items/survival/hide_sail.tscn", 0.0, -25.0, 12.0],
	"hand_cannon": ["tools", "res://scenes/items/weapons/hand_cannon.tscn", 24.0, 62.0, 18.0],
}
const PLAYER_SKIN := "res://models/player/xavivar/firstage_human_male_player_skin.tres"


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
	for weapon in WeaponBake.WEAPONS:
		if only.is_empty() or weapon in only:
			await WeaponBake.render_weapon(self, weapon, load(WeaponBake.MESH_DIR + weapon + ".res"))
	for id in WeaponBake.SURVIVAL:
		if only.is_empty() or id in only:
			await WeaponBake.render_survival(self, id, load(WeaponBake.SURVIVAL_MESH_DIR + id + ".res"))
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
	var garments := ARMOR.duplicate()
	garments.merge(BRONZE_ARMOR)
	for id in LEGACY_ARMOR:
		var piece: String = LEGACY_ARMOR[id]
		garments[id] = [0.0, -45.0 if piece == "foot" else -15.0, piece, 0.82]
	for id in garments:
		if not only.is_empty() and id not in only:
			continue
		var item := ItemCatalog.get_item(id)
		var view: Array = garments[id]
		var model := (load(item.scene_path) as PackedScene).instantiate() as MeshInstance3D
		# Sin esqueleto se muestra la pose de reposo. Conserva los materiales y los broches de la escena.
		for part: MeshInstance3D in [model] + model.find_children("*", "MeshInstance3D", true, false):
			part.skin = null
			if view[2] != "":
				part.mesh = _left_piece(part.mesh)
		if view[2] == "hand":
			model.basis = _upright_hand()
		await Renderer.render(self, model, [view[0], view[1]], item.icon.resource_path,
			false, 0.0, view[3] if view.size() > 3 else 1.0)
	if only.is_empty() or "hoplite_aspis" in only:
		var shield := MeshInstance3D.new()
		shield.mesh = load("res://models/equipable/bronze_age/hoplite_aspis.res")
		await Renderer.render(self, shield, [-8.0, -20.0], "res://textures/icons/items/weapons/hoplite_aspis.png", false, 0.0, 0.85)
	for id in props:
		if not only.is_empty() and id not in only:
			continue
		var view: Array = props[id]
		var model := MeshInstance3D.new()
		model.mesh = (view[0] as Callable).call()
		if id == "rope_ladder":
			model.rotation.z = PI
		await Renderer.render(self, model, [view[1], view[2]],
			"res://textures/icons/items/survival/%s.png" % id, false, view[3])
	for id in VISUAL_SCENES:
		if not only.is_empty() and id not in only:
			continue
		var view: Array = VISUAL_SCENES[id]
		var model := (load(view[1]) as PackedScene).instantiate() as Node3D
		if id == "fishing_rod":
			model.scale = Vector3(2.5, 1.0, 2.5)
		await Renderer.render(self, model, [view[2], view[3]],
			"res://textures/icons/items/%s/%s.png" % [view[0], id], false, view[4])
	for id in ["wood", "stone"]:
		if only.is_empty() or id in only:
			var model := MeshInstance3D.new()
			model.mesh = _material_bundle(id)
			await Renderer.render(self, model, [0.0, -38.0], "res://textures/icons/items/collectable/icon_%s.png" % id, false, 18.0)
	print("Iconos Saga: horneado terminado.")
	quit()


## Una pila de tres unidades distingue el material suelto del bloque de construcción.
func _material_bundle(id: String) -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	if id == "stone":
		for i in 3:
			var at: Vector3 = [Vector3(-0.23, 0.0, 0.0), Vector3(0.22, 0.0, 0.03), Vector3(0.0, 0.21, 0.02)][i]
			WeaponMeshes.lump(b.st(WeaponMeshes.STONE), at, 0.32, 123 + i, 0.64)
	else:
		for at: Vector2 in [Vector2(-0.15, 0.0), Vector2(0.15, 0.0), Vector2(0.0, 0.235)]:
			var points := PackedVector3Array([Vector3(at.x, at.y, -0.38), Vector3(at.x, at.y, 0.38)])
			ProcMesh.tube(b.st(WeaponMeshes.BARK), points, PackedVector2Array([Vector2.ONE * 0.16, Vector2.ONE * 0.15]), 11, Vector3.UP)
			# La testa clara y la médula se ven en la cara de los troncos.
			for end: float in [-1.0, 1.0]:
				for ring in 2:
					var z: float = end * (0.381 + 0.002 * ring)
					var radius := 0.138 if ring == 0 else 0.045
					var face := b.st(WeaponMeshes.WOOD if ring == 0 else WeaponMeshes.DARK_WOOD)
					for k in 11:
						var a := TAU * k / 11 * end
						var next := TAU * (k + 1) / 11 * end
						ProcMesh.tri(face, Vector3(at.x, at.y, z),
							Vector3(at.x + radius * cos(next), at.y + radius * sin(next), z),
							Vector3(at.x + radius * cos(a), at.y + radius * sin(a), z))
	return b.commit(WeaponMeshes.make_material)


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
