class_name ItemData
extends Resource
const config = preload("res://scripts/config.gd")

enum Category {MATERIAL, TOOL, WEAPON, CONSUMABLE, ARMOR, BLOCK}
enum ToolType {NONE, PICKAXE, AXE, HAMMER, TORCH}
## Los valores nuevos van al final: los .tres guardan el número, no el nombre.
enum WeaponType {NONE, SWORD, SPEAR, BOW, CANNON, AXE, MACE, SLINGSHOT}
## Cómo muerde el golpe. Solo cambia la sensación (sonido, sangre, empuje), no la cuenta.
enum DamageKind {SLASH, BLUNT, PIERCE}
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
## Ritmo de los golpes: escala de tiempo de la animación de ataque (>1 más rápido).
@export var attack_speed: float = 1.0

@export_group("Combat")
## Distancia del agarre a la punta del arma, en metros. Es la hoja que barre el golpe.
@export var reach: float = 0.0
## Distancia del agarre a donde empieza la parte que corta (la mano y el mango no hieren).
@export var blade_start: float = 0.15
## Grosor del barrido, en metros: una maza golpea con más cabeza que el filo de una espada.
@export var blade_radius: float = 0.08
@export var damage_kind: DamageKind = DamageKind.SLASH
## Estamina que cuesta un golpe ligero; el pesado cuesta 1,6 veces esto.
@export var stamina_cost: float = 16.0
## Desgaste de la guardia del rival por golpe: al romperla, se tambalea.
@export var poise_damage: float = 20.0
## Multiplicador de daño y desgaste del golpe pesado a carga máxima.
@export var heavy_multiplier: float = 1.8
## Se empuña con las dos manos (espadones, hachas y martillos grandes): otro repertorio de
## golpes, más lentos, anchos y con más guardia mientras se descargan.
@export var two_handed: bool = false
## Munición que consume al disparar (id de item). Vacío = se lanza a sí misma (lanza).
@export var ammo_id: StringName = &""
## Velocidad de salida del proyectil a tensión completa, en m/s.
@export var projectile_speed: float = 0.0
## Segundos para tensar del todo.
@export var draw_time: float = 0.8
## Se puede arrojar (lanzas): el arma sale de la mano y hay que recogerla.
@export var throwable: bool = false

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
	reach = source.reach
	blade_start = source.blade_start
	blade_radius = source.blade_radius
	damage_kind = source.damage_kind
	stamina_cost = source.stamina_cost
	poise_damage = source.poise_damage
	heavy_multiplier = source.heavy_multiplier
	two_handed = source.two_handed
	ammo_id = source.ammo_id
	projectile_speed = source.projectile_speed
	draw_time = source.draw_time
	throwable = source.throwable
	attack_animation = source.attack_animation
	idle_animation = source.idle_animation
	running_animation = source.running_animation
	is_attack_animation = source.is_attack_animation
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


## Sirve para pegar: lleva hoja que barre golpes (espadas, hachas, mazas, lanzas, y las
## herramientas con alcance, que también hieren).
func is_melee() -> bool:
	return reach > 0.0 and weapon_type != WeaponType.BOW and weapon_type != WeaponType.SLINGSHOT \
		and weapon_type != WeaponType.CANNON


## Dispara o se arroja apuntando: arco, tirachinas y lanza.
func is_ranged() -> bool:
	return weapon_type == WeaponType.BOW or weapon_type == WeaponType.SLINGSHOT or throwable


## Se lleva en la mano izquierda (el arco y el tirachinas se sujetan con la izquierda y la
## derecha tensa).
func is_left_handed() -> bool:
	return weapon_type == WeaponType.BOW or weapon_type == WeaponType.SLINGSHOT


	
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
