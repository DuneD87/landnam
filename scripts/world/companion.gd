class_name Companion extends CharacterBody3D

## Un aldeano que se ha ido con el jugador (SettlementCompanions): lleva el humano que tenía en su
## poblado y anda por el mundo con física, con la gravedad del planeta. Sigue al jugador (andando,
## corriendo o a la carrera según lo lejos que se quede, saltando si algo le corta el paso), lo espera
## donde se le diga o vuelve a casa. Si se queda muy atrás o atascado, aparece detrás del jugador. Se le
## habla como a un aldeano (VillagerChat).
##
## Lleva cosas en su morral (pack), que el jugador le da y le quita en la charla. Pelea: va a por lo que
## ataca al jugador o a él y por lo que ha herido el jugador, con la mejor arma que lleve (o la
## herramienta de su oficio, o los puños), y las fieras se le revuelven (Perception lo sigue viendo). Sin
## vida cae malherido y se levanta al rato; fuera de pelea se recupera poco a poco y come lo asado que
## lleve si le hace falta.
##
## Se le puede decir que se quede a vivir donde está (SETTLE): es un colono de la base del jugador. Hace
## vida allí: de día pasea cerca, al atardecer se sienta junto a una hoguera encendida (Campfire), de
## noche duerme en un petate libre (Bedroll) o, si no lo hay, en el suelo; y defiende la base de lo que
## ataque cerca. En su horario de trabajo hace lo que se le haya mandado (SettlerWork: talar, picar o
## limpiar una zona). Un árbol que le cae encima lo mata (crush). Ver docs/villagers.md.

enum Mode {FOLLOW, WAIT, LEAVE, SETTLE}
## Lo que hace en la base.
enum Chore {STAND, WALK, SIT, SLEEP}

const GROUP := &"companion"
## Siguiendo: se para a STOP m del jugador y echa a andar a más de START; a más de JOG_FROM m trota y
## a más de RUN_FROM corre, cada vez más deprisa hasta la carrera (SPRINT_FROM m). Por pasos y no
## subiendo poco a poco: cada animación casa con su velocidad (a ritmo 1, Villager.*_CLIP_SPEED).
const STOP := 2.2
const START := 3.5
const JOG_FROM := 7.0
const RUN_FROM := 10.0
const SPRINT_FROM := 15.0
const WALK_SPEED := 1.4
const JOG_SPEED := 2.4
const RUN_SPEED := 4.0
const SPRINT_SPEED := 8.0
const ACCEL := 12.0
const TURN_RATE := 6.0
## La animación por la velocidad real (m/s): trota por encima de GAITS.x y corre por encima de GAITS.y;
## para volver a la de abajo tiene que bajar GAIT_MARGIN más.
const GAITS := Vector2(2.0, 3.2)
const GAIT_MARGIN := 0.3
const JUMP_SPEED := 5.0
## En el suelo empuja hacia él a STICK m/s: sin eso, contra una pared de una construcción deja el suelo
## un tick sí y otro no.
const STICK := 0.5
## Atascado: avanzando a menos de STUCK_RATIO de lo que quiere, salta cada JUMP_EVERY s si lo que
## tiene delante es bajo (nada a WALL_HEIGHT m del suelo a WALL_REACH m por delante); contra una pared
## no salta: busca camino (steer). Si sigue así STUCK_TELEPORT s a más de STUCK_FAR m, aparece detrás
## del jugador. A más de TELEPORT m, también.
const STUCK_RATIO := 0.35
const JUMP_EVERY := 0.8
const WALL_HEIGHT := 1.3
const WALL_REACH := 0.6
const STUCK_TELEPORT := 4.0
const STUCK_FAR := 8.0
const TELEPORT := 50.0
## Dónde aparece: a esto (m) del jugador, por detrás, o girando estos grados si ahí no cabe.
const BEHIND := 2.5
const TELEPORT_ANGLES: Array[float] = [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]
## A más de esto (m) del jugador no se mueve ni cae: por allí el terreno no tiene colisión.
const FREEZE := 120.0
## Sin suelo a menos de PROBE_DEPTH m por debajo (aún no ha llegado la colisión) no cae; se mira cada
## PROBE_INTERVAL s.
const PROBE_DEPTH := 60.0
const PROBE_INTERVAL := 0.25
## Esperando, se sienta al rato (s).
const SIT_AFTER := 25.0
## Lo mira a menos de esto (m) si está quieto.
const FACE_PLAYER := 6.0
## Volviendo a casa: se va del todo a más de LEAVE_GONE m del jugador o a los LEAVE_TIME s.
const LEAVE_GONE := 35.0
const LEAVE_TIME := 45.0
## Lo que aguanta, los huecos de su morral y lo que cuenta la protección de su ropa (no la lleva por
## partes, como el jugador: se suma toda).
const MAX_HEALTH := 100.0
const PACK_SLOTS := 12
const ARMOR_SHARE := 0.4
## Pelea con lo que ataca al jugador o a él a menos de ENGAGE m del jugador (esperando, de sí mismo), y
## con lo que el jugador ha herido; lo deja si se aleja más de LEASH m. Se mira cada SCAN_INTERVAL s.
const ENGAGE := 20.0
const LEASH := 30.0
const SCAN_INTERVAL := 0.3
## Golpea al DAMAGE_SCALE de lo que haría el jugador con lo mismo (sin arma, FIST_DAMAGE; nunca menos),
## a ATTACK_SPEED del ritmo del golpe del jugador (MeleeMoveset) y con un respiro de ATTACK_PAUSE s entre
## golpe y golpe. Llega a la fiera con el brazo y lo que mide el arma (ARM más reach).
const DAMAGE_SCALE := 0.8
const FIST_DAMAGE := 6.0
const ARM := 0.45
const ATTACK_SPEED := 1.3
const ATTACK_PAUSE := Vector2(0.4, 1.1)
## El arma se ve mientras pelea y hasta ARMED_TIME s después.
const ARMED_TIME := 5.0
## Lo que dura el respingo al encajar un golpe (s; a mitad de golpe no se inmuta).
const FLINCH_TIME := 0.45
## Sin vida cae malherido: se levanta a los DOWN_TIME s con RISE_HEALTH de su vida.
const DOWN_TIME := 25.0
const RISE_HEALTH := 0.4
## Fuera de pelea, a los REGEN_AFTER s del último golpe recupera REGEN por segundo; y por debajo de
## EAT_BELOW de su vida come, cada EAT_EVERY s, algo de lo que lleva: lo asado cura HEAL_FOOD, un remedio
## HEAL_REMEDY.
const REGEN_AFTER := 8.0
const REGEN := 0.5
const EAT_BELOW := 0.5
const EAT_EVERY := 6.0
const HEAL_FOOD := 25.0
const HEAL_REMEDY := 40.0
## Viviendo en la base: sus petates y hogueras son los que hay a menos de BASE_RADIUS m del sitio que se
## le dio; de día pasea a menos de ROAM m de él y al atardecer se sienta alrededor de la hoguera (a
## FIRE_RING m). Llega a un sitio a menos de ARRIVE m. Pelea con lo que ataca a menos de DEFEND m de la
## base.
const BASE_RADIUS := 40.0
const ROAM := 10.0
const FIRE_RING := Vector2(1.6, 2.4)
const ARRIVE := 0.6
const DEFEND := 25.0
## Caminos (steer): si en REPATH s no se acerca al menos PROGRESS m a donde va (o al siguiente punto del
## camino), busca un camino (GroundPath), como mucho PATH_TRIES veces por destino; llega a cada punto a
## menos de WAYPOINT m. Abre las puertas cerradas a menos de DOOR_OPEN m por las que pasa y las cierra
## al quedar a más de DOOR_CLOSE m.
## Gastados los intentos, vuelve a probar a los PATH_RETRY s si sigue sin acercarse.
const REPATH := 1.5
const PROGRESS := 0.3
const PATH_TRIES := 3
const PATH_RETRY := 8.0
const WAYPOINT := 0.6
const DOOR_OPEN := 1.6
const DOOR_CLOSE := 2.5
## Aplastado por un árbol: se queda en el suelo GONE_TIME s y se va.
const GONE_TIME := 60.0
## En formación (SettlementCompanions.slot_of): echa a andar a más de SLOT_START m de su hueco y se para a
## menos de SLOT_STOP con el jugador quieto. Va al paso del jugador y, si se queda atrás, más deprisa
## (SLOT_GAIN por metro; al menos al trote a más de SLOT_JOG m y corriendo a más de SLOT_RUN, hasta la
## carrera a SLOT_SPRINT). Si en
## SLOT_GIVE_UP s no se acerca al hueco (cae dentro de una pared) estando a menos de SLOT_NEAR m del
## jugador, se queda donde está hasta que el hueco se mueva SLOT_MOVED m. Se aparta de otro del grupo a
## menos de APART m.
const SLOT_START := 1.2
const SLOT_STOP := 0.5
const SLOT_JOG := 3.0
const SLOT_RUN := 6.0
const SLOT_SPRINT := 12.0
## Fuera de su hueco va al paso del jugador más SLOT_GAIN m/s por cada metro que le falta.
const SLOT_GAIN := 1.2
const SLOT_GIVE_UP := 1.5
const SLOT_NEAR := 7.0
const SLOT_MOVED := 1.5
const APART := 0.9
## A la orden: a por la fiera que se le marca hasta ORDER_LEASH m del jugador; en retirada no pelea
## RETREAT_TIME s y vuelve corriendo.
const ORDER_LEASH := 60.0
const RETREAT_TIME := 12.0
## Mandado a su base desde lejos (homing): va derecho a ella, trotando, hasta quedar a HOME_NEAR m; fuera
## de la vista del jugador (FREEZE) llega cuando habría llegado andando.
const HOME_NEAR := 12.0
const ANIM_HIT := &"combat/hit_react"
const ANIM_DOWN := &"combat/death"

