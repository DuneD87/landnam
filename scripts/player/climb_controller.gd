class_name ClimbController
extends Node

## Escalada del jugador. Al empujar contra una pared que no se puede andar (más empinada que el
## floor_max_angle del cuerpo) se agarra y trepa: sin gravedad, con la cápsula pegada a la pared por
## la física normal (move_and_slide en modo flotante) y la animación de trepar. Cuando la pared se
## acaba por encima de la cabeza corona con climb_top, que empieza donde está el personaje y acaba de
## pie en el suelo que haya donde termina el clip (no se casa con el borde). Gasta aguante; si se
## acaba, se suelta y cae.
##
##   Empujar contra la pared   agarrarse (andando, tras un instante; saltando, al momento)
##   Adelante / atrás          subir / bajar
##   Saltar                    soltarse
##
## Como al correr, la animación tiene que casar con el cuerpo: se reproduce al ritmo que hace
## coincidir sus apoyos con la velocidad, y PlayerModel se pone, inclinado con la pared, a la
## distancia a la que la animación la tiene delante. climb_top lleva su propio recorrido (1,7 m
## arriba y 1,4 m adelante): el cuerpo, y con él la cámara, sigue a su cadera.

enum Mode {NONE, CLIMB, TOP}

const Config = preload("res://scripts/config.gd")

## Lo que avanzan manos y pies apoyados a ritmo 1 (m/s) en climb_up y climb_down, y a qué distancia
## por delante de los pies tocan la pared. Como RUN_CLIP_SPEED al correr: medido sobre el
## esqueleto del jugador.
const UP_CLIP_SPEED := 0.75
const DOWN_CLIP_SPEED := 0.74
const CLIMB_WALL := 0.36
## Aguante por segundo trepando y colgado quieto.
const CLIMB_DRAIN := 5.0
const HANG_DRAIN := 2.5
## Más tumbada que esto (grados desde arriba) ya no es pared sino techo.
const MAX_WALL_ANGLE := 110.0
## Andando hay que empujar este tiempo contra la pared para agarrarse (rozarla no basta), y de
## frente: el input contra la pared (coseno) al menos PUSH_DOT.
const GRAB_DELAY := 0.2
const PUSH_DOT := 0.6
## Tras soltarse, segundos sin volver a agarrarse.
const REGRAB_COOLDOWN := 0.5
## Velocidad (m/s) con la que la cápsula se aprieta contra la pared para no despegarse.
const STICK_SPEED := 1.0
## Ticks seguidos sin tocar pared que se aguantan antes de soltarse (un saliente, un hueco).
const LOST_WALL_TICKS := 4
## Rapidez (1/s) con la que la normal de la pared sigue a la que se toca y el cuerpo se gira a ella.
const WALL_SMOOTH := 10.0
const TURN_SPEED := 12.0
## Fundidos (s): al agarrarse o pasar a coronar (y entre subir y bajar), y al volver a la locomoción.
const BLEND_IN := 0.25
const BLEND_OUT := 0.3
## Muestras por segundo del recorrido de la cadera al coronar.
const PATH_FPS := 30.0

var player: PlayerController
var mode: Mode = Mode.NONE

## Pesos del canal: escalada sobre la locomoción, coronar sobre los ciclos y bajar sobre subir.
var _w := 0.0
var _top_w := 0.0
var _dir_w := 0.0
## Fundido de la transición en curso (agarrarse o pasar a coronar), de 0 a 1, y lo que se veía al
## empezarla (PlayerModel en mundo).
var _blend := 1.0
var _from := Transform3D.IDENTITY
## PlayerModel respecto al cuerpo en el último tick: de ahí se funde a la locomoción al soltarse.
var _local := Transform3D.IDENTITY
## Trepando: normal de la pared (suavizada), un punto de contacto y ticks sin tocarla.
var _normal := Vector3.UP
var _contact := Vector3.ZERO
var _lost := 0
var _push_time := 0.0
var _cooldown := 0.0
## Tras soltarse, no se vuelve a agarrar hasta dejar de empujar (o tocar suelo): seguir pulsando
## adelante al saltar de la pared no debe devolverlo a ella.
var _await_release := false

## Coronando: instante del clip, su duración, dónde acaba de pie (marco del clip, en mundo) y la
## diferencia entre el cuerpo y su recorrido al empezar (se funde a cero).
var _top_t := 0.0
var _top_length := 0.0
var _top_frame := Transform3D.IDENTITY
var _top_offset := Vector3.ZERO
## Cadera de climb_top en el marco de PlayerModel, muestreada del clip.
var _hips_path := PackedVector3Array()

