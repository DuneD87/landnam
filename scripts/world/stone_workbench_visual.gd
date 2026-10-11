class_name StoneWorkbenchVisual
extends Node3D

## Lo que se ve del banco de trabajo de la Edad de piedra: un banco de madera tosca y, encima, lo de
## tallar: una piedra de yunque con una lasca, un percutor, más lascas, un cuenco tallado y un palo
## para un mango; al pie, unas piedras. Piezas de Poly Haven (CC0): Wooden Stool 02 (el banco,
## agrandado), Stone 01, Namaqualand Stones 01, Wooden Bowl 02 y una rama de Dry Branches Medium 01.
## El origen es el suelo, en el centro, y el lado de trabajo mira a +Z. Lo usan Workstation y la
## vista previa al plantarlo (SurvivalActions). Ver docs/items.md.

const BENCH := preload("res://models/props/workbench/wooden_stool_02/wooden_stool_02_2k.gltf")
## Piedra clara de canto: el yunque y una al pie.
const STONE := preload("res://models/props/workbench/stone_01/stone_01_1k.gltf")
## Cinco piedras sueltas: el percutor y las lascas.
const PEBBLES := preload("res://models/props/workbench/namaqualand_stones_01/namaqualand_stones_01_1k.gltf")
const BOWL := preload("res://models/props/workbench/wooden_bowl_02/wooden_bowl_02_1k.gltf")
const BRANCHES := preload("res://models/props/campfire/dry_branches_medium_01/dry_branches_medium_01_1k.gltf")
## El banco es un taburete de 26 cm: a tamaño de banco de trabajo, 1,22 m de largo, 0,76 de alto y
## 0,47 de fondo.
const BENCH_SCALE := Vector3(4.6, 4.2, 4.8)
## Altura del tablero (m, ya escalado).
const TOP := 0.76
## Lo que ocupa, para la colisión (Workstation.collision_size).
const SIZE := Vector3(1.24, 0.76, 0.5)

## Lo que va encima y al pie: [modelo, malla (lo que acaba su nombre; "" = la única), dónde va el
## centro de su base, giro sobre la vertical (grados), escala].
var PIECES := [
	[STONE, "", Vector3(-0.27, TOP - 0.01, 0.0), 10.0, 1.8],
	[PEBBLES, "_d", Vector3(-0.29, TOP + 0.105, 0.0), 20.0, 0.55],
	[PEBBLES, "_e", Vector3(0.0, TOP - 0.004, 0.12), 35.0, 0.85],
	[PEBBLES, "_a", Vector3(-0.1, TOP - 0.002, -0.14), -40.0, 0.7],
	[PEBBLES, "_c", Vector3(0.12, TOP - 0.003, -0.12), 70.0, 0.6],
	[BOWL, "", Vector3(0.41, TOP - 0.002, -0.03), 0.0, 1.25],
	[PEBBLES, "_b", Vector3(-0.76, -0.02, 0.16), 15.0, 1.0],
	[STONE, "", Vector3(-0.55, -0.02, 0.4), 120.0, 1.3],
]
## Palos: [rama (lo que acaba su nombre), un extremo, el otro, grosor]. Uno encima, para un mango.
var STICKS := [
	["_c", Vector3(0.06, TOP + 0.016, 0.15), Vector3(0.52, TOP + 0.016, 0.19), 0.8],
]


func _ready() -> void:
	var bench: Node3D = BENCH.instantiate()
	bench.scale = BENCH_SCALE
	add_child(bench)
	for piece in PIECES:
		var mesh := _mesh(piece[0], piece[1])
		if mesh != null:
			var basis := Basis(Vector3.UP, deg_to_rad(piece[3])).scaled(Vector3.ONE * float(piece[4]))
			_add(mesh, basis, piece[2])
	for stick in STICKS:
		var mesh := _mesh(BRANCHES, stick[0])
		if mesh != null:
			_add_stick(mesh, stick[1], stick[2], stick[3])


## La malla de [scene] cuyo nombre acaba en [suffix] (o la primera).
func _mesh(scene: PackedScene, suffix: String) -> Mesh:
	var source: Node = scene.instantiate()
	var found: Mesh = null
	for child in source.find_children("*", "MeshInstance3D", true, false):
		if suffix == "" or String(child.name).ends_with(suffix):
			found = (child as MeshInstance3D).mesh
			break
	source.free()
	return found


## [mesh] con el centro de su base en [at] (las piezas de un mismo modelo no están en su origen).
func _add(mesh: Mesh, basis: Basis, at: Vector3) -> void:
	var box := mesh.get_aabb()
	var base := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(basis, at - basis * base)
	add_child(mi)


## Una rama (larga en su Z) de [from] a [to], estirada a esa medida y con [thickness] de grosor.
func _add_stick(mesh: Mesh, from: Vector3, to: Vector3, thickness: float) -> void:
	var box := mesh.get_aabb()
	var along := (to - from).normalized()
	var side := Vector3.UP.cross(along)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	var basis := Basis(side, along.cross(side).normalized(), along)
	basis = basis.scaled_local(Vector3(thickness, thickness, from.distance_to(to) / maxf(box.size.z, 0.01)))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(basis, (from + to) * 0.5 - basis * box.get_center())
	add_child(mi)
