extends SceneTree

## Hornea las armas de combate: mallas (data/items/meshes/weapons/), escenas de arma
## (scenes/items/weapons/combat/) e iconos de inventario (textures/icons/items/weapons/). También los
## objetos de supervivencia (SurvivalMeshes: carne, piel, lo que dan los animales, odre, hoguera,
## banco de trabajo), en sus carpetas survival/.
## Los iconos se renderizan, así que NO va con --headless:
##   godot --path . --script res://tools/combat/bake_weapons.gd [-- --only=greatsword,war_hammer]
## Después, `godot --headless --path . --import` para importar los PNG nuevos.
## Con `--meshes-only` solo guarda mallas y escenas, sin iconos, y entonces sí va con --headless.

const MESH_DIR := "res://data/items/meshes/weapons/"
const SCENE_DIR := "res://scenes/items/weapons/combat/"
const ICON_DIR := "res://textures/icons/items/weapons/"
const ICON_SIZE := 256
const TOOL_ICONS := ["stone_axe_01", "stone_pickaxe_01", "stone_hammer_01", "stone_hoe_01",
	"bronze_axe", "bronze_pickaxe", "bronze_hoe"]
## Inclinación hacia la cámara del icono (grados): las azadas, para que se vea la cara de la hoja.
const TOOL_ICON_PITCH := {"stone_hoe_01": -40.0, "bronze_hoe": -40.0}
const ItemIconRenderer = preload("res://tools/ui/item_icon_renderer.gd")

