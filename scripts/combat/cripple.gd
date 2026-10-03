class_name Cripple
extends RefCounted

## Andar lisiado, según cómo tiene las piernas el jugador: perdidas (BodyDamage) o rotas (una zona
## inutilizada en StatusEffects):
##   - una pierna mala y una rama (branch_01) empuñada: cojea con la rama de muleta, que pasa sola a
##     la mano que toca. Si la pierna falta, la muleta la sustituye en su mismo lado; si está rota
##     (sigue ahí), va en la mano contraria, como un bastón. Sin esa mano no hay muleta;
##   - una pierna rota sin muleta: cojea más despacio, apoyándola como puede;
##   - una pierna perdida sin muleta, o las dos malas: se arrastra.
## Lisiado no corre, no salta, no esquiva, no trepa ni pega. La cojera es la de Mixamo (pierna
## izquierda mala) o su espejo; al arrastrarse la cámara baja y el IK de pies se apaga.
##
## Animación: un canal encima de la locomoción (build), con quieto / adelante / atrás de la cojera
## (Blend3) y el arrastre (Blend2), cada uno al ritmo que hace coincidir sus pies con la velocidad.

enum Mode {NONE, LIMP, CRUTCH, CRAWL}

const CRUTCH_ID := &"branch_01"
## Lo que avanza cada clip a ritmo 1 (m/s, medido sobre el esqueleto del jugador) y a qué ritmo
## se reproduce: la velocidad del cuerpo sale de ahí.
const LIMP_CLIP_SPEED := 1.03
const LIMP_BACK_CLIP_SPEED := 0.78
const CRAWL_CLIP_SPEED := 0.36
const LIMP_RATE := 0.85
## Cojera sin muleta (pierna rota): la misma, más despacio.
const UNAIDED_LIMP_RATE := 0.6
const CRAWL_RATE := 1.2
const BLEND_SPEED := 3.0
const CRAWL_CAMERA_HEIGHT := 0.6

## Muleta: la punta se apoya bajo donde va la mano (CombatPose la pone respecto al hombro), un poco
## más afuera (m), así la rama va casi vertical y se queda con la mano; hasta que CombatPose la ha
## colocado, al costado de los pies (hacia fuera y adelante). Cuánto se levanta al dar el paso.
const CRUTCH_HAND_OUT := 0.04
const CRUTCH_OUT := 0.42
const CRUTCH_AHEAD := 0.0
const CRUTCH_LIFT := 0.12
## Andando, la muleta va con la pierna mala, como al andar con una muleta o un bastón: se levanta
## cuando ese pie despega, va por el aire lo que él y se clava por delante del costado lo que el
## cuerpo la dejará atrás hasta el paso siguiente (así va centrada en el costado). Fases (0..1 del
## clip) en que el pie de la pierna mala va por el aire en la cojera adelante y atrás; cada clip
## trae dos ciclos, y su espejo lleva el mismo ritmo con el otro pie.
const CRUTCH_STEPS_WALK: Array[Vector2] = [Vector2(0.325, 0.467), Vector2(0.833, 0.992)]
const CRUTCH_STEPS_BACK: Array[Vector2] = [Vector2(0.442, 0.533), Vector2(0.95, 0.075)]
## Si se aleja de su sitio más que esto (al girar, al cambiar de ritmo), si parado se aleja más que
## lo segundo, o si al girar se le mete entre las piernas (más cerca del centro del cuerpo que lo
## tercero), da un paso suelto que dura CRUTCH_SWING (s) y se clava CRUTCH_LEAD por delante.
const CRUTCH_MAX_LAG := 0.45
const CRUTCH_IDLE_LAG := 0.12
const CRUTCH_MIN_OUT := 0.2
const CRUTCH_SWING := 0.3
const CRUTCH_LEAD := 0.25

var combat: PlayerCombat
var mode: Mode = Mode.NONE
## Lado de la pierna mala ("Left"/"Right"): el de la cojera.
var side := "Left"
## Lado de la mano que lleva la muleta: el de la pierna si falta, el contrario si está rota.
var crutch_side := "Left"

