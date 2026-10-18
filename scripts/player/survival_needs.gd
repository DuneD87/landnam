class_name SurvivalNeeds
extends Node

## Necesidades del jugador: hambre, sed, descanso, cordura, oxígeno y temperatura del cuerpo. Todas
## van de 0 a 1 con 1 = bien (saciado, bebido, descansado, cuerdo, con aire), salvo la temperatura,
## que va de -1 (helado) a 1 (abrasado) con 0 = a gusto. Las enseña la consola de la barra rápida
## (Hotbar.show_needs) y la ficha de atributos del inventario; ver docs/survival.md.
##
## Hambre, sed y descanso bajan solas, más deprisa con esfuerzo (lo que gasta aguante, nadar). El
## frío da hambre y el calor, sed. La temperatura del cuerpo va hacia la que se siente: la del
## clima del planeta (latitud, altura y estación), la hora, el tiempo, si se está mojado y, en el
## agua, la del agua, que enfría mucho más deprisa. La cordura baja a oscuras, sin dormir y con
## hambre o sed, y se rehace de día si se ha descansado. El oxígeno solo baja con la cabeza bajo el
## agua. Vacías, hambre, sed y oxígeno quitan vida, igual que el frío o el calor extremos; el
## cansancio y el frío hacen que el aguante se recupere más despacio.
##
## Lo compensan comer y beber (eat, drink: desde la barra, junto al agua dulce o de los odres; ver
## SurvivalActions), la ropa puesta, que abriga (InsulationTrait), y las hogueras encendidas
## (Campfire), que calientan, secan y alumbran: a su luz la oscuridad no quita cordura. Todavía no
## hay forma de dormir.

## Segundos de lleno a vacío en reposo (a ritmo 1).
const HUNGER_TIME := 2700.0
const THIRST_TIME := 1800.0
const REST_TIME := 3600.0
## Aire que dura una zambullida y lo que tarda en volver al sacar la cabeza.
const OXYGEN_TIME := 40.0
const OXYGEN_REFILL := 4.0
## Cordura: a oscuras, muy cansado o pasando hambre o sed baja; de día y descansado se rehace.
const SANITY_DARK_TIME := 2400.0
const SANITY_TIRED_TIME := 1800.0
const SANITY_NEED_TIME := 3600.0
const SANITY_DAY_TIME := 1500.0
## Segundos que tarda el cuerpo en ir a la temperatura que siente (en el aire; en el agua, mucho menos).
const WARMTH_TIME := 90.0
const WARMTH_WATER_TIME := 20.0
## Grados (°C) entre los que se está a gusto, y a cuánto de ellos se llega al extremo.
const COMFORT_LOW := 10.0
const COMFORT_HIGH := 24.0
const COLD_SPAN := 22.0
const HEAT_SPAN := 16.0
## Lluvia que empapa del todo y lo que se tarda en secarse.
const SOAK_TIME := 60.0
const DRY_TIME := 240.0
## Vida por segundo con la necesidad vacía (o la temperatura al extremo).
const STARVE_DPS := 0.25
const DEHYDRATE_DPS := 0.4
const DROWN_DPS := 8.0
const EXPOSURE_DPS := 0.35
## La vida se quita a golpes de este tamaño, no a pellizcos cada tick.
const DAMAGE_STEP := 2.0
## Temperatura (de -1 a 1) a partir de la que el frío o el calor hacen daño.
const EXPOSURE_START := 0.85
## Lo que el tiempo resta a la temperatura sentida, al aire libre.
const WEATHER_CHILL := {"storm": -3.0, "snow": -5.0, "wind": -3.0, "fog": -1.0}
## Lo que quita la sed un trago (de un río, un lago o un odre).
const SIP := 0.2
## Los valores, por el nombre de su propiedad (el de la consola y la barra rápida).
const NAMES: Array[String] = ["hunger", "thirst", "rest", "sanity", "oxygen", "warmth", "wetness"]

var hunger := 1.0
var thirst := 1.0
var rest := 1.0
var sanity := 1.0
var oxygen := 1.0
var warmth := 0.0
var wetness := 0.0
## Tragos de agua en los odres (de todos juntos; caben water_capacity()).
var water := 0

