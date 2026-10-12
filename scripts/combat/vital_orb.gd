class_name VitalOrb
extends Control

## Orbe de vida o de aguante, a lo Diablo pero en Saga: una esfera de cristal con un líquido que
## llega hasta lo que queda (vital_orb.gdshader) y un aro de bronce con cuatro remaches. Las dos
## van encajadas en la consola de la barra rápida (Hotbar, VitalsPlate) y CombatHUD les da cada
## fotograma el nivel, el tramo perdido y los avisos. La cifra sale un momento en el centro cuando
## cambia. La de la cordura es media orbe (half), con la base plana sobre la barra.

const SHADER := preload("res://shaders/ui/vital_orb.gdshader")
## Segundos que se ve la cifra tras un cambio, y lo que tarda en irse.
const VALUE_HOLD := 1.6
const VALUE_FADE := 0.5

## Destello del aro (falta aguante para el golpe, o un golpe recibido).
var flash := 0.0
var flash_color := GameTheme.BRONZE.lightened(0.35)
## Media orbe: el control es solo la mitad de arriba y el centro queda en su borde de abajo.
var half := false

var _liquid := ColorRect.new()
var _rim := Control.new()
var _value := Label.new()
var _value_text := ""
var _value_age := INF


static func health() -> VitalOrb:
	var orb := VitalOrb.new(Color(0.71, 0.1, 0.08), Color(0.19, 0.02, 0.02), Color(0.86, 0.66, 0.3))
	orb.flash_color = Color(1.0, 0.45, 0.35)
	return orb


static func stamina() -> VitalOrb:
	var orb := VitalOrb.new(Color(0.42, 0.64, 0.33), Color(0.06, 0.12, 0.05), Color(0.86, 0.66, 0.3))
	orb.flash_color = Color(0.95, 0.82, 0.35)
	return orb


## Media orbe violeta: la cordura, en el centro de la barra.
static func sanity() -> VitalOrb:
	var orb := VitalOrb.new(Color(0.5, 0.33, 0.76), Color(0.09, 0.04, 0.15), Color(0.86, 0.66, 0.3))
	orb.half = true
	(orb._liquid.material as ShaderMaterial).set_shader_parameter(&"half_orb", 1.0)
	orb.flash_color = Color(0.8, 0.6, 1.0)
	return orb


func _init(liquid: Color, deep: Color, trail: Color) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"liquid_color", liquid)
	material.set_shader_parameter(&"deep_color", deep)
	material.set_shader_parameter(&"trail_color", trail)
	var noise := NoiseTexture2D.new()
	noise.seamless = true
	noise.width = 128
	noise.height = 128
	var fast := FastNoiseLite.new()
	fast.frequency = 0.03
	fast.fractal_octaves = 3
	noise.noise = fast
	material.set_shader_parameter(&"noise", noise)
	_liquid.material = material
	_liquid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_liquid)
	_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rim.draw.connect(_draw_rim)
	add_child(_rim)
	_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.add_theme_font_override("font", GameTheme.medium_font())
	_value.add_theme_color_override("font_color", GameTheme.BONE)
	_value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_value.modulate.a = 0.0
	add_child(_value)


## Centro y radio en pantalla; [ui_scale] para el grosor del aro y la cifra.
func place(centre: Vector2, radius: float, ui_scale: float) -> void:
	position = centre - Vector2(radius, radius)
	size = Vector2(radius * 2.0, radius if half else radius * 2.0)
	_liquid.position = Vector2.ZERO
	_liquid.size = size
	_rim.position = Vector2.ZERO
	_rim.size = size
	_value.add_theme_font_size_override("font_size", roundi((18 if half else 24) * ui_scale))
	_value.add_theme_constant_override("outline_size", roundi(6 * ui_scale))
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.size = Vector2(size.x, size.y * (0.75 if half else 1.0))
	_value.position = Vector2(0.0, size.y * (0.25 if half else 0.0))
	_rim.queue_redraw()


## [fill] y [trail] de 0 a 1; [glow] aclara el líquido y [dim] lo apaga.
func set_levels(fill: float, trail: float, glow: float, dim: float, value_text: String, delta: float) -> void:
	var material := _liquid.material as ShaderMaterial
	material.set_shader_parameter(&"fill", clampf(fill, 0.0, 1.0))
	material.set_shader_parameter(&"trail", clampf(trail, 0.0, 1.0))
	material.set_shader_parameter(&"glow", clampf(glow, 0.0, 1.0))
	material.set_shader_parameter(&"dim", clampf(dim, 0.0, 1.0))
	if value_text != _value_text:
		_value_text = value_text
		_value.text = value_text
		_value_age = 0.0
	else:
		_value_age += delta
	_value.modulate.a = clampf(1.0 - (_value_age - VALUE_HOLD) / VALUE_FADE, 0.0, 1.0)
	_rim.queue_redraw()


func _draw_rim() -> void:
	var radius := size.x * 0.5
	if radius <= 0.0:
		return
	var centre := Vector2(radius, radius)
	var s := radius / 75.0
	var bronze := GameTheme.BRONZE.lerp(flash_color, clampf(flash, 0.0, 1.0))
	# Aro: una banda oscura de bronce entre dos filetes, el de fuera más vivo. La media orbe lo
	# lleva solo por arriba y cierra con un filete recto en la base.
	var from := PI if half else 0.0
	var points := 48 if half else 96
	_rim.draw_arc(centre, radius - 3.0 * s, from, TAU, points, GameTheme.BRONZE_DARK.darkened(0.35), 6.0 * s, true)
	_rim.draw_arc(centre, radius - 0.6 * s, from, TAU, points, bronze.darkened(0.12), 1.2 * s, true)
	_rim.draw_arc(centre, radius - 2.25 * s, PI, TAU, 64, bronze.lightened(0.08), 2.0 * s, true)
	if not half:
		_rim.draw_arc(centre, radius - 2.25 * s, 0.0, PI, 64, bronze.darkened(0.42), 2.0 * s, true)
	_rim.draw_arc(centre, radius - 5.5 * s, from, TAU, points, GameTheme.INK, 1.3 * s, true)
	_rim.draw_arc(centre, radius - 3.0 * s, PI * 1.08, PI * 1.47, 32,
		Color(GameTheme.BONE, 0.75), 0.8 * s, true)
	if half:
		_rim.draw_line(Vector2(0.0, radius - 0.6 * s), Vector2(radius * 2.0, radius - 0.6 * s), bronze, 1.2 * s, true)
	var rivets := [PI, PI * 1.5, TAU] if half else [0.0, PI * 0.5, PI, PI * 1.5]
	for angle in rivets:
		var at := centre + Vector2.from_angle(angle) * (radius - 2.5 * s)
		if half:
			at.y = minf(at.y, radius - 3.5 * s)
		_rim.draw_colored_polygon(SagaFrame.diamond(at, 2.5 * s), bronze)
		_rim.draw_colored_polygon(SagaFrame.diamond(at, 1.0 * s), GameTheme.INK)
