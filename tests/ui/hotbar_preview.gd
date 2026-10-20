extends Node

## Vista aislada de la hotbar real: 1–0 seleccionan, clic selecciona y Espacio alterna
## normal / crítico / bajo el agua. --capture guarda los estados y escalas en build/ui/hotbar/.
## godot --path . res://tests/ui/hotbar_preview.tscn -- --capture

const OUTPUT := "res://build/ui/hotbar"

var _hotbar: Hotbar
var _needs := SurvivalNeeds.new()
var _scenario := 0
var _health := 0.72
var _stamina := 0.64
var _title: Label
var _capture_resolution := Vector2i.ZERO


func _ready() -> void:
	if "--capture" in OS.get_cmdline_user_args():
		get_window().mode = Window.MODE_WINDOWED
		if "--background" in OS.get_cmdline_user_args():
			get_window().unfocusable = true
			get_window().position = Vector2i(-4000, -4000)
	_build_backdrop()
	_needs.paused = true
	add_child(_needs)
	_hotbar = load("res://scenes/ui/hotbar.tscn").instantiate()
	add_child(_hotbar)
	for entry in [[0, &"iron_sword"], [1, &"battle_axe"], [2, &"hunting_bow"], [3, &"spear"],
			[4, &"stone_axe_01"], [5, &"stone_pickaxe_01"], [6, &"heater_shield"], [7, &"torch_01"]]:
		_hotbar.assign_to_slot(entry[0], ItemCatalog.get_item(entry[1]))
	_hotbar.select_slot(0)
	_hotbar.set_offhand(ItemCatalog.get_item(&"heater_shield"))
	_hotbar.offhand_toggled.connect(func(data: ItemData):
		_hotbar.set_offhand(null if _hotbar._offhand_id == data.id else data))
	_hotbar.hotbar_slot_clicked.connect(_hotbar.select_slot)
	_set_scenario(0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _process(delta: float) -> void:
	if _hotbar == null:
		return
	_hotbar.health_orb.set_levels(_health, _health, 0.0, 0.0, "%d / 100" % roundi(_health * 100.0), delta)
	_hotbar.stamina_orb.set_levels(_stamina, 0.0, 0.0, 0.0, "%d / 100" % roundi(_stamina * 100.0), delta)
	_hotbar.show_needs(_needs, delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_set_scenario((_scenario + 1) % 3)


func _set_scenario(index: int) -> void:
	_scenario = index
	_health = 0.72 if index != 1 else 0.18
	_stamina = 0.64 if index != 1 else 0.08
	_needs.hunger = 0.78 if index != 1 else 0.12
	_needs.thirst = 0.6 if index != 1 else 0.1
	_needs.rest = 0.85 if index != 1 else 0.1
	_needs.sanity = 0.68 if index != 1 else 0.12
	_needs.warmth = -0.18 if index != 1 else -0.8
	_needs.submerged = index == 2
	_needs.oxygen = 0.46 if index == 2 else 1.0
	_title.text = "SAGA · %s" % ["EXPLORACIÓN", "NECESIDADES CRÍTICAS", "BAJO EL AGUA"][index]


func _build_backdrop() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("3b4850"), Color("242e2f"), Color("111719")])
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	background.texture = texture
	layer.add_child(background)
	_title = Label.new()
	_title.position = Vector2(48, 40)
	_title.add_theme_font_override("font", GameTheme.title_font())
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", GameTheme.BRONZE)
	layer.add_child(_title)
	var hint := Label.new()
	hint.position = Vector2(48, 82)
	hint.text = "1–0 / clic: seleccionar · 7: escudo · Espacio: cambiar estado"
	hint.add_theme_font_override("font", GameTheme.body_font())
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", GameTheme.MUTED)
	layer.add_child(hint)


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	# Settings puede haber aplicado pantalla completa. La prueba controla solo esta ventana,
	# sin guardar preferencias, y comprueba el viewport en lugar de fiarse del nombre del PNG.
	get_window().mode = Window.MODE_WINDOWED
	if "--background" in OS.get_cmdline_user_args():
		get_window().unfocusable = true
		get_window().position = Vector2i(-4000, -4000)
	if not await _resize(Vector2i(1920, 1080)):
		return
	await _shot("01_exploracion_1080")
	# La nueva envoltura del icono no debe interceptar el ratón ni cambiar los atajos.
	if not await _verify_input():
		get_tree().quit(1)
		return
	_hotbar.slots[1]._set_hovered(true)
	await _shot("02_seleccion_hover_1080")
	_hotbar.slots[1]._set_hovered(false)
	_set_scenario(1)
	await _shot("03_critico_1080")
	_set_scenario(2)
	await _shot("04_oxigeno_1080")
	_hotbar.set_vitals_shown(false)
	await _shot("05_barra_sola_1080")
	_hotbar.set_vitals_shown(true)
	_set_scenario(0)
	if not await _resize(Vector2i(1280, 720)):
		return
	# Deja terminar la persistencia del aliento antes de la siguiente vista de exploración.
	await _shot("06_exploracion_720", BreathRing.LINGER + BreathRing.FADE + 0.1)
	if not await _resize(Vector2i(2560, 1440)):
		return
	await _shot("07_exploracion_1440")
	if not await _resize(Vector2i(1920, 1080)):
		return
	await _shot("09_regreso_1080")
	get_tree().quit()


