class_name AbyssStare
extends Node

## La mirada del abismo vista desde el jugador (la echa Cthulhu). Mientras dura, el cuerpo no responde
## (PlayerController da el paso con el input en reposo: gravedad, agua y barco siguen), la cámara se
## va sola hacia los ojos que lo miran y cierra el encuadre, el mundo se retuerce y la cordura se vacía
## hasta cero. Al soltarlo quedan unos minutos de secuelas que se van pasando.

const SHADER := preload("res://shaders/effects/abyss_gaze.gdshader")
## Lo que duran las secuelas (s), de entero a nada.
const AFTERMATH_TIME := 180.0
## Cuánto se cierra el encuadre (grados de FOV) con la mirada entera.
const FOV_DROP := 24.0
## Lo que tarda en entrar la mirada y en irse al soltar (s).
const RISE_TIME := 0.9
const FALL_TIME := 2.5
## Latido: intervalo en plena mirada y en las secuelas (s).
const BEAT_STARE := 0.5
const BEAT_AFTER := 1.1

var _player: PlayerController
## Quien mira: un nodo con eye_position() -> Vector3 (mundo).
var _source: Node = null
var _duration := 4.0
var _time := 0.0
var _start_sanity := 1.0
var _stare := 0.0
var _aftermath := 0.0
var _beat_timer := 0.0
var _pulse := 0.0
var _overlay: ColorRect
var _material: ShaderMaterial


func setup(player: PlayerController) -> void:
	_player = player
	var layer := CanvasLayer.new()
	layer.name = "AbyssStare"
	# Debajo del desangrado (9) y de la interfaz.
	layer.layer = 8
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_overlay.material = _material
	_overlay.visible = false
	layer.add_child(_overlay)


## Empieza la mirada de [source] durante [duration] s: al acabar, la cordura está a cero.
func begin(source: Node, duration: float) -> void:
	if _player == null or _player.combat.is_dead():
		return
	_source = source
	_duration = maxf(duration, 0.5)
	_time = 0.0
	_start_sanity = _player.needs.sanity
	_beat_timer = 0.0


## Suelta al jugador antes de tiempo (quien miraba se ha ido). Las secuelas quedan igual.
func release() -> void:
	if _source == null:
		return
	_source = null
	_aftermath = maxf(_aftermath, clampf(_time / _duration, 0.0, 1.0))
	if _player != null:
		_player.camera_controller.stare_point = null


func is_transfixed() -> bool:
	return _source != null


## 0..1: lo que queda de las secuelas.
func aftermath() -> float:
	return _aftermath


func _process(delta: float) -> void:
	if _player == null:
		return
	if _source != null and (not is_instance_valid(_source) or _player.combat.is_dead()):
		release()
	if _source != null:
		_time += delta
		var t := clampf(_time / _duration, 0.0, 1.0)
		_player.needs.sanity = lerpf(_start_sanity, 0.0, pow(t, 0.75))
		_player.camera_controller.stare_point = _source.eye_position()
		if _time >= _duration:
			_player.needs.sanity = 0.0
			release()
	_stare = move_toward(_stare, 1.0 if _source != null else 0.0, delta / (RISE_TIME if _source != null else FALL_TIME))
	_aftermath = maxf(0.0, _aftermath - delta / AFTERMATH_TIME)
	var stare := smoothstep(0.0, 1.0, _stare)
	_player.camera_controller.stare_weight = stare
	_player.camera_controller.stare_fov_drop = FOV_DROP * stare
	_update_heart(delta)
	var visible := stare > 0.002 or _aftermath > 0.002
	_overlay.visible = visible
	if visible:
		_material.set_shader_parameter(&"amount", stare)
		_material.set_shader_parameter(&"after", _aftermath)
		_material.set_shader_parameter(&"pulse", _pulse)


func _update_heart(delta: float) -> void:
	_pulse = maxf(0.0, _pulse - delta * 3.0)
	var strength := maxf(_stare, _aftermath * 0.5)
	if strength < 0.05:
		_beat_timer = 0.0
		return
	_beat_timer -= delta
	if _beat_timer > 0.0:
		return
	_beat_timer = lerpf(BEAT_AFTER, BEAT_STARE, _stare)
	_pulse = 1.0
	CombatFx.play(&"heartbeat", _player.global_position, {"volume_offset_db": lerpf(-14.0, 2.0, strength)})
