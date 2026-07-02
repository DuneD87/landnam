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

## El vertex shader reconstruye el quad en mundo, fuera del AABB del mesh: amplía el margen de culling.
func _enter_tree() -> void:
	_holder = _find_holder()
	extra_cull_margin = 1.0

func _ready() -> void:
	_light = get_node_or_null("../OmniLight3D") as OmniLight3D
	if _light != null:
		_base_energy = _light.light_energy

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
