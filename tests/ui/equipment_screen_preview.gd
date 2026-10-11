extends Node

## Abre la pantalla de personaje (InventoryUI con el muñeco de CharacterWindow y la barra
## rápida) sobre una escena mínima, con el inventario lleno y algo de ropa puesta. Sin argumentos
## se queda abierta para probarla a mano: I, C y Tab (fabricar, con un banco de trabajo al lado)
## cambian de vista como en partida. Con
## `-- --capture` guarda capturas en build/ui/equipment/ (la pantalla, la ficha de un objeto, uno
## en el cursor y el botín) y sale. Necesita ventana.
##   godot --path . res://tests/ui/equipment_screen_preview.tscn -- --capture

const Config = preload("res://scripts/config.gd")

var _ui: InventoryUI
var _character_window: CharacterWindow
var _hotbar: Hotbar
var _inventory: Inventory


func _ready() -> void:
	_build_scene()
	var character := CharacterData.new()
	character.display_name = "Astrid"
	character.appearance.set_sex(&"female")
	GameManager.character = character

	_inventory = Inventory.new()
	add_child(_inventory)
	for entry in [[&"iron_sword", 1], [&"battle_axe", 1], [&"hunting_bow", 1], [&"arrow", 40],
			[&"stone_axe_01", 1], [&"stone_pickaxe_01", 1], [&"torch_01", 1], [&"heater_shield", 1],
			[&"leather_hood", 1], [&"leather_boots", 1], [&"firstage_skin_chest", 1], [&"wood_01", 64],
			[&"stone_01", 99], [&"iron_01", 12], [&"branch_01", 10], [&"raw_hide", 5]]:
		_inventory.add_item(Config.get_item(entry[0]), entry[1])
	_ui = load("res://scenes/ui/inventory_ui.tscn").instantiate()
	_character_window = load("res://scenes/ui/character_window.tscn").instantiate()
	_hotbar = load("res://scenes/ui/hotbar.tscn").instantiate()
	add_child(_ui)
	add_child(_character_window)
	add_child(_hotbar)
	_ui.setup(_inventory, _character_window, _hotbar)
	# Quien fabrica, con un banco de trabajo al lado: sus recetas salen «Cerca».
	var crafter := Node3D.new()
	add_child(crafter)
	_ui.crafter = crafter
	var bench: Node3D = load("res://scenes/world/stone_workbench.tscn").instantiate()
	add_child(bench)
	bench.position = Vector3(1.5, 0, 0)
	var health := HealthComponent.new()
	add_child(health)
	health.health = 72.0
	var stamina := StaminaComponent.new()
	add_child(stamina)
	_ui.set_vitals(health, stamina)
	for entry in [[ItemData.ArmorSlot.CHEST, &"leather_chest"], [ItemData.ArmorSlot.LEGS, &"leather_leggings"],
			[ItemData.ArmorSlot.HANDS, &"leather_hands"], [ItemData.ArmorSlot.RIGHT_HAND, &"spear"],
			[ItemData.ArmorSlot.OFFHAND, &"wooden_shield"]]:
		_character_window.equip_item(_character_window.equipment_slots[entry[0]],
			InventoryItem.new(Config.get_item(entry[1]), 1))
	for i in 4:
		_hotbar.assign_to_slot(i, _inventory.items[i].data)
	_ui.open(InventoryUI.View.CHARACTER)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		_ui.toggle(InventoryUI.View.INVENTORY)
	elif event.is_action_pressed("character_window"):
		_ui.toggle(InventoryUI.View.CHARACTER)
	elif event.is_action_pressed("crafting"):
		_ui.toggle(InventoryUI.View.CRAFTING)


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/ui/equipment")
	# El muñeco hornea el cuerpo y ajusta la ropa en hilos: se le deja tiempo.
	await _shot("01_equipo", 3.0)
	_ui._on_slot_hovered(_ui.slots[1], true, &"inventory")
	await _shot("02_ficha_arma")
	_ui._on_slot_hovered(_ui.slots[1], false, &"inventory")
	_ui._on_slot_hovered(_ui.slots[8], true, &"inventory")
	await _shot("03_ficha_armadura")
	_ui._on_slot_hovered(_ui.slots[8], false, &"inventory")
	var head: EquipmentSlot = _character_window.equipment_slots[ItemData.ArmorSlot.HEAD]
	_ui._on_slot_hovered(head, true, &"equipment")
	await _shot("03b_ficha_hueco_vacio")
	_ui._on_slot_hovered(head, false, &"equipment")
	_ui._on_slot_hovered(_hotbar.slots[1], true, &"hotbar")
	await _shot("03c_ficha_barra")
	_ui._on_slot_hovered(_hotbar.slots[1], false, &"hotbar")
	_ui._set_filter(1)
	_ui._on_slot_clicked(_ui.slots[0], MOUSE_BUTTON_LEFT)
	Input.warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.5, 0.45))
	await _shot("04_cursor_filtro")
	_ui._return_to_origin()
	_ui._set_filter(0)
	var loot := Inventory.new()
	add_child(loot)
	for entry in [[&"great_axe", 1], [&"firstage_skin_hood", 1], [&"arrow", 12], [&"gold_01", 3]]:
		loot.add_item(Config.get_item(entry[0]), entry[1])
	_ui.open_loot(loot)
	await _shot("05_botin")
	_ui.close_loot()
	_ui.open(InventoryUI.View.CRAFTING)
	await _shot("06_fabricar")
	get_tree().quit()


func _shot(shot_name: String, wait := 0.5) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var path := "res://build/ui/equipment/%s.png" % shot_name
	get_viewport().get_texture().get_image().save_png(path)
	print("Captura: ", ProjectSettings.globalize_path(path))


## Un poco de mundo detrás para que se vea el fondo desenfocado: cielo, suelo y unas cajas.
func _build_scene() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.8, 6)
	add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-35, 40, 0)
	add_child(sun)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_SKY
	world.environment.sky = Sky.new()
	world.environment.sky.sky_material = ProceduralSkyMaterial.new()
	world.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	add_child(world)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.scale = Vector3.ONE * 40.0
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color("4f6b3a")
	ground.material_override = grass
	add_child(ground)
	for i in 6:
		var box := MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		box.position = Vector3(-6 + i * 2.4, 0.5 + (i % 2) * 0.5, -2 - (i % 3) * 2)
		box.scale = Vector3.ONE * (1.0 + (i % 3) * 0.6)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.from_hsv(0.07 + i * 0.03, 0.4, 0.5)
		box.material_override = material
		add_child(box)