## Lo que se siente ahora (°C) y si la cabeza está bajo el agua: los calcula cada tick.
var felt_temperature := 18.0
var submerged := false
## Pausa las necesidades (consola) y su ritmo (consola: acelerarlas para verlas cambiar).
var paused := false
var rate := 1.0

var _player: PlayerController
var _pending_damage := 0.0
var _exertion := 0.0
var _last_stamina := -1.0
var _daylight := 1.0
var _climate_timer := 0.0
var _base_temperature := 18.0
var _skeleton: Skeleton3D
var _head_bone := -1
## De la ropa puesta (°C) y de las hogueras cercanas (calor en °C, luz de 0 a 1).
var _insulation := 0.0
var _fire_heat := 0.0
var _fire_light := 0.0


func setup(player: PlayerController) -> void:
	_player = player
	_skeleton = player.get_node_or_null("PlayerModel/Armature/Skeleton3D") as Skeleton3D
	if _skeleton != null:
		_head_bone = _skeleton.find_bone(CharacterAppearanceRig.HEAD_BONE)


func _physics_process(delta: float) -> void:
	if _player == null or paused or _player.free_flight_enabled or not _player.visible:
		return
	var health := _player.health_component
	if health == null or health.is_dead:
		return
	var dt := delta * rate
	_climate_timer -= delta
	if _climate_timer <= 0.0:
		_climate_timer = 0.5
		_base_temperature = _climate_temperature()
		_daylight = _local_daylight()
		_insulation = _worn_insulation()
		_update_fires()
		water = mini(water, water_capacity())
	submerged = _head_under_water()
	_update_exertion(delta)

	var swimming: bool = _player.movement.is_swimming
	var effort := 1.0 + 0.8 * maxf(_exertion, 0.5 if swimming else 0.0)
	hunger -= dt / HUNGER_TIME * effort * (1.0 + 0.5 * maxf(-warmth, 0.0))
	thirst -= dt / THIRST_TIME * effort * (1.0 + maxf(warmth, 0.0))
	rest -= dt / REST_TIME * (1.0 + 0.3 * _exertion)
	if submerged:
		oxygen -= dt / OXYGEN_TIME
	else:
		oxygen += delta / OXYGEN_REFILL
	_update_wetness(dt, swimming)
	_update_warmth(dt, swimming)
	_update_sanity(dt)
	_clamp_all()
	_hurt(dt, health)


## Multiplica la recuperación del aguante (lo aplica PlayerCombat con los estados).
func stamina_regen_mult() -> float:
	var mult := lerpf(0.4, 1.0, smoothstep(0.0, 0.3, rest))
	mult *= 1.0 - 0.4 * smoothstep(0.5, 1.0, -warmth)
	if hunger <= 0.0 or thirst <= 0.0:
		mult *= 0.7
	return mult


## Come o bebe lo que dice [edible]: lo suma a cada necesidad y cura lo suyo. Devuelve si intoxica
## (lo tira con su probabilidad; quien come le pone el estado).
func eat(edible: EdibleTrait) -> bool:
	hunger += edible.hunger
	thirst += edible.thirst
	sanity += edible.sanity
	_clamp_all()
	if edible.health > 0.0 and _player != null:
		_player.health_component.heal(edible.health)
	elif edible.health < 0.0 and _player != null:
		_player.health_component.take_damage(-edible.health)
	return randf() < edible.intoxication_chance


func drink(amount: float = SIP) -> void:
	thirst = clampf(thirst + amount, 0.0, 1.0)


## Tragos que caben en todos los odres que se llevan.
func water_capacity() -> int:
	if _player == null:
		return 0
	var total := 0
	for item in _player.inventory.items:
		var container := item.data.get_trait(WaterContainerTrait) as WaterContainerTrait if item != null else null
		if container != null:
			total += container.capacity * item.quantity
	return total


## Todo lleno y a gusto (al reaparecer o con la consola).
func refill() -> void:
	hunger = 1.0
	thirst = 1.0
	rest = 1.0
	sanity = 1.0
	oxygen = 1.0
	warmth = 0.0
	wetness = 0.0
	_pending_damage = 0.0


## Valor de una necesidad por su nombre (ver NAMES).
func get_value(need: String) -> float:
	return get(need)


