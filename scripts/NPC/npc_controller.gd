@tool
extends PlanetaryBody
class_name NPCController

const Config = preload("res://scripts/config.gd")

## Controlador base para todos los NPCs (animales, humanos…).
##
## ── Nodos hijo requeridos en la escena ──────────────────────────────────────
##   Movement          (scripts/Player/movement.gd)
##   HealthComponent   (scripts/NPC/health_component.gd)
##   AIController      (scripts/NPC/ai/ai_controller.gd)
##     └── [estados AIState como hijos, ej: IdleState, WanderState, FleeState…]
##   Inventory         (scripts/ui/inventory/inventory.gd)
##
## ── Nodo hijo opcional ──────────────────────────────────────────────────────
##   AnimationController (scripts/Player/animation_controller.gd)
##     Con los exports animator / animation_tree apuntando al modelo del NPC.
##
## ── Hereda de PlanetaryBody ─────────────────────────────────────────────────
##   @export planets, var planet, var gravity_direction
##   align_to_gravity(), rotate_toward_direction(), project_on_gravity_plane()
##   update_nearest_planet()

## Nombre del estado inicial de la FSM. Debe coincidir con el nombre de un
## nodo hijo de AIController (ej: &"IdleState").
@export var initial_ai_state: StringName = &"IdleState"
## Estado al que transicionar cuando Perception detecta un objetivo.
## Vacío = sin reacción automática (útil para NPCs pasivos).
@export var detect_state: StringName = &""
## Estado al que transicionar cuando Perception pierde el objetivo.
## Vacío = dejar que el estado activo decida por sí mismo.
@export var lose_state: StringName = &""
## Tipo de NPC. Usado por Perception de otros NPCs para identificar amenazas (ej: &"bear", &"deer").
@export var npc_type: StringName = &""
## Identificador único para el sistema de guardado. Se genera automáticamente
## si está vacío. Sobreescribir en el editor para NPCs fijos en la escena.
@export var entity_id: String = ""
var save_category: String = "npc"

@onready var movement: Movement = $Movement
@onready var health_component: HealthComponent = $HealthComponent
@onready var ai_controller: AIController = $AIController
@onready var inventory: Inventory = $Inventory
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var npc_model: Node3D = $NPCModel
## Asignado automáticamente si existe el nodo hijo "AnimationController".
var animation_controller: AnimationController
var current_animation  # Config.ANIMATION value
## Asignado automáticamente si existe el nodo hijo "Perception".
var perception: Perception

## Segundos que el cadáver permanece antes de desaparecer. 0 = desaparece inmediatamente.
## Asignado por NPCSpawner al instanciar.
var corpse_duration: float = 0.0
var is_dead: bool = false

## Segundos que el NPC queda paralizado tras recibir un golpe.
@export var hit_stun_duration: float = 0.35
var is_hit: bool = false
var _hit_timer: float = 0.0

var _frame_offset: int = 0
var _ai_update_stride: int = 1
## 0 = cada frame. > 0 = intervalo en segundos (spawner lo ajusta por distancia).
var _physics_interval: float = 0.0
var _physics_timer: float = 0.0

## Layer 2 para NPCs vivos. Los muertos pasan a layer 0 (invisibles).
## Cuando el jugador añada raycasts de ataque, incluir layer 2 en su collision_mask.
const NPC_LIVE_LAYER := 2

func _ready() -> void:
	safe_margin = 0.008
	floor_max_angle = deg_to_rad(70.0)
	floor_snap_length = 0.1
	collision_layer = NPC_LIVE_LAYER
	collision_mask  = 1 | NPC_LIVE_LAYER

	if entity_id.is_empty():
		entity_id = "npc_%d" % get_instance_id()
	add_to_group(GameManager.SAVEABLE_GROUP)
	add_to_group("npc")

	# Movement en modo IA: la dirección la inyecta el AIController, no el Input
	movement.use_ai_input = true

	# AnimationController es opcional (puede no haber modelo aún)
	animation_controller = get_node_or_null("AnimationController")

	# Perception es opcional
	perception = get_node_or_null("Perception")
	if perception:
		perception.npc = self
		perception.controller = ai_controller
		if detect_state != &"":
			perception.target_detected.connect(_on_target_detected)
		if lose_state != &"":
			perception.target_lost.connect(_on_target_lost)

	# Wiring del AIController con este cuerpo y el Movement
	ai_controller.npc = self
	ai_controller.movement = movement

	# Señales de salud
	movement.landed.connect(_on_landed)
	health_component.damaged.connect(_on_damaged)
	health_component.died.connect(_on_died)

	# Planeta de referencia
	update_nearest_planet()

	# Arrancar la FSM con el estado inicial
	if initial_ai_state != &"":
		ai_controller.start(initial_ai_state)

func _physics_process(delta: float) -> void:
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

	if Engine.get_physics_frames() % _ai_update_stride == _frame_offset:
		ai_controller.gravity_direction = gravity_direction
		ai_controller.update(delta * _ai_update_stride)

	var raw_dir := ai_controller.desired_direction
	movement.ai_direction = project_on_gravity_plane(raw_dir)

	if is_hit:
		_hit_timer -= delta
		if _hit_timer <= 0.0:
			is_hit = false
		movement.ai_direction = Vector3.ZERO

	movement.handle_run_movement(delta, ai_controller.is_attacking, gravity_direction, null)
	movement.handle_idle_movement(delta, gravity_direction, is_on_floor(), planet.gravity_strength, velocity)

	current_animation = movement.current_animation
	if ai_controller.is_attacking:
		current_animation = Config.ANIMATION.ATTACK_1
	if animation_controller:
		animation_controller.handle_animations(delta, current_animation, false)

	velocity = movement.velocity

	var rot_dir := project_on_gravity_plane(movement.direction)
	if rot_dir.length() > 0.1:
		rotate_toward_direction(rot_dir, delta)

	align_to_gravity(gravity_direction, delta)

	move_and_slide()


# ── Señales ─────────────────────────────────────────────────────────────────

func _on_target_detected(_target: Node3D) -> void:
	ai_controller.transition_to(detect_state)


func _on_target_lost() -> void:
	ai_controller.transition_to(lose_state)


func _on_damaged(_amount: float, _source: Node) -> void:
	if is_dead:
		return
	is_hit = true
	_hit_timer = hit_stun_duration
	if animation_controller:
		animation_controller.trigger_hit()


func _on_landed(impact_speed: float) -> void:
	health_component.take_fall_damage(impact_speed)


func _on_died() -> void:
	is_dead = true
	collision_layer = 0  # cadáver invisible a todos los NPCs vivos
	collision_mask  = 1  # solo terreno: el cadáver se queda en el suelo
	velocity = Vector3.ZERO
	ai_controller.desired_direction = Vector3.ZERO
	ai_controller.is_attacking = false
	if perception:
		perception.set_physics_process(false)
	if animation_controller:
		animation_controller.trigger_death()
	if corpse_duration <= 0.0:
		queue_free()
		return
	ai_controller.transition_to(&"DeathState")
	get_tree().create_timer(corpse_duration).timeout.connect(
		func(): if is_instance_valid(self): queue_free()
	)


# ── Save / Load ──────────────────────────────────────────────────────────────

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