## El arma va escondida mientras las manos están en la pared.
var _weapon: Node3D = null


func setup(owner_player: PlayerController) -> void:
	player = owner_player
	name = "Climb"


func is_active() -> bool:
	return mode != Mode.NONE


## PlayerModel lo coloca la escalada (también mientras se funde de vuelta a la locomoción).
func holds_model() -> bool:
	return mode != Mode.NONE or _w > 0.0


## Monta el canal encima de [below] y devuelve el nodo que queda arriba.
static func build(tree_root: AnimationNodeBlendTree, below: StringName) -> StringName:
	for clip in ["up", "down", "top"]:
		var anim := AnimationNodeAnimation.new()
		anim.animation = StringName("combat/climb_" + clip)
		tree_root.add_node(StringName("cl_%s_anim" % clip), anim)
		tree_root.add_node(StringName("cl_%s_speed" % clip), AnimationNodeTimeScale.new())
	# Coronar empieza siempre desde el principio (el clip se queda en su último fotograma).
	tree_root.add_node(&"cl_top_seek", AnimationNodeTimeSeek.new())
	tree_root.connect_node(&"cl_top_seek", 0, &"cl_top_anim")
	tree_root.connect_node(&"cl_top_speed", 0, &"cl_top_seek")
	tree_root.connect_node(&"cl_up_speed", 0, &"cl_up_anim")
	tree_root.connect_node(&"cl_down_speed", 0, &"cl_down_anim")
	tree_root.add_node(&"cl_dir", AnimationNodeBlend2.new())
	tree_root.connect_node(&"cl_dir", 0, &"cl_up_speed")
	tree_root.connect_node(&"cl_dir", 1, &"cl_down_speed")
	tree_root.add_node(&"cl_mode", AnimationNodeBlend2.new())
	tree_root.connect_node(&"cl_mode", 0, &"cl_dir")
	tree_root.connect_node(&"cl_mode", 1, &"cl_top_speed")
	tree_root.add_node(&"climb", AnimationNodeBlend2.new())
	tree_root.connect_node(&"climb", 0, below)
	tree_root.connect_node(&"climb", 1, &"cl_mode")
	return &"climb"


## Un tick, dentro del movimiento normal y antes de él. Devuelve true si la escalada lleva el
## cuerpo en este tick (el movimiento normal no debe tocarlo).
func physics_update(delta: float) -> bool:
	_cooldown = maxf(0.0, _cooldown - delta)
	if mode == Mode.NONE and not _try_start(delta):
		_fade_out(delta)
		return false
	_blend = minf(1.0, _blend + delta / BLEND_IN)
	_w = move_toward(_w, 1.0, delta / BLEND_IN)
	match mode:
		Mode.CLIMB:
			_update_climb(delta)
		Mode.TOP:
			_update_top(delta)
	_apply_tree()
	player.current_animation = Config.ANIMATION.IDLE
	return true


## Fuera de la escalada al instante (cargar partida, vuelo libre).
func cancel() -> void:
	if mode != Mode.NONE:
		_end()
	_w = 0.0
	_cooldown = 0.0
	player.player_model.transform = Transform3D.IDENTITY
	_apply_tree()


## Tras un rebase de FloatingOrigin: los puntos guardados en mundo se mueven con él.
func shift_origin(offset: Vector3) -> void:
	_from.origin -= offset
	_contact -= offset
	_top_frame.origin -= offset


# ---------------------------------------------------------------------------------------------
# Agarrarse y soltarse


## Empujando contra una pared a la que se puede agarrar, que sigue por encima de la cabeza (una
## más baja se salta), empieza a trepar.
func _try_start(delta: float) -> bool:
	var movement := player.movement
	var combat := player.combat
	if _cooldown > 0.0 or combat.is_busy() or combat.cripple.active() or movement.is_swimming \
			or combat.stamina.exhausted or combat.stamina.stamina <= 0.0 or combat.status.blocks(&"climb"):
		_push_time = 0.0
		return false
	var up := _up()
	var input := movement.get_input_direction(player.camera, player.gravity_direction, true)
	if _await_release:
		if input.length() >= 0.5 and not player.is_on_floor():
			return false
		_await_release = false
	var wall := _wall_contact(up)
	if wall.is_empty() or input.dot(-_flat(wall.normal, up)) < PUSH_DOT:
		_push_time = 0.0
		return false
	if player.is_on_floor():
		_push_time += delta
		if _push_time < GRAB_DELAY:
			return false
	_push_time = 0.0
	if not _wall_at_head(wall.normal, wall.point, up):
		return false
	_begin()
	mode = Mode.CLIMB
	_normal = wall.normal
	_contact = wall.point
	_lost = 0
	_top_w = 0.0
	_dir_w = 0.0
	player.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	return true


