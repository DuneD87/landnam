extends Node3D

## Equipo persistente, transporte, cambios de herramienta, conservación y partidas antiguas.
## godot --headless --path . res://tests/player/test_weapon_loadout.tscn
class GroundedPlayer extends PlayerController:
	func is_ground_ready() -> bool:
		return true

var player: PlayerController
var failures := 0
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _count(data: ItemData) -> int:
	var count := player.inventory.get_item_count(data)
	for slot: EquipmentSlot in player.character_window.equipment_slots.values():
		if slot.has_item() and slot.equipped_item.data.id == data.id:
			count += slot.equipped_item.quantity
	return count


func _run() -> void:
	var menu := Control.new()
	add_child(menu)
	for button_name in ["btnSaveGame", "btnStartGame"]:
		var button := Button.new()
		button.name = button_name
		menu.add_child(button)
		button.owner = menu
	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	add_child(spawn)
	player = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.set_script(GroundedPlayer)
	player.main_menu = menu
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	GameManager.current_state = GameManager.State.PLAYING
	player.inventory.clear()
	var sword := ItemCatalog.get_item(&"iron_sword")
	var greatsword := ItemCatalog.get_item(&"greatsword")
	var bow := ItemCatalog.get_item(&"hunting_bow")
	var pick := ItemCatalog.get_item(&"stone_pickaxe_01")
	var hammer := ItemCatalog.get_item(&"stone_hammer_01")
	var shield := ItemCatalog.get_item(&"heater_shield")
	for data in [sword, greatsword, bow, pick, hammer, shield]:
		player.inventory.add_item(data, 1)
	for i in 5:
		player.hotbar.assign_to_slot(i, [sword, pick, greatsword, bow, hammer][i])
	player.hotbar.select_slot(0)
	var primary := player.character_window.get_slot(ItemData.ArmorSlot.PRIMARY)
	var tool := player.character_window.get_slot(ItemData.ArmorSlot.RIGHT_HAND)
	var sword_node: Node3D = player.combat.weapon_node()
	check(primary.has_item() and player._get_right_hand_item() == sword, "el arma tiene su hueco propio y se empuña")
	player._on_hotbar_offhand_toggled(shield)
	check(player.combat.pose.shield_on and player.combat._guard_item() == shield, "con espada el escudo va al brazo y bloquea")
	player.hotbar.select_slot(1)
	check(primary.equipped_item.data == sword and tool.equipped_item.data == pick \
		and player._get_right_hand_item() == pick, "usar el pico conserva equipada la espada")
	check(sword_node.get_parent() == player.loadout.primary_carry and sword_node.visible \
		and player.loadout.primary_carry.bone_name == HumanRig.HIPS, "la misma espada queda visible en la cintura")
	player.hotbar.select_slot(0)
	check(player.combat.weapon_node() == sword_node and not player.loadout.visuals[ItemData.ArmorSlot.RIGHT_HAND].visible,
		"volver al arma reutiliza su modelo y guarda la herramienta")
	for i in 12:
		player.loadout.toggle_weapon()
	check(_count(sword) == 1 and _count(pick) == 1, "sacar y guardar repetidamente conserva las unidades")
	player.loadout.toggle_weapon()
	check(not player.right_hand_equipped and sword_node.visible and not player.combat.pose.shield_on \
		and player.combat._shield_node.visible and player.combat._guard_item() == null,
		"guardados, espada y escudo se ven pero no atacan ni bloquean")
	player.hotbar.select_slot(2)
	check(player.combat._shield_node.get_parent() == player.combat._shield_carry \
		and not player.combat.pose.shield_on and player.combat._guard_item() == greatsword,
		"el espadón deja el escudo a la espalda y usa su propia guardia")
	player.loadout.toggle_weapon()
	check(player.loadout.primary_carry.bone_name == HumanRig.SPINE2, "el espadón guardado sigue el torso")
	_check_back_carry()
	player.hotbar.select_slot(3)
	check(not player.combat.pose.shield_on and player.combat._guard_item() == null, "con arco el escudo transportado no bloquea")
	player.loadout.toggle_weapon()
	check(player.loadout.primary_carry.get_child_count() == 1 \
		and player.combat._quiver == null, "guardar el arco retira la flecha activa y deja su modelo en la espalda")
	player.hotbar.select_slot(4)
	check(player.building_system.build_mode and primary.equipped_item.data == bow, "el martillo permite construir manteniendo el arco equipado")
	player.character_window.refresh()
	check(player.character_window._dressed.get(ItemData.ArmorSlot.PRIMARY) is WeaponCarry \
		and player.character_window._dressed.get(ItemData.ArmorSlot.OFFHAND) is WeaponCarry,
		"el muñeco del inventario muestra arma y escudo transportados")
	var saved := player.get_save_data()
	player.restore_save_data(saved)
	check(_count(bow) == 1 and _count(hammer) == 1 and player._get_right_hand_item() == hammer \
		and player.building_system.build_mode, "cargar restaura arma transportada, herramienta activa y construcción")
	player.loadout.toggle_weapon()
	player.loadout.toggle_weapon()
	saved = player.get_save_data()
	player.restore_save_data(saved)
	check(not player.right_hand_equipped and player.loadout.primary_carry.get_child_count() == 1 \
		and player.combat._guard_item() == null, "cargar con las armas guardadas conserva ese estado")
	# La mochila llena no afecta a sacar/guardar ni a volver a una herramienta ya equipada.
	player.inventory.clear()
	var stone := ItemCatalog.get_item(&"stone_01")
	for i in player.inventory.max_slots:
		player.inventory.items[i] = InventoryItem.new(stone, stone.max_stack)
	for i in 4:
		player.loadout.toggle_weapon()
	player._equip_from_hotbar(null, hammer)
	check(_count(bow) == 1 and _count(hammer) == 1 and player._get_right_hand_item() == hammer \
		and player.inventory.is_full(), "con la mochila llena se conserva todo el equipo al alternar")
	# Si el arma entrante procede de un montón y no deja hueco, el intercambio debe cancelarse.
	var spear := ItemCatalog.get_item(&"spear")
	player.inventory.items[0] = InventoryItem.new(spear, 2)
	player._equip_from_hotbar(null, spear)
	check(primary.equipped_item.data == bow and _count(spear) == 2 and _count(bow) == 1,
		"un intercambio sin sitio para devolver el arco conserva ambos objetos")
	player.inventory.items[2] = InventoryItem.new(stone, 40)
	player.inventory.items[3] = InventoryItem.new(stone, 40)
	player._equip_from_hotbar(null, spear)
	check(primary.equipped_item.data == bow and _count(spear) == 2 and _count(bow) == 1,
		"los montones que podrían compactarse no se confunden con un hueco realmente libre")
	var torch := ItemCatalog.get_item(&"torch_01")
	player.inventory.items[1] = InventoryItem.new(torch, 2)
	player._on_hotbar_offhand_toggled(torch)
	check(player.character_window.get_equipped_item(ItemData.ArmorSlot.OFFHAND).data == shield \
		and _count(torch) == 2 and _count(shield) == 1,
		"una antorcha apilada no hace perder el escudo con el inventario lleno")
	# Partida anterior al nuevo hueco: solo arma en RIGHT_HAND, sin estado de presentación.
	saved = player.get_save_data()
	saved.equipment = {str(int(ItemData.ArmorSlot.RIGHT_HAND)): "iron_sword"}
	saved.erase("loadout")
	player.restore_save_data(saved)
	check(primary.has_item() and primary.equipped_item.data == sword and not tool.has_item() \
		and player._get_right_hand_item() == sword and _count(sword) == 1,
		"la partida antigua migra el arma sin duplicarla y la deja empuñada")
	# Entrada real del jugador: teclado y acción contextual de la cruceta.
	player.free_flight_enabled = false
	player.input_enabled = true
	player.mouse_captured = true
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	key.pressed = true
	player._input(key)
	check(not player.right_hand_equipped and player.hotbar.selected_index == -1,
		"R guarda el arma a través de la entrada del jugador")
	key.echo = true
	player._input(key)
	check(not player.right_hand_equipped, "la repetición del teclado no vuelve a sacar el arma")
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_DPAD_UP
	button.pressed = true
	player._input(button)
	check(player._get_right_hand_item() == sword and player.hotbar.selected_index == 0,
		"cruceta arriba saca el arma y restaura su selección sin transferir objetos")
	player.inventory_ui.open(InventoryUI.View.CHARACTER)
	key.echo = false
	player._input(key)
	check(player._get_right_hand_item() == sword, "R no cambia el arma con el inventario abierto")
	player.inventory_ui.close()
	player.inventory.clear()
	player.inventory.add_item(pick, 1)
	player._equip_from_hotbar(null, pick)
	var loot := player.leave_death_loot()
	check(loot.inventory.get_item_count(sword) == 1 and loot.inventory.get_item_count(pick) == 1 \
		and not primary.has_item() and not tool.has_item(),
		"la muerte deja una unidad del arma transportada y de la herramienta en el botín")
	player._clear_visual_equipment()
	check(player.loadout.visuals.is_empty() and player.combat.weapon_node() == null,
		"la limpieza de reaparición retira los modelos de ambas ranuras")
	GameManager.player = null
	player.queue_free()
	await get_tree().process_frame
	print("WEAPON LOADOUT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _check_back_carry() -> void:
	var skeleton: Skeleton3D = player.player_model.get_node("Armature/Skeleton3D")
	var rest := BodyMeasurements.rest_globals(skeleton)
	var to_model := player.player_model.global_transform.affine_inverse() * skeleton.global_transform
	for id in [&"greatsword", &"dawn_greatsword"]:
		var anchor := WeaponCarry.create(skeleton, ItemCatalog.get_item(id))
		anchor.fit_to_body(player.appearance_rig)
		var frame := (to_model * rest[skeleton.find_bone(anchor.bone_name)]).basis
		var orientation := (frame * anchor.mount.basis).orthonormalized()
		# Las caras de estas hojas tienen normal ±X; su longitud sigue +Y.
		check(absf(orientation.x.dot(Vector3.BACK)) > 0.99 \
			and absf(orientation.y.dot(Vector3.BACK)) < 0.01,
			"%s: la hoja reposa plana sobre el plano de la espalda" % id)
		check(orientation.y.y < -0.7 and orientation.y.x > 0.3,
			"%s: la punta cruza hacia abajo desde el hombro al lado opuesto" % id)
		anchor.queue_free()
	var before := player.loadout.primary_carry.mount
	var shield_before := player.combat._shield_carry.mount
	var back_slot := player.character_window.get_slot(ItemData.ArmorSlot.BACK)
	for id in [&"hide_backpack", &"skin_backpack", &"bearpaw_backpack"]:
		var pack := ItemCatalog.get_item(id)
		player.inventory.add_item(pack, 1)
		player.inventory.remove_item(pack, 1)
		player.character_window.equip_item(back_slot, InventoryItem.new(pack))
		check(player.loadout.primary_carry.mount.is_equal_approx(before),
			"%s: poner la mochila mantiene el arma contra el cuerpo" % id)
		check(player.combat._shield_carry.mount.is_equal_approx(shield_before) \
			and player.combat._shield_node.get_parent() == player.combat._shield_carry \
			and not player.combat.pose.shield_on,
			"%s: el escudo sigue contra el cuerpo y transportado al poner la mochila" % id)
		player.character_window.refresh()
		var doll := player.character_window._dressed[ItemData.ArmorSlot.PRIMARY] as WeaponCarry
		var doll_shield := player.character_window._dressed[ItemData.ArmorSlot.OFFHAND] as WeaponCarry
		var doll_with_pack := doll.mount
		var doll_shield_with_pack := doll_shield.mount
		var removed := player.character_window.unequip_item(back_slot)
		player.inventory.insert(removed)
		check(player.loadout.primary_carry.mount.is_equal_approx(before),
			"%s: quitar la mochila conserva la posición y el ángulo del arma" % id)
		check(player.combat._shield_carry.mount.is_equal_approx(shield_before),
			"%s: quitar la mochila conserva la posición y el ángulo del escudo" % id)
		check(doll.mount.is_equal_approx(doll_with_pack) \
			and doll_shield.mount.is_equal_approx(doll_shield_with_pack),
			"%s: el muñeco también conserva los anclajes de arma y escudo" % id)
