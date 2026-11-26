class_name Cthulhu
extends Node3D

## Cthulhu: un gigante de unos 117 m que cruza el mar a pie. Cerca de la costa pisa el fondo; en lo
## hondo vadea con el agua por la cintura (el fondo no se ve). No ataca a nadie: si ve al jugador
## (línea de visión entre sus ojos y la cabeza del jugador, de frente y a menos de SIGHT_RANGE) se para,
## lo mira y el jugador queda paralizado mientras la cordura se le vacía (AbyssStare). Bajo cubierta o
## buceando no se le ve. Lo único que mata es un accidente: una pierna, el cuerpo o la cola que pasan
## por un barco lo parten, y quien quede dentro de ellos muere aplastado.
##
## Lo crea y lo retira CthulhuDirector. Cuelga del terreno (FloatingOrigin lo lleva con él) y todo lo
## guardado entre fotogramas va relativo al centro del planeta.

signal gone

const SCENE := preload("res://models/monsters/cthulhu/cthulhu.glb")
## Escala del modelo (1,62 m en Blender): unos 117 m de pies a cabeza.
const MODEL_SCALE := 72.0
## En lo hondo, cuánto de él va bajo el agua: la superficie le queda por la cintura.
const WADE_DEPTH := 52.0
## Fondo mínimo (m) por el que camina: no se acerca a la playa más que eso.
const MIN_DEPTH := 14.0
## Ritmo de la animación de andar (1 = el del modelo, ligero para su tamaño) y velocidad del pie
## apoyado a escala 1 y ritmo 1 (m/s, medida en el Blender).
const WALK_RATE := 0.6
const STRIDE_SPEED := 0.227
## Hasta dónde mira delante (m) si se acaba el mar.
const LOOKAHEAD := 260.0
## Giro andando (rad/s) y girándose hacia el jugador al verlo.
const TURN_RATE := deg_to_rad(4.0)
const FACE_RATE := deg_to_rad(18.0)
## Sale de lo hondo y se vuelve a hundir andando: cuánto más abajo empieza/acaba y en cuánto.
const EMERGE_DEPTH := 135.0
const EMERGE_TIME := 32.0
const SUBMERGE_TIME := 38.0
## Vista: alcance (m), medio ángulo del cono (rad) y segundos viendo al jugador antes de fijarse.
const SIGHT_RANGE := 750.0
const SIGHT_CONE := deg_to_rad(110.0)
const NOTICE_TIME := 0.8
## Bajo el agua a más de esto (m) la cabeza del jugador no se ve.
const HIDDEN_DEPTH := 1.2
## Paseo: cada cuánto se para (s), y de cada parada, la probabilidad de desplegar la amenaza.
const PAUSE_EVERY := Vector2(70.0, 140.0)
const PAUSE_TIME := Vector2(6.0, 11.0)
const THREAT_CHANCE := 0.55
## Pisadas: segundos del ciclo de andar (a ritmo 1) en que planta cada pie.
const FOOTFALLS: Array[float] = [0.17, 1.27]
## Anillo de cada pisada, donde la espinilla corta el agua: altura, radio inicial, velocidad y vida.
const STEP_RING := [1.3, 7.0, 7.5, 14.0]
## Al asomar la cabeza.
const BREACH_RING := [2.4, 22.0, 9.0, 18.0]
## Aplastar: energía y radio (m) de cada golpe al casco, y cada cuánto se repite mientras toca.
const CRUSH_ENERGY := 600000.0
const CRUSH_RADIUS := 5.0
const CRUSH_EVERY := 0.25
## Tope del empujón a un barco (m/s) y de la masa a la que se aplica (t).
const SHOVE_MAX := 4.0
const SHOVE_MASS := 60000.0
## Volúmenes que aplastan: [hueso inicio, hueso fin, radio a escala 1].
const LIMBS := [
	["Muslo.L", "Pie.L", 0.085], ["Muslo.R", "Pie.R", 0.085],
	["Cadera", "Pecho", 0.2], ["Cola.01", "Cola.03", 0.07],
	["Antebrazo.L", "Mano.L", 0.05], ["Antebrazo.R", "Mano.R", 0.05],
]

