class_name SettlementAnimal extends Node3D

## Un animal de los poblados: el ganado de los cercados (SettlementProp &"pen") y los perros sueltos
## (SettlementVillagers). Es el modelo de la fauna con sus animaciones (el NPCModel de su escena, sin IA,
## física ni salud) y una rutina sencilla: está, pasta o se tumba un rato y luego anda hasta otro sitio
## de su zona, pegado al suelo con un rayo como los aldeanos. No se le puede cazar ni se guarda. A más de
## SLEEP_DISTANCE del jugador se oculta y deja de moverse.

## Por especie: la escena de la fauna, las animaciones de estar, andar y tumbarse ("" si no hay), lo que
## anda (m/s) y a qué ritmo va su animación de andar.
const SPECIES := {
	&"cow": {"scene": "res://scenes/animals/Cow.tscn", "idle": "Idle", "walk": "Walk_100", "lie": "", "speed": 0.8, "clip": 1.0},
	&"calf": {"scene": "res://scenes/animals/Calf.tscn", "idle": "Idle", "walk": "Walk_60", "lie": "", "speed": 0.7, "clip": 1.0},
	&"goat": {"scene": "res://scenes/animals/Goat.tscn", "idle": "idle", "walk": "walk", "lie": "laydown", "speed": 0.7, "clip": 1.0},
	&"horse": {"scene": "res://scenes/animals/Horse.tscn", "idle": "Idle", "walk": "G0_Walk", "lie": "", "speed": 1.3, "clip": 1.0},
	&"donkey": {"scene": "res://scenes/animals/Donkey.tscn", "idle": "idle", "walk": "walk", "lie": "laydown", "speed": 0.9, "clip": 1.0},
	&"labrador": {"scene": "res://scenes/animals/Labrador.tscn", "idle": "Idle", "walk": "walk_fwd_01", "lie": "idle_to_idle_lay_01", "speed": 1.1, "clip": 1.0},
	&"bloodhound": {"scene": "res://scenes/animals/Bloodhound.tscn", "idle": "Idle", "walk": "walk fwd", "lie": "idle to idle lay", "speed": 1.1, "clip": 1.0},
}
const DOGS: Array[StringName] = [&"labrador", &"bloodhound"]
## Cuánto está quieto o tumbado (s), y lo a menudo que se tumba el que puede.
const REST_TIME := Vector2(6.0, 25.0)
const LIE_TIME := Vector2(20.0, 60.0)
const LIE_CHANCE := 0.25
const TURN_SPEED := 2.5
const PROBE_INTERVAL := 0.3
const PROBE_UP := 1.5
const PROBE_DOWN := 4.0
## Parado, cada cuánto vuelve a buscar el suelo (s): al aparecer el terreno puede no tener colisión aún.
const REST_PROBE_INTERVAL := 1.0
## A más de esto del jugador se oculta y no hace nada (m).
const SLEEP_DISTANCE := 140.0
const ARRIVE := 0.3

enum State {REST, WALK, LIE}

var species: StringName
## Su zona: los puntos a los que puede ir ([spots], marco del terreno) o, en un cercado, el rectángulo
## [pen] (su pose en el suelo y su tamaño), algo metido.
var spots := PackedVector3Array()
var pen := Transform3D.IDENTITY
var pen_size := Vector2.ZERO
var terrain: Node3D

var _info: Dictionary
var _player: AnimationPlayer
var _model: Node3D
var _pos := Vector3.ZERO
var _forward := Vector3.FORWARD
var _target := Vector3.ZERO
var _state := State.REST
var _left := 0.0
var _probe_left := 0.0
var _sleep_check := 0.0
var _rng := RandomNumberGenerator.new()
static var _scenes := {}


## Un animal de [kind] en [at] (marco del terreno) que vive en un cercado ([pen_pose], [size]) o, sin
## tamaño, que va de un sitio a otro de [roam]. [seed]: su rutina, siempre igual.
static func create(kind: StringName, at: Vector3, terrain_node: Node3D, seed: int, pen_pose := Transform3D.IDENTITY,
		size := Vector2.ZERO, roam := PackedVector3Array()) -> SettlementAnimal:
	if not SPECIES.has(kind):
		return null
	var model := _model_of(kind)
	if model == null:
		return null
	var animal := SettlementAnimal.new()
	animal.species = kind
	animal.terrain = terrain_node
	animal.pen = pen_pose
	animal.pen_size = size
	animal.spots = roam
	animal._info = SPECIES[kind]
	animal._model = model
	animal._rng.seed = seed
	animal._pos = at
	var up := at.normalized()
	animal._forward = up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized().rotated(up,
		animal._rng.randf() * TAU)
	animal.name = "SettlementAnimal_%s" % kind
	animal.add_child(model)
	return animal


