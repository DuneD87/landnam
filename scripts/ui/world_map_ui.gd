class_name WorldMapUI extends CanvasLayer

## Mapa mundial que se abre con M. Dibuja el equirect precomputado del planeta más cercano al
## jugador (ver PlanetWorldMap) con world_map.gdshader, más la posición y el rumbo del jugador.
##
## La UI no calcula nada del mundo: solo consulta el WorldMapData ya horneado, así lo que se ve
## aquí y lo que responden las consultas de gameplay es literalmente el mismo dato.

const SHADER_PATH := "res://shaders/ui/world_map.gdshader"

const MIN_ZOOM := 1.0
const MAX_ZOOM := 64.0
const ZOOM_STEP := 1.25

## Anchura de terreno (en metros) que se ve al abrir el mapa. A zoom 1 cabe el planeta entero, y en
## un planeta de radio 30000 eso son ~157 m por píxel: el marcador del jugador no se movería de
## forma perceptible andando. Se abre encuadrado a escala de andar y ya se aleja quien quiera.
const DEFAULT_VIEW_SPAN := 20000.0

## Área mínima (fracción de la superficie del planeta) para rotular un cuerpo de agua. Baja con el
## zoom: de lejos solo se nombran océanos y mares, de cerca también los lagos.
const LABEL_AREA_AT_MIN_ZOOM := 0.004
const LABEL_AREA_AT_MAX_ZOOM := 0.000004

var player: Node3D

var _panel: PanelContainer
var _title: Label
var _frame: Control
var _map_rect: ColorRect
var _overlay: _Overlay
var _status: Label
var _info_left: Label
var _info_right: Label

var _material: ShaderMaterial
var _world_map: PlanetWorldMap
var _connected_map: PlanetWorldMap
var _zoom: float = 1.0
var _offset: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _hover_uv: Vector2 = Vector2(-1.0, -1.0)
## El centrado se aplaza a _process: al abrir por primera vez el marco aún no tiene tamaño.
var _needs_center: bool = false
## Mientras esté activo la vista sigue al jugador. Se suelta al arrastrar y se recupera con el botón.
var _follow: bool = true
## Superpone las flechas de dirección del oleaje (ver el botón "Olas" y wave_arrow en el shader).
var _show_wave_arrows: bool = false
## Contrasta el mapa con el terreno real bajo el jugador (ver _diagnose).
var _debug_check: bool = false


## Control con el _draw delegado, para poder pintar los marcadores encima del mapa sin que les
## afecte el ShaderMaterial del TextureRect (el material tiñe todo el CanvasItem, marcas incluidas).
class _Overlay extends Control:
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func _ready() -> void:
	layer = 12
	_build_ui()
	visible = false


func setup(player_node: Node3D) -> void:
	player = player_node


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if player == null:
		return
	_resolve_world_map()
	visible = true
	_refresh_map_source()


func close() -> void:
	visible = false
	_dragging = false


func _process(_delta: float) -> void:
	if not visible:
		return
	if _needs_center and _frame.size.x > 0.0:
		_center_on_player()
		_needs_center = false
	elif _follow:
		_center_on_player()
	_layout_map()
	_update_info()
	_overlay.queue_redraw()


# --------------------------------------------------------------------------------------------
#  Construcción de la UI
# --------------------------------------------------------------------------------------------

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.82)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_style())
	margin.add_child(_panel)

	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(inner)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	inner.add_child(column)

	column.add_child(_build_header())

	_frame = Control.new()
	_frame.clip_contents = true
	_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_frame.gui_input.connect(_on_frame_input)
	_frame.mouse_exited.connect(func() -> void: _hover_uv = Vector2(-1.0, -1.0))
	column.add_child(_frame)

	# Un ColorRect basta: el mapa de alturas entra por uniform, no como textura del nodo (ver la
	# cabecera del shader). Solo aporta el rectángulo y sus UV de 0 a 1.
	_map_rect = ColorRect.new()
	_map_rect.color = Color(0.08, 0.10, 0.13)
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_map_rect)

	_overlay = _Overlay.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.painter = _paint_overlay
	_frame.add_child(_overlay)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_CENTER)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	_frame.add_child(_status)

	column.add_child(_build_footer())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	_title = Label.new()
	_title.text = "Mapa mundial"
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)

	var hint := Label.new()
	hint.text = "Rueda: zoom  ·  Arrastrar: desplazar  ·  M / Esc: cerrar"
	hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	header.add_child(hint)

	var center_button := Button.new()
	center_button.text = "Centrar en mí"
	center_button.pressed.connect(func() -> void: _follow = true)
	header.add_child(center_button)

	# Contraste con el terreno real: sirve para separar "el mapa está mal orientado" de "el mapa
	# es correcto pero a 92 m por téxel no representa lo que tienes delante".
	var debug_button := CheckBox.new()
	debug_button.text = "Contrastar"
	debug_button.toggled.connect(func(on: bool) -> void: _debug_check = on)
	header.add_child(debug_button)

	# Dibuja sobre el mapa hacia dónde viaja el oleaje. Separa "el campo de orilla está mal horneado"
	# de "el campo está bien y quien lo consume mal es el agua", que a ojo no se distingue.
	var waves_button := CheckBox.new()
	waves_button.text = "Olas"
	waves_button.toggled.connect(func(on: bool) -> void:
		_show_wave_arrows = on
		if _material != null:
			_material.set_shader_parameter("show_wave_arrows", on))
	header.add_child(waves_button)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	return header


