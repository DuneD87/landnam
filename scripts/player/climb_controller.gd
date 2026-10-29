class_name ClimbController
extends Node

## Escalada del jugador. Al empujar contra una pared que no se puede andar (más empinada que el
## floor_max_angle del cuerpo) se agarra y trepa: sin gravedad, con la cápsula pegada a la pared por
## la física normal (move_and_slide en modo flotante) y la animación de trepar. Cuando la pared se
## acaba por encima de la cabeza corona con climb_top, que empieza donde está el personaje y acaba de
## pie arriba: donde termina el clip, o encima del muro si es más fino. Una pared más baja que la
## cabeza (pero más alta que un escalón) se sube igual, con climb_top empezado a esa altura, y si es
## del terreno, sin la E: basta con empujar contra ella (andando, tras GRAB_DELAY; saltando, al
## momento). Las construcciones y los barcos piden siempre la E. Gasta
## aguante; si se acaba, se suelta y cae. Agarrarse cayendo para la caída con su golpe, salvo los
## primeros GRAB_MARGIN metros. Los barcos (DynamicGridBody) también se trepan: lo de la escalada
## va con el casco mientras se mueve (_carry).
##
##   Empujar contra la pared   agarrarse o subirse encima (también en el aire)
##   y USAR (E)
##   Empujar contra una pared  subirse encima
##   baja (no construcciones
##   ni barcos)
##   Adelante / atrás          subir / bajar
##   Izquierda / derecha       de lado (según la cámara), si la pared sigue por ese lado
##   Saltar                    soltarse
##
## Como al correr, la animación tiene que casar con el cuerpo: se reproduce al ritmo que hace
## coincidir sus apoyos con la velocidad, y PlayerModel se pone, inclinado con la pared, a la
## distancia a la que la animación la tiene delante. climb_top lleva su propio recorrido (1,7 m
## arriba y 1,4 m adelante): el cuerpo, y con él la cámara, sigue a su cadera, y su marco se corre
## poco a poco lo que el borde no casa con él.

enum Mode {NONE, CLIMB, TOP}

## Lo que avanza a ritmo 1 (m/s) la mano que agarra en climb_up, climb_down y climb_left/right, y a
## qué distancia por delante de los pies tocan la pared. Como RUN_CLIP_SPEED al correr: medido
## sobre el esqueleto del jugador.
const UP_CLIP_SPEED := 0.76
const DOWN_CLIP_SPEED := 0.76
const SIDE_CLIP_SPEED := 0.46
const CLIMB_WALL := 0.36
## Aguante por segundo trepando y colgado quieto.
const CLIMB_DRAIN := 5.0
const HANG_DRAIN := 2.5
## Más tumbada que esto (grados desde arriba) ya no es pared sino techo.
const MAX_WALL_ANGLE := 110.0
## Para agarrarse hay que empujar de frente contra la pared: el input contra ella (coseno) al menos
## PUSH_DOT.
const PUSH_DOT := 0.6
## Una pared baja (no una construcción ni un barco) se sube sola empujando de frente contra ella
## este tiempo (s) andando: rozarla no basta. Saltando contra ella, al momento.
const GRAB_DELAY := 0.2
## Agarrarse cayendo cobra el golpe de aterrizar, pero los primeros GRAB_MARGIN metros (m) de caída
## se perdonan: soltarse y volver a agarrarse un poco más abajo sale gratis.
const GRAB_MARGIN := 3.5
## Tras soltarse, segundos sin volver a agarrarse.
const REGRAB_COOLDOWN := 0.5
## Velocidad (m/s) con la que la cápsula se aprieta contra la pared para no despegarse.
const STICK_SPEED := 1.0
## Ticks seguidos sin tocar pared que se aguantan antes de soltarse (un saliente, un hueco).
const LOST_WALL_TICKS := 4
## Rapidez (1/s) con la que la normal de la pared sigue a la que se toca y el cuerpo se gira a ella.
const WALL_SMOOTH := 10.0
const TURN_SPEED := 12.0
## Fundidos (s): al agarrarse o pasar a coronar (y entre direcciones), y al volver a la locomoción.
const BLEND_IN := 0.25
const BLEND_OUT := 0.3
## Muestras por segundo del recorrido de la cadera al coronar.
const PATH_FPS := 30.0
## Dónde ponerse de pie al coronar se busca con rayos cada TOP_STEP, del borde (TOP_EDGE por dentro
## de la cara de la pared) a donde acaba el clip.
const TOP_EDGE := 0.1
const TOP_STEP := 0.1
## Coronar acaba cuando la cadera del clip ya no se aleja más que esto de donde termina: lo que
## queda del clip es estar de pie.
const TOP_SETTLE := 0.05