func set_value(need: String, value: float) -> void:
	var low := -1.0 if need == "warmth" else 0.0
	set(need, clampf(value, low, 1.0))


## Si la necesidad está tan baja que hay que avisar (el medallón late).
func is_critical(need: String) -> bool:
	match need:
		"warmth":
			return absf(warmth) >= 0.65
		"oxygen":
			return oxygen <= 0.25
		_:
			return get_value(need) <= 0.15


## Lo que se siente, en palabras: para la ficha de atributos.
func temperature_word() -> String:
	if warmth <= -0.85:
		return tr("TEMP_FREEZING")
	if warmth <= -0.45:
		return tr("TEMP_COLD")
	if warmth <= -0.15:
		return tr("TEMP_COOL")
	if warmth < 0.15:
		return tr("TEMP_COMFORTABLE")
	if warmth < 0.45:
		return tr("TEMP_WARM")
	if warmth < 0.85:
		return tr("TEMP_HOT")
	return tr("TEMP_SCORCHING")


func save_data() -> Dictionary:
	return {
		"hunger": hunger, "thirst": thirst, "rest": rest, "sanity": sanity,
		"oxygen": oxygen, "warmth": warmth, "wetness": wetness, "water": water,
	}


func load_data(data: Dictionary) -> void:
	for key in ["hunger", "thirst", "rest", "sanity", "oxygen", "warmth", "wetness"]:
		if data.has(key):
			set(key, float(data[key]))
	water = int(data.get("water", water))
	_clamp_all()


# --- Reglas ---------------------------------------------------------------------------------------

## Esfuerzo de 0 a 1: sube cuando se gasta aguante y se apaga en unos segundos.
func _update_exertion(delta: float) -> void:
	var stamina: StaminaComponent = _player.combat.stamina if _player.combat != null else null
	var spent := stamina != null and _last_stamina >= 0.0 and stamina.stamina < _last_stamina - 0.001
	_last_stamina = stamina.stamina if stamina != null else -1.0
	_exertion = 1.0 if spent else maxf(_exertion - delta / 3.0, 0.0)


func _update_wetness(dt: float, swimming: bool) -> void:
	if swimming:
		wetness = 1.0
		return
	var weather := _weather()
	var outside: bool = weather != null and not weather.is_sheltered()
	var event: String = weather.get_current_weather_name() if weather != null else "clear"
	if outside and event == "storm":
		wetness += dt / SOAK_TIME
	elif outside and event == "snow":
		wetness += dt / (SOAK_TIME * 4.0)
	else:
		var drying := (0.5 + 0.5 * _daylight) * (2.0 if felt_temperature > 20.0 else 1.0) * (1.0 + _fire_heat / 6.0)
		wetness -= dt / DRY_TIME * drying


func _update_warmth(dt: float, swimming: bool) -> void:
	var felt := _base_temperature
	var time := WARMTH_TIME
	if swimming:
		# El agua no pasa mucho de cero en los mares fríos y no se calienta con el sol.
		felt = clampf(_base_temperature - 2.0, -1.8, 26.0)
		time = WARMTH_WATER_TIME
	else:
		felt += lerpf(-6.0, 3.0, _daylight)
		var weather := _weather()
		if weather != null:
			var event: String = weather.get_current_weather_name()
			var shelter := 0.3 if weather.is_sheltered() else 1.0
			felt += float(WEATHER_CHILL.get(event, 0.0)) * shelter
			if event == "clear" and not weather.is_sheltered():
				felt += 2.0 * _daylight
		felt -= 8.0 * wetness
		# La ropa mojada abriga mucho menos.
		felt += _insulation * (1.0 - 0.6 * wetness) + _fire_heat
	felt_temperature = felt
	var target := 0.0
	if felt < COMFORT_LOW:
		target = (felt - COMFORT_LOW) / COLD_SPAN
	elif felt > COMFORT_HIGH:
		target = (felt - COMFORT_HIGH) / HEAT_SPAN
	target = clampf(target, -1.0, 1.0)
	warmth += (target - warmth) * minf(dt / time, 1.0)