## SettlementPopulation.residents: "id", "name", "sex", "job"...
var resident: Dictionary
## Su poblado (índice en el campo de poblados), su nombre y la confianza (la de SettlementManager).
var village := -1
var village_name := ""
var relations: SettlementRelations
var mode := Mode.FOLLOW
## Viviendo en la base: su sitio, en el marco del terreno (Vector3.INF si no).
var base := Vector3.INF
## La del planeta (PlanetLoader.gravity_strength).
var gravity := 9.8
## Lo que lleva (se guarda con él) y su vida (la buscan las fieras y los golpes por su nombre).
var pack: Inventory
## El morral, con el nombre con el que la tala y la picada dan lo que sacan (DroppedItem.give).
var inventory: Inventory
var health: HealthComponent
## Lo que hace en su horario de trabajo (viviendo en la base), y su hambre (allí come de los cofres).
var work: SettlerWork
var meals: SettlerMeals
## Hasta dónde va (m, desde lo que guarda) a por la fiera que se le marca: el cazador, hasta más allá
## de su zona.
var order_leash := ORDER_LEASH
## La base y el trabajo (SettlerWork.save_data) que dejó al irse con el jugador: a ellos vuelve
## (return_to_base). Vector3.INF si no vivía en ninguna.
var return_base := Vector3.INF
var return_work := {}
## Muerto (aplastado): no se guarda y se va a los GONE_TIME s.
var dead := false
var _gone_left := 0.0

var _terrain: Node3D
var _player: Node3D
## El centro de su poblado, en el marco del terreno (hacia donde vuelve).
var _home := Vector3.ZERO
var _model: Node3D
var _anim_player: AnimationPlayer
var _anim := &""
var _forward := Vector3.FORWARD
## 0 anda, 1 trota, 2 corre.
var _gait := 0
var _moving := false
var _stuck := 0.0
var _jump_left := 0.0
var _jump := false
var _idle := 0.0
var _leave_time := 0.0
var _chatting := false
var _say_left := 0.0
var _ground := true
var _probe_left := 0.0
var _rng := RandomNumberGenerator.new()
var _hurtbox: Hurtbox
## Con lo que pelea (null: los puños), lo que tiene en la mano y lo que le queda a la vista.
var _weapon: ItemData
var _tool: Node3D
var _armed_left := 0.0
## La fiera con la que pelea, o null.
var _target: NPCController
var _scan_left := 0.0
## El golpe: lo que le queda a la animación, cuándo llega (s, −1 ya ha llegado) y el respiro.
var _attack_left := 0.0
var _hit_at := -1.0
var _pause_left := 0.0
var _flinch_left := 0.0
## Malherido: lo que le queda en el suelo.
var _down_left := 0.0
var _since_hit := INF
var _eat_left := 0.0
var _shape: CollisionShape3D
## En la base: lo que hace, lo que le queda, adónde va andando (marco del terreno) y qué hará al llegar,
## hacia dónde mira sentado (la hoguera, marco del terreno) y su petate.
var _chore := Chore.STAND
var _chore_left := 0.0
var _spot := Vector3.ZERO
var _then := Chore.STAND
var _look := Vector3.INF
var _bed: Bedroll
## Acostarse, dormir y levantarse (las animaciones encadenadas); y lo que falta para volver a apoyarse
## en el petate, dormido y quieto (s).
var _sleep_routine: SleepRoutine
var _bed_fit_left := 0.0
## El camino de ahora (puntos, marco del terreno), por cuál va, a dónde (marco del terreno), lo más cerca
## que ha llegado del punto al que va, lo que le queda para buscar otro, los intentos y las puertas que
## ha abierto.
var _path := PackedVector3Array()
var _path_index := 0
var _path_dest := Vector3.INF
var _steer_best := INF
var _steer_left := REPATH
var _path_tries := 0
var _opened_doors: Array[WoodenDoor] = []
## A la orden: la fiera se la ha marcado el jugador (order_attack), y lo que le queda de retirada (s).
var _ordered := false
var _retreat_left := 0.0
## En formación: lo más cerca que ha llegado de su hueco, lo que le queda para darlo por imposible y el
## hueco (marco del terreno) que dejó por imposible.
var _slot_best := INF
var _slot_left := SLOT_GIVE_UP
var _slot_held := Vector3.INF
## De vuelta a su base (return_to_base) y lo que lleva andado (s) fuera de la vista del jugador.
var homing := false
var _travel := 0.0


