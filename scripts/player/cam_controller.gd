extends Node
class_name CameraController

## Al entrar y salir de primera persona (el jugador esconde la cabeza y ajusta LookAtIK).
signal first_person_changed(enabled: bool)

@export var mouse_sensitivity := 0.001
@export var invert_y := false
@export var max_pitch := 1.2
@export var min_pitch := -1.2

@export var camera_distance: float = 8.0
@export var min_distance: float = 0.5
@export var max_distance: float = 15.0
@export var zoom_speed: float = 0.4
@export var target_height_offset: float = 1.5
@export var collision_mask: int = 1
@export var collision_padding: float = 0.5

@export var fp_threshold: float = 0.5
## Altura del ojo en primera persona mientras no hay pose de la que sacarlo.
@export var fp_eye_height: float = 1.7
## Primera persona: lo que se adelanta la cámara del punto entre los ojos a lo largo de la cara
## (m). En negativo se mete en la cabeza, donde girarla apenas la mueve: los golpes la giran hasta
## 70° a cada lado de la mirada y el pesado da la vuelta entera.
@export var fp_eye_forward: float = -0.1
## Primera persona, rodando: la cámara no da la vuelta con la cabeza (vería la espalda al rodar
## hacia atrás o de lado). Va por el eje del cuerpo, baja hasta fp_roll_dip metros del suelo y
## vuelve a subir, y la vista sigue siendo la del ratón, algo inclinada hacia donde rueda.
@export var fp_roll_dip: float = 0.6
## Segundos en volver a la cabeza al acabar la voltereta.
const FP_ROLL_RETURN := 0.18
## Lo más que se inclina la vista rodando: hacia delante baja (hacia atrás sube, a 0,6) y de lado
## se ladea hacia ese lado.
const FP_ROLL_PITCH := deg_to_rad(10.0)
const FP_ROLL_BANK := deg_to_rad(9.0)
## Lo que baja el ojo agachado (Locomotion), en tercera y en primera persona.
var crouch_drop: float = 0.0
@onready var camera_pivot: Node3D = $"../CameraPivot"
@onready var pitch_pivot: Node3D = $"../CameraPivot/PitchPivot"
@onready var camera: Camera3D = $"../CameraPivot/PitchPivot/Camera3D"
@onready var _skeleton: Skeleton3D = $"../PlayerModel/Armature/Skeleton3D"

## Se apaga mientras otro modo usa la rueda (colocar un blueprint); el giro de ratón sigue vivo.
var zoom_enabled := true

## Objetivo fijado (punto en mundo) o null. Mientras hay uno, la cámara lo encuadra sola y el
## ratón en horizontal sirve para cambiar de objetivo (consume_lock_swipe).
var lock_point: Variant = null
## 0..1: cámara de apuntar (sobre el hombro derecho y más cerca). La fija el combate.
var aim_target: float = 0.0
## 0..1: cierre extra del encuadre mientras se tensa.
var aim_zoom: float = 0.0
## Ajustes del encuadre de apuntar.
@export var aim_shoulder: float = 0.62
@export var aim_distance: float = 2.1
@export var aim_fov_drop: float = 16.0
var _aim: float = 0.0
var _lock_swipe: float = 0.0
var _shake: float = 0.0
var _base_fov: float = -1.0

var pitch := 0.0
var yaw := 0.0
var delta_yaw := 0.0
var delta_pitch := 0.0
var target_distance: float
var first_person := false
## La cámara de primera persona ya va pegada a la cabeza (_place_on_head); hasta entonces la
## coloca update_camera_transform.
var _on_head := false
## Al volver a tercera persona, la interpolación de la cámara se reinicia en la primera
## colocación.
var _reset_interpolation := false
## Primera persona: lo más que el ratón puede apartar la vista del frente del cuerpo (radianes),
## o INF. El jugador lo pone mientras el cuerpo no puede girar con ella (trepando, golpeando...):
## más allá, la cámara en la cabeza vería la espalda.
var fp_yaw_limit := INF
## Voltereta en primera persona: 1 mientras rueda, y baja a 0 al volver a la cabeza.
var _roll_weight := 0.0
## Dónde estaba la cámara respecto a los pies al empezar a rodar, dónde va ahora y dónde estaba
## en el último fotograma.
var _roll_start := Vector3.ZERO
var _roll_offset := Vector3.ZERO
var _roll_last := Vector3.ZERO
var _roll_x := 0.0
## Inclinación de la vista (cabeceo, ladeo), suavizada para que una voltereta encadenada no salte.
var _roll_tilt := Vector2.ZERO
var _current_up_axis: Vector3 = Vector3.UP
var _prev_platform_basis: Basis = Basis.IDENTITY
var _tracking_platform: DynamicGridBody = null

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_pivot.top_level = true
	target_distance = camera_distance
		
