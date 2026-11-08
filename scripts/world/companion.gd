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
## lleve si le hace falta. Ver docs/villagers.md.

enum Mode {FOLLOW, WAIT, LEAVE}

const GROUP := &"companion"
## Siguiendo: se para a STOP m del jugador y echa a andar a más de START; la velocidad sube con la
## distancia, de andar a correr y a la carrera (SPRINT_FROM m).
const STOP := 2.2
const START := 3.5
const SPRINT_FROM := 15.0
const WALK_SPEED := 1.4
const SPRINT_SPEED := 8.0
const ACCEL := 12.0
const TURN_RATE := 6.0
## Por encima de esta velocidad (m/s) corre; vuelve a andar por debajo de WALK_BELOW.
const RUN_ABOVE := 2.6
const WALK_BELOW := 2.2
const JUMP_SPEED := 5.0
## Atascado: avanzando a menos de STUCK_RATIO de lo que quiere, salta cada JUMP_EVERY s; si sigue
## así STUCK_TELEPORT s a más de STUCK_FAR m, aparece detrás del jugador. A más de TELEPORT m, también.
const STUCK_RATIO := 0.35
const JUMP_EVERY := 0.8
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
const ANIM_HIT := &"combat/hit_react"
const ANIM_DOWN := &"combat/death"

## SettlementPopulation.residents: "id", "name", "sex", "job"...
var resident: Dictionary
## Su poblado (índice en el campo de poblados), su nombre y la confianza (la de SettlementManager).
var village := -1
var village_name := ""
var relations: SettlementRelations
var mode := Mode.FOLLOW
## La del planeta (PlanetLoader.gravity_strength).
var gravity := 9.8
## Lo que lleva (se guarda con él) y su vida (la buscan las fieras y los golpes por su nombre).
var pack: Inventory
var health: HealthComponent

var _terrain: Node3D
var _player: Node3D
## El centro de su poblado, en el marco del terreno (hacia donde vuelve).
var _home := Vector3.ZERO
var _model: Node3D
var _anim_player: AnimationPlayer
var _anim := &""
var _forward := Vector3.FORWARD
var _running := false
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
	_model = model
	_model.transform = Transform3D.IDENTITY
	add_child(_model)
	_anim_player = _model.get_node("AnimationPlayer") as AnimationPlayer
	_anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	# Los golpes, el respingo y la caída, los del jugador.
	if not _anim_player.has_animation_library(&"combat") and ResourceLoader.exists(PlayerCombat.COMBAT_LIBRARY):
		_anim_player.add_animation_library(&"combat", load(PlayerCombat.COMBAT_LIBRARY))
	_tool = _model.get_node_or_null("Armature/Skeleton3D/ToolHand/Grip/Tool") as Node3D
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
	# La herramienta que ya trae en la mano (build_model) es la de su oficio.
	_weapon = _job_tool() if _tool != null else null
	refresh_weapon()


func _ready() -> void:
	_forward = _tangent(global_basis.z)
	if _forward == Vector3.ZERO:
		_forward = _tangent(Vector3.FORWARD)
	_play(Villager.ANIM_IDLE, 0.0)


## Se queda donde está hasta que se le diga que siga.
func wait_here() -> void:
	mode = Mode.WAIT
	_idle = 0.0


func follow() -> void:
	mode = Mode.FOLLOW
	_idle = 0.0


## Se vuelve a su poblado: echa a andar hacia allí y se va del todo al perderse de vista
## (SettlementCompanions lo quita al salir del árbol).
func go_home() -> void:
	mode = Mode.LEAVE
	_leave_time = 0.0


## Se le puede hablar si no se va, no pelea y no está malherido.
func can_chat() -> bool:
	return mode != Mode.LEAVE and _target == null and _down_left <= 0.0


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
	if distance > FREEZE and mode != Mode.LEAVE:
		velocity = Vector3.ZERO
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
				if distance > START or (_moving and distance > STOP):
					heading = _tangent(to_player)
					speed = remap(clampf(distance, STOP, SPRINT_FROM), STOP, SPRINT_FROM, WALK_SPEED, SPRINT_SPEED)
			Mode.LEAVE:
				_leave_time += delta
				if distance > LEAVE_GONE or _leave_time > LEAVE_TIME:
					queue_free()
					return
				heading = _tangent(_terrain.global_transform * _home - global_position)
				speed = WALK_SPEED
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
		if distance < FACE_PLAYER:
			_face(to_player, delta)
	_pose(up)
	_animate()


