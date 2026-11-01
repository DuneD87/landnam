class_name Minimap extends CanvasLayer

## Minimapa, arriba a la derecha: el mapa del planeta alrededor del jugador, con él en el centro y el
## norte arriba. Abajo, en una cartela sobre el aro, la estación; a la izquierda, en una cajita
## propia, la hora solar del sitio y la altura sobre el nivel del mar.
##
## Pinta el mismo mapa horneado que la M (PlanetWorldMap) con el mismo shader en vista local
## (local_view en world_map.gdshader): un trozo del plano tangente bajo el jugador, sin el
## estiramiento del equirect. Encima van los marcadores del mapa que caen dentro y el rumbo.
##
## Va en una talla como la de la barra rápida (tools/ui/bake_minimap_frame.py): un engaste con una
## banda de runas, el medallón del norte con su copa de hojas, la cartela de la estación y la cajita
## de la hora y la altura, fundida con el engaste. Aquí se pone encima lo que cambia: el mapa con su
## aro y los textos.

## Metros de terreno de lado a lado. El mapa tiene ~92 m por téxel: más cerca solo se ve borroso.
const SPAN := 3000.0
## La talla: píxeles de la imagen por píxel de la UI a 1440 px de alto y, en píxeles base desde el
## centro del mapa, el lienzo, lo que ocupa de verdad, el radio del mapa, el medallón del norte, el
## sitio del texto de la cartela, el hueco de la cajita y las líneas de base de sus dos filas (entre
## ellas va el filete horneado). Los imprime el script al hornear; tienen que coincidir.
const FRAME := preload("res://textures/ui/minimap_frame.png")
const ART_SCALE := 2.0
const ART_RECT := Rect2(-240, -172, 390, 328)
const BOUNDS := Rect2(-231.5, -162.5, 365.5, 303)
const MAP_RADIUS := 108.0
const NORTH_AT := Vector2(0, -119.75)
const SEASON_RECT := Rect2(-75, 109, 150, 30)
const STATS_PANEL := Rect2(-225, -34, 97.5, 68)
const TIME_BASELINE := -7.0
const ALTITUDE_BASELINE := 25.0
## Donde acaban la hora y la altura, arrimadas al aro a unos píxeles de la banda de runas.
const TEXT_RIGHT := -133.0
## Hueco entre la talla y los bordes de arriba y de la derecha de la pantalla, en píxeles base.
const MARGIN := 22.0
const MARKER_RADIUS := 13.0

var player: PlayerController

var _root: Control
var _frame: TextureRect
var _map_rect: ColorRect
var _overlay: Control
var _material: ShaderMaterial
## El mapa para el que se hizo _material: si se vuelve a hornear o cambia de planeta, se rehace.
var _material_map: WorldMapData
var _world_map: PlanetWorldMap
var _ui_scale := 0.0
var _title_font: Font
## Cinzel sin el espaciado de los títulos: así «Primavera · 8/8» cabe en la cartela sin achicarse.
var _season_font: FontVariation
## Centro del mapa dentro de _root.
var _map_centre := Vector2.ZERO
## Base del plano tangente bajo el jugador (ver _update_view).
var _center := Vector3.UP
var _east := Vector3.RIGHT
var _north := Vector3.BACK


func setup(player_node: PlayerController) -> void:
	player = player_node


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_frame = TextureRect.new()
	_frame.texture = FRAME
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_root.add_child(_frame)

	# Un ColorRect basta, como en el mapa grande: el shader recibe el mapa por uniform.
	_map_rect = ColorRect.new()
	_map_rect.color = Color.TRANSPARENT
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_map_rect)

	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_root.add_child(_overlay)
	# El primer dibujo llega antes del primer _process: las fuentes y medidas ya tienen que estar.
	_layout()


func _process(_delta: float) -> void:
	visible = player != null and _is_shown()
	if not visible:
		return
	_layout()
	_refresh_material()
	_update_view()
	_overlay.queue_redraw()


## Fuera de partida, con el menú de pausa, el mapa grande o las pantallas que oscurecen el mundo
## (personaje y fabricar, que además ocupan la columna de la derecha) no sale.
func _is_shown() -> bool:
	if GameManager.current_state != GameManager.State.PLAYING:
		return false
	if player.main_menu != null and player.main_menu.visible:
		return false
	if player.world_map_ui != null and player.world_map_ui.visible:
		return false
	var inventory := player.inventory_ui
	return inventory == null or not inventory.visible or inventory.view == InventoryUI.View.INVENTORY