enum State { EMERGE, WALK, PAUSE, THREAT, NOTICE, GAZE, SUBMERGE, GONE }

var state: State = State.EMERGE
var player: PlayerController
var habitat: WaterFaunaHabitat
## Ya ha mirado al jugador en este encuentro: no vuelve a fijarse.
var gazed := false

var _model: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _look: CthulhuLookAt
var _voice: AudioStreamPlayer3D
## Rumbo (mundo, tangente) y destino (relativo al centro del planeta).
var _heading := Vector3.FORWARD
var _destination := Vector3.ZERO
var _speed := 0.0
## Radio de los pies, suavizado, y lo que aún le falta por salir (o lo que lleva hundido).
var _feet_radius := 0.0
var _sink := EMERGE_DEPTH
var _state_time := 0.0
var _pause_timer := 0.0
var _pause_length := 0.0
var _seen_time := 0.0
var _sight_timer := 0.0
## Posición del ciclo de andar el fotograma anterior (-1 si no anda).
var _walk_clock := -1.0
var _breached := false
var _crush_timer := 0.0
var _repick_timer := 0.0
## Anillos propios vivos, para mecer los barcos al pasar: offset al centro, edad y forma.
var _rings: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func setup(player_: PlayerController, habitat_: WaterFaunaHabitat, spawn: Vector3, heading: Vector3,
		destination: Vector3, emerged: bool) -> void:
	player = player_
	habitat = habitat_
	_rng.randomize()
	var up := (spawn - habitat.center()).normalized()
	_heading = heading.slide(up).normalized()
	_destination = destination - habitat.center()
	_sink = 0.0 if emerged else EMERGE_DEPTH
	_breached = emerged
	_set_state(State.WALK if emerged else State.EMERGE)
	_feet_radius = _target_feet_radius(spawn - habitat.center())
	global_position = habitat.center() + up * (_feet_radius - _sink)
	_pause_timer = _rng.randf_range(PAUSE_EVERY.x, PAUSE_EVERY.y)
	_apply_transform()


func _ready() -> void:
	_model = SCENE.instantiate() as Node3D
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip in [&"walk", &"idle"]:
		var animation := _anim.get_animation(clip)
		if animation != null:
			animation.loop_mode = Animation.LOOP_LINEAR
	_look = CthulhuLookAt.new()
	_skeleton.add_child(_look)
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		# Con la pose de andar se sale de la caja de reposo: que no desaparezca al borde de la vista.
		(mesh as MeshInstance3D).extra_cull_margin = 30.0
	_voice = AudioStreamPlayer3D.new()
	_voice.unit_size = 260.0
	_voice.max_distance = 5000.0
	_voice.attenuation_filter_db = -6.0
	_voice.position = Vector3.UP * 100.0
	add_child(_voice)
	HullWaves.add_wader(self)
	_play(&"walk", 0.0)


func _exit_tree() -> void:
	HullWaves.remove_wader(self)
	if player != null and is_instance_valid(player) and player.abyss_stare != null:
		player.abyss_stare.release()


## Ojos en mundo, para la vista y para que la cámara del jugador vaya a ellos.
func eye_position() -> Vector3:
	return _look.eye_position() if _look != null else global_position + global_basis.y * 105.0


## Se va hundiendo mientras anda, de espaldas al jugador si puede.
func submerge() -> void:
	if state == State.SUBMERGE or state == State.GONE:
		return
	if state == State.NOTICE or state == State.GAZE:
		return
	_set_state(State.SUBMERGE)
	if player != null:
		var away := (global_position - player.global_position).slide(_up())
		if away.length_squared() > 1.0:
			_pick_destination(away.normalized())


## Lo planta delante del jugador, ya fuera del agua y mirándolo (consola: cthulhu gaze).
func face(point: Vector3) -> void:
	var to := (point - global_position).slide(_up())
	if to.length_squared() > 1.0:
		_heading = to.normalized()
		_apply_transform()


