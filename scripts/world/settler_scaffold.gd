class_name SettlerScaffold extends Node3D

## El andamio de un colono constructor (SettlerBuild): cuatro postes de rollizo, una plataforma de
## tablas a [height] m y una escalera de mano por detrás, atados con tendón. Lo planta junto a la obra
## cuando lo siguiente por poner queda alto (BlueprintSite.next_point), sube por la escalera
## (Companion.climb_ladder, con las animaciones de trepar) y martillea desde arriba; si la obra sube más,
## baja, lo sube de altura y vuelve a subir; al acabar baja y lo quita. Solo la plataforma choca (capa
## del mundo), para que se pueda estar de pie encima. No se guarda: al cargar se vuelve a plantar.
##
## Marco: el origen en el suelo, en medio; +Z hacia la obra (hacia donde mira quien martillea) y la
## escalera en el lado de -Z. Ver docs/villagers.md (Constructor).

## La planta (m), lo que sobresale la escalera, el grueso de la plataforma, los peldaños y la baranda.
const HALF := 0.7
const LADDER_OUT := 0.12
const DECK := 0.08
const RUNG := 0.32
const RAIL := 0.95
## Lo más alto y lo más bajo que se pone la plataforma (m), y de cuánto en cuánto.
const MIN_HEIGHT := 1.0
const MAX_HEIGHT := 9.0
const HEIGHT_STEP := 0.5
## A qué distancia de la escalera va quien trepa (m), como de una pared (ClimbRoutes), y cuánto por
## debajo de la plataforma deja de trepar y corona (sus pies).
const CLIMB_OFF := 0.38
const TOP_BELOW := 1.35
## Dónde se pone de pie arriba (marco del andamio).
const STAND := Vector3(0.0, 0.0, 0.25)

static var _meshes := {}

var height := 2.0
var _mesh: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D


## Uno nuevo en [at] (mundo, en el suelo) con +Z hacia [toward] y arriba [up], de [deck] m.
static func plant(parent: Node, at: Vector3, toward: Vector3, up: Vector3, deck: float) -> SettlerScaffold:
	var scaffold := SettlerScaffold.new()
	scaffold.name = "SettlerScaffold"
	parent.add_child(scaffold)
	var forward := (toward - up * toward.dot(up)).normalized()
	if not forward.is_finite() or forward.is_zero_approx():
		forward = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	scaffold.global_transform = Transform3D(Basis(up.cross(forward).normalized(), up, forward), at)
	scaffold.set_height(deck)
	return scaffold


## La altura de la plataforma que hace falta para poner algo a [rise] m sobre el suelo con el martillo a
## la altura del pecho ([reach] m sobre los pies), redondeada a HEIGHT_STEP.
static func deck_for(rise: float, reach: float) -> float:
	return clampf(snappedf(rise - reach, HEIGHT_STEP), MIN_HEIGHT, MAX_HEIGHT)


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	add_child(_mesh)
	_body = StaticBody3D.new()
	_body.collision_layer = PhysicsLayers.WORLD
	_body.collision_mask = 0
	add_child(_body)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HALF * 2.0, DECK, HALF * 2.0)
	_shape.shape = box
	_body.add_child(_shape)
	set_height(height)


func set_height(deck: float) -> void:
	height = clampf(snappedf(deck, HEIGHT_STEP), MIN_HEIGHT, MAX_HEIGHT)
	if _mesh == null:
		return
	_mesh.mesh = make_mesh(height)
	_shape.position = Vector3(0.0, height - DECK * 0.5, 0.0)


## Lo alto de la plataforma (mundo).
func deck_top() -> Vector3:
	return global_transform * Vector3(0.0, height, 0.0)


## Dónde se pone de pie arriba para martillear (mundo).
func stand_point() -> Vector3:
	return global_transform * (STAND + Vector3(0.0, height, 0.0))


## Dónde se pone al pie de la escalera para empezar a subir (mundo).
func foot() -> Vector3:
	return global_transform * Vector3(0.0, 0.0, -HALF - LADDER_OUT - CLIMB_OFF)


## Hacia dónde mira la escalera (mundo): de ella hacia quien trepa.
func ladder_normal() -> Vector3:
	return -global_basis.z


## Los puntos por los que suben sus pies (mundo), del suelo hasta donde corona.
func climb_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	var top := maxf(height - TOP_BELOW, 0.2)
	var steps := maxi(ceili(top / 0.5), 1)
	for i in steps + 1:
		out.append(global_transform * Vector3(0.0, top * i / steps, -HALF - LADDER_OUT - CLIMB_OFF))
	return out


## Los mismos, de arriba abajo, para bajar: desde el borde de la plataforma hasta el suelo.
func descend_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	var top := maxf(height - TOP_BELOW, 0.2)
	var steps := maxi(ceili(top / 0.5), 1)
	for i in range(steps, -1, -1):
		out.append(global_transform * Vector3(0.0, top * i / steps, -HALF - LADDER_OUT - CLIMB_OFF))
	return out


