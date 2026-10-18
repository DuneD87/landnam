class_name ItemTaxonomy
extends RefCounted

## La clasificación de los objetos: cada uno es de una categoría (los filtros del inventario) y,
## dentro, de un grupo (el orden al ordenar y el tipo en la ficha). Lo que se puede hacer con él va
## aparte, en sus rasgos (ItemTrait). Ver docs/items.md.
##
## La categoría que se enseña sale del grupo, no de ItemData.category: esa la sigue usando el juego
## para equipar (un escudo es ARMOR para la mano secundaria y la flecha MATERIAL para no empuñarla),
## pero en el inventario los dos van con las armas.

## Orden de los filtros y de ordenar, con la clave de su nombre.
const CATEGORIES := [
	[ItemData.Category.WEAPON, "CAT_WEAPONS"],
	[ItemData.Category.TOOL, "CAT_TOOLS"],
	[ItemData.Category.ARMOR, "CAT_CLOTHING"],
	[ItemData.Category.CONSUMABLE, "CAT_CONSUMABLES"],
	[ItemData.Category.MATERIAL, "CAT_MATERIALS"],
	[ItemData.Category.BLOCK, "CAT_BUILDING"],
]
## Grupos: id → [categoría que se enseña, clave del nombre]. El orden de aquí es el de ordenar.
const GROUPS := {
	&"melee": [ItemData.Category.WEAPON, "GROUP_MELEE"],
	&"ranged": [ItemData.Category.WEAPON, "GROUP_RANGED"],
	&"ammo": [ItemData.Category.WEAPON, "GROUP_AMMO"],
	&"shield": [ItemData.Category.WEAPON, "GROUP_SHIELD"],
	&"tool": [ItemData.Category.TOOL, "GROUP_TOOL"],
	&"light": [ItemData.Category.TOOL, "GROUP_LIGHT"],
	&"container": [ItemData.Category.TOOL, "GROUP_CONTAINER"],
	&"head": [ItemData.Category.ARMOR, "GROUP_HEAD"],
	&"chest": [ItemData.Category.ARMOR, "GROUP_CHEST"],
	&"hands": [ItemData.Category.ARMOR, "GROUP_HANDS"],
	&"legs": [ItemData.Category.ARMOR, "GROUP_LEGS"],
	&"feet": [ItemData.Category.ARMOR, "GROUP_FEET"],
	&"cooked": [ItemData.Category.CONSUMABLE, "GROUP_COOKED"],
	&"raw": [ItemData.Category.CONSUMABLE, "GROUP_RAW"],
	&"drink": [ItemData.Category.CONSUMABLE, "GROUP_DRINK"],
	&"remedy": [ItemData.Category.CONSUMABLE, "GROUP_REMEDY"],
	&"hunt": [ItemData.Category.MATERIAL, "GROUP_HUNT"],
	&"wood": [ItemData.Category.MATERIAL, "GROUP_WOOD"],
	&"stone": [ItemData.Category.MATERIAL, "GROUP_STONE"],
	&"misc": [ItemData.Category.MATERIAL, "GROUP_MISC"],
	&"station": [ItemData.Category.BLOCK, "GROUP_STATION"],
	&"placeable": [ItemData.Category.BLOCK, "GROUP_PLACEABLE"],
	&"block": [ItemData.Category.BLOCK, "GROUP_BLOCK"],
}
const ARMOR_GROUPS := {
	ItemData.ArmorSlot.HEAD: &"head",
	ItemData.ArmorSlot.CHEST: &"chest",
	ItemData.ArmorSlot.HANDS: &"hands",
	ItemData.ArmorSlot.LEGS: &"legs",
	ItemData.ArmorSlot.FEET: &"feet",
}
const DAMAGE_KINDS := Armor.KIND_NAMES


## El grupo del objeto: el suyo o, si no lo tiene, el que le toca por cómo es.
static func group_of(data: ItemData) -> StringName:
	if data.group != &"" and GROUPS.has(data.group):
		return data.group
	if data.is_shield():
		return &"shield"
	match data.category:
		ItemData.Category.WEAPON:
			return &"ranged" if data.is_ranged() else &"melee"
		ItemData.Category.TOOL:
			return &"ranged" if data.weapon_type != ItemData.WeaponType.NONE else &"tool"
		ItemData.Category.ARMOR:
			return ARMOR_GROUPS.get(data.armor_slot, &"chest")
		ItemData.Category.CONSUMABLE:
			return &"cooked"
		ItemData.Category.BLOCK:
			return &"block"
	return &"placeable" if data.placeable else &"misc"


## La categoría con la que se enseña y se filtra.
static func category_of(data: ItemData) -> ItemData.Category:
	return GROUPS[group_of(data)][0]


## El nombre de la categoría, ya traducido.
static func category_name(category: ItemData.Category) -> String:
	for entry in CATEGORIES:
		if entry[0] == category:
			return TranslationServer.translate(entry[1])
	return TranslationServer.translate(&"CAT_ITEM")


## «Armas · Cuerpo a cuerpo · Tajo · Dos manos».
static func kind_line(data: ItemData) -> String:
	var group := group_of(data)
	var parts: Array[String] = [category_name(GROUPS[group][0]), TranslationServer.translate(GROUPS[group][1])]
	if data.category in [ItemData.Category.WEAPON, ItemData.Category.TOOL] and not data.is_shield():
		if data.damage > 0 and group in [&"melee", &"ranged", &"tool"]:
			parts.append(TranslationServer.translate(DAMAGE_KINDS.get(data.damage_kind, "")))
		if data.two_handed:
			parts.append(TranslationServer.translate(&"ITEM_TWO_HANDED"))
	return " · ".join(parts.filter(func(part: String) -> bool: return part != ""))


## Clave para ordenar: categoría, grupo y nombre (en el idioma del juego).
static func sort_key(data: ItemData) -> Array:
	var group := group_of(data)
	var category_index := 0
	for i in CATEGORIES.size():
		if CATEGORIES[i][0] == GROUPS[group][0]:
			category_index = i
	return [category_index, GROUPS.keys().find(group), data.get_display_name().to_lower()]


## Junta lo que se apila y lo pone en orden, todo seguido desde el primer hueco.
static func sort_inventory(inventory: Inventory) -> void:
	var stacks: Array[InventoryItem] = []
	for item in inventory.items:
		if item == null or item.data == null:
			continue
		var merged := false
		if item.data.stackable:
			for stack in stacks:
				if stack.data.id == item.data.id and not stack.is_full():
					var left := stack.add(item.quantity)
					if left == 0:
						merged = true
					else:
						item.quantity = left
					break
		if not merged:
			stacks.append(item)
	stacks.sort_custom(func(a: InventoryItem, b: InventoryItem) -> bool:
		return _less(sort_key(a.data), sort_key(b.data)))
	for i in inventory.items.size():
		inventory.items[i] = stacks[i] if i < stacks.size() else null
	inventory.inventory_changed.emit()


static func _less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
