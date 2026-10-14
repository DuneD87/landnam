class_name LootTable
extends Resource

const Config = preload("res://scripts/config.gd")

## Lo que da algo: un animal al despellejarlo (NPCController.butcher_loot) y, más adelante, lo que
## se rompa o se saquee. Cada cosa lleva el suyo, en su escena o en un .tres propio
## (data/fauna/loot/ los de los animales). Ver docs/items.md.

@export var entries: Array[LootEntry] = []


## Mete en [inventory] una tirada: cada línea, si sale, da su cantidad por [scale], con un ±20 %, y
## al menos uno; las que no crecen (LootEntry.scales), su cantidad justa.
func roll_into(inventory: Inventory, scale: float = 1.0) -> void:
	for entry in entries:
		if entry == null or randf() > entry.chance:
			continue
		var data: ItemData = Config.get_item(entry.item)
		if data == null:
			continue
		var amount := entry.amount
		if entry.scales:
			amount = maxi(1, roundi(float(amount) * scale * randf_range(0.8, 1.2)))
		inventory.add_item(data, amount)
