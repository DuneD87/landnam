# item_data.gd
class_name ItemData extends Resource

enum Category {MATERIAL, TOOL, WEAPON, CONSUMABLE, ARMOR}
enum ToolType {NONE, PICKAXE, AXE, HAMMER}
enum WeaponType {NONE, SWORD, SPEAR, BOW}

@export var id: StringName  # "stone_pickaxe"
@export var display_name: String
@export var description: String
@export var icon: Texture2D
@export var category: Category

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

@export_group("Durability")
@export var has_durability: bool = false
@export var max_durability: int = 100
