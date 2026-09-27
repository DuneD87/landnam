extends Node

## Abre la pantalla de opciones sobre una escena mínima (sol, entorno con atmósfera). Sin
## argumentos se queda abierta para probarla a mano. Con `-- --capture` comprueba presets,
## audio, reasignación de teclas y Cancelar, guarda capturas de cada pestaña en
## build/ui/options/ y sale con código 1 si algo falla. No guarda user://settings.cfg: termina
## siempre con Cancelar. Necesita ventana.

var _screen: OptionsScreen
var _sun: DirectionalLight3D
var _world: WorldEnvironment
var _atmosphere := PlanetAtmosphere.new()
var _failures: Array[String] = []


func _ready() -> void:
	_build_scene()
	_screen = OptionsScreen.new()
	add_child(_screen)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()


func _build_scene() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 2, 6)
	add_child(camera)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 1500.0
	_sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(_sun)
	_world = WorldEnvironment.new()
	_world.environment = Environment.new()
	_world.environment.glow_enabled = true
	_world.compositor = Compositor.new()
	# Sin ser efecto activo: solo interesa que reciba la calidad.
	_atmosphere.enabled = false
	_world.compositor.compositor_effects = [_atmosphere]
	add_child(_world)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.scale = Vector3.ONE * 20.0
	add_child(floor_mesh)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.position.y = 0.5
	add_child(box)


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/ui/options")
	var settings := get_node("/root/Settings") as SettingsManager
	var root := get_tree().root
	var music := AudioServer.get_bus_index(&"Music")
	var music_db := AudioServer.get_bus_volume_db(music)
	var jump_before := InputMap.action_get_events(&"jump")

	for tab in OptionsScreen.TABS.size():
		_screen._show_tab(tab)
		await _shot("%02d_%s" % [tab + 1, ["pantalla", "graficos", "audio", "controles"][tab]])

	_screen._show_tab(1)
	_screen._on_preset_selected(SettingsManager.Preset.LOW)
	await _shot("05_graficos_bajo")
	_check(SettingsManager.current_preset() == SettingsManager.Preset.LOW, "el preset Bajo no se detecta")
	_check(is_equal_approx(root.scaling_3d_scale, 0.75), "escala de render %s" % root.scaling_3d_scale)
	_check(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR, "reescalado %s" % root.scaling_3d_mode)
	_check(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA and root.msaa_3d == Viewport.MSAA_DISABLED,
		"antialiasing no es FXAA")
	_check(_sun.shadow_enabled and _sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"sombras bajas sin dos cascadas")
	_check(is_equal_approx(_sun.directional_shadow_max_distance, 1500.0 * 0.35),
		"distancia de sombra %s" % _sun.directional_shadow_max_distance)
	_check(not _world.environment.glow_enabled, "el resplandor sigue encendido")
	_check(is_equal_approx(_atmosphere.quality_step_scale, 0.6) and not _atmosphere.quality_god_rays,
		"atmósfera sin la calidad baja")
	_check(is_equal_approx(WeatherParticles.amount_scale, 0.3), "partículas %s" % WeatherParticles.amount_scale)
	_check(SettingsManager.needs_restart(), "no avisa de reinicio con la hierba cambiada")
	_check(_screen._notice.text != "", "sin aviso de reinicio en pantalla")

	settings.set_value("graphics/shadow_quality", 0)
	_check(not _sun.shadow_enabled, "sin sombras el sol las sigue teniendo")
	_screen._on_preset_selected(SettingsManager.Preset.ULTRA)
	_check(_sun.shadow_enabled and _sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"Ultra no recupera las cuatro cascadas")
	_check(is_equal_approx(_sun.directional_shadow_max_distance, 1500.0), "Ultra no recupera la distancia")
	settings.set_value("graphics/render_scale", 0.9)
	_check(SettingsManager.current_preset() == SettingsManager.PRESET_CUSTOM, "no pasa a Personalizado")
	await _shot("06_graficos_personalizado")

	_screen._show_tab(2)
	settings.set_value("audio/Music", 0.5)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(music), music_db + linear_to_db(0.5)),
		"la música no respeta la mezcla (%s dB)" % AudioServer.get_bus_volume_db(music))
	_check(is_equal_approx(AudioManager.get_bus_volume(&"Music"), 0.5), "get_bus_volume no devuelve 0.5")

	# Reasignar Saltar a J con eventos de verdad: J era Convertir en dinámica y se le quita.
	_screen._show_tab(3)
	await get_tree().process_frame
	var jump_button := _find_binding_button(&"jump")
	jump_button.pressed.emit()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.keycode = KEY_J
	key.pressed = true
	get_viewport().push_input(key)
	await _shot("07_controles_reasignado")
	_check(_has_key(&"jump", KEY_J), "Saltar no tiene la J")
	_check(not _has_key(&"convert_dynamic", KEY_J), "la J sigue en Convertir en dinámica")
	_check(_screen._notice.text.contains("Convertir en dinámica"), "sin aviso de tecla quitada")
	settings.set_value("controls/mouse_sensitivity", 1.5)
	_check(is_equal_approx(SettingsManager.mouse_scale, 1.5), "la sensibilidad no llega a las cámaras")

	_screen._on_cancel()
	await get_tree().process_frame
	_check(not OptionsScreen.is_open(), "sigue abierta tras Cancelar")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(music), music_db), "Cancelar no devuelve la música")
	_check(_has_key(&"convert_dynamic", KEY_J) and not _has_key(&"jump", KEY_J), "Cancelar no devuelve las teclas")
	_check(InputMap.action_get_events(&"jump").size() == jump_before.size(), "Saltar cambia de nº de teclas")
	_check(is_equal_approx(SettingsManager.mouse_scale, float(SettingsManager.value("controls/mouse_sensitivity"))),
		"Cancelar no devuelve la sensibilidad")

	for failure in _failures:
		push_error("OptionsScreen: " + failure)
	print("OptionsScreen: %s" % ("OK" if _failures.is_empty() else "%d fallos" % _failures.size()))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _find_binding_button(action: StringName) -> Button:
	var label := ""
	for group in SettingsManager.REBINDABLE_ACTIONS:
		for entry in group[1]:
			if entry[0] == action:
				label = entry[1]
	for node in _screen.find_children("*", "Label", true, false):
		if node.text == label:
			var row: Node = node.get_parent().get_parent()
			return row.get_child(1).get_child(0)
	return null


func _has_key(action: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _shot(shot_name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://build/ui/options/%s.png" % shot_name
	get_viewport().get_texture().get_image().save_png(path)
	print("Captura: ", ProjectSettings.globalize_path(path))