## [who]: su vecino (SettlementPopulation.residents) del poblado [v] ([v_name]); [model]: su humano
## vestido (Villager.build_model o el del aldeano); [home]: el centro del poblado en el marco del
## terreno [terrain].
func setup(who: Dictionary, v: int, v_name: String, trust: SettlementRelations, model: Node3D,
		terrain: Node3D, player: Node3D, home: Vector3) -> void:
	resident = who
	village = v
	village_name = v_name
	relations = trust
	_terrain = terrain
	_player = player
	_home = home
	name = "Companion_%s" % String(who.get("id", "")).replace(":", "_")
	add_to_group(GROUP)
	collision_layer = Villager.BODY_LAYER
	collision_mask = PhysicsLayers.WORLD
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = Villager.BODY_RADIUS
	capsule.height = Villager.BODY_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, Villager.BODY_HEIGHT * 0.5, 0.0)
	add_child(shape)
	_shape = shape
	_model = model
	_model.transform = Transform3D.IDENTITY
	add_child(_model)
	_anim_player = _model.get_node("AnimationPlayer") as AnimationPlayer
	_anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	# Los golpes, el respingo y la caída, los del jugador.
	if not _anim_player.has_animation_library(&"combat") and ResourceLoader.exists(PlayerCombat.COMBAT_LIBRARY):
		_anim_player.add_animation_library(&"combat", load(PlayerCombat.COMBAT_LIBRARY))
	_tool = _model.get_node_or_null("Armature/Skeleton3D/ToolHand/Grip/Tool") as Node3D
	(_model.get_node("Armature/Skeleton3D") as Skeleton3D).skeleton_updated.connect(_on_skeleton_updated)
	_sleep_routine = SleepRoutine.new(_anim_player, hash([who.get("look", 0), "sleep"]),
		_model.get_node_or_null("AppearanceRig") as CharacterAppearanceRig)
	if _tool != null:
		_tool.visible = false
	_rng.seed = hash([who.get("look", 0), "companion"])
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = MAX_HEALTH
	var armor := _outfit_armor()
	health.armor_slash = armor.x
	health.armor_blunt = armor.y
	health.armor_pierce = armor.z
	health.hit_received.connect(_on_hit)
	health.died.connect(_on_down)
	add_child(health)
	_hurtbox = Hurtbox.attach(self, self, capsule, shape.transform, &"body")
	_hurtbox.health = health
	pack = Inventory.new(PACK_SLOTS)
	pack.name = "Pack"
	add_child(pack)
	pack.inventory_changed.connect(refresh_weapon)
	inventory = pack
	meals = SettlerMeals.new(self)
	work = SettlerWork.new(self)
	# La herramienta que ya trae en la mano (build_model) es la de su oficio.
	_weapon = _job_tool() if _tool != null else null
	refresh_weapon()


func _ready() -> void:
	_forward = _tangent(global_basis.z)
	if _forward == Vector3.ZERO:
		_forward = _tangent(Vector3.FORWARD)
	_play(Villager.ANIM_IDLE, 0.0)


func _exit_tree() -> void:
	# Libera reservas y rompe el ciclo SettlerWork -> SettlerTask -> SettlerWork, también al
	# cargar otra partida o retirar el planeta (no solo al morir o cambiar de oficio).
	if work != null:
		work.stop()


## Se queda donde está hasta que se le diga que siga.
func wait_here() -> void:
	_leave_base()
	mode = Mode.WAIT
	_idle = 0.0


func follow() -> void:
	_leave_base()
	mode = Mode.FOLLOW
	_idle = 0.0
	_slot_held = Vector3.INF


## Si tiene una base a la que volver (la que dejó para irse con el jugador).
func has_return_base() -> bool:
	return return_base.is_finite()


## Vuelve a vivir a la base que dejó, con el trabajo que tenía. Falso si no tenía ninguna.
func return_to_base() -> bool:
	if not return_base.is_finite() or dead or mode == Mode.LEAVE:
		return false
	var job := return_work
	settle_here(return_base)
	work.restore(job)
	homing = true
	return true


## A la orden del jugador: a por [creature]. Falso si no puede (malherido, se va) o no vale.
func order_attack(creature: NPCController) -> bool:
	if dead or _down_left > 0.0 or mode == Mode.LEAVE or not _alive(creature):
		return false
	_retreat_left = 0.0
	_chatting = false
	_target = creature
	_ordered = true
	_show_weapon()
	_to_arms()
	return true


## A la orden del jugador: deja la pelea y, si lo acompaña, vuelve con él corriendo.
func order_retreat() -> void:
	_target = null
	_ordered = false
	_retreat_left = RETREAT_TIME


## Si pelea ahora.
func is_fighting() -> bool:
	return _target != null


## Se queda a vivir donde está (o en [at], marco del terreno: al cargar).
func settle_here(at := Vector3.INF) -> void:
	# Dormido, se levanta antes (si no, se quedaría de pie sin colisión y se hundiría).
	_wake()
	mode = Mode.SETTLE
	base = at if at.is_finite() else _terrain.global_transform.affine_inverse() * global_position
	return_base = Vector3.INF
	return_work = {}
	homing = false
	_travel = 0.0
	_rest(Chore.STAND, 2.0)


## Se vuelve a su poblado: echa a andar hacia allí y se va del todo al perderse de vista
## (SettlementCompanions lo quita al salir del árbol).
func go_home() -> void:
	_leave_base()
	mode = Mode.LEAVE
	_leave_time = 0.0


## Se le puede hablar si no se va, no pelea, no está malherido y no duerme.
func can_chat() -> bool:
	return not dead and mode != Mode.LEAVE and _target == null and _down_left <= 0.0 and _chore != Chore.SLEEP


## Al cargar: la vida que tenía (si cayó, la de levantarse).
func restore_health(value: float) -> void:
	if value < 0.0:
		return
	health.health = clampf(maxf(value, MAX_HEALTH * RISE_HEALTH), 0.0, MAX_HEALTH)
	health.health_changed.emit(health.health, health.max_health)


## Dónde se le mira al buscarlo con la vista (Perception): el pecho.
func get_lock_point() -> Vector3:
	return global_position + global_basis.y * Villager.BODY_HEIGHT * 0.65


## Con qué pelea: lo mejor que lleve para golpear o, si no, la herramienta de su oficio (o nada: los
## puños). Lo pone en la mano.
func refresh_weapon() -> void:
	var best := _job_tool()
	var best_damage := float(best.damage) if best != null else 0.0
	for item in pack.get_all_items():
		if item != null and _strikes_with(item.data) and float(item.data.damage) > best_damage:
			best = item.data
			best_damage = float(item.data.damage)
	if best == _weapon and (best == null or _tool != null):
		return
	_weapon = best
	_tool = Villager.hold(_model, best.scene_path if best != null else "")
	if _tool != null:
		_tool.visible = _armed_left > 0.0


## El jugador le habla: se para y lo mira hasta end_chat.
func begin_chat() -> bool:
	if not can_chat():
		return false
	_chatting = true
	_say_left = 0.0
	_play(Villager.ANIM_IDLE)
	return true


## Dice una frase: gesticula un rato.
func say() -> void:
	if not _chatting:
		return
	_say_left = Villager.SAY_TIME
	_play(Villager.ANIM_TALK)


func end_chat() -> void:
	_chatting = false
	_idle = 0.0


func is_chatting() -> bool:
	return _chatting