var player: PlayerController
var mode: Mode = Mode.NONE

## Pesos del canal: escalada sobre la locomoción, coronar sobre los ciclos, de lado sobre arriba y
## abajo, bajar sobre subir y derecha sobre izquierda.
var _w := 0.0
var _top_w := 0.0
var _axis_w := 0.0
var _dir_w := 0.0
var _side_w := 0.0
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
var _cooldown := 0.0
## USAR ha pedido agarrarse (request_grab): se agarra en el próximo tick.
var _grab_requested := false
## Lo que lleva empujando contra una pared baja (GRAB_DELAY).
var _push_time := 0.0
## El barco al que se trepa (null en una pared fija) y dónde estaba en el último tick: lo que la
## escalada guarda en mundo se mueve con él.
var _carrier: DynamicGridBody = null
var _carrier_xform := Transform3D.IDENTITY

## Coronando: instante del clip, cuándo acaba, dónde acaba de pie (marco del clip, en mundo) y la
## diferencia entre el cuerpo y su recorrido al empezar (se funde a cero).
var _top_t := 0.0
var _top_end := 0.0
var _top_frame := Transform3D.IDENTITY
var _top_offset := Vector3.ZERO
## Lo que el marco del clip está corrido al empezar (de frente y de alto) respecto a _top_frame,
## para que su cadera salga de la del personaje, y dónde está esa cadera en el clip.
var _top_ahead := Vector3.ZERO
var _top_rise := Vector3.ZERO
var _top_from := Vector3.ZERO
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
	for clip in ["up", "down", "left", "right", "top"]:
		var anim := AnimationNodeAnimation.new()
		anim.animation = StringName("combat/climb_" + clip)
		# Coronar empieza siempre desde el principio (el clip se queda en su último fotograma).
		AnimGraph.add_clip(tree_root, "cl_%s" % clip, anim, clip == "top")
	tree_root.add_node(&"cl_dir", AnimationNodeBlend2.new())
	tree_root.connect_node(&"cl_dir", 0, &"cl_up_speed")
	tree_root.connect_node(&"cl_dir", 1, &"cl_down_speed")
	tree_root.add_node(&"cl_side", AnimationNodeBlend2.new())
	tree_root.connect_node(&"cl_side", 0, &"cl_left_speed")
	tree_root.connect_node(&"cl_side", 1, &"cl_right_speed")
	tree_root.add_node(&"cl_axis", AnimationNodeBlend2.new())
	tree_root.connect_node(&"cl_axis", 0, &"cl_dir")
	tree_root.connect_node(&"cl_axis", 1, &"cl_side")
	tree_root.add_node(&"cl_mode", AnimationNodeBlend2.new())
	tree_root.connect_node(&"cl_mode", 0, &"cl_axis")
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
	_carry()
	_blend = minf(1.0, _blend + delta / BLEND_IN)
	_w = move_toward(_w, 1.0, delta / BLEND_IN)
	match mode:
		Mode.CLIMB:
			_update_climb(delta)
		Mode.TOP:
			_update_top(delta)
	_apply_tree()
	player.current_animation = AnimationController.Anim.IDLE
	return true


## Fuera de la escalada al instante (cargar partida, vuelo libre).
func cancel() -> void:
	# Lo pone en otro sitio: no vuelve al barco.
	_carrier = null
	if mode != Mode.NONE:
		_end()
	_grab_requested = false
	_push_time = 0.0
	_w = 0.0
	_cooldown = 0.0
	player.player_model.transform = Transform3D.IDENTITY
	_apply_tree()


