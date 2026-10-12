class_name VitalsPlate
extends TextureRect

## Consola compacta de hierro forjado: el riel central conecta dos cápsulas circulares para vida
## y aguante. El riel y los engastes continúan hasta el borde inferior como un zócalo.
## Las bandas de runas, los medidores, las abrazaderas y la trenza quedan tallados en el metal.
## La media orbe de cordura asoma por el centro. Imagen horneada con
## tools/ui/bake_hotbar_console.py; se coloca a partir del panel de la barra.

const TEXTURE := preload("res://textures/ui/hotbar_console.png")
## Píxeles de la imagen por píxel de la UI a 1440 px de alto, y dónde empieza en ella el panel de
## la barra (los imprime el script al hornear; tienen que coincidir).
const ART_SCALE := 2.0
const BAR_ORIGIN := Vector2(480, 164)
## Cuánto sale la talla a cada lado del panel, en la escala base (para colocar lo de al lado).
const REACH := 240.0


func _init() -> void:
	texture = TEXTURE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## [bar] es el panel de la barra rápida en pantalla.
func layout(bar: Rect2, ui_scale: float) -> void:
	var factor := ui_scale / ART_SCALE
	position = bar.position - BAR_ORIGIN * factor
	size = Vector2(TEXTURE.get_size()) * factor


## Borde izquierdo de la talla en pantalla.
func left_edge(bar: Rect2, ui_scale: float) -> float:
	return bar.position.x - REACH * ui_scale