func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)

	_info_left = Label.new()
	_info_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_info_left)

	_info_right = Label.new()
	_info_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_info_right.add_theme_color_override("font_color", Color(0.72, 0.82, 0.92))
	footer.add_child(_info_right)
	return footer


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.10, 0.96)
	style.border_color = Color(0.30, 0.34, 0.40)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style


# --------------------------------------------------------------------------------------------
#  Fuente de datos
# --------------------------------------------------------------------------------------------

## Busca el PlanetWorldMap del planeta más cercano al jugador y se suscribe a su horneado.
func _resolve_world_map() -> void:
	if player.has_method("update_nearest_planet"):
		player.update_nearest_planet()
	var loader = player.get("planet")
	var found: PlanetWorldMap = loader.get("world_map") if loader != null else null
	if found == _world_map:
		return

	_world_map = found
	_material = null
	_map_rect.material = null
	if _connected_map != null and is_instance_valid(_connected_map):
		_connected_map.map_ready.disconnect(_on_map_ready)
		_connected_map = null
	if _world_map != null:
		_world_map.map_ready.connect(_on_map_ready)
		_connected_map = _world_map
	_title.text = "Mapa mundial — %s" % (loader.name if loader != null else "?")


func _on_map_ready(_map: WorldMapData) -> void:
	if visible:
		_refresh_map_source()


## Deja el TextureRect y el material apuntando al mapa actual, o el mensaje de espera si aún no está.
func _refresh_map_source() -> void:
	if _world_map == null:
		_status.text = "Este cuerpo no tiene mapa."
		_status.visible = true
		return
	if not _world_map.is_ready():
		_status.text = "Generando el mapa del planeta…"
		_status.visible = true
		return
	_status.visible = false
	if _material != null:
		return

	var map := _world_map.map
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	if _material.shader == null:
		push_error("[world-map] no se pudo cargar %s" % SHADER_PATH)
		_status.text = "Falta el shader del mapa."
		_status.visible = true
		_material = null
		return
	_map_rect.material = _material
	_apply_map_params(map)
	_apply_planet_params(map)
	# Encuadre inicial a escala humana, no el planeta entero: ver DEFAULT_VIEW_SPAN.
	_zoom = clampf(TAU * map.radius / DEFAULT_VIEW_SPAN, MIN_ZOOM, MAX_ZOOM)
	_follow = true
	_needs_center = true


func _apply_map_params(map: WorldMapData) -> void:
	_material.set_shader_parameter("height_map", map.height_texture())
	_material.set_shader_parameter("height_texel", Vector2(1.0 / map.size.x, 1.0 / map.size.y))
	_material.set_shader_parameter("body_radius", map.radius)
	_material.set_shader_parameter("height_min", map.height_min)
	_material.set_shader_parameter("height_range", map.height_span)
	_material.set_shader_parameter("sea_height", map.sea_level_radius - map.radius)
	_material.set_shader_parameter("has_water", map.has_water)

	if map.has_water and not map.body_ids.is_empty():
		# El int32 de cada téxel se reinterpreta como RGBA8 sin recorrer el array; el shader lo
		# vuelve a montar byte a byte (por eso se muestrea con filter_nearest).
		var img := Image.create_from_data(
			map.size.x, map.size.y, false, Image.FORMAT_RGBA8, map.body_ids.to_byte_array())
		_material.set_shader_parameter("body_map", ImageTexture.create_from_image(img))
		_material.set_shader_parameter("has_body_map", true)

	if map.has_shore_field():
		_material.set_shader_parameter("shore_map", map.shore_texture())
		_material.set_shader_parameter("has_shore_map", true)
	_material.set_shader_parameter("show_wave_arrows", _show_wave_arrows)


