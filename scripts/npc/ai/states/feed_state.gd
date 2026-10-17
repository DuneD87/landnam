extends AIState
class_name FeedState

## Comer carne: va a [food] (los restos del jugador, PlayerRemains) y come lo que le toca
## (food.bite_point: la primera fiera, la parte que se trabaja; las demás, otra cada una), con los
## clips de su perfil (CreatureCombatProfile.feed_anims) uno tras otro y gruñendo de vez en cuando.
##   - Se coloca para que su boca caiga sobre lo que muerde: dónde queda la boca de media en sus
##     clips de comer (la punta de la mandíbula) se saca de las pistas de los clips
##     (BiteReach.clip_mouth); sin ellas, se mide mientras come; hasta entonces, la punta de su
##     cápsula. Si aun así no cae donde debe, se arrima despacio sin dejar de comer.
##   - BiteReach lleva la boca al punto exacto (gira cuello y cabeza), y a cada bocado (bite) la
##     cabeza entra y tira hacia atrás.
##   - Lo que arranca se lo lleva en la boca (hold): levanta la cabeza, lo sacude y lo suelta.
## Mientras come, Devouring despieza el cuerpo; acabado (food.devoured), sigue feed_time segundos y
## vuelve a IdleState. Lo monta NPCController.feed_on la primera vez. Ver a alguien o que le
## hieran lo saca de aquí como de cualquier estado (Perception, provoked_state).

## Si el sitio donde comer queda más lejos que esto (m, a tamaño 1), va andando; ya comiendo, no
## se levanta hasta que se aleja REPOSITION, y por encima de SHUFFLE se arrima sin dejar de comer.
const ARRIVE := 0.3
const REPOSITION := 1.0
const SHUFFLE := 0.03
## Lo deprisa que se arrima comiendo (m/s).
const SHUFFLE_SPEED := 0.6
## Lo que tarda la medida de la boca en seguir al clip, si no se ha podido sacar de él (s).
const MOUTH_SMOOTH := 0.8
## Antes de que acabe el clip, cuánto antes (s) se funde con el siguiente.
const CLIP_OVERLAP := 0.35
## Un bocado: lo que dura (s), lo que entra la cabeza y lo que tira hacia atrás y arriba (m).
const BITE_TIME := 0.45
const BITE_DIP := 0.05
const BITE_PULL := Vector2(0.14, 0.07)
## Lo arrancado en la boca: cuánto sube la cabeza, lo que sacude a los lados (m) y a qué ritmo.
const HOLD_LIFT := 0.15
const HOLD_SHAKE := 0.14
const HOLD_SHAKE_RATE := 15.0

@export var profile: CreatureCombatProfile

var food: Node3D

var _eating := false
var _anim := &""
var _clip_left := 0.0
var _next_growl := 0.0
## Lo que le queda comiendo una vez despiezado el cuerpo (s); se sortea al acabar el despiece.
var _after := -1.0
var _original_speed := 0.0
var _reach: BiteReach
## Dónde le queda la boca comiendo (marco del cuerpo, media de los clips); INF hasta saberlo.
var _mouth_local := Vector3.INF
## La media sale de los clips (no hay que medirla).
var _mouth_from_clips := false
var _bite_time := INF
var _bite_pull := Vector3.ZERO
## Lo que lleva en la boca (SeveredLimb), cuánto lleva y cuánto lo va a llevar.
var _held: Node3D
var _hold_time := 0.0
var _hold_length := 0.0


func enter() -> void:
	_eating = false
	_anim = &""
	_after = -1.0
	_bite_time = INF
	_next_growl = randf_range(profile.feed_growl.x, profile.feed_growl.y) * 0.5
	_original_speed = controller.movement.speed
	controller.target = null
	controller.is_attacking = false
	CombatDirector.leave_all(controller.npc)
	if _reach == null:
		_reach = BiteReach.for_npc(npc())
		if npc().animation_controller != null:
			profile.add_feed_library(npc().animation_controller.animator)
	_mouth_local = _clips_mouth()
	_mouth_from_clips = _mouth_local != Vector3.INF
	if is_instance_valid(food) and food.has_method(&"add_feeder"):
		food.add_feeder(self)


func exit() -> void:
	_release_held()
	_stop_eating()
	controller.movement.speed = _original_speed
	controller.desired_direction = Vector3.ZERO
	if _reach != null:
		_reach.wanted = 0.0
	if is_instance_valid(food) and food.has_method(&"remove_feeder"):
		food.remove_feeder(self)


## Con la boca en la comida, comiendo (también con algo en la boca).
func is_eating() -> bool:
	return _eating


func npc() -> NPCController:
	return controller.npc as NPCController


