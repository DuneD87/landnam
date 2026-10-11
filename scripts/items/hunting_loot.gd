class_name HuntingLoot
extends RefCounted

const Config = preload("res://scripts/config.gd")

## Lo que da un animal muerto al despellejarlo (con algo que despelleje en la mano: SkinningTrait).
## Lo que da lo dice cada animal en su escena (NPCController.butcher_loot, un LootTable); aquí solo
## se escala por su tamaño y por el cuchillo. El que no lo diga da carne y piel según el grosor de
## su cuerpo. Ver docs/items.md.

const MEAT := &"raw_meat"
const HIDE := &"raw_hide"


## Llena el inventario del cadáver con lo que da. [yield_mult] es el del cuchillo.
static func fill(npc: NPCController, yield_mult: float) -> void:
	var inventory := npc.inventory
	inventory.clear()
	var loot := npc.butcher_loot if npc.butcher_loot != null else _by_bulk(npc)
	loot.roll_into(inventory, clampf(npc.body_size, 0.3, 2.0) * yield_mult)
	inventory.inventory_changed.emit()


## Sin lo suyo: carne y piel por el radio de su cápsula de colisión.
static func _by_bulk(npc: NPCController) -> LootTable:
	var capsule := npc.collision_shape.shape as CapsuleShape3D if npc.collision_shape != null else null
	var radius := capsule.radius if capsule != null else 0.4
	var loot := LootTable.new()
	for entry in [[MEAT, clampi(roundi(radius * 6.0), 1, 8)], [HIDE, clampi(roundi(radius * 3.0), 1, 4)]]:
		var line := LootEntry.new()
		line.item = entry[0]
		line.amount = entry[1]
		loot.entries.append(line)
	return loot
