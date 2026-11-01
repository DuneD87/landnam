class_name ForgeVisual
extends Node3D

## Lo que se ve de la forja del broncista (la estación de armas y armaduras de la Edad del bronce):
## - un banco de madera largo, el de Wooden Stool 02 agrandado como el banco de trabajo;
## - encima, dos moldes de piedra, uno abierto con una espada recién colada, lingotes de bronce, un
##   crisol de barro con un poso de metal y el martillo de piedra;
## - al lado, un tocón con una piedra de yunque y unas tenazas de madera verde apoyadas.
## Las piezas de Poly Haven (CC0) son las del banco de trabajo; la espada, los lingotes y el martillo,
## las mallas horneadas de sus objetos (si no están, no salen); lo demás sale de ProcMesh. El origen
## es el suelo, en el centro del banco, y el lado de trabajo mira a +Z. Lo usan Workstation y la vista
## previa al plantarla (SurvivalActions). Ver docs/items.md.

const BENCH := preload("res://models/props/workbench/wooden_stool_02/wooden_stool_02_2k.gltf")
const STONE := preload("res://models/props/workbench/stone_01/stone_01_1k.gltf")
const SWORD := "res://data/items/meshes/weapons/bronze_sword.res"
const HAMMER := "res://data/items/meshes/weapons/stone_hammer_01.res"
const INGOT := "res://data/items/meshes/survival/bronze_ingot.res"
## El taburete de 26 cm a 1,43 m de largo, 0,76 de alto y 0,49 de fondo.
const BENCH_SCALE := Vector3(5.4, 4.2, 5.0)
const TOP := 0.76
## Lo que ocupa el banco, para la colisión (Workstation.collision_size).
const SIZE := Vector3(1.46, 0.76, 0.5)
## El tocón del yunque: dónde, su radio y su alto.
const STUMP := Vector3(1.0, 0.0, 0.08)
const STUMP_RADIUS := 0.2
const STUMP_HEIGHT := 0.48

## Los moldes, el crisol, el tocón y las tenazas: se hace una vez y la comparten todas.
static var _props: ArrayMesh


func _ready() -> void:
	var bench: Node3D = BENCH.instantiate()
	bench.scale = BENCH_SCALE
	add_child(bench)
	if _props == null:
		_props = _build_props()
	var props := MeshInstance3D.new()
	props.mesh = _props
	add_child(props)
	# El yunque, en el tocón.
	var anvil := _mesh(STONE)
	if anvil != null:
		_add(anvil, Basis(Vector3.UP, 0.4).scaled(Vector3(1.7, 1.2, 1.7)), STUMP + Vector3.UP * STUMP_HEIGHT)
	# Tumbados con su +Y (la punta) hacia +X, el filo en horizontal.
	var flat := Basis(Vector3.BACK, -PI * 0.5)
	_place(SWORD, flat, Vector3(-0.58, TOP + 0.056, 0.06))
	_place(HAMMER, Basis(Vector3.BACK, PI * 0.5), Vector3(0.66, TOP + 0.032, 0.18))
	for ingot in [[Vector3(0.36, TOP, -0.1), 0.1], [Vector3(0.36, TOP, -0.16), -0.05],
			[Vector3(0.37, TOP + 0.025, -0.13), 1.5], [Vector3(STUMP.x + 0.06, STUMP_HEIGHT + 0.0, STUMP.z - 0.12), 0.6]]:
		_place(INGOT, Basis(Vector3.UP, ingot[1]), ingot[0])


## Los moldes de piedra (uno abierto, con la huella de la hoja; el otro, la tapa), el crisol de
## barro con su poso de bronce, el tocón y las tenazas.
static func _build_props() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var stone := b.st(WeaponMeshes.STONE)
	WeaponMeshes.slab(stone, Vector3(-0.2, TOP + 0.025, 0.06), Vector3(0.92, 0.05, 0.17))
	WeaponMeshes.slab(stone, Vector3(-0.22, TOP + 0.02, -0.15), Vector3(0.9, 0.04, 0.15), Basis(Vector3.UP, 0.03))
	# El crisol: un cuenco de barro de paredes gruesas, tiznado, con el metal que se quedó en el fondo.
	var clay := b.st(FurnaceVisual.SOOT)
	ProcMesh.lathe(clay, [Vector2(0.0, TOP), Vector2(0.05, TOP + 0.002), Vector2(0.07, TOP + 0.03),
		Vector2(0.072, TOP + 0.08), Vector2(0.06, TOP + 0.085), Vector2(0.055, TOP + 0.04),
		Vector2(0.0, TOP + 0.035)], 14, Vector3(0.52, 0.0, 0.1))
	ProcMesh.lathe(b.st(WeaponMeshes.BRONZE), [Vector2(0.0, TOP + 0.042), Vector2(0.054, TOP + 0.042)], 14,
		Vector3(0.52, 0.0, 0.1))
	# El tocón: corteza alrededor y la madera del corte arriba.
	var bark := b.st(WeaponMeshes.BARK)
	ProcMesh.lathe(bark, [Vector2(STUMP_RADIUS * 1.2, -0.04), Vector2(STUMP_RADIUS * 1.08, 0.06),
		Vector2(STUMP_RADIUS, 0.2), Vector2(STUMP_RADIUS * 0.98, STUMP_HEIGHT - 0.01)], 12, STUMP, 2.0, 1.0)
	ProcMesh.lathe(b.st(WeaponMeshes.WOOD), [Vector2(STUMP_RADIUS * 0.98, STUMP_HEIGHT - 0.01),
		Vector2(STUMP_RADIUS * 0.9, STUMP_HEIGHT), Vector2(0.0, STUMP_HEIGHT + 0.004)], 12, STUMP)
	# Las tenazas: dos varas de madera verde atadas por la mitad, apoyadas en el tocón.
	var wood := b.st(WeaponMeshes.WOOD)
	var foot := STUMP + Vector3(0.05, 0.0, STUMP_RADIUS + 0.28)
	var lean := STUMP + Vector3(0.02, STUMP_HEIGHT - 0.04, STUMP_RADIUS + 0.02)
	for side in [-1.0, 1.0]:
		var spread := Vector3(side * 0.025, 0.0, 0.0)
		ProcMesh.tube(wood, PackedVector3Array([foot + spread * 1.6, (foot + lean) * 0.5, lean + spread * 2.2 + Vector3.UP * 0.06]),
			PackedVector2Array([Vector2(0.011, 0.011), Vector2(0.012, 0.012), Vector2(0.009, 0.009)]), 6)
	return b.commit(FurnaceVisual.make_material)


## Pone la malla horneada de [path] con su origen en [at], si está.
func _place(path: String, basis: Basis, at: Vector3) -> void:
	if not ResourceLoader.exists(path):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = load(path)
	mi.transform = Transform3D(basis, at)
	add_child(mi)


## La primera malla de [scene].
func _mesh(scene: PackedScene) -> Mesh:
	var source: Node = scene.instantiate()
	var found: Mesh = null
	for child in source.find_children("*", "MeshInstance3D", true, false):
		found = (child as MeshInstance3D).mesh
		break
	source.free()
	return found


## [mesh] con el centro de su base en [at].
func _add(mesh: Mesh, basis: Basis, at: Vector3) -> void:
	var box := mesh.get_aabb()
	var base := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(basis, at - basis * base)
	add_child(mi)