## Borde de abajo de la talla en pantalla, para lo que va debajo (la rosa de navegación). 0 si no
## se ve.
func bottom() -> float:
	if not visible or _ui_scale <= 0.0:
		return 0.0
	return _root.position.y + _map_centre.y + BOUNDS.end.y * _ui_scale


## La talla, arrimada a MARGIN de los bordes de arriba y de la derecha por lo que ocupa de verdad, y
## el mapa en su engaste.
func _layout() -> void:
	var viewport := get_viewport()
	var ui_scale := maxf(0.625, GameTheme.scale_for(viewport))
	if ui_scale != _ui_scale:
		_ui_scale = ui_scale
		_title_font = GameTheme.title_font(ui_scale, 700)
		_season_font = GameTheme.title_font(ui_scale, 700)
		_season_font.spacing_glyph = 0
	var centre := Vector2(viewport.get_visible_rect().size.x - (MARGIN + BOUNDS.end.x) * ui_scale,
		(MARGIN - BOUNDS.position.y) * ui_scale).round()
	_root.position = centre + ART_RECT.position * ui_scale
	_root.size = ART_RECT.size * ui_scale
	_map_centre = centre - _root.position
	_frame.size = _root.size
	var radius := MAP_RADIUS * ui_scale
	_map_rect.position = _map_centre - Vector2(radius, radius)
	_map_rect.size = Vector2(radius, radius) * 2.0
	_overlay.size = _root.size


# --------------------------------------------------------------------------------------------
#  Mapa
# --------------------------------------------------------------------------------------------

func _refresh_material() -> void:
	var loader = player.planet
	_world_map = loader.get("world_map") if loader != null else null
	var map: WorldMapData = _world_map.map if _world_map != null and _world_map.is_ready() else null
	if map == _material_map:
		return
	_material_map = map
	_material = WorldMapUI.make_material(map, loader) if map != null else null
	if _material != null:
		_material.set_shader_parameter("local_view", true)
		_material.set_shader_parameter("round_mask", true)
		_material.set_shader_parameter("view_span", Vector2(SPAN, SPAN))
		# Una línea de la retícula de 15° cruza la vista de tarde en tarde y no dice nada.
		_material.set_shader_parameter("grid_strength", 0.0)
	_map_rect.material = _material
	_map_rect.visible = _material != null


## Lleva el plano tangente de la vista a la vertical del jugador: este y norte del sitio. En un polo
## no hay norte y vale cualquier eje.
func _update_view() -> void:
	if _world_map == null:
		return
	_center = _world_map.direction_of(player.global_position)
	var north := Vector3.UP - _center * _center.y
	if north.length_squared() < 0.000001:
		north = Vector3.RIGHT - _center * _center.x
	_north = north.normalized()
	_east = _north.cross(_center)
	if _material != null:
		_material.set_shader_parameter("view_center", _center)
		_material.set_shader_parameter("view_east", _east)
		_material.set_shader_parameter("view_north", _north)


## Punto de la vista (relativo a su centro, en píxeles) de una dirección desde el centro del
## planeta: la misma proyección gnomónica que el shader. Null si queda en el otro hemisferio.
func _project(dir: Vector3, radius: float, pixels_per_meter: float) -> Variant:
	var facing := dir.dot(_center)
	if facing <= 0.0:
		return null
	var on_plane := dir / facing - _center
	return Vector2(on_plane.dot(_east), -on_plane.dot(_north)) * radius * pixels_per_meter


# --------------------------------------------------------------------------------------------
#  Dibujo
# --------------------------------------------------------------------------------------------

func _draw_overlay() -> void:
	if player == null:
		return
	var s := _ui_scale
	var centre := _map_centre
	var radius := MAP_RADIUS * s
	if _material == null:
		# Sin mapa se ve el hueco del engaste, que ya viene oscuro en la talla.
		if _world_map != null:
			_centered_text(centre + Vector2(0.0, 6.0 * s), tr("MINIMAP_GENERATING"),
				GameTheme.body_font(), maxi(12, roundi(18.0 * s)), GameTheme.MUTED)
	else:
		_draw_markers(centre, radius)
		_draw_player(centre)
	_draw_ring(centre, radius)
	var north := centre + NORTH_AT * s
	var font_size := maxi(10, roundi(15.0 * s))
	_centered_text(north + Vector2(0.0, font_size * 0.36), tr("COMPASS_N"), _title_font, font_size,
		GameTheme.BRONZE)
	_draw_texts(centre)


