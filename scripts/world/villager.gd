class_name Villager extends Node3D

## Un aldeano (SettlementVillagers): un humano vestido de pieles que vive según la hora del sitio. De
## noche duerme en su lecho. De día, si tiene oficio (SettlementPopulation: "job"), trabaja en su sitio
## con su herramienta en la mano: el leñador parte leña en el tajo, el granjero cava el huerto y el
## artesano golpea en el banco; a mediodía se sienta delante de su casa. Sin oficio, o fuera de esas
## horas, pasea por la plaza, se queda de pie, se sienta en el suelo o se junta con otro a charlar; al
## atardecer se sienta en corro junto a la hoguera. Al jugador lo mira si está cerca y a veces lo
## saluda; a él y a los demás los esquiva al andar; si una fiera ataca cerca corre a su casa y no sale
## hasta que acaba (SettlementVillage.danger).
##
## Va por los sitios de su poblado (SettlementVillage) en línea recta y sin física: sigue el suelo con
## un rayo y abre y cierra las puertas al cruzarlas. Un collider lo hace sólido para el jugador. Su
## sitio va en el marco del terreno (el del plano), y su pose en el mundo sale de él en cada paso: así
## el origen flotante no lo mueve. El humano se viste fuera del árbol (build_model, en un hilo).

const MODEL := "res://scenes/character/character_model.tscn"
const ANIMS := "res://models/player/village_anims.tres"
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"village/walk"
const ANIM_RUN := &"running"
const ANIM_SIT := &"village/sit_idle"
const ANIM_TALK := &"village/talk"
const ANIM_SLEEP := &"village/sleep"
const ANIM_DIG := &"village/dig"
const ANIM_WAVE := &"village/wave"
## El golpe de arriba abajo del jugador (el del pico y la azada): partir leña y martillear.
const ANIM_STRIKE := &"attack_vertical"
## Al andar y al correr (m/s), y lo que avanzan sus clips a ritmo 1 (Locomotion).
const WALK_SPEED := 1.1
const WALK_CLIP_SPEED := 0.5
const RUN_SPEED := 3.5
const RUN_CLIP_SPEED := 4.3
## Giro al andar y al encarar a alguien (rad/s).
const TURN_RATE := 4.0
## Llega a un punto a menos de esto (m).
const ARRIVE := 0.15
## Fundido entre animaciones (s).
const BLEND := 0.4
## El rayo del suelo: de esto por encima de los pies a esto por debajo (m), cada tanto (s) al andar.
const PROBE_UP := 1.2
const PROBE_DOWN := 2.5
const PROBE_INTERVAL := 0.15
## Fuera, quieto y aún sin suelo (al aparecer, o sin la colisión del terreno todavía), lo busca cada
## tanto (s) desde más arriba (m): la plaza tiene desnivel.
const GROUND_RETRY := 1.0
const GROUND_SEARCH := 4.0
## Lo que levanta el lecho del suelo (m).
const BED_HEIGHT := 0.1
## Capa del collider: la 3, con la que choca el jugador (no la del mundo, que es la que mira el rayo).
const BODY_LAYER := 4
const BODY_RADIUS := 0.28
const BODY_HEIGHT := 1.7
## La herramienta, como la lleva el jugador (PlayerCombat): un marco de agarre en el hueso del dedo
## corazón; las de "combat" van en metros en él.
const HAND_BONE := "mixamorig_RightHandMiddle2"
## Horas solares del sitio.
const BED_HOUR := 21.5
const WAKE_HOUR := 6.5
const WORK_HOURS: Array[Vector2] = [Vector2(8.0, 12.0), Vector2(13.0, 18.0)]
const LUNCH := Vector2(12.0, 13.0)
const EVENING_HOUR := 18.5
## Cuánto dura cada cosa (s, entre las dos).
const STAND_TIME := Vector2(6.0, 20.0)
const SIT_TIME := Vector2(25.0, 70.0)
const TALK_TIME := Vector2(12.0, 30.0)
const WORK_TIME := Vector2(60.0, 150.0)
const BREAK_TIME := Vector2(5.0, 15.0)
const SHELTER_TIME := Vector2(15.0, 40.0)
## Cuando escampa, lo que tarda cada uno en salir de casa (s).
const CLEAR_DELAY := Vector2(2.0, 12.0)
## Entre golpe y golpe (s), y el ritmo del golpe en el banco (más corto que partir leña).
const STRIKE_PAUSE := Vector2(0.4, 1.3)
const BENCH_STRIKE_SPEED := 1.25
## Lo que espera de pie a su pareja de charla (s) y a qué distancia se ponen (m).
const WAIT_PARTNER := 25.0
const TALK_GAP := 1.3
## Dormido, o escondido en casa, cada cuánto mira si ya puede salir (s).
const SLEEP_CHECK := 20.0
const HIDE_CHECK := 6.0
## El jugador: de pie lo mira a menos de FACE_PLAYER m y lo saluda a menos de GREET m, una vez cada
## GREET_COOLDOWN s; el saludo dura WAVE_TIME s. Se mira cada LOOK_INTERVAL s.
const FACE_PLAYER := 4.0
const GREET := 6.0
const GREET_COOLDOWN := 90.0
const WAVE_TIME := 2.2
const LOOK_INTERVAL := 0.5
## Al andar se aparta de quien tenga a menos de esto (m) por delante.
const AVOID := 1.3
## Los aldeanos de ahora, para que el jugador encuentre con quién hablar (find).
const GROUP := &"villager"
## Hablando con el jugador: lo que dura cada frase (s).
const SAY_TIME := 2.6

