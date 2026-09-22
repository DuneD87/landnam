extends Control

@export var start_button: Button
@export var quit_button: Button
@export var fade_duration: float = 0.8

var _save_button: Button
var _load_button: Button


func _ready() -> void:
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

	_save_button = find_child("btnSaveGame")
	_load_button = find_child("btnLoadGame")

	if _save_button:
		_save_button.pressed.connect(_on_save_pressed)
		_save_button.visible = false
	if _load_button:
		_load_button.pressed.connect(_on_load_pressed)
		_load_button.visible = GameManager.has_save(GameManager.MAIN_SLOT)

	GameManager.state_changed.connect(_on_game_state_changed)
	visible = true


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


## "Start Game" pasa por la creación de personaje; la partida arranca al confirmarla.
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
		GameManager.State.CINEMATIC, GameManager.State.CHARACTER_CREATION:
			visible = false
		GameManager.State.PLAYING:
			visible = false
			if _save_button:
				_save_button.visible = true


func _set_buttons_disabled(disabled: bool) -> void:
	if start_button:
		start_button.disabled = disabled
	if quit_button:
		quit_button.disabled = disabled
	if _save_button:
		_save_button.disabled = disabled
	if _load_button:
		_load_button.disabled = disabled


func _get_all_controls() -> Array[Control]:
	var controls: Array[Control] = []
	_collect_controls(self, controls)
	return controls


func _collect_controls(node: Node, result: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control:
			result.append(child)
		_collect_controls(child, result)