func reset_camera_rotation():
	camera_pivot.rotation = Vector3.ZERO
	pitch_pivot.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.position = Vector3.ZERO
	update_camera_transform()

## Sensibilidad de la escena por el multiplicador de las opciones.
func _look_sensitivity() -> float:
	return mouse_sensitivity * SettingsManager.mouse_scale


func _input(event: InputEvent):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED \
			and lock_point != null:
		_lock_swipe += -event.relative.x * _look_sensitivity()
	elif event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		delta_yaw += -event.relative.x * _look_sensitivity()
		delta_pitch += -event.relative.y * _look_sensitivity() * (-1 if invert_y != SettingsManager.invert_y else 1)
	elif event is InputEventMouseButton and event.pressed:
		if not zoom_enabled:
			return
		if Input.is_action_pressed("left_ctrl") || Input.is_action_pressed("left_shift"):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_distance = max(target_distance - zoom_speed, min_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_distance = min(target_distance + zoom_speed, max_distance)

## Ratón horizontal acumulado con un objetivo fijado (radianes); se vacía al leerlo.
func consume_lock_swipe() -> float:
	var value := _lock_swipe
	_lock_swipe = 0.0
	return value


## Sacudida de cámara (golpes). Se suma y se apaga sola.
func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 0.6)


## Con objetivo fijado, gira yaw y pitch hacia él (control proporcional: en una esfera el yaw no
## es un ángulo absoluto, así que se corrige por la diferencia que se ve cada frame).
func _track_lock_point() -> void:
	var player = get_parent()
	var up: Vector3 = _current_up_axis
	var eye: Vector3 = player.global_position + up * (target_height_offset - crouch_drop)
	var to: Vector3 = (lock_point as Vector3) - eye
	var to_h := to - up * to.dot(up)
	# El PitchPivot de la escena va girado 180°: la cámara mira hacia -Z del pivote de yaw.
	var cur := -camera_pivot.global_basis.z
	cur = cur - up * cur.dot(up)
	if to_h.length_squared() > 0.01 and cur.length_squared() > 1e-6:
		to_h = to_h.normalized()
		cur = cur.normalized()
		var angle := atan2(up.dot(cur.cross(to_h)), cur.dot(to_h))
		yaw += angle * 0.18
		camera_pivot.rotation.y = yaw
	var dist := to.length()
	# Algo por encima del objetivo, más cuanto más cerca (encuadra la cabeza del oso sin
	# tapar al personaje).
	# Hasta el límite normal de la cámara: un ave fijada puede ir muy por encima.
	var desired := clampf(asin(clampf(to.normalized().dot(up), -1.0, 1.0)) - lerpf(0.32, 0.14, clampf(dist / 20.0, 0.0, 1.0)), min_pitch, max_pitch)
	pitch = lerpf(pitch, desired, 0.12)


func update_camera_rotation():
	if lock_point != null:
		_track_lock_point()
		delta_yaw = 0.0
		delta_pitch = 0.0
	if first_person and fp_yaw_limit < PI and delta_yaw != 0.0:
		delta_yaw = _limited_yaw_step(delta_yaw)
	if delta_yaw != 0.0:
		yaw += delta_yaw
		camera_pivot.rotation.y = yaw
	if delta_pitch != 0.0:
		pitch = clamp(pitch + delta_pitch, min_pitch, max_pitch)
		pitch_pivot.rotation.x = pitch

	camera_distance = lerp(camera_distance, target_distance, 0.15)

	if not first_person and camera_distance <= fp_threshold:
		_set_first_person(true)
	elif first_person and camera_distance > fp_threshold + 0.5:
		_set_first_person(false)

	update_camera_transform()
	delta_yaw = 0.0
	delta_pitch = 0.0

