class_name XpStrip
extends Control

## La experiencia del nivel en curso (Progression): una barra de bronce bajo la barra rápida, de
## engaste a engaste, en el hueco liso que le deja la consola (bake_hotbar_console.py: XP_X0, XP_X1).
## Al ganar XP el relleno se aviva un momento; al subir de nivel destella entera antes de vaciarse.

## Dónde va respecto al panel de la barra, en la escala base: de lado a lado (lo que sobresale
## por cada lado) y su alto, en medio del hueco hasta el borde de la pantalla.
const OVERHANG := 10.0
const HEIGHT := 10.0
## Lo que dura el brillo al ganar XP (s).
const GLOW_TIME := 1.2

var _ratio := 0.0
var _shown_ratio := 0.0
var _glow := 0.0
var _level_flash := 0.0
var _scale := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Bajo el panel [bar] de la barra rápida, en medio de los [gap] px hasta el borde de la pantalla.
func place(bar: Rect2, gap: float, ui_scale: float) -> void:
	_scale = ui_scale
	size = Vector2(bar.size.x + 2.0 * OVERHANG * ui_scale, HEIGHT * ui_scale).round()
	position = Vector2(bar.position.x - OVERHANG * ui_scale, bar.end.y + (gap - size.y) * 0.5).round()
	queue_redraw()


## Lo que lleva del nivel (0-1). [gained]: lo ha cambiado una ganancia de XP (se aviva).
func set_ratio(ratio: float, gained := false) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	if gained:
		_glow = 1.0
	queue_redraw()


## Ha subido de nivel: destella entera antes de vaciarse.
func flash_level() -> void:
	_level_flash = 1.0


func _process(delta: float) -> void:
	var redraw := false
	if _glow > 0.0:
		_glow = maxf(_glow - delta / GLOW_TIME, 0.0)
		redraw = true
	if _level_flash > 0.0:
		_level_flash = maxf(_level_flash - delta / 1.5, 0.0)
		redraw = true
	if not is_equal_approx(_shown_ratio, _ratio):
		# Al vaciarse (nivel nuevo) baja de golpe; al llenarse, corre.
		_shown_ratio = _ratio if _ratio < _shown_ratio else move_toward(_shown_ratio, _ratio, delta * 0.8)
		redraw = true
	if redraw:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, GameTheme.IRON_DEEP)
	var fill := maxf(_shown_ratio, _level_flash)
	if fill > 0.0:
		var color := GameTheme.BRONZE_DARK.lerp(GameTheme.BRONZE, 0.55 + 0.45 * _glow) \
			.lerp(GameTheme.BONE, _level_flash * 0.6)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * fill, rect.size.y)), color)
	draw_rect(rect, GameTheme.BRONZE_LINE, false, maxf(1.0, roundf(_scale)))
