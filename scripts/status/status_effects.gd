class_name StatusEffects
extends Node

## Estados duraderos de una entidad (pierna rota, intoxicación, enfermedad…; ver StatusEffectData):
## les cuenta el tiempo, los guarda en la partida y responde a los sistemas que preguntan qué
## limitan (blocks, speed_mult, is_zone_impaired…). Lo único que hace por su cuenta es quitar o dar
## la vida de health_per_second, en puntos enteros como el sangrado de BodyDamage.
##
## El tiempo es de juego: corre con _physics_process (se para con la pausa) y advance() lo adelanta
## de golpe (dormir). Lo que le queda a cada estado se guarda tal cual: al cargar sigue donde iba.

## Le ha pasado (o le ha vuelto a pasar) [effect]. No al cargar la partida.
signal applied(effect: StatusEffect)
## [cured]: lo quitó una cura o reaparecer; false: se le acabó el tiempo.
signal ended(effect: StatusEffect, cured: bool)

var health: HealthComponent

var _effects: Array[StatusEffect] = []
var _health_debt := 0.0


func _physics_process(delta: float) -> void:
	if not _effects.is_empty():
		advance(delta)


## Le pasa [effect_id] en [zone] (se ignora si el estado no va por zonas), con la duración de su
## gravedad o, si se da, [duration] segundos. Si ya lo tenía, se acumula según su Stacking.
func apply(effect_id: StringName, zone: StringName = &"", severity: float = 0.5,
		duration: float = -1.0) -> StatusEffect:
	var data := StatusEffectData.find(effect_id)
	if data == null:
		push_warning("StatusEffects: estado desconocido '%s'" % effect_id)
		return null
	if health != null and health.is_dead:
		return null
	if not data.per_zone:
		zone = &""
	var time := duration if duration >= 0.0 else data.duration_for(severity)
	var current := get_effect(effect_id, zone)
	if current != null:
		match data.stacking:
			StatusEffectData.Stacking.IGNORE:
				return current
			StatusEffectData.Stacking.EXTEND:
				current.remaining += time
			_:
				current.remaining = maxf(current.remaining, time)
		current.severity = maxf(current.severity, clampf(severity, 0.0, 1.0))
		applied.emit(current)
		return current
	var effect := StatusEffect.new(data, zone, severity, time)
	_effects.append(effect)
	data.on_apply(self, effect)
	applied.emit(effect)
	return effect


## Lo cura antes de tiempo. Sin [zone], en todas las partes. Devuelve si tenía algo que curar.
func remove(effect_id: StringName, zone: StringName = &"") -> bool:
	var found := false
	for effect in _effects.duplicate():
		if effect.data.id == effect_id and (zone == &"" or effect.zone == zone):
			_end(effect, true)
			found = true
	return found


## Cura todo lo que responda a [tag] (StatusEffectData.cure_tags).
func cure(tag: StringName) -> bool:
	var found := false
	for effect in _effects.duplicate():
		if effect.data.cure_tags.has(tag):
			_end(effect, true)
			found = true
	return found


## Todo sano otra vez (reaparecer; al cargar, load_data vuelve a poner lo guardado).
func restore() -> void:
	for effect in _effects.duplicate():
		_end(effect, true)
	_health_debt = 0.0


## Pasa [seconds] de juego: cada estado se descuenta lo suyo, y el que llega a cero se acaba. La
## vida que da o quita cada uno solo cuenta mientras le quedaba tiempo.
func advance(seconds: float) -> void:
	if seconds <= 0.0:
		return
	for effect in _effects.duplicate():
		effect.data.on_tick(self, effect, seconds)
		if not _effects.has(effect):
			continue
		var lived := minf(seconds, maxf(effect.remaining, 0.0))
		_health_debt += effect.data.health_per_second * lived
		effect.elapsed += seconds
		effect.remaining -= seconds
		if effect.remaining <= 0.0:
			_end(effect, false)
	_settle_health()


# ---------------------------------------------------------------------------------------------
# Lo que preguntan los demás sistemas


func effects() -> Array[StatusEffect]:
	return _effects


func get_effect(effect_id: StringName, zone: StringName = &"") -> StatusEffect:
	for effect in _effects:
		if effect.data.id == effect_id and effect.zone == zone:
			return effect
	return null


## Sin [zone], si lo tiene en alguna parte.
func has(effect_id: StringName, zone: StringName = &"") -> bool:
	for effect in _effects:
		if effect.data.id == effect_id and (zone == &"" or effect.zone == zone):
			return true
	return false


## La parte [zone] no sirve (una pierna rota no carga peso).
func is_zone_impaired(zone: StringName) -> bool:
	for effect in _effects:
		if effect.zone == zone and effect.data.impairs_zone:
			return true
	return false


## Algún estado impide [action] (sprint, jump, dodge, attack, climb).
func blocks(action: StringName) -> bool:
	for effect in _effects:
		if effect.data.blocks.has(action):
			return true
	return false


func speed_mult() -> float:
	var mult := 1.0
	for effect in _effects:
		mult *= effect.data.speed_mult
	return mult


func stamina_regen_mult() -> float:
	var mult := 1.0
	for effect in _effects:
		mult *= effect.data.stamina_regen_mult
	return mult


# ---------------------------------------------------------------------------------------------
# Partida guardada


func save_data() -> Array:
	var out := []
	for effect in _effects:
		out.append(effect.to_dict())
	return out


## Vuelve a poner los estados de [data] (de save_data()) con lo que les quedaba, sin avisar con
## applied ni llamar a on_apply: no es nada nuevo.
func load_data(data: Array) -> void:
	for entry in data:
		if not entry is Dictionary:
			continue
		var effect := StatusEffect.from_dict(entry)
		if effect == null:
			continue
		if not effect.data.per_zone:
			effect.zone = &""
		if get_effect(effect.data.id, effect.zone) == null:
			_effects.append(effect)


func _end(effect: StatusEffect, cured: bool) -> void:
	_effects.erase(effect)
	effect.data.on_end(self, effect, cured)
	ended.emit(effect, cured)


func _settle_health() -> void:
	if health == null or health.is_dead:
		_health_debt = 0.0
		return
	if _health_debt <= -1.0:
		var amount := floorf(-_health_debt)
		_health_debt += amount
		health.take_damage(amount)
	elif _health_debt >= 1.0:
		var amount := floorf(_health_debt)
		_health_debt -= amount
		health.heal(amount)
