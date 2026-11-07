class_name PickupPopup
extends Label3D

## «+3 Piedra» que sube y se desvanece donde se ha cosechado algo que entra solo en el inventario
## (picar una roca o el terreno, partir un leño). Se ve a través de lo que tenga delante y sigue
## al origen flotante.

## Lo que sube (m) y lo que dura (s): sube deprisa frenando y se desvanece en la segunda mitad.
const RISE := 0.7
const LIFETIME := 1.4
const COLOR := Color(1.0, 0.93, 0.72)
const WARNING := Color(1.0, 0.45, 0.35)

var _up := Vector3.UP
var _t := 0.0


## [text] en [at] (mundo), subiendo hacia [up], del color [color].
static func spawn(context: Node, at: Vector3, up: Vector3, text: String, color := COLOR) -> PickupPopup:
	var popup := PickupPopup.new()
	popup.text = text
	popup.modulate = color
	popup._up = up.normalized()
	context.get_tree().current_scene.add_child(popup)
	popup.global_position = at
	return popup


func _init() -> void:
	name = "PickupPopup"
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	render_priority = 10
	outline_render_priority = 9
	font_size = 56
	outline_size = 14
	pixel_size = 0.004
	outline_modulate = Color(0.08, 0.06, 0.04, 0.85)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Se mueve en _process: sin interpolar entre ticks de física.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group(&"floating_origin")


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFETIME:
		queue_free()
		return
	var s := _t / LIFETIME
	global_position += _up * (RISE * 2.0 * (1.0 - s) * delta / LIFETIME)
	transparency = clampf(s * 2.0 - 1.0, 0.0, 1.0)
