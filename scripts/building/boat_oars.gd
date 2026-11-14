class_name BoatOars
extends Node3D

## Los remos de los remeros: uno por cada aldeano sentado en una bancada junto a la borda (RowingBench).
## Solo decoran: el empuje lo da BoatSailing.rowing_acceleration según cuántos hay. Cada remo apoya en
## el costado, a la altura de la eslora de su bancada (de las cajas de colisión del casco,
## espacio local del body, proa +Z), y baja hasta el agua; el mango llega hasta el remero. Con la
## marcha de remo bogan; si no, descansan con la pala fuera del agua.
## Ciclo de una palada (s). Ciar va algo más lento.
const STROKE_TIME := 1.7
const BACK_STROKE_TIME := 2.1
## Barrido alrededor del tolete (rad, + hacia proa) y alzado de la pala en el retorno.
const SWEEP_CENTER := 0.05
const SWEEP_AMPLITUDE := 0.4
const LIFT := 0.3
## Recorrido del mango y separación de las manos (m). El barrido se adapta a su longitud.
const HANDLE_TRAVEL := 0.18
const HAND_SPACING := 0.22
## El final del tirón deja sitio para muñecas y antebrazos delante del abdomen.
const HOLD_FORWARD := 0.36
const HOLD_HEIGHT := 0.23
## Mango que queda dentro de la borda (por defecto), y lo que la pala pasa del punto de entrada en el agua.
const INBOARD := 0.7
const BLADE := 0.85
## Una bancada da remo si su centro queda a menos de esto (m, en horizontal) de la borda de su costado.
const ROW_REACH := 2.4
## Quieto: la fase en la que la pala queda alzada y a mitad de barrido.
const REST_PHASE := 0.75

var direction := 0
var _phase := 0.0
## Las bancadas con remo de ahora (sus instance id, en orden), para rehacer solo si cambian.
var _keys: Array[int] = []
var _hull_version := -1
var _layout: Array[Dictionary] = []
var _oars: Array[Dictionary] = []
static var _meshes := {}


func _ready() -> void:
	name = "Oars"
	visible = false
	set_process(false)


## [row]: -1 ciar, 0 parado, 1 remar. [list]: un remo por remero ({key, pivot, side, length, pitch,
## inboard}, de station_at), en el marco del body.
func update(row: int, list: Array[Dictionary], hull_version: int) -> void:
	var keys: Array[int] = []
	for station in list:
		keys.append(int(station["key"]))
	if keys != _keys or hull_version != _hull_version or list != _layout:
		_keys = keys
		_hull_version = hull_version
		_layout = list.duplicate(true)
		_rebuild(list)
	visible = not _oars.is_empty()
	if row == direction:
		return
	direction = row
	_phase = REST_PHASE if row == 0 else 0.0
	set_process(row != 0)
	_pose()


func _process(delta: float) -> void:
	_phase = fposmod(_phase + delta * direction / (STROKE_TIME if direction > 0 else BACK_STROKE_TIME), 1.0)
	_pose()


## Dónde va la palada (0-1), para que el remero la acompañe.
func phase() -> float:
	return _phase


func _pose() -> void:
	for oar: Dictionary in _oars:
		(oar["node"] as Node3D).transform = station_pose(oar, _phase)


func _rebuild(list: Array[Dictionary]) -> void:
	for oar: Dictionary in _oars:
		(oar["node"] as Node).queue_free()
	_oars.clear()
	if direction == 0:
		_phase = REST_PHASE
	for station: Dictionary in list:
		station = station.duplicate()
		var node := MeshInstance3D.new()
		node.mesh = oar_mesh(station["length"], station.get("inboard", INBOARD))
		add_child(node)
		station["node"] = node
		_oars.append(station)
	_pose()


