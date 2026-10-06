extends AIState
class_name TerritorialState

## Defiende su sitio del objetivo que se le acerca, sin ir a por él mientras no haga falta:
##   - lo vigila encarado;
##   - más cerca que warn_distance le avisa (amenaza con clip y sonido cada poco) y se le va
##     agotando la paciencia, más deprisa cuanto más se acerca;
##   - si se mete a menos de attack_distance o se le acaba la paciencia, pasa a combat_state (y
##     si le hieren también: NPCController.provoked_state);
##   - si se aleja más que calm_distance, se calma.
## Lo enciende IdleState/WanderState con threat_state cuando el objetivo entra en su radio. La
## paciencia gastada no vuelve de golpe: se recupera despacio, también fuera de este estado.

@export var warn_distance: float = 22.0
@export var attack_distance: float = 11.0
@export var calm_distance: float = 34.0
## Segundos a tiro de aviso (al borde; más cerca se gasta antes) que aguanta sin atacar.
@export var patience: float = 6.0
## Paciencia que recupera por segundo mientras el objetivo no está a tiro de aviso.
@export var patience_regen: float = 0.5
@export var combat_state: StringName = &"CombatState"
@export var calm_state: StringName = &"IdleState"

@export_group("Warning")
## Clips de amenaza, uno al azar cada vez; y lo que suena con ellos, a su tono.
@export var warn_anims: Array[StringName] = []
@export var warn_sound: StringName = &""
@export var warn_pitch: float = 1.0
## Segundos entre amenazas.
@export var warn_interval := Vector2(2.5, 4.0)

## Paciencia gastada (s). La leen la consola y las pruebas.
var annoyance: float = 0.0

var _next_warn: float = 0.0
var _left_at_ms: int = 0


func enter() -> void:
	# Lo que ha recuperado desde la última vez.
	if _left_at_ms > 0:
		var away := (Time.get_ticks_msec() - _left_at_ms) / 1000.0
		annoyance = maxf(0.0, annoyance - away * patience_regen)
	_next_warn = 0.0


func exit() -> void:
	_left_at_ms = Time.get_ticks_msec()
	controller.desired_direction = Vector3.ZERO


func update(delta: float) -> StringName:
	var target := controller.target
	if target == null or not is_instance_valid(target):
		return calm_state
	var health := target.get_node_or_null("HealthComponent") as HealthComponent
	if health != null and health.is_dead:
		return calm_state
	var dist := controller.distance_to_target()
	if dist > calm_distance:
		return calm_state
	if dist <= attack_distance:
		return combat_state
	controller.movement.speed = AIController.TURN_ONLY_SPEED
	controller.desired_facing = controller.project_on_gravity_plane(target.global_position - controller.npc.global_position)
	if dist > warn_distance:
		annoyance = maxf(0.0, annoyance - delta * patience_regen)
		return &""
	# Al borde del aviso gasta a ritmo 1; pegado a attack_distance, a ritmo 3.
	var closeness := clampf((warn_distance - dist) / maxf(warn_distance - attack_distance, 0.1), 0.0, 1.0)
	annoyance += delta * (1.0 + 2.0 * closeness)
	if annoyance >= patience:
		return combat_state
	_next_warn -= delta
	if _next_warn <= 0.0:
		_next_warn = randf_range(warn_interval.x, warn_interval.y)
		_warn()
	return &""


func _warn() -> void:
	var npc := controller.npc as NPCController
	var channel := npc.get_action_channel()
	if not warn_anims.is_empty() and channel != null:
		channel.play(warn_anims.pick_random(), 1.0, 0.25, 0.4)
	if warn_sound != &"":
		CombatFx.play(warn_sound, npc.global_position, {"pitch": warn_pitch * randf_range(0.95, 1.05)})


## Una línea para la consola (ia).
func debug_line() -> String:
	var text := "paciencia %.1f/%.1f s" % [annoyance, patience]
	if controller.target != null and is_instance_valid(controller.target):
		text += "  → %s a %.1f m (aviso %.0f, ataque %.0f)" % [controller.target.name,
			controller.distance_to_target(), warn_distance, attack_distance]
	return text