func _physics_process(delta: float) -> void:
	if state == State.GONE or habitat == null:
		return
	_state_time += delta
	match state:
		State.EMERGE:
			_sink = EMERGE_DEPTH * (1.0 - smoothstep(0.0, 1.0, _state_time / EMERGE_TIME))
			if _state_time >= EMERGE_TIME:
				_sink = 0.0
				_set_state(State.WALK)
			_walk(delta)
		State.WALK:
			_walk(delta)
			_pause_timer -= delta
			if _pause_timer <= 0.0:
				_pause_length = _rng.randf_range(PAUSE_TIME.x, PAUSE_TIME.y)
				_set_state(State.THREAT if _rng.randf() < THREAT_CHANCE else State.PAUSE)
		State.PAUSE:
			_stand(delta)
			if _state_time >= _pause_length:
				_resume()
		State.THREAT:
			_stand(delta)
			if not _anim.is_playing() or _anim.current_animation != "threat":
				_resume()
		State.NOTICE:
			_stand(delta)
			_turn_toward(player.global_position, FACE_RATE, delta)
			_look.target = player.global_position + _player_up() * 1.6
			_look.weight = move_toward(_look.weight, 1.0, delta / 1.5)
			if not _anim.is_playing() or _anim.current_animation != "alert":
				_set_state(State.GAZE)
		State.GAZE:
			_stand(delta)
			_turn_toward(player.global_position, FACE_RATE * 0.5, delta)
			_look.target = player.global_position + _player_up() * 1.6
			_look.weight = 1.0
			if not _anim.is_playing() or _anim.current_animation != "gaze":
				_resume()
		State.SUBMERGE:
			_sink = (EMERGE_DEPTH + WADE_DEPTH) * smoothstep(0.0, 1.0, _state_time / SUBMERGE_TIME)
			_walk(delta)
			if _state_time >= SUBMERGE_TIME:
				_set_state(State.GONE)
				gone.emit()
				queue_free()
				return
	if state != State.NOTICE and state != State.GAZE:
		_look.weight = move_toward(_look.weight, 0.0, delta / 2.0)
	_update_height(delta)
	_apply_transform()
	_update_sight(delta)
	_update_breach()
	_update_rings(delta)
	_update_crush(delta)


func _set_state(next: State) -> void:
	state = next
	_state_time = 0.0
	match next:
		State.WALK, State.EMERGE, State.SUBMERGE:
			_play(&"walk", 1.2, WALK_RATE)
		State.PAUSE:
			_play(&"idle", 1.0)
		State.THREAT:
			_play(&"threat", 0.8)
		State.NOTICE:
			_play(&"alert", 0.6)
			_roar(0.34)
		State.GAZE:
			_play(&"gaze", 0.5)


func _resume() -> void:
	_pause_timer = _rng.randf_range(PAUSE_EVERY.x, PAUSE_EVERY.y)
	_set_state(State.WALK)


func _play(clip: StringName, blend: float, rate: float = 1.0) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	_anim.play(clip, blend, rate)


func _roar(pitch: float) -> void:
	var stream := load("res://audio/combat/lion_roar/lion_roar_0%d.ogg" % _rng.randi_range(1, 9)) as AudioStream
	if stream == null:
		return
	_voice.stream = stream
	_voice.pitch_scale = pitch
	_voice.volume_db = 10.0
	_voice.play()


# --- Andar ---------------------------------------------------------------------------------------

func _up() -> Vector3:
	return (global_position - habitat.center()).normalized()


func _walk(delta: float) -> void:
	var up := _up()
	var to := (habitat.center() + _destination - global_position).slide(up)
	_repick_timer -= delta
	if to.length() < 120.0:
		_pick_destination(_heading)
	# Delante se acaba el mar (o se hace poco hondo): frena, gira más deprisa y busca otro destino,
	# como mucho cada pocos segundos para no dar bandazos.
	var blocked := not _walkable(global_position + _heading * LOOKAHEAD)
	if blocked and _repick_timer <= 0.0:
		_repick_timer = 4.0
		_pick_destination(_heading.rotated(up, PI * 0.5 * (1.0 if _rng.randf() < 0.5 else -1.0)))
	_turn_toward(habitat.center() + _destination, TURN_RATE * (3.5 if blocked else 1.0), delta)
	var full := STRIDE_SPEED * MODEL_SCALE * WALK_RATE * (0.35 if blocked else 1.0)
	_speed = move_toward(_speed, full, STRIDE_SPEED * MODEL_SCALE * WALK_RATE * delta / 1.2)
	_advance(delta)
	_step_waves()


