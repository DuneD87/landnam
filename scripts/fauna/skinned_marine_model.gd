class_name SkinnedMarineModel
extends SkinnedModel

## El animal marino grande con esqueleto de un pack (MarineModelData) para AmbientMarineAnimal: nada
## al ritmo de su velocidad, con el clip de girar mientras gira y el de nadar deprisa a la carga,
## muerde una vez al morder y aparece y se va fundiéndose (pack_marine.gdshader, set_fade). Va
## centrado en su caja, como las mallas procedurales: el cuerpo gira y choca alrededor de su mitad.

## Ritmo de los clips de nadar, como mucho.
const RATE_RANGE := Vector2(0.35, 2.0)

## La caja del modelo en reposo, centrada, en metros de la especie (sin el tamaño del individuo).
var bounds := AABB()

var _model: MarineModelData
var _meshes: Array[GeometryInstance3D] = []
var _center := Vector3.ZERO
var _biting: bool = false


func _init() -> void:
	cost_label = &"fauna:marine/anim"


func set_data(model: FaunaModelData, seed_value: int = 0) -> void:
	var changed := model != data
	super.set_data(model, seed_value)
	_model = model as MarineModelData
	_biting = false
	if changed:
		_meshes.clear()
		for node in _skin.find_children("*", "MeshInstance3D", true, false):
			_meshes.append(node as GeometryInstance3D)
		var box := _rest_box()
		_center = box.get_center()
		bounds = AABB(box.position - _center, box.size)
	_skin.position = -_center


## Lo que hace el cuerpo este paso: va a [speed] m/s, gira a [turn] rad/s (positivo a la izquierda),
## si va a la carga, y a qué escala está el individuo ([size]).
func swim(speed: float, turn: float, dashing: bool, size: float) -> void:
	if _model == null:
		return
	if _biting:
		if not _clip_done():
			return
		_biting = false
	var clip := _model.swim_clip
	var clip_speed := _model.swim_speed
	if dashing and _model.dash_clip != &"":
		clip = _model.dash_clip
		clip_speed = _model.dash_speed
	elif turn > _model.turn_rate and _model.turn_left_clip != &"":
		clip = _model.turn_left_clip
	elif turn < -_model.turn_rate and _model.turn_right_clip != &"":
		clip = _model.turn_right_clip
	var rate := clampf(speed / maxf(clip_speed * _model.scale * size, 0.01), RATE_RANGE.x, RATE_RANGE.y)
	# Del de crucero al de girar y vuelta, la cola sigue donde iba: el nuevo empieza en la misma fase.
	var phase := player.current_animation_position / maxf(player.current_animation_length, 0.01) \
		if player.current_animation != &"" else 0.0
	var was := current_clip
	_play(clip, _model.blend_time, rate)
	if current_clip != was and not _biting:
		player.seek(phase * player.current_animation_length)


## Muerde hacia [side] (positivo a la izquierda): una vez, y luego vuelve a nadar.
func bite(side: float) -> void:
	if _model == null:
		return
	var clip := _model.bite_left_clip if side > 0.0 else _model.bite_right_clip
	if clip == &"":
		return
	_biting = true
	_play(clip, 0.15, 1.0)


## 0 oculto, 1 opaco.
func set_fade(value: float) -> void:
	for mesh in _meshes:
		mesh.set_instance_shader_parameter(&"fade", value)


## La caja de las mallas en reposo, en el espacio de este nodo (sin su escala) y antes de centrarlas.
func _rest_box() -> AABB:
	var box := AABB()
	var first := true
	for mesh in _meshes:
		var to_self := Transform3D.IDENTITY
		var node: Node = mesh
		while node != self:
			to_self = (node as Node3D).transform * to_self if node is Node3D else to_self
			node = node.get_parent()
		var part := to_self * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box
