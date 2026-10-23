class_name TreeLog
extends Node3D

## Trozo del tronco de un árbol talado (FallingTree): al partir el tronco tumbado, cada trozo se
## aparta un poco del corte y cae al suelo, tendido a lo largo de la pendiente. Se parte a
## hachazos en un montón de leña que se recoge (DroppedItem). Si la cámara se aleja antes, se va.
##
## Cuelga de TreeFelling, bajo el terreno: sigue al planeta y al origen flotante.

const GROUP := &"tree_log"
const GRAVITY := 9.8
## Trabajo para partirlo: fijo más por metro de diámetro del trozo.
const WORK := 8.0
const WORK_PER_METER := 60.0
## Cuánto se hunde en el suelo (fracción del radio): asienta en vez de apoyarse en una línea.
const SINK := 0.15
## Lo que sube al soltarse del tronco antes de caer (m).
const POP := 0.25
const DESPAWN_DISTANCE := 170.0

var radius := 0.2
var length := 2.0
var _wood: ItemData
var _amount := 0
var _bark: Material
var _work := 10.0
var _done := 0.0
var _up := Vector3.UP
var _body: StaticBody3D
## La caída, en el marco del padre: de dónde a dónde y cuánto dura.
var _from: Transform3D
var _to: Transform3D
var _up_local := Vector3.UP
var _t := 0.0
var _duration := 0.0
var _despawn_check := 1.0


## El trozo de [p_radius] y [p_length] (m) en [xf] (mundo, sin escala, con su eje en X), con
## [amount] de [wood] dentro y la corteza [bark]. Se aparta [push] (mundo) y cae contra [up] hasta
## el suelo; [exclude]: lo que no es suelo (el tronco del que sale).
func setup(xf: Transform3D, p_radius: float, p_length: float, bark: Material, wood: ItemData, amount: int,
		up: Vector3, push: Vector3, exclude: Array[RID]) -> void:
	name = "TreeLog"
	radius = p_radius
	length = p_length
	_bark = bark
	_wood = wood
	_amount = amount
	_up = up
	_work = WORK + WORK_PER_METER * radius * 2.0
	var mesh := MeshInstance3D.new()
	mesh.mesh = TreeFelling.log_mesh(radius, length, bark)
	mesh.position.y = -radius
	mesh.visibility_range_end = DESPAWN_DISTANCE
	add_child(mesh)
	global_transform = xf
	reset_physics_interpolation()

	var rest := _rest(xf, push, exclude)
	var to_parent := (get_parent() as Node3D).global_transform.affine_inverse()
	_from = to_parent * xf
	_to = to_parent * rest
	_up_local = (to_parent.basis * up).normalized()
	_duration = sqrt(2.0 * maxf((xf.origin - rest.origin).dot(up), 0.05) / GRAVITY) + 0.2
	add_to_group(GROUP)


## Dónde queda tendido (apartado [push]): sobre el suelo bajo sus dos puntas, con el eje a lo largo
## de él; si a una le falta, sobre el de debajo del centro y en horizontal; sin suelo, donde estaba.
func _rest(xf: Transform3D, push: Vector3, exclude: Array[RID]) -> Transform3D:
	var space := get_world_3d().direct_space_state
	var center := xf.origin + push
	var axis := xf.basis.x.normalized()
	var ends: Array[Vector3] = []
	for offset: float in [-0.4, 0.4]:
		var end := center + axis * (offset * length)
		var hit := FallingTree.ground(space, end + _up * (radius + 1.0), end - _up * 30.0, exclude)
		if not hit.is_finite():
			break
		ends.append(hit)
	var base: Vector3
	if ends.size() == 2:
		axis = (ends[1] - ends[0]).normalized()
		base = ends[0].lerp(ends[1], 0.5)
	else:
		base = FallingTree.ground(space, center + _up * (radius + 1.0), center - _up * 30.0, exclude)
		if not base.is_finite():
			return Transform3D(xf.basis, center)
		axis = (axis - _up * axis.dot(_up)).normalized()
	var up := (_up - axis * axis.dot(_up)).normalized()
	var basis := Basis(axis, up, axis.cross(up)).rotated(axis, randf_range(-0.6, 0.6))
	return Transform3D(basis, base + up * radius * (1.0 - SINK))


## Ya en el suelo y con leña dentro: hasta entonces no se parte.
func is_ready() -> bool:
	return _t >= _duration and _amount > 0