var _weight := 0.0
var _crawl := 0.0
var _move := 0.0
var _crutch := 0.0
var _clip_side := ""
var _tip_side := ""
var _tip := Vector3.ZERO
var _tip_valid := false
var _swing_t := -1.0
var _swing_time := CRUTCH_SWING
var _gait_phase := -1.0
var _gait_node := ""
var _swing_from := Vector3.ZERO
var _swing_to := Vector3.ZERO
var _camera_height := -1.0


func _init(owner_combat: PlayerCombat) -> void:
	combat = owner_combat


func active() -> bool:
	return mode != Mode.NONE


## Monta el canal encima de [below] y devuelve el nodo que queda arriba.
static func build(tree_root: AnimationNodeBlendTree, below: StringName) -> StringName:
	for clip in ["idle", "walk", "back", "crawl"]:
		var anim := AnimationNodeAnimation.new()
		anim.animation = StringName("combat/" + ("crawl" if clip == "crawl" else "injured_idle"))
		tree_root.add_node(StringName("cr_%s_anim" % clip), anim)
	for clip in ["walk", "back", "crawl"]:
		tree_root.add_node(StringName("cr_%s_speed" % clip), AnimationNodeTimeScale.new())
		tree_root.connect_node(StringName("cr_%s_speed" % clip), 0, StringName("cr_%s_anim" % clip))
	tree_root.add_node(&"cr_limp", AnimationNodeBlend3.new())
	tree_root.connect_node(&"cr_limp", 0, &"cr_back_speed")
	tree_root.connect_node(&"cr_limp", 1, &"cr_idle_anim")
	tree_root.connect_node(&"cr_limp", 2, &"cr_walk_speed")
	tree_root.add_node(&"cr_mode", AnimationNodeBlend2.new())
	tree_root.connect_node(&"cr_mode", 0, &"cr_limp")
	tree_root.connect_node(&"cr_mode", 1, &"cr_crawl_speed")
	tree_root.add_node(&"cripple", AnimationNodeBlend2.new())
	tree_root.connect_node(&"cripple", 0, below)
	tree_root.connect_node(&"cripple", 1, &"cr_mode")
	return &"cripple"


func _decide() -> Mode:
	var bd := combat.body_damage
	if bd == null or bd.dismemberment == null or bd.dismemberment.skeleton == null or combat.is_dead():
		return Mode.NONE
	var dm := bd.dismemberment
	var skel := dm.skeleton
	var lost_l := dm.is_lost(skel.find_bone("mixamorig_LeftFoot"))
	var lost_r := dm.is_lost(skel.find_bone("mixamorig_RightFoot"))
	var status := combat.status
	var bad_l := lost_l or (status != null and status.is_zone_impaired(&"left_leg"))
	var bad_r := lost_r or (status != null and status.is_zone_impaired(&"right_leg"))
	if not bad_l and not bad_r:
		return Mode.NONE
	if bad_l and bad_r:
		return Mode.CRAWL
	side = "Left" if bad_l else "Right"
	var lost := lost_l or lost_r
	crutch_side = side if lost else ("Right" if side == "Left" else "Left")
	var data := combat.weapon()
	if data != null and data.id == CRUTCH_ID and not dm.is_lost(skel.find_bone("mixamorig_%sHand" % crutch_side)):
		return Mode.CRUTCH
	# Una pierna rota aún se apoya; sin pierna y sin muleta no hay en qué.
	return Mode.CRAWL if lost else Mode.LIMP