enum Act {STAND, WALK, SIT, TALK, SLEEP, WORK, WAVE, HIDE, CHAT, SHELTER}

## SettlementPopulation.residents: "name", "home", "bed", "job"...
var resident: Dictionary
var village: SettlementVillage
var act := Act.STAND

var _pos := Vector3.ZERO
## Hacia dónde mira el cuerpo (+Z del modelo), tangente.
var _forward := Vector3.FORWARD
var _left := 0.0
var _path := PackedVector3Array()
## Por punto del camino: la casa cuya puerta se cruza al ir hacia él, o -1; y en qué casa queda al
## llegar a él (-1 fuera; -2 donde estaba).
var _doors := PackedInt32Array()
var _after := PackedInt32Array()
var _step := 0
var _speed := WALK_SPEED
## Lo que hace al acabar el camino.
var _arrive := Callable()
## La casa en la que está (índice en el plano), o -1 fuera.
var _inside := -1
var _partner: Villager
var _waiting := false
## Al trabajar: hacia dónde mira y, si es a golpes, cuánto falta para el siguiente.
var _look_at := Vector3.ZERO
var _strike_left := 0.0
var _striking := false
## Lo que hacía antes de saludar: [act, lo que le quedaba].
var _before_wave := []
var _greet_left := 0.0
var _look_left := 0.0
## De pie con el jugador cerca: lo va mirando (a _look_at).
var _eyeing := false
## Hablando con el jugador: lo que le queda a la frase de ahora (s).
var _say_left := 0.0
var _rng := RandomNumberGenerator.new()
var _model: Node3D
var _player: AnimationPlayer
var _body: AnimatableBody3D
var _tool: Node3D
var _anim := &""
var _anim_speed := 1.0
var _anim_accum := 0.0
var _frame := 0
var _probe_left := 0.0
## Ha encontrado el suelo desde que llegó a donde está.
var _grounded := false


## El humano de [who] (SettlementPopulation.residents), vestido con [pieces] ([ruta de la escena, si
## tapa el pelo] por pieza), con [tool] (la escena de su herramienta, o "") en la mano derecha, oculta,
## y con sus animaciones, fuera del árbol. Se puede llamar desde un hilo, de uno en uno
## (AppearanceCatalog ya cargado): el ajuste de la ropa sigue en el WorkerThreadPool y lo recoge el rig
## al entrar en el árbol.
static func build_model(who: Dictionary, pieces: Array, tool := "") -> Node3D:
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	var rig := model.get_node("AppearanceRig") as CharacterAppearanceRig
	var skeleton := model.get_node("Armature/Skeleton3D") as Skeleton3D
	var look := CharacterAppearance.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(who.get("look", 0))
	look.set_sex(StringName(who.get("sex", &"male")))
	look.randomize_values(rng, [], &"north")
	rig.apply(look)
	for piece: Array in pieces:
		var item := (load(String(piece[0])) as PackedScene).instantiate()
		skeleton.add_child(item)
		rig.dress(item, bool(piece[1]))
	if tool != "":
		hold(model, tool)
	var player := model.get_node("AnimationPlayer") as AnimationPlayer
	player.add_animation_library(&"village", load(ANIMS))
	return model


