class_name RopeLadder
extends Node3D

## Escala de cuerda: dos cabos de fibra con travesaños de rama, atada a dos estacas encima de un
## bloque y colgada por el canto de una de sus caras hasta el suelo (o hasta meterse un poco en el
## mar, para subir nadando a un barco). Es un colocable (BuildingSystem): su marco es el del
## colocable, con el origen en el canto, +Y hacia abajo a lo largo de la escala y +Z hacia fuera de
## la cara. No choca con nada: su cuerpo va en PhysicsLayers.CLIMBABLE, que solo ven los rayos del
## jugador para apuntarla y quitarla. Se trepa con USAR (ClimbController).

const ITEM := &"rope_ladder_01"
## Las escalas puestas (no los fantasmas del martillo): donde las busca ClimbController.
const GROUP := &"rope_ladders"
## Entre los dos cabos, de la cara a los cabos y entre travesaños (m).
const WIDTH := 0.46
const STANDOFF := 0.035
const RUNG_SPACING := 0.32
const FIRST_RUNG := 0.24
const ROPE_RADIUS := 0.013
const RUNG_RADIUS := 0.02
## Las estacas, encima del bloque y por dentro del canto (m).
const STAKE_IN := 0.17
## Cuelga hasta lo primero que toca, entre estos largos (m)...
const MIN_LENGTH := 1.0
const MAX_LENGTH := 12.0
## ...y sobre el agua, hasta esto por debajo del nivel del mar.
const WATER_DEPTH := 1.2
## El largo va en pasos de esto (m): el fantasma no rehace la malla a cada milímetro.
const LENGTH_STEP := 0.05
## Material de los cabos: fibra torcida, más parda que la fibra suelta.
const ROPE := &"rope"

var length := 3.0
var _mesh: MeshInstance3D

static var _materials := {}


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = make_mesh(length)
	add_child(_mesh)
	# El fantasma del martillo no cuelga de un colocable: no se trepa.
	var anchor := get_parent()
	if anchor != null and anchor.has_meta(&"prop_key"):
		add_to_group(GROUP)


func restore_prop_state(state: Dictionary) -> void:
	set_length(float(state.get("length", length)))


func set_length(value: float) -> void:
	value = clamp_length(value)
	if is_equal_approx(value, length):
		return
	length = value
	if _mesh != null:
		_mesh.mesh = make_mesh(length)


static func clamp_length(value: float) -> float:
	return snappedf(clampf(value, MIN_LENGTH, MAX_LENGTH), LENGTH_STEP)


## La caja con la que se apunta (en el marco del colocable, hacia abajo desde el canto).
static func collider_size(ladder_length: float) -> Vector3:
	return Vector3(WIDTH + 0.14, clamp_length(ladder_length), 0.1)


## Marco del colocable en la cara [out] (en la grid): +Y hacia abajo y +Z hacia fuera.
static func hanging_basis(out: Vector3) -> Basis:
	return Basis(Vector3.DOWN.cross(out), Vector3.DOWN, out)


## Lo que cuelga desde [top] (el canto, en mundo) a lo largo de [down] hasta lo primero del mundo
## que toque, o hasta WATER_DEPTH bajo el mar (la esfera de [sea_center] y [sea_radius]; radio 0 si
## no hay), entre MIN_LENGTH y MAX_LENGTH.
static func measure_length(space: PhysicsDirectSpaceState3D, top: Vector3, down: Vector3, out: Vector3,
		sea_center: Vector3, sea_radius: float) -> float:
	# Un poco por fuera de la cara, para no rozar la pared de la que cuelga.
	var from := top + out * 0.1 + down * 0.05
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + down * MAX_LENGTH,
		PhysicsLayers.WORLD))
	var reach := MAX_LENGTH
	if not hit.is_empty():
		reach = ((hit.position as Vector3) - top).dot(down)
	if sea_radius > 0.0:
		# Donde la escala entra en la esfera del mar.
		var m := top - sea_center
		var b := m.dot(down)
		var c := m.length_squared() - sea_radius * sea_radius
		if c <= 0.0:
			reach = minf(reach, WATER_DEPTH)
		elif b * b - c >= 0.0 and b < 0.0:
			reach = minf(reach, -b - sqrt(b * b - c) + WATER_DEPTH)
	return clamp_length(reach)