## Escala la rampa hipsométrica al relieve real de este planeta y hereda del bioma polar la latitud
## a la que empieza el casquete de hielo. Es lo único que el mapa toma del planeta: la paleta es
## cartográfica a propósito, no la del terreno (ver la cabecera del shader).
func _apply_planet_params(map: WorldMapData) -> void:
	# Escalas sacadas del relieve REAL, no del rango del horneado: si no, toda la tierra cae en el
	# mismo tramo de la rampa y el mapa sale de un solo color.
	_material.set_shader_parameter("land_stops", map.land_height_stops())
	_material.set_shader_parameter("deep_depth", map.water_depth_percentile())

	var loader = player.get("planet")

	# Marco del oleaje y umbral de profundidad copiados del material del agua: si el mapa los
	# supusiera por su cuenta, las flechas apuntarían a un sitio y el agua se movería hacia otro.
	var ocean = loader.get("water_sphere") if loader != null else null
	var water_mat := (ocean.quadtree_material as ShaderMaterial) if ocean != null else null
	if water_mat != null:
		for pair in [["wave_pole", "swell_pole"], ["wave_direction", "swell_direction"],
				["shore_reach", "shore_reach"]]:
			# get_shader_parameter devuelve null para todo lo que el .tres no sobrescriba, que es
			# justo el caso de los que viven en el default del shader. Sin este relevo el mapa se
			# quedaría con su propia copia del valor y los dos se separarían en silencio.
			var value: Variant = water_mat.get_shader_parameter(pair[0])
			if value == null and water_mat.shader != null:
				value = RenderingServer.shader_get_parameter_default(
					water_mat.shader.get_rid(), pair[0])
			if value != null:
				_material.set_shader_parameter(pair[1], value)

	var planet = loader.get("planet") if loader != null else null
	if planet == null:
		return
	# biome_latitude_ranges va de -90 a 90, un corte por frontera de bioma. El primero es el borde
	# del casquete polar; el del bioma central marca hasta dónde llega la banda árida.
	var ranges: Array = planet.get("biome_latitude_ranges")
	if ranges == null or ranges.size() < 2:
		return
	_material.set_shader_parameter("snow_latitude", absf(float(ranges[1])))
	var middle := ranges.size() / 2 - 1
	if middle >= 1:
		_material.set_shader_parameter("arid_latitude", absf(float(ranges[middle])))


# --------------------------------------------------------------------------------------------
#  Vista: zoom, desplazamiento y colocación
# --------------------------------------------------------------------------------------------

## Tamaño del mapa dibujado. La base es el mayor rectángulo 2:1 que cabe en el marco.
func _map_size() -> Vector2:
	var frame := _frame.size
	var base := Vector2(minf(frame.x, frame.y * 2.0), minf(frame.x * 0.5, frame.y))
	return base * _zoom


func _layout_map() -> void:
	_clamp_offset()
	_map_rect.position = _offset
	_map_rect.size = _map_size()
	# El paso de las flechas se mide en píxeles de pantalla: sin esto crecerían con el zoom en vez
	# de aparecer más.
	if _material != null:
		_material.set_shader_parameter("map_size_px", _map_rect.size)


## Mantiene el mapa cubriendo el marco (o centrado si el zoom aún no lo llena).
func _clamp_offset() -> void:
	var frame := _frame.size
	var ms := _map_size()
	_offset.x = (frame.x - ms.x) * 0.5 if ms.x <= frame.x else clampf(_offset.x, frame.x - ms.x, 0.0)
	_offset.y = (frame.y - ms.y) * 0.5 if ms.y <= frame.y else clampf(_offset.y, frame.y - ms.y, 0.0)


## Coloca la vista con el jugador en el centro del marco.
func _center_on_player() -> void:
	var uv := _player_uv()
	if uv.x < 0.0:
		return
	var ms := _map_size()
	_offset = _frame.size * 0.5 - uv * ms
	_clamp_offset()