## Tras un rebase de FloatingOrigin: los puntos guardados en mundo se mueven con él.
func shift_origin(offset: Vector3) -> void:
	_from.origin -= offset
	_contact -= offset
	_carrier_xform.origin -= offset
	_top_frame.origin -= offset


# ---------------------------------------------------------------------------------------------
# Agarrarse y soltarse


## USAR (E) empujando contra una pared a la que se puede agarrar: se agarra en el próximo tick y
## devuelve true (USAR no hace nada más). El tick vuelve a mirarlo todo.
func request_grab() -> bool:
	_grab_requested = mode == Mode.NONE and not _grab_wall(_up()).is_empty()
	return _grab_requested


## La pared contra la que se empuja, si ahora se puede agarrar a ella; {} si no. Sale de lo que tocó
## el último move_and_slide, así que vale también fuera del tick (al pulsar USAR).
func _grab_wall(up: Vector3) -> Dictionary:
	var movement := player.movement
	var combat := player.combat
	if _cooldown > 0.0 or combat.is_busy() or combat.cripple.active() or movement.is_swimming \
			or player.locomotion.crouching or combat.stamina.exhausted or combat.stamina.stamina <= 0.0 or combat.status.blocks(&"climb"):
		return {}
	var input := movement.get_input_direction(player.camera, player.gravity_direction, true)
	var wall := _wall_contact(up)
	if wall.is_empty() or input.dot(-_flat(wall.normal, up)) < PUSH_DOT:
		return {}
	return wall


## Si USAR lo ha pedido: a una pared que sigue por encima de la cabeza se agarra y empieza a
## trepar. Si es más baja, se sube encima (si arriba hay dónde ponerse de pie), y eso también sin
## USAR, empujando contra ella: en el suelo tras GRAB_DELAY, saltando al momento (cayendo no, que
## no se agarre a cada cornisa al pasar). Sin USAR solo el terreno: en un barco o una construcción
## empujar contra la borda o un muro no lo sube encima.
func _try_start(delta: float) -> bool:
	var requested := _grab_requested
	_grab_requested = false
	var up := _up()
	var wall := _grab_wall(up)
	if wall.is_empty() or (not requested and player.movement.is_falling):
		_push_time = 0.0
		return false
	var tall := _wall_at(wall.normal, wall.point, _along_up(wall.normal, up) * _head_height())
	if not requested:
		if tall or _is_structure(wall.collider):
			_push_time = 0.0
			return false
		if player.is_on_floor():
			_push_time += delta
			if _push_time < GRAB_DELAY:
				return false
	_push_time = 0.0
	_normal = wall.normal
	_contact = wall.point
	_carrier = _carrier_of(wall.collider)
	if _carrier != null:
		_carrier_xform = _carrier.global_transform
	if not tall:
		if _start_top(up):
			return true
		_carrier = null
		return false
	_begin()
	mode = Mode.CLIMB
	_lost = 0
	_top_w = 0.0
	_axis_w = 0.0
	_dir_w = 0.0
	_side_w = 0.0
	player.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	return true


## Lo común al agarrarse y al pasar a coronar: lo que se ve sale de donde está, el movimiento
## normal queda en reposo y fuera el IK, el objetivo fijado y el arma en la mano. Agarrarse para
## la caída (_catch_fall).
func _begin() -> void:
	if mode == Mode.NONE:
		_catch_fall()
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
	# En un barco, el movimiento normal vuelve a llevarlo con él (si no está encima, lo suelta solo).
	if is_instance_valid(_carrier):
		player._platform_body = _carrier
		player._platform_prev_xform = _carrier.global_transform
		player._platform_miss_time = 0.0
		_carrier._is_being_controlled = true
	_carrier = null


## Se suelta (saltar, sin aguante, sin pared, al agua o por un golpe) y cae.
func _let_go() -> void:
	_end()


