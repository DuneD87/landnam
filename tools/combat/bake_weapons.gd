extends SceneTree

## Hornea las armas de combate: mallas (data/items/meshes/weapons/), escenas de arma
## (scenes/items/weapons/combat/) e iconos de inventario (textures/icons/items/weapons/). También los
## objetos de supervivencia (SurvivalMeshes: carne, piel, odre, hoguera, banco de trabajo), en sus
## carpetas survival/.
## Los iconos se renderizan, así que NO va con --headless:
##   godot --path . --script res://tools/combat/bake_weapons.gd [-- --only=greatsword,war_hammer]
## Después, `godot --headless --path . --import` para importar los PNG nuevos.

const MESH_DIR := "res://data/items/meshes/weapons/"
const SCENE_DIR := "res://scenes/items/weapons/combat/"
const ICON_DIR := "res://textures/icons/items/weapons/"
const IconRenderer = preload("res://tools/ui/item_icon_renderer.gd")
const ICON_SIZE := IconRenderer.SIZE

## nombre: [constructor, script de la escena o "", rotación del icono en grados (sobre Z de cámara)]
var WEAPONS := {
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
}
## Objetos de supervivencia: [constructor, giro del icono sobre Z de cámara, giro sobre Y, inclinación
## hacia la cámara (sobre X), si lleva escena para verse en el suelo]. Grados.
var SURVIVAL := {
	"raw_meat": [SurvivalMeshes.meat.bind(false), -35.0, 90.0, 0.0, true],
	"cooked_meat": [SurvivalMeshes.meat.bind(true), -35.0, 90.0, 0.0, true],
	"raw_hide": [SurvivalMeshes.hide, 0.0, 0.0, 0.0, true],
	"waterskin": [SurvivalMeshes.waterskin, -10.0, 0.0, 0.0, true],
	"campfire": [SurvivalMeshes.campfire, 0.0, 0.0, 32.0, false],
	"stone_workbench": [SurvivalMeshes.workbench, 0.0, -28.0, 22.0, false],
}
const SURVIVAL_MESH_DIR := "res://data/items/meshes/survival/"
const SURVIVAL_SCENE_DIR := "res://scenes/items/survival/"
const SURVIVAL_ICON_DIR := "res://textures/icons/items/survival/"
## Los que se ven de frente en el icono (no de canto): el tirachinas y los escudos.
const FACE_ON := ["slingshot", "wooden_shield", "iron_shield", "heater_shield"]

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
		var yaw := 0.0 if weapon_name in FACE_ON else 90.0
		await _render_icon(weapon_name, mesh, entry[2], yaw, 0.0, ICON_DIR)
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
		await _render_icon(item_name, mesh, entry[1], entry[2], entry[3], SURVIVAL_ICON_DIR)
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


func _render_icon(weapon_name: String, mesh: ArrayMesh, roll_deg: float, yaw_deg: float, pitch_deg: float,
		dir: String) -> void:
	var model := MeshInstance3D.new()
	model.mesh = mesh
	IconRenderer.prepare_model(model, weapon_name)
	await IconRenderer.render(self, model, [roll_deg, yaw_deg], dir + weapon_name + ".png",
		weapon_name == "hunting_bow", pitch_deg)
