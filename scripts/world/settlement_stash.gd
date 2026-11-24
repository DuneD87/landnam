class_name SettlementStash extends Node3D

## Un arcón, una caja, un barril o un saco de una casa de los poblados (SettlementProp de esas clases, que
## SettlementManager envuelve en esto): se abre con E como un botín (InventoryUI.open_loot) y tiene lo que
## le toca hoy (SettlementTrade.stash: sale cada día, menos lo que se ha llevado el jugador).
##
## Llevarse lo suyo es robar: se apunta (SettlementTrade.take_stash) y, si lo ve alguien del poblado
## (SettlementVillage.robbed), el poblado le guarda rencor. Lo que deja el jugador sigue siendo suyo: puede
## volver a cogerlo sin que cuente. Lo que deja se pierde cuando la casa se quita (es decorado).

const GROUP := &"settlement_stash"
## Lo que se envuelve, y el título de la ventana de cada uno.
const KINDS := {&"chest": "VILLAGE_STASH_CHEST", &"crate": "VILLAGE_STASH_CRATE",
	&"barrel": "VILLAGE_STASH_BARREL", &"sack": "VILLAGE_STASH_SACK"}
const SLOTS := 12

## "<poblado>:<casa>:<adorno>".
var key := ""
var kind := &"chest"
var village_index := -1
var manager: SettlementManager
var inventory: Inventory
## Lo suyo que sigue dentro y lo que ha dejado el jugador: id (String) -> cuántos.
var _owned := {}
var _deposits := {}
var _filling := false


func _ready() -> void:
	add_to_group(GROUP)


## Lo abre para [player] (PlayerController) con lo que tiene hoy.
func open(player: Node) -> void:
	if manager == null:
		return
	refill()
	player.inventory_ui.open_loot(inventory, String(KINDS.get(kind, "INV_LOOT")))
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## Lo de hoy (SettlementTrade.stash) más lo que dejó el jugador.
func refill() -> void:
	if inventory == null:
		inventory = Inventory.new(SLOTS)
		inventory.name = "Inventory"
		add_child(inventory)
		inventory.inventory_changed.connect(_on_changed)
	_filling = true
	inventory.clear()
	_owned.clear()
	var today := manager.trade.stash(key, kind)
	for id: StringName in today:
		var data := ItemCatalog.get_item(id)
		if data == null:
			continue
		var added := int(today[id]) - inventory.add_item(data, int(today[id]))
		if added > 0:
			_owned[String(id)] = added
	for id: String in _deposits.keys():
		var data := ItemCatalog.get_item(StringName(id))
		if data == null:
			_deposits.erase(id)
			continue
		var left := inventory.add_item(data, int(_deposits[id]))
		_deposits[id] = int(_deposits[id]) - left
	_filling = false


## Algo ha entrado o salido: lo que sobra de lo que había es del jugador; lo que falta sale primero de lo
## que dejó él y después de lo suyo, y eso es robar.
func _on_changed() -> void:
	if _filling:
		return
	var now := {}
	for item in inventory.get_all_items():
		if item != null and item.data != null:
			now[String(item.data.id)] = int(now.get(String(item.data.id), 0)) + item.quantity
	var stolen := {}
	var value := 0.0
	var ids := {}
	for id in now:
		ids[id] = true
	for id in _owned:
		ids[id] = true
	for id in _deposits:
		ids[id] = true
	for id: String in ids:
		var owned := int(_owned.get(id, 0))
		var mine := int(_deposits.get(id, 0))
		var count := int(now.get(id, 0))
		if count > owned + mine:
			_deposits[id] = count - owned
			continue
		var gone := owned + mine - count
		if gone <= 0:
			continue
		var back := mini(gone, mine)
		_deposits[id] = mine - back
		if int(_deposits[id]) <= 0:
			_deposits.erase(id)
		var taken := gone - back
		if taken > 0:
			_owned[id] = owned - taken
			if int(_owned[id]) <= 0:
				_owned.erase(id)
			stolen[id] = taken
			value += ItemValue.of(ItemCatalog.get_item(StringName(id))) * taken
	if not stolen.is_empty():
		manager.stash_taken(self, stolen, value)