## Agarrarse cayendo para la caída, y su golpe llega aquí: el de un aterrizaje que llega al umbral
## de daño y sigue cayendo lo que pase de GRAB_MARGIN. La aceleración sale de la propia caída
## (v² = 2·a·h). Con una pierna rota sigue agarrado: lisiado ya no se agarra otra vez.
func _catch_fall() -> void:
	var fall := player.movement.end_fall()
	if fall.x <= GRAB_MARGIN:
		return
	var safe := player.health_component.fall_damage_min_speed
	player.take_fall_hit(sqrt(safe * safe + fall.y * fall.y * (1.0 - GRAB_MARGIN / fall.x)))


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
	var t_up := _along_up(_normal, up)
	# La derecha del personaje a lo largo de la pared (mira a -_normal).
	var t_right := (-_normal).cross(t_up).normalized()
	var lateral := Input.get_axis(&"move_left", &"move_right")
	# De lado según la cámara: con ella de frente, la izquierda de la pantalla es su derecha.
	if player.camera.global_basis.x.dot(t_right) < 0.0:
		lateral = -lateral
	var vertical := Input.get_axis(&"move_back", &"move_forward")
	var move := Vector2(signf(lateral) if absf(lateral) > 0.2 else 0.0,
		signf(vertical) if absf(vertical) > 0.2 else 0.0)
	# Por encima de la cabeza se acaba la pared: a coronar, si arriba hay dónde ponerse de pie (si
	# no, no se sube más).
	if move.y > 0.0 and not _wall_at(_normal, _contact, t_up * _head_height()):
		if _start_top(up):
			_update_top(0.0)
			return
		move.y = 0.0
	# De lado, solo si la pared sigue por ese lado (donde llega el costado, a media altura): en una
	# esquina se para con el costado en ella.
	if move.x != 0.0 and not _wall_at(_normal, _contact,
			t_right * move.x * _radius() + t_up * _head_height() * 0.5):
		move.x = 0.0
	if not combat.stamina.drain(CLIMB_DRAIN if move != Vector2.ZERO else HANG_DRAIN, delta):
		_let_go()
		return

	var speed := player.movement.walk_speed
	var dir := (t_up * move.y + t_right * move.x).normalized()
	player.velocity = dir * speed - _normal * STICK_SPEED
	player.move_and_slide()
	# Subiendo o bajando, tocar algo que se puede andar es haber llegado (abajo, o arriba si la
	# pared se tumba). Al agarrarse desde el suelo aún lo roza: no cuenta hasta acabar el fundido.
	if move.y != 0.0 and _blend >= 1.0 and _touches_floor(up):
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

	t_up = _along_up(_normal, up)
	_face(-_flat(_normal, up), up, delta)
	# PlayerModel inclinado con la pared y a CLIMB_WALL de ella (la cápsula se queda a su radio).
	var gap := (player.global_position - _contact).dot(_normal)
	_set_frame(Transform3D(Basis(t_up.cross(-_normal).normalized(), t_up, -_normal),
		player.global_position + _normal * (CLIMB_WALL - gap)))

	# Cada clip en su sentido a su ritmo; en diagonal se mezclan. Quieto, se paran donde iban.
	if move != Vector2.ZERO:
		var to := delta / BLEND_IN
		_axis_w = move_toward(_axis_w, absf(move.x) / (absf(move.x) + absf(move.y)), to)
		if move.y != 0.0:
			_dir_w = move_toward(_dir_w, 1.0 if move.y < 0.0 else 0.0, to)
		if move.x != 0.0:
			_side_w = move_toward(_side_w, 1.0 if move.x > 0.0 else 0.0, to)
	var tree := player.animation_controller.animation_tree
	if tree != null and combat._anims_ready:
		tree.set(&"parameters/cl_up_speed/scale", speed / UP_CLIP_SPEED if move.y > 0.0 else 0.0)
		tree.set(&"parameters/cl_down_speed/scale", speed / DOWN_CLIP_SPEED if move.y < 0.0 else 0.0)
		tree.set(&"parameters/cl_left_speed/scale", speed / SIDE_CLIP_SPEED if move.x < 0.0 else 0.0)
		tree.set(&"parameters/cl_right_speed/scale", speed / SIDE_CLIP_SPEED if move.x > 0.0 else 0.0)