## Hacia dónde mira (tangente, mundo).
func facing() -> Vector3:
	return _forward


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _terrain == null \
			or GameManager.current_state != GameManager.State.PLAYING:
		return
	var up := (global_position - _terrain.global_position).normalized()
	up_direction = up
	var to_player := _player.global_position - global_position
	var distance := (to_player - up * to_player.dot(up)).length()
	_since_hit += delta
	if dead:
		_gone_left -= delta
		_move(Vector3.ZERO, 0.0, up, delta)
		_pose(up)
		if _gone_left <= 0.0:
			queue_free()
		return
	if _down_left > 0.0:
		_lie(up, delta)
		return
	# La fiera puede haberse ido del árbol (un cadáver suelto se libera).
	if _target != null and not is_instance_valid(_target):
		_target = null
	if not _chatting:
		_scan_left -= delta
		if _scan_left <= 0.0:
			_scan_left = SCAN_INTERVAL
			_scan(distance)
	if _armed_left > 0.0 and _target == null:
		_armed_left -= delta
		if _armed_left <= 0.0 and _tool != null:
			_tool.visible = false
	# Siguiendo, primero intenta aparecer junto al jugador (al que, por ejemplo, ha reaparecido lejos).
	if mode == Mode.FOLLOW and not _chatting and _target == null and distance > TELEPORT and _teleport():
		return
	if _retreat_left > 0.0:
		_retreat_left -= delta
	if mode == Mode.SETTLE:
		meals.tick(delta)
	if distance > FREEZE and mode != Mode.LEAVE:
		velocity = Vector3.ZERO
		if mode == Mode.SETTLE and not _travel_home(delta):
			work.away(delta, _hour())
		return
	if _target == null:
		_recover(delta)
	# El golpe sigue hasta el final aunque la fiera caiga o se vaya.
	if _attack_left > 0.0:
		_attack_left -= delta
		if _hit_at >= 0.0:
			_hit_at -= delta
			if _hit_at < 0.0:
				_land_hit(up)

	var heading := Vector3.ZERO
	var speed := 0.0
	if _flinch_left > 0.0:
		_flinch_left -= delta
	elif _target != null:
		var step := _fight(up, delta)
		heading = step[0]
		speed = step[1]
	elif _chatting:
		_face(to_player, delta)
		if _say_left > 0.0:
			_say_left -= delta
			if _say_left <= 0.0:
				_play(Villager.ANIM_IDLE)
	else:
		match mode:
			Mode.FOLLOW:
				var step := _follow(to_player, distance, up, delta)
				heading = step[0]
				speed = step[1]
			Mode.LEAVE:
				_leave_time += delta
				if distance > LEAVE_GONE or _leave_time > LEAVE_TIME:
					queue_free()
					return
				heading = _tangent(_terrain.global_transform * _home - global_position)
				speed = WALK_SPEED
			Mode.SETTLE:
				var step := _live(delta)
				heading = step[0]
				speed = step[1]
	# Tumbado en el petate (o en el suelo) no se mueve ni choca.
	if _chore == Chore.SLEEP:
		velocity = Vector3.ZERO
		_moving = false
		_pose(up)
		_animate()
		return
	_moving = speed > 0.0
	_move(heading, speed, up, delta)
	if _moving:
		_face(heading, delta)
		_unstick(heading, speed, distance, delta)
	elif _target != null:
		_stuck = 0.0
	elif not _chatting:
		_stuck = 0.0
		_idle += delta
		# Trabajando mira a lo que golpea, no al jugador.
		if distance < FACE_PLAYER and (mode != Mode.SETTLE or _chore == Chore.STAND) and not work.busy():
			_face(to_player, delta)
	_pose(up)
	_animate()


## Un paso siguiendo al jugador: [hacia dónde, a qué velocidad]. Con formación (cuña o fila) va a su
## hueco, al paso del jugador y más deprisa si se queda atrás; suelto (o en retirada), hacia el jugador
## como siempre. Se aparta de los otros del grupo.
func _follow(to_player: Vector3, distance: float, up: Vector3, delta: float) -> Array:
	var party := _party()
	var slot := party.slot_of(self) if party != null and _retreat_left <= 0.0 else Vector3.INF
	var heading := Vector3.ZERO
	var speed := 0.0
	if not slot.is_finite():
		var stop := STOP + (party.loose_margin(self) if party != null else 0.0)
		if distance > stop + (START - STOP) or (_moving and distance > stop):
			heading = _tangent(to_player)
			if _retreat_left > 0.0:
				speed = remap(clampf(distance, stop, SPRINT_FROM), stop, SPRINT_FROM, RUN_SPEED, SPRINT_SPEED)
			elif distance < JOG_FROM:
				speed = WALK_SPEED
			elif distance < RUN_FROM:
				speed = JOG_SPEED
			else:
				speed = remap(minf(distance, SPRINT_FROM), RUN_FROM, SPRINT_FROM, RUN_SPEED, SPRINT_SPEED)
	else:
		var to_local := _terrain.global_transform.affine_inverse()
		var slot_local := to_local * slot
		# El hueco que dio por imposible sigue ahí: quieto.
		if _slot_held.is_finite():
			if _slot_held.distance_to(slot_local) < SLOT_MOVED:
				return [Vector3.ZERO, 0.0]
			_slot_held = Vector3.INF
			_slot_best = INF
			_slot_left = SLOT_GIVE_UP
		var d := (slot - global_position).slide(up).length()
		var body := _player as CharacterBody3D
		var pace := body.get_real_velocity().slide(up).length() if body != null else 0.0
		if d > SLOT_START or (_moving and (d > SLOT_STOP or pace > 0.3)):
			heading = steer(slot, SLOT_STOP * 0.8, delta)
			var catch_up := WALK_SPEED
			if d > SLOT_RUN:
				catch_up = remap(minf(d, SLOT_SPRINT), SLOT_RUN, SLOT_SPRINT, RUN_SPEED, SPRINT_SPEED)
			elif d > SLOT_JOG:
				catch_up = JOG_SPEED
			# Al paso del jugador y, fuera del hueco, más deprisa cuanto más lejos.
			speed = minf(maxf(catch_up, pace + d * SLOT_GAIN), SPRINT_SPEED) if d > SLOT_STOP \
				else minf(pace, SPRINT_SPEED)
			if d < _slot_best - PROGRESS:
				_slot_best = d
				_slot_left = SLOT_GIVE_UP
			else:
				_slot_left -= delta
				if _slot_left <= 0.0 and distance < SLOT_NEAR and pace < 0.3:
					_slot_held = slot_local
					return [Vector3.ZERO, 0.0]
		else:
			_slot_best = INF
			_slot_left = SLOT_GIVE_UP
	if speed > 0.0 and party != null:
		var push := party.apart_from(self, up)
		if push != Vector3.ZERO:
			heading = _tangent(heading + push * 0.7)
	return [heading, speed]


func _party() -> SettlementCompanions:
	return get_tree().get_first_node_in_group(SettlementCompanions.GROUP) as SettlementCompanions


## Fuera de la vista del jugador y lejos de su base: «anda» hacia ella y aparece allí cuando habría
## llegado. Cierto mientras va de camino (aún no trabaja).
func _travel_home(delta: float) -> bool:
	if not homing or not base.is_finite():
		return false
	var home := _terrain.global_transform * base
	var far := global_position.distance_to(home)
	_travel += delta
	if far > HOME_NEAR and _travel * WALK_SPEED < far:
		return true
	homing = false
	_travel = 0.0
	if far <= HOME_NEAR:
		return false
	global_position = home + (home - _terrain.global_position).normalized() * 0.1
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	return false


## La velocidad de este paso: en el plano, hacia [heading] a [speed]; en vertical, la gravedad (si hay
## suelo debajo: si no, espera a que llegue su colisión).
func _move(heading: Vector3, speed: float, up: Vector3, delta: float) -> void:
	var vertical := up * velocity.dot(up)
	var flat := velocity - vertical
	flat = flat.move_toward(heading * speed, ACCEL * delta)
	if _jump and is_on_floor():
		vertical = up * JUMP_SPEED
	elif is_on_floor():
		vertical = -up * STICK
		_ground = true
	else:
		_probe_left -= delta
		if _probe_left <= 0.0:
			_probe_left = PROBE_INTERVAL
			_ground = _ground_below(up)
		if _ground:
			vertical -= up * gravity * delta
		else:
			vertical = Vector3.ZERO
			flat = Vector3.ZERO
	_jump = false
	velocity = flat + vertical
	move_and_slide()


