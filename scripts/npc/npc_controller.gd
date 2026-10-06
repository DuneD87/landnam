@tool
extends AmbientAnimal
class_name NPCController

const Config = preload("res://scripts/config.gd")

## Controlador de los NPCs con esqueleto (animales, humanos…): es una AmbientAnimal que además
## orquesta sus componentes hijo (Movement, AIController + estados, Inventory, y opcionalmente
## AnimationController y Perception), gestionando gravedad, animación, daño, muerte y guardado.

## Nombre del estado inicial de la FSM (nombre de un nodo hijo de AIController).
@export var initial_ai_state: StringName = &"IdleState"
## Estado al que ir cuando Perception detecta objetivo. Vacío = sin reacción automática.
@export var detect_state: StringName = &""
## Estado al que ir cuando Perception pierde el objetivo. Vacío = decide el estado activo.
@export var lose_state: StringName = &""
## Estado al que ir cuando alguien le hiere. Vacío = detect_state.
@export var provoked_state: StringName = &""
## Tipo de NPC, usado por Perception de otros NPCs para identificar amenazas (ej: &"bear", &"deer").
@export var npc_type: StringName = &""
## Identificador único para guardado; se genera automáticamente si está vacío.
@export var entity_id: String = ""
## Solo los NPCs únicos se guardan. Los de población se reciclan por distancia, así que
## guardarlos sería resucitar copias que el spawner ya no controla.
@export var persistent: bool = false
var save_category: String = "npc"

@onready var movement: Movement = $Movement
@onready var ai_controller: AIController = $AIController
@onready var inventory: Inventory = $Inventory
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var npc_model: Node3D = $NPCModel
var animation_controller: AnimationController
var current_animation
var perception: Perception

## Segundos que el cadáver permanece antes de desaparecer. 0 = inmediato. Lo asigna NPCSpawner.
var corpse_duration: float = 0.0
var is_dead: bool = false
var _is_dying: bool = false

## Segundos que el NPC queda paralizado tras recibir un golpe.
@export var hit_stun_duration: float = 0.35
## Desde esta velocidad (m/s) corre con la animación de esprintar en vez de la de correr.
## 0 = nunca. Conviene que esté entre la velocidad de suelo de un clip y la del otro.
@export var sprint_anim_speed: float = 0.0
## Velocidad de suelo (m/s) de los clips de correr y esprintar, medida en ellos: con ella cada
## clip se acelera o se frena a la velocidad a la que va el cuerpo, para que las patas no
## patinen. 0 = el clip a su ritmo.
@export var run_clip_speed: float = 0.0
@export var sprint_clip_speed: float = 0.0

@export_group("Combate")
## Hueso de la cabeza: lleva un hurtbox propio que duele más. Vacío = solo el del cuerpo.
@export var head_bone: StringName = &""
@export var head_radius: float = 0.35
@export var head_multiplier: float = 1.5
## Cadena de huesos que dobla el respingo al encajar un golpe (tronco → cabeza).
@export var flinch_bones: Array[String] = []
## Lo que suena al encajar daño y al morir (ids de CombatFx). Vacío = nada.
@export var hurt_sound: StringName = &""
@export var death_sound: StringName = &""

## Zonas que reciben golpes: el cuerpo (copia de la cápsula de colisión) y la cabeza.
var hurtboxes: Array[Hurtbox] = []
var hit_react: HitReact
var is_hit: bool = false
var _hit_timer: float = 0.0

var _frame_offset: int = 0
var _ai_update_stride: int = 1
## Cuenta de activaciones: un temporizador de cadáver de una vida anterior no debe tocar a la
## criatura que el pool ya ha vuelto a sacar.
var _life_id: int = 0

# Layer de NPCs vivos; los muertos pasan a layer 0.
const NPC_LIVE_LAYER := 2
## Una de cada cuántas actualizaciones de IA corre cuando la criatura está lejos.
const AI_STRIDE_FAR := 4
## El charco bajo el cadáver: cuándo sale tras morir (s, ya caído) y lo que tarda en extenderse (s).
const BLEED_OUT_DELAY := 1.6
const BLEED_OUT_GROW := 16.0

