class_name Cripple
extends RefCounted

## Andar lisiado, según los miembros que le quedan al jugador (BodyDamage):
##   - le falta una pierna y lleva una rama (branch_01) empuñada, con la mano de ese lado: cojea
##     con la rama de muleta en el lado de la pierna que falta;
##   - sin rama, sin la mano de ese lado o sin las dos piernas: se arrastra.
## Lisiado no corre, no salta, no esquiva ni pega. La cojera es la de Mixamo (pierna izquierda
## mala) o su espejo; al arrastrarse la cámara baja y el IK de pies se apaga.
##
## Animación: un canal encima de la locomoción (build), con quieto / adelante / atrás de la cojera
## (Blend3) y el arrastre (Blend2), cada uno al ritmo que hace coincidir sus pies con la velocidad.

enum Mode {NONE, CRUTCH, CRAWL}

const CRUTCH_ID := &"branch_01"
## Lo que avanza cada clip a ritmo 1 (m/s, medido sobre el esqueleto del jugador) y a qué ritmo
## se reproduce: la velocidad del cuerpo sale de ahí.
const LIMP_CLIP_SPEED := 1.03
const LIMP_BACK_CLIP_SPEED := 0.78
const CRAWL_CLIP_SPEED := 0.36
const LIMP_RATE := 0.85
const CRAWL_RATE := 1.2
const BLEND_SPEED := 3.0
const CRAWL_CAMERA_HEIGHT := 0.6

## Muleta: dónde se apoya en reposo (m, hacia fuera del lado de la pierna que falta y adelante),
## cuánto se deja atrás antes de dar el paso, lo que dura el paso y cuánto se levanta, y dónde va
## el puño (altura y hacia fuera); la rama mide CRUTCH_REACH de la punta al puño.
const CRUTCH_OUT := 0.34
const CRUTCH_AHEAD := 0.15
const CRUTCH_STRIDE := 0.5
const CRUTCH_SWING := 0.3
const CRUTCH_LIFT := 0.12
const CRUTCH_FIST_HEIGHT := 0.86
const CRUTCH_FIST_OUT := 0.24
const CRUTCH_REACH := 0.93

var combat: PlayerCombat
var mode: Mode = Mode.NONE
## Lado de la pierna que falta ("Left"/"Right"): el de la muleta.
var side := "Left"

var _weight := 0.0
var _crawl := 0.0
var _move := 0.0
var _crutch := 0.0
var _clip_side := ""
var _tip := Vector3.ZERO
var _tip_valid := false
var _swing_t := -1.0
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
	if not lost_l and not lost_r:
		return Mode.NONE
	if lost_l and lost_r:
		return Mode.CRAWL
	side = "Left" if lost_l else "Right"
	var data := combat.weapon()
	if data != null and data.id == CRUTCH_ID and not dm.is_lost(skel.find_bone("mixamorig_%sHand" % side)):
		return Mode.CRUTCH
	return Mode.CRAWL


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
	var limp_speed := LIMP_CLIP_SPEED * LIMP_RATE
	_move = move_toward(_move, clampf(forward_speed / limp_speed, -1.0, 1.0), delta * 4.0)
	var tree := combat._tree
	if tree != null and combat._anims_ready:
		tree.set("parameters/cripple/blend_amount", smoothstep(0.0, 1.0, _weight))
		tree.set("parameters/cr_mode/blend_amount", smoothstep(0.0, 1.0, _crawl))
		tree.set("parameters/cr_limp/blend_amount", _move)
		tree.set("parameters/cr_walk_speed/scale", LIMP_RATE)
		tree.set("parameters/cr_back_speed/scale", LIMP_RATE)
		# Parado, el arrastre se queda quieto donde iba.
		var crawl_speed := CRAWL_CLIP_SPEED * CRAWL_RATE
		tree.set("parameters/cr_crawl_speed/scale", CRAWL_RATE * clampf(flat_v.length() / crawl_speed, 0.0, 1.0))
	if active():
		movement.sprint_blocked = true
		movement.jump_blocked = true
		var target := CRAWL_CLIP_SPEED * CRAWL_RATE
		if mode == Mode.CRUTCH:
			target = LIMP_BACK_CLIP_SPEED * LIMP_RATE if input_dir.dot(fwd) < -0.3 else limp_speed
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


## La punta de la muleta se queda clavada en el suelo; cuando se queda atrás (o, parado, lejos de
## su sitio) da un paso hacia donde va el cuerpo, como un pie más.
func _update_crutch(delta: float, velocity: Vector3) -> void:
	var pose := combat.pose
	_crutch = move_toward(_crutch, 1.0 if mode == Mode.CRUTCH else 0.0, delta * BLEND_SPEED)
	pose.crutch = smoothstep(0.0, 1.0, _crutch)
	pose.crutch_side = side
	if _crutch <= 0.0:
		_tip_valid = false
		_swing_t = -1.0
		return
	var model: Node3D = combat.player.player_model
	var up := -combat.player.gravity_direction.normalized()
	var fwd := combat._body_forward()
	var out := up.cross(fwd).normalized() * (1.0 if side == "Left" else -1.0)
	var base := model.global_position
	var rest := base + out * CRUTCH_OUT + fwd * CRUTCH_AHEAD
	if not _tip_valid:
		_tip = _ground(rest, base, up)
		_tip_valid = true
	var tip := _tip
	if _swing_t >= 0.0:
		_swing_t = minf(_swing_t + delta / CRUTCH_SWING, 1.0)
		var k := smoothstep(0.0, 1.0, _swing_t)
		tip = _swing_from.lerp(_swing_to, k) + up * sin(k * PI) * CRUTCH_LIFT
		if _swing_t >= 1.0:
			_tip = _swing_to
			tip = _tip
			_swing_t = -1.0
	else:
		var lag := _tip - rest
		lag -= up * lag.dot(up)
		var moving := velocity.length() > 0.1
		if lag.length() > (CRUTCH_STRIDE * 0.5 if moving else 0.12):
			_swing_from = _tip
			var ahead := velocity.normalized() * CRUTCH_STRIDE * 0.4 if moving else Vector3.ZERO
			_swing_to = _ground(rest + ahead + velocity * CRUTCH_SWING, base, up)
			_swing_t = 0.0
	var fist_rest := base + up * CRUTCH_FIST_HEIGHT + out * CRUTCH_FIST_OUT
	var axis := (fist_rest - tip).normalized()
	pose.crutch_tip = tip
	pose.crutch_fist = tip + axis * CRUTCH_REACH


## El suelo bajo [p] (mundo); sin suelo, a la altura de los pies.
func _ground(p: Vector3, base: Vector3, up: Vector3) -> Vector3:
	var player := combat.player
	var query := PhysicsRayQueryParameters3D.create(p + up * 0.6, p - up * 1.0, player.collision_mask)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position
	return p - up * (p - base).dot(up)