## Pone en la mano derecha del humano [model] (build_model) la escena [scene] (una herramienta o un arma,
## de las que van en metros en el marco de agarre), oculta, en lugar de lo que llevase; con "", nada. Lo
## que pone, o null.
static func hold(model: Node3D, scene: String) -> Node3D:
	var skeleton := model.get_node("Armature/Skeleton3D") as Skeleton3D
	var grip := skeleton.get_node_or_null("ToolHand/Grip") as Node3D
	if grip != null:
		var old := grip.get_node_or_null("Tool")
		if old != null:
			grip.remove_child(old)
			old.queue_free()
	if scene == "":
		return null
	if grip == null:
		var hand := BoneAttachment3D.new()
		hand.name = "ToolHand"
		hand.bone_name = HAND_BONE
		skeleton.add_child(hand)
		grip = Node3D.new()
		grip.name = "Grip"
		grip.transform = CombatPose.RIGHT_GRIP
		hand.add_child(grip)
	var item := (load(scene) as PackedScene).instantiate() as Node3D
	item.name = "Tool"
	item.visible = false
	grip.add_child(item)
	return item


## Lo pone en su poblado con su humano (build_model), donde le toca a esta hora. Antes de add_child.
func setup(who: Dictionary, home_village: SettlementVillage, model: Node3D) -> void:
	resident = who
	village = home_village
	name = "Villager_%s" % String(who.get("id", "")).replace(":", "_")
	_rng.seed = hash([who.get("look", 0), "routine"])
	add_to_group(GROUP)
	_model = model
	add_child(_model)
	_player = _model.get_node("AnimationPlayer") as AnimationPlayer
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_tool = _model.get_node_or_null("Armature/Skeleton3D/ToolHand/Grip/Tool") as Node3D
	_body = AnimatableBody3D.new()
	_body.collision_layer = BODY_LAYER
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = BODY_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, BODY_HEIGHT * 0.5, 0.0)
	_body.add_child(shape)
	add_child(_body)
	_frame = _rng.randi() % 8
	_greet_left = _rng.randf() * GREET_COOLDOWN * 0.3
	var h := village.hour()
	if _is_night(h):
		_sleep()
	elif village.danger:
		_sleep()
		_get_up()
		_hide()
	elif village.raining:
		_sleep()
		_get_up()
		_sheltered()
	else:
		_pos = village.plaza_spot(_rng)
		_forward = _tangent(village.center - _pos, _pos)
		_stand(_rng.randf_range(1.0, STAND_TIME.y))


func _ready() -> void:
	_player.play(_anim, 0.0, _anim_speed)
	if _inside < 0:
		_grounded = _follow_ground(GROUND_SEARCH)
	_pose()
	reset_physics_interpolation()


## Su sitio en el marco del terreno.
func local_position() -> Vector3:
	return _pos


## Si está de pie en la plaza sin hacer nada en concreto (se le puede proponer charlar).
func free_to_talk() -> bool:
	return act == Act.STAND and _inside < 0 and _partner == null and not village.danger


## El aldeano al que habla el jugador en [at] (mundo) mirando hacia [look]: el más a mano a menos de
## [reach] m y por delante, o null.
static func find(tree: SceneTree, at: Vector3, look: Vector3, reach := 2.6) -> Villager:
	return nearest(tree, GROUP, at, look, reach) as Villager


## Como find, entre los nodos del grupo [group] (los aldeanos, los compañeros: Companion.find).
static func nearest(tree: SceneTree, group: StringName, at: Vector3, look: Vector3, reach := 2.6) -> Node3D:
	var best: Node3D
	var best_score := INF
	for node in tree.get_nodes_in_group(group):
		var v := node as Node3D
		if v == null or not v.is_inside_tree():
			continue
		var to := v.global_position - at
		var up := v.global_basis.y
		var flat := to - up * to.dot(up)
		var d := flat.length()
		if d > reach or absf(to.dot(up)) > 2.0:
			continue
		var ahead := flat.normalized().dot((look - up * look.dot(up)).normalized()) if d > 0.3 else 1.0
		if ahead < 0.35:
			continue
		var score := d * (2.0 - ahead)
		if score < best_score:
			best = v
			best_score = score
	return best


