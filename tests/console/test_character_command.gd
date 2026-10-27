extends Node

## Runs against the real creator and appearance rig without loading a planet:
## godot --headless --path . res://tests/console/test_character_command.tscn

class TestPlayer extends CharacterBody3D:
	var input_enabled := true
	var appearance_rig: CharacterAppearanceRig
	var character_window: CharacterWindow

var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)


func _run() -> void:
	var previous_player := GameManager.player
	var previous_character := GameManager.character
	var previous_state := GameManager.current_state
	var previous_locale := TranslationServer.get_locale()
	var previous_mouse := Input.get_mouse_mode()
	var player := TestPlayer.new()
	get_tree().root.add_child(player)
	player.position = Vector3(3, 5, 9)
	var model: Node3D = load("res://scenes/character/character_model.tscn").instantiate()
	player.add_child(model)
	player.appearance_rig = model.get_node("AppearanceRig")
	GameManager.player = player
	var original := CharacterData.new()
	original.display_name = "Saved Hero"
	original.appearance.set_value(AppearanceCatalog.HAIR_STYLE, &"jungle")
	GameManager.character = original
	player.appearance_rig.apply(original.appearance)
	var original_data := original.to_dict()

	for locale in ["en", "es"]:
		TranslationServer.set_locale(locale)
		var help := Console._cmd_help(["character"])
		check(help.contains("Edits the current character" if locale == "en" else "Edita el personaje actual"),
			"%s: character help is registered and translated" % locale)
		check(Console._cmd_character(["invalid"]).contains("Usage:" if locale == "en" else "Uso:"),
			"%s: invalid arguments are rejected" % locale)
	GameManager.current_state = GameManager.State.MENU
	check(not Console._cmd_character([]).is_empty() and not get_tree().paused,
		"editing requires a loaded, playing game")
	GameManager.current_state = GameManager.State.PLAYING
	Console._set_visible(true)
	Console._run("character")
	var editor := Console._character_editor
	check(is_instance_valid(editor) and editor.editing and not Console._is_open,
		"character opens the editor and closes the console")
	check(get_tree().paused and not player.input_enabled, "the world and player controls pause while editing")
	check(editor.character != original and editor.character.appearance != original.appearance
			and editor.character.to_dict() == original_data, "the editor starts with an independent copy of the saved character")
	check(editor._back_button.text == "UI_CANCEL" and editor._next_button.text == "CREATE_APPLY_CHANGES",
		"editing offers Cancel and Apply changes")
	Console._cmd_character([])
	check(Console._character_editor == editor, "another command cannot open a second editor")
	if "--capture" in OS.get_cmdline_user_args():
		for category in AppearanceCatalog.categories():
			if category.id == &"hair":
				editor._steps[0]._select_category(category)
		editor.preview.focus(&"head", false)
		var deadline := Time.get_ticks_msec() + 15000
		while editor._steps[0]._thumbnails._busy and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/character/edit_review")
		get_viewport().get_texture().get_image().save_png("res://build/character/edit_review/editor.png")
	editor.character.display_name = "Edited Hero"
	editor.character.appearance.set_value(AppearanceCatalog.HAIR_STYLE, &"spiky")
	check(GameManager.character.to_dict() == original_data, "pending edits leave the current character untouched")
	editor._on_next()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not get_tree().paused and player.input_enabled and not is_instance_valid(Console._character_editor),
		"applying closes the editor and restores controls")
	check(GameManager.character.display_name == "Edited Hero"
			and player.appearance_rig._slots[&"hair"].part == &"hair_ht_spiky",
		"applying updates the current character and its visible hair")
	var saved := JSON.parse_string(JSON.stringify(GameManager.character.to_dict())) as Dictionary
	check(CharacterData.from_dict(saved).appearance.get_value(AppearanceCatalog.HAIR_STYLE) == &"spiky",
		"the player save's character data retains the edited hair after a JSON round trip")
	check(original.to_dict() == original_data and player.position == Vector3(3, 5, 9)
			and GameManager.current_state == GameManager.State.PLAYING,
		"editing preserves the original resource, player position and playing state")

	var applied := GameManager.character
	var applied_data := applied.to_dict()
	Console._cmd_character([])
	editor = Console._character_editor
	editor.character.display_name = "Discarded"
	editor.character.appearance.set_sex(&"female")
	editor._on_back()
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameManager.character == applied and GameManager.character.to_dict() == applied_data and not get_tree().paused,
		"cancelling discards all pending edits and resumes the game")
	player.input_enabled = false
	Console._cmd_character([])
	Console._character_editor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not player.input_enabled and not get_tree().paused, "closing preserves controls that were already disabled")
	player.input_enabled = true

	GameManager.character = null
	Console._cmd_character([])
	editor = Console._character_editor
	check(editor.character != null and not editor._next_button.disabled,
		"legacy saves without character data or a name can be edited")
	editor._on_next()
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameManager.character != null and not get_tree().paused, "legacy characters can be applied without starting a new game")
	var creator := CharacterCreationScreen.new()
	get_tree().root.add_child(creator)
	check(creator._next_button.disabled and creator._back_button.text == "CREATE_BACK_TO_MENU",
		"new-game creation still requires a name and offers Back to menu")
	creator.queue_free()
	await get_tree().process_frame
	GameManager.player = previous_player
	GameManager.character = previous_character
	GameManager.current_state = previous_state
	TranslationServer.set_locale(previous_locale)
	Input.set_mouse_mode(previous_mouse)
	player.free()
	print("CHARACTER COMMAND TESTS: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
