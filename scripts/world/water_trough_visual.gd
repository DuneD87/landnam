@tool
extends MeshInstance3D

## Bebedero: un dornajo bajo de tablas, calzado en dos traviesas y forrado de piel por dentro. A lo
## largo va X. La misma malla en el mundo y en la vista previa; el agua es aparte (WaterTrough).
static var _mesh: ArrayMesh

## Largo, ancho y alto por fuera (m), grueso de las tablas y altura del fondo por dentro.
const LENGTH := 1.3
const WIDTH := 0.56
const HEIGHT := 0.42
const PLANK := 0.05
const FLOOR := 0.12
## El forro: así de metido en la madera.
const LINING := 0.012


func _ready() -> void:
	mesh = make_mesh()


static func make_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var builder := ProcMesh.Builder.new()
	var wood := builder.st(WeaponMeshes.WOOD)
	var hx := LENGTH * 0.5
	var hz := WIDTH * 0.5
	# Las dos traviesas en que se calza.
	for end in [-1.0, 1.0]:
		ProcMesh.box(wood, Vector3(end * (hx - 0.16), 0.04, 0.0), Vector3(0.12, 0.08, WIDTH + 0.12))
	# El fondo y los costados.
	ProcMesh.box(wood, Vector3(0.0, FLOOR - PLANK * 0.5, 0.0), Vector3(LENGTH, PLANK, WIDTH))
	for side in [-1.0, 1.0]:
		ProcMesh.box(wood, Vector3(0.0, (FLOOR - PLANK + HEIGHT) * 0.5, side * (hz - PLANK * 0.5)),
			Vector3(LENGTH, HEIGHT - FLOOR + PLANK, PLANK))
		ProcMesh.box(wood, Vector3(side * (hx - PLANK * 0.5), (FLOOR - PLANK + HEIGHT) * 0.5, 0.0),
			Vector3(PLANK, HEIGHT - FLOOR + PLANK, WIDTH - PLANK * 2.0))
	# El forro de piel: fondo y paredes por dentro, y doblado por encima del borde.
	var hide := builder.st(SurvivalMeshes.HIDE)
	var ix := hx - PLANK - LINING
	var iz := hz - PLANK - LINING
	ProcMesh.box(hide, Vector3(0.0, FLOOR + LINING * 0.5, 0.0), Vector3(ix * 2.0, LINING, iz * 2.0))
	for side in [-1.0, 1.0]:
		ProcMesh.box(hide, Vector3(0.0, (FLOOR + HEIGHT) * 0.5, side * (iz + LINING * 0.5)),
			Vector3(ix * 2.0, HEIGHT - FLOOR, LINING))
		ProcMesh.box(hide, Vector3(side * (ix + LINING * 0.5), (FLOOR + HEIGHT) * 0.5, 0.0),
			Vector3(LINING, HEIGHT - FLOOR, iz * 2.0))
		ProcMesh.box(hide, Vector3(0.0, HEIGHT + LINING * 0.5, side * (hz - PLANK * 0.5)),
			Vector3(LENGTH - 0.04, LINING, PLANK + 0.03))
	_mesh = builder.commit(SurvivalMeshes.make_material)
	return _mesh


## El hueco de dentro: medio largo y medio ancho (m), y el alto del agua vacío y lleno.
static func inner() -> Vector2:
	return Vector2(LENGTH * 0.5 - PLANK - LINING, WIDTH * 0.5 - PLANK - LINING)


static func water_heights() -> Vector2:
	return Vector2(FLOOR + LINING + 0.01, HEIGHT - 0.05)
