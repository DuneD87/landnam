@tool
extends MeshInstance3D

## Acompaña a cualquier fuego con volumetric_fire.gdshader (antorcha, hoguera, brasero...).
## Pone el "arriba" del fuego por instancia = dirección desde el centro del planeta del portador
## (el PlanetaryBody ancestro) hasta el nodo, así vale con varios planetas y en multiplayer.
## En el editor (sin portador) usa el up local del nodo para poder colocarlo con referencia.
## Si existe una OmniLight3D hermana, la hace parpadear para vender el fuego en el entorno.

var _holder: PlanetaryBody
var _light: OmniLight3D
var _base_energy := 0.0
var _wants_shadow := false

## Cuántos fuegos proyectan sombra a la vez: los más cercanos a la cámara. Cada sombra de fuego
## repinta terreno, hierba y personajes de su radio, y una base con 9 fuegos gastaba en ellas
## la mitad del CPU de render (2,3 de 4,8 ms).
const MAX_SHADOWED := 3
## Cada cuántos frames se vuelve a elegir quién lleva sombra.
const SHADOW_PICK_EVERY := 15
## Ventaja en metros del fuego que ya lleva sombra, para que dos a la misma distancia no se la
## pasen de uno a otro a cada elección.
const SHADOW_KEEP_BIAS := 2.0

## Luces de fuego que quieren sombra (la traían encendida de serie).
static var _shadow_lights: Array[OmniLight3D] = []
static var _shadow_pick_frame := -1

## El vertex shader reconstruye el quad en mundo, fuera del AABB del mesh: amplía el margen de culling.
func _enter_tree() -> void:
	_holder = _find_holder()
	extra_cull_margin = 1.0
	# Al volver al árbol (cambio de padre) _ready no se repite.
	if _wants_shadow and not _shadow_lights.has(_light):
		_shadow_lights.append(_light)

func _ready() -> void:
	_light = get_node_or_null("../OmniLight3D") as OmniLight3D
	if _light != null:
		_base_energy = _light.light_energy
		if not Engine.is_editor_hint() and _light.shadow_enabled:
			# Dos pasadas por luz en vez de las seis del cubo.
			_light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
			_wants_shadow = true
			_shadow_lights.append(_light)

func _exit_tree() -> void:
	_shadow_lights.erase(_light)

## Sube por la cadena de padres hasta el primer PlanetaryBody (el portador de esta antorcha).
func _find_holder() -> PlanetaryBody:
	var n := get_parent()
	while n != null:
		if n is PlanetaryBody:
			return n
		n = n.get_parent()
	return null

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		set_instance_shader_parameter("up_axis", global_transform.basis.y.normalized())
		return
	_update_up_axis()
	_flicker_light()
	_pick_shadowed()

func _update_up_axis() -> void:
	if _holder == null or not is_instance_valid(_holder) or _holder.planet == null:
		return
	var up := global_position - _holder.planet.global_position
	if up.length() > 0.001:
		set_instance_shader_parameter("up_axis", up.normalized())

## Parpadeo de la luz: suma de senos a frecuencias no armónicas, sin aleatoriedad por frame.
func _flicker_light() -> void:
	if _light == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var f := 0.9 + 0.08 * sin(t * 11.3) + 0.05 * sin(t * 27.7 + 1.7) + 0.04 * sin(t * 5.1 + 4.0)
	_light.light_energy = _base_energy * f


## Reparte las sombras entre los fuegos encendidos: solo los MAX_SHADOWED más cercanos a la
## cámara. Lo llaman todos los fuegos, pero solo trabaja una vez cada SHADOW_PICK_EVERY frames.
func _pick_shadowed() -> void:
	var frame := Engine.get_process_frames()
	if frame - _shadow_pick_frame < SHADOW_PICK_EVERY and frame >= _shadow_pick_frame:
		return
	_shadow_pick_frame = frame
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	var ranked := []
	for light in _shadow_lights:
		if not is_instance_valid(light) or not light.is_visible_in_tree():
			continue
		var distance := light.global_position.distance_to(eye)
		if light.shadow_enabled:
			distance -= SHADOW_KEEP_BIAS
		ranked.append([distance, light])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in ranked.size():
		var light: OmniLight3D = ranked[i][1]
		var wanted := i < MAX_SHADOWED
		if light.shadow_enabled != wanted:
			light.shadow_enabled = wanted