## Si se le puede hablar ahora (dormido no).
func can_chat() -> bool:
	return act != Act.SLEEP


## El jugador le habla: deja lo que haga, se para y lo mira hasta end_chat. Falso si no puede.
func begin_chat() -> bool:
	if not can_chat():
		return false
	if act == Act.CHAT:
		return true
	_abort_leg()
	_waiting = false
	_striking = false
	_show_tool(false)
	_drop_partner()
	_before_wave = []
	act = Act.CHAT
	_left = INF
	_say_left = 0.0
	_play(ANIM_IDLE)
	return true


## Dice una frase: gesticula un rato.
func say() -> void:
	if act != Act.CHAT:
		return
	_say_left = SAY_TIME
	_play(ANIM_TALK)


## El jugador se va: vuelve a lo suyo.
func end_chat() -> void:
	if act == Act.CHAT:
		_greet_left = GREET_COOLDOWN
		_decide()


func is_chatting() -> bool:
	return act == Act.CHAT


## Se va con el jugador (SettlementCompanions): sale de su poblado y suelta su humano, que se lleva el
## compañero. Después se puede liberar.
func leave_with_player() -> Node3D:
	_abort_leg()
	_drop_partner()
	village.villagers.erase(self)
	act = Act.STAND
	var model := _model
	remove_child(model)
	_model = null
	set_process(false)
	set_physics_process(false)
	return model


## Ataca una fiera (SettlementVillage): deja lo que haga y corre a casa.
func alarm() -> void:
	if act != Act.SLEEP and act != Act.HIDE:
		_decide()


## Cambia el tiempo (SettlementVillage): si empieza a llover, quien no esté a cubierto corre a casa; si
## empieza a nevar, quien esté sentado fuera se levanta; si escampa, los de casa salen al poco.
func weather_turned() -> void:
	match act:
		Act.SLEEP, Act.HIDE, Act.CHAT:
			pass
		Act.SHELTER:
			if not village.raining:
				_left = minf(_left, _rng.randf_range(CLEAR_DELAY.x, CLEAR_DELAY.y))
		Act.WORK:
			if village.raining and _inside < 0:
				_decide()
		Act.SIT:
			if _inside < 0 and (village.raining or village.snowing):
				_decide()
		_:
			if village.raining:
				_decide()


func _physics_process(delta: float) -> void:
	_greet_left -= delta
	_look_left -= delta
	if _look_left <= 0.0:
		_look_left = LOOK_INTERVAL
		_watch_player()
	match act:
		Act.WALK:
			_walk(delta)
		Act.TALK:
			if _partner_lost():
				_decide()
			else:
				_face(_partner.local_position() - _pos, delta)
				_tick(delta, _end_talk)
		Act.WORK:
			_face(_look_at - _pos, delta)
			_strike(delta)
			_tick(delta, _decide)
		Act.WAVE:
			var at := village.player_local()
			if at.is_finite():
				_face(at - _pos, delta)
			_tick(delta, _end_wave)
		Act.CHAT:
			var at := village.player_local()
			if at.is_finite():
				_face(at - _pos, delta)
			_settle(delta)
			if _say_left > 0.0:
				_say_left -= delta
				if _say_left <= 0.0:
					_play(ANIM_IDLE)
		Act.HIDE, Act.SLEEP:
			_tick(delta, func() -> void:
				if village.danger or (act == Act.SLEEP and _is_night(village.hour())):
					_left = HIDE_CHECK if act == Act.HIDE else SLEEP_CHECK
				else:
					_decide())
		Act.SHELTER:
			_settle(delta)
			_tick(delta, func() -> void:
				if village.raining and not village.danger and not _is_night(village.hour()):
					_sheltered()
				else:
					_decide())
		_:
			_settle(delta)
			if act == Act.STAND and _eyeing and not _waiting:
				_face(_look_at - _pos, delta)
			if _waiting:
				if _partner_lost():
					_waiting = false
					_partner = null
				else:
					_face(_partner.local_position() - _pos, delta)
			_tick(delta, _decide)
	_pose()


