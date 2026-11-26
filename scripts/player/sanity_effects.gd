class_name SanityEffects
extends Node

## Lo que hace la cordura baja (SurvivalNeeds.sanity), por tramos:
##   - Inquieto (bajo UNEASY): susurros sueltos alrededor de la cabeza y los bordes de la vista que se
##     oscurecen y se mueven.
##   - Perturbado (bajo DISTURBED): pasos que se acercan por la espalda, una figura oscura que asoma un
##     momento en el borde de la vista, el color que se va y la imagen que respira.
##   - Al borde (bajo BREAKING): gruñidos de fieras que no están, todo más a menudo, y las pesadillas no
##     dejan dormir de un tirón (RestController) ni el aguante se recupera igual (SurvivalNeeds).
## Nada de esto mata: es la cordura la que se pierde. Se pasa como se recupera la cordura (de día y
## descansado, durmiendo, comiendo asado).
##
## Lo crea PlayerController. Es del jugador local: cada jugador ve y oye solo lo suyo.

## Las sombras del borde y la figura (multiplican, sin leer la pantalla) y, desde perturbado, la imagen
## que respira y pierde el color (lee la pantalla: una copia del fondo cada fotograma, por eso aparte).
const SHADER := preload("res://shaders/effects/sanity.gdshader")
const WARP_SHADER := preload("res://shaders/effects/sanity_warp.gdshader")
const UNEASY := 0.5
const DISTURBED := 0.25
const BREAKING := 0.1
## Segundos entre susurros con la cordura en UNEASY y a cero (con un ±40 %).
const WHISPER_EVERY := Vector2(75.0, 14.0)
const STEPS_EVERY := Vector2(110.0, 35.0)
const GROWL_EVERY := Vector2(140.0, 60.0)
const FIGURE_EVERY := Vector2(80.0, 25.0)
## Lo que tarda en entrar y salir la figura del borde (s) y lo que se queda.
const FIGURE_FADE := 0.5
const FIGURE_HOLD := Vector2(0.6, 1.6)
const GROWLS: Array[StringName] = [&"wolf_growl", &"lion_growl", &"bear_growl"]

## 0..1: lo hondo que se está (0 sobre UNEASY, 1 sin cordura), suavizado.
var level := 0.0

var _player: PlayerController
var _overlay: ColorRect
var _material: ShaderMaterial
var _warp: ColorRect
var _warp_material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _whisper_timer := 0.0
var _steps_timer := 0.0
var _growl_timer := 0.0
var _figure_timer := 0.0
## Pasos que faltan por sonar, su ritmo y desde dónde se acercan (relativo al jugador).
var _steps_left := 0
var _step_clock := 0.0
var _step_offset := Vector3.ZERO
var _figure_age := -1.0
var _figure_hold := 1.0
var _figure_uv := Vector2.ZERO
var _last_forward := Vector3.ZERO


func setup(player: PlayerController) -> void:
	_player = player
	_rng.randomize()
	var layer := CanvasLayer.new()
	layer.name = "Sanity"
	# Debajo de la mirada del abismo (8), del desangrado (9) y de la interfaz.
	layer.layer = 7
	add_child(layer)
	_warp_material = ShaderMaterial.new()
	_warp_material.shader = WARP_SHADER
	_warp = _full_rect(_warp_material)
	layer.add_child(_warp)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_overlay = _full_rect(_material)
	layer.add_child(_overlay)
	_whisper_timer = _rng.randf_range(10.0, 30.0)
	_steps_timer = _rng.randf_range(20.0, 40.0)
	_growl_timer = _rng.randf_range(30.0, 60.0)
	_figure_timer = _rng.randf_range(15.0, 30.0)


func _full_rect(material: ShaderMaterial) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = material
	rect.visible = false
	return rect


## 0..1: lo hondo que está [sanity] respecto a un tramo (1 a cero, 0 desde [from]).
static func depth(sanity: float, from: float) -> float:
	return clampf((from - sanity) / from, 0.0, 1.0)


func _process(delta: float) -> void:
	if _player == null or _player.needs == null:
		return
	var sanity := _player.needs.sanity
	level = move_toward(level, depth(sanity, UNEASY), delta / 4.0)
	var active := _active()
	var shown := level > 0.005 and _player.visible
	_overlay.visible = shown
	if shown:
		_material.set_shader_parameter(&"intensity", level)
	var disturbed_now := depth(sanity, DISTURBED)
	_warp.visible = shown and disturbed_now > 0.005
	if _warp.visible:
		_warp_material.set_shader_parameter(&"disturbed", disturbed_now)
	if not active:
		_steps_left = 0
		_update_figure(delta, false)
		return
	var dt := delta
	_whisper_timer -= dt
	if _whisper_timer <= 0.0:
		_whisper_timer = _interval(WHISPER_EVERY, level)
		if sanity < UNEASY:
			_whisper()
	var disturbed := depth(sanity, DISTURBED)
	_steps_timer -= dt
	if _steps_timer <= 0.0:
		_steps_timer = _interval(STEPS_EVERY, disturbed)
		if sanity < DISTURBED:
			_start_steps()
	_play_steps(dt)
	var breaking := depth(sanity, BREAKING)
	_growl_timer -= dt
	if _growl_timer <= 0.0:
		_growl_timer = _interval(GROWL_EVERY, breaking)
		if sanity < BREAKING:
			_growl()
	_figure_timer -= dt
	if _figure_timer <= 0.0:
		_figure_timer = _interval(FIGURE_EVERY, disturbed)
		if sanity < DISTURBED and _figure_age < 0.0:
			_start_figure()
	_update_figure(delta, true)


