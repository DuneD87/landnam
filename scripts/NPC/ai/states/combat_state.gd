extends AIState
class_name CombatState

## El NPC persigue a controller.target y le inflige daño cuando está en rango.
## Vuelve a IdleState si el target se aleja o desaparece.

## Distancia máxima de persecución. Más allá, el NPC desiste.
@export var disengage_distance: float = 20.0
## Distancia a la que el NPC se detiene y ataca.
@export var attack_range: float = 1.8
## Daño por golpe.
@export var attack_damage: float = 15.0
## Segundos entre golpes.
@export var attack_cooldown: float = 1.5
## Multiplicador de velocidad durante el combate.
@export var speed_multiplier: float = 1.3
## Duración de la animación de ataque (segundos). Controla cuánto permanece is_attacking = true.
@export var attack_anim_duration: float = 0.6

var _attack_timer: float = 0.0
var _anim_timer: float = 0.0
var _original_speed: float = 0.0


func enter() -> void:
	_attack_timer = 0.0
	_anim_timer = 0.0
	_original_speed = controller.movement.speed
	controller.movement.speed = _original_speed * speed_multiplier


func update(delta: float) -> StringName:
	if not is_instance_valid(controller.target):
		return &"IdleState"

	if not controller.is_target_within(disengage_distance):
		return &"IdleState"

	var dist := controller.distance_to_target()

	if dist <= attack_range:
		controller.desired_direction = Vector3.ZERO
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = attack_cooldown
			_deal_damage()
	else:
		var to_target := controller.target.global_position - controller.npc.global_position
		controller.desired_direction = controller.project_on_gravity_plane(to_target)

	_anim_timer = max(0.0, _anim_timer - delta)
	controller.is_attacking = _anim_timer > 0.0

	return &""


func exit() -> void:
	controller.movement.speed = _original_speed
	controller.desired_direction = Vector3.ZERO
	controller.is_attacking = false
	_anim_timer = 0.0


func _deal_damage() -> void:
	_anim_timer = attack_anim_duration
	controller.is_attacking = true
	var health: HealthComponent = controller.target.get_node_or_null("HealthComponent")
	if health:
		health.take_damage(attack_damage, controller.npc)
