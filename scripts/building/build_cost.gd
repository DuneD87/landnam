class_name BuildCost
extends RefCounted

## Lo que cuesta construir. Un bloque gasta su material según el tamaño de celda de su grid
## (BuildMaterial.get_cost_for_size) y un colocable, una unidad de su objeto; los aparejos navales
## cuestan los materiales de su diseño. Igual que al ponerlos
## a mano con el martillo. Sirve para los blueprints (lo que gastan al colocarlos), para el valor de
## una construcción en pie (lo que devuelve al desmontarla, según la vida de cada bloque, como al
## quitarlos uno a uno) y para compararlo con el inventario.
##
## Un coste es un Dictionary id de objeto (StringName) → cantidad. Un recuento es lo que hay que
## pagar antes de ponerle precio: {"blocks": {material_id: {celda: n}}, "props": {item_id: n}}, con
## la celda como texto («1.000») y "sails" con los diseños; así se guarda en la ficha del blueprint y el precio sale siempre
## del coste de los materiales de ahora.


## Recuento de un blueprint ya leído. Lo que no se va a reconstruir (un bloque de id desconocido)
## no se cuenta.
static func count_blueprint(data: Dictionary) -> Dictionary:
	var blocks := {}
	var props := {}
	var sails: Array = []
	for grid_data: Dictionary in data.get("grids", []):
		var cell := cell_key(float(grid_data.get("cell_size", 1.0)))
		for info: Dictionary in (grid_data.get("blocks", {}) as Dictionary).values():
			if BlockDatabase.get_block(int(info.get("block_id", -1))) == null:
				continue
			_add_count(blocks, str(info.get("material_id", "")), cell, 1)
		for prop: Dictionary in grid_data.get("props", []):
			var id := str(prop.get("item_id", ""))
			if id == SailDesign.ITEM:
				sails.append(SailDesign.from_state(prop.get("state", {})))
				continue
			props[id] = int(props.get(id, 0)) + 1
	return {"blocks": blocks, "props": props, "sails": sails}


## Precio de un recuento con los costes de ahora. Los bloques sin material (el genérico) o de un
## material que ya no existe no cuestan nada.
static func of_counts(counts: Dictionary) -> Dictionary:
	var cost := {}
	var blocks: Dictionary = counts.get("blocks", {})
	for mat_id: String in blocks:
		var mat := BlockDatabase.get_material_by_id(mat_id)
		if mat == null or mat.item == null:
			continue
		var by_cell: Dictionary = blocks[mat_id]
		for cell: String in by_cell:
			add(cost, mat.item.id, mat.get_cost_for_size(float(cell)) * int(by_cell[cell]))
	var props: Dictionary = counts.get("props", {})
	for item_id: String in props:
		if ItemCatalog.get_item(StringName(item_id)) != null:
			var price := prop_cost({"item_id": item_id})
			for id: StringName in price:
				add(cost, id, int(price[id]) * int(props[item_id]))
	for design: Dictionary in counts.get("sails", []):
		var price := SailDesign.cost(design)
		for id: StringName in price:
			add(cost, id, int(price[id]))
	return cost


## Los aparejos a medida cuestan materiales; los otros colocables cuestan una unidad del objeto.
static func prop_cost(info: Dictionary) -> Dictionary:
	var item_id := StringName(str(info.get("item_id", "")))
	var item := ItemCatalog.get_item(item_id)
	if item == null:
		return {}
	if item.get_trait(SailTrait) != null:
		return SailDesign.cost(SailDesign.from_state(info.get("state", {})))
	return {item_id: 1}


static func of_blueprint(data: Dictionary) -> Dictionary:
	return of_counts(count_blueprint(data))


## Lo que vale una construcción en pie (sus grids). Con [by_health], lo que devolvería al
## desmontarla: cada bloque, la parte de su coste que le queda de vida (redondeando hacia arriba,
## como BuildingSystem al quitar uno), y los colocables enteros.
static func of_grids(grids: Array, by_health: bool = false) -> Dictionary:
	var cost := {}
	for grid: GridBase in grids:
		var blocks := grid.get_all_blocks()
		for grid_pos: Vector3i in blocks:
			var info: Dictionary = blocks[grid_pos]
			var mat := BlockDatabase.get_material_by_id(info.get("material_id", ""))
			if mat == null or mat.item == null:
				continue
			var amount := mat.get_cost_for_size(grid.cell_size)
			if by_health:
				amount = mini(amount, ceili(amount * clampf(info.get("hp", 1.0), 0.0, 1.0)))
			add(cost, mat.item.id, amount)
		var props := grid.get_all_props()
		for key: String in props:
			var price := prop_cost(props[key])
			for id: StringName in price:
				add(cost, id, int(price[id]))
	return cost


## Lo que falta en [inventory] para pagar [cost] (id → cuánto falta); vacío si alcanza.
static func missing(cost: Dictionary, inventory: Inventory) -> Dictionary:
	var out := {}
	for id: StringName in cost:
		var have := inventory.get_item_count(ItemCatalog.get_item(id)) if inventory else 0
		if have < int(cost[id]):
			out[id] = int(cost[id]) - have
	return out


## Saca [cost] de [inventory]; si no alcanza no saca nada y devuelve false.
static func pay(cost: Dictionary, inventory: Inventory) -> bool:
	if inventory == null or not missing(cost, inventory).is_empty():
		return false
	for id: StringName in cost:
		inventory.remove_item(ItemCatalog.get_item(id), int(cost[id]))
	return true


## Mete [cost] en [inventory]; lo que no quepa cae al suelo delante de [dropper].
static func give(cost: Dictionary, inventory: Inventory, dropper: Node3D, down: Vector3) -> void:
	for id: StringName in cost:
		var data := ItemCatalog.get_item(id)
		if data == null or int(cost[id]) <= 0:
			continue
		var left := inventory.add_item(data, int(cost[id])) if inventory else int(cost[id])
		if left > 0 and dropper != null and dropper.is_inside_tree():
			DroppedItem.spawn(dropper, data, left, down)


## Filas para la interfaz, por nombre: [ItemData, lo que pide, lo que hay].
static func rows(cost: Dictionary, inventory: Inventory) -> Array:
	var out := []
	for id: StringName in cost:
		var data := ItemCatalog.get_item(id)
		if data == null:
			continue
		out.append([data, int(cost[id]), inventory.get_item_count(data) if inventory else 0])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[0] as ItemData).get_display_name() < (b[0] as ItemData).get_display_name())
	return out


## Unidades en total (para avisos cortos).
static func total(cost: Dictionary) -> int:
	var sum := 0
	for id: StringName in cost:
		sum += int(cost[id])
	return sum


## «12 piedra · 4 madera».
static func describe(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for row: Array in rows(cost, null):
		parts.append("%d %s" % [row[1], (row[0] as ItemData).get_display_name().to_lower()])
	return " · ".join(parts)


static func add(cost: Dictionary, id: StringName, amount: int) -> void:
	if amount != 0:
		cost[id] = int(cost.get(id, 0)) + amount


static func cell_key(cell_size: float) -> String:
	return "%.3f" % cell_size


static func _add_count(counts: Dictionary, mat_id: String, cell: String, n: int) -> void:
	if not counts.has(mat_id):
		counts[mat_id] = {}
	counts[mat_id][cell] = int(counts[mat_id].get(cell, 0)) + n