# ---------------------------------------------------------------------------------------------
# En mundo, para ClimbController


## El canto del que cuelga.
func top() -> Vector3:
	return global_position


## Hacia abajo a lo largo de la escala.
func down() -> Vector3:
	return global_basis.y.normalized()


## Hacia fuera de la cara de la que cuelga.
func out() -> Vector3:
	return global_basis.z.normalized()


## Arriba del todo en la línea de los travesaños.
func rung_top() -> Vector3:
	return top() + out() * STANDOFF


# ---------------------------------------------------------------------------------------------
# Malla


## La escala de [ladder_length] m, en el marco del colocable. [thickness] engruesa cabos y
## travesaños (el icono, que se ve muy pequeño).
static func make_mesh(ladder_length: float, thickness: float = 1.0) -> ArrayMesh:
	var builder := ProcMesh.Builder.new()
	var rope := builder.st(ROPE)
	var wood := builder.st(WeaponMeshes.WOOD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var rungs := PackedFloat32Array()
	var y := FIRST_RUNG
	while y <= ladder_length - 0.08:
		rungs.append(y)
		y += RUNG_SPACING
	for side in [-1.0, 1.0]:
		var x: float = side * WIDTH * 0.5
		# La estaca, clavada encima del bloque, y el cabo que sale de ella y dobla el canto.
		ProcMesh.tube(wood, PackedVector3Array([Vector3(x, 0.02, -STAKE_IN), Vector3(x, -0.13, -STAKE_IN)]),
			PackedVector2Array([Vector2.ONE * 0.016, Vector2.ONE * 0.024]), 6)
		var r := ROPE_RADIUS * thickness
		var points := PackedVector3Array([Vector3(x, -0.05, -STAKE_IN), Vector3(x, -r, -STAKE_IN + 0.04),
			Vector3(x, -r, -0.02), Vector3(x, -r * 0.7, r * 0.7), Vector3(x, 0.03, STANDOFF)])
		var radii := PackedVector2Array([Vector2.ONE * r * 1.6, Vector2.ONE * r, Vector2.ONE * r, Vector2.ONE * r,
			Vector2.ONE * r])
		# Un nudo en cada travesaño.
		for rung in rungs:
			for k in [-0.035, 0.0, 0.035]:
				points.append(Vector3(x, rung + k, STANDOFF))
				radii.append(Vector2.ONE * r * (1.8 if k == 0.0 else 1.0))
		points.append(Vector3(x, ladder_length, STANDOFF))
		radii.append(Vector2.ONE * r * 0.8)
		ProcMesh.tube(rope, points, radii, 6)
	for rung in rungs:
		var half := WIDTH * 0.5 + rng.randf_range(0.04, 0.07)
		var tilt := rng.randf_range(-0.012, 0.012)
		ProcMesh.tube(wood, PackedVector3Array([Vector3(-half, rung - tilt, STANDOFF),
			Vector3(0.0, rung + rng.randf_range(-0.004, 0.004), STANDOFF + rng.randf_range(-0.006, 0.006)),
			Vector3(half, rung + tilt, STANDOFF)]),
			PackedVector2Array([Vector2.ONE * RUNG_RADIUS * thickness * rng.randf_range(0.75, 0.9),
				Vector2.ONE * RUNG_RADIUS * thickness * rng.randf_range(0.95, 1.1),
				Vector2.ONE * RUNG_RADIUS * thickness * rng.randf_range(0.75, 0.9)]),
			7, Vector3.UP)
	return builder.commit(_material)


static func _material(kind: StringName) -> Material:
	if not _materials.has(kind):
		if kind == ROPE:
			var rope := StandardMaterial3D.new()
			rope.resource_name = String(ROPE)
			rope.albedo_texture = ProcMesh.noise_texture(Color(0.40, 0.32, 0.20), Color(0.70, 0.60, 0.42), 9.0, 2207)
			rope.roughness = 0.95
			_materials[kind] = rope
		else:
			_materials[kind] = SurvivalMeshes.make_material(kind)
	return _materials[kind]
