class_name BoatOars
extends Node3D

## Remos a ambos costados mientras el barco va a remo. Solo decoran: el empuje lo da
## BoatSailing.rowing_acceleration. Las bancadas salen de las cajas de colisión del casco (espacio
## local del body, proa +Z), así que valen para cualquier barco construido: cada remo apoya en la
## borda del costado más ancho a esa altura de la eslora y baja hasta el agua.
const PAIR_SPACING := 1.6
const MAX_PAIRS := 4
## Ciclo de una palada (s). Ciar va algo más lento.
const STROKE_TIME := 1.7
const BACK_STROKE_TIME := 2.1
## Barrido alrededor del tolete (rad, + hacia proa) y alzado de la pala en el retorno.
const SWEEP_CENTER := 0.05
const SWEEP_AMPLITUDE := 0.4
const LIFT := 0.3
## Mango que queda dentro de la borda, y lo que la pala pasa del punto de entrada en el agua.
const INBOARD := 0.7
const BLADE := 0.85

var direction := 0
var _phase := 0.0
var _hull_version := -1
var _oars: Array[Dictionary] = []
static var _meshes := {}


func _ready() -> void:
	name = "Oars"
	visible = false
	set_process(false)


## [row]: -1 ciar, 0 remos dentro, 1 remar.
func update(row: int, box_pos: PackedVector3Array, box_half: PackedVector3Array, hull_version: int) -> void:
	if hull_version != _hull_version:
		_hull_version = hull_version
		_rebuild(stations(box_pos, box_half))
	if row == direction:
		return
	if direction == 0:
		_phase = 0.0
	direction = row
	visible = row != 0
	set_process(visible)
	_pose()


func _process(delta: float) -> void:
	_phase = fposmod(_phase + delta * direction / (STROKE_TIME if direction > 0 else BACK_STROKE_TIME), 1.0)
	_pose()


func _pose() -> void:
	for oar: Dictionary in _oars:
		(oar["node"] as Node3D).transform = Transform3D(oar_basis(oar["side"], oar["pitch"], _phase), oar["pivot"])


func _rebuild(list: Array[Dictionary]) -> void:
	for oar: Dictionary in _oars:
		(oar["node"] as Node).queue_free()
	_oars.clear()
	for station: Dictionary in list:
		var node := MeshInstance3D.new()
		node.mesh = oar_mesh(station["length"])
		add_child(node)
		station["node"] = node
		_oars.append(station)
	_pose()


## Una bancada por cada 3 m de eslora (de 1 a MAX_PAIRS pares), centradas. Cada remo: {pivot, side,
## length, pitch}, con el tolete en lo alto de la caja más exterior de su costado.
static func stations(box_pos: PackedVector3Array, box_half: PackedVector3Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if box_pos.is_empty():
		return result
	var z0 := INF
	var z1 := -INF
	for k in box_pos.size():
		z0 = minf(z0, box_pos[k].z - box_half[k].z)
		z1 = maxf(z1, box_pos[k].z + box_half[k].z)
	var length := z1 - z0
	var pairs := clampi(floori(length / 3.0), 1, MAX_PAIRS)
	var spacing := minf(PAIR_SPACING, length * 0.6 / pairs)
	for i in pairs:
		var z := (z0 + z1) * 0.5 + (i - (pairs - 1) * 0.5) * spacing
		for side: float in [-1.0, 1.0]:
			var outer := -INF
			var top := 0.0
			var bottom := INF
			for k in box_pos.size():
				var p := box_pos[k]
				var h := box_half[k]
				if absf(z - p.z) > h.z:
					continue
				bottom = minf(bottom, p.y - h.y)
				var edge := side * p.x + h.x
				if edge > outer + 0.01:
					outer = edge
					top = p.y + h.y
				elif edge > outer - 0.01:
					top = maxf(top, p.y + h.y)
			if outer == -INF:
				continue
			# La pala entra en el agua algo por encima de la quilla: un casco flota medio hundido.
			var drop := (top - bottom) * 0.6 + 0.3
			var oar_length := clampf(drop / 0.5 + BLADE * 0.7, 2.4, 6.0)
			result.append({"pivot": Vector3(side * (outer + 0.02), top + 0.05, z), "side": side,
				"length": oar_length, "pitch": asin(clampf(drop / (oar_length - BLADE * 0.5), 0.25, 0.9))})
	return result


## Palo a lo largo de Y local hacia fuera y abajo. Palada (fase 0 → 0.5): la pala, metida y de
## canto, barre de proa a popa; en el retorno sale del agua y se pone plana.
static func oar_basis(side: float, pitch: float, phase: float) -> Basis:
	var sweep := SWEEP_CENTER + SWEEP_AMPLITUDE * cos(TAU * phase)
	var raised := maxf(-sin(TAU * phase), 0.0)
	var angle := pitch - LIFT * raised
	var axis := Vector3(side * cos(angle) * cos(sweep), -sin(angle), cos(angle) * sin(sweep))
	var width := (Vector3.UP - axis * axis.y).normalized()
	width = width.rotated(axis, PI * 0.5 * clampf(raised * 3.0, 0.0, 1.0) * side)
	return Basis(width, axis, width.cross(axis))


static func oar_mesh(length: float) -> ArrayMesh:
	var key := roundi(length * 10.0)
	if _meshes.has(key):
		return _meshes[key]
	length = key / 10.0
	var b := ProcMesh.Builder.new()
	var wood := b.st(WeaponMeshes.WOOD)
	var neck := length - BLADE
	ProcMesh.lathe(wood, [Vector2(0.0, -INBOARD), Vector2(0.026, -INBOARD), Vector2(0.03, -INBOARD + 0.04),
		Vector2(0.03, -INBOARD + 0.3), Vector2(0.042, -INBOARD + 0.36), Vector2(0.045, 0.15),
		Vector2(0.034, neck), Vector2(0.0, neck + 0.02)], 8, Vector3.ZERO, 1.0, 1.0)
	ProcMesh.set_flat(wood, true)
	var rings := []
	for section: Vector3 in [Vector3(neck - 0.05, 0.05, 0.05), Vector3(neck + 0.25, 0.17, 0.035),
			Vector3(length - 0.04, 0.17, 0.025), Vector3(length, 0.13, 0.02)]:
		var ring := PackedVector3Array()
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			ring.append(Vector3(c.x * section.y * 0.5, section.x, c.y * section.z * 0.5))
		rings.append(ring)
	ProcMesh.loft(wood, rings)
	var mesh := b.commit(WeaponMeshes.make_material)
	_meshes[key] = mesh
	return mesh