## Un tick, después de PlayerCombat._update_limits (pisa sus límites de movimiento).
func update(delta: float, input_dir: Vector3) -> void:
	mode = _decide()
	var player := combat.player
	var movement: Movement = player.movement
	_weight = move_toward(_weight, 1.0 if active() else 0.0, delta * BLEND_SPEED)
	_crawl = move_toward(_crawl, 1.0 if mode == Mode.CRAWL else 0.0, delta * BLEND_SPEED)
	_update_clips()
	var fwd := combat._body_forward()
	var flat_v := combat._flat(player.velocity) * combat._flat(player.velocity).dot(player.velocity)
	var forward_speed := player.velocity.dot(fwd)
	var limp_rate := UNAIDED_LIMP_RATE if mode == Mode.LIMP else LIMP_RATE
	var limp_speed := LIMP_CLIP_SPEED * limp_rate
	_move = move_toward(_move, clampf(forward_speed / limp_speed, -1.0, 1.0), delta * 4.0)
	var tree := combat._tree
	if tree != null and combat._anims_ready:
		tree.set("parameters/cripple/blend_amount", smoothstep(0.0, 1.0, _weight))
		tree.set("parameters/cr_mode/blend_amount", smoothstep(0.0, 1.0, _crawl))
		tree.set("parameters/cr_limp/blend_amount", _move)
		tree.set("parameters/cr_walk_speed/scale", limp_rate)
		tree.set("parameters/cr_back_speed/scale", limp_rate)
		# Parado, el arrastre se queda quieto donde iba.
		var crawl_speed := CRAWL_CLIP_SPEED * CRAWL_RATE
		tree.set("parameters/cr_crawl_speed/scale", CRAWL_RATE * clampf(flat_v.length() / crawl_speed, 0.0, 1.0))
	if active():
		movement.sprint_blocked = true
		movement.jump_blocked = true
		var target := CRAWL_CLIP_SPEED * CRAWL_RATE
		if mode != Mode.CRAWL:
			target = LIMP_BACK_CLIP_SPEED * limp_rate if input_dir.dot(fwd) < -0.3 else limp_speed
		var base := movement.walk_speed if movement.walking else movement.speed
		movement.speed_scale = target / maxf(base, 0.01)
	# Arrastrándose los pies no se clavan al suelo y la cámara va a ras de él.
	if combat._foot_ik != null and _crawl > 0.0:
		combat._foot_ik.influence = minf(combat._foot_ik.influence, 1.0 - _crawl)
	var cam = player.camera_controller
	if cam != null:
		if _camera_height < 0.0:
			_camera_height = cam.target_height_offset
		cam.target_height_offset = lerpf(_camera_height, CRAWL_CAMERA_HEIGHT, smoothstep(0.0, 1.0, _crawl))
	_update_crutch(delta, flat_v)


## Cojera de la pierna izquierda tal cual, o su espejo para la derecha.
func _update_clips() -> void:
	if side == _clip_side or not combat._anims_ready:
		return
	_clip_side = side
	var suffix := "" if side == "Left" else "_mirror"
	var tree_root := combat._tree.tree_root as AnimationNodeBlendTree
	for entry in [["idle", "injured_idle"], ["walk", "injured_walk"], ["back", "injured_walk_back"]]:
		(tree_root.get_node(StringName("cr_%s_anim" % entry[0])) as AnimationNodeAnimation).animation = \
			StringName("combat/%s%s" % [entry[1], suffix])


