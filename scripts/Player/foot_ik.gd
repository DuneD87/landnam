class_name FootIK
extends SkeletonModifier3D

## IK de pies de dos huesos para personajes sobre cuerpos planetarios: pega cada pie al suelo real,
## lo inclina segun la normal del terreno y baja la pelvis cuando un pie no llega. El estado que
## guarda entre frames son desplazamientos escalares sobre el eje "arriba" gravitacional, no
## posiciones de mundo, asi que los rebases de FloatingOrigin no le afectan.

const Config = preload("res://scripts/config.gd")

const _SIDES := 2
const _EPS := 0.0001

@export_group("Huesos")
@export var hips_bone: String = "mixamorig_Hips"
@export var left_chain: Array[String] = ["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot"]
@export var right_chain: Array[String] = ["mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot"]

@export_group("Sondeo")
## Altura sobre el pie animado desde la que sale el rayo, y cuanto baja por debajo de el.
@export var ray_up: float = 0.6
@export var ray_down: float = 0.8
## Separacion entre el hueso del pie y la planta; sube el pie para que no se hunda en el suelo.
@export var foot_height: float = 0.12
## Capas sobre las que se apoyan los pies. En 0 hereda la mascara del propio cuerpo, que es lo
## que garantiza que el pie aterrice justo en lo que el personaje puede pisar.
@export_flags_3d_physics var collision_mask: int = 0
## Mas alla de esta distancia a la camara el IK se apaga (relevante con muchos NPCs).
@export var max_distance: float = 25.0

@export_group("Fase de zancada")
## Altura del pie animado sobre la base del cuerpo a la que empieza y termina de soltarse el IK.
## Sin esto el pie en vuelo tambien encuentra suelo debajo y la zancada se aplasta al correr.
@export var plant_lift_min: float = 0.18
@export var plant_lift_max: float = 0.40

@export_group("Limites")
@export var max_rise: float = 0.45
@export var max_drop: float = 0.45
@export var max_pelvis_drop: float = 0.35
@export_range(0.0, 90.0) var max_foot_angle: float = 45.0

@export_group("Suavizado")
@export var offset_speed: float = 12.0
@export var normal_speed: float = 10.0
@export var pelvis_speed: float = 8.0

var _skel: Skeleton3D
var _body: CharacterBody3D
var _hips: int = -1
var _chains: Array[PackedInt32Array] = []

var _foot_offset := PackedFloat32Array([0.0, 0.0])
var _foot_normal: Array[Vector3] = [Vector3.UP, Vector3.UP]
var _pelvis_offset: float = 0.0

var _anim_foot_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _has_pose: bool = false
var _idle: bool = true

var _hips_written: Vector3 = Vector3.INF
var _hips_shift: Vector3 = Vector3.ZERO


func _ready() -> void:
	_skel = get_skeleton()
	_body = _find_body()
	if not _skel or not _body:
		push_warning("FootIK '%s': necesita colgar de un Skeleton3D bajo un CharacterBody3D." % name)
		active = false
		return

	_hips = _skel.find_bone(hips_bone)
	_chains = [_resolve_chain(left_chain), _resolve_chain(right_chain)]
	for chain in _chains:
		if chain.is_empty():
			push_warning("FootIK '%s': huesos de pierna no encontrados en el esqueleto." % name)
			active = false
			return

	_foot_normal = [_get_up(), _get_up()]


## Devuelve los indices de la cadena, o vacio si falta alguno.
func _resolve_chain(names: Array[String]) -> PackedInt32Array:
	if names.size() != 3:
		return PackedInt32Array()
	var out := PackedInt32Array()
	for n in names:
		var idx := _skel.find_bone(n)
		if idx < 0:
			return PackedInt32Array()
		out.append(idx)
	return out


func _find_body() -> CharacterBody3D:
	var node := get_parent()
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


