class_name PlayerCombat
extends Node

## Combate del jugador, al estilo souls: todo en tiempo real y por colisión.
##
##   Clic izquierdo   golpe ligero (encadena combo) · con arco/tirachinas: tensar y soltar
##   Clic derecho     golpe pesado (mantener = cargar) · con arco/tirachinas/lanza: apuntar
##   Alt              esquivar rodando hacia donde te mueves; quieto, paso atrás
##   Q / rueda (clic) fijar objetivo; mover el ratón de lado cambia de objetivo
##
## Los golpes de hoja se resuelven barriendo la hoja real del arma (la que mueve la animación)
## contra los Hurtbox de las criaturas en la ventana activa de cada animación. Rodar apaga el
## hurtbox propio durante los fotogramas de invulnerabilidad. La estamina limita golpes,
## esquivas, carrera y tensar.
##
## Lo crea player_controller en _ready y le pasa el control del movimiento en los estados que lo
## necesitan (golpe, esquiva, tambaleo, muerte) a través de apply_motion() y update_facing().

signal state_changed(new_state: State)

enum State {IDLE, ATTACK, DODGE, AIM, STAGGER, DEAD}

const Config = preload("res://scripts/config.gd")

const RIGHT_GRIP := CombatPose.RIGHT_GRIP
const LEFT_GRIP := CombatPose.LEFT_GRIP

## Ataques sobre las dos animaciones de golpe del rig. Tiempos en segundos de la animación a
## velocidad 1 (medidos por la velocidad de la mano): hit = ventana en que la hoja hiere,
## combo = desde cuándo encadena el siguiente, end = cuándo termina, lunge = (desde, hasta,
## metros) del paso adelante, hold = dónde se congela el pesado mientras se carga.
const ATTACKS := {
	&"h": {"oneshot": "attack_horizontal", "speed": "atk_h_speed", "hit": Vector2(0.74, 1.08),
		"combo": 1.0, "end": 1.62, "lunge": Vector3(0.40, 0.95, 0.85), "hold": 0.55},
	&"v": {"oneshot": "attack_vertical", "speed": "atk_v_speed", "hit": Vector2(0.62, 0.98),
		"combo": 0.94, "end": 1.50, "lunge": Vector3(0.36, 0.88, 0.75), "hold": 0.50},
}

const ROLL_COST := 18.0
const BACKSTEP_COST := 10.0
## Duración de la voltereta procedural (RollMotion) y de la de Mixamo (1,17 s a
## ROLL_ANIM_SPEED).
const ROLL_TIME := 0.68
const ROLL_ANIM_TIME := 0.86
const ROLL_DISTANCE := 4.4
## Ventana de invulnerabilidad de la voltereta, en segundos desde que empieza.
const ROLL_IFRAMES := Vector2(0.04, 0.46)
const ROLL_ANIM_IFRAMES := Vector2(0.06, 0.56)
const BACKSTEP_TIME := 0.42
const BACKSTEP_ANIM_TIME := 0.63
const BACKSTEP_DISTANCE := 2.1
const BACKSTEP_IFRAMES := Vector2(0.03, 0.24)
const BACKSTEP_ANIM_IFRAMES := Vector2(0.04, 0.30)
const SPRINT_DRAIN := 11.0
const HOLD_DRAW_DRAIN := 6.0
## Guardia del jugador: un golpe que la supera le hace tambalearse.
const PLAYER_POISE := 24.0
const STAGGER_TIME := 0.55
const STAGGER_ANIM_TIME := 0.59
## Cuánto tiempo sirve una pulsación guardada (golpe o esquiva) mientras otra acción termina.
const INPUT_BUFFER := 0.45
const LOCK_RANGE := 28.0
const LOCK_BREAK_RANGE := 34.0
## Ratón acumulado (radianes de giro de cámara) para cambiar de objetivo fijado.
const LOCK_SWITCH_THRESHOLD := 0.09
## Penalización de puntuación de la fauna menuda (aves, conejos, peces) frente a los NPCs: con un
## oso y un gorrión en el mismo encuadre, se fija el oso.
const LOCK_SMALL_FAUNA_BIAS := 0.35
const HITSTOP_TIME := 0.075
const DEATH_SCREEN_DELAY := 1.3
const RESPAWN_DELAY := 5.0

## Animaciones de Mixamo reorientadas al jugador (tools/combat/retarget_mixamo.gd). Tiempos en
## segundos de cada animación, medidos sobre ella.
const COMBAT_LIBRARY := "res://models/player/mixamo/combat_anims.tres"
## Qué acciones usan la animación de Mixamo (true) y cuáles la procedural (false). Elegido a ojo
## en el juego: la voltereta y el arco (Pro Longbow Pack, con BowAnimRig) de Mixamo; el resto,
## las procedurales. Con el arco en false vuelve ArcheryPose.
const USE_MIXAMO := {
	&"roll": true,
	&"dodge_back": false,
	&"hit_react": false,
	&"death": false,
	&"bow": true,
	&"throw": false,
}
const ROLL_ANIM_SPEED := 1.35
const BACKSTEP_ANIM_FROM := 0.2
const BACKSTEP_ANIM_SPEED := 1.5
const HIT_ANIM_SPEED := 1.3
const DEATH_ANIM_SPEED := 1.15
## Arco con animaciones (Pro Longbow Pack, ver BowAnimRig): velocidad de sacar la flecha de la
## aljaba y encajarla (bow_draw hasta BowAnimRig.NOCK_T), y del retroceso al soltar.
const BOW_NOCK_SPEED := 1.2
const BOW_RECOIL_SPEED := 1.2
## throw: brazo listo, brazo atrás del todo y suelta.
const THROW_READY := 0.4
const THROW_COCKED := 1.15
const THROW_RELEASE := 1.33
const THROW_SPEED := 1.3
## Huesos que mueve el canal de tronco y brazos (y sus descendientes).
const UPPER_ROOT := "mixamorig_Spine"
## Arco procedural: tras soltar, cuánto se sostiene el gesto antes de ir a por otra flecha, y
## desde qué punto de la recarga se empieza al subir el arco sin flecha (la mano ya va subiendo).
const BOW_FOLLOW_THROUGH := 0.26
const BOW_RAISE_RELOAD_FROM := 0.25
## Giro del cuerpo al apuntar quieto con el arco (grados; el tronco pone el resto).
const BOW_STANCE_YAW := -50.0
const THROW_STANCE_YAW := -25.0

var player: PlayerController
var stamina: StaminaComponent
var hurtbox: Hurtbox
var hud: CombatHUD
var pose: CombatPose
var hit_react: HitReact
## Muñeco de trapo al morir (si la muerte no es la animación de Mixamo).
var ragdoll: Ragdoll
var lock_target: Node3D = null

var state: State = State.IDLE
var _t: float = 0.0

# Golpe
var _attack_id: StringName = &""
var _attack: Dictionary = {}
var _heavy: bool = false
var _charge: float = 0.0
var _combo: int = 0
var _attack_dir: Vector3 = Vector3.FORWARD
var _attack_speed: float = 1.0
var _hitstop: float = 0.0
var _sweep: MeleeSweep
var _swing_hits: int = 0
var _buffered: StringName = &""
var _buffer_age: float = 0.0

# Esquiva
var _dodge_dir: Vector3 = Vector3.FORWARD
var _dodge_roll: bool = true

# Apuntar
var _aim_held: bool = false
var _draw_held: bool = false
var _draw: float = 0.0
var _release_t: float = -1.0
var _fire_cooldown: float = 0.0
var _aim_point: Vector3 = Vector3.ZERO
var _aim_dir: Vector3 = Vector3.FORWARD
var _aim_weight: float = 0.0
var _ranged_visual: Node3D = null
var _arrow_visual: MeshInstance3D

# Tambaleo / muerte
var _knock: Vector3 = Vector3.ZERO
var _motion_h: Vector3 = Vector3.ZERO
var _death_time: float = 0.0
## Dirección y fuerza del último golpe encajado (para cómo cae al morir).
var _last_hit_push: Vector3 = Vector3.ZERO
var _respawning: bool = false

var _lock_lost_time: float = 0.0
var _lock_switch_cooldown: float = 0.0

var _skeleton: Skeleton3D
var _right_attachment: BoneAttachment3D
var _right_grip: Node3D
var _left_grip: Node3D
var _weapon_node: Node3D = null
var _foot_ik: SkeletonModifier3D
var _look_ik: SkeletonModifier3D
var _tree: AnimationTree
var _anims_ready: bool = false
## Estado de los dos canales de acción: "full" (cuerpo entero) y "upper" (tronco y brazos).
var _act := {
	"full": {"anim": &"", "time": 0.0, "speed": 1.0, "length": 0.0, "active": false, "hold_end": false},
	"upper": {"anim": &"", "time": 0.0, "speed": 1.0, "length": 0.0, "active": false, "hold_end": false,
		"weight": 0.0},
}
## Fundidos del canal de tronco y brazos (s): entrar y salir.
const UPPER_FADE_IN := 0.12
const UPPER_FADE_OUT := 0.25
## Arco: "" (sin arco en alto), "nock" (encajando), "ready" (encajada, tensa con el clic) o
## "recoil" (acaba de soltar).
var _bow_phase: StringName = &""
var _spear_released: bool = false
## Arco procedural (ArcheryPose): fases "" (bajado), "reload" (sacando y encajando flecha),
## "ready" (encajada, tensa con el clic), "release" (acaba de soltar) y "empty" (sin flechas).
var _bow_reload: float = -1.0
var _bow_release: float = -1.0
var _bow_hold: float = 0.0
## La flecha sigue encajada aunque baje el arco: al volver a subirlo no hay que sacar otra.
var _bow_nocked: bool = false
var _quiver: QuiverVisual = null
## Giro del cuerpo (grados) al apuntar con el arco quieto: de perfil al blanco.
var _stance_yaw: float = 0.0
## 0..1 llevar el arma al correr (CombatPose.carry), y a qué ritmo entra y sale (1/s).
var _carry: float = 0.0
const CARRY_BLEND_SPEED := 5.0

## Punto de reaparición cuando no hay partida guardada: donde empezó a jugar (canónico).
var _spawn_canonical: Variant = null
var _spawn_basis: Basis = Basis.IDENTITY