func _stand(delta: float) -> void:
	var full := STRIDE_SPEED * MODEL_SCALE * WALK_RATE
	_speed = move_toward(_speed, 0.0, full * delta / 0.8)
	_advance(delta)


func _advance(delta: float) -> void:
	if _speed <= 0.0:
		return
	var center := habitat.center()
	var local := global_position - center
	var next := (local + _heading * _speed * delta).normalized() * local.length()
	global_position = center + next


func _turn_toward(point: Vector3, rate: float, delta: float) -> void:
	var up := _up()
	var to := (point - global_position).slide(up)
	if to.length_squared() < 1.0:
		return
	to = to.normalized()
	var angle := _heading.signed_angle_to(to, up)
	_heading = _heading.rotated(up, clampf(angle, -rate * delta, rate * delta)).slide(up).normalized()


## Destino nuevo a 700–1400 m, cerca de [toward], con mar hondo en todo el camino.
func _pick_destination(toward: Vector3) -> void:
	var up := _up()
	toward = toward.slide(up).normalized()
	for attempt in 16:
		var spread := PI * (0.35 + 0.08 * attempt)
		var direction := toward.rotated(up, _rng.randf_range(-spread, spread))
		var distance := _rng.randf_range(700.0, 1400.0)
		var ok := true
		for i in range(1, 6):
			if not _walkable(global_position + direction * distance * i / 5.0):
				ok = false
				break
		if ok:
			_destination = global_position + direction * distance - habitat.center()
			return
	# Sin salida a la vista: de vuelta por donde vino.
	_destination = global_position - toward * 900.0 - habitat.center()


func _walkable(point: Vector3) -> bool:
	var map := habitat.world_map
	if map == null or not map.is_ready():
		return true
	var water := map.get_water_type_at(point)
	if water != WorldMapData.WaterType.OCEAN and water != WorldMapData.WaterType.SEA:
		return false
	return map.get_water_depth_at(point) >= MIN_DEPTH


func _target_feet_radius(local: Vector3) -> float:
	var sea := habitat.ocean.radius
	var map := habitat.world_map
	# Sin mapa no se sabe el fondo: vadea como en lo hondo.
	var depth := map.water_depth_local(local) if map != null and map.is_ready() else 1000.0
	return maxf(sea - depth, sea - WADE_DEPTH)


func _update_height(delta: float) -> void:
	var center := habitat.center()
	var local := global_position - center
	_feet_radius = lerpf(_feet_radius, _target_feet_radius(local), 1.0 - exp(-delta / 2.5))
	global_position = center + local.normalized() * (_feet_radius - _sink)


func _apply_transform() -> void:
	var up := _up()
	var forward := _heading.slide(up).normalized()
	global_basis = Basis(up.cross(forward), up, forward)


# --- Vista y mirada ------------------------------------------------------------------------------

func _player_up() -> Vector3:
	return (player.global_position - habitat.center()).normalized()


func _update_sight(delta: float) -> void:
	if gazed or player == null or not is_instance_valid(player):
		return
	if state != State.WALK and state != State.PAUSE and state != State.THREAT and state != State.EMERGE:
		return
	_sight_timer -= delta
	if _sight_timer > 0.0:
		return
	_sight_timer = 0.2
	if _sees_player():
		_seen_time += 0.2
	else:
		_seen_time = maxf(0.0, _seen_time - 0.4)
	if _seen_time >= NOTICE_TIME:
		_notice()


func _sees_player() -> bool:
	if AIController.ignore_player or player.combat.is_dead() or not player.visible:
		return false
	var eye := eye_position()
	# Con los ojos aún bajo el agua no ve nada.
	if eye.distance_to(habitat.center()) < habitat.ocean.radius + 2.0:
		return false
	var up := _player_up()
	var head := player.global_position + up * 1.6
	var to := head - eye
	if to.length() > SIGHT_RANGE:
		return false
	if _heading.angle_to(to.slide(_up())) > SIGHT_CONE:
		return false
	if habitat.surface_radius(head) - head.distance_to(habitat.center()) > HIDDEN_DEPTH:
		return false
	return _clear_line(eye, head) or _clear_line(eye, player.global_position + up * 0.9)


