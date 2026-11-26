class_name CthulhuBrood
extends Node

## La comuna de esbirros que vive sobre Cthulhu. Van posados en su piel (los asientos de
## data/monsters/cthulhu_perches.json, que saca tools/monsters/build_cthulhu_perches.gd: puntos de los
## hombros, los brazos, la base de las alas y el lomo, cada uno pegado a su hueso), como modelos ligeros
## que solo respiran (el clip idle). Cuando Cthulhu anda a menos de LAUNCH_RANGE del jugador, o lo ve, saltan uno
## tras otro: cada uno se agacha (el principio del clip leap) y, en el impulso, deja su sitio a un esbirro
## de verdad (Minion.leap) que cae al mar y va nadando a por el jugador o uno de sus compañeros.
## Una sola oleada por encuentro.
##
## Lo crea Cthulhu.

const MODEL := preload("res://models/monsters/minion/minion.glb")
const MINION_SCENE := preload("res://scenes/monsters/Minion.tscn")
const PERCHES := "res://data/monsters/cthulhu_perches.json"
## Cuántos viven en él (como mucho, los asientos que haya).
const COUNT := 8
## Saltan con el jugador a menos de esto (m, en horizontal desde donde Cthulhu corta el agua), o en
## cuanto él lo ve (NOTICE), esté donde esté.
const LAUNCH_RANGE := 700.0
## Entre un salto y el siguiente (s).
const LAUNCH_STAGGER := Vector2(0.15, 0.6)
## Velocidad del salto: hacia la presa (m/s) y hacia arriba.
const LEAP_FORWARD := Vector2(16.0, 24.0)
const LEAP_UP := Vector2(5.0, 9.0)
## Los posados no se animan más lejos que esto de la cámara (m): de lejos no se ven.
const ANIMATE_RANGE := 450.0
## Más lejos que esto de la cámara (m) los posados no se dibujan.
const VISIBLE_RANGE := 700.0
## Lo que dura un cadáver de esbirro (s).
const CORPSE_TIME := 90.0
## La presa: el jugador cuenta por tantos compañeros.
const PLAYER_WEIGHT := 2.0

enum RiderState { PERCHED, CROUCH, GONE }

var launched := false

var _cthulhu: Cthulhu
var _riders: Array[Dictionary] = []
var _check := 0.0
var _rng := RandomNumberGenerator.new()


