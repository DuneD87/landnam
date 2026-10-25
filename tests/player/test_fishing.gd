extends Node3D

## godot --headless --path . res://tests/player/test_fishing.tscn
## Ciclo de entrada, peces reales, conservación, obstáculos y agua voxel cargada/ausente.
class FishingPlanet extends Node3D:
	var planet: Planet
	var water_sphere: OceanSystem

class OpenWater extends FishHabitat:
	func surface_radius(_point: Vector3) -> float:
		return 1000.0
	func terrain_is_clear(_point: Vector3, _clearance: float) -> bool:
		return true

class TestFishing extends PlayerFishing:
	var wet := true
	func _can_fish() -> bool:
		# El backend headless no captura el cursor; el resto del bloqueo se verifica aquí.
		return not _player.inventory_ui.visible and _player.combat.state == PlayerCombat.State.IDLE
	func _water_at(_point: Vector3) -> bool:
		return wet

var failures := 0
var checks := 0
var player: PlayerController
var fishing: TestFishing
var terrain: VoxelLodTerrain
var planet_host: FishingPlanet
var habitat: OpenWater
var rod_item: ItemData
var hook: ItemData
var bait: ItemData
var fish_item: ItemData


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var menu := Control.new()
	add_child(menu)
	var button := Button.new()
	button.name = "btnSaveGame"
	menu.add_child(button)
	button.owner = menu
	player = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.main_menu = menu
	add_child(player)
	player.fishing.free()
	fishing = TestFishing.new()
	player.add_child(fishing)
	fishing.setup(player)
	player.fishing = fishing
	player.free_flight_enabled = false
	player.input_enabled = true
	player.visible = true
	player.capture_mouse(true)
	GameManager.current_state = GameManager.State.PLAYING
	planet_host = FishingPlanet.new()
	terrain = VoxelLodTerrain.new()
	planet_host.planet = Planet.new(terrain)
	planet_host.planet.radius = 1020.0
	planet_host.planet.water_radius = 20.0
	planet_host.planet.has_water = true
	add_child(planet_host)
	planet_host.add_child(terrain)
	planet_host.planet.voxel_terrain = terrain
	player.planet = planet_host
	player.global_position = Vector3(0, 1001, 0)
	player.camera.global_basis = Basis.IDENTITY
	habitat = OpenWater.new()
	habitat.terrain = terrain
	rod_item = ItemCatalog.get_item(&"fishing_rod")
	hook = ItemCatalog.get_item(&"fishing_hook")
	bait = ItemCatalog.get_item(&"fishing_bait")
	fish_item = ItemCatalog.get_item(&"raw_fish")
	_check_resources()
	_reset()
	_check_input_and_cost()
	await _check_fish_cycle()
	_check_interruptions()
	await _check_cast_obstacle()
	await _check_real_water()
	fishing.cancel()
	GameManager.player = null
	player.planet = null
	player.free()
	planet_host.planet.free()
	planet_host.free()
	await get_tree().process_frame
	print("FISHING: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _press(action: StringName, pressed := true) -> bool:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return fishing.handle_input(event)


func _reset() -> void:
	fishing.cancel()
	player.inventory.clear()
	player.inventory.add_item(hook, 2)
	player.inventory.add_item(bait, 5)
	if player.combat.weapon() != rod_item:
		player.inventory.add_item(rod_item, 1)
		player._equip_from_hotbar(null, rod_item)
	fishing.wet = true
	player.capture_mouse(true)
	player.inventory_ui.close()
	player.combat.state = PlayerCombat.State.IDLE


func _check_resources() -> void:
	check(rod_item != null and hook != null and bait != null and fish_item != null, "catálogo de pesca completo")
	check(rod_item.tool_type == ItemData.ToolType.FISHING_ROD and not rod_item.is_melee()
		and not rod_item.is_ranged(), "la caña se equipa como herramienta de pesca")
	var rod := rod_item.get_trait(FishingRodTrait) as FishingRodTrait
	check(is_equal_approx(rod.distance_at(0), rod.min_distance)
		and is_equal_approx(rod.distance_at(100), rod.max_distance), "alcance acotado aunque se mantenga pulsado")
	for id in [&"fishing_rod", &"fishing_hook", &"fishing_bait"]:
		var found := false
		for recipe in Recipes.all():
			if recipe.result == id:
				found = true
				for ingredient: StringName in recipe.inputs:
					player.inventory.add_item(ItemCatalog.get_item(ingredient), recipe.inputs[ingredient])
				check(Recipes.craft(recipe, player.inventory) == 0, "se fabrica %s con sus materiales" % id)
		check(found, "hay receta de %s" % id)
	var cooking := fish_item.get_trait(CookableTrait) as CookableTrait
	check(cooking != null and ItemCatalog.get_item(cooking.result).get_trait(EdibleTrait) != null,
		"la captura se puede asar y comer")


func _check_input_and_cost() -> void:
	check(_press(&"attack_1") and fishing.state == PlayerFishing.State.CHARGING, "pulsar izquierdo muestra marcador")
	var near := fishing._float.global_position
	fishing._physics_process(10.0)
	check(fishing._float.global_position.distance_to(near) > 15.0
		and fishing._float.global_position.distance_to(player.global_position) < 22.1,
		"mantener desplaza el marcador hasta el máximo")
	check(player.inventory.get_item_count(bait) == 5, "apuntar no consume cebo")
	_press(&"attack_2")
	check(not fishing.is_active() and player.inventory.get_item_count(hook) == 2, "cancelar la carga conserva el aparejo")
	fishing.wet = false
	_press(&"attack_1")
	_press(&"attack_1", false)
	check(not fishing.is_active() and player.inventory.get_item_count(bait) == 5, "un destino seco no gasta cebo")
	fishing.wet = true
	_cast_waiting()
	check(fishing.state == PlayerFishing.State.WAITING and player.inventory.get_item_count(bait) == 4
		and player.inventory.get_item_count(hook) == 1, "soltar lanza y monta un anzuelo con un cebo")
	fishing._physics_process(10.0)
	check(fishing.state == PlayerFishing.State.WAITING and player.inventory.get_item_count(fish_item) == 0,
		"sin peces no hay picadas ni capturas")
	_press(&"attack_2")
	check(player.inventory.get_item_count(hook) == 2 and player.inventory.get_item_count(bait) == 4,
		"recoger devuelve el anzuelo una sola vez")
	fishing.cancel()
	check(player.inventory.get_item_count(hook) == 2, "cancelar otra vez no duplica anzuelos")
	player.inventory.remove_item(bait, 4)
	_press(&"attack_1")
	check(not fishing.is_active(), "sin cebo no comienza el lanzamiento")
	_reset()
	player.inventory.remove_item(hook, 2)
	_press(&"attack_1")
	check(not fishing.is_active() and player.inventory.get_item_count(bait) == 5, "sin anzuelo tampoco se gasta cebo")
	_reset()


func _cast_waiting() -> void:
	_press(&"attack_1")
	fishing._physics_process(0.7)
	_press(&"attack_1", false)
	for i in 60:
		fishing._physics_process(1.0 / 60.0)


func _new_fish(at: Vector3) -> AmbientFish:
	var fish: AmbientFish = load("res://scenes/animals/ambient_fish.tscn").instantiate()
	terrain.add_child(fish)
	fish.set_physics_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	fish.activate(at, habitat, rng)
	fish.set_physics_process(false)
	return fish


func _check_fish_cycle() -> void:
	_cast_waiting()
	var fish := _new_fish(fishing._float.hook.global_position + Vector3(5, -2, 0))
	var before := fish.global_position.distance_to(fishing._float.hook.global_position)
	fishing._physics_process(0.6)
	check(fish.follows_lure(fishing._float.hook), "el cebo atrae un pez que existe en el hábitat")
	var other := Node3D.new()
	add_child(other)
	check(not fish.can_follow_lure(other), "dos anzuelos no se disputan el mismo pez")
	other.free()
	for i in 240:
		await get_tree().physics_frame
		fish._swim(1.0 / 60.0)
	check(fish.active and fish.global_position.distance_to(fishing._float.hook.global_position) < before - 2.0,
		"el pez nada físicamente hasta el cebo sin teletransporte")
	# Extremos deterministas de la probabilidad: nunca y siempre.
	fishing._rod = fishing._rod.duplicate()
	fishing._rod.hook_chance = 0.0
	fish.global_position = fishing._float.hook.global_position
	fishing._update_bite(0.0)
	check(fishing.state == PlayerFishing.State.BITE, "al llegar pica antes de engancharse")
	fishing._elapsed = fishing._rod.bite_time
	fishing._update_bite(0.0)
	check(not fishing.is_active() and fish.active and player.inventory.get_item_count(fish_item) == 0,
		"con 0 % se come el cebo y queda libre")
	_reset()
	_cast_waiting()
	fish.global_position = fishing._float.hook.global_position
	fishing._update_bite(1.0)
	fishing._rod = fishing._rod.duplicate()
	fishing._rod.hook_chance = 1.0
	fishing._elapsed = fishing._rod.bite_time
	fishing._update_bite(0.0)
	check(fishing.state == PlayerFishing.State.HOOKED, "con 100 % se engancha tras picar")
	fishing._update_pose(0.2)
	fishing._float.present(0.1, false, true, false, true)
	var visual := player.combat.weapon_node() as FishingRodVisual
	check(visual != null and visual.tension > 0.4 and fishing._float._alert.visible,
		"la caña se dobla y el agua muestra una alerta")
	await _capture_if_requested()
	check(_press(&"attack_1") and fishing.state == PlayerFishing.State.REELING, "izquierdo recoge al engancharse")
	# El pez sigue nadando mientras la boya avanza hacia el jugador.
	for i in 1200:
		if not fishing.is_active():
			break
		await get_tree().physics_frame
		fish._swim(1.0 / 60.0)
		fishing._update_reel(1.0 / 60.0)
	check(not fishing.is_active() and not fish.active and player.inventory.get_item_count(fish_item) == 1,
		"recoger cerca entrega exactamente un pescado y retira al pez")
	check(player.inventory.get_item_count(hook) == 2, "la captura devuelve el anzuelo reutilizable")
	fish.free()
	_reset()
	_cast_waiting()
	fishing._float.global_position = fishing._surface_point(player.global_position + Vector3(0, 0, -4.5))
	fish = _new_fish(fishing._float.hook.global_position + Vector3(2.2, 0, 0))
	fish.follow_lure(fishing._float.hook)
	fishing._fish = fish
	fishing.state = PlayerFishing.State.REELING
	fishing._reel_held = true
	fishing.wet = false
	fishing._update_reel(0.1)
	check(fishing.is_active() and fish.active, "en la orilla la boya espera al pez que aún va detrás")
	fish.global_position = fishing._float.hook.global_position
	fishing._update_reel(0.1)
	check(not fishing.is_active() and player.inventory.get_item_count(fish_item) == 1,
		"cuando el pez alcanza la boya se recoge sin perderlo contra la ribera")
	fish.free()
	_reset()
	_cast_waiting()
	fish = _new_fish(fishing._float.hook.global_position)
	fish.follow_lure(fishing._float.hook)
	fishing._fish = fish
	fishing.state = PlayerFishing.State.HOOKED
	fishing._slack_left = 0.1
	fishing._update_reel(0.2)
	check(not fishing.is_active() and fish.active and not is_instance_valid(fish._fishing_lure),
		"si no se tira a tiempo escapa y vuelve a nadar")
	fish.deactivate()
	check(not fish.follows_lure(fishing._float), "el pool no conserva referencias al anzuelo")
	fish.free()
	var marine := AmbientMarineAnimal.new()
	check(not marine.can_be_fished(), "la caña no pesca tiburones ni ballenas")
	marine.free()
	await get_tree().physics_frame


func _check_interruptions() -> void:
	_reset()
	_cast_waiting()
	player.inventory_ui.open()
	fishing._physics_process(0.1)
	check(not fishing.is_active() and player.inventory.get_item_count(hook) == 2,
		"abrir inventario interrumpe y recupera el anzuelo")
	_reset()
	_cast_waiting()
	player.prepare_save()
	check(not fishing.is_active() and player.inventory.get_item_count(hook) == 2,
		"guardar resuelve el anzuelo antes de capturar el inventario")
	_reset()
	_cast_waiting()
	var sword := ItemCatalog.get_item(&"iron_sword")
	player.inventory.add_item(sword, 1)
	player._equip_from_hotbar(rod_item, sword)
	check(not fishing.is_active() and player.inventory.get_item_count(hook) == 2,
		"cambiar de herramienta cancela inmediatamente")
	_reset()
	_cast_waiting()
	var at := fishing._float.position
	terrain.position += Vector3(1500, -700, 300)
	check(fishing._float.position.is_equal_approx(at)
		and fishing._float.global_position.is_equal_approx(terrain.to_global(at)),
		"el marcador sigue al terreno cuando cambia el origen flotante")
	terrain.position = Vector3.ZERO
	fishing.cancel()
	# Inventario lleno: la devolución se conserva en el mundo.
	_reset()
	_cast_waiting()
	player.inventory.clear()
	var wood := ItemCatalog.get_item(&"wood_01")
	for i in player.inventory.max_slots:
		player.inventory.add_item_at(wood, wood.max_stack, i)
	var drops_before := get_tree().get_nodes_in_group(DroppedItem.GROUP).size()
	fishing.cancel()
	check(get_tree().get_nodes_in_group(DroppedItem.GROUP).size() == drops_before + 1,
		"si no cabe el anzuelo queda como objeto recuperable")
	DroppedItem.clear_all(get_tree())
	_reset()
	_cast_waiting()
	var fish := _new_fish(fishing._float.hook.global_position)
	fish.follow_lure(fishing._float.hook)
	fishing._fish = fish
	fish.free()
	fishing._scan_left = 0.0
	fishing._update_bite(0.1)
	check(fishing.state == PlayerFishing.State.WAITING and fishing._fish == null,
		"un pez eliminado por el mundo no deja una referencia inválida")
	fishing.cancel()
	_reset()
	_cast_waiting()
	player.combat.state = PlayerCombat.State.STAGGER
	fishing._physics_process(0.1)
	check(not fishing.is_active() and player.inventory.get_item_count(hook) == 2,
		"un golpe interrumpe la pesca y devuelve el anzuelo")
	_reset()
	_cast_waiting()
	var loot := player.leave_death_loot()
	check(not fishing.is_active() and loot != null and loot.inventory.get_item_count(hook) == 2,
		"al morir el anzuelo montado pasa al botín con el resto del equipo")
	if loot != null:
		loot.free()


func _check_real_water() -> void:
	var real := PlayerFishing.new()
	real._player = player
	real._terrain = terrain
	real._sea_radius = 1000.0
	check(not real._water_at(Vector3(0, 1000, 0)), "terreno sin cargar nunca se acepta como agua")
	var generator := VoxelGeneratorFlat.new()
	generator.height = 980.0
	terrain.generator = generator
	terrain.mesher = VoxelMesherTransvoxel.new()
	terrain.lod_count = 3
	terrain.view_distance = 128
	terrain.streaming_system = VoxelLodTerrain.STREAMING_SYSTEM_CLIPBOX
	var viewer := VoxelViewer.new()
	viewer.position = Vector3(0, 995, 0)
	viewer.view_distance = 128
	add_child(viewer)
	var loaded := false
	for i in 100:
		await get_tree().create_timer(0.05).timeout
		if real._water_at(Vector3(0, 1000, 0)):
			loaded = true
			break
	check(loaded, "agua profunda sobre terreno voxel cargado permite pescar")
	var rock := _obstacle(Vector3(0, 998.5, 0))
	await get_tree().physics_frame
	check(not real._water_at(Vector3(0, 1000, 0)), "un obstáculo bajo la boya impide lanzar ahí")
	rock.free()
	real._sea_radius = 982.0
	check(real._water_at(Vector3(0, 982, 0)), "dos metros de agua permiten pescar desde la orilla")
	real._sea_radius = 981.0
	check(not real._water_at(Vector3(0, 981, 0)), "un fondo demasiado somero no admite el anzuelo")
	real.free()
	viewer.queue_free()


func _obstacle(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 1.5
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = at
	return body


func _check_cast_obstacle() -> void:
	_reset()
	_press(&"attack_1")
	fishing._physics_process(0.8)
	_press(&"attack_1", false)
	var from := terrain.to_global(fishing._flight_local)
	var to := terrain.to_global(fishing._target_local)
	var rock := _obstacle(from.lerp(to, 0.5) + (to - terrain.global_position).normalized() * 3.0)
	await get_tree().physics_frame
	for i in 60:
		fishing._physics_process(1.0 / 60.0)
	check(not fishing.is_active() and player.inventory.get_item_count(hook) == 2,
		"el arco de lanzamiento choca con obstáculos y devuelve el anzuelo")
	rock.free()


func _capture_if_requested() -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	get_window().size = Vector2i(1440, 900)
	player.player_model.visible = true
	player.hotbar.hide()
	player.debug_stats.hide()
	player.rotate_toward_direction(Vector3.FORWARD, 1.0, 1.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.8
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.10, 0.17, 0.22)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.9, 1.0)
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	water.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.07, 0.30, 0.38)
	material.roughness = 0.35
	water.material_override = material
	water.position.y = 1000
	add_child(water)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = player.global_position + Vector3(5, 4, 5)
	cam.look_at(player.global_position + Vector3(0, 0, -3.5))
	cam.make_current()
	for i in 5:
		player.animation_controller.animation_tree.advance(1.0 / 60.0)
		player.combat.pose._apply()
		fishing._float.draw_line(fishing._tip(), false)
		fishing._update_hud()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/fishing")
	get_viewport().get_texture().get_image().save_png("res://build/fishing/hooked.png")
	cam.free()
	water.free()
	environment.free()
	sun.free()