## nombre: [constructor, script de la escena o "", rotación del icono en grados (sobre Z de cámara)]
static var WEAPONS := {
	"iron_sword": [WeaponMeshes.sword, "", -45.0],
	"battle_axe": [WeaponMeshes.battle_axe, "", -40.0],
	"iron_mace": [WeaponMeshes.mace, "", -40.0],
	"spear": [WeaponMeshes.spear, "", -45.0],
	"greatsword": [WeaponMeshes.greatsword, "", -45.0],
	"great_axe": [WeaponMeshes.great_axe, "", -40.0],
	"war_hammer": [WeaponMeshes.war_hammer, "", -40.0],
	"hunting_bow": [WeaponMeshes.bow_flexing, "res://scripts/combat/ranged_weapon_visual.gd", -35.0],
	"slingshot": [WeaponMeshes.slingshot, "res://scripts/combat/ranged_weapon_visual.gd", -25.0],
	"arrow": [WeaponMeshes.arrow, "", -45.0],
	"branch": [WeaponMeshes.branch, "", -45.0],
	"wooden_shield": [WeaponMeshes.plank_shield, "", 0.0],
	"iron_shield": [WeaponMeshes.round_shield, "", 0.0],
	"heater_shield": [WeaponMeshes.heater_shield, "", -8.0],
	"seax": [SurvivalMeshes.seax, "", -45.0],
	"flint_sword": [WeaponMeshes.flint_sword, "", -45.0],
	"flint_spear": [WeaponMeshes.flint_spear, "", -45.0],
	"flint_knife": [WeaponMeshes.flint_knife, "", -45.0],
	"bone_dagger": [WeaponMeshes.bone_dagger, "", -45.0],
	"obsidian_sword": [WeaponMeshes.flint_sword.bind(WeaponMeshes.OBSIDIAN), "", -45.0],
	"stone_club": [WeaponMeshes.stone_club, "", -40.0],
	"stone_maul": [WeaponMeshes.stone_maul, "", -40.0],
	"stone_axe_01": [WeaponMeshes.stone_axe, "", -35.0],
	"stone_pickaxe_01": [WeaponMeshes.stone_pickaxe, "", -35.0],
	"stone_hammer_01": [WeaponMeshes.stone_hammer, "", -35.0],
	"stone_hoe_01": [WeaponMeshes.stone_hoe, "", -35.0],
	"bronze_axe": [WeaponMeshes.bronze_axe, "", -35.0],
	"bronze_pickaxe": [WeaponMeshes.bronze_pickaxe, "", -35.0],
	"bronze_hoe": [WeaponMeshes.bronze_hoe, "", -35.0],
	"crescent_labrys": [WeaponMeshes.crescent_labrys, "", -35.0],
	"dawn_greatsword": [WeaponMeshes.dawn_greatsword, "", -40.0],
	"bronze_sword": [WeaponMeshes.bronze_sword, "", -45.0],
	"hide_shield": [WeaponMeshes.hide_shield, "", 0.0],
	"bone_shield": [WeaponMeshes.bone_shield, "", -8.0],
}
## Objetos de supervivencia: [constructor, giro del icono sobre Z de cámara, giro sobre Y, inclinación
## hacia la cámara (sobre X), si lleva escena para verse en el suelo]. Grados.
static var SURVIVAL := {
	"raw_meat": [SurvivalMeshes.meat.bind(false), -35.0, 90.0, 0.0, true],
	"cooked_meat": [SurvivalMeshes.meat.bind(true), -35.0, 90.0, 0.0, true],
	"raw_hide": [SurvivalMeshes.hide, 0.0, 0.0, 0.0, true],
	"bone": [SurvivalMeshes.bone, -45.0, 0.0, 0.0, true],
	"sinew": [SurvivalMeshes.sinew, -45.0, 0.0, 0.0, true],
	"antler": [SurvivalMeshes.antler, -20.0, 90.0, 0.0, true],
	"boar_tusk": [SurvivalMeshes.boar_tusk, 0.0, 90.0, 0.0, true],
	"ivory": [SurvivalMeshes.ivory, -30.0, 90.0, 0.0, true],
	"horn": [SurvivalMeshes.horn, 0.0, 90.0, 0.0, true],
	"plant_fiber": [SurvivalMeshes.plant_fiber, -45.0, 0.0, 0.0, true],
	"feather": [SurvivalMeshes.feather, -40.0, 0.0, 0.0, true],
	"waterskin": [SurvivalMeshes.waterskin, -10.0, 0.0, 0.0, true],
	"yarrow": [SurvivalMeshes.yarrow, -20.0, 0.0, 12.0, true],
	"yarrow_poultice": [SurvivalMeshes.poultice, -15.0, 0.0, 65.0, true],
	"yarrow_draught": [SurvivalMeshes.draught, -25.0, 90.0, 0.0, true],
	"splint": [SurvivalMeshes.splint, -45.0, 0.0, 0.0, true],
	"flint": [SurvivalMeshes.ore_chunk.bind(&"flint"), 0.0, 30.0, 25.0, true],
	"obsidian": [SurvivalMeshes.ore_chunk.bind(&"obsidian"), 0.0, 20.0, 20.0, true],
	"copper_ore": [SurvivalMeshes.ore_chunk.bind(&"copper_ore"), 0.0, 20.0, 30.0, true],
	"tin_ore": [SurvivalMeshes.ore_chunk.bind(&"tin_ore"), 0.0, 20.0, 25.0, true],
	"bog_iron": [SurvivalMeshes.ore_chunk.bind(&"bog_iron"), 0.0, 20.0, 25.0, true],
	"iron_ore": [SurvivalMeshes.ore_chunk.bind(&"iron_ore"), 0.0, 20.0, 25.0, true],
	"coal": [SurvivalMeshes.ore_chunk.bind(&"coal"), 0.0, 20.0, 25.0, true],
	"silver_ore": [SurvivalMeshes.ore_chunk.bind(&"silver_ore"), 0.0, 20.0, 30.0, true],
	"gold": [SurvivalMeshes.ore_chunk.bind(&"gold"), 0.0, 20.0, 25.0, true],
	"sulfur": [SurvivalMeshes.ore_chunk.bind(&"sulfur"), 0.0, 20.0, 30.0, true],
	"campfire": [SurvivalMeshes.campfire, 0.0, 0.0, 32.0, false],
	"stone_workbench": [SurvivalMeshes.workbench, 0.0, -28.0, 22.0, false],
	"bronze_ingot": [SurvivalMeshes.bronze_ingot, 0.0, 30.0, 30.0, true],
	"smelting_furnace": [SurvivalMeshes.smelting_furnace, 0.0, -35.0, 15.0, false],
	"bronze_forge": [SurvivalMeshes.bronze_forge, 0.0, -28.0, 22.0, false],
}
const SURVIVAL_MESH_DIR := "res://data/items/meshes/survival/"
const SURVIVAL_SCENE_DIR := "res://scenes/items/survival/"
const SURVIVAL_ICON_DIR := "res://textures/icons/items/survival/"
## Los que se ven de frente en el icono (no de canto): el tirachinas y los escudos.
const FACE_ON := ["slingshot", "wooden_shield", "iron_shield", "heater_shield", "hide_shield", "bone_shield"]

## Ramas tiradas por el suelo (objetos del planeta, planet_earth.json): malla tumbada y escena.
const LITTER_DIR := "res://data/items/meshes/litter/"
const LITTER_SCENE_DIR := "res://scenes/planet/planet_items/litter/"
const LITTER_BRANCHES := 3

