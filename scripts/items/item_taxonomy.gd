class_name ItemTaxonomy
extends RefCounted

## La clasificación de los objetos: cada uno es de una categoría (los filtros del inventario) y,
## dentro, de un grupo (el orden al ordenar y el tipo en la ficha). Lo que se puede hacer con él va
## aparte, en sus rasgos (ItemTrait). Ver docs/items.md.
##
## La categoría que se enseña sale del grupo, no de ItemData.category: esa la sigue usando el juego
## para equipar (un escudo es ARMOR para la mano secundaria y la flecha MATERIAL para no empuñarla),
## pero en el inventario los dos van con las armas.

## Orden de los filtros y de ordenar, con su nombre.
const CATEGORIES := [
	[ItemData.Category.WEAPON, "Armas"],
	[ItemData.Category.TOOL, "Herramientas"],
	[ItemData.Category.ARMOR, "Ropa"],
	[ItemData.Category.CONSUMABLE, "Comida"],
	[ItemData.Category.MATERIAL, "Materiales"],
	[ItemData.Category.BLOCK, "Construcción"],
]
## Grupos: id → [categoría que se enseña, nombre]. El orden de aquí es el de ordenar.
const GROUPS := {
	&"melee": [ItemData.Category.WEAPON, "Cuerpo a cuerpo"],
	&"ranged": [ItemData.Category.WEAPON, "A distancia"],
	&"ammo": [ItemData.Category.WEAPON, "Munición"],
	&"shield": [ItemData.Category.WEAPON, "Escudos"],
	&"tool": [ItemData.Category.TOOL, "Hachas y picos"],
	&"light": [ItemData.Category.TOOL, "Luz"],
	&"container": [ItemData.Category.TOOL, "Recipientes"],
	&"head": [ItemData.Category.ARMOR, "Cabeza"],
	&"chest": [ItemData.Category.ARMOR, "Torso"],
	&"hands": [ItemData.Category.ARMOR, "Manos"],
	&"legs": [ItemData.Category.ARMOR, "Piernas"],
	&"feet": [ItemData.Category.ARMOR, "Pies"],
	&"cooked": [ItemData.Category.CONSUMABLE, "Cocinada"],
	&"raw": [ItemData.Category.CONSUMABLE, "Cruda"],
	&"drink": [ItemData.Category.CONSUMABLE, "Bebida"],
	&"hunt": [ItemData.Category.MATERIAL, "De caza"],
	&"wood": [ItemData.Category.MATERIAL, "Madera"],
	&"stone": [ItemData.Category.MATERIAL, "Piedra y mineral"],
	&"misc": [ItemData.Category.MATERIAL, "Otros"],
	&"placeable": [ItemData.Category.BLOCK, "Colocables"],
	&"block": [ItemData.Category.BLOCK, "Bloques"],
}
const ARMOR_GROUPS := {
	ItemData.ArmorSlot.HEAD: &"head",
	ItemData.ArmorSlot.CHEST: &"chest",
	ItemData.ArmorSlot.HANDS: &"hands",
	ItemData.ArmorSlot.LEGS: &"legs",
	ItemData.ArmorSlot.FEET: &"feet",
}
const DAMAGE_KINDS := {
	ItemData.DamageKind.SLASH: "Tajo",
	ItemData.DamageKind.BLUNT: "Contundente",
	ItemData.DamageKind.PIERCE: "Perforante",
}


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


static func category_name(category: ItemData.Category) -> String:
	for entry in CATEGORIES:
		if entry[0] == category:
			return entry[1]
	return "Objeto"


## «Armas · Cuerpo a cuerpo · Tajo · Dos manos».
static func kind_line(data: ItemData) -> String:
	var group := group_of(data)
	var parts: Array[String] = [category_name(GROUPS[group][0]), GROUPS[group][1]]
	if data.category in [ItemData.Category.WEAPON, ItemData.Category.TOOL] and not data.is_shield():
		if data.damage > 0 and group == &"melee":
			parts.append(DAMAGE_KINDS.get(data.damage_kind, ""))
		if data.two_handed:
			parts.append("Dos manos")
	return " · ".join(parts.filter(func(part: String) -> bool: return part != ""))


## Clave para ordenar: categoría, grupo y nombre.
static func sort_key(data: ItemData) -> Array:
	var group := group_of(data)
	var category_index := 0
	for i in CATEGORIES.size():
		if CATEGORIES[i][0] == GROUPS[group][0]:
			category_index = i
	return [category_index, GROUPS.keys().find(group), data.display_name.to_lower()]


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