## La punta de la muleta se queda clavada en el suelo y da el paso con la pierna mala (ver
## CRUTCH_STEPS_WALK); parada, o si se ha quedado muy atrás, cuando se aleja de su sitio.
func _update_crutch(delta: float, velocity: Vector3) -> void:
	var pose := combat.pose
	_crutch = move_toward(_crutch, 1.0 if mode == Mode.CRUTCH else 0.0, delta * BLEND_SPEED)
	pose.crutch = smoothstep(0.0, 1.0, _crutch)
	# Si la muleta cambia de mano, se vuelve a apoyar en su nuevo lado.
	if crutch_side != _tip_side:
		_tip_side = crutch_side
		_tip_valid = false
		_swing_t = -1.0
	pose.crutch_side = crutch_side
	if _crutch <= 0.0:
		_tip_valid = false
		_swing_t = -1.0
		return
	var model: Node3D = combat.player.player_model
	var up := -combat.player.gravity_direction.normalized()
	var fwd := combat._body_forward()
	var out := up.cross(fwd).normalized() * (1.0 if crutch_side == "Left" else -1.0)
	var base := model.global_position
	var rest := base + out * CRUTCH_OUT + fwd * CRUTCH_AHEAD
	# La mano es del fotograma anterior: de este lado y cerca (no de antes de un salto del origen).
	var hand := pose.crutch_hand - base
	if hand.dot(out) > 0.1 and hand.length() < 1.5:
		rest = base + hand - up * hand.dot(up) + out * CRUTCH_HAND_OUT
	if not _tip_valid:
		_tip = _ground(rest, base, up)
		_tip_valid = true
	var tip := _tip
	var moving := velocity.length() > 0.1
	var gait := _gait_step() if moving else Vector2.ZERO
	if _swing_t >= 0.0:
		_swing_t = minf(_swing_t + delta / _swing_time, 1.0)
		var k := smoothstep(0.0, 1.0, _swing_t)
		tip = _swing_from.lerp(_swing_to, k)
		# De camino pasa por encima de lo que haya entre los dos apoyos (un bache, una piedra).
		tip += up * (maxf((_ground(tip, base, up) - tip).dot(up), 0.0) + sin(k * PI) * CRUTCH_LIFT)
		if _swing_t >= 1.0:
			_tip = _swing_to
			tip = _tip
			_swing_t = -1.0
	elif gait.x > 0.0:
		var lead := velocity.length() * maxf(gait.y - gait.x, 0.0) * 0.5
		_start_swing(rest + velocity * gait.x + velocity.normalized() * lead, gait.x, base, up)
	else:
		var lag := _tip - rest
		lag -= up * lag.dot(up)
		if lag.length() > (CRUTCH_MAX_LAG if moving else CRUTCH_IDLE_LAG) or (_tip - base).dot(out) < CRUTCH_MIN_OUT:
			var ahead := velocity.normalized() * CRUTCH_LEAD if moving else Vector3.ZERO
			_start_swing(rest + ahead + velocity * CRUTCH_SWING, CRUTCH_SWING, base, up)
	pose.crutch_tip = tip


func _start_swing(target: Vector3, duration: float, base: Vector3, up: Vector3) -> void:
	_swing_from = _tip
	_swing_to = _ground(target, base, up)
	_swing_time = maxf(duration, 0.15)
	_swing_t = 0.0


## Si el pie de la pierna mala acaba de despegar en la cojera que suena: (lo que irá por el aire,
## lo que dura un ciclo), en segundos. Si no, cero.
func _gait_step() -> Vector2:
	var tree := combat._tree
	if tree == null or not combat._anims_ready or absf(_move) < 0.3:
		_gait_phase = -1.0
		return Vector2.ZERO
	var back := _move < 0.0
	var node := "cr_back_anim" if back else "cr_walk_anim"
	var length := float(tree.get("parameters/%s/current_length" % node))
	if length <= 0.0:
		return Vector2.ZERO
	var phase := fposmod(float(tree.get("parameters/%s/current_position" % node)) / length, 1.0)
	var prev := _gait_phase if node == _gait_node else -1.0
	_gait_phase = phase
	_gait_node = node
	if prev < 0.0:
		return Vector2.ZERO
	for window in (CRUTCH_STEPS_BACK if back else CRUTCH_STEPS_WALK):
		if _in_window(phase, window) and not _in_window(prev, window):
			var seconds := length / LIMP_RATE
			return Vector2(fposmod(window.y - window.x, 1.0) * seconds, seconds * 0.5)
	return Vector2.ZERO


static func _in_window(phase: float, window: Vector2) -> bool:
	if window.x <= window.y:
		return phase >= window.x and phase < window.y
	return phase >= window.x or phase < window.y


## El suelo bajo [p] (mundo); sin suelo, a la altura de los pies.
func _ground(p: Vector3, base: Vector3, up: Vector3) -> Vector3:
	var player := combat.player
	var query := PhysicsRayQueryParameters3D.create(p + up * 0.6, p - up * 1.0, player.collision_mask)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position
	return p - up * (p - base).dot(up)
