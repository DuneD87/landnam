extends Node3D

## godot --headless --path . res://tests/fauna/test_shore_fish.tscn
## Orillas con terreno voxel real: el spawner de producción tiene que poblar el agua
## que se está mirando y una caña debe capturar uno de esos peces, sin inyectarlo.
class BankPlayer extends PlayerController:
	func is_mouse_captured() -> bool:
		return true # El backend headless no captura el cursor.

class WaterPlanet extends Node3D:
	var planet: Planet
	var water_sphere: OceanSystem
	var world_map: PlanetWorldMap

const RADIUS := 1000.0
var failures := 0
var checks := 0
var player: PlayerController
var host: WaterPlanet
var terrain: VoxelLodTerrain
var viewer: VoxelViewer
var voxels: VoxelToolLodTerrain
var fishing: PlayerFishing
var rod: FishingRodTrait


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	var menu := Control.new()
	add_child(menu)
	var button := Button.new()
	button.name = "btnSaveGame"
	menu.add_child(button)
	button.owner = menu
	player = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.set_script(BankPlayer)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.main_menu = menu
	add_child(player)
	check(player.fishing != null and player.combat != null, "sistemas del jugador inicializados")
	if player.fishing == null or player.combat == null:
		get_tree().quit(1)
		return
	player.free_flight_enabled = false
	player.input_enabled = true
	player.visible = true
	GameManager.current_state = GameManager.State.PLAYING
	host = WaterPlanet.new()
	add_child(host)
	terrain = VoxelLodTerrain.new()
	var generator := VoxelGeneratorFlat.new()
	generator.height = 1004.0
	terrain.generator = generator
	terrain.mesher = VoxelMesherTransvoxel.new()
	terrain.lod_count = 3
	terrain.view_distance = 128
	terrain.streaming_system = VoxelLodTerrain.STREAMING_SYSTEM_CLIPBOX
	host.add_child(terrain)
	host.planet = Planet.new(terrain)
	host.planet.radius = 1020.0
	host.planet.water_radius = 20.0
	host.planet.has_water = true
	host.water_sphere = OceanSystem.new()
	host.water_sphere.radius = RADIUS
	var material := load("res://data/resources/WaterSphere_material.tres").duplicate() as ShaderMaterial
	for key in [&"wave_amplitude", &"wave_calm_amplitude", &"shore_amplitude"]:
		material.set_shader_parameter(key, 0.0)
	host.water_sphere.quadtree_material = material
	host.world_map = PlanetWorldMap.new()
	host.add_child(host.world_map)
	host.world_map._center_node = terrain
	host.world_map.map = _map()
	player.planet = host
	player.global_position = Vector3(0, 1001, 0)
	viewer = VoxelViewer.new()
	viewer.position = Vector3(0, 1000, 0)
	viewer.view_distance = 128
	add_child(viewer)
	voxels = terrain.get_voxel_tool() as VoxelToolLodTerrain
	voxels.channel = VoxelBuffer.CHANNEL_SDF
	var loaded := false
	for i in 100:
		await get_tree().create_timer(0.05).timeout
		loaded = voxels.is_area_editable(AABB(Vector3(-40, 990, -40), Vector3(80, 20, 80)))
		if loaded:
			break
	check(loaded, "terreno de las orillas cargado a LOD 0")
	if loaded:
		await _check_terrain_clearance()
		var item := ItemCatalog.get_item(&"fishing_rod")
		player.inventory.add_item(item, 1)
		player._equip_from_hotbar(null, item)
		fishing = player.fishing
		rod = item.get_trait(FishingRodTrait) as FishingRodTrait
		var chance := rod.hook_chance
		rod.hook_chance = 1.0 # La probabilidad se cubre por separado en test_fishing.
		await _case("costa", WorldMapData.WaterType.SEA, false)
		await _case("lago", WorldMapData.WaterType.LAKE, false)
		await _case("charca sin etiqueta", -1, false)
		await _case("río estrecho", WorldMapData.WaterType.SEA, true)
		rod.hook_chance = chance
	GameManager.player = null
	player.planet = null
	player.free()
	host.planet.free()
	host.water_sphere.free()
	host.free()
	viewer.free()
	await get_tree().process_frame
	print("SHORE FISH: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _check_terrain_clearance() -> void:
	voxels.mode = VoxelTool.MODE_REMOVE
	voxels.do_box(Vector3i(-38, 990, -38), Vector3i(38, 1008, 38))
	await get_tree().create_timer(0.3).timeout
	var habitat := FishHabitat.new()
	habitat.setup(terrain, host.water_sphere, host.world_map)
	var general := WaterFaunaHabitat.new()
	general.setup(terrain, host.water_sphere, host.world_map)
	var point := Vector3(0, 999, 0)
	check(habitat.terrain_is_clear(point, AmbientFish.CLEARANCE) and general.terrain_is_clear(point, 0.35),
		"el agua libre admite el volumen del pez")
	voxels.mode = VoxelTool.MODE_ADD
	voxels.do_box(Vector3i(-1, 995, -12), Vector3i(1, 1005, 12))
	check(not habitat.terrain_is_clear(point, AmbientFish.CLEARANCE) and not general.terrain_is_clear(point, 0.35),
		"una pared editada invalida inmediatamente el agua antes libre")
	voxels.mode = VoxelTool.MODE_REMOVE
	voxels.do_box(Vector3i(-2, 994, -13), Vector3i(2, 1006, 13))
	check(habitat.terrain_is_clear(point, AmbientFish.CLEARANCE) and general.terrain_is_clear(point, 0.35),
		"quitar la pared vuelve a permitir el paso sin datos de terreno antiguos")
	var shift := Vector3(4000, -2000, 3000)
	terrain.position += shift
	check(habitat.terrain_is_clear(point + shift, AmbientFish.CLEARANCE) and general.terrain_is_clear(point + shift, 0.35),
		"el descarte de terreno sigue al planeta tras un rebase")
	terrain.position -= shift
	check(not habitat.terrain_is_clear(Vector3(400, 999, 0), AmbientFish.CLEARANCE)
		and not general.terrain_is_clear(Vector3(400, 999, 0), 0.35),
		"el descarte rápido no confunde terreno sin cargar con agua libre")


func _map() -> WorldMapData:
	var map := WorldMapData.new()
	map.size = Vector2i(64, 32)
	map.radius = RADIUS
	map.sea_level_radius = RADIUS
	map.has_water = true
	map.heights.resize(64 * 32)
	map.heights.fill(-3.0)
	map.body_ids.resize(map.heights.size())
	map.body_ids.fill(0)
	map.bodies = [{"type": WorldMapData.WaterType.SEA}]
	return map


func _case(label: String, water_type: int, river: bool) -> void:
	fishing.cancel()
	player.inventory.clear()
	player.inventory.add_item(ItemCatalog.get_item(&"fishing_hook"), 1)
	player.inventory.add_item(ItemCatalog.get_item(&"fishing_bait"), 1)
	voxels.mode = VoxelTool.MODE_REMOVE
	voxels.do_box(Vector3i(-38, 995, -38), Vector3i(38, 1008, 38))
	voxels.mode = VoxelTool.MODE_ADD
	voxels.do_box(Vector3i(-38, 995, -38), Vector3i(38, 1001, 38))
	voxels.mode = VoxelTool.MODE_REMOVE
	voxels.do_box(Vector3i(-4 if river else -32, 997, -34), Vector3i(4 if river else 32, 1008, 34 if river else -4))
	player.global_position = Vector3(7 if river else 0, 1001.5, 0)
	var target := Vector3(0, 1000, -8)
	player.camera.global_position = player.global_position + Vector3(0, 6, 6)
	player.camera.look_at(target)
	player.camera.make_current()
	host.world_map.map.body_ids.fill(-1 if water_type < 0 else 0)
	host.world_map.map.bodies[0].type = water_type
	var habitat := FishHabitat.new()
	habitat.setup(terrain, host.water_sphere, host.world_map)
	if river:
		habitat.rivers = {"radius": RADIUS, "hydro_size": Vector2i(2048, 1024),
			"seg": PackedFloat32Array([512, 10, 1536, 10, -3, -3, 4, 4])}
	await get_tree().create_timer(0.3).timeout
	var settings := load("res://data/fauna/coastal_fish.tres") as AmbientFaunaProfile
	var spawner := AmbientFaunaSpawner.new()
	spawner.setup(settings, habitat, player)
	terrain.add_child(spawner)
	spawner.set_physics_process(false)
	spawner._rng.seed = 71
	for i in 120:
		spawner.update_population()
	var fish: Array[AmbientFish] = []
	var in_view := 0
	var correct_species := true
	for animal in spawner._pool:
		if not animal.active:
			continue
		fish.append(animal as AmbientFish)
		animal.set_physics_process(false)
		in_view += int(spawner._in_view(animal.global_position))
		correct_species = correct_species and ((animal as AmbientFish).current_species.id == &"atun") == (not river and water_type == WorldMapData.WaterType.SEA)
	check(fish.size() >= 4 and fish.size() <= settings.population, "%s: %d peces generados cerca de la orilla" % [label, fish.size()])
	check(in_view > 0, "%s: aparecen peces en el agua que estamos mirando" % label)
	check(correct_species, "%s: especies adecuadas al agua real" % label)
	check(not habitat.is_spawn_valid(player.global_position - Vector3.UP * 2.0, settings.clearance), "%s: la ribera seca no admite peces" % label)
	check(not habitat.is_spawn_valid(Vector3(400, 999, 0), settings.clearance), "%s: no aparecen peces en vóxeles sin cargar" % label)
	# La caña de producción decide si el agua es válida y selecciona un pez del pool.
	player.camera.global_basis = Basis.looking_at(target - player.global_position, Vector3.UP)
	player.combat.pose._apply()
	_press(true)
	check(fishing.state == PlayerFishing.State.CHARGING, "%s: se puede preparar la caña desde tierra" % label)
	fishing._physics_process(0.55)
	_press(false)
	check(fishing.state == PlayerFishing.State.CASTING, "%s: se lanza en agua de tres metros de profundidad" % label)
	print(label, " · lanzamiento: ", fishing._flight_local, " -> ", fishing._target_local)
	var last_state := fishing.state
	for tick in 1800:
		await get_tree().physics_frame
		for animal in fish:
			if animal.active:
				animal._physics_process(1.0 / 60.0)
		fishing._physics_process(1.0 / 60.0)
		if fishing.state == PlayerFishing.State.HOOKED:
			_press(true)
		if fishing.state != last_state:
			print(label, " · tick ", tick, " · estado ", last_state, " -> ", fishing.state)
			last_state = fishing.state
		if not fishing.is_active():
			break
	print(label, " · estado final: ", fishing.state, " · ", player.hotbar._notice.text)
	check(player.inventory.get_item_count(ItemCatalog.get_item(&"raw_fish")) == 1,
		"%s: un pez generado por el spawner pica y se recoge con la caña" % label)
	check(player.inventory.get_item_count(ItemCatalog.get_item(&"fishing_hook")) == 1,
		"%s: la captura recupera el anzuelo" % label)
	check(fish.any(func(animal: AmbientFish) -> bool: return animal.active and animal._spawn_fade >= 1.0),
		"%s: los peces terminan el fundido y siguen nadando en aguas someras" % label)
	fishing.cancel()
	spawner.free()
	await get_tree().process_frame


func _press(pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = &"attack_1"
	event.pressed = pressed
	fishing.handle_input(event)
