extends Node3D

## Marcadores: JSON, planetas, edición/cancelación, clic frente a arrastre y guardado real.
## godot --headless --path . res://tests/ui/test_map_markers.tscn
## Con render: -- --capture guarda la ficha y el selector en 720p y 1440p en build/ui/.

class MapHost extends Node3D:
	var entity_id := "planet_test"
	var gravity_strength := 9.8
	var world_map: PlanetWorldMap
	var water_sphere: OceanSystem
	var planet: Planet


class MapPlayer extends Node3D:
	var planet: MapHost
	var camera: Camera3D
	var free_flight_enabled := false


class GroundedPlayer extends PlayerController:
	func is_ground_ready() -> bool:
		return true


var failures := 0
var checks := 0
var _ui: WorldMapUI


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func _run() -> void:
	_check_data()
	_check_last_death()
	await _check_ui()
	await _check_player_save()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()
	_ui.queue_free()
	await get_tree().process_frame
	print("MAP MARKERS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _check_data() -> void:
	var markers := MapMarkers.new()
	for icon in MapMarkers.ICONS:
		check(markers.add("earth", Vector2(0.25, 0.75), icon, "  Casa ártica  ") > 0,
			"se admite el icono " + icon)
	var moon := markers.add("moon", Vector2(1.0, 0.0), "flag")
	check(markers.for_planet("earth").size() == MapMarkers.ICONS.size() and markers.for_planet("moon").size() == 1,
		"cada planeta tiene sus propios marcadores, también en el borde del mapa")
	var encoded := JSON.stringify(markers.save_data())
	var restored := MapMarkers.new()
	restored.load_data(JSON.parse_string(encoded))
	check(JSON.stringify(restored.save_data()) == encoded,
		"el paso por JSON conserva id, planeta, UV, nombre e icono")
	check(restored.get_marker(1).name == "Casa ártica", "se conservan acentos y se limpian espacios")
	restored.load_data(JSON.parse_string(encoded))
	check(restored.for_planet("earth").size() == MapMarkers.ICONS.size(), "restaurar dos veces no duplica marcadores")
	check(restored.update(moon, "cave", "Cráter") and restored.get_marker(moon).icon == "cave",
		"se cambia el nombre y el icono conservando la posición")
	check(restored.add("moon", Vector2(0.5, 1.0), "home") > moon,
		"un marcador nuevo tras cargar tiene otro id")
	check(restored.remove(moon) and restored.get_marker(moon).is_empty(), "se elimina solo el id elegido")
	check(markers.add("", Vector2.ZERO, "home") == 0
		and markers.add("earth", Vector2(NAN, 0.0), "home") == 0
		and markers.add("earth", Vector2(0.5, 1.1), "home") == 0
		and markers.add("earth", Vector2.ZERO, "missing") == 0,
		"no se crean marcadores sin planeta, fuera del mapa o con iconos desconocidos")
	var bad: Array = [null, 4, {}, {"id": "bad"},
		{"id": 1, "planet_id": "earth", "uv": {"u": "bad", "v": 0}},
		{"id": 2, "planet_id": "earth", "uv": {"u": -0.1, "v": 0}},
		{"id": 3, "planet_id": "earth", "uv": {"u": 0.2, "v": 0.4}, "icon": "old_icon"},
		{"id": 3, "planet_id": "earth", "uv": {"u": 0.5, "v": 0.5}}]
	restored.load_data(bad)
	check(restored.for_planet("earth").size() == 1 and restored.get_marker(3).icon == "flag",
		"se ignoran datos dañados e ids repetidos y se sustituye un icono antiguo por la bandera")
	restored.load_data(null)
	check(restored.save_data().is_empty(), "una partida antigua limpia los marcadores de la sesión anterior")


func _check_last_death() -> void:
	var markers := MapMarkers.new()
	var home := markers.add("earth", Vector2(0.2, 0.3), "home", "Refugio")
	var manual := markers.add("earth", Vector2(0.4, 0.5), "tombstone", "Tumba antigua")
	var death := markers.record_death("earth", Vector2(0.6, 0.7))
	check(death > 0 and markers.get_marker(death).icon == "tombstone" \
		and markers.get_marker(death).get("kind") == MapMarkers.LAST_DEATH,
		"la última muerte usa un marcador de tumba identificado aparte de las marcas personales")
	check(markers.record_death("moon", Vector2(0.8, 0.9)) == death \
		and markers.for_planet("moon").size() == 1 \
		and markers.get_marker(death).uv.is_equal_approx(Vector2(0.8, 0.9)) \
		and markers.for_planet("earth").size() == 2,
		"otra muerte mueve la misma tumba incluso al cambiar de planeta")
	check(not markers.get_marker(home).is_empty() and markers.get_marker(manual).name == "Tumba antigua",
		"la muerte no toca las marcas personales ni las tumbas puestas a mano")
	var saved := JSON.stringify(markers.save_data())
	check(markers.record_death("", Vector2.ZERO) == 0 \
		and markers.record_death("earth", Vector2(NAN, 1.0)) == 0 \
		and JSON.stringify(markers.save_data()) == saved,
		"una muerte sin posición válida conserva la última ubicación conocida")
	markers.load_data(JSON.parse_string(saved))
	check(JSON.stringify(markers.save_data()) == saved \
		and markers.record_death("earth", Vector2(0.1, 0.2)) == death \
		and markers.save_data().size() == 3,
		"guardar y cargar conserva la identidad de la muerte para actualizarla sin duplicados")
	markers.remove(death)
	check(markers.record_death("earth", Vector2(0.3, 0.4)) > death,
		"borrar la tumba permite crear la de la siguiente muerte")
	var duplicates := markers.save_data()
	var extra: Dictionary = duplicates[-1].duplicate(true)
	extra.id += 10
	duplicates.append(extra)
	markers.load_data(duplicates)
	check(markers.save_data().size() == 3 and markers.get_marker(extra.id).get("kind") == MapMarkers.LAST_DEATH,
		"cargar datos con dos últimas muertes conserva una sola")


func _button(index: MouseButton, pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = point
	_ui._on_frame_input(event)


func _viewport_button(index: MouseButton, pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)


func _check_ui() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	var host := MapHost.new()
	host.name = "Tierra"
	add_child(host)
	host.world_map = PlanetWorldMap.new()
	host.add_child(host.world_map)
	var map := WorldMapData.new()
	map.size = Vector2i(64, 32)
	map.radius = 30000.0
	map.sea_level_radius = 30000.0
	map.height_span = 1000.0
	map.heights.resize(64 * 32)
	for y in 32:
		for x in 64:
			map.heights[y * 64 + x] = 0.5 + 0.3 * sin(x * 0.17) * cos(y * 0.24)
	host.world_map.map = map
	var map_player := MapPlayer.new()
	map_player.planet = host
	add_child(map_player)
	map_player.position = WorldMapData.uv_to_dir(Vector2(0.5, 0.5)) * map.radius
	_ui = WorldMapUI.new()
	_ui.setup(map_player)
	add_child(_ui)
	_ui.set_process(false)
	_ui.open()
	await get_tree().process_frame
	await get_tree().process_frame
	_ui._zoom = 1.0
	_ui._follow = false
	_ui._needs_center = false
	_ui._layout_map()
	var uv := Vector2(0.35, 0.4)
	var point := _ui._point_of_uv(uv)
	_button(MOUSE_BUTTON_RIGHT, true, point)
	check(_ui._marker_editor.visible and _ui.markers.save_data().is_empty(),
		"clic derecho abre el alta sin guardar hasta aceptar")
	_ui._marker_editor._icon_choice.select(MapMarkers.ICONS.find("home"))
	_ui._marker_editor._name_edit.text = "Refugio"
	_ui._marker_editor._submit()
	var entry: Dictionary = _ui.markers.for_planet(host.entity_id)[0]
	check(entry.icon == "home" and entry.name == "Refugio" and entry.uv.is_equal_approx(uv),
		"aceptar crea el nombre y el icono en el punto del clic")
	_button(MOUSE_BUTTON_LEFT, true, point)
	_button(MOUSE_BUTTON_LEFT, false, point)
	check(_ui._editing_marker == entry.id and _ui._marker_editor.visible,
		"clic izquierdo sobre el marcador abre su ficha")
	_ui._marker_editor._name_edit.text = "Descartado"
	_ui.cancel_marker_edit()
	check(_ui.markers.get_marker(entry.id).name == "Refugio"
		and get_viewport().gui_get_focus_owner() != _ui._marker_editor._name_edit,
		"cancelar conserva el nombre anterior y libera el foco del campo")
	_button(MOUSE_BUTTON_RIGHT, true, point)
	_ui._marker_editor._icon_choice.select(MapMarkers.ICONS.find("cave"))
	_ui._marker_editor._name_edit.text = "Cueva"
	_ui._marker_editor._submit()
	check(_ui.markers.get_marker(entry.id).icon == "cave"
		and _ui.markers.for_planet(host.entity_id).size() == 1,
		"clic derecho sobre un marcador lo edita sin crear otro encima")
	_ui._zoom = 2.0
	_ui._layout_map()
	point = _ui._point_of_uv(uv)
	check(_ui._marker_at(point + Vector2(12, 0)) == entry.id,
		"el marcador sigue siendo seleccionable después del zoom")
	_ui._follow = true
	_button(MOUSE_BUTTON_LEFT, true, point)
	var motion := InputEventMouseMotion.new()
	motion.position = point + Vector2(25, 0)
	motion.relative = Vector2(25, 0)
	_ui._on_frame_input(motion)
	_button(MOUSE_BUTTON_LEFT, false, motion.position)
	check(not _ui._marker_editor.visible and not _ui._follow,
		"arrastrar desde un marcador desplaza el mapa sin abrir su ficha")
	_ui._mark_here_button.pressed.emit()
	check(_ui._pending_marker_uv.is_equal_approx(Vector2(0.5, 0.5)),
		"Marcar mi posición usa la posición del jugador")
	_ui.cancel_marker_edit()
	# Un desplazamiento compartido de planeta y jugador no cambia sus UV.
	var center := Node3D.new()
	host.add_child(center)
	host.world_map._center_node = center
	var before := _ui._player_uv()
	center.position += Vector3(5000, 3000, -2000)
	map_player.position += center.position
	check(_ui._player_uv().is_equal_approx(before) and _ui.markers.get_marker(entry.id).uv.is_equal_approx(uv),
		"el origen flotante no mueve el marcador sobre el planeta")
	_ui._edit_marker_at(uv, entry.id)
	_ui._marker_editor.deleted.emit()
	check(_ui.markers.save_data().is_empty(), "borrar desde la ficha elimina el marcador")
	_ui._edit_marker_at(uv)
	_ui.close()
	check(not _ui._marker_editor.visible and not _ui.visible, "cerrar el mapa cancela cualquier ficha abierta")
	# Otro planeta no hereda la ficha ni los marcadores del anterior.
	_ui.markers.add(host.entity_id, uv, "home", "Refugio")
	host.entity_id = "other_planet"
	_ui.open()
	check(_ui.markers.for_planet(_ui._planet_id).is_empty(), "cambiar de planeta muestra solo sus marcadores")
	host.entity_id = "planet_test"
	_ui.open()
	_ui._zoom = 1.0
	_ui._layout_map()
	point = _ui._frame.global_position + _ui._point_of_uv(Vector2(0.2, 0.3))
	_viewport_button(MOUSE_BUTTON_RIGHT, true, point)
	_viewport_button(MOUSE_BUTTON_RIGHT, false, point)
	await get_tree().process_frame
	await get_tree().process_frame
	check(_ui._marker_editor.visible, "el clic llega al mapa a través de los controles reales")
	check(Rect2(Vector2.ZERO, _ui._frame.size).encloses(_ui._marker_editor.get_rect()),
		"la ficha completa cabe en el mapa a 1280 × 720")
	_ui._marker_editor._name_edit.text = "Aceptado con Enter"
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	get_viewport().push_input(enter, true)
	enter.pressed = false
	get_viewport().push_input(enter, true)
	check(not _ui._marker_editor.visible and _ui.markers.for_planet(host.entity_id).size() == 2,
		"Enter en el campo acepta a través de la UI real")
	var available_map := host.world_map.map
	host.world_map.map = null
	_ui._refresh_map_source()
	_button(MOUSE_BUTTON_RIGHT, true, _ui._frame.size * 0.5)
	check(_ui._mark_here_button.disabled and not _ui._marker_editor.visible,
		"no se crean marcadores mientras el mapa no está disponible")
	host.world_map.map = available_map
	_ui._refresh_map_source()
	# La muerte no depende del planeta que se dejó abierto ni de que el mapa esté horneado.
	_ui.close()
	host.entity_id = "death_planet"
	host.world_map.map = null
	_ui.mark_last_death()
	var death: Dictionary = _ui.markers.for_planet("death_planet")[0]
	check(death.icon == "tombstone" and death.uv.is_equal_approx(_ui._player_uv()) \
		and MapMarkerEditor.ICON_TEXTURES.has("tombstone"),
		"se marca la muerte en el planeta vivo con el mapa cerrado y aún sin generar")
	host.world_map.map = available_map
	_ui.open()
	_ui._zoom = 1.0
	_ui._layout_map()
	check(_ui._marker_at(_ui._point_of_uv(death.uv)) == death.id,
		"la tumba automática se dibuja y selecciona con el sistema común de marcadores")
	_ui.close()
	host.entity_id = "planet_test"


func _check_player_save() -> void:
	var menu := Control.new()
	add_child(menu)
	for button_name in ["btnSaveGame", "btnStartGame"]:
		var button := Button.new()
		button.name = button_name
		menu.add_child(button)
		button.owner = menu
	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	add_child(spawn)
	var player: PlayerController = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.set_script(GroundedPlayer)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.main_menu = menu
	add_child(player)
	GameManager.current_state = GameManager.State.PLAYING
	var slot := "test_map_markers_%d" % Time.get_ticks_usec()
	var id := player.world_map_ui.markers.add("planet_test", Vector2(0.25, 0.6), "resources", "Hierro")
	var death_host := MapHost.new()
	death_host.entity_id = "death_planet"
	death_host.position = Vector3(6000, 1000, -3000)
	add_child(death_host)
	death_host.world_map = PlanetWorldMap.new()
	death_host.add_child(death_host.world_map)
	death_host.world_map._center_node = death_host
	player.planet = death_host
	var death_uv := Vector2(0.3, 0.65)
	player.global_position = death_host.global_position + WorldMapData.uv_to_dir(death_uv) * 30000.0
	player.health_component.take_damage(10000.0)
	var death: Dictionary = player.world_map_ui.markers.for_planet("death_planet")[0]
	check(death.uv.is_equal_approx(death_uv) and death.icon == "tombstone",
		"la muerte real registra sus coordenadas antes de la reaparición y sin abrir el mapa")
	player.planet = null
	check(await GameManager.save_game(slot), "se guarda una partida con marcadores")
	player.world_map_ui.markers.remove(id)
	player.world_map_ui.markers.add("other", Vector2(0.1, 0.2), "danger")
	for i in 2:
		check(GameManager.load_game(slot), "se carga la partida con marcadores (%d)" % (i + 1))
		check(player.world_map_ui.markers.save_data().size() == 2
			and player.world_map_ui.markers.get_marker(id).name == "Hierro"
			and player.world_map_ui.markers.get_marker(id).icon == "resources",
			"cargar recupera el marcador guardado y sustituye los de la sesión")
		check(player.world_map_ui.markers.get_marker(death.id).get("kind") == MapMarkers.LAST_DEATH \
			and player.world_map_ui.markers.get_marker(death.id).uv.is_equal_approx(death_uv),
			"la última muerte también se restaura sin duplicarse")
	# Compatibilidad usando la restauración real del jugador, sin la clave nueva.
	var old_save := player.get_save_data()
	old_save.erase("map_markers")
	player.restore_save_data(old_save)
	check(player.world_map_ui.markers.save_data().is_empty(), "el jugador carga una partida anterior sin marcadores")
	GameManager.delete_save(slot)
	GameManager.player = null
	player.queue_free()
	await get_tree().process_frame


func _capture() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().unfocusable = true
	get_window().position = Vector2i(-4000, -4000)
	get_window().gui_embed_subwindows = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	TranslationServer.set_locale("es")
	_ui.open()
	_ui.markers.load_data([])
	var names := ["Refugio", "Hierro", "Cueva del norte", "Campamento", "Lobos", "Mirador", "Tumba"]
	for i in MapMarkers.ICONS.size():
		_ui.markers.add("planet_test", Vector2(0.12 + i * 0.12, 0.3 + (i % 2) * 0.3),
			MapMarkers.ICONS[i], names[i])
	DirAccess.make_dir_recursive_absolute("res://build/ui")
	for resolution in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		_ui._zoom = 1.0
		_ui._offset = Vector2.ZERO
		_ui._layout_map()
		_ui._edit_marker_at(Vector2(0.36, 0.3), 3)
		_ui._overlay.queue_redraw()
		_ui._update_info()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var shot := get_viewport().get_texture().get_image()
		shot.save_png("res://build/ui/map_markers_%d.png" % resolution.y)
		if resolution.y == 720:
			shot.save_png("res://build/ui/map_markers.png")
		_ui._marker_editor._icon_choice.show_popup()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"res://build/ui/map_marker_icons_%d.png" % resolution.y)
		_ui._marker_editor._icon_choice.get_popup().hide()
