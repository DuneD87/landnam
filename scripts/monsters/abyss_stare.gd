class_name AbyssStare
extends Node

## La mirada del abismo vista desde el jugador (la echa Cthulhu). Mientras dura, el cuerpo no responde
## (PlayerController da el paso con el input en reposo: gravedad, agua y barco siguen), la vista tira
## sola hacia los ojos que lo miran y cierra el encuadre, el mundo se retuerce y la cordura se va.
##
## No le mires: la cordura cae deprisa con sus ojos en el centro de la vista y casi nada con la vista
## apartada. El ratón aún gira la cámara (más despacio, contra el tirón), y el botón de la guardia
## (attack_2) tapa los ojos con las manos: no se ve casi nada, pero tira menos y deja pasar muy poco.
## Si algo se pone en medio (una cubierta, el agua por encima de la cabeza) tampoco cuenta.
## Al soltarlo quedan unos minutos de secuelas, más largas cuanto más cordura se perdió.

const SHADER := preload("res://shaders/effects/abyss_gaze.gdshader")
## Lo que duran las secuelas enteras (s), de entero a nada.
const AFTERMATH_TIME := 180.0
## Cuánto se cierra el encuadre (grados de FOV) con la mirada entera.
const FOV_DROP := 24.0
## Lo que tarda en entrar la mirada y en irse al soltar (s).
const RISE_TIME := 0.9
const FALL_TIME := 2.5
## Latido: intervalo mirándolo de lleno, con la vista apartada y en las secuelas (s).
const BEAT_STARE := 0.45
const BEAT_AWAY := 0.75
const BEAT_AFTER := 1.1
## Cordura por segundo con sus ojos en el centro de la vista y con la vista apartada del todo. De lleno
## toda la mirada (~7 s) la vacía; apartando la vista se pierde poco más de un 10 %.
const DRAIN_FULL := 0.24
const DRAIN_AWAY := 0.015
## Ángulo (grados) entre la vista y sus ojos: hasta LOOK_CORE se le mira de lleno; desde LOOK_EDGE, nada.
const LOOK_CORE := 9.0
const LOOK_EDGE := 38.0
## Taparse los ojos: lo que tardan en subir las manos (s) y lo que dejan pasar.
const COVER_TIME := 0.35
const COVER_LEAK := 0.1
## Lo que tira de la vista con los ojos tapados (parte del tirón normal) y lo que responde el ratón.
const PULL_COVERED := 0.35
const MOUSE_RESIST := 0.6
## Cordura perdida (0..1) que deja las secuelas enteras.
const AFTERMATH_FULL := 0.6

## 0..1: lo que se le está mirando ahora (para el HUD y la consola).
var exposure := 0.0

var _player: PlayerController
## Quien mira: un nodo con eye_position() -> Vector3 (mundo) y, si lo tiene, target_visible.
var _source: Node = null
var _duration := 4.0
var _time := 0.0
var _lost := 0.0
var _stare := 0.0
var _cover := 0.0
var _seen := 0.0
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


## Empieza la mirada de [source] durante [duration] s.
func begin(source: Node, duration: float) -> void:
	if _player == null or _player.combat.is_dead():
		return
	_source = source
	_duration = maxf(duration, 0.5)
	_time = 0.0
	_lost = 0.0
	_beat_timer = 0.0
	if _player.hotbar != null:
		_player.hotbar.notify(tr("ABYSS_DONT_LOOK"))


## Suelta al jugador antes de tiempo (quien miraba se ha ido). Las secuelas quedan igual.
func release() -> void:
	if _source == null:
		return
	_source = null
	_aftermath = maxf(_aftermath, clampf(_lost / AFTERMATH_FULL, 0.15, 1.0))
	if _player != null:
		_player.camera_controller.stare_point = null
		_player.camera_controller.stare_pull = 1.0
		_player.camera_controller.stare_resist = 1.0


func is_transfixed() -> bool:
	return _source != null


## 0..1: lo que queda de las secuelas.
func aftermath() -> float:
	return _aftermath


## 0..1: lo tapados que están los ojos.
func covered() -> float:
	return _cover


func _process(delta: float) -> void:
	if _player == null:
		return
	if _source != null and (not is_instance_valid(_source) or _player.combat.is_dead()):
		release()
	var camera := _player.camera_controller
	if _source != null:
		_time += delta
		var covering := Input.is_action_pressed(&"attack_2") and _player.is_mouse_captured()
		_cover = move_toward(_cover, 1.0 if covering else 0.0, delta / COVER_TIME)
		exposure = _exposure()
		var before := _player.needs.sanity
		_player.needs.sanity = maxf(0.0, before - lerpf(DRAIN_AWAY, DRAIN_FULL, exposure) * delta)
		_lost += before - _player.needs.sanity
		camera.stare_point = _source.eye_position()
		camera.stare_pull = lerpf(1.0, PULL_COVERED, _cover)
		camera.stare_resist = MOUSE_RESIST
		if _time >= _duration:
			release()
	else:
		exposure = 0.0
		_cover = move_toward(_cover, 0.0, delta / COVER_TIME)
	_seen = move_toward(_seen, exposure, delta * 2.5)
	_stare = move_toward(_stare, 1.0 if _source != null else 0.0, delta / (RISE_TIME if _source != null else FALL_TIME))
	_aftermath = maxf(0.0, _aftermath - delta / AFTERMATH_TIME)
	var stare := smoothstep(0.0, 1.0, _stare)
	camera.stare_weight = stare
	camera.stare_fov_drop = FOV_DROP * stare * lerpf(0.45, 1.0, _seen)
	_update_heart(delta)
	var shown := stare > 0.002 or _aftermath > 0.002 or _cover > 0.002
	_overlay.visible = shown
	if shown:
		# Con la vista apartada el mundo se retuerce menos: así se nota que funciona.
		_material.set_shader_parameter(&"amount", stare * lerpf(0.35, 1.0, _seen))
		_material.set_shader_parameter(&"after", _aftermath)
		_material.set_shader_parameter(&"pulse", _pulse)
		_material.set_shader_parameter(&"cover", smoothstep(0.0, 1.0, _cover))


## Lo que se le mira: el ángulo entre la vista y sus ojos, si nada se pone en medio, menos lo que
## tapan las manos.
func _exposure() -> float:
	var camera := _player.camera
	if camera == null:
		return 1.0
	var to: Vector3 = _source.eye_position() - camera.global_position
	var angle := rad_to_deg((-camera.global_basis.z).angle_to(to))
	var seen := 1.0 - smoothstep(LOOK_CORE, LOOK_EDGE, angle)
	if &"target_visible" in _source and not _source.get(&"target_visible"):
		seen = 0.0
	return seen * lerpf(1.0, COVER_LEAK, _cover)


func _update_heart(delta: float) -> void:
	_pulse = maxf(0.0, _pulse - delta * 3.0)
	var strength := maxf(_stare * lerpf(0.6, 1.0, _seen), _aftermath * 0.5)
	if strength < 0.05:
		_beat_timer = 0.0
		return
	_beat_timer -= delta
	if _beat_timer > 0.0:
		return
	_beat_timer = lerpf(BEAT_AFTER, lerpf(BEAT_AWAY, BEAT_STARE, _seen), _stare)
	_pulse = 1.0
	CombatFx.play(&"heartbeat", _player.global_position, {"volume_offset_db": lerpf(-14.0, 2.0, strength)})
