class_name SkinnedFaunaModel
extends SkinnedModel

## El modelo con esqueleto de un animal pequeño de tierra: pone el clip que toca por lo que hace el
## cuerpo (quieto, a ratos pastando, o el ciclo de marcha más parecido a su velocidad, al ritmo de
## esa velocidad para que las patas no patinen). Misma interfaz que SimpleSmallAnimalModel para
## AmbientSmallGroundAnimal: set_data en vez de set_species, animate y advance.

## Por debajo de esta velocidad (m/s) está quieto.
const STILL_SPEED := 0.12
## Cambia de ciclo de marcha solo si el nuevo le va bastante mejor (en logaritmo del ritmo).
const GAIT_HYSTERESIS := 0.2
## Ritmo de los clips de marcha, como mucho.
const RATE_RANGE := Vector2(0.5, 2.0)

var _gait: int = -1
var _speed: float = 0.0
## Descanso: 0 = no, 1 = entrando, 2 = en bucle.
var _rest: int = 0
var _still_time: float = 0.0


func _init() -> void:
	cost_label = &"fauna:small_ground/anim"


func set_data(model: FaunaModelData, seed_value: int = 0) -> void:
	_gait = -1
	_speed = 0.0
	_rest = 0
	_still_time = 0.0
	super.set_data(model, seed_value)


## Pose fija para vistas previas y pruebas: el clip de [speed] en el instante [time].
func animate(time: float, speed: float) -> void:
	if data == null:
		return
	_speed = speed
	_pick(0.0)
	player.seek(fmod(time * player.speed_scale, maxf(player.current_animation_length, 0.01)), true)


## Lo que hace el cuerpo este paso de física: lo usa para elegir clip. [speed] en m/s de la especie
## a escala 1 (el cuerpo ya dividido por el tamaño del individuo).
func advance(delta: float, speed: float, _grounded: bool = true,
		_vertical_speed: float = 0.0, _turn: float = 0.0) -> void:
	if data == null:
		return
	_speed = lerpf(_speed, maxf(speed, 0.0), 1.0 - exp(-delta * 10.0))
	_pick(delta)


## Elige el clip: marcha si se mueve, y si no, quieto o descansando.
func _pick(delta: float) -> void:
	if _speed > STILL_SPEED and not data.gait_clips.is_empty():
		_still_time = 0.0
		_rest = 0
		var best := _best_gait(_speed)
		if _gait >= 0 and best != _gait and absf(_rate_log(best)) + GAIT_HYSTERESIS > absf(_rate_log(_gait)):
			best = _gait
		_gait = best
		var rate := clampf(_speed / _gait_speed(best), RATE_RANGE.x, RATE_RANGE.y)
		_play(data.gait_clips[best], data.blend_time, rate)
		return
	_gait = -1
	_still_time += delta
	if data.rest_clips.size() >= 2:
		match _rest:
			0:
				if _still_time > 0.0 and _still_time - delta <= 0.0 and _rng.randf() < data.rest_chance:
					_rest = 1
					_play(data.rest_clips[0], data.blend_time, 1.0)
					return
			1:
				if _clip_done():
					_rest = 2
					_play(data.rest_clips[1], 0.1, 1.0)
				return
			2:
				return
	_play(data.idle_clip, data.blend_time, 1.0)


func _best_gait(speed: float) -> int:
	var best := 0
	for i in data.gait_clips.size():
		if absf(log(speed / _gait_speed(i))) < absf(log(speed / _gait_speed(best))):
			best = i
	return best


func _rate_log(gait: int) -> float:
	return log(maxf(_speed, 0.01) / _gait_speed(gait))


func _gait_speed(i: int) -> float:
	return maxf(data.gait_speeds[i] if i < data.gait_speeds.size() else 1.0, 0.01) * data.scale