## Lo común al agarrarse y al pasar a coronar: lo que se ve sale de donde está, el movimiento
## normal queda en reposo y fuera el IK, el objetivo fijado y el arma en la mano.
func _begin() -> void:
	_from = player.player_model.global_transform
	_blend = 0.0
	var movement := player.movement
	movement.velocity = Vector3.ZERO
	movement.direction = Vector3.ZERO
	movement.is_running = false
	movement.is_sprinting = false
	movement.is_jumping = false
	movement.is_falling = false
	movement.jump_velocity = 0.0
	movement.gravity_velocity = 0.0
	player.velocity = Vector3.ZERO
	if player._platform_body != null and is_instance_valid(player._platform_body):
		player._platform_body._is_being_controlled = false
	player._platform_body = null
	player.combat.on_climb_start()
	_set_body_ik(false)
	var weapon := player.combat.weapon_node()
	if weapon != null and weapon != _weapon:
		_weapon = weapon
		_weapon.visible = false


## Vuelve al movimiento normal.
func _end() -> void:
	mode = Mode.NONE
	_cooldown = REGRAB_COOLDOWN
	_local = player.player_model.transform
	player.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	var movement := player.movement
	movement.velocity = Vector3.ZERO
	movement.direction = Vector3.ZERO
	movement.gravity_velocity = 0.0
	player.velocity = Vector3.ZERO
	_set_body_ik(true)
	if is_instance_valid(_weapon):
		_weapon.visible = true
	_weapon = null


## Se suelta (saltar, sin aguante, sin pared, al agua o por un golpe) y cae.
func _let_go() -> void:
	_end()
	_await_release = true


## IK de pies y mirada: fuera en la pared (los pies buscarían el suelo y la cabeza, la cámara).
## Al volver, el combate sube el de pies poco a poco.
func _set_body_ik(on: bool) -> void:
	var foot: SkeletonModifier3D = player.combat._foot_ik
	if foot != null:
		foot.active = on
		if not on:
			foot.influence = 0.0
	var look: SkeletonModifier3D = player.combat._look_ik
	if look != null:
		look.active = on


# ---------------------------------------------------------------------------------------------
# Trepar


func _update_climb(delta: float) -> void:
	var combat := player.combat
	if combat.is_busy() or combat.cripple.active() or player.movement.is_swimming \
			or Input.is_action_just_pressed(&"jump"):
		_let_go()
		return
	var up := _up()
	var axis := Input.get_axis(&"move_back", &"move_forward")
	var want := signf(axis) if absf(axis) > 0.2 else 0.0
	# Por encima de la cabeza se acaba la pared: a coronar, si arriba hay dónde ponerse de pie (si
	# no, no se sube más).
	if want > 0.0 and not _wall_at_head(_normal, _contact, up):
		if _start_top(up):
			_update_top(0.0)
			return
		want = 0.0
	if not combat.stamina.drain(CLIMB_DRAIN if want != 0.0 else HANG_DRAIN, delta):
		_let_go()
		return

	var speed := player.movement.walk_speed
	var t_up := (up - _normal * up.dot(_normal)).normalized()
	player.velocity = t_up * want * speed - _normal * STICK_SPEED
	player.move_and_slide()
	# Moviéndose, tocar algo que se puede andar es haber llegado (abajo, o arriba si la pared se
	# tumba). Al agarrarse desde el suelo aún lo roza: no cuenta hasta acabar el fundido.
	if want != 0.0 and _blend >= 1.0 and _touches_floor(up):
		_end()
		return
	var wall := _wall_contact(up)
	if wall.is_empty():
		_lost += 1
		if _lost > LOST_WALL_TICKS:
			_let_go()
			return
	else:
		_lost = 0
		_normal = _normal.slerp(wall.normal, 1.0 - exp(-WALL_SMOOTH * delta)).normalized()
		_contact = wall.point

	t_up = (up - _normal * up.dot(_normal)).normalized()
	_face(-_flat(_normal, up), up, delta)
	# PlayerModel inclinado con la pared y a CLIMB_WALL de ella (la cápsula se queda a su radio).
	var gap := (player.global_position - _contact).dot(_normal)
	_set_frame(Transform3D(Basis(t_up.cross(-_normal).normalized(), t_up, -_normal),
		player.global_position + _normal * (CLIMB_WALL - gap)))

	if want != 0.0:
		_dir_w = move_toward(_dir_w, 1.0 if want < 0.0 else 0.0, delta / BLEND_IN)
	var tree := player.animation_controller.animation_tree
	if tree != null and combat._anims_ready:
		tree.set(&"parameters/cl_up_speed/scale", speed / UP_CLIP_SPEED if want > 0.0 else 0.0)
		tree.set(&"parameters/cl_down_speed/scale", speed / DOWN_CLIP_SPEED if want < 0.0 else 0.0)


