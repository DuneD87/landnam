class_name Minion
extends NPCController

## Esbirro de Cthulhu (Abyssal Maw): una criatura de 1,58 m que vive en comuna sobre el monstruo. Es una
## fiera más (CombatState con su perfil, Perception, Devouring si mata a alguien), con lo que las
## demás no tienen:
##   - Nada. En agua honda flota con la espalda a flor de agua (o de pie, pataleando, si va despacio) y
##     va deprisa (SWIM_SPEED), dejando estela (HullWaves, como un vadeador) y rocío. Al tocar fondo en
##     la orilla se pone a correr; al meterse en agua honda, nada. El agua no la esquiva
##     (AIController.amphibious).
##   - Salta desde Cthulhu (leap): un arco hasta el mar, con su clip, y al caer nada hacia su presa.
## Muriendo en el agua se hunde.
##
## Clips (models/monsters/minion/minion.glb, tools/monsters/blender/export_minion.py): idle, run, swim,
## idle_water, leap, claws (zarpazos), devour (comer), y aún sin usar grab, climb y board. La muerte no
## tiene clip todavía: se cae de lado (_ensure_death_clip).

const MINION_GROUP := &"cthulhu_minion"
const SCENE_PATH := "res://scenes/monsters/Minion.tscn"
## Nado: velocidad (m/s), hondura del origen (los pies) bajo la superficie nadando y en el sitio, desde
## qué hondura de los pies se pone a nadar, y lo que tira la flotación hacia su altura (1/s).
const SWIM_SPEED := 9.0
const SWIM_DEPTH := 0.62
const TREAD_DEPTH := 0.92
const SWIM_ENTER := 0.75
const BUOYANCY := 3.5
## La superficie se muestrea cada tantos pasos de física (get_height_at es caro).
const SAMPLE_EVERY := 3
## Ritmo del clip de nadar a SWIM_SPEED (el clip no avanza: es lo que se ve bien).
const SWIM_ANIM_RATE := 1.6
## Estela: hasta dónde de la cámara (m), su forma y su tope de altura (m).
const WAKE_REACH := 450.0
const WAKE_LENGTH := 1.2
const WAKE_BEAM := 0.35
const WAKE_MAX := 0.35
## Rocío nadando deprisa: cada cuánto (s) y desde qué velocidad (m/s).
const SPRAY_EVERY := 0.1
const SPRAY_SPEED := 4.0
## Hasta dónde (m) huele a su presa: más cerca no la pierde aunque no la vea, y si se queda parado
## vuelve a por ella.
const PREY_SENSE := 1500.0
## Salto: el impulso del clip (F8 a 30 fps).
const LEAP_IMPULSE_AT := 8.0 / 30.0
## Los clips que son ciclos (en el .glb vienen sin bucle).
const LOOPS: Array[StringName] = [&"idle", &"idle_water", &"swim", &"run"]
## Muerte de reserva: lo que dura y hasta dónde se tumba (grados).
const DEATH_TIME := 0.9
const DEATH_TILT := 86.0

## En el aire, saltando desde Cthulhu.
var leaping := false
## A quién va (lo pone quien la suelta): en cuanto cae al agua va a por él.
var prey: Node3D

var _leap_velocity := Vector3.ZERO
var _sampler: WaterHeightSampler
## Radio de la superficie del agua aquí (o -INF lejos del mar).
var _surface := -INF
var _sample_clock := 0
var _spray_clock := 0.0
## 0 en el sitio, 1 nadando a fondo: la hondura y el ritmo del clip.
var _swim_blend := 0.0


## Pone en bucle los ciclos de [player] (los comparten todos los esbirros y los posados en Cthulhu).
static func prepare_clips(player: AnimationPlayer) -> void:
	for clip in LOOPS:
		var animation := player.get_animation(clip)
		if animation != null:
			animation.loop_mode = Animation.LOOP_LINEAR


func _ready() -> void:
	var player := _anim_player()
	if player != null:
		prepare_clips(player)
		_ensure_death_clip(player)
	super._ready()
	add_to_group(MINION_GROUP)
	movement.swim_speed = SWIM_SPEED
	ai_controller.amphibious = true
	if animation_controller != null and animation_controller.animation_tree != null:
		animation_controller.animation_tree.active = true
	HullWaves.add_wader(self)


func _anim_player() -> AnimationPlayer:
	var found := npc_model.find_children("*", "AnimationPlayer", true, false) if npc_model != null else []
	return found[0] as AnimationPlayer if not found.is_empty() else null


