extends SceneTree

## Hornea las armas de combate: mallas (data/items/meshes/weapons/), escenas de arma
## (scenes/items/weapons/combat/) e iconos de inventario (textures/icons/items/weapons/).
## Los iconos se renderizan, así que NO va con --headless:
##   godot --path . --script res://tools/combat/bake_weapons.gd [-- --only=greatsword,war_hammer]
## Después, `godot --headless --path . --import` para importar los PNG nuevos.

const MESH_DIR := "res://data/items/meshes/weapons/"
const SCENE_DIR := "res://scenes/items/weapons/combat/"
const ICON_DIR := "res://textures/icons/items/weapons/"
const ICON_SIZE := 256

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
}

## Ramas tiradas por el suelo (objetos del planeta, planet_earth.json): malla tumbada y escena.
const LITTER_DIR := "res://data/items/meshes/litter/"
const LITTER_SCENE_DIR := "res://scenes/planet/planet_items/litter/"
const LITTER_BRANCHES := 3

## Colores de icono por material (paleta de los iconos dibujados existentes). Alfa < 1 = brillo.
const ICON_COLORS := {
	&"wood": Color(0.73, 0.46, 0.37, 1.0),
	&"dark_wood": Color(0.55, 0.33, 0.25, 1.0),
	&"steel": Color(0.66, 0.72, 0.78, 0.9),
	&"iron": Color(0.47, 0.52, 0.58, 0.9),
	&"leather": Color(0.42, 0.26, 0.19, 1.0),
	&"flint": Color(0.46, 0.50, 0.55, 1.0),
	&"feather": Color(0.88, 0.32, 0.25, 1.0),
	&"cord": Color(0.99, 0.89, 0.76, 1.0),
	&"stone": Color(0.56, 0.63, 0.69, 1.0),
	&"bark": Color(0.55, 0.42, 0.33, 1.0),
}


func _initialize() -> void:
	if "--background" in OS.get_cmdline_user_args():
		root.unfocusable = true
		root.position = Vector2i(-4000, -4000)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(ICON_SIZE, ICON_SIZE)
	root.transparent_bg = true
	for dir in [MESH_DIR, SCENE_DIR, ICON_DIR, LITTER_DIR, LITTER_SCENE_DIR]:
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
		await _render_icon(weapon_name, mesh, entry[2])
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


func _save_scene(weapon_name: String, mesh: ArrayMesh, script_path: String) -> void:
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
	var path := SCENE_DIR + weapon_name + ".tscn"
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


func _render_icon(weapon_name: String, mesh: ArrayMesh, roll_deg: float) -> void:
	# En un SubViewport de tamaño fijo y fondo transparente: la ventana raíz puede acabar al
	# tamaño de la pantalla (y opaca) según el escritorio.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(ICON_SIZE, ICON_SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var shader: Shader = load("res://shaders/icon_toon.gdshader")
	var holder := Node3D.new()
	stage.add_child(holder)
	var color_mi := MeshInstance3D.new()
	color_mi.mesh = mesh
	for s in mesh.get_surface_count():
		var kind := StringName(mesh.surface_get_material(s).resource_name)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("base_color", ICON_COLORS.get(kind, Color(0.6, 0.6, 0.6)))
		color_mi.set_surface_override_material(s, mat)
	holder.add_child(color_mi)
	if weapon_name == "hunting_bow":
		# La cuerda es dinámica en el juego; en el icono se dibuja recta.
		var string_mi := MeshInstance3D.new()
		var cord := CylinderMesh.new()
		cord.top_radius = 0.006
		cord.bottom_radius = 0.006
		var a := WeaponMeshes.bow_tip(true)
		var b := WeaponMeshes.bow_tip(false)
		cord.height = a.distance_to(b)
		var cord_mat := ShaderMaterial.new()
		cord_mat.shader = shader
		cord_mat.set_shader_parameter("base_color", ICON_COLORS[&"cord"])
		cord.material = cord_mat
		string_mi.mesh = cord
		string_mi.position = (a + b) * 0.5
		holder.add_child(string_mi)
	# El arma de lado (plano de la hoja hacia la cámara) y girada en diagonal.
	# De plano: la anchura de la hoja (Z) pasa a la horizontal de la cámara. El tirachinas ya
	# tiene las horquillas en X.
	var yaw := 0.0 if weapon_name == "slingshot" else 90.0
	holder.basis = Basis(Vector3.BACK, deg_to_rad(roll_deg)) * Basis(Vector3.UP, deg_to_rad(yaw))
	# Encuadre: AABB en espacio de cámara.
	var aabb: AABB = Transform3D(holder.basis, Vector3.ZERO) * mesh.get_aabb()
	var extent := maxf(aabb.size.x, aabb.size.y)
	var outline := extent * 0.030
	# Contorno: copias negras desplazadas en círculo detrás de la de color.
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0.07, 0.06, 0.06)
	for k in 16:
		var a := TAU * k / 16.0
		var copy := MeshInstance3D.new()
		copy.mesh = mesh
		copy.material_override = black
		copy.position = Vector3(cos(a), sin(a), 0) * outline + Vector3(0, 0, -extent)
		holder.add_child(copy)
		copy.global_transform = Transform3D(holder.basis, holder.basis * Vector3.ZERO + Vector3(cos(a), sin(a), 0) * outline + Vector3(0, 0, -extent * 2.0))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = extent * 1.2 + outline * 2.0
	cam.position = Vector3(aabb.get_center().x, aabb.get_center().y, 10.0)
	cam.near = 0.1
	cam.far = 40.0
	stage.add_child(cam)
	cam.current = true
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var path := ICON_DIR + weapon_name + ".png"
	_check(image.save_png(path), path)
	viewport.queue_free()
	await process_frame