func _physics_process(delta: float) -> void:
	if _t < _duration:
		_t = minf(_t + delta, _duration)
		var s := _t / _duration
		# Sube un poco al soltarse y cae acelerando, girando hasta tenderse.
		var turn := _from.basis.get_rotation_quaternion().slerp(_to.basis.get_rotation_quaternion(), s)
		transform = Transform3D(Basis(turn), _from.origin.lerp(_to.origin, s * s) + _up_local * (POP * 4.0 * s * (1.0 - s)))
		if _t >= _duration:
			_land()
		return
	_despawn_check -= delta
	if _despawn_check <= 0.0:
		_despawn_check = 1.0
		var camera := get_viewport().get_camera_3d()
		if camera != null and camera.global_position.distance_to(global_position) > DESPAWN_DISTANCE:
			queue_free()


## En el suelo: suena y ya tiene colisión, para pisarlo o saltarlo.
func _land() -> void:
	AudioManager.play_material(&"block_impact", &"wood", global_position,
		{"volume_offset_db": -12.0, "pitch": randf_range(0.9, 1.15) * clampf(0.25 / maxf(radius, 0.05), 0.8, 1.2)})
	_body = StaticBody3D.new()
	_body.collision_layer = PhysicsLayers.WORLD
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius * 0.9
	cylinder.height = length
	shape.shape = cylinder
	shape.rotation.z = PI * 0.5
	_body.add_child(shape)
	add_child(_body)


## [hueco, punto]: lo que separa la superficie del trozo del tajo (los tramos [a]–[b] y [c]–[d]) y
## el punto de su eje más cercano; [] si aún cae. Como FallingTree.strike_reach.
func strike_reach(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Array:
	if not is_ready():
		return []
	var axis := global_basis.x.normalized() * (length * 0.5)
	var best := []
	for segment in [[a, b], [c, d]]:
		var closest := Geometry3D.get_closest_points_between_segments(segment[0], segment[1],
			global_position - axis, global_position + axis)
		var gap: float = closest[0].distance_to(closest[1]) - radius
		if best.is_empty() or gap < best[0]:
			best = [gap, closest[1]]
	return best


## Hachazo de [power] por [point] (en su eje), dado desde [chopper]: al completar el trabajo se
## parte en un montón de leña del lado de quien golpea.
func hack(point: Vector3, power: float, chopper: Node3D) -> bool:
	if not is_ready() or power <= 0.0:
		return false
	var along := global_basis.x.normalized()
	var side := along.cross(_up).normalized()
	if is_instance_valid(chopper) and side.dot(chopper.global_position - point) < 0.0:
		side = -side
	var surface := point + side * radius * 0.8 + _up * radius * 0.5
	WoodChips.burst(self, surface, (side + _up).normalized(), _up, power / 30.0)
	TreeFelling.play_sound(&"tree_chop", &"block_wood", surface,
		{"pitch": clampf(0.3 / maxf(radius, 0.05), 0.8, 1.2) * randf_range(1.05, 1.15)})
	_done += power
	if _done < _work:
		return true
	WoodChips.burst(self, global_position + _up * radius, _up, _up, 1.0)
	AudioManager.play_material(&"block_impact", &"wood", global_position,
		{"volume_offset_db": -8.0, "pitch": randf_range(1.1, 1.3)})
	if _wood != null:
		var exclude: Array[RID] = []
		if _body != null:
			exclude.append(_body.get_rid())
		DroppedItem.spawn_at(self, _wood, _amount, global_position + side * radius * 0.5 + _up * 0.5, -_up,
			pile(_amount, radius, _bark), exclude)
	_amount = 0
	queue_free()
	return true


## Montón de [amount] leños (uno, dos juntos, o dos y uno encima) de un tronco de [trunk_radius],
## con su corteza [bark].
static func pile(amount: int, trunk_radius: float, bark: Material) -> Node3D:
	var root := Node3D.new()
	var piece_radius := clampf(trunk_radius * 0.45, 0.06, 0.15)
	var mesh := TreeFelling.log_mesh(piece_radius, 0.75, bark)
	var spots := [Vector3(0.0, 0.0, -piece_radius), Vector3(0.0, 0.0, piece_radius),
		Vector3(0.0, piece_radius * 1.7, 0.0)]
	if amount == 1:
		spots = [Vector3.ZERO]
	for i in mini(amount, spots.size()):
		var piece := MeshInstance3D.new()
		piece.mesh = mesh
		piece.position = spots[i]
		piece.rotation.y = randf_range(-0.12, 0.12)
		root.add_child(piece)
	return root
