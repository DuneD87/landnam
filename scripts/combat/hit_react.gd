class_name HitReact
extends SkeletonModifier3D

## Respingo al encajar un golpe: dobla una cadena de huesos (tronco, cuello, cabeza) en el sentido
## del golpe y la devuelve con un muelle amortiguado. Sirve para cualquier esqueleto: el giro se
## hace en el espacio del esqueleto a partir de la dirección del golpe en mundo, sin mirar los
## ejes de cada hueso.

## Huesos de la cadena, de la base a la punta, y su parte del giro.
@export var chain: Array[String] = []
@export var weights: Array[float] = []
## Grados máximos que dobla un golpe de fuerza 1.
@export var max_angle: float = 22.0

var _skel: Skeleton3D
var _bones: PackedInt32Array = PackedInt32Array()
var _bone_weights: PackedFloat32Array = PackedFloat32Array()
var _axis_world: Vector3 = Vector3.RIGHT
var _strength: float = 0.0
var _time: float = 10.0


func _ready() -> void:
	_skel = get_skeleton()
	if _skel == null:
		active = false
		return
	for i in chain.size():
		var idx := _skel.find_bone(chain[i])
		if idx >= 0:
			_bones.append(idx)
			_bone_weights.append(weights[i] if i < weights.size() else 1.0 / chain.size())


## Dispara el respingo: [direction] es hacia donde empuja el golpe (mundo), [strength] 0..1.
func flinch(direction: Vector3, up: Vector3, strength: float) -> void:
	var push := direction - up * direction.dot(up)
	if push.length_squared() < 1e-6:
		push = -_skel.global_basis.z if _skel else Vector3.FORWARD
	_axis_world = up.cross(push.normalized()).normalized()
	_strength = clampf(strength, 0.0, 1.5)
	_time = 0.0


func _process_modification_with_delta(delta: float) -> void:
	_time += delta
	_apply()


func _process_modification() -> void:
	_apply()


## Curva del respingo: sube en 70 ms y vuelve oscilando un poco en ~0,4 s.
func _curve(t: float) -> float:
	if t < 0.07:
		return t / 0.07
	var u := t - 0.07
	return exp(-u * 7.0) * cos(u * 9.0)


func _apply() -> void:
	if _skel == null or _bones.is_empty() or _time > 0.8:
		return
	var angle := deg_to_rad(max_angle) * _strength * _curve(_time)
	if absf(angle) < 0.0005:
		return
	var axis := (_skel.global_basis.inverse() * _axis_world).normalized()
	for i in _bones.size():
		var bone := _bones[i]
		var rot := Quaternion(axis, angle * _bone_weights[i])
		var new_basis := Basis(rot) * _skel.get_bone_global_pose(bone).basis
		var parent := _skel.get_bone_parent(bone)
		if parent >= 0:
			new_basis = _skel.get_bone_global_pose(parent).basis.inverse() * new_basis
		_skel.set_bone_pose_rotation(bone, new_basis.get_rotation_quaternion())