## Si avanza mucho menos de lo que quiere: salta (un escalón, un bloque) y, si no sale de ahí y está
## lejos, aparece detrás del jugador.
func _unstick(heading: Vector3, speed: float, distance: float, delta: float) -> void:
	if get_real_velocity().dot(heading) >= speed * STUCK_RATIO:
		_stuck = maxf(_stuck - delta * 2.0, 0.0)
		return
	_stuck += delta
	_jump_left -= delta
	if is_on_floor() and _jump_left <= 0.0 and _stuck > 0.25:
		_jump_left = JUMP_EVERY
		if _wall_ahead(heading):
			_steer_left = minf(_steer_left, 0.0)
		else:
			_jump = true
	if mode == Mode.FOLLOW and _target == null and _stuck > STUCK_TELEPORT and distance > STUCK_FAR and _teleport():
		_stuck = 0.0


## Si delante (hacia [heading]) hay algo a WALL_HEIGHT m del suelo: una pared, no un escalón.
func _wall_ahead(heading: Vector3) -> bool:
	var from := global_position + up_direction * WALL_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, from + heading * (Villager.BODY_RADIUS + WALL_REACH),
		PhysicsLayers.WORLD, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Aparece a BEHIND m del jugador, por detrás de hacia donde va (o del lado por el que viene él), en
## un sitio a la vista del jugador y con suelo. Falso si no hay ninguno.
func _teleport() -> bool:
	var space := get_world_3d().direct_space_state
	var up := (_player.global_position - _terrain.global_position).normalized()
	var chest := _player.global_position + up * 1.2
	var body := _player as CharacterBody3D
	var back := _tangent(-body.velocity) if body != null else Vector3.ZERO
	if back == Vector3.ZERO:
		back = _tangent(global_position - _player.global_position)
	if back == Vector3.ZERO:
		back = _tangent(Vector3.FORWARD)
	# Cada uno del grupo prueba primero un ángulo distinto: no aparecen todos en el mismo sitio.
	var party := _party()
	var first := maxi(party.follower_index(self), 0) if party != null else 0
	for i in TELEPORT_ANGLES.size():
		var angle := TELEPORT_ANGLES[(i + first) % TELEPORT_ANGLES.size()]
		var spot := chest + back.rotated(up, deg_to_rad(angle)) * BEHIND
		var clear := PhysicsRayQueryParameters3D.create(chest, spot, PhysicsLayers.WORLD)
		if not space.intersect_ray(clear).is_empty():
			continue
		var down := PhysicsRayQueryParameters3D.create(spot, spot - up * 4.0, PhysicsLayers.WORLD)
		var hit := space.intersect_ray(down)
		if hit.is_empty():
			continue
		global_position = hit.position as Vector3 + up * 0.05
		velocity = Vector3.ZERO
		_forward = _tangent(_player.global_position - global_position)
		_ground = true
		reset_physics_interpolation()
		return true
	return false


func _ground_below(up: Vector3) -> bool:
	var from := global_position + up * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from - up * PROBE_DEPTH, PhysicsLayers.WORLD)
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _face(direction: Vector3, delta: float) -> void:
	var want := _tangent(direction)
	if want == Vector3.ZERO:
		return
	var up := up_direction
	var angle := _forward.signed_angle_to(want, up)
	_forward = _tangent(_forward.rotated(up, clampf(angle, -TURN_RATE * delta, TURN_RATE * delta)))


func _pose(up: Vector3) -> void:
	var forward := _tangent(_forward)
	if forward == Vector3.ZERO:
		forward = _tangent(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT)
	_forward = forward
	global_basis = Basis(up.cross(forward), up, forward)


## Andar o correr a la velocidad a la que va; quieto, de pie o (esperando un rato) sentado. El golpe, el
## respingo y la caída los pone quien los empieza.
func _animate() -> void:
	if _chatting or _attack_left > 0.0 or _flinch_left > 0.0:
		return
	var up := up_direction
	var real := get_real_velocity()
	var speed := (real - up * real.dot(up)).length()
	if _moving and speed > 0.15:
		var gait := 2 if speed > GAITS.y else (1 if speed > GAITS.x else 0)
		if gait < _gait and speed > GAITS[gait] - GAIT_MARGIN:
			gait = _gait
		_gait = gait
		match gait:
			0:
				_play(Villager.ANIM_WALK)
				_anim_player.speed_scale = speed / Villager.WALK_CLIP_SPEED
			1:
				_play(Villager.ANIM_JOG)
				_anim_player.speed_scale = speed / Villager.JOG_CLIP_SPEED
			_:
				_play(Villager.ANIM_RUN)
				_anim_player.speed_scale = speed / Villager.RUN_CLIP_SPEED
		return
	_anim_player.speed_scale = 1.0
	var sitting := (mode == Mode.WAIT and _idle > SIT_AFTER) or (mode == Mode.SETTLE and _chore == Chore.SIT)
	if _target != null:
		_play(Villager.ANIM_IDLE)
	elif _chore == Chore.SLEEP:
		pass  # SleepRoutine
	else:
		_play(Villager.ANIM_SIT if sitting else Villager.ANIM_IDLE)


func _play(anim: StringName, blend := Villager.BLEND, again := false) -> void:
	if _anim == anim and not again:
		return
	_anim = anim
	_anim_player.speed_scale = 1.0
	_anim_player.play(anim, blend)
	if again:
		_anim_player.seek(0.0, true)


# --- Pelea ----------------------------------------------------------------------------------------

## Lo que guarda (el jugador; esperando, él mismo; viviendo en la base, la base): de ahí se mide lo que
## está a tiro.
func _guard_point() -> Vector3:
	match mode:
		Mode.WAIT:
			return global_position
		Mode.SETTLE:
			return work.guard_point()
	return _player.global_position


## Sigue con la que tiene si aún vale la pena, o busca otra.
func _scan(player_distance: float) -> void:
	if mode == Mode.LEAVE or _retreat_left > 0.0:
		_target = null
		_ordered = false
		return
	if _target != null and not _worth_chasing(_target, player_distance):
		_target = null
	if _target == null:
		_ordered = false
	if _target == null:
		_target = _pick()
		if _target != null:
			_show_weapon()
			_to_arms()
			if mode == Mode.SETTLE:
				work.on_engage(_target)


func _worth_chasing(creature: NPCController, player_distance: float) -> bool:
	var leash := order_leash if _ordered else LEASH
	# El guardia vigila una zona mayor: no suelta lo que aún está en ella.
	if mode == Mode.SETTLE:
		leash = maxf(leash, work.defend_radius() + 5.0)
	if not _alive(creature) or (mode == Mode.FOLLOW and player_distance > leash):
		return false
	return creature.global_position.distance_to(_guard_point()) <= leash


## La más cercana de las que van a por el jugador o a por él, o que ha herido el jugador (siguiéndolo).
func _pick() -> NPCController:
	var guard := _guard_point()
	var best: NPCController
	var settled := mode == Mode.SETTLE
	var reach := work.defend_radius() if settled else ENGAGE
	var best_distance := reach
	for creature in CreatureGrid.near(guard, reach):
		if not _alive(creature) or not (_hostile(creature) or (settled and work.is_threat(creature))):
			continue
		var d := creature.global_position.distance_to(guard)
		if d < best_distance:
			best = creature
			best_distance = d
	return best