## Aro de bronce como el de las orbes, con un remache al este, al sur y al oeste; el norte lo marca
## su medallón en la talla.
func _draw_ring(centre: Vector2, radius: float) -> void:
	var s := _ui_scale
	_overlay.draw_arc(centre, radius - 3.5 * s, 0.0, TAU, 128, GameTheme.BRONZE_DARK.darkened(0.35), 7.0 * s, true)
	_overlay.draw_arc(centre, radius - 0.75 * s, 0.0, TAU, 128, GameTheme.BRONZE, 1.5 * s, true)
	_overlay.draw_arc(centre, radius - 7.0 * s, 0.0, TAU, 128, Color(GameTheme.BRONZE, 0.45), 1.0 * s, true)
	for angle in [0.0, PI * 0.5, PI]:
		var at := centre + Vector2.from_angle(angle) * (radius - 3.5 * s)
		_overlay.draw_colored_polygon(SagaFrame.diamond(at, 5.0 * s), GameTheme.BRONZE)
		_overlay.draw_colored_polygon(SagaFrame.diamond(at, 2.2 * s), GameTheme.INK)


## El jugador: una punta de flecha con su rumbo, o un rombo si mira a plomo y no hay rumbo.
func _draw_player(centre: Vector2) -> void:
	var s := _ui_scale
	var forward := WorldMapUI.player_forward(player)
	var flat := Vector2(forward.dot(_east), -forward.dot(_north))
	var shape: PackedVector2Array
	if flat.length() < 0.08:
		shape = SagaFrame.diamond(centre, 6.0 * s)
	else:
		var ahead := flat.normalized()
		shape = PackedVector2Array([centre + ahead * 12.0 * s, centre + ahead.rotated(2.45) * 9.0 * s,
			centre - ahead * 3.5 * s, centre + ahead.rotated(-2.45) * 9.0 * s])
	var outline := shape.duplicate()
	outline.append(shape[0])
	_overlay.draw_polyline(outline, GameTheme.INK, 3.0 * s, true)
	_overlay.draw_colored_polygon(shape, GameTheme.BONE)


## Los marcadores del mapa que caen dentro del aro, como en el mapa grande pero más pequeños.
func _draw_markers(centre: Vector2, radius: float) -> void:
	var loader = player.planet
	var planet_id := str(loader.get("entity_id")) if loader != null else ""
	if planet_id.is_empty() or player.world_map_ui == null:
		return
	var s := _ui_scale
	var marker_radius := MARKER_RADIUS * s
	var icon_size := Vector2.ONE * 20.0 * s
	var pixels_per_meter := radius * 2.0 / SPAN
	for marker in player.world_map_ui.markers.for_planet(planet_id):
		var offset: Variant = _project(WorldMapData.uv_to_dir(marker.uv), _material_map.radius,
			pixels_per_meter)
		if offset == null or (offset as Vector2).length() > radius - 7.0 * s - marker_radius:
			continue
		var point := centre + (offset as Vector2)
		_overlay.draw_circle(point, marker_radius, Color(0.025, 0.035, 0.045, 0.92))
		_overlay.draw_arc(point, marker_radius, 0.0, TAU, 32, GameTheme.BRONZE_LINE, 1.5 * s, true)
		_overlay.draw_texture_rect(MapMarkerEditor.ICON_TEXTURES[marker.icon],
			Rect2(point - icon_size * 0.5, icon_size), false)