func _ready() -> void:
	safe_margin = 0.008
	floor_max_angle = deg_to_rad(70.0)
	floor_snap_length = 0.1
	collision_layer = NPC_LIVE_LAYER
	collision_mask  = 1 | NPC_LIVE_LAYER

	if entity_id.is_empty():
		entity_id = "npc_%d" % get_instance_id()
	if persistent:
		add_to_group(GameManager.SAVEABLE_GROUP)
	add_to_group("npc")
	# Vivo y alcanzable: cañones y cascos buscan a las criaturas por el grupo de AmbientAnimal.
	# El pool llama a deactivate() justo después de instanciar, así que uno de población
	# arranca dormido y uno suelto en una escena arranca vivo.
	active = true
	add_to_group(GROUP)
	impact_radius = 0.8

	movement.use_ai_input = true

	animation_controller = get_node_or_null("AnimationController")

	perception = get_node_or_null("Perception")
	if perception:
		perception.npc = self
		perception.controller = ai_controller
		if detect_state != &"":
			perception.target_detected.connect(_on_target_detected)
		if lose_state != &"":
			perception.target_lost.connect(_on_target_lost)

	ai_controller.npc = self
	ai_controller.movement = movement

	_build_hurtboxes()
	_gore = AnimalGore.attach(self, npc_model, health_component)
	_setup_gait()

	movement.landed.connect(_on_landed)
	health_component.damaged.connect(_on_damaged)
	health_component.hit_received.connect(_on_hit_received)
	if not health_component.died.is_connected(_on_health_depleted):
		health_component.died.connect(_on_health_depleted)

	update_nearest_planet()

	if initial_ai_state != &"":
		ai_controller.start(initial_ai_state)
	inventory.add_item(Config.get_item(&"wood_01"), 37)
	inventory.add_item(Config.get_item(&"stone_01"), 37)

func _physics_process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_physics_step(delta)
	DebugStats.report_cost(&"npc:control", Time.get_ticks_usec() - _t0)


func _physics_step(delta: float) -> void:
	if _head_holder != null:
		# El hueso trae la escala del armature (0,01): se deshace para que la esfera mida metros.
		var s := _head_holder.get_parent_node_3d().global_basis.get_scale().x
		if s > 1e-4:
			_head_holder.scale = Vector3.ONE / s
	if not planet:
		update_nearest_planet()
		return
	gravity_direction = planet.get_gravity_direction(global_position)
	up_direction = -gravity_direction

	if is_dead:
		if animation_controller:
			animation_controller.handle_animations(delta, Config.ANIMATION.DEATH, false)
		if is_on_floor():
			velocity = Vector3.ZERO
		else:
			velocity += gravity_direction * planet.gravity_strength * delta
		align_to_gravity(gravity_direction, delta)
		move_and_slide()
		return

	# Un casco a velocidad lo mata; los que ya están muriendo no se atropellan dos veces.
	if active and _check_moving_ships(delta):
		return

	if not _is_dying and Engine.get_physics_frames() % _ai_update_stride == _frame_offset % _ai_update_stride:
		ai_controller.gravity_direction = gravity_direction
		ai_controller.update(delta * _ai_update_stride)

	var raw_dir := ai_controller.desired_direction
	movement.ai_direction = project_on_gravity_plane(raw_dir)

	if is_hit:
		_hit_timer -= delta
		if _hit_timer <= 0.0:
			is_hit = false
		movement.ai_direction = Vector3.ZERO

	movement.handle_run_movement(delta, ai_controller.is_attacking, gravity_direction, null, Config.ANIMATION.IDLE, Config.ANIMATION.RUN)
	movement.handle_idle_movement(delta, gravity_direction, is_on_floor(), planet.gravity_strength, velocity)

	current_animation = movement.current_animation
	if current_animation == Config.ANIMATION.RUN and sprint_anim_speed > 0.0 \
			and movement.speed >= sprint_anim_speed:
		current_animation = Config.ANIMATION.SPRINT
	if ai_controller.is_attacking:
		current_animation = Config.ANIMATION.ATTACK_1
	if animation_controller:
		animation_controller.handle_animations(delta, current_animation, false)
	if not _gait.is_empty():
		_update_gait()

	velocity = movement.velocity

	var facing := ai_controller.desired_facing
	var rot_dir := project_on_gravity_plane(facing if facing != Vector3.ZERO else movement.direction)
	if rot_dir.length() > 0.1:
		if ai_controller.turn_rate > 0.0:
			_turn_toward(rot_dir, deg_to_rad(ai_controller.turn_rate) * delta)
		else:
			rotate_toward_direction(rot_dir, delta)

	align_to_gravity(gravity_direction, delta)

	move_and_slide()


