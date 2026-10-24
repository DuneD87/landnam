extends Node3D

## Cantidades e identidad tras secuencias de cursor, equipo, cofres, hoguera y recogidas síncronas.
## godot --headless --path . res://tests/items/test_item_conservation.tscn

var failures := 0
var checks := 0
var _bag: Inventory
var _ui: InventoryUI
var _character: CharacterWindow
var _chest: Storage
var _fire: Campfire
var _dropped := {}


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)


func _totals() -> Dictionary:
	var result := _dropped.duplicate()
	var stacks: Array[InventoryItem] = []
	stacks.append_array(_bag.items)
	stacks.append_array(_chest.inventory.items)
	stacks.append_array(_fire.inventory.items)
	stacks.append(_ui.floating_item)
	for slot: EquipmentSlot in _character.equipment_slots.values():
		stacks.append(slot.equipped_item)
	var identities := {}
	for stack in stacks:
		if stack == null:
			continue
		check(not identities.has(stack.get_instance_id()), "cada montón tiene un único dueño")
		identities[stack.get_instance_id()] = true
		result[stack.data.id] = result.get(stack.data.id, 0) + stack.quantity
	return result


func _run() -> void:
	_bag = Inventory.new(8)
	add_child(_bag)
	_character = load("res://scenes/ui/character_window.tscn").instantiate()
	add_child(_character)
	_chest = load("res://scenes/world/wooden_chest.tscn").instantiate()
	add_child(_chest)
	_fire = load("res://scenes/world/campfire.tscn").instantiate()
	_fire.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_fire)
	_ui = InventoryUI.new()
	add_child(_ui)
	_ui.inventory = _bag
	_ui.character_window = _character
	_ui._create_slots()
	_bag.inventory_changed.connect(_ui._refresh)
	_ui.drop_requested.connect(func(data: ItemData, amount: int) -> void:
		_dropped[data.id] = _dropped.get(data.id, 0) + amount)
	for entry in [[&"stone_01", 38], [&"wood_01", 21], [&"spear", 7], [&"stone_axe_01", 2],
			[&"raw_meat", 6], [&"torch_01", 4]]:
		_bag.add_item(ItemCatalog.get_item(entry[0]), entry[1])
	_chest.inventory.add_item(ItemCatalog.get_item(&"stone_01"), 13)
	_chest.inventory.add_item(ItemCatalog.get_item(&"wood_01"), 49)
	_chest.inventory.add_item(ItemCatalog.get_item(&"iron_sword"), 1)
	_fire.inventory.add_item(ItemCatalog.get_item(&"raw_meat"), 3)
	var expected := _totals()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2401026
	for step in 4000:
		match rng.randi_range(0, 9):
			0, 1:
				_ui._on_slot_clicked(_ui.slots[rng.randi_range(0, _bag.max_slots - 1)],
					MOUSE_BUTTON_LEFT if rng.randf() < 0.5 else MOUSE_BUTTON_RIGHT)
			2:
				_ui.open_storage(_chest)
				_ui._on_loot_slot_clicked(_ui._loot_slots[rng.randi_range(0, _chest.inventory.max_slots - 1)],
					MOUSE_BUTTON_LEFT if rng.randf() < 0.5 else MOUSE_BUTTON_RIGHT)
			3:
				var slot := ItemData.ArmorSlot.RIGHT_HAND if rng.randf() < 0.5 else ItemData.ArmorSlot.OFFHAND
				_ui._on_equipment_slot_clicked(_character.get_slot(slot))
			4:
				_ui._sort_inventory()
			5:
				_ui.close()
			6:
				_bag.transfer_to(_chest.inventory, rng.randi_range(0, _bag.max_slots - 1), rng.randi_range(1, 9))
			7:
				_ui.open_campfire(_fire)
				_ui._on_campfire_slot_clicked(_ui._campfire_slots[rng.randi_range(0, Campfire.COOK_SLOTS)],
					MOUSE_BUTTON_LEFT if rng.randf() < 0.5 else MOUSE_BUTTON_RIGHT)
			8:
				if _ui.floating_item != null:
					_ui._drop_to_world(rng.randi_range(1, _ui.floating_item.quantity))
			9:
				_chest.inventory.transfer_to(_bag, rng.randi_range(0, _chest.inventory.max_slots - 1))
		# Recuperar periódicamente lo soltado mantiene los 4.000 pasos activos, con montones
		# circulando, en vez de terminar comprobando inventarios vacíos.
		if step % 17 == 0:
			for id: StringName in _dropped:
				_dropped[id] = _chest.inventory.add_item(ItemCatalog.get_item(id), _dropped[id])
		check(_totals() == expected, "se conservan las cantidades en el paso %d" % step)
		if failures:
			break
	_ui.close()
	check(_totals() == expected, "cerrar al terminar conserva todos los objetos")
	_test_reentrant_pickups()
	print("ITEM CONSERVATION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _test_reentrant_pickups() -> void:
	var data := ItemCatalog.get_item(&"spear")
	var bag := Inventory.new()
	add_child(bag)
	var drop := DroppedItem.new()
	drop.item_data = data
	drop.quantity = 3
	add_child(drop)
	var nested := []
	var retry_drop := func(_data: ItemData, _amount: int) -> void: nested.append(drop.pick_into(bag))
	bag.item_added.connect(retry_drop, CONNECT_ONE_SHOT)
	check(drop.pick_into(bag) and bag.get_item_count(data) == 3 and nested == [false],
		"las señales del inventario no pueden recoger dos veces el mismo montón")
	var projectile := CombatProjectile.new()
	projectile.kind = CombatProjectile.Kind.SPEAR
	projectile.item_data = data
	projectile._stuck = true
	add_child(projectile)
	projectile.add_to_group(CombatProjectile.PICKUP_GROUP)
	nested.clear()
	bag.item_added.connect(func(_data: ItemData, _amount: int) -> void:
		nested.append(projectile.pick_into(bag)), CONNECT_ONE_SHOT)
	check(projectile.pick_into(bag) and nested == [false] and bag.get_item_count(data) == 4,
		"una lanza se reserva antes de notificar que ha entrado en la mochila")
	check(not projectile.pick_into(bag) and bag.get_item_count(data) == 4,
		"dos recogidas antes de queue_free solo entregan una lanza")
	bag.clear()
	for i in bag.max_slots:
		bag.add_item_at(ItemCatalog.get_item(&"stone_axe_01"), 1, i)
	var full := CombatProjectile.new()
	full.kind = CombatProjectile.Kind.SPEAR
	full.item_data = data
	full._stuck = true
	add_child(full)
	full.add_to_group(CombatProjectile.PICKUP_GROUP)
	check(not full.pick_into(bag) and full.is_pickable() and not full.is_queued_for_deletion(),
		"sin sitio en la mochila la lanza sigue disponible en el mundo")
