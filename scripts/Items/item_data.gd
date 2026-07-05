class_name ItemData
extends Resource
const config = preload("res://scripts/config.gd")

enum Category {MATERIAL, TOOL, WEAPON, CONSUMABLE, ARMOR, BLOCK}
enum ToolType {NONE, PICKAXE, AXE, HAMMER, TORCH}
enum WeaponType {NONE, SWORD, SPEAR, BOW}
enum ArmorSlot {NONE, HEAD, CHEST, HANDS, LEGS, FEET, RIGHT_HAND, LEFT_HAND, OFFHAND}

@export var id: StringName  # "stone_pickaxe"
@export var display_name: String
@export var description: String
@export var icon: Texture2D
@export var category: Category
@export var scene_path: String
@export var attack_animation: config.ANIMATION = config.ANIMATION.ATTACK_1
@export var idle_animation: config.ANIMATION = config.ANIMATION.IDLE
@export var running_animation: config.ANIMATION = config.ANIMATION.RUN
@export var surface_material: Material
@export var block_id: int = -1
@export var build_material_id: String = ""
@export var is_attack_animation: bool = true
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

@export_group("Placement")
@export var placeable: bool = false
@export var placeable_on_floor: bool = true
@export var placeable_on_wall: bool = true
@export var placeable_on_ceiling: bool = false
@export var placed_collider_size: Vector3 = Vector3(0.2, 0.5, 0.2)

static func clone(source: ItemData) -> ItemData:
	var copy := ItemData.new()
	copy.copy_from(source)
	return copy
	
func copy_from(source: ItemData) -> void:
	id = source.id
	display_name = source.display_name
	description = source.description
	icon = source.icon
	category = source.category
	scene_path = source.scene_path
	stackable = source.stackable
	max_stack = source.max_stack
	tool_type = source.tool_type
	mining_power = source.mining_power
	harvest_multiplier = source.harvest_multiplier
	weapon_type = source.weapon_type
	damage = source.damage
	attack_speed = source.attack_speed
	armor_slot = source.armor_slot
	defense = source.defense
	resistance = source.resistance
	has_durability = source.has_durability
	max_durability = source.max_durability
	surface_material = source.surface_material
	block_id = source.block_id
	build_material_id = source.build_material_id
	placeable = source.placeable
	placeable_on_floor = source.placeable_on_floor
	placeable_on_wall = source.placeable_on_wall
	placeable_on_ceiling = source.placeable_on_ceiling
	placed_collider_size = source.placed_collider_size


	
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