func _tick(delta: float, then: Callable) -> void:
	_left -= delta
	if _left <= 0.0:
		then.call()


func _process(delta: float) -> void:
	_anim_accum += delta
	_frame += 1
	var stride := AnimationLod.stride_for(self, 1.0, AnimationLod.CREATURE_STRIDES)
	if _frame % stride == 0:
		_player.advance(_anim_accum)
		_anim_accum = 0.0


## Lo siguiente, según la hora, el tiempo y si ataca una fiera.
func _decide() -> void:
	var h := village.hour()
	_abort_leg()
	_waiting = false
	_striking = false
	_show_tool(false)
	_drop_partner()
	if village.danger:
		_flee()
		return
	if _is_night(h):
		if act != Act.SLEEP:
			var b: int = resident.home
			_go_to(village.bed_foot(b, resident.bed), b, _sleep)
		else:
			_left = SLEEP_CHECK
		return
	if act == Act.SLEEP:
		_get_up()
	var job: Dictionary = resident.get("job", {})
	var roll := _rng.randf()
	if village.raining:
		# Con lluvia solo se trabaja bajo techo; los demás, a casa.
		if not job.is_empty() and _work_hour(h) and roll < 0.85 and _indoor(village.workplace(job)):
			_go_work(job)
		else:
			_shelter()
	elif not job.is_empty() and _work_hour(h) and roll < 0.85:
		_go_work(job)
	elif village.snowing:
		# Con nieve nadie se sienta fuera: a casa, a calentarse a la hoguera o de pie en la plaza.
		var pick := _rng.randf()
		if pick < 0.45:
			_shelter()
		elif pick < 0.75:
			_go_to(village.ring_spot(_rng), -1, func() -> void:
				_forward = _tangent(village.center - _pos, _pos)
				_stand(_rng.randf_range(STAND_TIME.x, STAND_TIME.y) * 2.0))
		elif not _start_talk():
			_go_to(village.plaza_spot(_rng), -1, func() -> void:
				_stand(_rng.randf_range(STAND_TIME.x, STAND_TIME.y)))
	elif h >= LUNCH.x and h < LUNCH.y and roll < 0.8:
		var b: int = resident.home
		var spot := village.front_spot(b, _rng)
		_go_to(spot, -1, func() -> void:
			_forward = _tangent(village.homes[b].out as Vector3, _pos)
			_sit())
	elif _inside >= 0:
		# Sale y se queda delante un rato.
		var b := _inside
		_go_to(village.front_spot(b, _rng), -1, func() -> void:
			_stand(_rng.randf_range(STAND_TIME.x, STAND_TIME.y)))
	elif h >= EVENING_HOUR and roll < 0.6:
		_go_to(village.ring_spot(_rng), -1, func() -> void:
			_forward = _tangent(village.center - _pos, _pos)
			_sit())
	elif roll < 0.35 and _start_talk():
		pass
	elif roll < 0.6:
		_go_to(village.plaza_spot(_rng), -1, _sit)
	else:
		_go_to(village.plaza_spot(_rng), -1, func() -> void:
			_stand(_rng.randf_range(STAND_TIME.x, STAND_TIME.y)))


static func _is_night(h: float) -> bool:
	return h >= BED_HOUR or h < WAKE_HOUR


static func _work_hour(h: float) -> bool:
	for hours in WORK_HOURS:
		if h >= hours.x and h < hours.y:
			return true
	return false


## A su puesto ([job]: SettlementPopulation "job"), y a trabajar.
func _go_work(job: Dictionary) -> void:
	var work := village.workplace(job)
	var stand: Vector3 = (work.stands as PackedVector3Array)[job.stand]
	var look: Vector3 = (work.looks as PackedVector3Array)[job.stand]
	_go_to(stand, job.building if _indoor(work) else -1, func() -> void: _work(look))


## Si el sitio de trabajo [work] está dentro de su casa (en su suelo, no en el terreno).
func _indoor(work: Dictionary) -> bool:
	return StringName(work.kind) == &"bench"


func _stand(time: float) -> void:
	act = Act.STAND
	_left = time
	_play(ANIM_IDLE)


func _sit() -> void:
	act = Act.SIT
	_left = _rng.randf_range(SIT_TIME.x, SIT_TIME.y)
	_play(ANIM_SIT)