## El NPCModel de la escena de fauna de [kind] (el modelo y su AnimationPlayer con las animaciones),
## sacado de ella: lo demás (IA, física, salud) se tira.
static func _model_of(kind: StringName) -> Node3D:
	var path: String = SPECIES[kind].scene
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _scenes[path]
	if scene == null:
		return null
	var creature := scene.instantiate()
	var model := creature.get_node_or_null("NPCModel") as Node3D
	if model == null:
		creature.free()
		return null
	creature.remove_child(model)
	model.owner = null
	creature.free()
	# El AnimationTree de la fauna (el que lleva su AnimationController) manda en el esqueleto y lo deja
	# en su estado de reposo: sin él, lo que suena es lo del AnimationPlayer.
	for tree in model.find_children("*", "AnimationTree", true, false):
		tree.get_parent().remove_child(tree)
		tree.free()
	model.transform = Transform3D.IDENTITY
	return model


func _ready() -> void:
	_player = _model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _player != null:
		_player.animation_finished.connect(_on_finished)
	_follow_ground()
	_place()
	_rest()
	_sleep_check = _rng.randf()


func _process(delta: float) -> void:
	_sleep_check -= delta
	if _sleep_check <= 0.0:
		_sleep_check = 1.0
		var camera := get_viewport().get_camera_3d()
		var awake := camera == null or camera.global_position.distance_to(global_position) < SLEEP_DISTANCE
		if awake != visible:
			visible = awake
			if _player != null:
				if awake:
					_player.play()
				else:
					_player.pause()
	if not visible:
		return
	match _state:
		State.WALK:
			_walk(delta)
		_:
			_probe_left -= delta
			if _probe_left <= 0.0:
				_probe_left = REST_PROBE_INTERVAL
				_follow_ground()
				_place()
			_left -= delta
			if _left <= 0.0:
				_next()


func _next() -> void:
	var roll := _rng.randf()
	if _state != State.LIE and String(_info.lie) != "" and roll < LIE_CHANCE:
		_state = State.LIE
		_left = _rng.randf_range(LIE_TIME.x, LIE_TIME.y)
		_play(String(_info.lie))
	elif roll < 0.55:
		_target = _pick_spot()
		_state = State.WALK
		_play(String(_info.walk), float(_info.clip))
	else:
		_rest()


func _rest() -> void:
	_state = State.REST
	_left = _rng.randf_range(REST_TIME.x, REST_TIME.y)
	_play(String(_info.idle))


## Un sitio de su zona: dentro del cercado (algo metido) o uno de sus sitios.
func _pick_spot() -> Vector3:
	if pen_size != Vector2.ZERO:
		var half := pen_size * 0.5 - Vector2.ONE * 1.0
		var q := Vector3(_rng.randf_range(-half.x, half.x), 0.0, _rng.randf_range(-half.y, half.y))
		return pen * q
	if spots.is_empty():
		return _pos
	return spots[_rng.randi() % spots.size()]


func _walk(delta: float) -> void:
	var up := _pos.normalized()
	var to := (_target - _pos).slide(up)
	var distance := to.length()
	if distance < ARRIVE:
		_rest()
		return
	var heading := to / distance
	_forward = _forward.slerp(heading, minf(1.0, TURN_SPEED * delta)).slide(up).normalized()
	var step := minf(float(_info.speed) * delta, distance)
	var radius := _pos.length()
	_pos = (_pos + _forward * step).normalized() * radius
	_probe_left -= delta
	if _probe_left <= 0.0:
		_probe_left = PROBE_INTERVAL
		_follow_ground()
	_place()


func _place() -> void:
	var up := _pos.normalized()
	var fwd := _forward.slide(up).normalized()
	if fwd == Vector3.ZERO:
		return
	# Las escenas de fauna miran hacia +Z.
	var right := up.cross(fwd).normalized()
	global_transform = terrain.global_transform * Transform3D(Basis(right, up, fwd), _pos)


func _follow_ground() -> void:
	if not is_inside_tree() or terrain == null:
		return
	var frame := terrain.global_transform
	var up := _pos.normalized()
	var query := PhysicsRayQueryParameters3D.create(frame * (_pos + up * PROBE_UP), frame * (_pos - up * PROBE_DOWN), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_pos = frame.affine_inverse() * (hit.position as Vector3)


func _play(anim: String, speed := 1.0) -> void:
	if _player == null or anim == "" or not _player.has_animation(anim):
		return
	_player.play(anim, 0.3, speed)


## Tumbarse no se repite: se queda en el último fotograma. Lo demás vuelve a empezar si es lo que toca
## (la que acaba puede ser la de antes, aún fundiéndose).
func _on_finished(anim: StringName) -> void:
	if _state == State.LIE:
		if String(anim) == String(_info.lie):
			_player.pause()
		return
	var current := String(_info.walk) if _state == State.WALK else String(_info.idle)
	if String(anim) == current:
		_player.play(anim, 0.0, float(_info.clip) if _state == State.WALK else 1.0)
