extends SceneTree

## Pone al día el catálogo de objetos (data/items/) con la clasificación de ItemTaxonomy y los
## rasgos de supervivencia: nombres en español, grupos, abrigo de la ropa, leña de la madera y las
## ramas, y los objetos nuevos (seax, armas de sílex, carne, piel, odre, hoguera, banco de trabajo).
## Cambia solo los campos de aquí y deja el resto como esté, así que se puede volver a pasar. Ver
## docs/items.md.
##   godot --headless --path . --script res://tools/items/update_item_catalog.gd

const ITEMS := "res://data/items/"


func _initialize() -> void:
	_update_existing()
	_create_new()
	print("CATALOG DONE")
	quit()


func _update_existing() -> void:
	for path in ["Weapons/iron_sword", "Weapons/battle_axe", "Weapons/great_axe", "Weapons/greatsword",
			"Weapons/iron_mace", "Weapons/war_hammer", "Weapons/spear"]:
		_edit(path, {"group": &"melee"})
	_edit("Weapons/branch", {
		"group": &"melee", "stackable": true, "max_stack": 10,
		"description": "Una rama caída: sirve de garrote, de leña y para levantar una hoguera.",
		"traits": [_fuel(60.0)],
	})
	for path in ["Weapons/hunting_bow", "Weapons/slingshot", "Tools/hand_cannon"]:
		_edit(path, {"group": &"ranged"})
	_edit("Weapons/spear", {"display_name": "Lanza de hierro"})
	_edit("Weapons/arrow", {"group": &"ammo"})
	for path in ["Shields/wooden_shield", "Shields/heater_shield"]:
		_edit(path, {"group": &"shield"})
	_edit("Tools/stone_axe", {"display_name": "Hacha de piedra", "group": &"tool",
		"description": "Hoja de piedra atada a un mango: tala árboles y saca madera."})
	_edit("Tools/stone_pickaxe", {"display_name": "Pico de piedra", "group": &"tool",
		"description": "Pica la roca y el terreno para sacar piedra."})
	_edit("Tools/torch", {"display_name": "Antorcha", "group": &"light",
		"description": "Alumbra en la noche y en las cuevas."})
	_edit("Tools/torch_placeable", {"display_name": "Antorcha de pared", "group": &"placeable",
		"description": "Una antorcha para colgar en los muros de lo que construyas."})

	# La ropa: nombre, descripción y lo que abriga (°C). tool_type no pinta nada en la ropa.
	var clothing := {
		"Armor/FirstAge_Skin_Set/firstage_skin_hood": ["Capucha de pieles", 1.5],
		"Armor/FirstAge_Skin_Set/firstage_skin_chest": ["Jubón de pieles", 3.0],
		"Armor/FirstAge_Skin_Set/firstage_skin_hands": ["Manoplas de pieles", 1.0],
		"Armor/FirstAge_Skin_Set/firstage_skin_pants": ["Calzas de pieles", 2.0],
		"Armor/FirstAge_Skin_Set/firstage_skin_boots": ["Botas de pieles", 1.5],
		"Armor/leather_armor/leather_hood": ["Capucha de cuero", 1.0],
		"Armor/leather_armor/leather_chest": ["Peto de cuero", 2.0],
		"Armor/leather_armor/leather_hands": ["Guantes de cuero", 0.5],
		"Armor/leather_armor/leather_leggings": ["Calzas de cuero", 1.5],
		"Armor/leather_armor/leather_boots": ["Botas de cuero", 1.0],
		"Armor/leather_chest": ["Peto de cuero curtido", 2.0],
		"Armor/leather_pants": ["Pantalones de cuero", 1.5],
	}
	for path in clothing:
		var insulation := InsulationTrait.new()
		insulation.warmth = clothing[path][1]
		_edit(path, {"display_name": clothing[path][0], "tool_type": ItemData.ToolType.NONE, "traits": [insulation]})

	_edit("material/wood", {"display_name": "Madera", "group": &"wood", "traits": [_fuel(150.0)],
		"description": "Madera para construir, fabricar y quemar en la hoguera."})
	_edit("material/stone", {"display_name": "Piedra", "group": &"stone",
		"description": "Piedra suelta: para construir, para el corro de una hoguera y de munición del tirachinas."})
	_edit("material/iron", {"display_name": "Hierro", "group": &"stone", "description": "Hierro para construir."})
	_edit("material/gold", {"display_name": "Oro", "group": &"stone", "description": "Oro para construir."})
	_edit("material/glass", {"display_name": "Vidrio", "group": &"misc", "description": "Vidrio para construir."})


