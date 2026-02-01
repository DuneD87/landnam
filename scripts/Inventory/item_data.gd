# item_data.gd
class_name ItemData
extends Resource

enum Category {MATERIAL, TOOL, WEAPON, CONSUMABLE, ARMOR}
enum ToolType {NONE, PICKAXE, AXE, HAMMER}
enum WeaponType {NONE, SWORD, SPEAR, BOW}
enum ArmorSlot {NONE, HEAD, CHEST, HANDS, LEGS, FEET}

@export var id: StringName  # "stone_pickaxe"
@export var display_name: String
@export var description: String
@export var icon: Texture2D
@export var category: Category
@export var scene_path: String

@export_group("Stacking")
@export var stackable: bool = true
@export var max_stack: int = 99

@export_group("Tool Stats")
@export var tool_type: ToolType = ToolType.NONE
@export var mining_power: int = 0
@export var harvest_multiplier: float = 1.0

@export_group("Weapon Stats")
@export var weapon_type: WeaponType = WeaponType.NONE
@export var damage: int = 0
@export var attack_speed: float = 1.0

@export_group("Armor Stats")
@export var armor_slot: ArmorSlot = ArmorSlot.NONE
@export var defense: int = 0
@export var resistance: float = 0.0

@export_group("Durability")
@export var has_durability: bool = false
@export var max_durability: int = 100


# Valida si este item puede equiparse en un slot específico
func can_equip_in_slot(slot_type: String) -> bool:
	match slot_type:
		"head":
			return category == Category.ARMOR and armor_slot == ArmorSlot.HEAD
		"chest":
			return category == Category.ARMOR and armor_slot == ArmorSlot.CHEST
		"hands":
			return category == Category.ARMOR and armor_slot == ArmorSlot.HANDS
		"legs":
			return category == Category.ARMOR and armor_slot == ArmorSlot.LEGS
		"feet":
			return category == Category.ARMOR and armor_slot == ArmorSlot.FEET
		"main_hand":
			return category == Category.WEAPON
		"off_hand":
			return category == Category.WEAPON or category == Category.TOOL
		"tool":
			return category == Category.TOOL
		_:
			return false