## La pared que ha tocado el último move_and_slide: {normal (media), point (un punto de ella) y
## collider (uno de los que ha tocado)}, o vacío si no ha tocado ninguna a la que agarrarse.
func _wall_contact(up: Vector3) -> Dictionary:
	var normal := Vector3.ZERO
	var point := Vector3.ZERO
	var collider: Object = null
	var count := 0
	for i in player.get_slide_collision_count():
		var collision := player.get_slide_collision(i)
		for j in collision.get_collision_count():
			var n := collision.get_normal(j)
			if _grabbable(collision.get_collider(j), n, up):
				normal += n
				point += collision.get_position(j)
				collider = collision.get_collider(j)
				count += 1
	if count == 0:
		return {}
	return {"normal": normal.normalized(), "point": point / count, "collider": collider}


## El último move_and_slide ha tocado algo que se puede andar.
func _touches_floor(up: Vector3) -> bool:
	for i in player.get_slide_collision_count():
		var collision := player.get_slide_collision(i)
		for j in collision.get_collision_count():
			if collision.get_normal(j).dot(up) >= cos(player.floor_max_angle):
				return true
	return false


## Una pared a la que agarrarse: ni un cuerpo que se mueve (criaturas, cosas sueltas) salvo un barco,
## ni algo que se pueda andar o que ya sea techo.
func _grabbable(collider: Object, normal: Vector3, up: Vector3) -> bool:
	if collider is CharacterBody3D or (collider is RigidBody3D and _carrier_of(collider) == null):
		return false
	var angle := rad_to_deg(normal.angle_to(up))
	return angle > rad_to_deg(player.floor_max_angle) and angle < MAX_WALL_ANGLE


## El barco del que es [collider] (él o su padre), o null.
static func _carrier_of(collider: Object) -> DynamicGridBody:
	if collider is DynamicGridBody:
		return collider
	var node := collider as Node
	if node != null and node.get_parent() is DynamicGridBody:
		return node.get_parent()
	return null


## [collider] es de una construcción (sus cuerpos llevan grid_id) o de un barco.
static func _is_structure(collider: Object) -> bool:
	return _carrier_of(collider) != null or (collider != null and collider.has_meta(&"grid_id"))


## Lo que el barco se ha movido desde el último tick se lo lleva todo lo que la escalada guarda en
## mundo: el cuerpo, la pared, el marco de coronar y de dónde se funde lo que se ve.
func _carry() -> void:
	if _carrier == null:
		return
	if not is_instance_valid(_carrier):
		_carrier = null
		return
	var now := _carrier.global_transform
	var moved := now * _carrier_xform.affine_inverse()
	_carrier_xform = now
	player.global_transform = moved * player.global_transform
	_contact = moved * _contact
	_normal = (moved.basis * _normal).normalized()
	_from = moved * _from
	_top_frame = moved * _top_frame
	_top_ahead = moved.basis * _top_ahead
	_top_rise = moved.basis * _top_rise
	_top_offset = moved.basis * _top_offset


## La pared (de normal [normal], que pasa por [point]) sigue en [along] desde los pies, medido a lo
## largo de ella: vale igual para una pared vertical que para una ladera.
func _wall_at(normal: Vector3, point: Vector3, along: Vector3) -> bool:
	var radius := _radius()
	var feet := player.global_position - normal * (player.global_position - point).dot(normal)
	var from := feet + along + normal * radius
	return not _ray(from, from - normal * radius * 2.0).is_empty()


# ---------------------------------------------------------------------------------------------
# Coronar


