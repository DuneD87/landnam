class_name BreathRing
extends TextureRect

## El oxígeno, solo bajo el agua: las runas del engaste del aguante («þrek auk andi», y andi es
## aliento) se encienden en azul y se van apagando en el sentido de las agujas del reloj según se
## acaba el aire. Al sacar la cabeza se rellena y, lleno, se apaga. La textura son esas runas solas,
## horneadas con la consola (tools/ui/bake_hotbar_console.py) y centradas en el engaste.

const TEXTURE := preload("res://textures/ui/hotbar_breath_runes.png")
const SHADER := preload("res://shaders/ui/breath_runes.gdshader")
## Píxeles de la imagen por píxel de la UI a 1440 px de alto (como VitalsPlate.ART_SCALE).
const ART_SCALE := 2.0
## Segundos que sigue encendido ya lleno, y lo que tarda en aparecer o irse.
const LINGER := 1.2
const FADE := 0.35

var _shown := 0.0
var _full_for := INF


func _init() -> void:
	texture = TEXTURE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"alpha", 0.0)
	material = mat


## Centrado en el engaste del aguante.
func place(centre: Vector2, ui_scale: float) -> void:
	size = Vector2(TEXTURE.get_size()) * ui_scale / ART_SCALE
	position = centre - size * 0.5


func set_oxygen(oxygen: float, submerged: bool, delta: float) -> void:
	_full_for = 0.0 if submerged or oxygen < 0.999 else _full_for + delta
	var target := 1.0 if _full_for < LINGER else 0.0
	_shown = move_toward(_shown, target, delta / FADE)
	var mat := material as ShaderMaterial
	mat.set_shader_parameter(&"alpha", _shown)
	mat.set_shader_parameter(&"fill", clampf(oxygen, 0.0, 1.0))
	mat.set_shader_parameter(&"warn", 1.0 if oxygen <= 0.25 else 0.0)