## Gira sobre la vertical hacia [dir] como mucho [max_angle] radianes.
func _turn_toward(dir: Vector3, max_angle: float) -> void:
	var up := -gravity_direction.normalized()
	var forward := project_on_gravity_plane(global_basis.z)
	if forward == Vector3.ZERO:
		return
	var step := clampf(forward.signed_angle_to(dir, up), -max_angle, max_angle)
	if absf(step) < 1e-5:
		return
	global_basis = Basis(up, step) * global_basis
	orthonormalize()


func _on_target_detected(_target: Node3D) -> void:
	ai_controller.transition_to(detect_state)


func _on_target_lost() -> void:
	ai_controller.transition_to(lose_state)


func _on_damaged(_amount: float, source: Node) -> void:
	if is_dead:
		return
	is_hit = true
	_hit_timer = hit_stun_duration
	if animation_controller:
		animation_controller.trigger_hit()
	# El golpe que mata suena con la muerte.
	if hurt_sound != &"" and health_component.health > 0.0:
		CombatFx.play(hurt_sound, global_position)
	# Quien te pega es un objetivo aunque Perception no lo vigile.
	var provoked := provoked_state if provoked_state != &"" else detect_state
	if provoked != &"" and source is Node3D and source != self and not _is_dying:
		ai_controller.target = source
		ai_controller.transition_to(provoked)


## Hurtboxes del cuerpo y de la cabeza, y el respingo. Se crean aquí para que cualquier criatura
## con esqueleto se pueda golpear sin tocar su escena.
func _build_hurtboxes() -> void:
	if collision_shape != null and collision_shape.shape != null:
		var body_box := Hurtbox.attach(self, self, collision_shape.shape, collision_shape.transform, &"body")
		body_box.health = health_component
		hurtboxes.append(body_box)
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if head_bone != &"" and skeleton.find_bone(head_bone) >= 0:
		var attachment := BoneAttachment3D.new()
		attachment.name = "HeadHurtbox"
		attachment.bone_name = head_bone
		skeleton.add_child(attachment)
		var sphere := SphereShape3D.new()
		# La esfera se mide en metros aunque el hueso venga escalado (el armature va a 0,01).
		sphere.radius = head_radius
		var holder := Node3D.new()
		attachment.add_child(holder)
		holder.set_as_top_level(false)
		var head_box := Hurtbox.attach(holder, self, sphere, Transform3D.IDENTITY, &"head", head_multiplier)
		head_box.health = health_component
		holder.scale = Vector3.ONE / maxf(attachment.global_basis.get_scale().x, 1e-4) if attachment.is_inside_tree() else Vector3.ONE
		hurtboxes.append(head_box)
		_head_holder = holder
	if not flinch_bones.is_empty():
		hit_react = HitReact.new()
		hit_react.name = "HitReact"
		hit_react.chain = flinch_bones
		hit_react.max_angle = 14.0
		skeleton.add_child(hit_react)


