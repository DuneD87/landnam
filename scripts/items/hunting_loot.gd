class_name HuntingLoot
extends RefCounted

const Config = preload("res://scripts/config.gd")

## Lo que da un animal muerto al despellejarlo (con algo que despelleje en la mano: SkinningTrait).
## Lo que da lo dice cada animal en su escena (NPCController.butcher_loot, un LootTable) o, la fauna
## pequeña, su perfil (AmbientFaunaProfile.butcher_loot, que pasa a su FaunaCorpse); aquí solo se
## escala por su tamaño y por el cuchillo. El que no lo diga da carne y piel según el grosor de su
## cuerpo. Ver docs/items.md.

const MEAT := &"raw_meat"
const HIDE := &"raw_hide"


## Llena el inventario del cadáver ([body]: un NPCController muerto o un FaunaCorpse) con lo que da.
## Se suma a lo que ya llevara (las flechas y lanzas que se le quedaron clavadas). [yield_mult] es el
## del cuchillo.
static func fill(body: Node3D, yield_mult: float) -> void:
	var inventory: Inventory = body.inventory
	var loot: LootTable = body.butcher_loot
	if loot == null:
		loot = _by_bulk(body)
	loot.roll_into(inventory, clampf(body.body_size, 0.3, 2.0) * yield_mult)
	inventory.inventory_changed.emit()


## Sin lo suyo: carne y piel por el grueso de su cuerpo (butcher_shape).
static func _by_bulk(body: Node3D) -> LootTable:
	var radius: float = (body.butcher_shape() as Vector2).x
	var loot := LootTable.new()
	for entry in [[MEAT, clampi(roundi(radius * 6.0), 1, 8)], [HIDE, clampi(roundi(radius * 3.0), 1, 4)]]:
		var line := LootEntry.new()
		line.item = entry[0]
		line.amount = entry[1]
		loot.entries.append(line)
	return loot
