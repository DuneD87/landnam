class_name SkinnedBirdModel
extends SkinnedModel

## El ave con esqueleto de un pack (BirdModelData) para AmbientBird, con la interfaz de
## SimpleBirdModel (set_species, animate, soars). El clip sale del estado del ave que lo lleva:
##   - posada: al tocar, el de tomar tierra; luego uno de los de quieta, sorteado al posarse, o el
##     de nadar si la deriva la mueve; y en el agua flota hundida float_depth;
##   - al despegar, el de despegue; volando, el de aletear (o el de planear entre aleteos);
##   - llegando a posarse, el de frenar en el aire.

## Más deprisa que esto (m/s) posada, nada.
const SWIM_SPEED := 0.15

@export var model: BirdModelData

var _was_state: int = -1
var _taking_off: bool = false
var _landing: bool = false
var _rest_clip: StringName = &""
var _afloat: float = 0.0
var _last_position := Vector3.INF


func _init() -> void:
	cost_label = &"fauna:birds/anim"


func set_species(_kind: int) -> void:
	if model == null:
		return
	set_data(model, randi())
	_was_state = -1
	_taking_off = false
	_landing = false
	_last_position = Vector3.INF
	_pick_rest_clip()


func soars() -> bool:
	return model != null and model.soars


func animate(_time: float, flying: bool, delta: float, flap: float = 1.0) -> void:
	if data == null:
		return
	var bird := get_parent() as AmbientBird
	var state: int = bird.state if bird != null \
		else (AmbientBird.State.FLYING if flying else AmbientBird.State.PERCHED)
	var perched := state == AmbientBird.State.PERCHED
	var drift := 0.0
	if _last_position != Vector3.INF and delta > 0.0:
		drift = global_position.distance_to(_last_position) / delta
	_last_position = global_position
	if _was_state < 0:
		_afloat = 1.0 if perched else 0.0
	if perched:
		_afloat = move_toward(_afloat, 1.0, delta * 2.5)
		if _was_state >= 0 and _was_state != AmbientBird.State.PERCHED:
			_pick_rest_clip()
			_landing = model.touchdown_clip != &""
			if _landing:
				_play(model.touchdown_clip, 0.15, 1.0)
		if _landing and _clip_done():
			_landing = false
		if not _landing:
			var swimming := drift > SWIM_SPEED and model.swim_clip != &""
			_play(model.swim_clip if swimming else _rest_clip, model.blend_time, 1.0)
	else:
		_afloat = move_toward(_afloat, 0.0, delta * 4.0)
		if _was_state == AmbientBird.State.PERCHED and model.takeoff_clip != &"":
			_taking_off = true
			_play(model.takeoff_clip, 0.15, 1.0)
		if _taking_off and _clip_done():
			_taking_off = false
		if not _taking_off:
			if state == AmbientBird.State.APPROACH and model.brake_clip != &"":
				_play(model.brake_clip, model.blend_time, 1.0)
			elif flap < 0.5 and model.glide_clip != &"":
				_play(model.glide_clip, model.blend_time, 1.0)
			else:
				_play(model.fly_clip, model.blend_time, model.flap_rate)
	_was_state = state
	_skin.position = Vector3.DOWN * model.float_depth * _afloat


func _pick_rest_clip() -> void:
	_rest_clip = model.perched_clips[_rng.randi() % model.perched_clips.size()] \
		if not model.perched_clips.is_empty() else model.idle_clip