func setup(owner_player: PlayerController) -> void:
	player = owner_player
	name = "PlayerCombat"
	stamina = StaminaComponent.new()
	stamina.name = "Stamina"
	add_child(stamina)

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.72
	hurtbox = Hurtbox.attach(player, player, capsule, Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0)))
	hurtbox.health = player.health_component
	player.health_component.max_health = 100.0
	player.health_component.hit_received.connect(_on_hit_received)
	player.health_component.died.connect(_on_died)

	_skeleton = player.player_model.get_node("Armature/Skeleton3D")
	_right_attachment = _skeleton.get_node("RigthHandAttachment")
	_foot_ik = _skeleton.get_node_or_null("FootIK")
	_look_ik = _skeleton.get_node_or_null("LookAtIK")
	# El arma va respecto a la palma, no a un dedo (los dedos se cierran sobre el mango): la
	# coloca CombatPose al posar (right_grip_xform).
	_right_grip = Node3D.new()
	_right_grip.name = "CombatGrip"
	_right_grip.top_level = true
	_right_attachment.add_child(_right_grip)
	var left_attachment := BoneAttachment3D.new()
	left_attachment.name = "LeftHandAttachment"
	left_attachment.bone_name = "mixamorig_LeftHandMiddle2"
	_skeleton.add_child(left_attachment)
	_left_grip = Node3D.new()
	_left_grip.name = "CombatGrip"
	_left_grip.transform = LEFT_GRIP
	left_attachment.add_child(_left_grip)

	pose = CombatPose.new()
	pose.name = "CombatPose"
	pose.frame_node = player.player_model
	pose.after_pose = _place_ranged_visuals
	_skeleton.add_child(pose)
	hit_react = HitReact.new()
	hit_react.name = "HitReact"
	hit_react.chain = ["mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head"]
	hit_react.weights = [0.3, 0.3, 0.2, 0.2]
	_skeleton.add_child(hit_react)
	# El último modificador: mientras cae, manda sobre todo lo anterior.
	ragdoll = Ragdoll.new()
	ragdoll.name = "Ragdoll"
	ragdoll.frame_node = player.player_model
	ragdoll.world_mask = player.collision_mask
	ragdoll.exclude_body = player
	_skeleton.add_child(ragdoll)

	_arrow_visual = MeshInstance3D.new()
	_arrow_visual.name = "NockedArrow"
	_arrow_visual.mesh = load("res://data/items/meshes/weapons/arrow.res")
	_arrow_visual.top_level = true
	_arrow_visual.visible = false
	_arrow_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arrow_visual)

	_sweep = MeleeSweep.new()
	_sweep.exclude = [hurtbox.get_rid()]
	_setup_animation()

	hud = CombatHUD.new()
	hud.name = "CombatHUD"
	add_child(hud)
	hud.setup(self)


## Mete un escalador de tiempo entre cada animación de golpe y su one-shot, para que cada arma
## golpee a su ritmo y el pesado pueda congelarse mientras se carga.
func _setup_animation() -> void:
	_tree = player.animation_controller.animation_tree
	if _tree == null or not (_tree.tree_root is AnimationNodeBlendTree):
		return
	var tree_root := (_tree.tree_root as AnimationNodeBlendTree).duplicate(true) as AnimationNodeBlendTree
	var connections: Array = tree_root.get("node_connections")
	for id in ATTACKS:
		var info: Dictionary = ATTACKS[id]
		var oneshot := StringName(info.oneshot)
		var source := StringName()
		for i in range(0, connections.size(), 3):
			if connections[i] == oneshot and int(connections[i + 1]) == 1:
				source = connections[i + 2]
		if source == StringName() or tree_root.has_node(StringName(info.speed)):
			continue
		tree_root.add_node(StringName(info.speed), AnimationNodeTimeScale.new())
		tree_root.disconnect_node(oneshot, 1)
		tree_root.connect_node(StringName(info.speed), 0, source)
		tree_root.connect_node(oneshot, 1, StringName(info.speed))
	_setup_action_channels(tree_root)
	_tree.tree_root = tree_root


## Dos canales de acción encima de todo el árbol: "full" (voltereta, paso atrás, tambaleo,
## muerte) y "upper", filtrado al tronco y los brazos (arco, lanzamiento: las piernas siguen con
## la locomoción). Cada uno: animación → TimeSeek → TimeScale → mezcla, para poder
## reproducirla, acelerarla o arrastrarla a un instante concreto. "full" mezcla con un OneShot;
## "upper" con un Blend2 cuyo peso lleva _act_advance: un OneShot cuenta su propio tiempo desde
## que se dispara y se apaga al pasar la duración del clip aunque este vaya arrastrado (tensar y
## sostener el arco), y al cambiar de clip dentro de él se daría por acabado.
func _setup_action_channels(tree_root: AnimationNodeBlendTree) -> void:
	var animator: AnimationPlayer = player.animation_controller.animator
	if animator == null or not ResourceLoader.exists(COMBAT_LIBRARY):
		return
	if not animator.has_animation_library(&"combat"):
		animator.add_animation_library(&"combat", load(COMBAT_LIBRARY))
	var connections: Array = tree_root.get("node_connections")
	var top := StringName()
	for i in range(0, connections.size(), 3):
		if connections[i] == &"output" and int(connections[i + 1]) == 0:
			top = connections[i + 2]
	if top == StringName():
		return
	tree_root.disconnect_node(&"output", 0)
	var below := top
	for channel in ["upper", "full"]:
		var anim := AnimationNodeAnimation.new()
		anim.animation = &"combat/roll"
		var shot: AnimationNode
		if channel == "upper":
			shot = AnimationNodeBlend2.new()
		else:
			var oneshot := AnimationNodeOneShot.new()
			oneshot.fadein_time = 0.12
			oneshot.fadeout_time = 0.25
			shot = oneshot
		if channel == "upper":
			shot.filter_enabled = true
			var root_bone := _skeleton.find_bone(UPPER_ROOT)
			for b in _skeleton.get_bone_count():
				var p := b
				while p >= 0 and p != root_bone:
					p = _skeleton.get_bone_parent(p)
				if p == root_bone:
					shot.set_filter_path(NodePath("Armature/Skeleton3D:" + _skeleton.get_bone_name(b)), true)
		tree_root.add_node(StringName("act_%s_anim" % channel), anim)
		tree_root.add_node(StringName("act_%s_seek" % channel), AnimationNodeTimeSeek.new())
		tree_root.add_node(StringName("act_%s_speed" % channel), AnimationNodeTimeScale.new())
		tree_root.add_node(StringName("act_%s" % channel), shot)
		tree_root.connect_node(StringName("act_%s_seek" % channel), 0, StringName("act_%s_anim" % channel))
		tree_root.connect_node(StringName("act_%s_speed" % channel), 0, StringName("act_%s_seek" % channel))
		tree_root.connect_node(StringName("act_%s" % channel), 0, below)
		tree_root.connect_node(StringName("act_%s" % channel), 1, StringName("act_%s_speed" % channel))
		below = StringName("act_%s" % channel)
	tree_root.connect_node(&"output", 0, below)
	_anims_ready = true