## Si [at] (mundo, unos pies) está encima de la plataforma.
func is_on(at: Vector3) -> bool:
	var local := global_transform.affine_inverse() * at
	return absf(local.x) <= HALF + 0.15 and absf(local.z) <= HALF + 0.15 and absf(local.y - height) <= 0.4


static func make_mesh(deck: float) -> ArrayMesh:
	var key := roundi(deck / HEIGHT_STEP)
	if _meshes.has(key):
		return _meshes[key]
	var builder := ProcMesh.Builder.new()
	var wood := builder.st(WeaponMeshes.WOOD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5110 + key
	var top := deck + RAIL
	# Los postes de las esquinas, hasta la baranda; y riostras en cruz en los dos costados.
	for x in [-HALF, HALF]:
		for z in [-HALF, HALF]:
			ProcMesh.tube(wood, PackedVector3Array([Vector3(x, -0.15, z), Vector3(x * 1.01, top, z * 1.01)]),
				PackedVector2Array([Vector2.ONE * 0.065, Vector2.ONE * 0.055]), 7)
		ProcMesh.tube(wood, PackedVector3Array([Vector3(x, 0.2, -HALF), Vector3(x, deck - 0.1, HALF)]),
			PackedVector2Array([Vector2.ONE * 0.035, Vector2.ONE * 0.035]), 5)
		ProcMesh.tube(wood, PackedVector3Array([Vector3(x, 0.2, HALF), Vector3(x, deck - 0.1, -HALF)]),
			PackedVector2Array([Vector2.ONE * 0.035, Vector2.ONE * 0.035]), 5)
	# Los largueros bajo la plataforma y las tablas encima.
	for z in [-HALF, HALF]:
		ProcMesh.tube(wood, PackedVector3Array([Vector3(-HALF - 0.08, deck - DECK - 0.04, z), Vector3(HALF + 0.08, deck - DECK - 0.04, z)]),
			PackedVector2Array([Vector2.ONE * 0.05, Vector2.ONE * 0.05]), 6)
	var boards := 6
	for i in boards:
		var x := lerpf(-HALF + 0.11, HALF - 0.11, i / float(boards - 1))
		ProcMesh.box(wood, Vector3(x, deck - DECK * 0.5 + rng.randf_range(-0.006, 0.006), 0.0),
			Vector3(0.22, DECK * 0.6, HALF * 2.0 + 0.1), Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)))
	# La baranda por delante y a los lados (por detrás se sube).
	for side in [[Vector3(-HALF, top - 0.05, HALF), Vector3(HALF, top - 0.05, HALF)],
			[Vector3(-HALF, top - 0.05, -HALF), Vector3(-HALF, top - 0.05, HALF)],
			[Vector3(HALF, top - 0.05, -HALF), Vector3(HALF, top - 0.05, HALF)]]:
		ProcMesh.tube(wood, PackedVector3Array(side), PackedVector2Array([Vector2.ONE * 0.04, Vector2.ONE * 0.04]), 6)
	# La escalera: dos largueros apoyados en la plataforma y los peldaños.
	var foot_z := -HALF - LADDER_OUT - 0.25
	for x in [-0.22, 0.22]:
		ProcMesh.tube(wood, PackedVector3Array([Vector3(x, -0.05, foot_z), Vector3(x, deck + 0.6, -HALF - 0.02)]),
			PackedVector2Array([Vector2.ONE * 0.045, Vector2.ONE * 0.04]), 6)
	var rungs := floori((deck + 0.4) / RUNG)
	for i in range(1, rungs + 1):
		var y := i * RUNG
		var z := lerpf(foot_z, -HALF - 0.02, y / (deck + 0.65))
		ProcMesh.tube(wood, PackedVector3Array([Vector3(-0.26, y, z), Vector3(0.26, y + rng.randf_range(-0.01, 0.01), z)]),
			PackedVector2Array([Vector2.ONE * 0.028, Vector2.ONE * 0.028]), 5)
	# Ataduras en lo alto de los postes.
	var ties := builder.st(SurvivalMeshes.SINEW)
	for x in [-HALF, HALF]:
		for z in [-HALF, HALF]:
			var points := PackedVector3Array()
			var radii := PackedVector2Array()
			for i in 9:
				var a := TAU * i / 8.0
				points.append(Vector3(x + cos(a) * 0.075, deck - DECK - 0.04, z + sin(a) * 0.075))
				radii.append(Vector2.ONE * 0.01)
			ProcMesh.tube(ties, points, radii, 4)
	var mesh := builder.commit(SurvivalMeshes.make_material)
	_meshes[key] = mesh
	return mesh
