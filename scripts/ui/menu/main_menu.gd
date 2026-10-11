extends Control

## Menú principal, y en partida el de pausa (Escape): el nombre del juego y una columna de
## botones a la izquierda, sobre una sombra que deja ver el mundo a la derecha.

## Posición y ancho de la columna, en la escala base de 1440 px.
const COLUMN_LEFT := 160.0
const COLUMN_WIDTH := 760.0

@export var start_button: Button
@export var quit_button: Button
@export var fade_duration: float = 0.8

var _save_button: Button
var _load_button: Button
var _options_button: Button


func _ready() -> void:
	var shade := _build_shade()
	add_child(shade)
	move_child(shade, 0)
	_apply_theme()
	get_viewport().size_changed.connect(_apply_theme)
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

	_save_button = find_child("btnSaveGame")
	_load_button = find_child("btnLoadGame")
	_options_button = find_child("btnOptions")
	if _options_button:
		_options_button.pressed.connect(_on_options_pressed)

	if _save_button:
		_save_button.pressed.connect(_on_save_pressed)
		_save_button.visible = false
	if _load_button:
		_load_button.pressed.connect(_on_load_pressed)
		_load_button.visible = GameManager.has_save(GameManager.MAIN_SLOT)

	GameManager.state_changed.connect(_on_game_state_changed)
	visible = true


## Saga a la escala de la ventana; la columna, a la izquierda y centrada en alto.
func _apply_theme() -> void:
	var ui_scale := GameTheme.scale_for(get_viewport())
	theme = GameTheme.build(ui_scale)
	var column: VBoxContainer = $Column
	column.offset_left = COLUMN_LEFT * ui_scale
	column.offset_right = (COLUMN_LEFT + COLUMN_WIDTH) * ui_scale
	column.add_theme_constant_override("separation", roundi(20 * ui_scale))
	($Column/Buttons as VBoxContainer).add_theme_constant_override("separation", roundi(6 * ui_scale))


## Oscurece la mitad izquierda, donde va la columna, y se desvanece hacia el centro.
func _build_shade() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.012, 0.013, 0.016, 0.88))
	gradient.set_color(1, Color(0.012, 0.013, 0.016, 0.0))
	gradient.set_offset(1, 0.62)
	gradient.add_point(0.3, Color(0.012, 0.013, 0.016, 0.7))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1024
	texture.height = 4
	var rect := TextureRect.new()
	rect.name = "Shade"
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func fade_in(duration: float = fade_duration) -> void:
	visible = true
	for child in _get_all_controls():
		child.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	for child in _get_all_controls():
		tween.tween_property(child, "modulate:a", 1.0, duration)
	tween.set_parallel(false)
	tween.tween_callback(func(): _set_buttons_disabled(false))


func fade_out(duration: float = fade_duration) -> void:
	_set_buttons_disabled(true)
	var tween := create_tween()
	tween.set_parallel(true)
	for child in _get_all_controls():
		tween.tween_property(child, "modulate:a", 0.0, duration)
	tween.set_parallel(false)
	tween.tween_callback(func(): visible = false)


## "Nueva partida" pasa por la creación de personaje; la partida arranca al confirmarla.
func _on_start_pressed() -> void:
	fade_out()
	await get_tree().create_timer(fade_duration).timeout
	var screen := CharacterCreationScreen.new()
	screen.finished.connect(_on_character_created.bind(screen))
	screen.cancelled.connect(_on_character_creation_cancelled.bind(screen))
	get_parent().add_child(screen)
	GameManager.begin_character_creation()


func _on_character_created(character: CharacterData, screen: CharacterCreationScreen) -> void:
	screen.queue_free()
	GameManager.start_game(character)


func _on_character_creation_cancelled(screen: CharacterCreationScreen) -> void:
	screen.queue_free()
	GameManager.cancel_character_creation()
	fade_in()


## Encima del menú, que sigue debajo al cerrarla (también en partida, donde hace de pausa).
func _on_options_pressed() -> void:
	get_parent().add_child(OptionsScreen.new())


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_save_pressed() -> void:
	_set_buttons_disabled(true)
	var success := await GameManager.save_game(GameManager.MAIN_SLOT)
	if success:
		print("[MenuUI] Partida guardada en slot '%s'" % GameManager.MAIN_SLOT)
		if _load_button:
			_load_button.visible = true
	else:
		push_error("[MenuUI] Error al guardar partida")
	_set_buttons_disabled(false)


func _on_load_pressed() -> void:
	fade_out()
	await get_tree().create_timer(fade_duration).timeout
	var success := GameManager.load_game(GameManager.MAIN_SLOT)
	if not success:
		push_error("[MenuUI] Error al cargar partida")
		fade_in()


func _on_game_state_changed(new_state: GameManager.State) -> void:
	match new_state:
		GameManager.State.MENU:
			visible = true
			_set_buttons_disabled(false)
			for child in _get_all_controls():
				child.modulate.a = 1.0
			if _save_button:
				_save_button.visible = false
			if _load_button:
				_load_button.visible = GameManager.has_save(GameManager.MAIN_SLOT)
				_load_button.text = "Continuar partida"
		GameManager.State.CINEMATIC, GameManager.State.CHARACTER_CREATION:
			visible = false
		GameManager.State.PLAYING:
			visible = false
			if _save_button:
				_save_button.visible = true
			# En partida, cargar vuelve a la última guardada.
			if _load_button:
				_load_button.text = "Cargar partida"


func _set_buttons_disabled(disabled: bool) -> void:
	if start_button:
		start_button.disabled = disabled
	if quit_button:
		quit_button.disabled = disabled
	if _save_button:
		_save_button.disabled = disabled
	if _load_button:
		_load_button.disabled = disabled
	if _options_button:
		_options_button.disabled = disabled


func _get_all_controls() -> Array[Control]:
	var controls: Array[Control] = []
	_collect_controls(self, controls)
	return controls


func _collect_controls(node: Node, result: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control:
			result.append(child)
		_collect_controls(child, result)