## La velocidad de este paso: en el plano, hacia [heading] a [speed]; en vertical, la gravedad (si hay
## suelo debajo: si no, espera a que llegue su colisión).
func _move(heading: Vector3, speed: float, up: Vector3, delta: float) -> void:
	var vertical := up * velocity.dot(up)
	var flat := velocity - vertical
	flat = flat.move_toward(heading * speed, ACCEL * delta)
	if _jump and is_on_floor():
		vertical = up * JUMP_SPEED
	elif is_on_floor():
		vertical = Vector3.ZERO
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
		_jump = true
	if mode == Mode.FOLLOW and _target == null and _stuck > STUCK_TELEPORT and distance > STUCK_FAR and _teleport():
		_stuck = 0.0


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
	for angle in TELEPORT_ANGLES:
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
		_running = speed > (WALK_BELOW if _running else RUN_ABOVE)
		if _running:
			_play(Villager.ANIM_RUN)
			_anim_player.speed_scale = speed / Villager.RUN_CLIP_SPEED
		else:
			_play(Villager.ANIM_WALK)
			_anim_player.speed_scale = speed / Villager.WALK_CLIP_SPEED
		return
	_anim_player.speed_scale = 1.0
	_play(Villager.ANIM_SIT if mode == Mode.WAIT and _idle > SIT_AFTER and _target == null else Villager.ANIM_IDLE)


func _play(anim: StringName, blend := Villager.BLEND, again := false) -> void:
	if _anim == anim and not again:
		return
	_anim = anim
	_anim_player.speed_scale = 1.0
	_anim_player.play(anim, blend)
	if again:
		_anim_player.seek(0.0, true)


# --- Pelea ----------------------------------------------------------------------------------------

## Lo que guarda (el jugador; esperando, él mismo): de ahí se mide lo que está a tiro.
func _guard_point() -> Vector3:
	return global_position if mode == Mode.WAIT else _player.global_position


## Sigue con la que tiene si aún vale la pena, o busca otra.
func _scan(player_distance: float) -> void:
	if mode == Mode.LEAVE:
		_target = null
		return
	if _target != null and not _worth_chasing(_target, player_distance):
		_target = null
	if _target == null:
		_target = _pick()
		if _target != null:
			_show_weapon()


func _worth_chasing(creature: NPCController, player_distance: float) -> bool:
	if not _alive(creature) or (mode == Mode.FOLLOW and player_distance > LEASH):
		return false
	return creature.global_position.distance_to(_guard_point()) <= LEASH


## La más cercana de las que van a por el jugador o a por él, o que ha herido el jugador (siguiéndolo).
func _pick() -> NPCController:
	var guard := _guard_point()
	var best: NPCController
	var best_distance := ENGAGE
	for creature in CreatureGrid.near(guard, ENGAGE):
		if not _alive(creature) or not _hostile(creature):
			continue
		var d := creature.global_position.distance_to(guard)
		if d < best_distance:
			best = creature
			best_distance = d
	return best


static func _alive(creature: NPCController) -> bool:
	return creature != null and is_instance_valid(creature) and creature.active and not creature.is_dead \
		and not creature.dormant


## Si [creature] es de las suyas: le ataca a él, o al jugador (peleando: la presa que huye del jugador
## también lo tiene de objetivo), o el jugador la ha herido (de caza: siguiéndolo).
func _hostile(creature: NPCController) -> bool:
	var ai := creature.ai_controller
	if ai.target == self:
		return true
	if ai.target == _player and ai.get_node_or_null(NodePath(String(ai.get_current_state()))) is CreatureCombatState:
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
		return [toward, remap(clampf(distance, reach, SPRINT_FROM), reach, SPRINT_FROM, RUN_ABOVE + 1.0, SPRINT_SPEED)]
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
			and mode != Mode.LEAVE:
		_target = info.source as NPCController
		_show_weapon()
	if applied > 0.0 and _attack_left <= 0.0 and health.health > 0.0:
		_flinch_left = FLINCH_TIME
		_play(ANIM_HIT, 0.05, true)


## Sin vida: cae y se queda en el suelo DOWN_TIME s (las fieras lo dejan: su vida está a cero).
func _on_down() -> void:
	_down_left = DOWN_TIME
	_target = null
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
	if health.is_dead or health.health >= health.max_health or _since_hit < REGEN_AFTER:
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