func _get_up() -> Vector3:
	if _body and _body.up_direction.length_squared() > _EPS:
		return _body.up_direction.normalized()
	return global_transform.basis.y.normalized()


## Sondea el suelo bajo cada pie y actualiza los desplazamientos suavizados. Va en fisica porque
## las consultas al espacio no son validas dentro de la fase de modificadores del esqueleto.
func _physics_process(delta: float) -> void:
	if not active or not _has_pose:
		return

	var up := _get_up()
	var enabled := _is_enabled()
	var lowest := 0.0

	for i in _SIDES:
		var target_offset := 0.0
		var target_normal := up

		var plant := _plant_weight(i, up) if enabled else 0.0
		if plant > 0.0:
			var hit := _probe(_anim_foot_world[i], up)
			if not hit.is_empty():
				var contact: Vector3 = hit["position"] + up * foot_height
				target_offset = clampf((contact - _anim_foot_world[i]).dot(up), -max_drop, max_rise) * plant
				target_normal = up.lerp(hit["normal"], plant).normalized()

		var t_pos := 1.0 - exp(-offset_speed * delta)
		var t_rot := 1.0 - exp(-normal_speed * delta)
		_foot_offset[i] = lerpf(_foot_offset[i], target_offset, t_pos)
		_foot_normal[i] = _foot_normal[i].lerp(target_normal, t_rot).normalized()
		lowest = minf(lowest, _foot_offset[i])

	var target_pelvis := clampf(lowest, -max_pelvis_drop, 0.0)
	_pelvis_offset = lerpf(_pelvis_offset, target_pelvis, 1.0 - exp(-pelvis_speed * delta))

	_idle = absf(_foot_offset[0]) < 0.002 and absf(_foot_offset[1]) < 0.002 \
			and absf(_pelvis_offset) < 0.002 \
			and _foot_normal[0].dot(up) > 0.9999 and _foot_normal[1].dot(up) > 0.9999


## Cuanto pesa el IK en este pie segun su fase de zancada: 1 apoyado, 0 en vuelo.
func _plant_weight(side: int, up: Vector3) -> float:
	var lift := (_anim_foot_world[side] - _body.global_position).dot(up)
	return 1.0 - smoothstep(plant_lift_min, plant_lift_max, lift)


## El IK solo actua con el personaje apoyado, fuera del agua y cerca de la camara.
func _is_enabled() -> bool:
	if not _body.is_on_floor():
		return false
	if "free_flight_enabled" in _body and _body.free_flight_enabled:
		return false
	if "current_animation" in _body:
		var anim = _body.current_animation
		if anim == Config.ANIMATION.SWIM or anim == Config.ANIMATION.SWIM_IDLE \
				or anim == Config.ANIMATION.DEATH:
			return false
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_squared_to(_body.global_position) > max_distance * max_distance:
		return false
	return true


func _probe(foot_world: Vector3, up: Vector3) -> Dictionary:
	var mask := collision_mask if collision_mask != 0 else _body.collision_mask
	var query := PhysicsRayQueryParameters3D.create(
		foot_world + up * ray_up,
		foot_world - up * ray_down,
		mask,
		[_body.get_rid()])
	return _skel.get_world_3d().direct_space_state.intersect_ray(query)


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


## Lee la pose animada, hunde la pelvis y resuelve ambas piernas hacia su objetivo.
func _apply() -> void:
	if not _skel or not _body:
		return

	var to_world := _skel.global_transform
	for i in _SIDES:
		_anim_foot_world[i] = to_world * _skel.get_bone_global_pose(_chains[i][2]).origin
	_has_pose = true

	if _idle:
		_hips_written = Vector3.INF
		_hips_shift = Vector3.ZERO
		return

	var to_skel := to_world.affine_inverse()
	var up_world := _get_up()
	var up_skel := (to_world.basis.inverse() * up_world).normalized()

	if _hips >= 0:
		_shift_hips(up_world, to_world)

	for i in _SIDES:
		var chain := _chains[i]
		var target := to_skel * (_anim_foot_world[i] + up_world * _foot_offset[i])
		_solve_two_bone(chain[0], chain[1], chain[2], target)
		_align_foot(chain[2], up_skel, (to_world.basis.inverse() * _foot_normal[i]).normalized())


