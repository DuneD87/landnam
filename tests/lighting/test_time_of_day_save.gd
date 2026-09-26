extends Node

## La hora del día (posición del sol) sobrevive a guardar y cargar la partida.
##   godot --path . res://tests/lighting/test_time_of_day_save.tscn

const MAIN_SCENE := "res://scenes/maps/sun.tscn"
const SLOT := "test_time_of_day"


func _ready() -> void:
	var main: Node = load(MAIN_SCENE).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = main
	main.auto_rotate = false

	var failures := 0
	main.sun_azimuth_deg = -42.5
	main.sun_elevation_deg = 3.0
	var saved: bool = await GameManager.save_game(SLOT)
	if not saved:
		push_error("no se pudo guardar")
		failures += 1
	main.sun_azimuth_deg = 120.0
	main.sun_elevation_deg = 20.0
	if not GameManager.load_game(SLOT):
		push_error("no se pudo cargar")
		failures += 1
	if absf(main.sun_azimuth_deg - (-42.5)) > 0.001 or absf(main.sun_elevation_deg - 3.0) > 0.001:
		push_error("hora no restaurada: az=%f el=%f" % [main.sun_azimuth_deg, main.sun_elevation_deg])
		failures += 1
	GameManager.delete_save(SLOT)
	print("TIME OF DAY SAVE TESTS: %d failures (az=%.2f el=%.2f)" % [failures, main.sun_azimuth_deg, main.sun_elevation_deg])
	get_tree().quit(1 if failures else 0)