func _update_sanity(dt: float) -> void:
	var drain := (1.0 - _daylight) * (1.0 - _fire_light) / SANITY_DARK_TIME
	if rest < 0.25:
		drain += 1.0 / SANITY_TIRED_TIME
	if hunger <= 0.0 or thirst <= 0.0:
		drain += 1.0 / SANITY_NEED_TIME
	var mend := _daylight / SANITY_DAY_TIME if rest > 0.4 else 0.0
	sanity += (mend - drain) * dt


func _hurt(dt: float, health: HealthComponent) -> void:
	var dps := 0.0
	if hunger <= 0.0:
		dps += STARVE_DPS
	if thirst <= 0.0:
		dps += DEHYDRATE_DPS
	if oxygen <= 0.0:
		dps += DROWN_DPS
	var exposure := (absf(warmth) - EXPOSURE_START) / (1.0 - EXPOSURE_START)
	if exposure > 0.0:
		dps += EXPOSURE_DPS * (0.5 + 0.5 * exposure)
	if dps <= 0.0:
		_pending_damage = 0.0
		return
	_pending_damage += dps * dt
	if _pending_damage >= DAMAGE_STEP:
		health.take_damage(_pending_damage)
		_pending_damage = 0.0


func _clamp_all() -> void:
	hunger = clampf(hunger, 0.0, 1.0)
	thirst = clampf(thirst, 0.0, 1.0)
	rest = clampf(rest, 0.0, 1.0)
	sanity = clampf(sanity, 0.0, 1.0)
	oxygen = clampf(oxygen, 0.0, 1.0)
	warmth = clampf(warmth, -1.0, 1.0)
	wetness = clampf(wetness, 0.0, 1.0)


# --- Lo que se mira del mundo ---------------------------------------------------------------------

## Temperatura del sitio (°C) sin la hora ni el tiempo: sale del frío del clima del planeta, el
## mismo que pone la nieve (latitud, altura y estación). La cota de nieve cae en torno a 0 °C.
func _climate_temperature() -> float:
	var body: Node3D = _player.planet
	var planet: Planet = null
	if body != null:
		planet = body.get("planet") as Planet
	if planet == null or not planet.climate.enabled:
		return 18.0
	var cold := planet.climate.snow_coldness(_player.global_position - body.global_position)
	if cold < -50.0:
		return 18.0
	return 30.0 - cold * 0.8


## De 0 (noche cerrada) a 1 (de día), por la altura del sol sobre el horizonte del jugador.
func _local_daylight() -> float:
	var sun := get_tree().get_first_node_in_group("sun_controller")
	var light: DirectionalLight3D = sun.get("sun_light") if sun != null else null
	if light == null:
		return 1.0
	var up := -_player.gravity_direction
	var elevation := rad_to_deg(asin(clampf(up.dot(light.global_basis.z), -1.0, 1.0)))
	return smoothstep(-8.0, 8.0, elevation)


## Lo que abriga la ropa puesta (°C).
func _worn_insulation() -> float:
	var window: CharacterWindow = _player.character_window
	if window == null:
		return 0.0
	var total := 0.0
	for slot_type in window.equipment_slots:
		var slot: EquipmentSlot = window.equipment_slots[slot_type]
		if slot.has_item() and slot.equipped_item.data != null:
			var insulation := slot.equipped_item.data.get_trait(InsulationTrait) as InsulationTrait
			if insulation != null:
				total += insulation.warmth
	return total


## Calor y luz de las hogueras encendidas cercanas (las de más cerca mandan; no se suman).
func _update_fires() -> void:
	_fire_heat = 0.0
	_fire_light = 0.0
	for node in get_tree().get_nodes_in_group(Campfire.GROUP):
		var fire := node as Campfire
		if fire == null or not fire.lit:
			continue
		_fire_heat = maxf(_fire_heat, fire.heat_at(_player.global_position))
		_fire_light = maxf(_fire_light, fire.light_at(_player.global_position))


func _head_under_water() -> bool:
	if not _player.movement.is_swimming or _skeleton == null or _head_bone < 0:
		return false
	var head := _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone).origin
	return head.distance_to(_player._water_surface_center) < _player._water_surface_radius - 0.05


func _weather() -> Node:
	return get_tree().get_first_node_in_group("weather")