## Salta desde [from] (mundo) con [launch] (m/s), ya pasado el agacharse del clip: cae al mar (o donde
## caiga) y va a por [target].
func leap(from: Transform3D, launch: Vector3, target: Node3D) -> void:
	global_transform = from
	reset_physics_interpolation()
	leaping = true
	prey = target
	_leap_velocity = launch
	velocity = Vector3.ZERO
	movement.velocity = Vector3.ZERO
	# Tras el clip queda en la pose de nadar (el clip acaba en ella): cae así hasta el agua.
	movement.is_swimming = true
	var channel := get_action_channel()
	if channel != null:
		channel.play(&"leap", 1.0, 0.05, 0.35, LEAP_IMPULSE_AT)


## Va a por [target] (el jugador o uno de sus compañeros).
func hunt(target: Node3D) -> void:
	if target == null or not is_instance_valid(target) or is_dead:
		return
	prey = target
	ai_controller.target = target
	ai_controller.transition_to(detect_state)


func _physics_step(delta: float) -> void:
	if leaping:
		_leap_step(delta)
		return
	_update_water()
	_keep_prey()
	super._physics_step(delta)
	_update_swim_rate()


## Una vez lanzado a por alguien no lo suelta hasta que muere: lo huele a PREY_SENSE m aunque no lo vea
## (lejos, tras una loma), y si se ha quedado parado (lo perdió de vista y lo olvidó) vuelve a por él.
func _keep_prey() -> void:
	if is_dead or prey == null:
		return
	var health := prey.get_node_or_null("HealthComponent") as HealthComponent if is_instance_valid(prey) else null
	if not is_instance_valid(prey) or (health != null and health.is_dead):
		prey = null
		return
	if global_position.distance_to(prey.global_position) > PREY_SENSE:
		return
	var state := ai_controller.get_current_state()
	if state == &"IdleState" or state == &"WanderState":
		hunt(prey)
	elif state == detect_state and ai_controller.target == prey:
		ai_controller.target_seen = true


# --- Agua ----------------------------------------------------------------------------------------

func _update_water() -> void:
	if planet == null or not is_instance_valid(planet) or not planet.planet.has_water:
		_surface = -INF
		movement.is_swimming = false
		return
	var center: Vector3 = planet.global_position
	var r := global_position.distance_to(center)
	var base: float = planet.planet.radius - planet.planet.water_radius
	if r > base + 30.0:
		_surface = -INF
		movement.is_swimming = false
		return
	_sample_clock -= 1
	if _sample_clock <= 0 or _surface == -INF:
		_sample_clock = SAMPLE_EVERY
		_surface = base + _wave_height(center)
	if is_dead:
		movement.is_swimming = false
		return
	if movement.is_swimming:
		# Tocando fondo donde ya hace pie (la orilla) o fuera del agua (lo ha subido algo): de pie.
		if (is_on_floor() and r > _surface - SWIM_ENTER - 0.05) or r > _surface + 0.3:
			movement.is_swimming = false
	else:
		movement.is_swimming = r < _surface - SWIM_ENTER and not GridManager.is_point_in_dry_interior(global_position)


func _wave_height(center: Vector3) -> float:
	if _sampler == null:
		_sampler = WaterHeightSampler.new()
		_sampler.name = "WaterSampler"
		add_child(_sampler)
		_sampler.setup(planet.water_sphere.quadtree_material, planet.world_map)
	_sampler.world_map = planet.world_map
	var material := planet.water_sphere.quadtree_material as ShaderMaterial
	return _sampler.get_height_at(global_position, WaterHeightSampler.get_water_time(material), center, 1.5)


## Nadando, la flotación lleva el cuerpo a su altura: la espalda a flor de agua o, en el sitio, la
## cabeza fuera.
func _before_move(delta: float) -> void:
	if not movement.is_swimming or _surface == -INF:
		_swim_blend = 0.0
		return
	var up := up_direction
	var flat := velocity.slide(up)
	var speed := flat.length()
	_swim_blend = move_toward(_swim_blend, clampf(speed / 3.0, 0.0, 1.0), delta * 2.0)
	var depth := lerpf(TREAD_DEPTH, SWIM_DEPTH, _swim_blend)
	var r := global_position.distance_to(planet.global_position)
	velocity = flat + up * clampf((_surface - depth - r) * BUOYANCY, -4.0, 4.0)
	_swim_spray(delta, speed, flat)


func _swim_spray(delta: float, speed: float, flat: Vector3) -> void:
	if speed < SPRAY_SPEED:
		return
	_spray_clock -= delta
	if _spray_clock > 0.0:
		return
	_spray_clock = SPRAY_EVERY
	var up := up_direction
	var at := planet.global_position + (global_position - planet.global_position).normalized() * _surface
	OceanSpray.splash(at + flat.normalized() * 0.6 + up * 0.05, clampf(speed / SWIM_SPEED, 0.2, 0.5))