## La pared que ha tocado el último move_and_slide: {normal (media) y point (un punto de ella)}, o
## vacío si no ha tocado ninguna a la que agarrarse.
func _wall_contact(up: Vector3) -> Dictionary:
	var normal := Vector3.ZERO
	var point := Vector3.ZERO
	var count := 0
	for i in player.get_slide_collision_count():
		var collision := player.get_slide_collision(i)
		for j in collision.get_collision_count():
			var n := collision.get_normal(j)
			if _grabbable(collision.get_collider(j), n, up):
				normal += n
				point += collision.get_position(j)
				count += 1
	if count == 0:
		return {}
	return {"normal": normal.normalized(), "point": point / count}


## El último move_and_slide ha tocado algo que se puede andar.
func _touches_floor(up: Vector3) -> bool:
	for i in player.get_slide_collision_count():
		var collision := player.get_slide_collision(i)
		for j in collision.get_collision_count():
			if collision.get_normal(j).dot(up) >= cos(player.floor_max_angle):
				return true
	return false


## Una pared a la que agarrarse: ni un cuerpo que se mueve (criaturas, barcos) ni algo que se pueda
## andar o que ya sea techo.
func _grabbable(collider: Object, normal: Vector3, up: Vector3) -> bool:
	if collider is CharacterBody3D or collider is RigidBody3D:
		return false
	var angle := rad_to_deg(normal.angle_to(up))
	return angle > rad_to_deg(player.floor_max_angle) and angle < MAX_WALL_ANGLE


## La pared (de normal [normal], que pasa por [point]) sigue a la altura de la cabeza, medida a lo
## largo de ella desde los pies: vale igual para una pared vertical que para una ladera.
func _wall_at_head(normal: Vector3, point: Vector3, up: Vector3) -> bool:
	var capsule := player.collision_shape.shape as CapsuleShape3D
	var radius := capsule.radius if capsule != null else 0.45
	var t_up := (up - normal * up.dot(normal)).normalized()
	var feet := player.global_position - normal * (player.global_position - point).dot(normal)
	var head := feet + t_up * _head_height() + normal * radius
	return not _ray(head, head - normal * radius * 2.0).is_empty()


# ---------------------------------------------------------------------------------------------
# Coronar


## Corona: el clip empieza con su cadera donde está ahora la del personaje y acaba de pie en el
## suelo que haya donde termina. Si ahí no hay suelo que se pueda andar o sitio para ponerse de
## pie, no corona (devuelve false).
func _start_top(up: Vector3) -> bool:
	_sample_hips_path()
	if _hips_path.is_empty():
		return false
	var f := -_flat(_normal, up)
	var basis := Basis(up.cross(f).normalized(), up, f)
	var anchor := _hips_world() - basis * _hips_path[0]
	var h := _head_height()
	var ground := _ray(anchor + up * h, anchor - up * h)
	if ground.is_empty() or (ground.normal as Vector3).dot(up) < cos(player.floor_max_angle):
		return false
	var stand: Vector3 = ground.position
	if not _ray(stand + up * 0.05, stand + up * h).is_empty():
		return false
	_begin()
	mode = Mode.TOP
	_top_frame = Transform3D(basis, stand)
	_top_t = 0.0
	_top_offset = player.global_position - _top_body(0.0)
	var tree := player.animation_controller.animation_tree
	if tree != null and player.combat._anims_ready:
		tree.set(&"parameters/cl_top_seek/seek_request", 0.0)
		tree.set(&"parameters/cl_top_speed/scale", 1.0)
		tree.set(&"parameters/cl_up_speed/scale", 0.0)
		tree.set(&"parameters/cl_down_speed/scale", 0.0)
	return true