## Trabaja en su sitio mirando a [look]: el granjero cava; el leñador y el artesano, a golpes.
func _work(look: Vector3) -> void:
	act = Act.WORK
	_left = _rng.randf_range(WORK_TIME.x, WORK_TIME.y)
	_look_at = look
	_show_tool(true)
	if StringName(resident.job.kind) == &"garden":
		_striking = false
		_play(ANIM_DIG)
	else:
		_striking = true
		_strike_left = _rng.randf_range(0.2, 1.0)
		_play(ANIM_IDLE)


## A golpes: el golpe entero y, entre uno y otro, un respiro de pie.
func _strike(delta: float) -> void:
	if not _striking:
		return
	_strike_left -= delta
	if _strike_left > 0.0:
		return
	if _anim == ANIM_STRIKE:
		_play(ANIM_IDLE)
		_strike_left = _rng.randf_range(STRIKE_PAUSE.x, STRIKE_PAUSE.y)
	else:
		var speed := BENCH_STRIKE_SPEED if StringName(resident.job.kind) == &"bench" else 1.0
		_play(ANIM_STRIKE, speed, 0.15)
		_strike_left = _player.get_animation(ANIM_STRIKE).length / speed


## Busca pareja y van los dos a encontrarse a medio camino. Falso si no hay nadie libre.
func _start_talk() -> bool:
	var other := village.partner_for(self)
	if other == null:
		return false
	var mid := (_pos + other._pos) * 0.5
	var apart := _tangent(_pos - other._pos, mid)
	if apart == Vector3.ZERO:
		apart = _tangent(_forward, mid)
	_partner = other
	other._partner = self
	other._go_meet(mid - apart * TALK_GAP * 0.5)
	_go_meet(mid + apart * TALK_GAP * 0.5)
	return true


func _go_meet(spot: Vector3) -> void:
	_go_to(spot, -1, func() -> void:
		if _partner_lost():
			_partner = null
			_stand(_rng.randf_range(STAND_TIME.x, STAND_TIME.y))
		elif _partner.act == Act.STAND and _partner._waiting:
			var time := _rng.randf_range(TALK_TIME.x, TALK_TIME.y)
			_partner._talk(time)
			_talk(time)
		else:
			_stand(WAIT_PARTNER)
			_waiting = true)


func _talk(time: float) -> void:
	_waiting = false
	act = Act.TALK
	_left = time
	_play(ANIM_TALK)


func _end_talk() -> void:
	_drop_partner()
	_stand(_rng.randf_range(2.0, 6.0))


func _drop_partner() -> void:
	if _partner != null and is_instance_valid(_partner) and _partner._partner == self:
		_partner._partner = null
	_partner = null


func _partner_lost() -> bool:
	return _partner == null or not is_instance_valid(_partner) or _partner._partner != self


## Lo mira si está de pie y el jugador cerca, y a veces lo saluda (de pie o trabajando).
func _watch_player() -> void:
	_eyeing = false
	var at := village.player_local()
	if not at.is_finite() or village.danger:
		return
	var distance := _tangent_raw(at - _pos, _pos).length()
	if distance > GREET or distance < 0.8:
		return
	if _greet_left <= 0.0 and (act == Act.STAND or act == Act.WORK) and _partner == null:
		_greet_left = GREET_COOLDOWN
		_before_wave = [act, _left]
		act = Act.WAVE
		_left = WAVE_TIME
		_striking = false
		_show_tool(false)
		_play(ANIM_WAVE)
	elif act == Act.STAND and distance < FACE_PLAYER:
		_look_at = at
		_eyeing = true


## Vuelve a lo que hacía antes de saludar.
func _end_wave() -> void:
	var was: Act = _before_wave[0] if not _before_wave.is_empty() else Act.STAND
	var left: float = _before_wave[1] if not _before_wave.is_empty() else STAND_TIME.x
	_before_wave = []
	if was == Act.WORK and not resident.get("job", {}).is_empty():
		_work(_look_at if _look_at != Vector3.ZERO else _pos + _forward)
		_left = maxf(left, BREAK_TIME.x)
	else:
		_stand(maxf(left, 2.0))