## La estación en su cartela, bajo el mapa, y en la cajita de la izquierda la hora (con el sol o la
## luna) encima del filete y la altura debajo.
func _draw_texts(centre: Vector2) -> void:
	var s := _ui_scale
	var planet := _planet()
	if planet == null or not is_instance_valid(planet.voxel_terrain):
		return
	var local := player.global_position - planet.voxel_terrain.global_position

	var season := _season_text(local)
	if not season.is_empty():
		# Si en otro idioma no cabe en la cartela, se achica.
		var room := SEASON_RECT.size.x * s
		var season_size := maxi(13, roundi(18.0 * s))
		var season_width := _season_font.get_string_size(season, HORIZONTAL_ALIGNMENT_LEFT, -1, season_size).x
		if season_width > room:
			season_size = maxi(8, floori(season_size * room / season_width))
		var middle := centre + SEASON_RECT.get_center() * s
		_centered_text(middle + Vector2(0.0, season_size * 0.36), season, _season_font, season_size,
			GameTheme.BRONZE)

	var hour := Seasons.solar_hour(local)
	var time := "%02d:%02d" % [floori(hour), floori(fmod(hour, 1.0) * 60.0)] if not is_nan(hour) else ""
	var sea := planet.radius - planet.water_radius if planet.has_water else planet.radius
	var altitude := tr("MINIMAP_ALTITUDE") % roundi(local.length() - sea)
	# Las cifras, contra el aro; los iconos (dibujados para 26 px, unos 20 de ancho), en columna a 5 px
	# de la más ancha de las dos. La cajita es la justa para «00:00» o «888 m»: si una altura de cuatro
	# cifras no cabe, la letra de las dos filas se achica.
	var font := GameTheme.medium_font()
	var font_size := maxi(16, roundi(26.0 * s))
	var glyph_scale := font_size / 26.0
	var text_right := centre.x + TEXT_RIGHT * s
	var room := (TEXT_RIGHT - STATS_PANEL.position.x) * s - 29.0 * glyph_scale
	var widest := maxf(_text_width(time, font, font_size), _text_width(altitude, font, font_size))
	if widest > room:
		font_size = maxi(12, floori(font_size * room / widest))
		widest = maxf(_text_width(time, font, font_size), _text_width(altitude, font, font_size))
	var glyph_x := text_right - widest - 15.0 * glyph_scale
	if not time.is_empty():
		var baseline := centre.y + TIME_BASELINE * s
		var glyph := Vector2(glyph_x, baseline - font_size * 0.33)
		if Seasons.sun_elevation(local) > 0.0:
			_draw_sun(glyph, glyph_scale)
		else:
			_draw_moon(glyph, glyph_scale)
		_right_text(text_right, baseline, time, font, font_size)
	var baseline := centre.y + ALTITUDE_BASELINE * s
	_draw_mountain(Vector2(glyph_x, baseline - font_size * 0.33), glyph_scale)
	_right_text(text_right, baseline, altitude, font, font_size)


## «Verano · 3/8» (día 3 de 8) en ese sitio (el sur va medio año por detrás). Sin calendario, nada.
func _season_text(local: Vector3) -> String:
	var calendar := WorldTime.calendar()
	if not Seasons.enabled or calendar == null:
		return ""
	var phase := Seasons.local_phase(local, Seasons.year_phase)
	var days := maxi(roundi(float(calendar.days_per_season)), 1)
	var day := mini(floori(fposmod(phase * 4.0, 1.0) * days) + 1, days)
	var key := "SEASON_" + String(Seasons.KEYS[Seasons.season_index(phase)]).to_upper()
	return tr("MINIMAP_SEASON") % [tr(key).capitalize(), day, days]


func _draw_sun(at: Vector2, s: float) -> void:
	_overlay.draw_circle(at, 4.5 * s, GameTheme.BRONZE)
	for i in 8:
		var ray := Vector2.from_angle(i * TAU / 8.0)
		_overlay.draw_line(at + ray * 6.5 * s, at + ray * 9.0 * s, GameTheme.BRONZE, 1.5 * s, true)


## Luna creciente: el disco menos el mismo disco corrido a la derecha.
func _draw_moon(at: Vector2, s: float) -> void:
	var r := 7.5 * s
	var shift := 4.5 * s
	var cut := atan2(sqrt(r * r - shift * shift * 0.25), shift * 0.5)
	var points := PackedVector2Array()
	for i in 13:
		points.append(at + Vector2.from_angle(lerpf(cut, TAU - cut, i / 12.0)) * r)
	# Sin los extremos: son las puntas, que ya están en el arco de fuera.
	for i in range(1, 12):
		points.append(at + Vector2(shift, 0.0) + Vector2.from_angle(lerpf(PI + cut, PI - cut, i / 12.0)) * r)
	_overlay.draw_colored_polygon(points, GameTheme.FROST)


func _draw_mountain(at: Vector2, s: float) -> void:
	var points := PackedVector2Array([Vector2(-10, 7), Vector2(-4, -3), Vector2(-1, 1), Vector2(4, -8),
		Vector2(10, 7)])
	for i in points.size():
		points[i] = at + points[i] * s
	_overlay.draw_colored_polygon(points, GameTheme.MUTED)


func _right_text(right: float, baseline: float, text: String, font: Font, font_size: int) -> void:
	_overlay.draw_string(font, Vector2(right - _text_width(text, font, font_size), baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, GameTheme.BONE)


func _text_width(text: String, font: Font, font_size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _centered_text(at: Vector2, text: String, font: Font, font_size: int, color: Color) -> void:
	_overlay.draw_string(font, Vector2(at.x - _text_width(text, font, font_size) * 0.5, at.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _planet() -> Planet:
	var loader = player.planet
	return loader.get("planet") if loader != null else null
