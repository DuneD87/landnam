class_name QuiverVisual
extends Node3D

## Aljaba a la espalda con las flechas que quedan asomando (hasta MAX_SHOWN). La coloca quien
## la lleva en ArcheryPose.quiver_skel (boca en el origen, +Y hacia fuera).

const MAX_SHOWN := 7

var _arrows: Array[MeshInstance3D] = []


func _ready() -> void:
	var body := MeshInstance3D.new()
	body.name = "Mesh"
	body.mesh = load("res://data/items/meshes/weapons/quiver.res")
	add_child(body)
	var arrow_mesh: Mesh = load("res://data/items/meshes/weapons/arrow.res")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in MAX_SHOWN:
		var arrow := MeshInstance3D.new()
		arrow.mesh = arrow_mesh
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Punta abajo, repartidas por la boca y asomando más o menos.
		var a := TAU * i / MAX_SHOWN + rng.randf_range(-0.3, 0.3)
		var r := 0.024 if i > 0 else 0.0
		var out := rng.randf_range(0.13, 0.19)
		var tilt := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), rng.randf_range(0.03, 0.08) * (1.0 if r > 0.0 else 0.0))
		var basis := tilt * Basis(Vector3.RIGHT, PI) * Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		arrow.transform = Transform3D(basis, Vector3(cos(a) * r, out - WeaponMeshes.ARROW_LENGTH * 0.5, sin(a) * r))
		add_child(arrow)
		_arrows.append(arrow)


## Cuántas flechas lleva (se ven como mucho MAX_SHOWN).
func set_count(count: int) -> void:
	for i in _arrows.size():
		_arrows[i].visible = i < count