static func _alive(creature: NPCController) -> bool:
	return creature != null and is_instance_valid(creature) and creature.active and not creature.is_dead \
		and not creature.dormant


## Si [creature] es de las suyas: le ataca a él, o al jugador o a otro compañero (peleando: la presa que
## huye del jugador también lo tiene de objetivo), o el jugador la ha herido (de caza: siguiéndolo).
func _hostile(creature: NPCController) -> bool:
	var ai := creature.ai_controller
	if ai.target == self:
		return true
	if (ai.target == _player or ai.target is Companion) \
			and ai.get_node_or_null(NodePath(String(ai.get_current_state()))) is CreatureCombatState:
		return true
	return mode == Mode.FOLLOW and creature.health_component != null \
		and creature.health_component.last_attacker == _player


## Un paso de pelea: [hacia dónde, a qué velocidad]. Corre hasta tenerla a tiro, la encara y golpea.
func _fight(up: Vector3, delta: float) -> Array:
	var to := _target.global_position - global_position
	var flat := to - up * to.dot(up)
	var distance := flat.length()
	var toward := _tangent(to)
	if _attack_left > 0.0:
		_face(toward, delta)
		return [Vector3.ZERO, 0.0]
	var reach := _reach_to(_target)
	if distance > reach:
		return [toward, remap(clampf(distance, reach, SPRINT_FROM), reach, SPRINT_FROM, RUN_SPEED, SPRINT_SPEED)]
	_face(toward, delta)
	_pause_left -= delta
	if _pause_left <= 0.0 and toward != Vector3.ZERO and _forward.angle_to(toward) < deg_to_rad(40.0):
		_swing()
	return [Vector3.ZERO, 0.0]


## Lo que hay del centro de él al de [creature] cuando la alcanza: los dos cuerpos, el brazo y el arma.
func _reach_to(creature: NPCController) -> float:
	var radius := 0.5
	var capsule := creature.collision_shape.shape as CapsuleShape3D if creature.collision_shape != null else null
	if capsule != null:
		radius = capsule.radius * creature.collision_shape.global_basis.get_scale().x
	return radius + Villager.BODY_RADIUS + ARM + (_weapon.reach if _weapon != null else 0.0)


## Empieza un golpe: de arriba abajo con lo contundente y las hachas, de lado con lo demás.
func _swing() -> void:
	var blunt := _weapon == null or _weapon.damage_kind == ItemData.DamageKind.BLUNT \
		or _weapon.tool_type == ItemData.ToolType.AXE
	var move: Dictionary = MeleeMoveset.VERTICAL if blunt else MeleeMoveset.HORIZONTAL
	_play(move.anim, 0.12, true)
	_anim_player.speed_scale = ATTACK_SPEED
	var window: Vector2 = move.hit
	_hit_at = (window.x + window.y) * 0.5 / ATTACK_SPEED
	_attack_left = float(move.end) / ATTACK_SPEED
	_pause_left = _rng.randf_range(ATTACK_PAUSE.x, ATTACK_PAUSE.y)
	_show_weapon()


## El golpe llega: si la fiera sigue a tiro y delante, le da en el cuerpo.
func _land_hit(up: Vector3) -> void:
	if not _alive(_target) or _target.hurtboxes.is_empty():
		return
	var to := _target.global_position - global_position
	var flat := to - up * to.dot(up)
	if flat.length() > _reach_to(_target) + 0.5 or _forward.angle_to(flat.normalized()) > deg_to_rad(70.0):
		return
	var dir := flat.normalized()
	var point := _target.get_lock_point()
	var damage := maxf(float(_weapon.damage) if _weapon != null else 0.0, FIST_DAMAGE) * DAMAGE_SCALE
	var poise := (_weapon.poise_damage if _weapon != null else 10.0) * DAMAGE_SCALE
	var info := DamageInfo.create(damage, self, point, dir, poise)
	info.kind = _weapon.damage_kind if _weapon != null and _weapon.damage > 0 else ItemData.DamageKind.BLUNT
	info.penetration = _weapon.armor_penetration if _weapon != null else 0.0
	info.knockback = 0.3
	if _target.hurtboxes[0].receive(info) > 0.0:
		CombatFx.blood(_target, point, dir, info.kind, info.amount)
		CombatFx.impact(self, point, info.kind, true)


func _show_weapon() -> void:
	_armed_left = ARMED_TIME
	if _tool != null:
		_tool.visible = true


## Le han dado: un respingo (si no está a mitad de golpe), deja de hablar y se revuelve contra quien
## ha sido.
func _on_hit(info: DamageInfo, applied: float) -> void:
	_since_hit = 0.0
	_chatting = false
	if _target == null and info.source is NPCController and _alive(info.source as NPCController) \
			and mode != Mode.LEAVE and _retreat_left <= 0.0:
		_target = info.source as NPCController
		_show_weapon()
		_to_arms()
	if applied > 0.0 and _attack_left <= 0.0 and health.health > 0.0:
		_flinch_left = FLINCH_TIME
		_play(ANIM_HIT, 0.05, true)


## Sin vida: cae y se queda en el suelo DOWN_TIME s (las fieras lo dejan: su vida está a cero).
func _on_down() -> void:
	_down_left = DOWN_TIME
	_target = null
	_ordered = false
	_attack_left = 0.0
	_hit_at = -1.0
	_flinch_left = 0.0
	_chatting = false
	_hurtbox.set_enabled(false)
	_armed_left = 0.0
	if _tool != null:
		_tool.visible = false
	_play(ANIM_DOWN, 0.15)
	var hotbar: Node = _player.get("hotbar") if _player != null and is_instance_valid(_player) else null
	if hotbar != null:
		hotbar.notify(tr("VILLAGER_DOWN") % String(resident.get("name", "")))


func _lie(up: Vector3, delta: float) -> void:
	_down_left -= delta
	_move(Vector3.ZERO, 0.0, up, delta)
	_pose(up)
	if _down_left > 0.0:
		return
	health.revive()
	health.health = MAX_HEALTH * RISE_HEALTH
	health.health_changed.emit(health.health, health.max_health)
	_hurtbox.set_enabled(true)
	_since_hit = 0.0
	_idle = 0.0
	_play(Villager.ANIM_IDLE, 0.8)


## Fuera de pelea: se recupera poco a poco y, si le hace falta, come algo de lo que lleva.
func _recover(delta: float) -> void:
	if health.is_dead or health.health >= health.max_health or _since_hit < REGEN_AFTER \
			or (mode == Mode.SETTLE and meals.hungry()):
		return
	health.heal(REGEN * delta)
	_eat_left -= delta
	if _eat_left > 0.0 or health.get_health_ratio() >= EAT_BELOW:
		return
	_eat_left = EAT_EVERY
	for group in [&"cooked", &"remedy"]:
		for item in pack.get_all_items():
			if item == null or item.data.category != ItemData.Category.CONSUMABLE \
					or ItemTaxonomy.group_of(item.data) != group:
				continue
			pack.remove_item(item.data, 1)
			health.heal(HEAL_FOOD if group == &"cooked" else HEAL_REMEDY)
			return


# --- En la base -----------------------------------------------------------------------------------