## El remo de quien se sienta en [seat] (marco del body: el centro de la bancada) con el casco de esas
## cajas: {pivot, side, length, pitch, inboard, hold, sweep, lift}. El agarre queda delante del cuerpo
## y bajo los hombros; el apoyo sale en el costado más cercano. {} si queda lejos de la borda (más de ROW_REACH) o
## fuera del casco.
static func station_at(seat: Vector3, box_pos: PackedVector3Array, box_half: PackedVector3Array,
		forward := Vector3.FORWARD) -> Dictionary:
	if box_pos.is_empty():
		return {}
	var best := {}
	var best_gap := INF
	for side: float in [-1.0, 1.0]:
		var rim := _rim(seat.z, side, box_pos, box_half)
		if rim.is_empty():
			continue
		var gap: float = rim["outer"] - side * seat.x
		if gap < -0.3 or gap > ROW_REACH or gap >= best_gap:
			continue
		best_gap = gap
		var top: float = rim["top"]
		# El agarre manda la altura: usar la coronación de un costado alto levanta el mango
		# por encima de la cabeza. En esos cascos el remo sale por el costado, bajo la borda.
		var grip := seat + forward.slide(Vector3.UP).normalized() * HOLD_FORWARD + Vector3.UP * HOLD_HEIGHT
		var water_y: float = lerpf(float(rim["bottom"]), top, 0.4) - 0.3
		var span := maxf(float(rim["outer"]) + 0.02 - side * grip.x, 0.05)
		var pitch := clampf(atan2(maxf(grip.y - water_y, 0.2), span + 3.0), 0.18, 0.65)
		var lift := minf(0.10, 0.12 / maxf(span, 0.45))
		var hold := span / (cos(pitch - lift) * cos(SWEEP_CENTER))
		var sweep := minf(SWEEP_AMPLITUDE, atan(HANDLE_TRAVEL / hold))
		var rest_axis := oar_basis(side, pitch, REST_PHASE, sweep, lift).y
		var pivot := grip + rest_axis * hold
		var oar_length := clampf((pivot.y - water_y) / sin(pitch) + BLADE * 0.5, 2.4, 6.0)
		best = {"pivot": pivot, "side": side, "length": oar_length, "pitch": pitch,
			"hold": hold, "inboard": hold + HAND_SPACING * 0.5 + 0.10, "sweep": sweep, "lift": lift}
	return best


## La misma transformación para la malla y para los objetivos de las manos.
static func station_pose(station: Dictionary, phase: float) -> Transform3D:
	return Transform3D(oar_basis(station["side"], station["pitch"], phase,
		station.get("sweep", SWEEP_AMPLITUDE), station.get("lift", LIFT)), station["pivot"])


## Centro de agarre y eje del mango, en el marco del barco.
static func grip_at(station: Dictionary, phase: float) -> Vector3:
	var pose := station_pose(station, phase)
	return pose * Vector3(0.0, -float(station.get("hold", INBOARD - 0.2)), 0.0)


## La borda del costado [side] a la altura [z] de la eslora: {outer, top, bottom}, o {} sin casco ahí.
static func _rim(z: float, side: float, box_pos: PackedVector3Array, box_half: PackedVector3Array) -> Dictionary:
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
		return {}
	return {"outer": outer, "top": top, "bottom": bottom}


## Palo a lo largo de Y local hacia fuera y abajo. Palada (fase 0 → 0.5): la pala, metida y de
## canto, barre de proa a popa; en el retorno sale del agua y se pone plana.
static func oar_basis(side: float, pitch: float, phase: float,
		sweep_amplitude := SWEEP_AMPLITUDE, lift := LIFT) -> Basis:
	var sweep := SWEEP_CENTER + sweep_amplitude * cos(TAU * phase)
	var raised := maxf(-sin(TAU * phase), 0.0)
	var angle := pitch - lift * raised
	var axis := Vector3(side * cos(angle) * cos(sweep), -sin(angle), cos(angle) * sin(sweep))
	var width := (Vector3.UP - axis * axis.y).normalized()
	width = width.rotated(axis, PI * 0.5 * clampf(raised * 3.0, 0.0, 1.0) * side)
	return Basis(width, axis, width.cross(axis))


static func oar_mesh(length: float, inboard := INBOARD) -> ArrayMesh:
	var key := Vector2i(roundi(length * 10.0), roundi(inboard * 20.0))
	if _meshes.has(key):
		return _meshes[key]
	length = key.x / 10.0
	inboard = key.y / 20.0
	var b := ProcMesh.Builder.new()
	var wood := b.st(WeaponMeshes.WOOD)
	var neck := length - BLADE
	ProcMesh.lathe(wood, [Vector2(0.0, -inboard), Vector2(0.026, -inboard), Vector2(0.03, -inboard + 0.04),
		Vector2(0.03, -inboard + 0.3), Vector2(0.042, -inboard + 0.36), Vector2(0.045, 0.15),
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