func update_camera_transform():
	var player = get_parent()
	var player_pos = player.global_position
	var target_up: Vector3
	if player._platform_body and is_instance_valid(player._platform_body):
		target_up = player._platform_body.global_transform.basis.y.normalized()
		var current_platform_basis: Basis = player._platform_body.global_transform.basis
		if _tracking_platform == player._platform_body:
			var prev_forward := _prev_platform_basis.z
			var curr_forward := current_platform_basis.z
			prev_forward = (prev_forward - target_up * prev_forward.dot(target_up)).normalized()
			curr_forward = (curr_forward - target_up * curr_forward.dot(target_up)).normalized()
			var cross := prev_forward.cross(curr_forward)
			var dot := prev_forward.dot(curr_forward)
			var yaw_delta := atan2(cross.dot(target_up), dot)
			yaw += yaw_delta
		_tracking_platform = player._platform_body
		_prev_platform_basis = current_platform_basis
	else:
		target_up = -player.gravity_direction.normalized()

	_current_up_axis = _current_up_axis.slerp(target_up, 0.01)
	var up_axis = _current_up_axis
		
	camera_pivot.global_position = player_pos
	camera_pivot.global_transform.basis = Basis(up_axis, yaw)

	var current_up = camera_pivot.global_transform.basis.y
	if current_up.dot(up_axis) < 0.999:
		var align_axis = current_up.cross(up_axis)
		if align_axis.length() > 0.001:
			var align_angle = acos(clamp(current_up.dot(up_axis), -1.0, 1.0))
			camera_pivot.global_transform.basis = Basis(align_axis.normalized(), align_angle) * camera_pivot.global_transform.basis

	pitch_pivot.rotation.x = -pitch

	_aim = move_toward(_aim, aim_target, 0.08)
	var aim_ease := _aim * _aim * (3.0 - 2.0 * _aim)
	if _base_fov < 0.0:
		_base_fov = camera.fov
	camera.fov = _base_fov - aim_fov_drop * aim_ease * (0.55 + 0.45 * aim_zoom)
	_shake = maxf(0.0, _shake - 0.02)

	if first_person:
		if not _on_head:
			var fp_forward = pitch_pivot.global_transform.basis * Vector3.BACK
			camera.global_position = player_pos + up_axis * (fp_eye_height - crouch_drop)
			camera.look_at(camera.global_position + fp_forward, up_axis)
	else:
		var orbit_dir = -pitch_pivot.global_transform.basis.z
		var target_pos = player_pos + up_axis * (target_height_offset - crouch_drop)
		# Apuntando: el encuadre se corre al hombro derecho y se acerca.
		if aim_ease > 0.0:
			var right: Vector3 = camera.global_transform.basis.x
			target_pos += right * aim_shoulder * aim_ease + up_axis * 0.1 * aim_ease
		var distance := lerpf(camera_distance, minf(camera_distance, aim_distance), aim_ease)
		var ideal_pos = target_pos + orbit_dir * distance
		var final_pos = adjust_for_collisions(target_pos, ideal_pos)
		if _shake > 0.0:
			var t := Time.get_ticks_msec() * 0.001
			final_pos += (camera_pivot.global_transform.basis.x * sin(t * 71.0) + up_axis * sin(t * 83.0 + 1.3)) * _shake * 0.12
		camera.global_position = final_pos
		camera.look_at(target_pos, up_axis)
		if _reset_interpolation:
			_reset_interpolation = false
			camera.reset_physics_interpolation()

## Lo que queda del giro de ratón [step] para que la vista no se aparte del frente del cuerpo más
## de fp_yaw_limit. Si ya está más lejos (el cuerpo se giró solo), puede volver pero no alejarse:
## la vista nunca se mueve sola.
func _limited_yaw_step(step: float) -> float:
	var up := _current_up_axis
	var body: Vector3 = get_parent().global_basis.z
	body -= up * body.dot(up)
	# El PitchPivot va girado 180°: la vista es -Z del pivote de yaw.
	var view := -camera_pivot.global_basis.z
	view -= up * view.dot(up)
	if body.length_squared() < 1e-6 or view.length_squared() < 1e-6:
		return step
	var gap := atan2(up.dot(body.cross(view)), body.dot(view))
	var bound := maxf(fp_yaw_limit, absf(gap))
	return clampf(gap + step, -bound, bound) - gap


## En primera persona la cámara va suelta (top_level) y sin interpolación de física: la coloca
## _place_on_head en cada fotograma, ya interpolada, y la del padre la movería por su cuenta.
func _set_first_person(enabled: bool) -> void:
	first_person = enabled
	_on_head = false
	_roll_weight = 0.0
	_roll_tilt = Vector2.ZERO
	camera.top_level = enabled
	if enabled:
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_skeleton.skeleton_updated.connect(_place_on_head)
	else:
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
		_reset_interpolation = true
		if _skeleton.skeleton_updated.is_connected(_place_on_head):
			_skeleton.skeleton_updated.disconnect(_place_on_head)
	first_person_changed.emit(enabled)