## Un paso de su vida en la base: [hacia dónde, a qué velocidad].
func _live(delta: float) -> Array:
	# Lo han mandado volver a su base: va derecho a ella, trotando.
	if homing:
		var home := _terrain.global_transform * base
		if (home - global_position).slide(up_direction).length() > HOME_NEAR:
			_chore = Chore.STAND
			_chore_left = 0.0
			_travel = 0.0
			return [steer(home, HOME_NEAR * 0.8, delta), JOG_SPEED]
		homing = false
	if _chore != Chore.SLEEP and work.on_duty(_hour()):
		_chore = Chore.STAND
		_chore_left = 0.0
		_look = Vector3.INF
		return work.step(delta)
	if _chore == Chore.WALK:
		var to := _terrain.global_transform * _spot - global_position
		var up := up_direction
		var spot := _terrain.global_transform * _spot
		# Si no llega ni por un camino (STUCK_TELEPORT s atascado tras los intentos), hace allí lo suyo.
		if (to - up * to.dot(up)).length() < ARRIVE or (_stuck > STUCK_TELEPORT and _path_tries >= PATH_TRIES):
			_stuck = 0.0
			_arrive()
			return [Vector3.ZERO, 0.0]
		return [steer(spot, ARRIVE, delta), WALK_SPEED]
	_chore_left -= delta
	var night := work.sleeps(_hour())
	if _chore == Chore.SLEEP:
		_bed_fit_left -= delta
		_sleep_routine.update(delta)
		if _sleep_routine.done():
			_wake()
			_decide()
		elif not night and _sleep_routine.asleep():
			_sleep_routine.get_up()
	elif night or _chore_left <= 0.0:
		_decide()
	if _chore == Chore.SIT and _look.is_finite():
		_face(_terrain.global_transform * _look - global_position, delta)
	return [Vector3.ZERO, 0.0]


## Lo siguiente, según la hora: de noche a dormir, al atardecer a la hoguera y si no, por la base.
func _decide() -> void:
	_look = Vector3.INF
	var h := _hour()
	var to_local := _terrain.global_transform.affine_inverse()
	var fire := _fire()
	if work.sleeps(h):
		_bed = _free_bed()
		if _bed != null:
			var foot := _bed.global_position + _bed.global_basis.z * SettlementVillage.BED_FOOT
			_walk_to(to_local * foot, Chore.SLEEP)
		elif fire != null:
			_walk_to(to_local * _ring_spot(fire), Chore.SLEEP)
		else:
			_walk_to(_roam_spot(), Chore.SLEEP)
		return
	var roll := _rng.randf()
	if fire != null and h >= Villager.EVENING_HOUR and roll < 0.7:
		_look = to_local * fire.global_position
		_walk_to(to_local * _ring_spot(fire), Chore.SIT)
	elif roll < 0.5:
		_walk_to(_roam_spot(), Chore.STAND)
	elif roll < 0.75:
		_rest(Chore.SIT, _rng.randf_range(Villager.SIT_TIME.x, Villager.SIT_TIME.y))
	else:
		_rest(Chore.STAND, _rng.randf_range(Villager.STAND_TIME.x, Villager.STAND_TIME.y))


func _walk_to(spot: Vector3, then: Chore) -> void:
	_chore = Chore.WALK
	_spot = spot
	_then = then
	_stuck = 0.0


func _arrive() -> void:
	match _then:
		Chore.SLEEP:
			_lie_down()
		Chore.SIT:
			_rest(Chore.SIT, _rng.randf_range(Villager.SIT_TIME.x, Villager.SIT_TIME.y))
		_:
			_rest(Chore.STAND, _rng.randf_range(Villager.STAND_TIME.x, Villager.STAND_TIME.y))


func _rest(chore: Chore, time: float) -> void:
	_chore = chore
	_chore_left = time


## Se tumba en su petate (si aún está) o donde está.
func _lie_down() -> void:
	_chore = Chore.SLEEP
	_shape.disabled = true
	velocity = Vector3.ZERO
	_sleep_routine.lie_down()
	_anim = &""
	_bed_fit_left = 0.0
	if _bed != null and is_instance_valid(_bed) and _bed.is_inside_tree():
		var up := (_bed.global_position - _terrain.global_position).normalized()
		global_position = _bed.global_position + up * Villager.BED_HEIGHT
		_forward = _tangent(_bed.global_basis.z)
		reset_physics_interpolation()


## Acostado: se apoya en el petate (o en el suelo) con la pose que se ve (Villager.bed_fit). Cambiando de
## pose, a cada una; dormido y quieto, de vez en cuando.
func _on_skeleton_updated() -> void:
	if _chore != Chore.SLEEP:
		return
	if not _sleep_routine.settling():
		if _bed_fit_left > 0.0:
			return
		_bed_fit_left = Villager.BED_FIT_EVERY
	global_position += up_direction * Villager.bed_fit(_model, up_direction)


## Se levanta: de pie a los pies del petate.
func _wake() -> void:
	if _chore != Chore.SLEEP:
		return
	_sleep_routine.reset()
	_rest(Chore.STAND, 2.0)
	_shape.disabled = false
	if _bed != null and is_instance_valid(_bed) and _bed.is_inside_tree():
		var up := (_bed.global_position - _terrain.global_position).normalized()
		global_position = _bed.global_position + _bed.global_basis.z * SettlementVillage.BED_FOOT + up * 0.05
		reset_physics_interpolation()
	_bed = null


## A pelear: deja lo que hace en la base.
func _to_arms() -> void:
	_wake()
	_look = Vector3.INF
	if mode == Mode.SETTLE:
		_rest(Chore.STAND, 2.0)


func _leave_base() -> void:
	homing = false
	if mode == Mode.SETTLE and base.is_finite():
		return_base = base
		return_work = work.save_data()
	work.stop()
	_wake()
	_look = Vector3.INF
	_chore = Chore.STAND
	base = Vector3.INF


# --- Trabajo (SettlerWork) -----------------------------------------------------------------------

## Hacia dónde andar para llegar a menos de [reach] m (en el plano) de [dest] (mundo): en línea recta y,
## si así no se acerca, por un camino (GroundPath). Lo usan su vida en la base y su trabajo.
func steer(dest: Vector3, reach: float, delta: float) -> Vector3:
	var to_local := _terrain.global_transform.affine_inverse()
	var from_local := _terrain.global_transform
	var dest_local := to_local * dest
	if not _path_dest.is_finite() or _path_dest.distance_to(dest_local) > 1.0:
		_path = PackedVector3Array()
		_path_dest = dest_local
		_path_tries = 0
		_steer_best = INF
		_steer_left = REPATH
	_close_doors()
	var up := up_direction
	# El punto al que va: el siguiente del camino o, sin camino, el destino.
	var aim := dest
	while _path_index < _path.size():
		var point := from_local * _path[_path_index]
		if (point - global_position).slide(up).length() > WAYPOINT:
			aim = point
			break
		_path_index += 1
		_steer_best = INF
		_steer_left = REPATH
	if _path_index >= _path.size():
		_path = PackedVector3Array()
		_path_index = 0
	var distance := (aim - global_position).slide(up).length()
	if distance < _steer_best - PROGRESS:
		_steer_best = distance
		_steer_left = REPATH
	else:
		_steer_left -= delta
		if _steer_left <= -PATH_RETRY:
			_path_tries = 0
		if _steer_left <= 0.0 and _path_tries < PATH_TRIES:
			_path_tries += 1
			_steer_left = REPATH * 2.0
			_steer_best = INF
			var found := GroundPath.find(self, global_position, dest, up, reach)
			_path = PackedVector3Array()
			for point in found:
				_path.append(to_local * point)
			_path_index = 1 if _path.size() > 1 else 0
	if not _path.is_empty():
		_open_doors(from_local * _path[_path_index])
	return _tangent(aim - global_position)


