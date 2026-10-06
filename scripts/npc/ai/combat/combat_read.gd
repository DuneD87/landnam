class_name CombatRead
extends RefCounted

## Lo que una criatura sabe de su objetivo para elegir ataque (CreatureAttack.situations). Son
## nombres sueltos, para que cualquier objetivo nuevo (un humano, otra especie) entre sin tocar a
## las criaturas: lo que cuenta de sí mismo con get_combat_situation() y lo que se ve desde fuera.
##   windup      empieza un golpe que aún no hiere
##   active      está golpeando
##   recovering  acaba de golpear (o de fallar) y aún no se ha recompuesto
##   dodging     esquiva
##   aiming      apunta (arco, lanza)
##   staggered   se tambalea
##   fleeing     se aleja deprisa
##   back_turned da la espalda
##   weak        le queda poca vida

## Velocidad de alejamiento (m/s) a partir de la que huye.
const FLEE_SPEED := 2.5
## Fracción de vida por debajo de la que está débil.
const WEAK_HEALTH := 0.3


static func situations(observer: Node3D, target: Node3D, target_velocity: Vector3) -> Array[StringName]:
	var found: Array[StringName] = []
	if target == null or not is_instance_valid(target):
		return found
	if target.has_method(&"get_combat_situation"):
		var own: StringName = target.get_combat_situation()
		if own != &"":
			found.append(own)
	var away := target.global_position - observer.global_position
	if away.length_squared() > 1e-6:
		away = away.normalized()
		if target_velocity.dot(away) > FLEE_SPEED:
			found.append(&"fleeing")
		# El cuerpo mira por +Z (jugador y criaturas).
		if target.global_basis.z.normalized().dot(away) > 0.5:
			found.append(&"back_turned")
	var health := target.get_node_or_null("HealthComponent") as HealthComponent
	if health != null and health.get_health_ratio() < WEAK_HEALTH:
		found.append(&"weak")
	return found