func _resize(resolution: Vector2i) -> bool:
	_capture_resolution = resolution
	# Al salir de pantalla completa el gestor de ventanas puede enviar un tamaño restaurado
	# después de aceptar el pedido. Reintentar una vez asentado evita capturar esa transición.
	for attempt in 3:
		get_window().size = resolution
		await get_tree().create_timer(0.2).timeout
		if Vector2i(get_viewport().get_visible_rect().size) == resolution:
			return true
	push_error("El viewport no llegó a %s; sigue en %s." % [resolution, get_viewport().get_visible_rect().size])
	get_tree().quit(1)
	return false


func _verify_layout() -> bool:
	if Vector2i(get_viewport().get_visible_rect().size) != _capture_resolution:
		push_error("La ventana cambió de tamaño antes de capturar: se esperaba %s." % _capture_resolution)
		return false
	var s := _hotbar.get_ui_scale()
	var panel := _hotbar.get_panel()
	var bar := panel.get_global_rect()
	var minimum := panel.get_combined_minimum_size()
	if bar.size.x < minimum.x or bar.size.y < minimum.y or absf(bar.get_center().x - get_viewport().get_visible_rect().size.x * 0.5) > 1.0:
		push_error("Panel sin encajar o descentrado: %s; mínimo %s." % [bar, minimum])
		return false
	# El panel toma la medida de la consola horneada; tolera un píxel por el redondeo.
	if bar.size.distance_to(Hotbar.PANEL_SIZE * s) > 2.0:
		push_error("El panel no coincide con la consola horneada: %s." % bar.size)
		return false
	for slot in _hotbar.slots:
		var icon := slot._icon.get_global_rect()
		var key := slot._mark.get_global_rect()
		if icon.intersects(key) or not slot.get_global_rect().encloses(key):
			push_error("La tecla se sale del hueco o tapa el icono: %s." % slot.slot_index)
			return false
	return true


func _verify_input() -> bool:
	_key(KEY_3)
	await get_tree().process_frame
	if _hotbar.selected_index != 2:
		push_error("La tecla 3 no seleccionó el tercer hueco.")
		return false
	if _hotbar._selection_label.text != ItemCatalog.get_item(&"hunting_bow").get_display_name():
		push_error("El nombre no sigue al objeto seleccionado.")
		return false
	await _click(6)
	if _hotbar.selected_index != 2 or _hotbar._offhand_id != &"":
		push_error("El clic del escudo no mantuvo el arma ni quitó la otra mano.")
		return false
	await _click(6)
	if _hotbar.selected_index != 2 or _hotbar._offhand_id != &"heater_shield":
		push_error("El clic no volvió a equipar el escudo.")
		return false
	_key(KEY_3)
	await get_tree().process_frame
	if _hotbar.selected_index != -1:
		push_error("Repetir la tecla no deseleccionó el objeto.")
		return false
	if not _hotbar._selection_label.text.is_empty():
		push_error("El nombre sigue visible tras deseleccionar.")
		return false
	await _click(1)
	if _hotbar.selected_index != 1:
		push_error("La zona de icono interceptó el clic de selección.")
		return false
	_key(KEY_3)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(20, 20)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	print("Verificado: teclas, clic sobre iconos, escudo independiente y deselección.")
	return true


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)


func _click(index: int) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = _hotbar.slots[index].get_global_rect().get_center() - Vector2(0, 12)
		event.global_position = event.position
		Input.parse_input_event(event)
	await get_tree().process_frame


func _shot(shot_name: String, wait := 0.65) -> void:
	await get_tree().create_timer(wait).timeout
	if Vector2i(get_viewport().get_visible_rect().size) != _capture_resolution:
		if not await _resize(_capture_resolution):
			return
	await RenderingServer.frame_post_draw
	if not _verify_layout():
		get_tree().quit(1)
		return
	var path := "%s/%s.png" % [OUTPUT, shot_name]
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != Vector2i(get_viewport().get_visible_rect().size):
		push_error("La captura no coincide con el tamaño del viewport.")
		get_tree().quit(1)
		return
	var result := image.save_png(path)
	if result != OK:
		push_error("No se pudo guardar la captura: %s" % path)
		get_tree().quit(1)
	print("Captura: ", ProjectSettings.globalize_path(path), " · ", image.get_size())
	if shot_name == "01_exploracion_1080":
		# Un encuadre de la consola, generado desde el viewport para revisar el detalle.
		var bounds := _hotbar.plate.get_global_rect().merge(_hotbar._selection_label.get_global_rect())
		var region := Rect2i(bounds.grow(12.0))
		region = region.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		image.get_region(region).save_png(OUTPUT.path_join("08_detalle_1080.png"))
