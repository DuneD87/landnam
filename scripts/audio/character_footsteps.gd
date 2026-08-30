class_name CharacterFootsteps
extends Node

## Audio de locomoción de un personaje: pisadas, impulso de salto y aterrizaje.
## No decide nada por su cuenta: el instante de cada pisada y la superficie los pone el flanco de
## plantado del FootIK —que ya sondea el suelo bajo cada pie—, y la familia de sonido la resuelve
## SurfaceAudio. Andar o correr sale de la velocidad real, no del estado de input, para que valga
## igual con un NPC. Se cuelga del cuerpo del personaje y se autoconfigura.

## Velocidad horizontal (m/s) a partir de la cual las pisadas pasan de andar a correr.
@export var run_speed_threshold: float = 3.0
## Desplazamiento de volumen de todo el conjunto, para equilibrarlo con el resto de la mezcla.
@export_range(-24.0, 12.0) var volume_offset_db: float = 0.0
## Velocidad de impacto (m/s) a la que el aterrizaje ya suena a plena potencia.
@export var land_full_volume_speed: float = 18.0
## Velocidad vertical (m/s) a la que una zambullida ya salpica a plena potencia.
@export var splash_full_speed: float = 8.0
## Velocidad de cruce por debajo de la cual no hay chapoteo. Parado en la orilla, la lamina sube
## y baja con cada ola y cruza los pies una y otra vez: sin minimo, el oleaje ametralla salpicones.
@export var splash_min_speed: float = 1.2
## Velocidad de impacto por debajo de la cual el aterrizaje no suena. Movement emite "landed" en
## cada transicion de is_on_floor(), y sobre una cubierta que cabecea eso es una vez por ola:
## sin minimo, cada ola metia un golpe. El gameplay ya hace lo mismo con fall_damage_min_speed.
@export var land_min_speed: float = 3.0
## Nodos concretos; vacío = se buscan bajo el cuerpo.
@export var foot_ik_path: NodePath
@export var movement_path: NodePath

var _body: CharacterBody3D
var _foot_ik: FootIK
var _movement: Movement


func _ready() -> void:
	_body = _find_body()
	if _body == null:
		push_warning("[CharacterFootsteps] %s: debe colgar de un CharacterBody3D." % name)
		return
	_foot_ik = _resolve(foot_ik_path, "FootIK") as FootIK
	_movement = _resolve(movement_path, "Movement") as Movement

	if _foot_ik != null:
		_foot_ik.foot_planted.connect(_on_foot_planted)
	else:
		push_warning("[CharacterFootsteps] %s: sin FootIK, no habrá pisadas." % _body.name)
	if _movement != null:
		_movement.jumped.connect(_on_jumped)
		_movement.landed.connect(_on_landed)
		_movement.water_crossed.connect(_on_water_crossed)


func _on_foot_planted(_side: int, hit: Dictionary) -> void:
	if _movement != null and _movement.is_swimming:
		return
	var prefix := &"step_run" if _horizontal_speed() >= run_speed_threshold else &"step_walk"
	_play(prefix, hit, 0.0)


func _on_jumped() -> void:
	_play(&"jump", _probe_ground(), 0.0)


## El aterrizaje escala con la velocidad de impacto: dejarse caer un escalón no puede sonar como
## una caída de verdad.
func _on_landed(impact_speed: float) -> void:
	if impact_speed < land_min_speed:
		return
	var loudness := clampf(impact_speed / maxf(land_full_volume_speed, 0.001), 0.0, 1.0)
	_play(&"land", _probe_ground(), lerpf(-10.0, 0.0, loudness))


## Chapoteo al entrar o salir del agua. La salpicadura escala con la velocidad del cruce: una
## zambullida desde un acantilado no suena como meter el pie en la orilla.
func _on_water_crossed(speed: float, _entering: bool) -> void:
	if _body == null or not _body.is_inside_tree():
		return
	if speed < splash_min_speed:
		return
	var loudness := clampf(speed / maxf(splash_full_speed, 0.001), 0.0, 1.0)
	AudioManager.play_3d(&"water_splash", _body.global_position,
		{"volume_offset_db": volume_offset_db + lerpf(-14.0, 0.0, loudness)})


func _play(prefix: StringName, hit: Dictionary, extra_db: float) -> void:
	if hit.is_empty():
		return
	var family := SurfaceAudio.resolve(hit, _planet_root(), _up())
	AudioManager.play_material(prefix, family, hit["position"],
		{"volume_offset_db": volume_offset_db + extra_db})


## Sondeo vertical bajo el cuerpo, para los eventos que no vienen de un pie (saltar, aterrizar).
func _probe_ground() -> Dictionary:
	if not is_instance_valid(_body) or not _body.is_inside_tree():
		return {}
	var up := _up()
	var origin := _body.global_position + up * 0.5
	var query := PhysicsRayQueryParameters3D.create(origin, origin - up * 2.0,
		_body.collision_mask, [_body.get_rid()])
	return _body.get_world_3d().direct_space_state.intersect_ray(query)


func _horizontal_speed() -> float:
	if _movement == null:
		return 0.0
	var up := _up()
	var v := _movement.velocity
	return (v - up * v.dot(up)).length()


func _up() -> Vector3:
	if _body != null and _body.up_direction.length_squared() > 0.0001:
		return _body.up_direction.normalized()
	return Vector3.UP


## Nodo cargador del planeta que pisa el personaje, o null si aún no hay ninguno.
func _planet_root() -> Node3D:
	var n: Node = _body
	while n != null:
		if n is PlanetaryBody:
			return n.planet
		n = n.get_parent()
	return null


func _resolve(path: NodePath, type_name: String) -> Node:
	if not path.is_empty():
		return get_node_or_null(path)
	var found := _body.find_children("", type_name, true, false)
	return found[0] if not found.is_empty() else null


func _find_body() -> CharacterBody3D:
	var n := get_parent()
	while n != null:
		if n is CharacterBody3D:
			return n
		n = n.get_parent()
	return null