func _on_frame_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_apply_zoom(ZOOM_STEP, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_apply_zoom(1.0 / ZOOM_STEP, event.position)
			MOUSE_BUTTON_LEFT:
				_dragging = event.pressed
	elif event is InputEventMouseMotion:
		_hover_uv = _uv_at(event.position)
		if _dragging:
			# Arrastrar es tomar el control de la vista: deja de seguir al jugador hasta que se
			# pulse "Centrar en mí", o el desplazamiento se desharía al frame siguiente.
			_follow = false
			_offset += event.relative
			_clamp_offset()


## Zoom anclado al cursor: el punto del mapa bajo el ratón no se mueve.
func _apply_zoom(factor: float, pivot: Vector2) -> void:
	var previous := _zoom
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(previous, _zoom):
		return
	var ratio := _zoom / previous
	_offset = pivot - (pivot - _offset) * ratio
	_clamp_offset()


## Coordenada equirect bajo un punto del marco, o (-1,-1) si cae fuera del mapa.
func _uv_at(point: Vector2) -> Vector2:
	var ms := _map_size()
	if ms.x <= 0.0 or ms.y <= 0.0:
		return Vector2(-1.0, -1.0)
	var uv := (point - _offset) / ms
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1.0, -1.0)
	return uv


func _point_of_uv(uv: Vector2) -> Vector2:
	return _offset + uv * _map_size()


func _player_uv() -> Vector2:
	if _world_map == null or player == null:
		return Vector2(-1.0, -1.0)
	return _world_map.get_uv(player.global_position)


# --------------------------------------------------------------------------------------------
#  Marcadores e información
# --------------------------------------------------------------------------------------------

func _paint_overlay(canvas: Control) -> void:
	if _world_map == null or not _world_map.is_ready():
		return
	_draw_body_labels(canvas)
	_draw_player_marker(canvas)


## Rotula los cuerpos de agua grandes; el umbral baja con el zoom para no amontonar nombres.
func _draw_body_labels(canvas: Control) -> void:
	var font := canvas.get_theme_default_font()
	if font == null:
		return
	var t := (_zoom - MIN_ZOOM) / (MAX_ZOOM - MIN_ZOOM)
	var threshold: float = lerpf(
		log(LABEL_AREA_AT_MIN_ZOOM), log(LABEL_AREA_AT_MAX_ZOOM), t)
	threshold = exp(threshold)

	for body in _world_map.map.bodies:
		if body.area_fraction < threshold:
			continue
		var point := _point_of_uv(WorldMapData.dir_to_uv(body.center))
		if not Rect2(Vector2.ZERO, canvas.size).grow(80.0).has_point(point):
			continue
		var text: String = body.name
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		canvas.draw_string(font, point - Vector2(width * 0.5, 0.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.97, 1.0, 0.85))


## Punto del jugador más una punta de flecha con su rumbo, orientada en el plano del mapa.
func _draw_player_marker(canvas: Control) -> void:
	var uv := _player_uv()
	if uv.x < 0.0:
		return
	var point := _point_of_uv(uv)
	canvas.draw_circle(point, 8.0, Color(0.0, 0.0, 0.0, 0.55))
	canvas.draw_circle(point, 5.0, Color(1.0, 0.85, 0.25))

	var angle := _heading_on_map(uv)
	if is_nan(angle):
		return
	var tip := point + Vector2(cos(angle), sin(angle)) * 17.0
	var side := angle + PI * 0.5
	var base := point + Vector2(cos(angle), sin(angle)) * 6.0
	var wing := Vector2(cos(side), sin(side)) * 5.0
	canvas.draw_colored_polygon(
		PackedVector2Array([tip, base + wing, base - wing]), Color(1.0, 0.85, 0.25))


## Rumbo del jugador expresado como ángulo en pantalla, o NAN si no hay rumbo que dibujar. Las dos
## tangentes del equirect en ese punto son los ejes del mapa: la de u creciente apunta a la derecha
## y la de v creciente hacia abajo, así que basta proyectar el frente sobre ellas. Derivadas de
## WorldMapData.uv_to_dir.
func _heading_on_map(uv: Vector2) -> float:
	var theta := uv.y * PI
	var lon := (uv.x - 0.5) * TAU
	var right := Vector3(-sin(lon), 0.0, -cos(lon))
	var down := Vector3(cos(theta) * cos(lon), -sin(theta), -cos(theta) * sin(lon))
	var forward := _player_forward()
	var flat := Vector2(forward.dot(right), forward.dot(down))
	# Mirando a plomo (arriba o abajo) no hay rumbo en el plano del mapa: la flecha giraría al
	# azar con el ruido de la proyección, así que mejor no dibujarla.
	if flat.length() < 0.08:
		return NAN
	return atan2(flat.y, flat.x)