## Pega la cámara a la cabeza de la pose final, con las IK y las proporciones del cuerpo puestas:
## fuera de skeleton_updated el esqueleto ya ha vuelto a la pose de la animación. Va en cada
## fotograma y con lo que se dibuja (el jugador entre dos ticks de física, la pose de este
## fotograma), así que no se queda atrás cuando la cabeza va deprisa: en los golpes pasa de 1,8 a
## 6 m/s. Agachado ya baja la cabeza la animación: aquí no cuenta crouch_drop. El giro sigue
## siendo el del ratón.
func _place_on_head() -> void:
	var player = get_parent()
	if player.free_flight_enabled or player.appearance_rig == null:
		_on_head = false
		return
	var eye: Vector3 = player.appearance_rig.first_person_eye(fp_eye_forward)
	var head := _skeleton.find_bone(CharacterAppearanceRig.HEAD_BONE)
	if is_nan(eye.x) or head < 0:
		_on_head = false
		return
	var world := _skeleton.global_transform * (_skeleton.get_bone_global_pose(head) * eye)
	var local: Vector3 = player.global_transform.affine_inverse() * world
	var drawn: Transform3D = player.get_global_transform_interpolated()
	var position: Vector3 = drawn * local
	var forward := pitch_pivot.get_global_transform_interpolated().basis * Vector3.BACK
	var up := _current_up_axis
	if _follow_roll(player):
		var w := smoothstep(0.0, 1.0, _roll_weight)
		position = position.lerp(drawn.origin + _roll_offset, w)
		var right := forward.cross(up)
		if right.length_squared() > 1e-6:
			forward = forward.rotated(right.normalized(), _roll_tilt.x * w)
			up = up.rotated(forward.normalized(), _roll_tilt.y * w)
	_roll_last = position - drawn.origin
	camera.look_at_from_position(position, position + forward, up)
	_on_head = true


## La voltereta en primera persona (ver fp_roll_dip): deja en _roll_offset dónde va la cámara
## respecto a los pies y en _roll_tilt cuánto se inclina la vista. Mientras rueda, el jugador no
## enseña el cuerpo a la cámara. Devuelve false si ni rueda ni vuelve aún a la cabeza.
func _follow_roll(player: PlayerController) -> bool:
	var delta := get_process_delta_time()
	var x := player.combat.roll_progress() if player.combat != null else -1.0
	var tilt := Vector2.ZERO
	if x >= 0.0:
		if _roll_weight < 1.0 or x < _roll_x:
			# Empieza (o encadena otra voltereta) desde donde está la cámara ahora.
			_roll_start = _roll_last
			player.hide_body_in_first_person(true)
		_roll_weight = 1.0
		_roll_x = x
		var up := _current_up_axis
		var stand := _roll_start.dot(up)
		var down := smoothstep(0.05, 0.4, x) * (1.0 - smoothstep(0.55, 0.92, x))
		_roll_offset = (_roll_start - up * stand) * (1.0 - smoothstep(0.0, 0.3, x)) \
				+ up * lerpf(stand, fp_roll_dip, down)
		# El PitchPivot va girado 180°: la vista es -Z del pivote de yaw.
		var view := -camera_pivot.global_basis.z
		view -= up * view.dot(up)
		if view.length_squared() > 1e-6:
			view = view.normalized()
			var dir := player.combat.roll_direction()
			var ahead := dir.dot(view)
			tilt = Vector2(-FP_ROLL_PITCH * (ahead if ahead > 0.0 else 0.6 * ahead),
					FP_ROLL_BANK * dir.dot(view.cross(up).normalized())) * sin(PI * x)
	elif _roll_weight > 0.0:
		_roll_weight = maxf(0.0, _roll_weight - delta / FP_ROLL_RETURN)
		if _roll_weight == 0.0:
			player.hide_body_in_first_person(false)
	_roll_tilt = _roll_tilt.lerp(tilt, 1.0 - exp(-20.0 * delta))
	return _roll_weight > 0.0


func adjust_for_collisions(target_pos: Vector3, ideal_pos: Vector3) -> Vector3:
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		target_pos,
		ideal_pos,
		collision_mask
	)
	var result = space_state.intersect_ray(query)
	if result:
		return result.position + (target_pos - result.position).normalized() * collision_padding
	return ideal_pos

func toggle_mouse_capture():
	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		else Input.MOUSE_MODE_CAPTURED
	)