## Corona: acaba de pie arriba (_find_stand) y el clip empieza con su cadera donde está la del
## personaje. Colgado de la pared empieza por el principio; desde el suelo o en el aire, por donde su
## cadera va tan por debajo del borde como la del personaje, así que una pared baja se sube sin
## colgarse. Lo que el borde no casa con el clip (más cerca en un muro fino, más alto o más bajo) lo
## corre su marco poco a poco (_frame_at). Si arriba no hay dónde ponerse de pie, no corona
## (devuelve false).
func _start_top(up: Vector3) -> bool:
	_sample_hips_path()
	if _hips_path.is_empty():
		return false
	var f := -_flat(_normal, up)
	if f == Vector3.ZERO:
		return false
	var basis := Basis(up.cross(f).normalized(), up, f)
	var hips := _hips_world()
	var from_ground := mode == Mode.NONE
	var start := 0
	if from_ground:
		start = _ledge_start(hips, f, up)
		if start < 0:
			return false
	var anchor := hips - basis * _hips_path[start]
	var stand: Variant = _find_stand(anchor, f, up)
	if stand == null:
		return false
	_begin()
	mode = Mode.TOP
	# Desde el suelo no hay ciclo de trepar del que fundirse: el canal entra ya en coronar.
	if from_ground:
		_top_w = 1.0
	_top_frame = Transform3D(basis, stand)
	_top_t = start / PATH_FPS
	_top_from = _hips_path[start]
	var warp: Vector3 = anchor - stand
	_top_rise = up * warp.dot(up)
	_top_ahead = warp - _top_rise
	_top_offset = player.global_position - _top_body(_top_t)
	var tree := player.animation_controller.animation_tree
	if tree != null and player.combat._anims_ready:
		tree.set(&"parameters/cl_top_seek/seek_request", _top_t)
		tree.set(&"parameters/cl_top_speed/scale", 1.0)
		for clip in ["up", "down", "left", "right"]:
			tree.set("parameters/cl_%s_speed/scale" % clip, 0.0)
	return true


## Desde el suelo o en el aire, el índice del recorrido de climb_top en que su cadera está tan por
## debajo del borde como la del personaje. -1 si no hay borde o no pasa de un escalón (eso lo sube
## StepUpSystem).
func _ledge_start(hips: Vector3, f: Vector3, up: Vector3) -> int:
	var feet := player.global_position
	var head := feet + up * _head_height()
	var from := head + f * (_to_wall(head, f) + TOP_EDGE)
	var ledge := _ray(from, from - up * _head_height())
	if ledge.is_empty() or ((ledge.position as Vector3) - feet).dot(up) < _step_height():
		return -1
	var below := (hips - (ledge.position as Vector3)).dot(up)
	for i in _hips_path.size():
		if _hips_path[i].y >= below:
			return i
	return -1


## Dónde ponerse de pie al coronar. Se mira con rayos del borde hacia dentro hasta [end], donde lo
## deja el clip: el primer tramo seguido de suelo que se pueda andar, con sitio para ponerse de pie,
## más alto que un escalón sobre los pies y sin saltos de más de uno entre rayo y rayo (el suelo del
## otro lado de un muro no cuenta). Si llega a [end] (una cima ancha), ahí; si se acaba antes (un
## muro fino), en su mitad. null si no hay.
func _find_stand(end: Vector3, f: Vector3, up: Vector3) -> Variant:
	var h := _head_height()
	var step := _step_height()
	var low := player.global_position.dot(up) + step
	var depth := -_to_wall(end, f)
	var reach := maxf(depth, TOP_EDGE)
	var run: Array[Vector3] = []
	for i in int(ceil((reach - TOP_EDGE) / TOP_STEP)) + 1:
		var x := end + f * (minf(TOP_EDGE + i * TOP_STEP, reach) - depth)
		var ground := _ground_under(x, up, h, low)
		var ok := not ground.is_empty() and (ground.normal as Vector3).dot(up) >= cos(player.floor_max_angle)
		if ok:
			var at: Vector3 = ground.position
			ok = (run.is_empty() or absf((at - run.back()).dot(up)) <= step) \
				and _ray(at + up * 0.05, at + up * h).is_empty()
			if ok:
				run.append(at)
		if not ok and not run.is_empty():
			return run[floori(run.size() / 2.0)]
	return run.back() if not run.is_empty() else null


## El suelo más bajo bajo [x] (de [h] por encima a [h] por debajo) que no baje de [low]. Si hay
## varios, los de arriba son un techo o el muro sobre una ventana: desde el borde se llega al de
## abajo.
func _ground_under(x: Vector3, up: Vector3, h: float, low: float) -> Dictionary:
	var ground := {}
	var from := x + up * h
	for i in 4:
		var hit := _ray(from, x - up * h)
		if hit.is_empty() or (hit.position as Vector3).dot(up) < low:
			break
		ground = hit
		# Sigue desde dentro de lo que ha tocado: el rayo no ve sus caras de dentro.
		from = (hit.position as Vector3) - up * 0.02
	return ground