## Coronando el cuerpo no choca: sigue a la cadera del clip, que no se casa con el borde.
func _update_top(delta: float) -> void:
	if player.combat.is_busy():
		_let_go()
		return
	_top_t += delta
	_top_w = move_toward(_top_w, 1.0, delta / BLEND_IN)
	player.global_position = _top_body(_top_t) + _top_offset * (1.0 - smoothstep(0.0, 1.0, _blend))
	_face(_top_frame.basis.z, _top_frame.basis.y, delta)
	_set_frame(_top_frame)
	if _top_t >= _top_length:
		_end()


## El cuerpo sigue a la cadera: donde estarían los pies bajo ella si estuviera de pie.
func _top_body(t: float) -> Vector3:
	return _top_frame * (_hips_at(t) - _hips_path[_hips_path.size() - 1])


## Recorrido de la cadera en climb_top, en el marco de PlayerModel (se muestrea una vez).
func _sample_hips_path() -> void:
	if not _hips_path.is_empty():
		return
	var animator: AnimationPlayer = player.animation_controller.animator
	var path := &"combat/climb_top"
	if animator == null or not animator.has_animation(path):
		return
	var anim := animator.get_animation(path)
	var track := anim.find_track(NodePath("Armature/Skeleton3D:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	if track < 0:
		return
	var to_model := player.player_model.global_transform.affine_inverse() * _skeleton().global_transform
	_hips_path.clear()
	for i in int(ceil(anim.length * PATH_FPS)) + 1:
		_hips_path.append(to_model * anim.position_track_interpolate(track, minf(i / PATH_FPS, anim.length)))
	_top_length = anim.length


func _hips_at(t: float) -> Vector3:
	var x := clampf(t * PATH_FPS, 0.0, _hips_path.size() - 1.0)
	var i := int(x)
	return _hips_path[i].lerp(_hips_path[mini(i + 1, _hips_path.size() - 1)], x - i)


## Donde está ahora la cadera del personaje (la de la pose que se ve).
func _hips_world() -> Vector3:
	var skeleton := _skeleton()
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Hips")).origin


# ---------------------------------------------------------------------------------------------
# Visual


## Cuerpo derecho (la gravedad manda) y de cara a [f].
func _face(f: Vector3, up: Vector3, delta: float) -> void:
	if f == Vector3.ZERO:
		return
	var target := Basis(up.cross(f).normalized(), up, f)
	player.global_basis = player.global_basis.orthonormalized().slerp(target, 1.0 - exp(-TURN_SPEED * delta))


## Coloca PlayerModel en [frame] (mundo), fundido desde donde estaba al empezar la transición.
func _set_frame(frame: Transform3D) -> void:
	var seen := _from.interpolate_with(frame, smoothstep(0.0, 1.0, _blend))
	_local = player.global_transform.affine_inverse() * seen
	player.player_model.transform = _local


## Ya suelto: el canal y PlayerModel vuelven a la locomoción.
func _fade_out(delta: float) -> void:
	if _w <= 0.0:
		return
	_w = maxf(0.0, _w - delta / BLEND_OUT)
	player.player_model.transform = Transform3D.IDENTITY.interpolate_with(_local, smoothstep(0.0, 1.0, _w))
	_apply_tree()


func _apply_tree() -> void:
	var tree := player.animation_controller.animation_tree
	if tree == null or not player.combat._anims_ready:
		return
	tree.set(&"parameters/climb/blend_amount", smoothstep(0.0, 1.0, _w))
	tree.set(&"parameters/cl_mode/blend_amount", smoothstep(0.0, 1.0, _top_w))
	tree.set(&"parameters/cl_dir/blend_amount", smoothstep(0.0, 1.0, _dir_w))


# ---------------------------------------------------------------------------------------------
# Utilidades


func _up() -> Vector3:
	return -player.gravity_direction.normalized()


func _skeleton() -> Skeleton3D:
	return player.player_model.get_node("Armature/Skeleton3D")


## Altura de la cabeza: lo alto de la cápsula.
func _head_height() -> float:
	var capsule := player.collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return 1.8
	return player.collision_shape.position.y + capsule.height * 0.5


static func _flat(v: Vector3, up: Vector3) -> Vector3:
	var h := v - up * v.dot(up)
	return h.normalized() if h.length_squared() > 1e-8 else Vector3.ZERO


## Rayo contra lo que pisa el jugador, sin él y sin caras traseras (un rayo que empieza dentro de
## la roca no debe ver la cara de dentro).
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, player.collision_mask, [player.get_rid()])
	query.hit_back_faces = false
	return player.get_world_3d().direct_space_state.intersect_ray(query)
