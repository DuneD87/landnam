class_name SimpleBirdModel extends Node3D

const NAMES := ["Gorrión", "Petirrojo", "Herrerillo", "Gaviota", "Pato"]
## Shared offline meshes: no sculpting or LOD generation during spawning.
const BODIES: Array[ArrayMesh] = [
	preload("res://data/fauna/meshes/birds/sparrow_body.res"),
	preload("res://data/fauna/meshes/birds/robin_body.res"),
	preload("res://data/fauna/meshes/birds/blue_tit_body.res"),
	preload("res://data/fauna/meshes/birds/gull_body.res"),
	preload("res://data/fauna/meshes/birds/duck_body.res"),
]
const WINGS: Array[ArrayMesh] = [
	preload("res://data/fauna/meshes/birds/sparrow_wing.res"),
	preload("res://data/fauna/meshes/birds/robin_wing.res"),
	preload("res://data/fauna/meshes/birds/blue_tit_wing.res"),
	preload("res://data/fauna/meshes/birds/gull_wing.res"),
	preload("res://data/fauna/meshes/birds/duck_wing.res"),
]
static var _material: StandardMaterial3D
var left: MeshInstance3D
var right: MeshInstance3D
var body: MeshInstance3D
var _fold: float = 1.0
var _kind: int = 0


func _ready() -> void:
	body = MeshInstance3D.new()
	left = MeshInstance3D.new()
	right = MeshInstance3D.new()
	add_child(body)
	add_child(left)
	add_child(right)
	left.position = Vector3(-0.075, 0.255, 0.0)
	right.position = Vector3(0.075, 0.255, 0.0)
	left.scale.x = -1.0
	set_species(0)
	animate(0.0, false, 1.0)


func set_species(kind: int) -> void:
	kind = clampi(kind, 0, NAMES.size() - 1)
	_kind = kind
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.roughness = 0.85
	body.mesh = BODIES[kind]
	left.mesh = WINGS[kind]
	right.mesh = WINGS[kind]
	for part in [body, left, right]:
		part.material_override = _material
	var wing_origin := Vector3(0.085, 0.255, -0.04)
	if kind >= 3:
		wing_origin = Vector3(0.17 if kind == 4 else 0.13, 0.30, -0.025)
	right.position = wing_origin
	left.position = Vector3(-wing_origin.x, wing_origin.y, wing_origin.z)


func animate(time: float, flying: bool, delta: float) -> void:
	_fold = move_toward(_fold, 0.0 if flying else 1.0, delta * 5.0)
	var beat := 10.0 if _kind == 3 else (18.0 if _kind == 4 else 22.0)
	var flight := Basis(Vector3.BACK, sin(time * beat) * 0.7)
	# Resting feathers lie down the flanks, with their long axis toward the tail.
	var along := Vector3(0.12, -0.12, 1.0).normalized()
	var trailing := (Vector3.DOWN - along * along.dot(Vector3.DOWN)).normalized()
	var folded := Basis(along, trailing.cross(along), trailing)
	var orientation := Basis(flight.get_rotation_quaternion().slerp(folded.get_rotation_quaternion(), _fold))
	var span := lerpf(1.0, 0.78 if _kind >= 3 else 0.74, _fold)
	var chord := lerpf(1.0, 0.28, _fold)
	right.basis = orientation * Basis.from_scale(Vector3(span, 1.0, chord))
	left.basis = Basis.from_scale(Vector3(-1, 1, 1)) * right.basis
	# A little breathing while resting, without moving the feet.
	body.scale.y = 1.0 + sin(time * 3.0) * 0.008 * _fold
