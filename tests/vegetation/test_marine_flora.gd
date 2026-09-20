extends Node

## Comprueba el cableado de la flora sumergida: mallas horneadas, escenas de item y
## los generadores del planeta, que tienen que quedar POR DEBAJO del nivel del mar.

const IDS := ["seagrass", "kelp", "sea_fan", "coral"]
const GENERATORS := ["seagrass_generator", "kelp_generator", "sea_fan_generator", "coral_generator"]

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func _run() -> void:
	var json := JSON.new()
	_check(json.parse(FileAccess.get_file_as_string("res://data/planet/planet_earth.json")) == OK,
		"El JSON del planeta sigue siendo válido")
	var config: Dictionary = json.data
	var vegetation: Dictionary = config.get("vegetation_settings", {})
	var sea_level: float = float(config["terrain_settings"]["radius"]) - float(config["terrain_settings"]["water_level"])
	_test_meshes()
	_test_items(vegetation)
	_test_generators(vegetation, config, sea_level)
	print("MARINE FLORA TESTS: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)


func _test_meshes() -> void:
	for id in IDS:
		var mesh: ArrayMesh = load("res://data/vegetation/marine/%s.res" % id)
		_check(mesh != null and mesh.get_surface_count() == 1, "%s: una sola superficie horneada" % id)
		if mesh == null:
			continue
		var material := mesh.surface_get_material(0) as ShaderMaterial
		# El planeta recoge los materiales de item por surface_get_material: sin esto la
		# planta se instancia sin material y el vaivén no existe.
		_check(material != null and material.shader != null, "%s: lleva su material dentro de la malla" % id)
		var bounds := mesh.get_aabb()
		_check(bounds.position.y > -0.1 and bounds.size.y > 0.3,
			"%s: arraiga en Y=0 y tiene altura (%.2f m)" % [id, bounds.size.y])
		if material != null:
			var height: float = material.get_shader_parameter(&"plant_height")
			_check(absf(height - bounds.size.y) < bounds.size.y * 0.5,
				"%s: la altura del shader concuerda con la malla" % id)


func _test_items(vegetation: Dictionary) -> void:
	var found: Array = []
	for item in vegetation.get("items", []):
		var scene_path: String = str(item.get("scene", ""))
		if not ("vegetation/marine/" in scene_path):
			continue
		found.append(scene_path.get_file().get_basename())
		_check(ResourceLoader.exists(scene_path), "%s: la escena del item existe" % scene_path.get_file())
		var scene: PackedScene = load(scene_path)
		var node := scene.instantiate()
		# _build_item_shared_data exige que el primer hijo sea MeshInstance3D.
		_check(node.get_child_count() > 0 and node.get_child(0) is MeshInstance3D,
			"%s: su primer hijo es un MeshInstance3D" % scene_path.get_file())
		node.free()
	found.sort()
	var expected := IDS.duplicate()
	expected.sort()
	_check(found == expected, "Las cuatro especies están dadas de alta como items")


func _test_generators(vegetation: Dictionary, config: Dictionary, sea_level: float) -> void:
	var terrain := VoxelLodTerrain.new()
	var planet = preload("res://scripts/planet/planet.gd").new(terrain)
	planet.radius = float(config["terrain_settings"]["radius"])
	var seen: Array = []
	for generator_config in vegetation.get("generators", []):
		if not (generator_config["name"] in GENERATORS):
			continue
		seen.append(generator_config["name"])
		var built = planet._build_generator(generator_config, vegetation["hemisphere_graph_function"], 0)
		_check(built != null and built.max_height < sea_level,
			"%s: su franja entera queda bajo el agua (hasta %.0f m de profundidad)" % [
				generator_config["name"], sea_level - built.min_height])
		# El ruido es lo que agrupa las plantas en manchas en vez de repartirlas parejas.
		_check(built != null and built.noise != null, "%s: tiene ruido de parcheo" % generator_config["name"])
	seen.sort()
	var expected := GENERATORS.duplicate()
	expected.sort()
	_check(seen == expected, "Los cuatro generadores marinos están definidos")
	planet.free()
	terrain.free()
