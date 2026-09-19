class_name LookAtIK
extends SkeletonModifier3D

## Orienta cabeza, cuello y torso hacia donde apunta la camara (o hacia un nodo objetivo),
## repartiendo el giro entre varios huesos con pesos. Trabaja sobre la desviacion respecto al
## frente del propio cuerpo, no sobre ejes de hueso, asi que no depende de la convencion del rig
## ni del "arriba" gravitacional. La direccion suavizada se guarda en espacio local del cuerpo.

const Config = preload("res://scripts/config.gd")

const _EPS := 0.0001

@export_group("Huesos")
## Cadena de huesos y cuanto giro se lleva cada uno. Los pesos deben sumar 1.
@export var chain: Array[String] = ["mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head"]
@export var weights: Array[float] = [0.15, 0.15, 0.25, 0.45]

## Frente del personaje en espacio del cuerpo. Si la cabeza mira justo al reves, ponlo en (0,0,1).
@export var body_forward: Vector3 = Vector3.FORWARD

@export_group("Objetivo")
## Nodo al que mirar. Vacio: mira hacia donde apunta la camara activa.
@export var target_path: NodePath
@export var max_distance: float = 25.0

@export_group("Limites")
## Desviacion maxima respecto al frente del cuerpo con seguimiento completo.
@export_range(0.0, 180.0) var max_angle: float = 75.0
## Desviacion a la que la mirada ya ha vuelto del todo a reposo. Entre esta y max_angle la
## influencia se desvanece, asi la cabeza no se gira para esquivar una camara puesta de frente.
@export_range(0.0, 180.0) var release_angle: float = 110.0
@export var turn_speed: float = 8.0

var _skel: Skeleton3D
var _body: CharacterBody3D
var _bones: PackedInt32Array = PackedInt32Array()
var _bone_weights: PackedFloat32Array = PackedFloat32Array()

var _aim_local: Vector3 = Vector3.FORWARD
var _idle: bool = true


func _ready() -> void:
	_skel = get_skeleton()
	_body = _find_body()
	if not _skel or not _body or chain.size() != weights.size():
		push_warning("LookAtIK '%s': falta esqueleto/cuerpo o los pesos no cuadran con la cadena." % name)
		active = false
		return

	for i in chain.size():
		var idx := _skel.find_bone(chain[i])
		if idx >= 0:
			_bones.append(idx)
			_bone_weights.append(weights[i])
	if _bones.is_empty():
		push_warning("LookAtIK '%s': ninguno de los huesos de la cadena existe." % name)
		active = false
		return

	_aim_local = _rest_local()


func _find_body() -> CharacterBody3D:
	var node := get_parent()
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


## Frente del cuerpo en su propio espacio local. Es la direccion de reposo de la mirada.
func _rest_local() -> Vector3:
	if body_forward.length_squared() < _EPS:
		return Vector3.FORWARD
	return body_forward.normalized()


## Actualiza la direccion de mirada suavizada. En espacio local del cuerpo para que no la rompan
## ni un rebase de FloatingOrigin ni el giro del personaje.
func _physics_process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_update_aim(delta)
	DebugStats.report_cost(&"player:lookik", Time.get_ticks_usec() - _t0)


func _update_aim(delta: float) -> void:
	if not active:
		return

	var rest := _rest_local()
	var target := rest
	var desired := _desired_world()

	if desired != Vector3.ZERO:
		var local := (_body.global_basis.inverse() * desired).normalized()
		var angle := rest.angle_to(local)
		var max_radians := deg_to_rad(max_angle)
		if angle <= max_radians:
			target = local
		elif angle < deg_to_rad(maxf(release_angle, max_angle)) and PI - angle > _EPS:
			var clamped := _slerp(rest, local, max_radians / angle)
			var fade := deg_to_rad(maxf(release_angle, max_angle)) - max_radians
			var t := clampf((angle - max_radians) / maxf(fade, _EPS), 0.0, 1.0)
			target = _slerp(rest, clamped, 1.0 - t)

	_aim_local = _slerp(_aim_local, target, 1.0 - exp(-turn_speed * delta)).normalized()
	_idle = _aim_local.dot(rest) > 0.99995


## Vector3.slerp con vectores casi paralelos saca un eje sin normalizar por precisión y Godot escribe
## un error con traza en cada llamada; ya convergida la mirada eso bloqueaba el hilo 15-25 ms.
func _slerp(from: Vector3, to: Vector3, weight: float) -> Vector3:
	if from.cross(to).length_squared() < 1e-6:
		return from.lerp(to, weight)
	return from.slerp(to, weight)


## Direccion de mirada en mundo, o cero si ahora mismo no hay a donde mirar.
func _desired_world() -> Vector3:
	if "current_animation" in _body:
		var anim = _body.current_animation
		if anim == Config.ANIMATION.DEATH or anim == Config.ANIMATION.HIT:
			return Vector3.ZERO

	if not target_path.is_empty():
		var node := get_node_or_null(target_path) as Node3D
		if not node:
			return Vector3.ZERO
		var head := _skel.global_transform * _skel.get_bone_global_pose(_bones[_bones.size() - 1]).origin
		var to_target := node.global_position - head
		if to_target.length_squared() < _EPS:
			return Vector3.ZERO
		return to_target.normalized()

	var cam := get_viewport().get_camera_3d()
	if not cam:
		return Vector3.ZERO
	if cam.global_position.distance_squared_to(_body.global_position) > max_distance * max_distance:
		return Vector3.ZERO
	return -cam.global_basis.z.normalized()


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


## Reparte el giro de reposo a mirada entre los huesos de la cadena.
func _apply() -> void:
	if _idle or not _skel or not _body:
		return

	var basis_inv := _skel.global_transform.basis.inverse()
	var rest_skel := (basis_inv * (_body.global_basis * _rest_local())).normalized()
	var aim_skel := (basis_inv * (_body.global_basis * _aim_local)).normalized()

	var axis := rest_skel.cross(aim_skel)
	if axis.length_squared() < 1e-10:
		return
	axis = axis.normalized()
	var angle := rest_skel.angle_to(aim_skel)

	for i in _bones.size():
		_rotate_bone(_bones[i], Quaternion(axis, angle * _bone_weights[i]))


## Aplica una rotacion en espacio de esqueleto sobre el hueso, manteniendo su origen.
func _rotate_bone(bone: int, rot: Quaternion) -> void:
	var new_basis := Basis(rot) * _skel.get_bone_global_pose(bone).basis
	var parent := _skel.get_bone_parent(bone)
	if parent >= 0:
		new_basis = _skel.get_bone_global_pose(parent).basis.inverse() * new_basis
	_skel.set_bone_pose_rotation(bone, new_basis.get_rotation_quaternion())
