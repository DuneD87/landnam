extends PlanetaryBody
class_name NPCController

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

@onready var movement: Movement = $Movement
@onready var health_component: HealthComponent = $HealthComponent
@onready var ai_controller: AIController = $AIController
@onready var inventory: Inventory = $Inventory
## Asignado automáticamente si existe el nodo hijo "AnimationController".
var animation_controller: AnimationController
var current_animation  # Config.ANIMATION value


func _ready() -> void:
	safe_margin = 0.008
	floor_max_angle = deg_to_rad(70.0)
	floor_snap_length = 0.1

	# Movement en modo IA: la dirección la inyecta el AIController, no el Input
	movement.use_ai_input = true

	# AnimationController es opcional (puede no haber modelo aún)
	animation_controller = get_node_or_null("AnimationController")

	# Wiring del AIController con este cuerpo y el Movement
	ai_controller.npc = self
	ai_controller.movement = movement

	# Señales de salud
	movement.landed.connect(_on_landed)
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

	# Gravedad planetaria (heredado: gravity_direction, up_direction)
	gravity_direction = planet.get_gravity_direction(global_position)
	up_direction = -gravity_direction

	# ── IA ──────────────────────────────────────────────────────────────────
	# El estado activo escribe ai_controller.desired_direction en espacio mundo.
	# Lo proyectamos en el plano de gravedad antes de inyectarlo en Movement.
	ai_controller.gravity_direction = gravity_direction
	ai_controller.update(delta)

	var raw_dir := ai_controller.desired_direction
	movement.ai_direction = project_on_gravity_plane(raw_dir) if raw_dir.length() > 0.01 \
			else Vector3.ZERO

	# ── Movimiento ──────────────────────────────────────────────────────────
	# camera = null es seguro: con use_ai_input = true nunca se accede a ella
	var move_dir := movement.handle_run_movement(delta, false, gravity_direction, null)
	movement.handle_idle_movement(delta, gravity_direction, is_on_floor(), planet.gravity_strength, velocity)

	current_animation = movement.current_animation
	if animation_controller:
		animation_controller.handle_animations(delta, current_animation, false)

	velocity = movement.velocity

	if movement.is_running or movement.is_sprinting:
		rotate_toward_direction(move_dir, delta)  # de PlanetaryBody

	align_to_gravity(gravity_direction, delta)    # de PlanetaryBody
	move_and_slide()


# ── Señales ─────────────────────────────────────────────────────────────────

func _on_landed(impact_speed: float) -> void:
	health_component.take_fall_damage(impact_speed)


## Comportamiento por defecto al morir: desaparecer.
## Subclases pueden override para drops de loot, animación de muerte, etc.
func _on_died() -> void:
	queue_free()