## Hacia dónde mira el jugador. En vuelo libre el FreeFlightController rota LA CÁMARA y deja el
## cuerpo quieto, así que leer la base del cuerpo daba un rumbo congelado; a pie manda el cuerpo,
## que es el que gira hacia donde se anda (ver PlanetaryBody.rotate_toward_direction, +Z al frente).
func _player_forward() -> Vector3:
	var camera = player.get("camera")
	if player.get("free_flight_enabled") == true and camera is Camera3D:
		return -(camera as Camera3D).global_basis.z
	return player.global_basis.z


func _update_info() -> void:
	if _world_map == null or not _world_map.is_ready():
		_info_left.text = ""
		_info_right.text = ""
		return

	var pos: Vector3 = player.global_position
	var latlon := _world_map.get_latlon(pos)
	_info_left.text = "%s   ·   Altitud %.0f m   ·   %s   ·   1 px ≈ %.0f m" % [
		WorldMapData.format_latlon(latlon),
		_world_map.get_altitude(pos),
		_describe_water(_world_map.get_water_body_at(pos), _world_map.get_water_depth_at(pos)),
		TAU * _world_map.map.radius / maxf(_map_size().x, 1.0),
	]
	if _debug_check:
		_info_left.text += "\n" + _diagnose(pos)

	if _hover_uv.x < 0.0:
		_info_right.text = ""
		_material.set_shader_parameter("highlight_body", -1)
		return

	var map := _world_map.map
	var dir := WorldMapData.uv_to_dir(_hover_uv)
	var body := map.water_body_at_dir(dir)
	# Resaltar solo lo que se distingue de un vistazo. El océano cubre tres cuartas partes del
	# planeta: teñirlo al pasar el ratón por encima es un fogonazo en medio mapa, no una ayuda.
	var highlight := -1
	if not body.is_empty() and int(body.type) >= WorldMapData.WaterType.LAKE:
		highlight = int(body.id)
	_material.set_shader_parameter("highlight_body", highlight)
	_info_right.text = "%s   ·   %s" % [
		WorldMapData.format_latlon(WorldMapData.dir_to_latlon(dir)),
		_describe_hover(body, map.depth_at_dir(dir), map.height_at_dir(dir)),
	]


## Contrasta el mapa con el terreno real bajo el jugador: sondea la vertical con un rayo de física
## y compara la altura y el veredicto tierra/agua. Separa "el mapa está mal" de "el mapa está bien
## pero un téxel son ~92 m y no puede enseñar lo que tienes delante".
func _diagnose(pos: Vector3) -> String:
	var center := _world_map.get_planet_center()
	var dir := (pos - center).normalized()
	var map_radius := _world_map.get_surface_radius(pos)
	var own_radius := pos.distance_to(center)
	# El terreno es una malla sin caras traseras: hay que sondear siempre de arriba hacia abajo.
	var query := PhysicsRayQueryParameters3D.create(
		center + dir * (maxf(own_radius, map_radius) + 400.0),
		center + dir * (minf(own_radius, map_radius) - 800.0))
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "contraste: el rayo no encontró terreno (¿colisión aún sin hornear?)"

	var real_radius: float = (hit.position as Vector3).distance_to(center)
	var sea := _world_map.map.sea_level_radius
	return "contraste: mapa %+.0f m / real %+.0f m (desfase %+.0f m)   ·   mapa dice %s, real %s" % [
		map_radius - sea, real_radius - sea, map_radius - real_radius,
		"AGUA" if _world_map.is_water_at(pos) else "TIERRA",
		"AGUA" if real_radius < sea else "TIERRA"]


func _describe_water(body: Dictionary, depth: float) -> String:
	if body.is_empty():
		return "En tierra firme"
	return "%s (%.1f m de fondo)" % [body.name, maxf(depth, 0.0)]


func _describe_hover(body: Dictionary, depth: float, height: float) -> String:
	if body.is_empty():
		return "Tierra, %.0f m" % (height - (_world_map.map.sea_level_radius - _world_map.map.radius))
	return "%s · %.1f km² · fondo %.0f m (máx %.0f m)" % [
		body.name, body.area / 1_000_000.0, maxf(depth, 0.0), body.max_depth]