## Despierto, vivo y jugando: dormido, muerto o en un menú no se oye nada.
func _active() -> bool:
	if GameManager.current_state != GameManager.State.PLAYING or not _player.visible:
		return false
	if _player.combat.is_dead() or _player.needs.sleeping or _player.needs.paused:
		return false
	return true


func _interval(range_: Vector2, k: float) -> float:
	return lerpf(range_.x, range_.y, k) * _rng.randf_range(0.6, 1.4)


func _up() -> Vector3:
	var up := _player.up_direction
	return up.normalized() if up.length_squared() > 0.0001 else Vector3.UP


## Vectores del jugador: derecha y atrás según la cámara, en el plano del suelo.
func _frame() -> Array[Vector3]:
	var up := _up()
	var back := _player.camera.global_basis.z.slide(up)
	back = back.normalized() if back.length_squared() > 0.001 else up.cross(Vector3.RIGHT).normalized()
	return [up.cross(back).normalized(), back, up]


## Un susurro junto a una oreja o a la espalda, a un par de metros.
func _whisper() -> void:
	var event := AudioManager.get_event(&"sanity_whisper")
	if event == null:
		return
	var frame := _frame()
	var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
	var direction: Vector3 = (frame[0] * side * _rng.randf_range(0.5, 1.0) + frame[1] * _rng.randf_range(0.0, 1.0)).normalized()
	var at: Vector3 = _player.global_position + frame[2] * 1.7 + direction * _rng.randf_range(1.2, 2.5)
	AudioManager.play_event_3d(event, at, {"volume_offset_db": lerpf(-8.0, 0.0, level)})


## Cuatro a siete pasos que se acercan por la espalda y se callan de golpe.
func _start_steps() -> void:
	var frame := _frame()
	_steps_left = _rng.randi_range(4, 7)
	_step_clock = 0.0
	_step_offset = (frame[1] * 1.0 + frame[0] * _rng.randf_range(-0.4, 0.4)).normalized() * _rng.randf_range(9.0, 13.0)


func _play_steps(dt: float) -> void:
	if _steps_left <= 0:
		return
	_step_clock -= dt
	if _step_clock > 0.0:
		return
	_step_clock = _rng.randf_range(0.48, 0.58)
	_steps_left -= 1
	# Cada paso, un poco más cerca.
	_step_offset *= 0.82
	var up := _up()
	var at := _player.global_position + _step_offset
	var query := PhysicsRayQueryParameters3D.create(at + up * 3.0, at - up * 6.0, _player.collision_mask, [_player.get_rid()])
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_steps_left = 0
		return
	var family := SurfaceAudio.resolve(hit, _planet_root(), up)
	AudioManager.play_material(&"step_walk", family, hit["position"], {"volume_offset_db": -3.0})


func _planet_root() -> Node3D:
	var n: Node = _player
	while n != null:
		if n is PlanetaryBody:
			return n.planet
		n = n.get_parent()
	return null


## Una fiera que gruñe entre los árboles, a la espalda. No hay nada.
func _growl() -> void:
	var frame := _frame()
	var direction: Vector3 = (frame[1] + frame[0] * _rng.randf_range(-0.8, 0.8)).normalized()
	var at: Vector3 = _player.global_position + direction * _rng.randf_range(12.0, 22.0) + frame[2] * 0.6
	CombatFx.play(GROWLS[_rng.randi() % GROWLS.size()], at, {"volume_offset_db": -3.0})


## Una figura en el borde de la vista, que se va antes de poder mirarla.
func _start_figure() -> void:
	_figure_age = 0.0
	_figure_hold = _rng.randf_range(FIGURE_HOLD.x, FIGURE_HOLD.y)
	var side := 0.07 if _rng.randf() < 0.5 else 0.93
	_figure_uv = Vector2(side + _rng.randf_range(-0.03, 0.03), _rng.randf_range(0.5, 0.62))


func _update_figure(delta: float, active: bool) -> void:
	# Si se gira la vista deprisa (más de 40°/s, a buscarla), se esfuma antes.
	var forward := -_player.camera.global_basis.z
	var turned := _last_forward != Vector3.ZERO and forward.angle_to(_last_forward) > deg_to_rad(40.0) * delta
	_last_forward = forward
	if _figure_age < 0.0:
		_material.set_shader_parameter(&"figure_alpha", 0.0)
		return
	_figure_age += delta
	var total := FIGURE_FADE * 2.0 + _figure_hold
	if not active or _figure_age >= total or (turned and _figure_age > FIGURE_FADE):
		_figure_age = -1.0
		_material.set_shader_parameter(&"figure_alpha", 0.0)
		return
	var alpha := minf(_figure_age / FIGURE_FADE, 1.0) * clampf((total - _figure_age) / FIGURE_FADE, 0.0, 1.0)
	_material.set_shader_parameter(&"figure_alpha", alpha * 0.85)
	_material.set_shader_parameter(&"figure_uv", _figure_uv)