func setup(cthulhu: Cthulhu, skeleton: Skeleton3D, model_scale: float) -> void:
	_cthulhu = cthulhu
	_rng.randomize()
	var perches := _load_perches()
	perches.shuffle()
	for perch: Dictionary in perches.slice(0, COUNT):
		var bone := String(perch["bone"])
		if skeleton.find_bone(bone) < 0:
			continue
		var attach := BoneAttachment3D.new()
		attach.bone_name = bone
		skeleton.add_child(attach)
		var offset := _vec(perch["offset"])
		var up := _vec(perch["normal"]).normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis(side, up, side.cross(up)).rotated(up, _rng.randf() * TAU)
		var model := MODEL.instantiate() as Node3D
		model.transform = Transform3D(basis.scaled(Vector3.ONE / model_scale), offset)
		attach.add_child(model)
		# Diminutos de lejos: ni se dibujan ni dan sombra más allá de lo que se ve.
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).visibility_range_end = VISIBLE_RANGE
			(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var anim := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		Minion.prepare_clips(anim)
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim.play(&"idle")
		anim.seek(_rng.randf() * anim.current_animation_length, true)
		_riders.append({"model": model, "anim": anim, "state": RiderState.PERCHED, "timer": 0.0})


func _load_perches() -> Array:
	var text := FileAccess.get_file_as_string(PERCHES)
	var data: Variant = JSON.parse_string(text) if text != "" else null
	if not data is Dictionary:
		push_warning("CthulhuBrood: sin asientos en %s" % PERCHES)
		return []
	return (data as Dictionary).get("perches", [])


func _vec(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


## Que salten ya, estén donde estén (consola: cthulhu minions).
func launch() -> void:
	if launched:
		return
	launched = true
	var delay := 0.0
	for rider in _riders:
		if rider["state"] != RiderState.PERCHED:
			continue
		rider["state"] = RiderState.CROUCH
		rider["timer"] = -delay
		delay += _rng.randf_range(LAUNCH_STAGGER.x, LAUNCH_STAGGER.y)


## Cuántos quedan posados.
func perched() -> int:
	var count := 0
	for rider in _riders:
		if rider["state"] != RiderState.GONE:
			count += 1
	return count


func _process(delta: float) -> void:
	if _cthulhu == null or not is_instance_valid(_cthulhu):
		return
	var camera := get_viewport().get_camera_3d()
	var near := camera != null and camera.global_position.distance_to(_cthulhu.global_position) < ANIMATE_RANGE + 150.0
	for rider in _riders:
		match rider["state"]:
			RiderState.PERCHED:
				if near:
					(rider["anim"] as AnimationPlayer).advance(delta)
			RiderState.CROUCH:
				rider["timer"] = float(rider["timer"]) + delta
				var anim := rider["anim"] as AnimationPlayer
				if float(rider["timer"]) < 0.0:
					anim.advance(delta)
					continue
				if anim.current_animation != "leap":
					anim.play(&"leap", 0.1)
				anim.advance(delta)
				if float(rider["timer"]) >= Minion.LEAP_IMPULSE_AT:
					_jump(rider)
	if launched:
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	if _ready_to_launch():
		launch()


func _ready_to_launch() -> bool:
	var c := _cthulhu
	if c.state != Cthulhu.State.WALK and c.state != Cthulhu.State.PAUSE and c.state != Cthulhu.State.THREAT \
			and c.state != Cthulhu.State.NOTICE and c.state != Cthulhu.State.GAZE:
		return false
	var player := c.player
	if player == null or not is_instance_valid(player) or player.combat.is_dead():
		return false
	if c.state == Cthulhu.State.NOTICE or c.state == Cthulhu.State.GAZE:
		return true
	var center := c.habitat.center()
	var up := (c.global_position - center).normalized()
	return (player.global_position - c.global_position).slide(up).length() < LAUNCH_RANGE


## El posado deja su sitio a un esbirro de verdad, en pleno impulso.
func _jump(rider: Dictionary) -> void:
	rider["state"] = RiderState.GONE
	var model := rider["model"] as Node3D
	model.visible = false
	var player := _cthulhu.player
	if player == null or not is_instance_valid(player) or player.planet == null:
		return
	var origin := model.global_position
	var center := _cthulhu.habitat.center()
	var up := (origin - center).normalized()
	var prey := _pick_prey(origin)
	var toward := (prey.global_position - origin).slide(up)
	toward = toward.normalized() if toward.length_squared() > 1.0 else _cthulhu.global_basis.z.slide(up).normalized()
	var launch := toward * _rng.randf_range(LEAP_FORWARD.x, LEAP_FORWARD.y) + up * _rng.randf_range(LEAP_UP.x, LEAP_UP.y)
	launch += _cthulhu.surface_velocity()
	var minion := MINION_SCENE.instantiate() as Minion
	get_tree().current_scene.add_child(minion)
	minion.planets = player.planets
	minion.corpse_duration = CORPSE_TIME
	minion.add_to_group("floating_origin")
	minion.leap(Transform3D(Basis.looking_at(-toward, up), origin), launch, prey)


## El jugador o uno de sus compañeros vivos cerca, al azar (el jugador pesa más).
func _pick_prey(from: Vector3) -> Node3D:
	var player := _cthulhu.player
	var pool: Array[Node3D] = [player]
	var weights: Array[float] = [PLAYER_WEIGHT]
	for node in get_tree().get_nodes_in_group(Companion.GROUP):
		var mate := node as Node3D
		if mate == null or not is_instance_valid(mate):
			continue
		var health := mate.get_node_or_null("HealthComponent") as HealthComponent
		if health != null and health.is_dead:
			continue
		if mate.global_position.distance_to(from) > LAUNCH_RANGE + 150.0:
			continue
		pool.append(mate)
		weights.append(1.0)
	var total := 0.0
	for w in weights:
		total += w
	var roll := _rng.randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return player