## Dónde está la boca (mundo, mirando como la mandíbula), con el cuello y la cabeza ya girados.
func mouth_transform() -> Transform3D:
	if _reach != null:
		return _reach.mouth
	return Transform3D(npc().global_basis, npc().global_position)


## Un bocado (lo marca Devouring): la cabeza entra en la carne y tira hacia [pull] (mundo).
func bite(pull: Vector3) -> void:
	_bite_time = 0.0
	_bite_pull = pull


## Se lleva [limb] (SeveredLimb) en la boca [seconds] segundos, sacudiéndolo, y lo suelta.
func hold(limb: Node3D, seconds: float) -> void:
	if _reach == null or not is_instance_valid(limb) or not limb.has_method(&"grab"):
		return
	_release_held()
	_held = limb
	_hold_time = 0.0
	_hold_length = seconds
	limb.grab(mouth_transform)
	# Con la cabeza en alto: sin el clip de comer, que la lleva al suelo.
	_anim = &""
	var channel := npc().get_action_channel()
	if channel != null:
		channel.stop()


func update(delta: float) -> StringName:
	if not is_instance_valid(food):
		return &"IdleState"
	if food.get(&"devoured"):
		if _after < 0.0:
			_after = randf_range(profile.feed_time.x, profile.feed_time.y)
		_after -= delta
		if _after <= 0.0:
			return &"IdleState"
	var body := npc()
	var point: Vector3 = food.bite_point(self) if food.has_method(&"bite_point") else food.feed_point()
	var to := controller.project_on_gravity_plane(point - body.global_position)
	if to == Vector3.ZERO:
		to = controller.project_on_gravity_plane(body.global_basis.z)
	var up := -controller.gravity_direction.normalized()
	var off := _stand_point(point, to, up) - body.global_position
	off -= up * off.dot(up)
	var gap := off.length() / body.body_size
	if gap > (REPOSITION if _eating else ARRIVE):
		_release_held()
		_stop_eating()
		var near := clampf(gap / 1.5, 0.35, 1.0)
		controller.movement.speed = profile.circle_speed * body.speed_scale * near
		controller.desired_direction = controller.steer_clear_of_water(off.normalized())
		controller.desired_facing = to if gap < 0.6 else Vector3.ZERO
		return &""
	# Comiendo: se arrima sin levantarse si la boca no acaba de caer donde debe.
	if gap > SHUFFLE and _held == null:
		controller.movement.speed = clampf(off.length() * 2.0, 0.1, SHUFFLE_SPEED) * body.speed_scale
		controller.desired_direction = off.normalized()
	else:
		controller.movement.speed = AIController.TURN_ONLY_SPEED
	controller.desired_facing = to
	controller.turn_rate = 120.0
	_eat(delta, point, up)
	return &""


## Dónde ponerse para que la boca caiga en [point], mirando hacia [to]: con la boca de los clips, o
## hasta saberla, a la punta de la cápsula.
func _stand_point(point: Vector3, to: Vector3, up: Vector3) -> Vector3:
	if _mouth_local == Vector3.INF:
		return point - to * _capsule_reach()
	var offset := Basis(up.cross(to).normalized(), up, to) * _mouth_local
	offset -= up * offset.dot(up)
	return point - offset


## Dónde le queda la boca de media comiendo (marco del cuerpo): la media de sus clips de comer en sus
## tramos (BiteReach.clip_mouth). INF si no se puede sacar de ellos.
func _clips_mouth() -> Vector3:
	var body := npc()
	var player: AnimationPlayer = body.animation_controller.animator if body.animation_controller != null else null
	if _reach == null or player == null:
		return Vector3.INF
	var sum := Vector3.ZERO
	var count := 0
	for i in profile.feed_anims.size():
		var mouth := _reach.clip_mouth(player, profile.feed_anims[i], profile.feed_range(i))
		if mouth != Vector3.INF:
			sum += mouth
			count += 1
	if count == 0:
		return Vector3.INF
	var world := body.get_skeleton().global_transform * (sum / count)
	return body.global_basis.orthonormalized().inverse() * (world - body.global_position)