## A su casa corriendo, y dentro se queda (HIDE) hasta que pase el peligro.
func _flee() -> void:
	var b: int = resident.home
	_go_to(village.bed_foot(b, resident.bed), b, _hide, RUN_SPEED)


func _hide() -> void:
	act = Act.HIDE
	_left = HIDE_CHECK
	_play(ANIM_IDLE)


## A cubierto del tiempo en su casa, a los pies de su lecho (con lluvia, corriendo: _go_to).
func _shelter() -> void:
	var b: int = resident.home
	_go_to(village.bed_foot(b, resident.bed), b, _sheltered)


## Ya en casa: de pie o sentado en el suelo, mirando a la puerta, hasta que escampe.
func _sheltered() -> void:
	var b: int = resident.home
	_forward = _tangent(village.homes[b].inside - _pos, _pos)
	act = Act.SHELTER
	_left = _rng.randf_range(SHELTER_TIME.x, SHELTER_TIME.y)
	_play(ANIM_SIT if _rng.randf() < 0.5 else ANIM_IDLE)


## Se tumba en su lecho.
func _sleep() -> void:
	var pose := village.bed(resident.home, resident.bed)
	_inside = resident.home
	act = Act.SLEEP
	_left = SLEEP_CHECK
	_pos = pose.origin + pose.origin.normalized() * BED_HEIGHT
	_forward = pose.basis.z
	_grounded = true
	_set_solid(false)
	_play(ANIM_SLEEP)
	reset_physics_interpolation()


## Se levanta del lecho: de pie a sus pies.
func _get_up() -> void:
	var b: int = resident.home
	_pos = village.bed_foot(b, resident.bed)
	_forward = _tangent(village.homes[b].inside - _pos, _pos)
	_set_solid(true)
	act = Act.STAND
	reset_physics_interpolation()


## Echa a andar hacia [to] (marco del terreno), que está en la casa [building] (o fuera: -1), por las
## puertas que hagan falta, y al llegar hace [then]. Si llueve y hay que pasar por fuera, corriendo.
func _go_to(to: Vector3, building: int, then: Callable, speed := WALK_SPEED) -> void:
	if village.raining and (_inside < 0 or _inside != building):
		speed = maxf(speed, RUN_SPEED)
	var points: Array = []
	var doors: Array = []
	var after: Array = []
	if _inside >= 0 and _inside != building:
		var here: Dictionary = village.homes[_inside]
		points.append_array([here.inside, here.outside])
		doors.append_array([-1, _inside])
		after.append_array([-2, -1])
	if building >= 0 and building != _inside:
		var there: Dictionary = village.homes[building]
		points.append_array([there.outside, there.inside])
		doors.append_array([-1, building])
		after.append_array([-2, building])
	points.append(to)
	doors.append(-1)
	after.append(-2)
	_go(points, doors, after, then, speed)


func _go(points: Array, doors: Array, after: Array, then: Callable, speed: float) -> void:
	act = Act.WALK
	_path = PackedVector3Array(points)
	_doors = PackedInt32Array(doors)
	_after = PackedInt32Array(after)
	_step = 0
	_arrive = then
	_speed = speed
	_probe_left = 0.0
	_grounded = false
	if speed > WALK_SPEED:
		_play(ANIM_RUN, speed / RUN_CLIP_SPEED)
	else:
		_play(ANIM_WALK, speed / WALK_CLIP_SPEED)
	_begin_leg()


func _begin_leg() -> void:
	if _doors[_step] >= 0:
		village.open_door(_doors[_step], self, _pos)


## Si lo cortan a medio cruzar una puerta, la suelta (que se cierre si nadie más la cruza).
func _abort_leg() -> void:
	if act == Act.WALK and _step < _doors.size() and _doors[_step] >= 0:
		village.release_door(_doors[_step], self)
	_doors = PackedInt32Array()
	_arrive = Callable()