## Hunde la pelvis por el eje gravitacional. Si el mixer no reescribio la pose (animacion sin
## pista de posicion de cadera) deshace primero su propio desplazamiento, o se acumularia.
func _shift_hips(up_world: Vector3, to_world: Transform3D) -> void:
	var base := _skel.get_bone_pose_position(_hips)
	if base.is_equal_approx(_hips_written):
		base -= _hips_shift

	_hips_shift = to_world.basis.inverse() * (up_world * _pelvis_offset)
	var parent := _skel.get_bone_parent(_hips)
	if parent >= 0:
		_hips_shift = _skel.get_bone_global_pose(parent).basis.inverse() * _hips_shift

	_hips_written = base + _hips_shift
	_skel.set_bone_pose_position(_hips, _hips_written)


## IK analitico de dos huesos por ley de cosenos. Conserva el plano de flexion de la animacion,
## asi que la rodilla apunta donde el animador la puso sin necesidad de un pole target.
func _solve_two_bone(root: int, mid: int, tip: int, target: Vector3) -> void:
	var a := _skel.get_bone_global_pose(root).origin
	var b := _skel.get_bone_global_pose(mid).origin
	var c := _skel.get_bone_global_pose(tip).origin

	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var cur_d := a.distance_to(c)
	if l1 < _EPS or l2 < _EPS or cur_d < _EPS:
		return

	var to_target := target - a
	if to_target.length_squared() < _EPS:
		return
	var d := clampf(to_target.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)

	var axis := (b - a).cross(c - a)
	if axis.length_squared() < 1e-10:
		axis = (c - a).cross(_skel.get_bone_global_pose(root).basis.x)
		if axis.length_squared() < 1e-10:
			return
	axis = axis.normalized()

	_rotate_bone(root, Quaternion(axis, _angle(l1, cur_d, l2) - _angle(l1, d, l2)))
	_rotate_bone(mid, Quaternion(axis, _angle(l1, l2, cur_d) - _angle(l1, l2, d)))

	var new_tip := _skel.get_bone_global_pose(tip).origin - a
	if new_tip.length_squared() < _EPS:
		return
	_rotate_bone(root, Quaternion(new_tip.normalized(), to_target.normalized()))


## Inclina el pie hacia la normal del suelo, con tope para que no se rompa en pendientes fuertes.
func _align_foot(foot: int, up_skel: Vector3, normal_skel: Vector3) -> void:
	var axis := up_skel.cross(normal_skel)
	if axis.length_squared() < 1e-10:
		return
	var angle := minf(up_skel.angle_to(normal_skel), deg_to_rad(max_foot_angle))
	_rotate_bone(foot, Quaternion(axis.normalized(), angle))


## Aplica una rotacion en espacio de esqueleto sobre el hueso, manteniendo su origen.
func _rotate_bone(bone: int, rot: Quaternion) -> void:
	var new_basis := Basis(rot) * _skel.get_bone_global_pose(bone).basis
	var parent := _skel.get_bone_parent(bone)
	if parent >= 0:
		new_basis = _skel.get_bone_global_pose(parent).basis.inverse() * new_basis
	_skel.set_bone_pose_rotation(bone, new_basis.get_rotation_quaternion())


## Angulo opuesto al lado 'opposite' en el triangulo de lados adj_a, adj_b y opposite.
func _angle(adj_a: float, adj_b: float, opposite: float) -> float:
	var denom := 2.0 * adj_a * adj_b
	if denom < _EPS:
		return 0.0
	return acos(clampf((adj_a * adj_a + adj_b * adj_b - opposite * opposite) / denom, -1.0, 1.0))
