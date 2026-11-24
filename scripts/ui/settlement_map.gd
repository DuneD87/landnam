class_name SettlementMap extends RefCounted

## Los poblados en el mapa grande (WorldMapUI) y en el minimapa (Minimap): un icono por plantilla
## (textures/icons/settlements): la granja con su cerca, la aldea con dos casas, el poblado con la iglesia
## y la villa tras la empalizada. Son trazos blancos sobre otros de tinta: el blanco se tiñe (en hueso los
## que el jugador conoce, SettlementManager.map_sites con nombre; apagados los demás) y la tinta los hace
## legibles sobre cualquier terreno. De lejos en el mapa grande, solo un punto.

## Por encima de estos metros por píxel el mapa grande pone un punto en vez del icono.
const DOT_FROM := 90.0
## Por debajo de estos metros por píxel, el mapa grande rotula los poblados conocidos.
const LABEL_FROM := 40.0
const KNOWN := GameTheme.BONE
const UNKNOWN := Color(0.66, 0.63, 0.58, 0.8)
const OUTLINE := GameTheme.INK
const ICONS := {
	&"granja": preload("res://textures/icons/settlements/granja.svg"),
	&"aldea": preload("res://textures/icons/settlements/aldea.svg"),
	&"poblado": preload("res://textures/icons/settlements/poblado.svg"),
	&"villa": preload("res://textures/icons/settlements/villa.svg"),
}


## El icono del poblado de plantilla [kind], de [size] px de lado, centrado en [at].
static func draw(canvas: CanvasItem, at: Vector2, kind: StringName, size: float, known: bool) -> void:
	var icon: Texture2D = ICONS.get(kind, ICONS[&"aldea"])
	canvas.draw_texture_rect(icon, Rect2(at - Vector2.ONE * size * 0.5, Vector2.ONE * size), false,
		KNOWN if known else UNKNOWN)


## Un punto, para el mapa grande de lejos.
static func dot(canvas: CanvasItem, at: Vector2, radius: float, known: bool) -> void:
	canvas.draw_circle(at, radius + 1.0, OUTLINE)
	canvas.draw_circle(at, radius, KNOWN if known else UNKNOWN)
