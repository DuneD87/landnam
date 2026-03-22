## MenuUI.gd — Attached to a CanvasLayer containing your menu UI

extends Control

@export var start_button: Button
@export var quit_button: Button
@export var fade_duration: float = 0.8


func _ready() -> void:
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

	GameManager.state_changed.connect(_on_game_state_changed)
	visible = true


func _on_start_pressed() -> void:
	_set_buttons_disabled(true)

	var tween := create_tween()
	for child in _get_all_controls():
		tween.set_parallel(true)
		tween.tween_property(child, "modulate:a", 0.0, fade_duration)

	tween.set_parallel(false)
	tween.tween_callback(_start_after_fade)


func _start_after_fade() -> void:
	visible = false
	GameManager.start_game()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_game_state_changed(new_state: GameManager.State) -> void:
	match new_state:
		GameManager.State.MENU:
			visible = true
			_set_buttons_disabled(false)
			for child in _get_all_controls():
				child.modulate.a = 1.0
		GameManager.State.CINEMATIC, GameManager.State.PLAYING:
			visible = false


func _set_buttons_disabled(disabled: bool) -> void:
	if start_button:
		start_button.disabled = disabled
	if quit_button:
		quit_button.disabled = disabled


func _get_all_controls() -> Array[Control]:
	var controls: Array[Control] = []
	_collect_controls(self, controls)
	return controls


func _collect_controls(node: Node, result: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control:
			result.append(child)
		_collect_controls(child, result)
