class_name DoorMesh
extends RefCounted

## La malla de una puerta o una trampilla de madera (WoodenDoor), de celdas de 1 m: tablas de arriba
## abajo, con travesaños y riostras por detrás, tiras de cuero crudo de bisagra y un asidero en cada
## cara. Origen en el centro del canto de abajo de la hoja, en medio de su grueso, +Y a lo largo de
## ella, +Z hacia delante (los travesaños van detrás) y las bisagras en el canto de +X o de -X. La comparten la hoja puesta,
## el fantasma del martillo y los iconos (tools/items/bake_doors.gd).

## Grueso de las tablas y de los travesaños (en celdas).
const THICKNESS := 0.05
const LEDGE := 0.03
## Holgura con el hueco, a los lados y arriba, y abajo en una puerta (en celdas).
const GAP := 0.006
const FLOOR_GAP := 0.012
## Tablas a lo ancho de una celda.
const PLANKS := 5
## La foto de las tablas: la del casco de los barcos, con 12 tablas por fila y que mide esto a lo
## largo de la veta (en celdas).
const PHOTO_ROWS := 12
const PHOTO_LENGTH := 2.4
const PLANK := &"door_planks"

static var _meshes := {}
static var _materials := {}


## La hoja de [cells] celdas de 1 m con las bisagras en el canto de +X ([side] = 1) o de -X.
static func make(cells: Vector2i, side: int = 1) -> ArrayMesh:
	var key := Vector3i(cells.x, cells.y, side)
	if _meshes.has(key):
		return _meshes[key]
	var builder := ProcMesh.Builder.new()
	var planks := builder.st(PLANK)
	var strap := builder.st(WeaponMeshes.RAWHIDE)
	var wood := builder.st(WeaponMeshes.WOOD)
	ProcMesh.set_flat(planks, true)
	ProcMesh.set_flat(strap, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7411 + cells.y * 31 + cells.x
	var width := cells.x - GAP * 2.0
	var bottom := FLOOR_GAP if cells.y > 1 else GAP
	var length := cells.y - GAP - bottom
	var count := PLANKS * cells.x
	var plank := width / count
	# Las tablas, a lo largo, cada una con su fila de la foto.
	for i in count:
		_board(planks, Vector3(-width * 0.5 + plank * (i + 0.5), bottom + length * 0.5, 0.0),
			Vector3(length, plank - 0.003, THICKNESS), Basis(Vector3.UP, Vector3.LEFT, Vector3.BACK),
			rng.randi_range(0, PHOTO_ROWS - 1), rng.randf())
	# Los travesaños, detrás, uno cada metro y pico, y entre cada dos una riostra que sube desde las
	# bisagras.
	var ledges := maxi(2, roundi(length / 1.3) + 1)
	var heights := PackedFloat32Array()
	for k in ledges:
		heights.append(bottom + 0.2 + (length - 0.4) * k / (ledges - 1))
	var back := -THICKNESS * 0.5
	for y in heights:
		_board(planks, Vector3(0.0, y, back - LEDGE * 0.5), Vector3(width - 0.1, 0.13, LEDGE), Basis.IDENTITY,
			rng.randi_range(0, PHOTO_ROWS - 1), rng.randf())
	var reach := width * 0.5 - 0.12
	for k in ledges - 1:
		var from := Vector3(side * reach, heights[k], 0.0)
		var to := Vector3(-side * reach, heights[k + 1], 0.0)
		var grain := (to - from).normalized()
		_board(planks, (from + to) * 0.5 + Vector3(0.0, 0.0, back - 0.012),
			Vector3(from.distance_to(to), 0.1, 0.024), Basis(grain, Vector3.BACK.cross(grain), Vector3.BACK),
			rng.randi_range(0, PHOTO_ROWS - 1), rng.randf())
	# Las bisagras: una tira de cuero crudo en cada travesaño, por delante (más larga cuanto más ancha
	# es la hoja), por el canto y atada a su punta por detrás.
	var edge := side * width * 0.5
	var strap_length := 0.18 + 0.08 * cells.x
	for y in heights:
		ProcMesh.box(strap, Vector3(edge - side * strap_length * 0.5, y, THICKNESS * 0.5 + 0.003),
			Vector3(strap_length, 0.07, 0.006))
		ProcMesh.box(strap, Vector3(edge + side * 0.003, y, -LEDGE * 0.5),
			Vector3(0.006, 0.07, THICKNESS + LEDGE + 0.012))
		ProcMesh.box(strap, Vector3(edge - side * 0.06, y, back - LEDGE * 0.5), Vector3(0.12, 0.085, LEDGE + 0.008))
	# Un asidero en cada cara, junto al canto de abrir: a la altura de la mano en una puerta, en
	# medio en una trampilla.
	var grip := Vector2(-side * (width * 0.5 - 0.12), minf(1.0, bottom + length * 0.5))
	for out in [1.0, -1.0]:
		var z0: float = out * THICKNESS * 0.5
		ProcMesh.tube(wood, PackedVector3Array([Vector3(grip.x, grip.y - 0.1, z0 - out * 0.01),
			Vector3(grip.x, grip.y - 0.08, z0 + out * 0.045), Vector3(grip.x, grip.y + 0.08, z0 + out * 0.045),
			Vector3(grip.x, grip.y + 0.1, z0 - out * 0.01)]),
			PackedVector2Array([Vector2.ONE * 0.012, Vector2.ONE * 0.015, Vector2.ONE * 0.015, Vector2.ONE * 0.012]), 7)
	var mesh := builder.commit(_material)
	_meshes[key] = mesh
	return mesh


## Una tabla de [size] (largo a lo largo de la veta, ancho, grueso) en [center], con la veta en
## frame.x y el grueso en frame.z. Lleva la fila [row] de la foto, corrida [shift] a lo largo.
static func _board(st: SurfaceTool, center: Vector3, size: Vector3, frame: Basis, row: int, shift: float) -> void:
	var h := size * 0.5
	# Cada cara: su normal y dos ejes con r × u = normal, en el marco de la tabla.
	for face in [[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
			[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
			[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.BACK, Vector3.UP]]:
		var n: Vector3 = face[0]
		var r: Vector3 = face[1]
		var u: Vector3 = face[2]
		var base := ProcMesh.vertex_count(st)
		for corner in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1)]:
			var p: Vector3 = (n + r * corner.x + u * corner.y) * h
			# En las caras grandes la fila de la foto va a lo ancho; en los cantos, una tira de ella, y
			# en las testas, la fila de lado.
			var along := p.z if n.x != 0.0 else p.x
			var across := (p.z / h.z + 1.0) * 0.15 if n.y != 0.0 else (p.y / h.y + 1.0) * 0.5
			ProcMesh.emit(st, Vector2(along / PHOTO_LENGTH + shift, (row + across) / PHOTO_ROWS),
				center + frame * p)
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_index(base + i)


static func _material(kind: StringName) -> Material:
	if not _materials.has(kind):
		if kind == PLANK:
			var mat := ORMMaterial3D.new()
			mat.resource_name = String(PLANK)
			mat.albedo_texture = preload("res://textures/build_materials/ship_planks/ship_planks_albedo.png")
			# Curtida, más apagada que la foto, como el casco de los barcos.
			mat.albedo_color = Color(0.82, 0.76, 0.70)
			mat.orm_texture = preload("res://textures/build_materials/ship_planks/ship_planks_orm.png")
			mat.normal_enabled = true
			mat.normal_texture = preload("res://textures/build_materials/ship_planks/ship_planks_normal.png")
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			_materials[kind] = mat
		else:
			_materials[kind] = WeaponMeshes.make_material(kind)
	return _materials[kind]
