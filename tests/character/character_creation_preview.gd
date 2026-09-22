extends Node

## Runs the character creation screen on its own and prints the resulting
## character. With `-- --capture` it goes through a few states (default,
## female with long hair, face close-up, random) saving screenshots under
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
	appearance.set_value(AppearanceCatalog.HAIR_STYLE, &"ponytail01")
	appearance.set_value(&"skin_color", Color("7f5236"))
	_screen.preview.focus(&"head")
	await _shot("06_ponytail", 1.0)
	get_tree().quit()


func _shot(name: String, wait := 0.3) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/character/creation/%s.png" % name)