var _head_holder: Node3D
## Mutilaciones al morir (solo los esqueletos con tabla en AnimalGore).
var _gore: AnimalGore
var _skeleton: Skeleton3D
var _action_channel: CreatureActionChannel
## Dónde vive (donde apareció), en el marco del planeta: así sobrevive a los rebases del origen
## flotante. INF = aún no se sabe.
var _home_local := Vector3.INF
## Escaladores de ritmo de los clips de correr y esprintar (ver run_clip_speed): [nodo, m/s].
var _gait: Array = []


## El esqueleto del modelo, esté donde esté dentro de él (cada rig lo cuelga de un sitio).
func get_skeleton() -> Skeleton3D:
	if _skeleton == null and npc_model != null:
		var found := npc_model.find_children("*", "Skeleton3D", true, false)
		if not found.is_empty():
			_skeleton = found[0] as Skeleton3D
	return _skeleton


## Fija dónde vive (centro de su territorio).
func set_home(point: Vector3) -> void:
	_home_local = planet.to_local(point) if planet != null else Vector3.INF


## Dónde vive, en mundo. La primera vez que se pide sin saberlo, donde está ahora (una criatura
## soltada a mano no pasa por activate()). INF si aún no tiene planeta.
func get_home() -> Vector3:
	if planet == null:
		return Vector3.INF
	if _home_local == Vector3.INF:
		set_home(global_position)
	return planet.to_global(_home_local)


## Mete un TimeScale delante de los clips de correr y esprintar del árbol (las entradas 1 de los
## Blend2 bRun y bSprint, que es como los nombra AnimationController en todas las especies).
func _setup_gait() -> void:
	# En el editor no: el árbol cambiado se guardaría con la escena.
	if Engine.is_editor_hint() or animation_controller == null \
			or (run_clip_speed <= 0.0 and sprint_clip_speed <= 0.0):
		return
	var tree := animation_controller.animation_tree
	if tree == null or not (tree.tree_root is AnimationNodeBlendTree):
		return
	var tree_root := (tree.tree_root as AnimationNodeBlendTree).duplicate(true) as AnimationNodeBlendTree
	var connections: Array = tree_root.get("node_connections")
	for gait in [[&"bRun", &"gait_run", run_clip_speed], [&"bSprint", &"gait_sprint", sprint_clip_speed]]:
		if gait[2] <= 0.0:
			continue
		var source := StringName()
		for i in range(0, connections.size(), 3):
			if connections[i] == gait[0] and int(connections[i + 1]) == 1:
				source = connections[i + 2]
		if source == StringName():
			continue
		tree_root.add_node(gait[1], AnimationNodeTimeScale.new())
		tree_root.disconnect_node(gait[0], 1)
		tree_root.connect_node(gait[1], 0, source)
		tree_root.connect_node(gait[0], 1, gait[1])
		_gait.append([gait[1], gait[2]])
	tree.tree_root = tree_root


func _update_gait() -> void:
	var speed := movement.velocity.length()
	for gait in _gait:
		var rate := clampf(speed / gait[1], 0.5, 2.0) if speed > 0.3 else 1.0
		animation_controller.animation_tree.set("parameters/%s/scale" % gait[0], rate)


## Canal de animaciones de acción (ataques) encima de la locomoción; se monta la primera vez.
func get_action_channel() -> CreatureActionChannel:
	if _action_channel == null and animation_controller != null:
		_action_channel = CreatureActionChannel.build(animation_controller.animation_tree)
	return _action_channel


func _set_hurtboxes_enabled(value: bool) -> void:
	for box in hurtboxes:
		if is_instance_valid(box):
			box.set_enabled(value)


func _on_hit_received(info: DamageInfo, applied: float) -> void:
	if hit_react != null and applied > 0.0:
		hit_react.flinch(info.direction, up_direction, clampf(applied / 30.0, 0.35, 1.2))


## Lo que está haciendo en combate, para quien pelea con él (CombatRead): lo cuenta su estado de
## IA si sabe (get_situation), y si no, nada.
func get_combat_situation() -> StringName:
	if is_dead or _is_dying:
		return &"dead"
	var state := ai_controller.get_node_or_null(NodePath(ai_controller.get_current_state()))
	if state != null and state.has_method(&"get_situation"):
		return state.get_situation()
	return &""