## Nada entre los ojos y el punto: ni una cubierta, ni una pared, ni el terreno.
func _clear_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	query.hit_from_inside = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player


func _notice() -> void:
	gazed = true
	_seen_time = 0.0
	_set_state(State.NOTICE)
	var gaze_length := 4.2
	var alert_length := 3.1
	if _anim.has_animation(&"gaze"):
		gaze_length = _anim.get_animation(&"gaze").length
	if _anim.has_animation(&"alert"):
		alert_length = _anim.get_animation(&"alert").length
	player.abyss_stare.begin(self, alert_length + gaze_length)


# --- Olas ----------------------------------------------------------------------------------------

## Lo que levanta al andar, para HullWaves: la cintura corta el agua como una proa ancha.
func wake_source() -> Dictionary:
	if habitat == null:
		return {}
	var submerged_feet := habitat.ocean.radius - (_feet_radius - _sink)
	if _speed < 0.5 or submerged_feet < 3.0 or _sink > WADE_DEPTH + 20.0:
		return {}
	var up := _up()
	var center := habitat.center() + up * habitat.ocean.radius
	var amplitude := minf(0.42 * _speed * _speed / 19.6, 2.6) * smoothstep(0.5, 4.0, _speed)
	# Medio hundido (saliendo o yéndose) aparta menos agua.
	amplitude *= 1.0 - smoothstep(10.0, WADE_DEPTH + 20.0, _sink)
	return {"center": center, "heading": _heading, "length": 12.0, "beam": 20.0, "speed": _speed,
		"amplitude": amplitude}


## Una pisada cada vez que el ciclo de andar pasa por FOOTFALLS (también al dar la vuelta).
func _step_waves() -> void:
	if _anim.current_animation != "walk":
		_walk_clock = -1.0
		return
	var now := _anim.current_animation_position
	var before := _walk_clock
	_walk_clock = now
	if before < 0.0:
		return
	for i in FOOTFALLS.size():
		var at: float = FOOTFALLS[i]
		var crossed := (before < at and now >= at) if now >= before else (before < at or now >= at)
		if crossed:
			_footfall("Espinilla.L" if i == 0 else "Espinilla.R")


func _footfall(knee_bone: String) -> void:
	var knee := _bone_world(knee_bone)
	var center := habitat.center()
	var radius := knee.distance_to(center)
	# Solo si la pierna corta el agua: con la rodilla aún muy hondo, el agua apenas se mueve arriba.
	if radius > habitat.ocean.radius + 40.0 or radius < habitat.ocean.radius - 60.0:
		return
	_ring(center + (knee - center).normalized() * habitat.ocean.radius, STEP_RING)


func _update_breach() -> void:
	if _breached:
		return
	var eye := eye_position()
	if eye.distance_to(habitat.center()) > habitat.ocean.radius:
		_breached = true
		_ring(habitat.center() + _up() * habitat.ocean.radius, BREACH_RING)
		_roar(0.28)


func _ring(at: Vector3, shape: Array) -> void:
	HullWaves.wave_ring(at, shape[0], shape[1], shape[2], shape[3])
	_rings.append({"offset": at - habitat.center(), "age": 0.0, "amp": shape[0], "r0": shape[1],
		"speed": shape[2], "life": shape[3]})