func _walk(delta: float) -> void:
	var target := _path[_step]
	var to := _tangent_raw(target - _pos, _pos)
	var distance := to.length()
	if distance <= ARRIVE:
		if _doors[_step] >= 0:
			village.release_door(_doors[_step], self)
		if _after[_step] != -2:
			_inside = _after[_step]
		_step += 1
		if _step >= _path.size():
			_grounded = _follow_ground()
			_probe_left = 0.0
			var then := _arrive
			_arrive = Callable()
			_doors = PackedInt32Array()
			if then.is_valid():
				then.call()
			else:
				_stand(STAND_TIME.x)
			return
		_begin_leg()
		return
	var heading := to / distance
	# Fuera y sin cruzar una puerta, se aparta de quien tenga delante.
	if _inside < 0 and _doors[_step] < 0 and distance > AVOID:
		heading = _avoid(heading)
	_face(heading, delta)
	var move := heading * minf(_speed * delta, distance)
	var radius := _pos.length()
	_pos = (_pos + move).normalized() * radius
	_probe_left -= delta
	if _probe_left <= 0.0:
		_probe_left = PROBE_INTERVAL
		_follow_ground()


## [heading] torcido para no chocar con los demás, el jugador o la hoguera que tenga delante.
func _avoid(heading: Vector3) -> Vector3:
	var push := Vector3.ZERO
	var others: Array[Vector3] = []
	for v in village.villagers:
		if v != self and is_instance_valid(v) and v._inside < 0:
			others.append(v._pos)
	var player := village.player_local()
	if player.is_finite():
		others.append(player)
	if village.fire != null:
		others.append(village.center)
	for o in others:
		var away := _tangent_raw(_pos - o, _pos)
		var d := away.length()
		if d >= AVOID or d < 1e-4 or heading.dot(-away) <= 0.0:
			continue
		# De lado, hacia donde ya se aparta.
		var side := heading.cross(_pos.normalized())
		push += side * signf(side.dot(away) + 1e-3) * (AVOID - d) / AVOID
	if push == Vector3.ZERO:
		return heading
	return _tangent(heading + push * 1.5, _pos)


## Quieto fuera: busca el suelo si aún no lo tiene.
func _settle(delta: float) -> void:
	if _grounded or _inside >= 0:
		return
	_probe_left -= delta
	if _probe_left <= 0.0:
		_probe_left = GROUND_RETRY
		_grounded = _follow_ground(GROUND_SEARCH)


## Lo pega al suelo (terreno, suelos de las casas): un rayo de arriba abajo, desde [above] m sobre los
## pies. Sin nada debajo (lejos de la colisión del terreno), sigue a la misma altura: falso.
func _follow_ground(above := PROBE_UP) -> bool:
	if not is_inside_tree():
		return false
	var frame := village.frame()
	var up := _pos.normalized()
	var query := PhysicsRayQueryParameters3D.create(frame * (_pos + up * above),
		frame * (_pos - up * PROBE_DOWN), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	_pos = frame.affine_inverse() * (hit.position as Vector3)
	return true


func _face(direction: Vector3, delta: float) -> void:
	var want := _tangent(direction, _pos)
	if want == Vector3.ZERO:
		return
	var up := _pos.normalized()
	var angle := _forward.signed_angle_to(want, up)
	_forward = _forward.rotated(up, clampf(angle, -TURN_RATE * delta, TURN_RATE * delta))
	_forward = _tangent(_forward, _pos)


func _pose() -> void:
	if village == null:
		return
	var up := _pos.normalized()
	var forward := _tangent(_forward, _pos)
	if forward == Vector3.ZERO:
		forward = _tangent(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT, _pos)
	_forward = forward
	global_transform = village.frame() * Transform3D(Basis(up.cross(forward), up, forward), _pos)


func _set_solid(solid: bool) -> void:
	_body.collision_layer = BODY_LAYER if solid else 0


func _show_tool(shown: bool) -> void:
	if _tool != null:
		_tool.visible = shown


func _play(anim: StringName, speed := 1.0, blend := BLEND) -> void:
	if _anim == anim and is_equal_approx(_anim_speed, speed):
		return
	_anim = anim
	_anim_speed = speed
	# Fuera del árbol (setup) arranca en _ready.
	if is_inside_tree():
		_player.play(anim, blend, speed)


## [v] sobre el plano tangente en [at], unitario, o cero.
static func _tangent(v: Vector3, at: Vector3) -> Vector3:
	var t := _tangent_raw(v, at)
	return t.normalized() if t.length_squared() > 1e-10 else Vector3.ZERO


static func _tangent_raw(v: Vector3, at: Vector3) -> Vector3:
	var up := at.normalized()
	return v - up * v.dot(up)