## Punto al que se apunta al fijar este objetivo (centro de la cápsula).
func get_lock_point() -> Vector3:
	return collision_shape.global_position if collision_shape != null else global_position


func _on_landed(impact_speed: float) -> void:
	health_component.take_fall_damage(impact_speed)


## Sale del pool: repone salud, estado, IA y animación, para quedar indistinguible de uno
## recién instanciado.
func activate(point: Vector3, environment: AmbientFaunaHabitat,
		rng: RandomNumberGenerator) -> void:
	var ground := environment as GroundFaunaHabitat
	if ground != null:
		planets = ground.planets
	var settings := profile as GroundFaunaProfile
	corpse_duration = settings.corpse_duration if settings != null else 0.0
	_life_id += 1
	BloodStains.clear(self)
	if _gore != null:
		_gore.reset()
	is_dead = false
	_is_dying = false
	is_hit = false
	_hit_timer = 0.0
	collision_layer = NPC_LIVE_LAYER
	collision_mask = 1 | NPC_LIVE_LAYER
	_set_hurtboxes_enabled(true)
	if health_component != null:
		health_component.revive()
	_frame_offset = rng.randi() % AI_STRIDE_FAR
	_ai_update_stride = 1
	super.activate(point, environment, rng)
	if persistent:
		add_to_group(GameManager.SAVEABLE_GROUP)
	update_nearest_planet()
	set_home(point)
	if planet != null:
		gravity_direction = planet.get_gravity_direction(global_position)
		up_direction = -gravity_direction
		align_to_gravity(gravity_direction, 1.0)
	ai_controller.target = null
	ai_controller.is_attacking = false
	ai_controller.desired_direction = Vector3.ZERO
	ai_controller.desired_facing = Vector3.ZERO
	if initial_ai_state != &"":
		ai_controller.transition_to(initial_ai_state)
	current_animation = Config.ANIMATION.IDLE
	if animation_controller:
		animation_controller.handle_animations(0.0, Config.ANIMATION.IDLE, false)
	if perception:
		perception.set_physics_process(true)
	set_physics_process(true)
	reset_physics_interpolation()


## Un cadáver reciclado por distancia suelta su plaza: sin limpiar la muerte aquí, in_play()
## seguiría siendo cierto y el pool no lo volvería a usar nunca.
func deactivate() -> void:
	is_dead = false
	_is_dying = false
	_set_hurtboxes_enabled(false)
	super.deactivate()
	if perception:
		perception.set_physics_process(false)
	if is_in_group(GameManager.SAVEABLE_GROUP):
		remove_from_group(GameManager.SAVEABLE_GROUP)


func in_play() -> bool:
	return active or is_dead or _is_dying


func lockable() -> bool:
	return super.lockable() and not is_dead and not _is_dying \
		and health_component != null and not health_component.is_dead


## Detalle por distancia: lejos deja de simularse entero en vez de reciclarse.
func set_detail(distance: float) -> void:
	var settings := profile as GroundFaunaProfile
	if settings == null:
		return
	# Un cuerpo que aún cae, o que se está muriendo, se simula esté donde esté.
	var awake := settings.full_detail_distance <= 0.0 or distance <= settings.full_detail_distance 		or not active or not is_on_floor()
	set_physics_process(awake)
	if perception:
		perception.set_physics_process(awake and active)
	_ai_update_stride = 1 if distance <= settings.near_detail_distance else AI_STRIDE_FAR


## Un impacto letal (casco, bala) lo mata por su HealthComponent, para que corra la animación
## de muerte y deje cadáver. La sangre marca el punto del golpe.
func die(point: Vector3) -> void:
	if not active or _is_dying:
		return
	_is_dying = true
	CombatFx.blood(self, point, -gravity_direction.normalized(), ItemData.DamageKind.BLUNT, 60.0)
	if _gore != null:
		_gore.note_blast(point)
	if health_component != null and not health_component.is_dead:
		health_component.take_damage(health_component.health, self)
	_on_died()