## Los frentes que llegan a un barco lo levantan y lo apartan, por el lado que reciben primero.
func _update_rings(delta: float) -> void:
	if _rings.is_empty():
		return
	var center := habitat.center()
	var boats := DynamicGridBody.bodies_in_play(get_tree())
	for i in range(_rings.size() - 1, -1, -1):
		var ring := _rings[i]
		var age: float = ring["age"]
		var life: float = ring["life"]
		var front_before: float = ring["r0"] + ring["speed"] * age
		age += delta
		ring["age"] = age
		if age >= life:
			_rings.remove_at(i)
			continue
		var front: float = ring["r0"] + ring["speed"] * age
		var origin: Vector3 = center + (ring["offset"] as Vector3)
		var fade := 1.0 - smoothstep(0.0, life, age)
		var amp: float = ring["amp"] * fade * fade * sqrt(ring["r0"] / maxf(front, ring["r0"]))
		if amp < 0.05:
			continue
		for node in boats:
			var body := node as DynamicGridBody
			if body == null or not is_instance_valid(body) or body.movement_type != DynamicGridBody.MovementType.BOAT:
				continue
			var hull := body.get_hull_center_world()
			var up := (hull - center).normalized()
			var flat := (hull - origin).slide(up)
			var distance := flat.length()
			if distance < front_before or distance >= front or distance < 1.0:
				continue
			var out := flat / distance
			var mass := minf(body.mass, SHOVE_MASS)
			var near_side := hull - out * 2.0
			body.apply_impulse((up * 1.4 + out * 0.9) * amp * mass, near_side - body.global_position)


# --- Aplastar ------------------------------------------------------------------------------------

func _bone_world(bone_name: String) -> Vector3:
	var bone := _skeleton.find_bone(bone_name)
	if bone < 0:
		return global_position
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin


## Segmentos que aplastan, en mundo: [inicio, fin, radio].
func _limb_segments() -> Array:
	var out := []
	for limb in LIMBS:
		out.append([_bone_world(limb[0]), _bone_world(limb[1]), float(limb[2]) * MODEL_SCALE])
	return out


func _update_crush(delta: float) -> void:
	_crush_timer -= delta
	if _crush_timer > 0.0:
		return
	_crush_timer = CRUSH_EVERY
	# Hundido del todo no toca nada de arriba.
	if _sink > WADE_DEPTH + 60.0:
		return
	var limbs := _limb_segments()
	var reach := 140.0
	for node in DynamicGridBody.bodies_near(get_tree(), global_position, reach + 60.0):
		var body := node as DynamicGridBody
		if body == null or not is_instance_valid(body):
			continue
		_crush_boat(body, limbs)
	_crush_player(limbs)


func _crush_boat(body: DynamicGridBody, limbs: Array) -> void:
	var bounds := body.get_hull_bounds()
	if not bounds.has("half"):
		return
	var half: Vector3 = bounds["half"]
	var xform := body.global_transform
	var hull := xform * (bounds["pos"] as Vector3)
	var size := maxf(half.x, maxf(half.y, half.z))
	for limb in limbs:
		var closest := Geometry3D.get_closest_point_to_segment(hull, limb[0], limb[1])
		var radius: float = limb[2]
		if closest.distance_to(hull) > radius + size:
			continue
		# El punto del casco más cerca del miembro: dentro de su caja, hacia el eje.
		var local := xform.affine_inverse() * closest - (bounds["pos"] as Vector3)
		local = local.clamp(-half, half)
		var contact := xform * ((bounds["pos"] as Vector3) + local)
		if Geometry3D.get_closest_point_to_segment(contact, limb[0], limb[1]).distance_to(contact) > radius:
			continue
		body.apply_damage_at(contact, CRUSH_ENERGY, CRUSH_RADIUS)
		var up := (hull - habitat.center()).normalized()
		var away := (hull - closest).slide(up)
		away = away.normalized() if away.length_squared() > 0.01 else _heading
		var push := (away * 0.6 + _heading * 0.6 - up * 0.25).normalized()
		var mass := minf(body.mass, SHOVE_MASS)
		body.apply_impulse(push * minf(_speed * 0.6 + 1.0, SHOVE_MAX) * mass, contact - body.global_position)
		return


func _crush_player(limbs: Array) -> void:
	if player == null or not is_instance_valid(player) or player.combat.is_dead():
		return
	var chest := player.global_position + _player_up() * 0.9
	for limb in limbs:
		var closest := Geometry3D.get_closest_point_to_segment(chest, limb[0], limb[1])
		if closest.distance_to(chest) < float(limb[2]) + 0.4:
			player.health_component.take_damage(player.health_component.max_health * 10.0, self)
			return