## Lo que le queda hasta [dest] (m): por el camino, si va por uno; si no, en línea recta.
func steer_remaining(dest: Vector3) -> float:
	var up := up_direction
	if _path.is_empty() or _path_index >= _path.size():
		return (dest - global_position).slide(up).length()
	var from_local := _terrain.global_transform
	var total := 0.0
	var last := global_position
	for i in range(_path_index, _path.size()):
		var point := from_local * _path[i]
		total += (point - last).slide(up).length()
		last = point
	return total + (dest - last).slide(up).length()


## Abre la puerta cerrada que haya entre él y [next] (el siguiente punto del camino), si está cerca.
func _open_doors(next: Vector3) -> void:
	for node in get_tree().get_nodes_in_group(WoodenDoor.GROUP):
		var door := node as WoodenDoor
		if door == null or door.open_side != 0 or door.global_position.distance_to(global_position) > DOOR_OPEN + 1.5:
			continue
		var size := GroundPath.door_size(door)
		var middle := door.global_transform * Vector3(0.0, minf(size.y * 0.5, 1.0), 0.0)
		var on_way := Geometry3D.get_closest_point_to_segment(middle, global_position, next).distance_to(middle)
		if on_way < size.x * 0.5 + 0.4 and middle.distance_to(global_position) < DOOR_OPEN + size.x * 0.5:
			door.toggle(global_position)
			if not _opened_doors.has(door):
				_opened_doors.append(door)


## Cierra las que abrió al quedar lejos de ellas.
func _close_doors() -> void:
	for i in range(_opened_doors.size() - 1, -1, -1):
		var door := _opened_doors[i]
		if not is_instance_valid(door):
			_opened_doors.remove_at(i)
		elif door.global_position.distance_to(global_position) > DOOR_CLOSE:
			if door.open_side != 0:
				door.toggle(global_position)
			_opened_doors.remove_at(i)


## Pone [data] en la mano, a la vista.
func hold_work_tool(data: ItemData) -> void:
	if data != _weapon or _tool == null:
		_weapon = data
		_tool = Villager.hold(_model, data.scene_path)
	_armed_left = ARMED_TIME
	if _tool != null:
		_tool.visible = true


## Un golpe de trabajo: [anim] a [speed]; mientras, no se cambia de animación (set_busy).
func play_work(anim: StringName, speed: float) -> void:
	_play(anim, 0.12, true)
	_anim_player.speed_scale = speed


## Ocupado [time] s en un golpe: el movimiento no le cambia la animación.
func set_busy(time: float) -> void:
	_attack_left = time
	_hit_at = -1.0


## Un aviso en la barra del jugador.
func notify(text: String) -> void:
	var hotbar: Node = _player.get("hotbar") if _player != null and is_instance_valid(_player) else null
	if hotbar != null:
		hotbar.notify(text)


## Su árbol ha caído (TreeFelling._fell).
func on_felled(falling: FallingTree) -> void:
	work.on_felled(falling)


## Le cae un árbol encima (FallingTree): muere. Suelta lo que lleva y se va al rato.
func crush() -> void:
	if dead:
		return
	dead = true
	work.stop()
	_wake()
	_target = null
	_chatting = false
	_attack_left = 0.0
	_down_left = 0.0
	_hurtbox.set_enabled(false)
	health.health = 0.0
	health.health_changed.emit(health.health, health.max_health)
	_armed_left = 0.0
	if _tool != null:
		_tool.visible = false
	_gone_left = GONE_TIME
	_play(ANIM_DOWN, 0.1)
	var up := up_direction
	for item in pack.get_all_items():
		if item != null:
			DroppedItem.spawn_at(get_parent(), item.data, item.quantity, global_position + up * 0.8, -up)
	pack.clear()
	notify(tr("SETTLER_CRUSHED") % String(resident.get("name", "")))


## La hora solar de la base (sin sol, mediodía).
func _hour() -> float:
	var h := Seasons.solar_hour(base)
	return 12.0 if is_nan(h) else h


## El petate más cercano a la base que no use otro compañero, o null.
func _free_bed() -> Bedroll:
	var center := _terrain.global_transform * base
	var taken := {}
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Companion
		if other != null and other != self and other._bed != null:
			taken[other._bed] = true
	var best: Bedroll
	var best_distance := BASE_RADIUS
	for node in get_tree().get_nodes_in_group(Bedroll.GROUP):
		var bed := node as Bedroll
		if bed == null or not bed.is_inside_tree() or bed.is_queued_for_deletion() or taken.has(bed):
			continue
		var d := bed.global_position.distance_to(center)
		if d < best_distance:
			best = bed
			best_distance = d
	return best


## La hoguera encendida más cercana a la base, o null.
func _fire() -> Campfire:
	var center := _terrain.global_transform * base
	var best: Campfire
	var best_distance := BASE_RADIUS
	for node in get_tree().get_nodes_in_group(Campfire.GROUP):
		var fire := node as Campfire
		if fire == null or not fire.lit or not fire.is_inside_tree():
			continue
		var d := fire.global_position.distance_to(center)
		if d < best_distance:
			best = fire
			best_distance = d
	return best


## Un sitio alrededor de [fire] (mundo).
func _ring_spot(fire: Campfire) -> Vector3:
	var up := (fire.global_position - _terrain.global_position).normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	return fire.global_position + side.rotated(up, _rng.randf() * TAU) * _rng.randf_range(FIRE_RING.x, FIRE_RING.y)


## Un sitio de la base para pasear (marco del terreno).
func _roam_spot() -> Vector3:
	var up := base.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	return base + side.rotated(up, _rng.randf() * TAU) * ROAM * sqrt(_rng.randf())


## La herramienta de su oficio (SettlementPopulation: "job"), o null.
func _job_tool() -> ItemData:
	var job: Dictionary = resident.get("job", {})
	return ItemCatalog.get_item(StringName(job.tool)) if job.has("tool") else null


## Si [data] sirve para golpear con la derecha: un arma o una herramienta con daño que no se dispara.
static func _strikes_with(data: ItemData) -> bool:
	if data == null or data.damage <= 0 or data.is_left_handed() or data.ammo_id != &"":
		return false
	if data.category == ItemData.Category.WEAPON:
		return data.weapon_type != ItemData.WeaponType.CANNON
	return data.category == ItemData.Category.TOOL and data.tool_type != ItemData.ToolType.TORCH \
		and data.tool_type != ItemData.ToolType.FISHING_ROD


## Lo que protege su ropa (SettlementPopulation: "outfit"), en ARMOR_SHARE: x tajo, y contundente, z
## perforante.
func _outfit_armor() -> Vector3:
	var total := Vector3.ZERO
	for id in resident.get("outfit", []):
		total += Armor.of(ItemCatalog.get_item(StringName(id)))
	return total * ARMOR_SHARE


## [v] sobre el plano tangente aquí, unitario, o cero.
func _tangent(v: Vector3) -> Vector3:
	var up := (global_position - _terrain.global_position).normalized() if _terrain != null else Vector3.UP
	var t := v - up * v.dot(up)
	return t.normalized() if t.length_squared() > 1e-8 else Vector3.ZERO


## El que el jugador tiene delante en [at] mirando hacia [look] (como Villager.find), o null.
static func find(tree: SceneTree, at: Vector3, look: Vector3, reach := 2.6) -> Companion:
	return Villager.nearest(tree, GROUP, at, look, reach) as Companion
