class_name WeatherLightning
extends RefCounted

## Generador (lógica pura) del parpadeo de los relámpagos de tormenta. El WeatherController lo
## actualiza con la frecuencia de rayos y un factor de proximidad, y usa el 0..1 que devuelve
## update() para sumarlo a la iluminación. Cada descarga dispara 1-3 sub-destellos escalonados.

# Sub-destellos por descarga (un rayo suele parpadear 1-3 veces).
const MIN_SUBFLASHES := 1
const MAX_SUBFLASHES := 3
# Ataque (subida) y caída de cada sub-destello (s).
const ATTACK := 0.04
const DECAY := 0.38
const SPIKE_DURATION := ATTACK + DECAY
# Separación entre sub-destellos de una misma descarga (s).
const SUBFLASH_GAP_MIN := 0.05
const SUBFLASH_GAP_MAX := 0.13

# true solo el frame en que arranca una descarga nueva (gancho para el trueno o gameplay/UI).
var strike_started: bool = false

var _spikes: Array = []
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## Avanza el generador y devuelve el brillo del destello (0..1) de este frame.
## frequency: rayos/seg del clima actual; proximity: 0..1 (no relampaguea sobre las nubes).
func update(delta: float, frequency: float, proximity: float) -> float:
	strike_started = false
	_clock += delta

	var active_freq := frequency * clampf(proximity, 0.0, 1.0)
	if active_freq > 0.0 and _rng.randf() < active_freq * delta:
		_trigger_strike()

	return _sample_and_prune()


## Encola los sub-destellos de una descarga (1-3 spikes escalonados).
func _trigger_strike() -> void:
	strike_started = true
	var count := _rng.randi_range(MIN_SUBFLASHES, MAX_SUBFLASHES)
	var t := _clock
	for _k in count:
		_spikes.append([t, _rng.randf_range(0.6, 1.0)])
		t += _rng.randf_range(SUBFLASH_GAP_MIN, SUBFLASH_GAP_MAX)


## Suma el aporte de todos los sub-destellos vivos y descarta los ya extinguidos.
func _sample_and_prune() -> float:
	var total := 0.0
	var alive: Array = []
	for spike in _spikes:
		var dt: float = _clock - spike[0]
		if dt > SPIKE_DURATION:
			continue
		alive.append(spike)
		if dt >= 0.0:
			total += float(spike[1]) * _envelope(dt)
	_spikes = alive
	return clampf(total, 0.0, 1.0)


## Sobre del sub-destello: subida lineal en ATTACK y caída lineal en DECAY.
func _envelope(dt: float) -> float:
	if dt < ATTACK:
		return dt / ATTACK
	return maxf(1.0 - (dt - ATTACK) / DECAY, 0.0)