func _create_new() -> void:
	var skinning := SkinningTrait.new()
	_create("Weapons/seax", {
		"id": &"seax", "display_name": "Seax", "category": ItemData.Category.WEAPON, "group": &"melee",
		"description": "El cuchillo de un filo con el lomo quebrado que todos llevan al cinto: corta, despelleja y, en un apuro, pelea.",
		"icon": load("res://textures/icons/items/weapons/seax.png"),
		"scene_path": "res://scenes/items/weapons/combat/seax.tscn",
		"armor_slot": ItemData.ArmorSlot.RIGHT_HAND, "weapon_type": ItemData.WeaponType.SWORD,
		"damage": 14, "attack_speed": 1.35, "reach": 0.29, "blade_start": 0.08, "blade_radius": 0.05,
		"damage_kind": ItemData.DamageKind.SLASH, "stamina_cost": 9.0, "poise_damage": 8.0,
		"heavy_multiplier": 1.6, "stackable": false, "max_stack": 1, "traits": [skinning],
	})
	# Armas de la Edad de piedra (se fabrican en el banco de trabajo): algo menos que las de hierro.
	_create("Weapons/flint_sword", {
		"id": &"flint_sword", "display_name": "Espada de sílex", "category": ItemData.Category.WEAPON, "group": &"melee",
		"description": "Una pala de madera dura con lascas de sílex encajadas en los dos filos. Pesa más y corta menos que una de hierro, pero corta.",
		"icon": load("res://textures/icons/items/weapons/flint_sword.png"),
		"scene_path": "res://scenes/items/weapons/combat/flint_sword.tscn",
		"armor_slot": ItemData.ArmorSlot.RIGHT_HAND, "weapon_type": ItemData.WeaponType.SWORD,
		"damage": 22, "attack_speed": 0.95, "reach": 0.82, "blade_start": 0.12, "blade_radius": 0.07,
		"damage_kind": ItemData.DamageKind.SLASH, "stamina_cost": 17.0, "poise_damage": 16.0,
		"stackable": false, "max_stack": 1,
	})
	_create("Weapons/flint_spear", {
		"id": &"flint_spear", "display_name": "Lanza de sílex", "category": ItemData.Category.WEAPON, "group": &"melee",
		"description": "Asta larga con una punta de sílex atada con tiras de piel. Pica desde lejos o, apuntando con el botón derecho, se arroja. Hay que ir a recogerla.",
		"icon": load("res://textures/icons/items/weapons/flint_spear.png"),
		"scene_path": "res://scenes/items/weapons/combat/flint_spear.tscn",
		"armor_slot": ItemData.ArmorSlot.RIGHT_HAND, "weapon_type": ItemData.WeaponType.SPEAR,
		"damage": 21, "attack_speed": 1.4, "reach": 1.1, "blade_start": 0.5, "blade_radius": 0.06,
		"damage_kind": ItemData.DamageKind.PIERCE, "stamina_cost": 15.0, "poise_damage": 12.0,
		"heavy_multiplier": 1.7, "projectile_speed": 28.0, "draw_time": 0.55, "throwable": true, "max_stack": 5,
	})
	var raw := EdibleTrait.new()
	raw.hunger = 0.12
	raw.sanity = -0.06
	raw.intoxication_chance = 0.35
	raw.intoxication_severity = 0.5
	var cookable := CookableTrait.new()
	cookable.result = &"cooked_meat"
	cookable.cook_time = 40.0
	_create("Food/raw_meat", {
		"id": &"raw_meat", "display_name": "Carne cruda", "category": ItemData.Category.CONSUMABLE, "group": &"raw",
		"description": "Recién despiezada. Cruda alimenta poco, revuelve el estómago y puede intoxicar: mejor asarla en una hoguera.",
		"icon": load("res://textures/icons/items/survival/raw_meat.png"),
		"scene_path": "res://scenes/items/survival/raw_meat.tscn", "max_stack": 20, "traits": [raw, cookable],
	})
	var cooked := EdibleTrait.new()
	cooked.hunger = 0.35
	cooked.thirst = -0.03
	cooked.sanity = 0.03
	cooked.health = 8.0
	_create("Food/cooked_meat", {
		"id": &"cooked_meat", "display_name": "Carne asada", "category": ItemData.Category.CONSUMABLE, "group": &"cooked",
		"description": "Asada al fuego: llena, da fuerzas y sienta bien.",
		"icon": load("res://textures/icons/items/survival/cooked_meat.png"),
		"scene_path": "res://scenes/items/survival/cooked_meat.tscn", "max_stack": 20, "traits": [cooked],
	})
	_create("material/raw_hide", {
		"id": &"raw_hide", "display_name": "Piel", "category": ItemData.Category.MATERIAL, "group": &"hunt",
		"description": "La piel de un animal despellejado. Con ella se cosen odres y ropa.",
		"icon": load("res://textures/icons/items/survival/raw_hide.png"),
		"scene_path": "res://scenes/items/survival/raw_hide.tscn", "max_stack": 20,
	})
	var container := WaterContainerTrait.new()
	container.capacity = 5
	_create("Tools/waterskin", {
		"id": &"waterskin", "display_name": "Odre", "category": ItemData.Category.CONSUMABLE, "group": &"container",
		"description": "Bolsa de piel cosida para llevar agua. Se llena junto a un río o un lago (E con la sed saciada) y se bebe desde la barra.",
		"icon": load("res://textures/icons/items/survival/waterskin.png"),
		"scene_path": "res://scenes/items/survival/waterskin.tscn", "stackable": false, "max_stack": 1,
		"traits": [container],
	})
	var ground := GroundPlaceableTrait.new()
	ground.scene_path = "res://scenes/world/campfire.tscn"
	ground.preview_scene = load("res://scenes/world/campfire_visual.tscn")
	ground.radius = 0.55
	_create("Placeables/campfire", {
		"id": &"campfire", "display_name": "Hoguera", "category": ItemData.Category.MATERIAL, "group": &"placeable",
		"description": "Un corro de piedras con leña. Plántala en el suelo, échale combustible y enciéndela: asa la carne, calienta y alumbra.",
		"icon": load("res://textures/icons/items/survival/campfire.png"), "max_stack": 5, "traits": [ground],
	})
	# Sobre patas: casi derecho, apoyado en lo más bajo del suelo.
	var bench_ground := GroundPlaceableTrait.new()
	bench_ground.scene_path = "res://scenes/world/stone_workbench.tscn"
	bench_ground.preview_scene = load("res://scenes/world/stone_workbench_visual.tscn")
	bench_ground.radius = 0.6
	bench_ground.max_slope = 24.0
	bench_ground.max_rough = 0.3
	bench_ground.spacing = 2.0
	bench_ground.max_tilt = 10.0
	bench_ground.settle = 0.9
	bench_ground.max_settle = 0.25
	var station := CraftingStationTrait.new()
	station.era = Eras.Era.STONE
	_create("Placeables/stone_workbench", {
		"id": &"stone_workbench", "display_name": "Banco de trabajo", "category": ItemData.Category.MATERIAL,
		"group": &"station",
		"description": "Un banco de madera tosca con una losa para tallar. Plántalo en el suelo: a su lado se fabrican las herramientas, las armas y la ropa de la Edad de piedra.",
		"icon": load("res://textures/icons/items/survival/stone_workbench.png"), "stackable": false, "max_stack": 1,
		"traits": [bench_ground, station],
	})


func _fuel(seconds: float) -> FuelTrait:
	var fuel := FuelTrait.new()
	fuel.burn_time = seconds
	return fuel


func _edit(path: String, fields: Dictionary) -> void:
	var full := ITEMS + path + ".tres"
	var item := load(full) as ItemData
	if item == null:
		push_error("No está: " + full)
		return
	_apply(item, fields)
	_save(item, full)


func _create(path: String, fields: Dictionary) -> void:
	var full := ITEMS + path + ".tres"
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var item := (load(full) as ItemData) if ResourceLoader.exists(full) else ItemData.new()
	_apply(item, fields)
	_save(item, full)


func _apply(item: ItemData, fields: Dictionary) -> void:
	for key in fields:
		if key == "traits":
			var traits: Array[ItemTrait] = []
			for item_trait in fields[key]:
				traits.append(item_trait)
			item.traits = traits
		else:
			item.set(key, fields[key])


func _save(item: ItemData, path: String) -> void:
	var err := ResourceSaver.save(item, path)
	if err != OK:
		push_error("No se pudo guardar %s (%d)" % [path, err])
	else:
		print("saved ", path)
