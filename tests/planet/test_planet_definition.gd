extends Node

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	for name in ["earth", "moon"]:
		var path := "res://data/planet/planet_%s.json" % name
		var json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var parser := PlanetParser.new(null)
		parser.load_config(path)
		var terrain := VoxelLodTerrain.new()
		var world := Node3D.new()
		world.add_child(terrain)
		var planet := Planet.new(terrain)
		var loader: Node = load("res://scripts/planet/planet_loader.gd").new()
		loader.planet = planet
		loader._copy_parsed_data(parser)
		check(planet.definition == parser.definition, "%s: el cargador comparte la definición" % name)
		check(planet.radius == float(json.terrain_settings.radius), "%s: se conserva el radio" % name)
		check(planet.water_radius == float(json.terrain_settings.water_level), "%s: se conserva el nivel del agua" % name)
		check(planet.definition.biome_count == int(json.biome_settings.biome_count), "%s: se conservan los biomas" % name)
		check(planet.definition.textures.size() == json.biome_settings.textures.size(), "%s: se cargan las texturas" % name)
		planet.setup_shader_parameters()
		check(is_equal_approx(planet.shader_material.get_shader_parameter("slope_threshold"),
			float(json.biome_settings.get("slope_threshold", 0.35))), "%s: el shader recibe la pendiente" % name)
		parser.free()
		check(not planet.definition.textures.is_empty(), "%s: la definición sobrevive al lector" % name)
		loader.free()
		world.free()
		planet.free()
	var first := PlanetDefinition.new()
	var second := PlanetDefinition.new()
	first.max_heights.append(123.0)
	first.climate_settings["enabled"] = true
	check(second.max_heights.is_empty() and second.climate_settings.is_empty(),
		"Los planetas no comparten arrays o diccionarios por defecto")
	print("PLANET DEFINITION: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