func _on_died() -> void:
	_is_dying = true
	active = false
	if death_sound != &"":
		CombatFx.play(death_sound, global_position)
	startle_near(get_tree(), global_position, DEATH_STARTLE_RADIUS)
	_set_hurtboxes_enabled(false)
	ai_controller.desired_direction = Vector3.ZERO
	ai_controller.desired_facing = Vector3.ZERO
	ai_controller.is_attacking = false
	if perception:
		perception.set_physics_process(false)

	await get_tree().create_timer(0.4).timeout
	# El pool puede haberlo reciclado por distancia durante la espera; deactivate() limpia
	# _is_dying, y entonces esta muerte ya no va con este cuerpo.
	if not is_instance_valid(self) or not _is_dying:
		return

	is_dead = true
	collision_layer = 0
	collision_mask  = 1
	velocity = Vector3.ZERO
	if animation_controller:
		animation_controller.trigger_death()
	if corpse_duration <= 0.0:
		_retire()
		return
	ai_controller.transition_to(&"DeathState")
	var life := _life_id
	_bleed_out(life)
	get_tree().create_timer(corpse_duration).timeout.connect(
		func(): if is_instance_valid(self) and _life_id == life: _retire()
	)


## El cadáver se desangra: ya en el suelo, un charco debajo que se va extendiendo, a la medida de
## la criatura.
func _bleed_out(life: int) -> void:
	await get_tree().create_timer(BLEED_OUT_DELAY).timeout
	if not is_instance_valid(self) or _life_id != life or not is_dead:
		return
	var size := 1.0
	var capsule := collision_shape.shape as CapsuleShape3D if collision_shape != null else null
	if capsule != null:
		size = clampf(capsule.radius * 8.0, 1.5, 3.8)
	var at := collision_shape.global_position if collision_shape != null else global_position
	BloodPool.spawn(self, at, gravity_direction * 9.8, size, BLEED_OUT_GROW, 1)


## Fin del cadáver: al pool si lo gobierna un spawner, o fuera de la escena si es suelto.
func _retire() -> void:
	if profile != null:
		deactivate()
	else:
		queue_free()


func get_save_data() -> Dictionary:
	return {
		"position": {
			"x": global_position.x,
			"y": global_position.y,
			"z": global_position.z,
		},
		"basis": {
			"xx": global_basis.x.x, "xy": global_basis.x.y, "xz": global_basis.x.z,
			"yx": global_basis.y.x, "yy": global_basis.y.y, "yz": global_basis.y.z,
			"zx": global_basis.z.x, "zy": global_basis.z.y, "zz": global_basis.z.z,
		},
		"health": health_component.health,
		"ai_state": str(ai_controller.get_current_state()),
		"planets_path": str(planets.get_path()) if planets else "",
	}


func restore_save_data(save: Dictionary) -> void:
	global_position = Vector3(save.position.x, save.position.y, save.position.z)
	var b = save.basis
	global_basis = Basis(
		Vector3(b.xx, b.xy, b.xz),
		Vector3(b.yx, b.yy, b.yz),
		Vector3(b.zx, b.zy, b.zz),
	)
	health_component.health = save.health

	var planets_path: String = save.get("planets_path", "")
	if not planets_path.is_empty():
		var found := get_tree().root.get_node_or_null(planets_path)
		if found:
			planets = found

	var saved_state := StringName(save.get("ai_state", str(initial_ai_state)))
	if saved_state != ai_controller.get_current_state():
		ai_controller.transition_to(saved_state)


func post_restore() -> void:
	update_nearest_planet()
	if not planet:
		return
	gravity_direction = planet.get_gravity_direction(global_position)
	up_direction = -gravity_direction
	align_to_gravity(gravity_direction, 1.0)

	set_physics_process(false)
	while not is_ground_ready():
		await get_tree().create_timer(0.5).timeout
	set_physics_process(true)
