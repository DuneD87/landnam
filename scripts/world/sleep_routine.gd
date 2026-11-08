class_name SleepRoutine
extends RefCounted

## Acostarse, dormir y levantarse en un lecho (o en el suelo), con las animaciones de Mixamo de la tanda
## "village" (tools/combat/retarget_mixamo.gd) encadenadas:
##   acostarse: sentado (wake) -> se echa hacia atrás (lie_back al revés: de la cabeza alzada a plano)
##              -> se gira de lado (el final de sleep_toss) -> sleep_side, en bucle;
##   dormido:   sleep_side y, de vez en cuando, una vuelta (sleep_toss entero, que acaba como empieza);
##   levantarse: se gira boca arriba (un tramo de sleep_toss) -> alza la cabeza (lie_back) -> sentado
##              (wake) -> done(): quien lo lleva lo pone de pie a los pies del lecho.
## Los giros salen de la captura de sleep_toss: mezclar sin más boca arriba con de lado lo incorporaba
## a medias con un brazo en alto.
## Dormido (desde que se gira de lado hasta que se vuelve boca arriba) cierra los ojos.
## No mueve a nadie: quien lo lleva lo apoya en el lecho (Villager.bed_fit) mientras settling() o, ya
## dormido, de vez en cuando.

const SIT := &"village/wake"
const LIE := &"village/lie_back"
const SLEEP := &"village/sleep_side"
const TOSS := &"village/sleep_toss"
## El tramo de lie_back que va de tumbado plano a alzar la cabeza (s).
const LIE_FROM := 0.6
const LIE_TO := 1.9
## Los tramos de sleep_toss (s): de boca arriba a la pose de sleep_side (el giro, de 14,5 a 15,5), y
## de esa pose a boca arriba (el giro, de 5,5 a 7,5).
const TO_SIDE_FROM := 13.0
const TO_BACK_FROM := 4.5
const TO_BACK_TO := 7.8
## Sentado en el lecho al acostarse y al levantarse (s).
const SIT_TIME := 1.3
const RISE_TIME := 1.4
## Mezclas (s): de sentado a echarse; de plano a boca arriba en sleep_toss (dobla las rodillas y cruza
## los brazos) y al revés, y de dormido al tramo que lo pone boca arriba; entre sleep_side y sleep_toss
## entero (la misma pose); a sentarse. Las de poses distintas, despacio: más deprisa, las manos iban a
## 3 m/s.
const LIE_BLEND := 0.6
const ROLL_BLEND := 1.2
const TOSS_BLEND := 0.4
const RISE_BLEND := 0.8
## Cada cuánto da una vuelta (s).
const TOSS_EVERY := Vector2(45.0, 150.0)
## Cada tramo se deja un poco antes de su final (s): mezclar con un clip que ya ha acabado (o que vuelve
## a empezar) promedia poses opuestas, boca arriba y de lado, y sale la de reposo a medio sentar.
const END_MARGIN := 0.1
## Lo que tarda en asentarse una mezcla: hasta ahí se apoya en el lecho a cada pose (s).
const SETTLE := 1.5

enum Step {NONE, SIT_DOWN, LIE_DOWN, ROLL_SIDE, ASLEEP, TOSS, ROLL_BACK, LIE_UP, SIT_UP, DONE}

var step := Step.NONE
var _left := 0.0
var _since := 0.0
var _player: AnimationPlayer
var _rig: CharacterAppearanceRig
var _rng := RandomNumberGenerator.new()


## [rig]: el del humano, para cerrarle los ojos (o null).
func _init(player: AnimationPlayer, seed: int, rig: CharacterAppearanceRig = null) -> void:
	_player = player
	_rig = rig
	_rng.seed = seed


## Fuera del lecho (lo han puesto de pie de golpe, o se ha ido): con los ojos abiertos.
func reset() -> void:
	_go(Step.NONE, 0.0)


## Se acuesta; [instant]: ya dormido (al aparecer de noche).
func lie_down(instant := false) -> void:
	if instant:
		_go(Step.ASLEEP, _toss_wait())
		_player.play(SLEEP, 0.0)
	else:
		_go(Step.SIT_DOWN, SIT_TIME)
		_player.play(SIT, 0.0)


## Empieza a levantarse (si no lo está haciendo ya).
func get_up() -> void:
	if step == Step.ROLL_BACK or step == Step.LIE_UP or step == Step.SIT_UP or step == Step.DONE:
		return
	_go(Step.ROLL_BACK, TO_BACK_TO - TO_BACK_FROM - END_MARGIN)
	_player.play_section(TOSS, TO_BACK_FROM, TO_BACK_TO, ROLL_BLEND)


func update(delta: float) -> void:
	_since += delta
	_left -= delta
	if _left > 0.0:
		return
	match step:
		Step.SIT_DOWN:
			_go(Step.LIE_DOWN, LIE_TO - LIE_FROM - END_MARGIN)
			_player.play_section_backwards(LIE, LIE_FROM, LIE_TO, LIE_BLEND)
		Step.LIE_DOWN:
			var toss := _player.get_animation(TOSS).length
			_go(Step.ROLL_SIDE, toss - TO_SIDE_FROM - END_MARGIN)
			_player.play_section(TOSS, TO_SIDE_FROM, toss, ROLL_BLEND)
		Step.ROLL_SIDE:
			_go(Step.ASLEEP, _toss_wait())
			_player.play(SLEEP, TOSS_BLEND)
		Step.ASLEEP:
			_go(Step.TOSS, _player.get_animation(TOSS).length - END_MARGIN)
			_player.play(TOSS, TOSS_BLEND)
		Step.TOSS:
			_go(Step.ASLEEP, _toss_wait())
			_player.play(SLEEP, TOSS_BLEND)
		Step.ROLL_BACK:
			_go(Step.LIE_UP, LIE_TO - LIE_FROM - END_MARGIN)
			_player.play_section(LIE, LIE_FROM, LIE_TO, ROLL_BLEND)
		Step.LIE_UP:
			_go(Step.SIT_UP, RISE_TIME)
			_player.play(SIT, RISE_BLEND)
		Step.SIT_UP:
			_go(Step.DONE, INF)


## Dormido (de lado o dando una vuelta): ya puede levantarse cuando toque.
func asleep() -> bool:
	return step == Step.ASLEEP or step == Step.TOSS


## Ya sentado del todo al levantarse: a ponerlo de pie.
func done() -> bool:
	return step == Step.DONE


## Cambiando de pose: hay que apoyarlo en el lecho a cada una. Quieto dormido, de vez en cuando basta.
func settling() -> bool:
	return step != Step.ASLEEP or _since < SETTLE


func _go(next: Step, time: float) -> void:
	step = next
	_left = time
	_since = 0.0
	if _rig != null:
		_rig.set_eyes_shut(next == Step.ROLL_SIDE or next == Step.ASLEEP or next == Step.TOSS)


func _toss_wait() -> float:
	return _rng.randf_range(TOSS_EVERY.x, TOSS_EVERY.y)