## Coronando el cuerpo no choca: sigue a la cadera del clip.
func _update_top(delta: float) -> void:
	if player.combat.is_busy():
		_let_go()
		return
	_top_t += delta
	_top_w = move_toward(_top_w, 1.0, delta / BLEND_IN)
	player.global_position = _top_body(_top_t) + _top_offset * (1.0 - smoothstep(0.0, 1.0, _blend))
	_face(_top_frame.basis.z, _top_frame.basis.y, delta)
	_set_frame(_frame_at(_top_t))
	if _top_t >= _top_end:
		_end()


## El cuerpo sigue a la cadera: donde estarían los pies bajo ella si estuviera de pie.
func _top_body(t: float) -> Vector3:
	return _frame_at(t) * (_hips_at(t) - _hips_path[_hips_path.size() - 1])


## Marco del clip en [t]: empieza donde su cadera sale de la del personaje y acaba en _top_frame.
## Se corre a la par que avanza la cadera: lo de frente mientras pasa por encima del borde (colgada
## no se mueve, así que las manos no resbalan), lo de alto mientras sube.
func _frame_at(t: float) -> Transform3D:
	var hips := _hips_at(t)
	var end := _hips_path[_hips_path.size() - 1]
	var origin := _top_frame.origin + _top_ahead * (1.0 - _progress(hips.z, _top_from.z, end.z)) \
		+ _top_rise * (1.0 - _progress(hips.y, _top_from.y, end.y))
	return Transform3D(_top_frame.basis, origin)


## Lo que va [value] de [from] a [to], de 0 a 1.
static func _progress(value: float, from: float, to: float) -> float:
	if absf(to - from) < 0.01:
		return 1.0
	return clampf((value - from) / (to - from), 0.0, 1.0)


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
	var end := _hips_path[_hips_path.size() - 1]
	var last := _hips_path.size() - 1
	while last > 0 and _hips_path[last - 1].distance_to(end) <= TOP_SETTLE:
		last -= 1
	_top_end = last / PATH_FPS


func _hips_at(t: float) -> Vector3:
	var x := clampf(t * PATH_FPS, 0.0, _hips_path.size() - 1.0)
	var i := int(x)
	return _hips_path[i].lerp(_hips_path[mini(i + 1, _hips_path.size() - 1)], x - i)


## Donde está ahora la cadera del personaje (la de la pose que se ve).
func _hips_world() -> Vector3:
	var skeleton := _skeleton()
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(HumanRig.HIPS)).origin


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
	tree.set(&"parameters/cl_axis/blend_amount", smoothstep(0.0, 1.0, _axis_w))
	tree.set(&"parameters/cl_dir/blend_amount", smoothstep(0.0, 1.0, _dir_w))
	tree.set(&"parameters/cl_side/blend_amount", smoothstep(0.0, 1.0, _side_w))


# ---------------------------------------------------------------------------------------------
# Utilidades


func _up() -> Vector3:
	return -player.gravity_direction.normalized()


func _skeleton() -> Skeleton3D:
	return player.player_model.get_node("Armature/Skeleton3D")


## Hacia arriba a lo largo de la pared de normal [normal].
static func _along_up(normal: Vector3, up: Vector3) -> Vector3:
	return (up - normal * up.dot(normal)).normalized()


func _radius() -> float:
	var capsule := player.collision_shape.shape as CapsuleShape3D
	return capsule.radius if capsule != null else 0.45


## Lo más alto que el cuerpo sube solo, sin trepar.
func _step_height() -> float:
	return player.step_up.max_step_height if player.step_up != null else 0.55


## Lo que hay de [point] a la cara de la pared yendo por [f] (negativo si ya está detrás de ella).
func _to_wall(point: Vector3, f: Vector3) -> float:
	return (point - _contact).dot(_normal) / -_normal.dot(f)


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