func _update_swim_rate() -> void:
	if animation_controller == null or animation_controller.animation_tree == null:
		return
	var rate := lerpf(1.0, SWIM_ANIM_RATE, clampf(velocity.slide(up_direction).length() / SWIM_SPEED, 0.0, 1.0))
	animation_controller.animation_tree.set(&"parameters/swim_rate/scale", rate)


## Para HullWaves: nadando deprisa abre una estela como la de una barca pequeña.
func wake_source() -> Dictionary:
	if leaping or is_dead or not movement.is_swimming or _surface == -INF or planet == null:
		return {}
	var up := up_direction
	var flat := velocity.slide(up)
	var speed := flat.length()
	if speed < 1.5:
		return {}
	var center: Vector3 = planet.global_position + (global_position - planet.global_position).normalized() * _surface
	return {"center": center, "heading": flat / speed, "length": WAKE_LENGTH, "beam": WAKE_BEAM, "speed": speed,
		"amplitude": minf(0.42 * speed * speed / 19.6, WAKE_MAX), "reach": WAKE_REACH}


# --- Salto ---------------------------------------------------------------------------------------

func _leap_step(delta: float) -> void:
	if planet == null or not is_instance_valid(planet):
		update_nearest_planet()
		return
	var center: Vector3 = planet.global_position
	var up := (global_position - center).normalized()
	up_direction = up
	gravity_direction = -up
	_leap_velocity += -up * planet.gravity_strength * delta
	var next := global_position + _leap_velocity * delta
	var flat := _leap_velocity.slide(up)
	if flat.length_squared() > 0.01:
		global_basis = Basis.looking_at(-flat.normalized(), up)
	if animation_controller != null:
		animation_controller.handle_animations(delta, AnimationController.Anim.SWIM, false)
	# Lo que haya en medio: el terreno o un casco.
	var query := PhysicsRayQueryParameters3D.create(global_position, next, PhysicsLayers.WORLD | PhysicsLayers.BODIES)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit["position"] + up * 0.05
		_land(false)
		return
	global_position = next
	var base: float = planet.planet.radius - planet.planet.water_radius
	var r := next.distance_to(center)
	if planet.planet.has_water and r < base + 20.0:
		_surface = base + _wave_height(center)
		if r <= _surface:
			_land(true)


func _land(water: bool) -> void:
	leaping = false
	var up := up_direction
	var flat := _leap_velocity.slide(up)
	if water:
		var at := planet.global_position + (global_position - planet.global_position).normalized() * _surface
		OceanSpray.splash(at, 1.0)
		HullWaves.wave_ring(at, 0.3, 0.8, 3.5, 6.0)
		AudioManager.play_3d(&"water_splash", at, {"volume_offset_db": 6.0})
		movement.is_swimming = true
		# Entra de cabeza: sale hacia delante con algo de lo que traía.
		velocity = flat * 0.35 - up * minf(-_leap_velocity.dot(up), 6.0)
	else:
		movement.is_swimming = false
		velocity = flat * 0.2
	movement.velocity = velocity.slide(up)
	# La caída del salto no se cobra: es su forma de bajar.
	_fall_top = -INF
	if prey != null and is_instance_valid(prey):
		hunt(prey)


# --- Muerte de reserva ---------------------------------------------------------------------------

## Mientras no haya clip de muerte: se cae de lado girando la raíz.
func _ensure_death_clip(player: AnimationPlayer) -> void:
	if player.has_animation(&"death"):
		return
	var skel := get_skeleton()
	var root_node := player.get_node_or_null(player.root_node)
	if skel == null or root_node == null:
		return
	var bone := skel.find_bone("Raiz")
	if bone < 0:
		return
	var anim := Animation.new()
	anim.length = DEATH_TIME
	var track := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(track, NodePath(String(root_node.get_path_to(skel)) + ":Raiz"))
	var rest := skel.get_bone_rest(bone).basis.get_rotation_quaternion()
	for key: Vector2 in [Vector2(0.0, 0.0), Vector2(0.3, 0.22), Vector2(0.75, 1.03), Vector2(DEATH_TIME, 1.0)]:
		var tilt := Quaternion(Vector3.BACK, deg_to_rad(DEATH_TILT) * key.y)
		anim.rotation_track_insert_key(track, key.x, tilt * rest)
	var library := player.get_animation_library(&"")
	if library != null:
		library.add_animation(&"death", anim)