## Reproduce [anim_name] (de la librería "combat") en el canal, desde [from] y a [speed].
## [hold_end] la deja congelada en su último fotograma (muerte).
func _act_play(channel: String, anim_name: StringName, speed: float, from: float = 0.0,
		hold_end: bool = false) -> void:
	if not _anims_ready:
		return
	var ch: Dictionary = _act[channel]
	var tree_root := _tree.tree_root as AnimationNodeBlendTree
	var anim_path := StringName("combat/" + String(anim_name))
	(tree_root.get_node(StringName("act_%s_anim" % channel)) as AnimationNodeAnimation).animation = anim_path
	var animator: AnimationPlayer = player.animation_controller.animator
	ch.anim = anim_name
	ch.length = animator.get_animation(anim_path).length if animator.has_animation(anim_path) else 1.0
	ch.time = from
	ch.speed = speed
	ch.active = true
	ch.hold_end = hold_end
	_tree.set("parameters/act_%s_seek/seek_request" % channel, from)
	_tree.set("parameters/act_%s_speed/scale" % channel, speed)
	if channel != "upper":
		_tree.set("parameters/act_%s/request" % channel, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Cambia la animación de un canal que ya suena sin volver a dispararlo (disparar hace un fundido
## desde lo de debajo): para encadenar clips que empiezan donde acaba el anterior. Si el canal no
## suena, la reproduce como _act_play.
func _act_switch(channel: String, anim_name: StringName, speed: float, from: float = 0.0) -> void:
	if not _anims_ready:
		return
	var ch: Dictionary = _act[channel]
	if not ch.active or (channel != "upper" and not bool(_tree.get("parameters/act_%s/active" % channel))):
		_act_play(channel, anim_name, speed, from)
		return
	var tree_root := _tree.tree_root as AnimationNodeBlendTree
	var anim_path := StringName("combat/" + String(anim_name))
	(tree_root.get_node(StringName("act_%s_anim" % channel)) as AnimationNodeAnimation).animation = anim_path
	ch.anim = anim_name
	ch.length = _clip_length(anim_name)
	ch.time = from
	ch.speed = speed
	ch.hold_end = false
	_tree.set("parameters/act_%s_seek/seek_request" % channel, from)
	_tree.set("parameters/act_%s_speed/scale" % channel, speed)


## Deja el canal quieto en [time] (tensar el arco, cargar la lanza): se arrastra, no se reproduce.
func _act_scrub(channel: String, time: float) -> void:
	if not _anims_ready:
		return
	var ch: Dictionary = _act[channel]
	ch.time = clampf(time, 0.0, ch.length)
	ch.speed = 0.0
	_tree.set("parameters/act_%s_speed/scale" % channel, 0.0)
	_tree.set("parameters/act_%s_seek/seek_request" % channel, ch.time)


func _act_set_speed(channel: String, speed: float) -> void:
	if not _anims_ready:
		return
	_act[channel].speed = speed
	_tree.set("parameters/act_%s_speed/scale" % channel, speed)


func _act_stop(channel: String) -> void:
	if not _anims_ready or not _act[channel].active:
		return
	_act[channel].active = false
	_act[channel].hold_end = false
	_tree.set("parameters/act_%s_speed/scale" % channel, 1.0)
	if channel != "upper":
		_tree.set("parameters/act_%s/request" % channel, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## Giro de la cadera (grados, marco del modelo) en [anim_name] a [time], leído de la pista.
func _anim_hips_yaw(anim_name: StringName, time: float) -> float:
	var animator: AnimationPlayer = player.animation_controller.animator
	var path := StringName("combat/" + String(anim_name))
	if not animator.has_animation(path):
		return NAN
	var anim := animator.get_animation(path)
	var track := anim.find_track(NodePath("Armature/Skeleton3D:mixamorig_Hips"), Animation.TYPE_ROTATION_3D)
	if track < 0:
		return NAN
	var local := Basis(anim.rotation_track_interpolate(track, clampf(time, 0.0, anim.length)))
	var to_model := player.player_model.global_basis.inverse() * _skeleton.global_basis
	var z := (to_model * local).orthonormalized().z
	return rad_to_deg(atan2(z.x, z.z))


func _act_time(channel: String) -> float:
	return _act[channel].time


## Lleva la cuenta del tiempo de cada canal (para sincronizar golpes, disparos e invulnerabilidad
## con la animación) y congela al final los que lo piden.
func _act_advance(delta: float) -> void:
	if _anims_ready:
		# El canal de tronco y brazos entra y sale fundiéndose (Blend2, ver _setup_action_channels).
		var up: Dictionary = _act["upper"]
		up.weight = move_toward(up.weight, 1.0 if up.active else 0.0,
			delta / (UPPER_FADE_IN if up.active else UPPER_FADE_OUT))
		_tree.set("parameters/act_upper/blend_amount", smoothstep(0.0, 1.0, up.weight))
	for channel in _act:
		var ch: Dictionary = _act[channel]
		if not ch.active:
			continue
		ch.time += delta * ch.speed
		if ch.hold_end and ch.time >= ch.length - 0.03 and ch.speed > 0.0:
			_act_scrub(channel, ch.length - 0.03)
		elif not ch.hold_end and ch.speed > 0.0 and ch.time >= ch.length:
			ch.active = false


# ---------------------------------------------------------------------------------------------
# Armas


## El arma que sujeta: el item equipado en la mano derecha (sea del lado que sea).
func weapon() -> ItemData:
	if not player.right_hand_equipped:
		return null
	return player.equiped_weapon


## Cuelga la escena del arma de la mano que toca. Las armas de combate van en metros sobre el
## marco de agarre; las herramientas antiguas traen su propia escala y cuelgan del hueso.
func attach_weapon(node: Node3D, data: ItemData) -> void:
	detach_weapon()
	_weapon_node = node
	if data.is_left_handed():
		_left_grip.add_child(node)
		_ranged_visual = node
		if data.weapon_type == ItemData.WeaponType.BOW:
			_quiver = QuiverVisual.new()
			_quiver.name = "Quiver"
			_quiver.top_level = true
			add_child(_quiver)
	elif data.scene_path.begins_with("res://scenes/items/weapons/combat/"):
		_right_grip.add_child(node)
		pose.grip_right = true
	else:
		_right_attachment.add_child(node)
	if state == State.AIM and _release_t < 0.0:
		_end_aim(true)


## Suelta el arma de la mano y la devuelve (el que llama la libera).
func detach_weapon() -> Node3D:
	var node := _weapon_node
	_weapon_node = null
	_ranged_visual = null
	pose.grip_right = false
	_arrow_visual.visible = false
	_bow_nocked = false
	if _quiver != null:
		_quiver.queue_free()
		_quiver = null
	if node != null and is_instance_valid(node) and node.get_parent() != null:
		node.get_parent().remove_child(node)
	if state == State.ATTACK:
		_end_attack()
	return node


func weapon_node() -> Node3D:
	return _weapon_node


func _ammo_item() -> ItemData:
	var data := weapon()
	if data == null or data.ammo_id == &"":
		return null
	return Config.get_item(data.ammo_id)


func ammo_count() -> int:
	var data := weapon()
	if data == null:
		return 0
	if data.throwable and data.ammo_id == &"":
		return 1 + player.inventory.get_item_count(data)
	var ammo := _ammo_item()
	return player.inventory.get_item_count(ammo) if ammo != null else 0


# ---------------------------------------------------------------------------------------------
# Entrada


## Devuelve true si el evento es del combate (y ya no debe hacer otra cosa).
func handle_input(event: InputEvent) -> bool:
	if state == State.DEAD or _respawning:
		return event is InputEventMouseButton or event.is_action("dodge") or event.is_action("lock_on")
	if player.inventory_ui.visible or player.building_system.build_mode:
		return false
	if event.is_action_pressed("lock_on"):
		if lock_target != null:
			release_lock()
		else:
			lock_on()
		return true
	if event.is_action_pressed("dodge"):
		_request(&"dodge")
		return true
	var data := weapon()
	if data == null:
		return false
	if data.is_ranged():
		return _ranged_input(event, data)
	if not data.is_melee():
		return false
	var is_tool := data.category == ItemData.Category.TOOL
	if event.is_action_pressed("attack_1"):
		if is_tool and not _enemy_near():
			return false
		_request(&"light")
		return true
	if event.is_action_pressed("attack_2"):
		if is_tool and not _enemy_near():
			return false
		_request(&"heavy")
		return true
	return false


func _ranged_input(event: InputEvent, data: ItemData) -> bool:
	if event.is_action_pressed("attack_2"):
		_aim_held = true
		_enter_aim()
		return true
	if event.is_action_released("attack_2"):
		_aim_held = false
		return true
	if event.is_action_pressed("attack_1"):
		# La lanza sin apuntar pica cuerpo a cuerpo; apuntando, se carga el lanzamiento.
		if data.throwable and not _aim_held:
			_request(&"light")
			return true
		_draw_held = true
		_enter_aim()
		return true
	if event.is_action_released("attack_1"):
		_draw_held = false
		return true
	return false


## Hay algo a lo que pegar delante: con una herramienta en la mano, el clic sigue siendo talar
## o picar salvo que haya un enemigo encima.
func _enemy_near() -> bool:
	if lock_target != null:
		return true
	var forward := _camera_forward_h()
	for node in get_tree().get_nodes_in_group("npc"):
		var npc := node as NPCController
		if npc == null or not npc.active or npc.is_dead:
			continue
		var to := npc.global_position - player.global_position
		if to.length() < 3.6 and to.normalized().dot(forward) > 0.2:
			return true
	return false


func _request(action: StringName) -> void:
	_buffered = action
	_buffer_age = 0.0
	_try_buffered()


## Ejecuta la acción guardada si el estado actual la admite ya.
func _try_buffered() -> void:
	if _buffered == &"":
		return
	match _buffered:
		&"dodge":
			if _can_dodge_now():
				_buffered = &""
				_start_dodge()
		&"light", &"heavy":
			if _can_attack_now():
				var heavy := _buffered == &"heavy"
				_buffered = &""
				_start_attack(heavy)


func _can_dodge_now() -> bool:
	if player.movement.is_swimming or player.movement.is_falling or player.movement.is_jumping:
		return false
	match state:
		State.IDLE, State.AIM:
			return true
		State.ATTACK:
			# Cancelar la recuperación: ya ha pasado la ventana que hiere.
			return _t >= float(_attack.hit.y) and _hitstop <= 0.0
		State.DODGE:
			return _t >= _dodge_time() * 0.82
	return false


func _can_attack_now() -> bool:
	if player.movement.is_swimming or player.movement.is_falling or weapon() == null:
		return false
	match state:
		State.IDLE:
			return true
		State.ATTACK:
			return _t >= float(_attack.combo) and not _heavy
		State.DODGE:
			return _t >= _dodge_time() * 0.9
	return false


# ---------------------------------------------------------------------------------------------
# Bucle


## Avanza el combate un tick. La llama player_controller dentro de su movimiento normal, después
## de leer el input de movimiento y antes de fijar la velocidad.
func physics_update(delta: float, input_dir: Vector3) -> void:
	_record_spawn()
	_buffer_age += delta
	if _buffer_age > INPUT_BUFFER:
		_buffered = &""
	_lock_switch_cooldown = maxf(0.0, _lock_switch_cooldown - delta)
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_motion_h = Vector3.ZERO
	_act_advance(delta)
	match state:
		State.IDLE:
			_try_buffered()
			var data := weapon()
			if (_aim_held or _draw_held) and data != null and data.is_ranged():
				_enter_aim()
		State.ATTACK:
			_update_attack(delta)
		State.DODGE:
			_update_dodge(delta, input_dir)
		State.AIM:
			_update_aim(delta)
		State.STAGGER:
			_update_stagger(delta)
		State.DEAD:
			_update_dead(delta)
	if state != State.DEAD:
		_try_buffered()
	_update_lock(delta)
	_update_limits(delta, input_dir)
	_update_aim_blend(delta)
	_update_carry(delta)


## Velocidad final del cuerpo: en golpe, esquiva, tambaleo y muerte el combate manda en el plano
## del suelo; la componente vertical (gravedad, salto) sigue siendo la del movimiento.
func apply_motion(velocity: Vector3) -> Vector3:
	if state == State.IDLE or state == State.AIM:
		return velocity
	var up := -player.gravity_direction.normalized()
	return up * velocity.dot(up) + _motion_h


## Orienta el cuerpo si el combate lo decide. Devuelve false para dejar el giro por defecto.
func update_facing(delta: float, input_dir: Vector3) -> bool:
	match state:
		State.DODGE, State.STAGGER, State.DEAD:
			return true
		State.ATTACK:
			if _t < float(_attack.hit.x):
				_face(_attack_dir, delta, 9.0)
			return true
		State.AIM:
			_face(_camera_forward_h(), delta, 14.0)
			return true
	if lock_target != null:
		var moving := input_dir.length() > 0.2
		_face(_flat(input_dir) if moving else _flat(_lock_point(lock_target) - player.global_position),
			delta, 10.0)
		return true
	return false


func _face(dir: Vector3, delta: float, speed: float) -> void:
	var flat := _flat(dir)
	if flat.length_squared() < 1e-4:
		return
	player.rotate_toward_direction(flat, delta, speed)


func _flat(v: Vector3) -> Vector3:
	var up := -player.gravity_direction.normalized()
	var h := v - up * v.dot(up)
	return h.normalized() if h.length_squared() > 1e-8 else Vector3.ZERO


func _camera_forward_h() -> Vector3:
	return _flat(-player.camera.global_basis.z)


func _body_forward() -> Vector3:
	return _flat(player.global_basis.z)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	_t = 0.0
	# Un tambaleo o paso atrás cortado (muerte, otra acción) no sigue posando.
	if new_state != State.STAGGER and new_state != State.DODGE:
		pose.motion_x = -1.0
	state_changed.emit(new_state)


func is_busy() -> bool:
	return state != State.IDLE


func is_dead() -> bool:
	return state == State.DEAD


# ---------------------------------------------------------------------------------------------
# Golpes


func _start_attack(heavy: bool) -> void:
	var data := weapon()
	if data == null:
		return
	var cost := data.stamina_cost * (1.6 if heavy else 1.0)
	if not stamina.spend(cost):
		hud.flash_stamina()
		return
	var chained := state == State.ATTACK
	var previous := _attack
	if state == State.AIM:
		_end_aim()
	_combo = (_combo + 1) if chained else 0
	_attack_id = &"v" if heavy else (&"h" if _combo % 2 == 0 else &"v")
	# La lanza pica de arriba abajo; es lo más parecido a una estocada que trae el rig.
	if data.weapon_type == ItemData.WeaponType.SPEAR and not heavy:
		_attack_id = &"v"
	_attack = ATTACKS[_attack_id]
	_heavy = heavy
	_charge = 0.0
	_attack_speed = maxf(data.attack_speed, 0.3) * (0.85 if heavy else 1.0)
	_attack_dir = _choose_attack_dir()
	_sweep.radius = maxf(data.blade_radius, 0.04)
	_sweep.reset()
	_swing_hits = 0
	_hitstop = 0.0
	_set_state(State.ATTACK)
	_t = 0.0
	if chained and not previous.is_empty() and previous.oneshot != _attack.oneshot:
		_tree_set("parameters/%s/request" % previous.oneshot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_tree_set("parameters/%s/scale" % _attack.speed, _attack_speed)
	_tree_set("parameters/%s/request" % _attack.oneshot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	CombatFx.play(&"swing_windup", player.global_position, {"pitch": randf_range(0.9, 1.1)})


## Hacia dónde sale el golpe: al objetivo fijado; si no, hacia donde se mueve; si no, hacia
## donde mira la cámara.
func _choose_attack_dir() -> Vector3:
	if lock_target != null:
		return _flat(_lock_point(lock_target) - player.global_position)
	var move := _flat(player.movement.direction)
	if player.movement.direction.length() > 0.3 and move != Vector3.ZERO:
		return move
	var cam := _camera_forward_h()
	return cam if cam != Vector3.ZERO else _body_forward()


func _update_attack(delta: float) -> void:
	var data := weapon()
	if data == null:
		_end_attack()
		return
	var speed := _attack_speed
	if _hitstop > 0.0:
		_hitstop -= delta
		speed = 0.02
	elif _heavy and _t >= float(_attack.hold) and _charge < 1.0 and Input.is_action_pressed("attack_2"):
		# Cargando el pesado: la animación se congela arriba y la carga sube.
		speed = 0.0
		_charge = minf(1.0, _charge + delta / 0.9)
	elif _heavy and _t >= float(_attack.hold):
		speed = _attack_speed * 1.25
	_tree_set("parameters/%s/scale" % _attack.speed, speed)
	var prev_t := _t
	_t += delta * speed
	# Paso adelante mientras el golpe arranca; se frena pegado al objetivo.
	var lunge: Vector3 = _attack.lunge
	if _t > lunge.x and prev_t < lunge.y and speed > 0.0:
		var span := (lunge.y - lunge.x) / maxf(_attack_speed, 0.01)
		var step := lunge.z * (1.4 if _heavy else 1.0) / span
		var close := lock_target != null and player.global_position.distance_to(lock_target.global_position) < 1.9
		if not close:
			_motion_h = _flat(player.global_basis.z) * step * (speed / _attack_speed)
	var hit: Vector2 = _attack.hit
	if _t >= hit.x and prev_t <= hit.y:
		_sweep_blade(data)
	if _t >= float(_attack.end):
		_end_attack()


func _sweep_blade(data: ItemData) -> void:
	var frame := _right_grip.global_transform
	var base := frame * Vector3(0, data.blade_start, 0)
	var tip := frame * Vector3(0, data.reach, 0)
	var space := player.get_world_3d().direct_space_state
	var damage := float(data.damage)
	var poise_damage := data.poise_damage
	if _heavy:
		var mult := lerpf(1.3, data.heavy_multiplier, _charge)
		damage *= mult
		poise_damage *= mult
	elif _combo >= 2:
		damage *= 1.1
	for hit in _sweep.sweep(space, base, tip):
		var box: Hurtbox = hit.hurtbox
		if box.owner_body == player:
			continue
		var dir := _flat(box.owner_body.global_position - player.global_position)
		var info := DamageInfo.create(damage, player, hit.point, dir if dir != Vector3.ZERO else hit.direction, poise_damage)
		info.kind = data.damage_kind
		info.knockback = 0.6 if data.damage_kind == ItemData.DamageKind.BLUNT else 0.3
		var applied := box.receive(info)
		if applied > 0.0:
			_on_blade_hit(box, hit.point, info)
	for creature in MeleeSweep.loose_creatures_on_segment(get_tree(), base, tip, _sweep.radius):
		if not _sweep.has_hit(creature):
			_sweep.mark_hit(creature)
			creature.take_damage(damage, player)


func _on_blade_hit(box: Hurtbox, point: Vector3, info: DamageInfo) -> void:
	_swing_hits += 1
	_hitstop = HITSTOP_TIME * (1.6 if _heavy else 1.0)
	player.camera_controller.add_shake(0.10 if _heavy else 0.05)
	CombatFx.blood(box.owner_body, point, info.direction)
	CombatFx.impact(player, point, info.kind, true)
	hud.note_enemy_hit(box.owner_body)


func _end_attack() -> void:
	if not _attack.is_empty():
		_tree_set("parameters/%s/request" % _attack.oneshot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		_tree_set("parameters/%s/scale" % _attack.speed, 1.0)
	_attack = {}
	_heavy = false
	if state == State.ATTACK:
		_set_state(State.IDLE)
	if _aim_held or _draw_held:
		_enter_aim()


func _abort_attack_anim() -> void:
	for id in ATTACKS:
		_tree_set("parameters/%s/request" % ATTACKS[id].oneshot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		_tree_set("parameters/%s/scale" % ATTACKS[id].speed, 1.0)


func _tree_set(path: String, value: Variant) -> void:
	if _tree != null:
		_tree.set(path, value)


# ---------------------------------------------------------------------------------------------
# Esquiva


## La acción [action] se hace con la animación de Mixamo (ver USE_MIXAMO).
func _mixamo(action: StringName) -> bool:
	return _anims_ready and USE_MIXAMO.get(action, false)


func _dodge_time() -> float:
	if _dodge_roll:
		return ROLL_ANIM_TIME if _mixamo(&"roll") else ROLL_TIME
	return BACKSTEP_ANIM_TIME if _mixamo(&"dodge_back") else BACKSTEP_TIME


func _dodge_iframes() -> Vector2:
	if _dodge_roll:
		return ROLL_ANIM_IFRAMES if _mixamo(&"roll") else ROLL_IFRAMES
	return BACKSTEP_ANIM_IFRAMES if _mixamo(&"dodge_back") else BACKSTEP_IFRAMES


func _stagger_time() -> float:
	return STAGGER_ANIM_TIME if _mixamo(&"hit_react") else STAGGER_TIME


func _start_dodge() -> void:
	_roll_mirror = not _roll_mirror
	_roll_ground_normal = Vector3.UP
	_roll_ground_offset = 0.0
	var move := player.movement.direction
	_dodge_roll = move.length() > 0.25
	if not stamina.spend(ROLL_COST if _dodge_roll else BACKSTEP_COST):
		hud.flash_stamina()
		return
	if state == State.ATTACK:
		_abort_attack_anim()
		_attack = {}
	if state == State.AIM:
		_end_aim(true)
	_dodge_dir = _flat(move) if _dodge_roll else -_body_forward()
	if _dodge_dir == Vector3.ZERO:
		_dodge_dir = -_body_forward()
	# Rodando de lado se cae sobre el hombro de ese lado; adelante o atrás, alterna.
	var side := _dodge_dir.dot(player.camera.global_basis.x)
	if absf(side) > 0.5:
		_roll_mirror = side < 0.0
	if _dodge_roll:
		# Se gira de golpe hacia donde rueda, como en los souls.
		player.rotate_toward_direction(_dodge_dir, 1.0, 1.0)
	_set_state(State.DODGE)
	if _dodge_roll and _mixamo(&"roll"):
		_act_play("full", &"roll", ROLL_ANIM_SPEED)
	elif not _dodge_roll and _mixamo(&"dodge_back"):
		_act_play("full", &"dodge_back", BACKSTEP_ANIM_SPEED, BACKSTEP_ANIM_FROM)
	elif not _dodge_roll:
		_start_body_motion(BodyMotion.BACKSTEP, BodyMotion.backstep_travel, _dodge_dir, BACKSTEP_DISTANCE, 1.0)
	CombatFx.play(&"dodge", player.global_position)


func _update_dodge(delta: float, _input_dir: Vector3) -> void:
	_t += delta
	var duration := _dodge_time()
	var x := clampf(_t / duration, 0.0, 1.0)
	var distance := ROLL_DISTANCE if _dodge_roll else BACKSTEP_DISTANCE
	# Velocidad casi constante que se apaga al final (integra exactamente a la distancia).
	var v := distance / duration * 1.3333 * (1.0 - x * x * x)
	_motion_h = _dodge_dir * v
	var frames := _dodge_iframes()
	hurtbox.set_enabled(not (_t >= frames.x and _t <= frames.y))
	if pose.motion_x >= 0.0:
		pose.motion_x = x
	if _t >= duration:
		pose.motion_x = -1.0
		hurtbox.set_enabled(true)
		_act_stop("full")
		_set_state(State.IDLE)
		if _aim_held or _draw_held:
			_enter_aim()


# ---------------------------------------------------------------------------------------------
# Apuntar y disparar


func _enter_aim() -> void:
	if state == State.DEAD or state == State.DODGE or state == State.STAGGER:
		return
	if state == State.ATTACK:
		return
	_set_state(State.AIM)


func _end_aim(keep_input: bool = false) -> void:
	_draw = 0.0
	_release_t = -1.0
	_bow_phase = &""
	_bow_reload = -1.0
	_bow_release = -1.0
	_bow_hold = 0.0
	_spear_released = false
	_act_stop("upper")
	_arrow_visual.visible = false
	if not keep_input:
		_aim_held = false
		_draw_held = false
	if state == State.AIM:
		_set_state(State.IDLE)


func _update_aim(delta: float) -> void:
	var data := weapon()
	if data == null or not data.is_ranged():
		_end_aim()
		return
	_t += delta
	_draw_held = _draw_held and Input.is_action_pressed("attack_1")
	_aim_held = _aim_held and Input.is_action_pressed("attack_2")
	_update_aim_point(data)
	if _mixamo(&"throw") and data.throwable:
		_update_throw(delta, data)
		return
	var is_bow := data.weapon_type == ItemData.WeaponType.BOW
	if is_bow and _mixamo(&"bow"):
		_update_bow_anim(delta)
	elif is_bow:
		_update_bow_cycle(delta)
	if _release_t >= 0.0:
		# Lanzando (segundos desde que arranca el gesto, ThrowPose): la lanza sale cuando la
		# mano la suelta, por delante del hombro.
		var before := _release_t
		_release_t += delta
		if before < ThrowPose.RELEASE_AT and _release_t >= ThrowPose.RELEASE_AT:
			_fire(data, _draw)
		if _release_t >= ThrowPose.THROW_TIME:
			_release_t = -1.0
			_draw = 0.0
		return
	var has_ammo := ammo_count() > 0
	var can_draw := _bow_phase == &"ready" or not is_bow
	if _draw_held and has_ammo and _fire_cooldown <= 0.0 and not stamina.exhausted and can_draw:
		_draw = minf(1.0, _draw + delta / maxf(data.draw_time, 0.1))
		if _draw >= 1.0:
			stamina.drain(HOLD_DRAW_DRAIN, delta)
	elif _draw > 0.0 and not _draw_held:
		if _draw >= 0.3:
			if data.throwable:
				_release_t = 0.0
				return
			_fire(data, _draw)
		_draw = 0.0
	elif stamina.exhausted and _draw > 0.0:
		# Sin aguante no se sostiene la cuerda: se afloja sin disparar.
		_draw = maxf(0.0, _draw - delta * 3.0)
	if not _aim_held and not _draw_held and _draw <= 0.0 and _release_t < 0.0 \
			and _bow_phase != &"recoil" and _bow_phase != &"release":
		_end_aim()


## Arco procedural (ArcheryPose): al subirlo saca una flecha si no la lleva encajada; tras
## soltar sostiene el gesto y, si sigue apuntando y quedan flechas, va a por otra a la aljaba.
func _update_bow_cycle(delta: float) -> void:
	var has_ammo := ammo_count() > 0
	var keep := _aim_held or _draw_held
	match _bow_phase:
		&"":
			if _bow_nocked and has_ammo:
				_bow_phase = &"ready"
			elif has_ammo:
				_bow_phase = &"reload"
				_bow_reload = BOW_RAISE_RELOAD_FROM
			else:
				_bow_phase = &"empty"
		&"reload":
			_bow_reload += delta / ArcheryPose.RELOAD_TIME
			if _bow_release >= 0.0:
				_bow_release += delta
			if _bow_reload >= 1.0:
				_bow_reload = -1.0
				_bow_release = -1.0
				_bow_nocked = true
				_bow_phase = &"ready"
		&"release":
			_bow_release += delta
			if _bow_release >= BOW_FOLLOW_THROUGH and keep:
				if has_ammo:
					_bow_phase = &"reload"
					_bow_reload = 0.0
				else:
					_bow_phase = &"empty"
			elif _bow_release >= BOW_FOLLOW_THROUGH + 0.2:
				_bow_phase = &"empty"
		&"empty":
			_bow_release = -1.0
			if has_ammo and keep:
				_bow_phase = &"reload"
				_bow_reload = 0.0
		&"ready":
			if not has_ammo:
				_bow_nocked = false
				_bow_phase = &"empty"
	_bow_hold = _bow_hold + delta if _draw >= 1.0 else 0.0
	var a := pose.archery
	a.draw = _draw
	a.release_t = _bow_release
	a.reload = _bow_reload if _bow_phase == &"reload" else -1.0
	a.hold_t = _bow_hold
	a.nocked = _bow_phase == &"ready"
	a.fatigue = clampf(1.0 - stamina.stamina / (stamina.max_stamina * 0.25), 0.0, 1.0)


## Arco con las animaciones del Pro Longbow Pack (BowAnimRig coloca arco, cuerda y flecha): la
## mano va por encima del hombro a la aljaba, saca la flecha y la encaja (bow_draw hasta
## NOCK_T); tensar arrastra el resto de bow_draw con la tensión real y a tope se queda en su
## final; al soltar suena bow_recoil, que acaba donde empieza bow_draw: si sigue apuntando, va a
## por otra flecha sin cortes.
func _update_bow_anim(delta: float) -> void:
	var has_ammo := ammo_count() > 0
	var keep := _aim_held or _draw_held
	var t := _act_time("upper")
	match _bow_phase:
		&"":
			_bow_nocked = false
			if has_ammo:
				_bow_clip(&"bow_draw", 0.0)
				_bow_phase = &"nock"
			else:
				_bow_phase = &"empty"
		&"nock":
			t += delta * BOW_NOCK_SPEED
			_bow_clip(&"bow_draw", minf(t, BowAnimRig.NOCK_T))
			if t >= BowAnimRig.NOCK_T:
				_bow_phase = &"ready"
				_bow_nocked = true
		&"ready":
			if not has_ammo:
				_bow_phase = &"empty"
				_bow_nocked = false
				_act_stop("upper")
			else:
				# A tope se queda en el último fotograma (ver BowAnimRig).
				var length := _clip_length(&"bow_draw")
				_bow_clip(&"bow_draw", lerpf(BowAnimRig.NOCK_T, length, clampf(_draw, 0.0, 1.0)))
		&"recoil":
			_bow_nocked = false
			t += delta * BOW_RECOIL_SPEED
			var length := _clip_length(&"bow_recoil")
			_bow_clip(&"bow_recoil", minf(t, length))
			if t >= length:
				if keep and has_ammo:
					_bow_clip(&"bow_draw", 0.0)
					_bow_phase = &"nock"
				else:
					_bow_phase = &"empty" if keep else &""
					if not keep:
						_end_aim()
		&"empty":
			if has_ammo and keep:
				_bow_phase = &""
	var rig := pose.bow_rig
	var ch: Dictionary = _act["upper"]
	rig.clip = ch.anim if ch.active else &""
	rig.time = ch.time


## Deja el canal de tronco y brazos en [anim_name] a [time], arrastrado (el tiempo lo lleva el
## arco): los clips del arquero se encadenan sin fundidos y el canal no se acaba solo.
func _bow_clip(anim_name: StringName, time: float) -> void:
	if _act["upper"].anim != anim_name or not _act["upper"].active:
		_act_switch("upper", anim_name, 0.0, time)
	else:
		_act_scrub("upper", time)


func _clip_length(anim_name: StringName) -> float:
	var animator: AnimationPlayer = player.animation_controller.animator
	var path := StringName("combat/" + String(anim_name))
	return animator.get_animation(path).length if animator.has_animation(path) else 1.0


## Lanza con la animación de Mixamo: con el botón derecho el brazo se queda listo; cargando se
## lleva atrás (se arrastra la animación hasta el brazo del todo atrás) y al soltar se reproduce
## el lanzamiento; la lanza sale en el instante en que la mano la suelta en la animación.
func _update_throw(delta: float, data: ItemData) -> void:
	if _release_t >= 0.0:
		if not _spear_released and _act_time("upper") >= THROW_RELEASE:
			_spear_released = true
			_fire(data, _draw)
		if _act_time("upper") >= _act["upper"].length - 0.05 or not _act["upper"].active:
			_release_t = -1.0
			_draw = 0.0
			_spear_released = false
			if not _aim_held and not _draw_held:
				_end_aim()
		return
	if _draw_held and not stamina.exhausted:
		_draw = minf(1.0, _draw + delta / maxf(data.draw_time, 0.1))
	elif _draw > 0.0 and not _draw_held:
		if _draw >= 0.3:
			_release_t = 0.0
			_spear_released = false
			_act_play("upper", &"throw", THROW_SPEED, _act_time("upper"))
			return
		_draw = 0.0
	if not _act["upper"].active or _act["upper"].anim != &"throw":
		_act_play("upper", &"throw", 1.0, 0.0)
	# Brazo listo y, cargando, llevándolo atrás; con un suavizado para que no salte.
	var target := lerpf(THROW_READY, THROW_COCKED, _draw)
	_act_scrub("upper", move_toward(_act_time("upper"), target, delta * 2.2))
	if not _aim_held and not _draw_held and _draw <= 0.0:
		_end_aim()


## Punto al que se apunta: con objetivo fijado, el objetivo con la caída compensada (la cámara
## fijada lo encuadra algo por debajo del centro, así que la mira no vale); sin fijar, lo que
## hay bajo la mira (rayo desde el centro de la cámara).
func _update_aim_point(data: ItemData) -> void:
	var cam := player.camera
	if lock_target != null:
		var target := _lock_point(lock_target)
		var speed := maxf(data.projectile_speed, 1.0)
		var flight := player.global_position.distance_to(target) / speed
		# Adelanto: donde estará el objetivo cuando llegue el proyectil (dos pasadas bastan).
		var lead := _lock_velocity(lock_target)
		for _pass in 2:
			flight = player.global_position.distance_to(target + lead * flight) / speed
		target += lead * flight
		var g: float = player.planet.gravity_strength if player.planet else 9.8
		_aim_point = target - player.gravity_direction * (0.5 * g * flight * flight)
	else:
		var from := cam.global_position
		var to := from - cam.global_basis.z * 300.0
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1 | Hurtbox.LAYER
		query.collide_with_areas = true
		query.exclude = [player.get_rid(), hurtbox.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		_aim_point = hit.position if not hit.is_empty() else to
	var origin := player.global_position - player.gravity_direction * 1.45
	_aim_dir = (_aim_point - origin).normalized()


func _fire(data: ItemData, draw: float) -> void:
	if not stamina.spend(data.stamina_cost):
		hud.flash_stamina()
		return
	var kind := CombatProjectile.Kind.ARROW
	var visual: Node3D = null
	var ammo := _ammo_item()
	var from: Vector3
	if data.weapon_type == ItemData.WeaponType.SLINGSHOT:
		kind = CombatProjectile.Kind.STONE
		from = pose.bone_world("mixamorig_RightHandMiddle1")
	elif data.throwable:
		kind = CombatProjectile.Kind.SPEAR
		from = pose.bone_world("mixamorig_RightHand") - player.gravity_direction * 0.05
		ammo = data
		visual = load(data.scene_path).instantiate()
	else:
		from = _arrow_visual.global_position if _arrow_visual.visible else pose.bone_world("mixamorig_RightHand")
	var power := lerpf(0.45, 1.0, clampf(draw, 0.0, 1.0))
	var projectile := CombatProjectile.new()
	projectile.kind = kind
	projectile.shooter = player
	projectile.item_data = ammo
	projectile.planet_node = player.planet
	projectile.damage = float(data.damage) * (1.5 if data.throwable else 1.0) * lerpf(0.35, 1.0, pow(clampf(draw, 0.0, 1.0), 1.5))
	projectile.poise = data.poise_damage * power
	projectile.damage_kind = data.damage_kind
	projectile.set_exclude([player.get_rid(), hurtbox.get_rid()])
	get_tree().current_scene.add_child(projectile)
	var dir := (_aim_point - from).normalized()
	projectile.launch(from, dir, data.projectile_speed * power, visual)
	CombatFx.play(&"bow_release" if kind == CombatProjectile.Kind.ARROW else &"throw", from,
		{"pitch": 1.3 if kind == CombatProjectile.Kind.STONE else 1.0})
	_fire_cooldown = 0.35
	_arrow_visual.visible = false
	if _mixamo(&"bow") and data.weapon_type == ItemData.WeaponType.BOW:
		_bow_clip(&"bow_recoil", 0.0)
		_bow_phase = &"recoil"
		_bow_nocked = false
	elif data.weapon_type == ItemData.WeaponType.BOW:
		_bow_phase = &"release"
		_bow_release = 0.0
		_bow_nocked = false
	if data.throwable:
		_consume_thrown_weapon(data)
	elif ammo != null:
		player.inventory.remove_item(ammo, 1)
		player.inventory.inventory_changed.emit()


## La lanza se va con el lanzamiento: sale de la mano y, si quedan más en el inventario, se
## empuña la siguiente.
func _consume_thrown_weapon(data: ItemData) -> void:
	player._consume_right_hand_item()
	if player.inventory.get_item_count(data) > 0:
		player._equip_from_hotbar(null, data)
	else:
		_end_aim()


## Recoge la lanza clavada más cercana. Devuelve true si ha recogido algo.
func try_pickup() -> bool:
	var best: CombatProjectile = null
	var best_d := 2.6
	for node in get_tree().get_nodes_in_group(CombatProjectile.PICKUP_GROUP):
		var p := node as CombatProjectile
		if p == null or not p.is_pickable():
			continue
		var d := p.global_position.distance_to(player.global_position)
		if d < best_d:
			best = p
			best_d = d
	if best == null or best.item_data == null:
		return false
	var data := best.item_data
	best.queue_free()
	if weapon() == null and player.hotbar.get_selected_data() != null \
			and player.hotbar.get_selected_data().id == data.id:
		player.inventory.add_item(data, 1)
		player._equip_from_hotbar(null, data)
	else:
		player.inventory.add_item(data, 1)
		player.inventory.inventory_changed.emit()
	return true


## Coloca arco/tirachinas, flecha y lanza sobre las manos ya posadas (lo llama CombatPose al
## terminar de posar, así va en el mismo fotograma que el esqueleto).
func _place_ranged_visuals(p: CombatPose) -> void:
	if p.grip_right:
		_right_grip.global_transform = p.right_grip_xform
	var data := weapon()
	if data == null or _weapon_node == null or not is_instance_valid(_weapon_node):
		_arrow_visual.visible = false
		return
	var aiming := _aim_weight > 0.02
	var up := -player.gravity_direction.normalized()
	if _quiver != null:
		var q := ArcheryPose.quiver_skel(p)
		var skel_xf := p.skeleton().global_transform
		_quiver.global_transform = Transform3D((skel_xf.basis * q.basis).orthonormalized(), skel_xf * q.origin)
		var arrow_mode: StringName = pose.bow_rig.arrow_mode if _mixamo(&"bow") else pose.archery.arrow_mode
		var in_hand := 1 if (_bow_nocked or arrow_mode != &"") and state == State.AIM else 0
		_quiver.set_count(ammo_count() - in_hand)
	if data.weapon_type == ItemData.WeaponType.BOW:
		_place_bow(p, data)
		return
	if data.is_left_handed():
		var visual := _weapon_node as RangedWeaponVisual
		if aiming:
			_weapon_node.top_level = true
			var z := p.aim_dir.normalized()
			var y := (up - z * up.dot(z)).normalized()
			# Arco algo ladeado, como se sujeta de verdad.
			y = y.rotated(z, deg_to_rad(-12.0 if data.weapon_type == ItemData.WeaponType.BOW else 0.0))
			var hand := p.bone_world("mixamorig_LeftHand")
			var grip_offset := z * 0.03 + y * (0.0 if data.weapon_type == ItemData.WeaponType.BOW else -0.06)
			_weapon_node.global_transform = Transform3D(Basis(y.cross(z), y, z), hand + grip_offset)
			var nock := p.bone_world("mixamorig_RightHandMiddle1")
			if visual != null:
				visual.set_draw_point(nock if _draw > 0.02 or state == State.AIM else null)
			var show_arrow := data.weapon_type == ItemData.WeaponType.BOW and ammo_count() > 0 \
				and _fire_cooldown <= 0.15 and state == State.AIM
			_arrow_visual.visible = show_arrow
			if show_arrow:
				var grip := _weapon_node.global_position
				var axis := (grip - nock).normalized()
				var center := nock + axis * (WeaponMeshes.ARROW_LENGTH * 0.5 - 0.03)
				var ax := axis.cross(up).normalized()
				_arrow_visual.global_transform = Transform3D(Basis(ax, axis, ax.cross(axis)), center)
		else:
			_weapon_node.top_level = false
			_weapon_node.transform = Transform3D.IDENTITY
			_arrow_visual.visible = false
			if visual != null:
				visual.set_draw_point(null)
	elif data.throwable:
		_arrow_visual.visible = false
		var released := _spear_released if _mixamo(&"throw") else _release_t >= ThrowPose.RELEASE_AT
		if aiming and state == State.AIM and not released:
			_weapon_node.top_level = true
			if _mixamo(&"throw"):
				# La lanza, apuntada al blanco sobre la mano alzada.
				var y := p.aim_dir.normalized()
				var x := y.cross(up).normalized()
				var hand := p.bone_world("mixamorig_RightHand")
				# Agarrada por el tercio trasero, como una jabalina: casi todo el asta por delante.
				_weapon_node.global_transform = Transform3D(Basis(x, y, x.cross(y)), hand + y * 0.40)
			else:
				# Cruzando la palma, como la deja ThrowPose; agarrada por el tercio trasero.
				var g := p.throw.grip_xform
				var dir := -g.basis.z
				var hanging := p.bone_world_xform("mixamorig_RightHandMiddle2") * RIGHT_GRIP
				var held := Transform3D(Basis(g.basis.x, dir, g.basis.x.cross(dir)), g.origin + dir * 0.40)
				_weapon_node.global_transform = hanging.orthonormalized().interpolate_with(held, smoothstep(0.0, 0.7, p.aim_weight))
		else:
			_weapon_node.top_level = false
			_weapon_node.transform = Transform3D.IDENTITY
			_weapon_node.visible = not released
	else:
		_arrow_visual.visible = false


## Arco, cuerda y flecha donde los deja BowAnimRig (con animaciones) o ArcheryPose (procedural).
## Mientras sube o baja, el arco pasa del agarre de colgar al de tirar sin saltos.
func _place_bow(p: CombatPose, _data: ItemData) -> void:
	var a: Object = p.bow_rig if _mixamo(&"bow") else p.archery
	var visual := _weapon_node as RangedWeaponVisual
	if p.aim_weight <= 0.001:
		_weapon_node.top_level = false
		_weapon_node.transform = Transform3D.IDENTITY
		_arrow_visual.visible = false
		if visual != null:
			visual.flex = 0.0
			visual.set_draw_point(null)
		return
	_weapon_node.top_level = true
	var hanging := p.bone_world_xform("mixamorig_LeftHandMiddle2") * LEFT_GRIP
	var k := smoothstep(0.0, 0.7, p.aim_weight)
	_weapon_node.global_transform = hanging.orthonormalized().interpolate_with(a.bow_xform, k)
	if visual != null:
		visual.flex = a.bow_flex
		visual.set_draw_point(a.string_point if k > 0.95 else null)
	_arrow_visual.visible = a.arrow_mode != &"" and state == State.AIM and ammo_count() > 0 and k > 0.5
	if _arrow_visual.visible:
		_arrow_visual.global_transform = a.arrow_xform


## Al correr con un arma de combate en la derecha, el brazo la lleva a un costado (ver
## CombatPose._apply_carry): la animación de correr cruza la hoja por el cuerpo.
func _update_carry(delta: float) -> void:
	var m := player.movement
	var data := weapon()
	var target := 1.0 if pose.grip_right and data != null and state == State.IDLE \
		and (m.is_running or m.is_sprinting) and not m.is_swimming else 0.0
	# Al golpear, esquivar o apuntar se suelta enseguida para no arrastrarla sobre la acción.
	var rate := CARRY_BLEND_SPEED if state == State.IDLE else CARRY_BLEND_SPEED * 3.0
	_carry = move_toward(_carry, target, delta * rate)
	pose.carry = smoothstep(0.0, 1.0, _carry)
	if data != null:
		pose.carry_perpendicular = data.weapon_type != ItemData.WeaponType.SPEAR


func _update_aim_blend(delta: float) -> void:
	var data := weapon()
	var target := 1.0 if state == State.AIM and data != null and data.is_ranged() else 0.0
	_aim_weight = move_toward(_aim_weight, target, delta * 6.0)
	pose.aim_weight = smoothstep(0.0, 1.0, _aim_weight)
	# Al apuntar, la pose lleva el tronco y la cabeza al blanco: si la mirada (LookAtIK, que va
	# antes) también se inclinara hacia la cámara, el tronco se pasaría del blanco y la cabeza,
	# que sube más que los brazos, dejaría la mano de la cuerda en el cuello.
	if _look_ik:
		_look_ik.influence = 1.0 - pose.aim_weight
	pose.aim_dir = _aim_dir
	pose.draw = _draw
	pose.release = clampf(_release_t, 0.0, 1.0) if _release_t >= 0.0 else 0.0
	pose.throw.draw = _draw
	pose.throw.throw_t = _release_t
	# Con animación (arco, lanza) el modificador solo inclina el tronco hacia el blanco; sin
	# ella (tirachinas) pone también los brazos por IK.
	pose.aim_arms_ik = not (data != null and ((data.weapon_type == ItemData.WeaponType.BOW and _mixamo(&"bow"))
		or (data.throwable and _mixamo(&"throw"))))
	pose.upper_hips_yaw = _anim_hips_yaw(_act["upper"].anim, _act["upper"].time) if _act["upper"].active else NAN
	if data != null:
		match data.weapon_type:
			ItemData.WeaponType.BOW:
				pose.aim_style = &"bow"
			ItemData.WeaponType.SLINGSHOT:
				pose.aim_style = &"sling"
			_:
				pose.aim_style = &"throw"
	var cam_aim := 1.0 if state == State.AIM and (_aim_held or _draw > 0.2) else 0.0
	player.camera_controller.aim_target = cam_aim
	player.camera_controller.aim_zoom = _draw


# ---------------------------------------------------------------------------------------------
# Golpes recibidos


func _on_hit_received(info: DamageInfo, applied: float) -> void:
	if state == State.DEAD:
		return
	var up := -player.gravity_direction.normalized()
	var push_dir := _flat(info.direction)
	_last_hit_push = push_dir * clampf(35.0 + applied * 1.2 + info.poise * 0.8, 35.0, 110.0) + up * 8.0
	hit_react.flinch(info.direction, up, clampf(applied / 22.0, 0.3, 1.2))
	player.camera_controller.add_shake(clampf(applied / 60.0, 0.06, 0.35))
	hud.flash_damage(clampf(applied / 40.0, 0.25, 1.0))
	CombatFx.play(&"player_hurt", player.global_position)
	if player.health_component.health - applied <= 0.0:
		return
	if info.poise >= PLAYER_POISE and state != State.DODGE:
		_start_stagger(info)


func _start_stagger(info: DamageInfo) -> void:
	if state == State.ATTACK:
		_abort_attack_anim()
		_attack = {}
	if state == State.AIM:
		_end_aim(true)
	var push := _flat(info.direction)
	if push == Vector3.ZERO:
		push = -_body_forward()
	_knock = push * maxf(info.knockback, 1.2) / (_stagger_time() * 0.5)
	_act_stop("upper")
	_set_state(State.STAGGER)
	if _mixamo(&"hit_react"):
		_act_play("full", &"hit_react", HIT_ANIM_SPEED)
	else:
		# Trastabilla hacia donde empuja el golpe (BodyMotion.STAGGER): lo que recorre el cuerpo
		# con la velocidad de _update_stagger, para que los pies apoyados no patinen.
		_start_body_motion(BodyMotion.STAGGER, BodyMotion.stagger_travel, push,
			_knock.length() * _stagger_time() * (1.0 / 1.8 - 0.9 / (1.8 * 1.8)), clampf(info.poise / 40.0, 0.6, 1.3))


func _update_stagger(delta: float) -> void:
	_t += delta
	var x := clampf(_t / _stagger_time(), 0.0, 1.0)
	_motion_h = _knock * maxf(0.0, 1.0 - x * 1.8)
	if pose.motion_x >= 0.0:
		pose.motion_x = x
	if _t >= _stagger_time():
		_act_stop("full")
		pose.motion_x = -1.0
		_set_state(State.IDLE)


## Arranca un movimiento de cuerpo entero de BodyMotion. [push] en mundo.
func _start_body_motion(motion: Dictionary, travel: Callable, push: Vector3, distance: float, power: float) -> void:
	pose.motion = motion
	pose.motion_travel = travel
	pose.motion_push = (player.player_model.global_basis.inverse() * push).normalized()
	pose.motion_distance = distance
	pose.motion_power = power
	pose.motion_left_first = not pose.motion_left_first
	pose.motion_x = 0.0


# ---------------------------------------------------------------------------------------------
# Muerte y reaparición


func _on_died() -> void:
	if state == State.DEAD:
		return
	_abort_attack_anim()
	_attack = {}
	_end_aim()
	release_lock()
	hurtbox.set_enabled(false)
	_set_state(State.DEAD)
	_death_time = 0.0
	_act_stop("upper")
	if _mixamo(&"death"):
		_act_play("full", &"death", DEATH_ANIM_SPEED, 0.0, true)
	else:
		# Cae como un muñeco desde la pose que tenga, empujado por el golpe que lo mata.
		player.player_model.transform = Transform3D.IDENTITY
		ragdoll.gravity = player.gravity_direction.normalized() * (player.planet.gravity_strength if player.planet else 9.8)
		ragdoll.start(player.velocity, _last_hit_push)
	if _foot_ik:
		_foot_ik.influence = 0.0
	if _look_ik:
		_look_ik.active = false
	CombatFx.play(&"player_death", player.global_position)


func _update_dead(delta: float) -> void:
	_death_time += delta
	_t += delta
	if ragdoll.is_running():
		# El cuerpo físico (y con él la cámara) sigue al muñeco si rueda ladera abajo.
		var up := -player.gravity_direction.normalized()
		var to := ragdoll.center() - player.global_position
		to -= up * to.dot(up)
		_motion_h = to.limit_length(1.0) * 5.0 if to.length() > 0.3 else Vector3.ZERO
	if _death_time >= DEATH_SCREEN_DELAY and not hud.is_death_shown():
		hud.show_death()
	if _death_time >= RESPAWN_DELAY and not _respawning:
		_respawn()


## Vuelve al último punto guardado (o al inicio de la partida si no hay nada guardado) con la
## vida y el aguante llenos, y calma a las criaturas que venían a por él.
func _respawn() -> void:
	_respawning = true
	await hud.fade_to_black(0.9)
	var xform := _respawn_transform()
	player.input_enabled = false
	player.global_transform = xform
	player.velocity = Vector3.ZERO
	player.movement.velocity = Vector3.ZERO
	player.movement.gravity_velocity = 0.0
	player.movement.is_falling = false
	player.movement.is_jumping = false
	player.reset_physics_interpolation()
	ragdoll.stop()
	player.player_model.transform = Transform3D.IDENTITY
	_act_stop("full")
	_act_stop("upper")
	player.health_component.revive()
	stamina.refill()
	pose.death = 0.0
	pose.tuck = 0.0
	hurtbox.set_enabled(true)
	if _foot_ik:
		_foot_ik.influence = 1.0
	if _look_ik:
		_look_ik.active = true
	_calm_hostiles()
	hud.hide_death()
	player.update_nearest_planet()
	if player.planet:
		player.gravity_direction = player.planet.get_gravity_direction(player.global_position)
		player.up_direction = -player.gravity_direction
	# Como al activar al jugador: esperar a que el suelo de destino tenga colisión.
	var confirmations := 0
	var waited := 0.0
	while confirmations < 3 and waited < 15.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		confirmations = confirmations + 1 if player.is_ground_ready() else 0
	_set_state(State.IDLE)
	player.input_enabled = true
	_respawning = false
	await hud.fade_from_black(1.2)


## Al cargar una partida: fuera de cualquier golpe, esquiva o muerte, y con todo lleno.
func on_restored() -> void:
	_abort_attack_anim()
	_act_stop("full")
	_act_stop("upper")
	_attack = {}
	_end_aim()
	release_lock()
	if player.health_component.is_dead:
		player.health_component.revive()
	stamina.refill()
	hurtbox.set_enabled(true)
	ragdoll.stop()
	pose.death = 0.0
	pose.tuck = 0.0
	player.player_model.transform = Transform3D.IDENTITY
	if _foot_ik:
		_foot_ik.influence = 1.0
	if _look_ik:
		_look_ik.active = true
	hud.hide_death()
	_respawning = false
	_set_state(State.IDLE)


func _respawn_transform() -> Transform3D:
	var fo := get_tree().get_first_node_in_group("floating_origin_manager") as FloatingOrigin
	var saved := GameManager.peek_player_data(GameManager.MAIN_SLOT)
	if not saved.is_empty() and saved.has("position"):
		var p: Dictionary = saved.position
		var canonical := Vector3(float(p.x), float(p.y), float(p.z))
		var basis := player.global_basis
		if saved.has("basis"):
			var b: Dictionary = saved.basis
			basis = Basis(Vector3(b.xx, b.xy, b.xz), Vector3(b.yx, b.yy, b.yz), Vector3(b.zx, b.zy, b.zz))
		return Transform3D(basis.orthonormalized(), fo.from_canonical(canonical) if fo != null else canonical)
	if _spawn_canonical != null:
		return Transform3D(_spawn_basis, fo.from_canonical(_spawn_canonical) if fo != null else _spawn_canonical)
	return player.global_transform


## Guarda dónde empezó a jugar, para reaparecer ahí si nunca se ha guardado.
func _record_spawn() -> void:
	if _spawn_canonical != null or not player.input_enabled or not player.is_on_floor():
		return
	var fo := get_tree().get_first_node_in_group("floating_origin_manager") as FloatingOrigin
	_spawn_canonical = fo.to_canonical(player.global_position) if fo != null else player.global_position
	_spawn_basis = player.global_basis.orthonormalized()


func _calm_hostiles() -> void:
	for node in get_tree().get_nodes_in_group("npc"):
		var npc := node as NPCController
		if npc == null or npc.is_dead or npc.ai_controller == null:
			continue
		if npc.ai_controller.target != player:
			continue
		npc.ai_controller.target = null
		if npc.perception:
			npc.perception.forget()
		npc.ai_controller.transition_to(npc.initial_ai_state)
		if npc.health_component and not npc.health_component.is_dead:
			npc.health_component.revive()


# ---------------------------------------------------------------------------------------------
# Objetivo fijado


func lock_on() -> void:
	var target := _find_lock_target(0.0)
	if target != null:
		lock_target = target
		_lock_lost_time = 0.0
		CombatFx.play(&"lock", player.global_position)


func release_lock() -> void:
	lock_target = null
	player.camera_controller.lock_point = null


func _lock_point(target: Node3D) -> Vector3:
	var creature := target as AmbientAnimal
	if creature != null:
		return creature.lock_point()
	return target.global_position - player.gravity_direction * 0.8


## Cualquier criatura viva (NPCs, aves, fauna menuda) se puede fijar.
func _lockable(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var creature := target as AmbientAnimal
	return creature != null and creature.lockable()


## Velocidad del objetivo para adelantar el tiro: sin ella, un ave en vuelo es imposible de acertar.
func _lock_velocity(target: Node3D) -> Vector3:
	var body := target as CharacterBody3D
	return body.velocity if body != null else Vector3.ZERO


## Mejor candidato: el más centrado en pantalla y cerca. [side] != 0 busca solo a ese lado del
## objetivo actual (−1 izquierda, +1 derecha).
func _find_lock_target(side: float) -> Node3D:
	var cam := player.camera
	var cam_forward := -cam.global_basis.z
	var cam_right := cam.global_basis.x
	var best: Node3D = null
	var best_score := INF
	var current_x := 0.0
	if lock_target != null:
		current_x = (_lock_point(lock_target) - cam.global_position).normalized().dot(cam_right)
	for node in get_tree().get_nodes_in_group(AmbientAnimal.GROUP):
		var creature := node as AmbientAnimal
		if not _lockable(creature) or creature == lock_target:
			continue
		var point := _lock_point(creature)
		var dist := player.global_position.distance_to(point)
		if dist > LOCK_RANGE:
			continue
		var to := (point - cam.global_position).normalized()
		var facing := to.dot(cam_forward)
		if facing < 0.35:
			continue
		var x := to.dot(cam_right)
		if side != 0.0 and signf(x - current_x) != signf(side):
			continue
		if not _has_line_of_sight(point, creature):
			continue
		var score := acos(clampf(facing, -1.0, 1.0)) * 2.0 + dist / LOCK_RANGE
		if side != 0.0:
			score = absf(x - current_x) * 3.0 + dist / LOCK_RANGE
		if not creature is NPCController:
			score += LOCK_SMALL_FAUNA_BIAS
		if score < best_score:
			best_score = score
			best = creature
	return best


func _has_line_of_sight(point: Vector3, target: Node) -> bool:
	var from := player.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, point)
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target


func _update_lock(delta: float) -> void:
	if not is_instance_valid(lock_target):
		lock_target = null
	if lock_target == null:
		player.camera_controller.lock_point = null
		return
	var npc := lock_target as NPCController
	if not _lockable(lock_target) or player.global_position.distance_to(lock_target.global_position) > LOCK_BREAK_RANGE:
		release_lock()
		# Si cae uno, se pasa al siguiente como en los souls.
		if npc != null and npc.is_dead:
			lock_on()
		return
	var point := _lock_point(lock_target)
	if _has_line_of_sight(point, lock_target):
		_lock_lost_time = 0.0
	else:
		_lock_lost_time += delta
		if _lock_lost_time > 2.0:
			release_lock()
			return
	player.camera_controller.lock_point = point
	var swipe := player.camera_controller.consume_lock_swipe()
	if absf(swipe) > LOCK_SWITCH_THRESHOLD and _lock_switch_cooldown <= 0.0:
		var next := _find_lock_target(-signf(swipe))
		if next != null:
			lock_target = next
			_lock_switch_cooldown = 0.35


# ---------------------------------------------------------------------------------------------
# Límites al movimiento y visual del cuerpo


func _update_limits(delta: float, input_dir: Vector3) -> void:
	var movement: Movement = player.movement
	var sprinting := Input.is_action_pressed("Sprint") and input_dir.length() > 0.1 and state == State.IDLE
	if sprinting and not stamina.drain(SPRINT_DRAIN, delta):
		sprinting = false
	movement.sprint_blocked = state != State.IDLE or stamina.exhausted
	movement.jump_blocked = state != State.IDLE
	movement.speed_scale = 0.45 if state == State.AIM else 1.0
	player.current_animation = Config.ANIMATION.DEATH if state == State.DEAD else player.current_animation
	# Tambaleo y paso atrás procedurales van sobre la animación de estar quieto: los pasos los
	# dan las piernas por IK (si debajo corriera, las piernas seguirían corriendo).
	if pose.motion_x >= 0.0:
		player.current_animation = player.equiped_weapon.idle_animation if player.right_hand_equipped \
			else Config.ANIMATION.IDLE
	_update_body_visual()


## Hombro sobre el que rueda: alterna en cada voltereta (y según hacia qué lado se rueda).
var _roll_mirror: bool = false
var _roll_ground_normal: Vector3 = Vector3.UP
var _roll_ground_offset: float = 0.0


## Suelo bajo el cuerpo durante la voltereta, en su espacio local: en una ladera el ovillo se
## apoya en ella y no en el plano horizontal de los pies. Suavizado para que las irregularidades
## del terreno no hagan temblar el cuerpo.
func _update_roll_ground() -> void:
	var up := -player.gravity_direction.normalized()
	var from := player.global_position + up * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, from - up * 3.0)
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var normal := Vector3.UP
	var offset := 0.0
	if not hit.is_empty():
		normal = (player.global_basis.inverse() * (hit.normal as Vector3)).normalized()
		if normal.y < 0.5:
			normal = Vector3.UP
		offset = normal.dot(player.to_local(hit.position))
	_roll_ground_normal = _roll_ground_normal.lerp(normal, 0.35).normalized()
	_roll_ground_offset = lerpf(_roll_ground_offset, offset, 0.35)


## IK de pies y mirada: fuera mientras rueda (el de pies intentaría clavar los pies al suelo en
## plena vuelta y el de mirada giraría la cabeza hacia la cámara); vuelven suaves al terminar.
func _set_body_ik(target: float) -> void:
	if _foot_ik:
		_foot_ik.influence = target if target <= 0.0 else move_toward(_foot_ik.influence, target, 0.12)
	if _look_ik:
		_look_ik.active = target > 0.0


## Giro y ovillo de la voltereta y vuelco al morir, sobre PlayerModel (el cuerpo físico no gira).
func _update_body_visual() -> void:
	var model: Node3D = player.player_model
	var animated := false
	match state:
		State.DODGE:
			animated = _mixamo(&"roll") if _dodge_roll else _mixamo(&"dodge_back")
		State.DEAD:
			animated = _mixamo(&"death")
		State.STAGGER:
			animated = _mixamo(&"hit_react")
	if animated:
		# La pose la pone la animación de Mixamo; aquí solo se evita que se hunda en una ladera
		# (el cuerpo sube lo justo para que su punto más bajo quede sobre el suelo real).
		pose.sample_contacts = true
		pose.tuck = 0.0
		pose.roll_x = -1.0
		pose.death = 0.0
		var sample: Dictionary = pose.contact_sample
		var lift := 0.0
		if not sample.is_empty():
			_update_roll_ground()
			lift = RollMotion.ground_lift(sample.points, sample.radii, _roll_ground_normal, _roll_ground_offset)
		var current := model.transform.origin.y
		model.transform = Transform3D(Basis.IDENTITY, Vector3(0, lerpf(current, lift, 0.5), 0))
		if state != State.STAGGER:
			_set_body_ik(0.0)
		return
	match state:
		State.DODGE:
			var x := clampf(_t / _dodge_time(), 0.0, 1.0)
			if _dodge_roll:
				# Posturas clave, vuelta en diagonal y apoyo en el suelo (RollMotion). Los huesos
				# de contacto los mide CombatPose ya encogidos.
				pose.sample_contacts = true
				pose.tuck = 0.0
				pose.roll_x = x
				pose.roll_mirror = _roll_mirror
				var sample: Dictionary = pose.contact_sample
				if not sample.is_empty():
					_update_roll_ground()
					model.transform = RollMotion.model_transform(x, sample.points, sample.radii,
						sample.pivot, _roll_ground_normal, _roll_ground_offset, _roll_mirror)
				_set_body_ik(0.0)
			else:
				# Paso atrás: lo pone entero BodyMotion.BACKSTEP en CombatPose.
				pose.tuck = 0.0
				model.transform = Transform3D.IDENTITY
		State.DEAD:
			if ragdoll.is_running():
				pose.death = 0.0
				pose.tuck = 0.0
				return
			var x := clampf(_death_time / 0.75, 0.0, 1.0)
			# Cae hacia atrás con un pequeño rebote al dar en el suelo.
			var fall := x * x
			if x >= 1.0:
				fall = 1.0 + 0.04 * sin(minf((_death_time - 0.75) / 0.25, 1.0) * PI)
			var angle := deg_to_rad(-86.0) * fall
			var pivot := Vector3(0, 0.0, -0.12)
			var basis := Basis(Vector3.RIGHT, angle)
			model.transform = Transform3D(basis, pivot - basis * pivot + Vector3(0, 0.14 * x, 0))
			pose.death = smoothstep(0.2, 1.0, x)
			pose.tuck = 0.0
		_:
			pose.sample_contacts = false
			pose.roll_x = -1.0
			pose.tuck = 0.0
			if state != State.DEAD:
				_set_body_ik(1.0)
			# Apuntando con el arco sin moverse, el cuerpo se pone de perfil (los pies con él);
			# andando vuelve de frente y el giro lo hace solo el tronco.
			var data := weapon()
			var target := 0.0
			var stance := 0.0
			if state == State.AIM and data != null:
				if data.weapon_type == ItemData.WeaponType.BOW and not _mixamo(&"bow"):
					stance = BOW_STANCE_YAW
				elif data.throwable and not _mixamo(&"throw"):
					stance = THROW_STANCE_YAW
			if stance != 0.0:
				var up := -player.gravity_direction.normalized()
				var h_speed := (player.velocity - up * player.velocity.dot(up)).length()
				target = stance * _aim_weight * (1.0 - clampf(h_speed / 1.5, 0.0, 1.0))
				# En cuesta, girar los pies deja uno muy por encima del otro: se gira menos.
				if player.is_on_floor():
					var slope := rad_to_deg(player.get_floor_normal().angle_to(up))
					target *= 1.0 - smoothstep(8.0, 22.0, slope)
			_stance_yaw = move_toward(_stance_yaw, target, 240.0 * get_physics_process_delta_time())
			if not player.movement.is_swimming:
				var want := Transform3D.IDENTITY
				if absf(_stance_yaw) > 0.01:
					want = Transform3D(Basis(Vector3.UP, deg_to_rad(_stance_yaw)), Vector3.ZERO)
				if model.transform != want:
					model.transform = want
			return
	_stance_yaw = 0.0
