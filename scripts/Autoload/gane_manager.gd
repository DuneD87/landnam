# game_manager.gd
extends Node

const SAVE_PATH := "user://savegame.save"
const WORLD_SCENE := "res://scenes/World.tscn"
const MENU_SCENE := "res://scenes/MainMenu.tscn"

var save_data: Dictionary = {}

func new_game() -> void:
	# Limpia datos previos y carga el mundo desde cero
	save_data = {}
	get_tree().change_scene_to_file(WORLD_SCENE)

func save_game() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		push_warning("No se encontró el jugador para guardar.")
		return

	save_data = {
		"position": {
			"x": player.global_position.x,
			"y": player.global_position.y,
			"z": player.global_position.z,
		},
		"rotation": {
			"x": player.global_rotation.x,
			"y": player.global_rotation.y,
			"z": player.global_rotation.z,
		},
	}

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data))
	file.close()
	print("Partida guardada.")

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		push_warning("No existe archivo de guardado.")
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json = JSON.new()
	var result = json.parse(file.get_as_text())
	file.close()

	if result != OK:
		push_error("Error parseando el archivo de guardado.")
		return

	save_data = json.data
	# Cargamos el mundo; el jugador leerá save_data al entrar
	get_tree().change_scene_to_file(WORLD_SCENE)

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func go_to_menu() -> void:
	save_data = {}
	get_tree().change_scene_to_file(MENU_SCENE)

func quit_game() -> void:
	get_tree().quit()
