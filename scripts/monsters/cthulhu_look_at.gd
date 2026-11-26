class_name CthulhuLookAt
extends SkeletonModifier3D

## Lleva la cara de Cthulhu hacia [target] (mundo) encima de la animación: reparte entre lomo, pecho,
## cuello y cabeza el giro que hay desde donde mira la animación en este fotograma hasta el objetivo.
## Así la mirada del abismo, hecha para alguien de pie delante, clava los ojos en un barco a 400 m y a
## 60 m por debajo de la cara. [weight] (0..1) funde la corrección; con 0 no toca nada.

const CHAIN: Array[String] = ["Lomo", "Pecho", "Cuello", "Cabeza"]
const WEIGHTS: Array[float] = [0.12, 0.18, 0.3, 0.4]
## Giro máximo entre la cara animada y el objetivo; más allá se queda en el tope.
const MAX_ANGLE := deg_to_rad(85.0)

var target := Vector3.ZERO
var weight := 0.0
## Frente del cuerpo en espacio del esqueleto (la escena del modelo mira a +Z).
var model_forward := Vector3.BACK

var _skel: Skeleton3D
var _bones := PackedInt32Array()
var _head := -1
## Frente de la cara en espacio del hueso de la cabeza, sacado de la pose de reposo.
var _face_local := Vector3.BACK
## Pose de la cabeza (espacio de esqueleto) ya girada, del último fotograma con mirada. Fuera de la
## modificación el esqueleto devuelve la de la animación: Godot deshace los modificadores al acabar.
var _final_head := Transform3D()
var _has_final := false


func _ready() -> void:
	_skel = get_skeleton()
	if _skel == null:
		active = false
		return
	for bone_name in CHAIN:
		_bones.append(_skel.find_bone(bone_name))
	_head = _skel.find_bone("Cabeza")
	if _head < 0 or _bones.has(-1):
		push_warning("CthulhuLookAt: faltan huesos de la cadena en el esqueleto.")
		active = false
		return
	var rest := _skel.get_bone_global_rest(_head).basis
	_face_local = (rest.inverse() * model_forward).normalized()


## Posición de los ojos en mundo (entre los dos, en la cara).
func eye_position() -> Vector3:
	if _skel == null or _head < 0:
		return Vector3.ZERO
	# El hueso nace en la nuca y sube 0,25 (unidades del modelo): los ojos, a media cabeza y delante.
	var pose := _final_head if _has_final and weight > 0.001 else _skel.get_bone_global_pose(_head)
	var tip := pose.origin + pose.basis.y.normalized() * 0.11 + (pose.basis * _face_local).normalized() * 0.09
	return _skel.global_transform * tip


func _process_modification_with_delta(_delta: float) -> void:
	_has_final = false
	if weight <= 0.001 or _skel == null or _head < 0:
		return
	var to_skel := _skel.global_transform.affine_inverse()
	var head_pose := _skel.get_bone_global_pose(_head)
	var face := (head_pose.basis * _face_local).normalized()
	var aim := (to_skel * target - head_pose.origin).normalized()
	if aim.length_squared() < 0.5:
		return
	var axis := face.cross(aim)
	if axis.length_squared() < 1e-10:
		return
	axis = axis.normalized()
	var angle := minf(face.angle_to(aim), MAX_ANGLE) * clampf(weight, 0.0, 1.0)
	# Cada hueso gira su parte en espacio de esqueleto; como los hijos heredan, la cabeza acaba con
	# la suma de todos.
	for i in _bones.size():
		_rotate_bone(_bones[i], Quaternion(axis, angle * WEIGHTS[i]))
	_final_head = _skel.get_bone_global_pose(_head)
	_has_final = true


func _rotate_bone(bone: int, rot: Quaternion) -> void:
	var new_basis := Basis(rot) * _skel.get_bone_global_pose(bone).basis
	var parent := _skel.get_bone_parent(bone)
	if parent >= 0:
		new_basis = _skel.get_bone_global_pose(parent).basis.inverse() * new_basis
	_skel.set_bone_pose_rotation(bone, new_basis.get_rotation_quaternion())
