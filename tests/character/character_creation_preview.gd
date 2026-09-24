extends Node

## Runs the character creation screen on its own and prints the resulting
## character. With `-- --capture` it goes through a few states (default,
## female with long hair, face close-up, random, camera moved with the mouse)
## saving screenshots under
## build/character/creation/ and quits. Needs a window.

var _screen: CharacterCreationScreen


func _ready() -> void:
	_screen = CharacterCreationScreen.new()
	_screen.finished.connect(func(character: CharacterData) -> void:
		print("Personaje creado: ", JSON.stringify(character.to_dict(), "\t"))
		get_tree().quit())
	_screen.cancelled.connect(get_tree().quit)
	add_child(_screen)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/character/creation")
	var appearance := _screen.character.appearance
	var step: Control = _screen._steps[0]
	await _shot("01_default")
	appearance.set_sex(&"female")
	step._rebuild_options()
	await _shot("02_female")
	for category in AppearanceCatalog.categories():
		if category.id == &"hair":
			step._select_category(category)
	appearance.set_value(&"hair_color", Color("9c7449"))
	await _shot("03_female_hair", 1.0)
	for category in AppearanceCatalog.categories():
		if category.id == &"eyes":
			step._select_category(category)
	appearance.set_value(&"eye_color", Color("3f6f9a"))
	await _shot("04_female_face", 1.0)
	appearance.set_sex(&"male")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	appearance.randomize_values(rng)
	step._select_category(AppearanceCatalog.categories()[0])
	await _shot("05_male_random", 1.0)
	appearance.set_value(AppearanceCatalog.HAIR_STYLE, &"topknot")
	appearance.set_value(&"skin_color", Color("7f5236"))
	_screen.preview.focus(&"head")
	await _shot("06_ponytail", 1.0)
	# The camera, through real mouse input: zoom towards the chest, move the
	# view down to the hands, then orbit to look from above.
	_screen.preview.focus(&"body")
	await _shot("07_body", 1.0)
	var size := get_viewport().get_visible_rect().size
	var chest := Vector2(size.x * 0.62, size.y * 0.36)
	for i in 8:
		_click(chest, MOUSE_BUTTON_WHEEL_UP, true)
		_click(chest, MOUSE_BUTTON_WHEEL_UP, false)
	await _shot("08_zoom_chest")
	_drag(chest, MOUSE_BUTTON_RIGHT, Vector2(0, -size.y * 0.3))
	await _shot("09_pan_down")
	_drag(chest, MOUSE_BUTTON_LEFT, Vector2(size.x * 0.1, size.y * 0.15))
	await _shot("10_orbit")
	get_tree().quit()


func _click(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = pressed
	event.factor = 1.0
	get_viewport().push_input(event)


## Holds `button` at `from` and moves the mouse by `by` in small steps.
func _drag(from: Vector2, button: MouseButton, by: Vector2) -> void:
	_click(from, button, true)
	var steps := 20
	for i in steps:
		var event := InputEventMouseMotion.new()
		event.position = from + by * (i + 1) / steps
		event.global_position = event.position
		event.relative = by / steps
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		get_viewport().push_input(event)
	_click(from + by, button, false)


func _shot(name: String, wait := 0.3) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/character/creation/%s.png" % name)