## Come: los clips uno tras otro, fundidos (el siguiente entra antes de que acabe el anterior, para
## que no levante la cabeza entre uno y otro), la boca sobre [point] y algún gruñido.
func _eat(delta: float, point: Vector3, up: Vector3) -> void:
	_eating = true
	var body := npc()
	if _held != null:
		_update_hold(delta, up)
	else:
		var channel := body.get_action_channel()
		_clip_left -= delta
		if channel != null and (_anim == &"" or _clip_left <= 0.0 or not channel.is_playing()):
			_play_next(channel)
		if _reach != null:
			var mouth := _reach.animal_mouth() if not _mouth_from_clips else Vector3.INF
			if mouth != Vector3.INF:
				var local := body.global_basis.orthonormalized().inverse() * (mouth - body.global_position)
				_mouth_local = local if _mouth_local == Vector3.INF \
					else _mouth_local.lerp(local, 1.0 - exp(-delta / MOUTH_SMOOTH))
			# A la carne por donde caiga la boca, no a un punto fijo: lo justo para tocarla.
			var surface: Vector3 = food.bite_surface(self, _reach.animal_mouth()) \
				if food.has_method(&"bite_surface") else point
			_reach.wanted = 1.0
			_reach.target = surface + _bite_offset(delta, up)
	_next_growl -= delta
	if _next_growl <= 0.0:
		_next_growl = randf_range(profile.feed_growl.x, profile.feed_growl.y)
		var sound := profile.feed_sound if profile.feed_sound != &"" else profile.wait_sound
		if sound != &"":
			CombatFx.play(sound, body.global_position,
				{"pitch": profile.voice_pitch * body.voice_pitch * randf_range(0.92, 1.05), "volume_offset_db": -3.0})


## El bocado en curso: la cabeza entra un poco en la carne y luego tira hacia atrás y arriba.
func _bite_offset(delta: float, up: Vector3) -> Vector3:
	if _bite_time >= BITE_TIME:
		return Vector3.ZERO
	_bite_time += delta
	var x := clampf(_bite_time / BITE_TIME, 0.0, 1.0)
	var dip := smoothstep(0.0, 0.25, x) * (1.0 - smoothstep(0.25, 0.45, x))
	var pull := smoothstep(0.25, 0.55, x) * (1.0 - smoothstep(0.6, 1.0, x))
	return -up * BITE_DIP * dip + (_bite_pull * BITE_PULL.x + up * BITE_PULL.y) * pull


## Con algo en la boca: la cabeza arriba, sacudiéndolo de lado a lado, y al acabar lo suelta.
func _update_hold(delta: float, up: Vector3) -> void:
	_hold_time += delta
	if not is_instance_valid(_held) or _hold_time >= _hold_length:
		var side := up.cross(npc().global_basis.z).normalized()
		_release_held(side * randf_range(-2.0, 2.0) + up * 1.2)
		return
	if _reach == null:
		return
	var side := up.cross(npc().global_basis.z).normalized()
	var fade := 1.0 - smoothstep(0.6, 1.0, _hold_time / _hold_length)
	var shake := sin(_hold_time * HOLD_SHAKE_RATE) * HOLD_SHAKE * fade
	_reach.wanted = 1.0
	_reach.target = _reach.animal_mouth() + up * HOLD_LIFT + side * shake


func _release_held(velocity := Vector3.ZERO) -> void:
	if _held != null and is_instance_valid(_held) and _held.has_method(&"release"):
		_held.release(velocity)
	_held = null


## El siguiente clip (otro que el de ahora, si hay más), en su tramo (feed_range).
func _play_next(channel: CreatureActionChannel) -> void:
	var options: Array[int] = []
	for i in profile.feed_anims.size():
		if profile.feed_anims[i] != _anim or profile.feed_anims.size() == 1:
			options.append(i)
	var index: int = options.pick_random()
	_anim = profile.feed_anims[index]
	var span := profile.feed_range(index)
	var speed := maxf(profile.feed_anim_speed, 0.05)
	channel.play(_anim, speed, CLIP_OVERLAP, CLIP_OVERLAP, span.x)
	var length := span.y - span.x if span.y > span.x else _clip_length(_anim) - span.x
	_clip_left = maxf(length / speed - CLIP_OVERLAP, 0.3) if length > 0.0 else INF


func _clip_length(anim: StringName) -> float:
	var anim_controller := npc().animation_controller
	var player: AnimationPlayer = anim_controller.animator if anim_controller != null else null
	if player == null or not player.has_animation(anim):
		return 0.0
	return player.get_animation(anim).length


func _stop_eating() -> void:
	if _reach != null:
		_reach.wanted = 0.0
	if not _eating:
		return
	_eating = false
	_anim = &""
	var channel := npc().get_action_channel()
	if channel != null:
		channel.stop()


## De su origen a la boca (m) antes de medirla: la del perfil a su tamaño o, sin ella, hasta la
## punta de su cápsula.
func _capsule_reach() -> float:
	var body := npc()
	if profile.feed_reach > 0.0:
		return profile.feed_reach * body.body_size
	var shape := body.collision_shape
	var capsule := shape.shape as CapsuleShape3D if shape != null else null
	if capsule == null:
		return 0.8 * body.body_size
	var forward := controller.project_on_gravity_plane(body.global_basis.z)
	var ahead := maxf((shape.global_position - body.global_position).dot(forward), 0.0)
	return ahead + capsule.height * 0.5 * shape.global_basis.get_scale().x