func _initialize() -> void:
	if "--background" in OS.get_cmdline_user_args():
		root.unfocusable = true
		root.position = Vector2i(-4000, -4000)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(ICON_SIZE, ICON_SIZE)
	root.transparent_bg = true
	for dir in [MESH_DIR, SCENE_DIR, ICON_DIR, LITTER_DIR, LITTER_SCENE_DIR, SURVIVAL_MESH_DIR,
			SURVIVAL_SCENE_DIR, SURVIVAL_ICON_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)
	var only: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7).split(",")
	var meshes_only := "--meshes-only" in OS.get_cmdline_user_args()
	for weapon_name in WEAPONS:
		if not only.is_empty() and weapon_name not in only:
			continue
		var entry: Array = WEAPONS[weapon_name]
		var mesh: ArrayMesh = (entry[0] as Callable).call()
		var mesh_path: String = MESH_DIR + weapon_name + ".res"
		_check(ResourceSaver.save(mesh, mesh_path), mesh_path)
		mesh = load(mesh_path)
		if weapon_name != "arrow":
			_save_scene(weapon_name, mesh, entry[1])
		if meshes_only:
			continue
		await render_weapon(self, weapon_name, mesh)
	for item_name in SURVIVAL:
		if not only.is_empty() and item_name not in only and "survival" not in only:
			continue
		var entry: Array = SURVIVAL[item_name]
		var mesh: ArrayMesh = (entry[0] as Callable).call()
		var mesh_path: String = SURVIVAL_MESH_DIR + item_name + ".res"
		_check(ResourceSaver.save(mesh, mesh_path), mesh_path)
		mesh = load(mesh_path)
		if entry[4]:
			_save_scene(item_name, mesh, "", SURVIVAL_SCENE_DIR)
		if meshes_only:
			continue
		await render_survival(self, item_name, mesh)
	if only.is_empty() or "litter" in only:
		for variant in LITTER_BRANCHES:
			var path := LITTER_DIR + "fallen_branch_%d.res" % variant
			_check(ResourceSaver.save(WeaponMeshes.lying_branch(variant + 1), path), path)
			_save_litter_scene("fallen_branch_%d" % variant, load(path))
	if not only.is_empty():
		print("BAKE WEAPONS DONE")
		quit()
		return
	# La piedra del tirachinas: solo malla (el proyectil la carga).
	var pebble := WeaponMeshes.pebble()
	_check(ResourceSaver.save(pebble, MESH_DIR + "pebble.res"), "pebble")
	# La aljaba: solo malla (la lleva el jugador a la espalda con el arco).
	_check(ResourceSaver.save(WeaponMeshes.quiver(), MESH_DIR + "quiver.res"), "quiver")
	print("BAKE WEAPONS DONE")
	quit()


func _check(err: int, what: String) -> void:
	if err != OK:
		push_error("No se pudo guardar %s (%d)" % [what, err])
	else:
		print("saved ", what)


func _save_scene(weapon_name: String, mesh: ArrayMesh, script_path: String, dir: String = SCENE_DIR) -> void:
	var root_node := Node3D.new()
	root_node.name = weapon_name.to_pascal_case()
	if weapon_name in TOOL_ICONS:
		root_node.set_meta(&"grip_aligned", true)
	if script_path != "":
		root_node.set_script(load(script_path))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	root_node.add_child(mi)
	mi.owner = root_node
	var packed := PackedScene.new()
	packed.pack(root_node)
	var path := dir + weapon_name + ".tscn"
	_check(ResourceSaver.save(packed, path), path)
	root_node.free()


## Escena de objeto del planeta: raíz y la malla como primer hijo (Planet la lee de ahí).
func _save_litter_scene(scene_name: String, mesh: ArrayMesh) -> void:
	var root_node := Node3D.new()
	root_node.name = scene_name.to_pascal_case()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	root_node.add_child(mi)
	mi.owner = root_node
	var packed := PackedScene.new()
	packed.pack(root_node)
	var path := LITTER_SCENE_DIR + scene_name + ".tscn"
	_check(ResourceSaver.save(packed, path), path)
	root_node.free()

static func render_weapon(tree: SceneTree, id: String, mesh: Mesh) -> void:
	var model := MeshInstance3D.new()
	model.mesh = mesh
	ItemIconRenderer.prepare_model(model, id)
	var folder := "tools" if id in TOOL_ICONS else "weapons"
	var yaw := -12.0 if id in FACE_ON else 82.0
	await ItemIconRenderer.render(tree, model, [WEAPONS[id][2], yaw],
		"res://textures/icons/items/%s/%s.png" % [folder, id], id == "hunting_bow", TOOL_ICON_PITCH.get(id, 0.0))


static func render_survival(tree: SceneTree, id: String, mesh: Mesh) -> void:
	var model := MeshInstance3D.new()
	model.mesh = mesh
	var view: Array = SURVIVAL[id]
	await ItemIconRenderer.render(tree, model, [view[1], view[2]], SURVIVAL_ICON_DIR + id + ".png", false, view[3])
