extends Node3D

## Muerte real, último lecho, pérdida de la tumba anterior y guardado con origen flotante.
## godot --headless --path . res://tests/player/test_respawn.tscn

class GroundedPlayer extends PlayerController:
	func is_ground_ready() -> bool:
		return true


var failures := 0
var checks := 0
var player: PlayerController
var origin: FloatingOrigin
var world: Node3D
var bed: Bedroll
var slot_name := "test_respawn_%d" % Time.get_ticks_usec()


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _bags() -> Array[Node]:
	return get_tree().get_nodes_in_group(DeathLoot.GROUP).filter(
		func(node: Node) -> bool: return not node.is_queued_for_deletion())


func _run() -> void:
	var menu := Control.new()
	add_child(menu)
	for button_name in ["btnSaveGame", "btnStartGame"]:
		var button := Button.new()
		button.name = button_name
		menu.add_child(button)
		button.owner = menu
	var sun := Node3D.new()
	add_child(sun)
	sun.set_script(load("res://scripts/planet/sun_controller.gd"))
	sun.set_process(false)
	sun.add_to_group("sun_controller")
	var marker := Marker3D.new()
	marker.name = "SpawnPoint"
	add_child(marker)
	var planets := Node3D.new()
	add_child(planets)
	world = Node3D.new()
	planets.add_child(world)
	origin = FloatingOrigin.new()
	add_child(origin)
	origin.set_physics_process(false)
	player = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.set_script(GroundedPlayer)
	player.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.main_menu = menu
	player.spawn_point = marker
	add_child(player)
	origin._player = player
	origin._planets = planets
	player.combat.hud.process_mode = Node.PROCESS_MODE_ALWAYS
	player.free_flight_enabled = false
	player.collision_model.disabled = false
	player.input_enabled = true
	player.visible = true
	GameManager.current_state = GameManager.State.PLAYING

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.velocity = Vector3.DOWN
	player.move_and_slide()
	check(player.is_on_floor(), "el jugador real está sobre suelo seco")
	player.combat.restore_respawn_data({})
	var initial := player.global_transform

	bed = load("res://scenes/world/bedroll.tscn").instantiate()
	bed.position.x = 1.5
	world.add_child(bed)
	player.resting.open(bed)
	check(player.combat.respawn_bed_id == "", "abrir el panel no fija un lecho sin usarlo")
	check(player.resting.start_sleep(), "se puede dormir en el primer lecho")
	check(player.combat.respawn_bed_id == bed.entity_id, "dormir fija el lecho antes de completar la noche")
	player.resting.close(false)
	var second: Bedroll = load("res://scenes/world/bedroll.tscn").instantiate()
	second.position.x = -1.5
	world.add_child(second)
	player.resting.open(second)
	check(player.resting.start_sleep(), "se puede usar otro lecho")
	player.resting.close(false)
	check(player.combat.respawn_bed_id == second.entity_id, "prevalece el último lecho usado")
	second.queue_free()
	check(player.combat._respawn_transform().is_equal_approx(initial),
		"retirar el último lecho vuelve al inicio aunque quede otro lecho")
	await get_tree().process_frame
	player.resting.open(bed)
	check(player.resting.start_sleep(), "el primer lecho se puede volver a fijar")
	player.resting.close(false)

	var pack := ItemCatalog.get_item(&"hide_backpack")
	var axe := ItemCatalog.get_item(&"stone_axe_01")
	var torch := ItemCatalog.get_item(&"torch_01")
	var stone := ItemCatalog.get_item(&"stone_01")
	var sword := ItemCatalog.get_item(&"iron_sword")
	var armor := ItemCatalog.get_item(&"fur_loincloth")
	var slots := player.character_window
	slots.equip_item(slots.get_slot(ItemData.ArmorSlot.BACK), InventoryItem.new(pack))
	slots.equip_item(slots.get_slot(ItemData.ArmorSlot.RIGHT_HAND), InventoryItem.new(axe))
	slots.equip_item(slots.get_slot(ItemData.ArmorSlot.OFFHAND), InventoryItem.new(torch))
	slots.equip_item(slots.get_slot(ItemData.ArmorSlot.LEGS), InventoryItem.new(armor))
	var filled_slots := player.inventory.max_slots
	for i in filled_slots:
		player.inventory.items[i] = InventoryItem.new(sword)
	player.inventory.items[0] = InventoryItem.new(stone, 17)
	player.inventory.inventory_changed.emit()
	player.hotbar.assign_to_slot(0, axe)
	player.hotbar.restore_selection(0)
	# El cursor también pertenece al jugador cuando le matan.
	player.inventory_ui._pickup_from(player.inventory, 0)
	var died_at := Vector3(12, 0, 3)
	player.global_position = died_at
	player.health_component.take_damage(10000.0)
	check(player.combat.is_dead() and _bags().size() == 1, "la muerte genera exactamente una bolsa")
	var bag := _bags()[0] as DeathLoot
	check(bag.global_position.is_equal_approx(died_at), "el botín queda en el lugar de la muerte")
	check(bag.inventory.get_item_count(stone) == 17 and player.inventory_ui.floating_item == null,
		"los objetos del cursor entran en la bolsa sin perder unidades")
	check(bag.inventory.get_item_count(sword) == filled_slots - 1 \
		and bag.inventory.get_item_count(pack) == 1 and bag.inventory.get_item_count(axe) == 1 \
		and bag.inventory.get_item_count(torch) == 1 and bag.inventory.get_item_count(armor) == 1,
		"se conserva toda la mochila llena y el equipo de ambas manos")
	check(player.inventory.get_free_slots() == player.inventory.max_slots \
		and player.inventory.max_slots == slots.inventory_capacity.base_slots \
		and slots.get_equipped_item(ItemData.ArmorSlot.BACK) == null,
		"el personaje queda vacío y vuelve a la capacidad sin mochila")
	player.combat._on_died()
	check(_bags().size() == 1, "notificar otra vez la misma muerte no duplica el botín")
	await player.combat._respawn()
	check(player.global_transform.is_equal_approx(bed.respawn_transform()) \
		and not player.health_component.is_dead and player.input_enabled,
		"el respawn real devuelve al lecho con vida y controles")
	check(player.inventory.get_free_slots() == player.inventory.max_slots \
		and player._get_right_hand_item() == null and player.hotbar.slots[0].assigned_data == axe,
		"reaparecer no regala objetos y conserva los accesos de la barra")

	player.global_position = died_at
	check(player.survival.open_nearby_death_loot(), "E abre los objetos propios sin cuchillo")
	player.inventory_ui._take_loot(0)
	check(player.inventory.get_item_count(pack) == 1, "la mochila se ofrece primero para recuperar capacidad")
	player.inventory_ui._take_all_loot()
	check(bag.inventory.get_free_slots() < bag.inventory.max_slots \
		and player.inventory.is_full(), "lo que no cabe al recuperar todo permanece en la bolsa")
	player.global_position += Vector3(10, 0, 0)
	player.survival._process(0.0)
	check(player.inventory_ui.open_loot_inventory() == null, "alejarse cierra la recuperación")

	# Lo ya recuperado cae de nuevo; lo que seguía en la tumba anterior se pierde.
	var recovered_swords := player.inventory.get_item_count(sword)
	var lost_swords := bag.inventory.get_item_count(sword)
	var previous_bag_id := bag.entity_id
	player.health_component.take_damage(10000.0)
	check(_bags().size() == 1 and bag.is_queued_for_deletion() \
		and not bag.is_in_group(GameManager.SAVEABLE_GROUP),
		"volver a morir retira la tumba anterior del mundo y del guardado inmediatamente")
	var latest := _bags()[0] as DeathLoot
	check(latest.entity_id != previous_bag_id and lost_swords > 0 \
		and latest.inventory.get_item_count(sword) == recovered_swords \
		and latest.inventory.get_item_count(sword) + lost_swords == filled_slots - 1 \
		and latest.inventory.get_item_count(axe) == 0 and latest.inventory.get_item_count(torch) == 0 \
		and latest.inventory.get_item_count(armor) == 0,
		"la nueva tumba conserva solo lo recuperado y pierde definitivamente el resto del equipo")
	await player.combat._respawn()
	var bag_ids: Array[String] = []
	var saved_items := {}
	for node: DeathLoot in _bags():
		bag_ids.append(node.entity_id)
		saved_items[node.entity_id] = node.inventory.get_save_data()
	check(await GameManager.save_game(slot_name), "se guardan el último lecho y la única tumba recuperable")
	var bed_id := bed.entity_id
	var canonical_bed := bed.global_position
	for node: DeathLoot in _bags():
		node.free()
	bed.free()
	origin._rebase(Vector3(2500, 100, -700))
	check(GameManager.load_game(slot_name), "se restaura la partida con otro origen flotante")
	await get_tree().create_timer(0.4).timeout
	bed = Bedroll.find_by_id(get_tree(), bed_id)
	check(bed != null and player.combat.respawn_bed_id == bed_id \
		and origin.to_canonical(bed.global_position).is_equal_approx(canonical_bed),
		"el lecho recreado conserva su identidad y posición canónica")
	check(_bags().size() == 1, "cargar recupera solo la última tumba y no resucita la anterior")
	check(GameManager.load_game(slot_name) and _bags().size() == 1,
		"cargar otra vez sobre la tumba existente no la duplica")
	await get_tree().create_timer(0.4).timeout
	for node: DeathLoot in _bags():
		check(node.entity_id in bag_ids and node.inventory.get_save_data() == saved_items[node.entity_id],
			"el contenido se restaura sin pérdida ni duplicación")
	check(player.combat._respawn_transform().is_equal_approx(bed.respawn_transform()),
		"el respawn reconoce el lecho recreado después de un rebase")
	bed.queue_free()
	check(origin.to_canonical(player.combat._respawn_transform().origin).is_equal_approx(initial.origin),
		"el punto inicial también sobrevive al guardado y al cambio de origen")

	# Recuperar toda una bolsa, con capacidad suficiente, la retira de forma diferida.
	player.inventory.max_slots = 100
	for node: DeathLoot in _bags():
		for i in node.inventory.max_slots:
			node.inventory.transfer_to(player.inventory, i)
	await get_tree().process_frame
	await get_tree().process_frame
	check(_bags().is_empty(), "las bolsas desaparecen al recuperar su último objeto")
	check(player.inventory.get_item_count(stone) == 17 \
		and player.inventory.get_item_count(sword) == recovered_swords \
		and player.inventory.get_item_count(pack) == 1 and player.inventory.get_item_count(axe) == 0 \
		and player.inventory.get_item_count(torch) == 0 and player.inventory.get_item_count(armor) == 0,
		"recuperar tras cargar conserva lo salvado sin devolver los objetos perdidos por el castigo")
	# Sin recuperar nada: una muerte con inventario vacío también debe perder la tumba guardada.
	player.health_component.take_damage(10000.0)
	await player.combat._respawn()
	check(_bags().size() == 1 and await GameManager.save_game(slot_name),
		"se guarda una tumba pendiente mientras el jugador vuelve a por ella sin objetos")
	check(GameManager.load_game(slot_name), "se carga la tumba pendiente antes de aplicar el castigo")
	await get_tree().create_timer(0.4).timeout
	player.health_component.take_damage(10000.0)
	check(_bags().is_empty() and player.inventory.get_free_slots() == player.inventory.max_slots,
		"morir de camino sin objetos destruye la tumba cargada y no deja una bolsa vacía")
	check(await GameManager.save_game(slot_name) and GameManager.load_game(slot_name) \
		and _bags().is_empty(), "guardar y cargar después del castigo no recupera los objetos destruidos")
	await get_tree().create_timer(0.4).timeout
	# Cargar durante un fundido debe cancelar esa reaparición, sin tocar el equipo restaurado.
	player.inventory.add_item(axe, 1)
	player.hotbar.select_slot(0)
	check(player.combat.weapon() == axe and player.combat.weapon_node() != null,
		"el arma está equipada antes de iniciar el caso de carga durante el respawn")
	player.global_position += Vector3(9, 0, 0)
	var loaded_position := player.global_position
	check(await GameManager.save_game(slot_name), "se guarda equipo y posición antes de probar una carga durante el respawn")
	player.health_component.take_damage(10000.0)
	player.combat._respawn()
	await get_tree().create_timer(0.2).timeout
	check(GameManager.load_game(slot_name), "se carga una partida durante el fundido a negro")
	await get_tree().create_timer(2.6).timeout
	check(player.global_position.is_equal_approx(loaded_position),
		"cargar tras un rebase conserva la posición y cancela el teletransporte del respawn anterior")
	check(player.combat.weapon() == axe \
		and player.combat.weapon_node() != null and not player.combat._respawning,
		"el respawn cancelado conserva el arma recién restaurada")
	check(not player.combat.hud._fade.visible, "cargar durante el respawn no deja la pantalla negra")
	GameManager.delete_save(slot_name)
	GameManager.player = null
	WorldTime.reset()
	player.queue_free()
	await get_tree().process_frame
	print("RESPAWN: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
