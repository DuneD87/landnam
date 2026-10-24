class_name ItemData
extends Resource

enum Category {MATERIAL, TOOL, WEAPON, CONSUMABLE, ARMOR, BLOCK}
## HOE, la azada, allana el terreno (TerrainLeveling). Los nuevos, al final, como en WeaponType.
enum ToolType {NONE, PICKAXE, AXE, HAMMER, TORCH, HOE}
## Los valores nuevos van al final: los .tres guardan el número, no el nombre.
enum WeaponType {NONE, SWORD, SPEAR, BOW, CANNON, AXE, MACE, SLINGSHOT}
## Cómo muerde el golpe: cada armadura protege distinto de cada uno (Armor), y cambia el sonido,
## la sangre y el empuje.
enum DamageKind {SLASH, BLUNT, PIERCE}
## Se añaden al final para conservar los valores de recursos y partidas existentes.
enum ArmorSlot {NONE, HEAD, CHEST, HANDS, LEGS, FEET, RIGHT_HAND, LEFT_HAND, OFFHAND, BACK}

@export var id: StringName  # "stone_pickaxe"
## Claves de localization/translations.csv (ITEM_<ID> e ITEM_<ID>_DESC); se leen traducidas con
## get_display_name() y get_description(). Un texto que no sea clave sale tal cual.
@export var display_name: String
@export var description: String
@export var icon: Texture2D
@export var category: Category
@export var scene_path: String
@export var attack_animation: AnimationController.Anim = AnimationController.Anim.ATTACK_1
@export var idle_animation: AnimationController.Anim = AnimationController.Anim.IDLE
@export var running_animation: AnimationController.Anim = AnimationController.Anim.RUN
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
## Parte de la protección del que recibe el golpe que no cuenta (0-1, Armor.mitigate): una punta
## fina o un pico entran entre placas y costuras; un filo ancho resbala.
@export_range(0.0, 0.8) var armor_penetration: float = 0.0

@export_group("Guard")
## Lo que para de cada golpe bloqueado (0–1). 0 = con esto no se bloquea. Lo usan los escudos y
## las armas a dos manos (Guard).
@export_range(0.0, 1.0) var guard_reduction: float = 0.0
## Estabilidad (0–100): cuánto de la fuerza del golpe (su desgaste de guardia) aguanta sin gastar
## aguante. Más estable = cada golpe parado cuesta menos.
@export_range(0.0, 100.0) var guard_stability: float = 0.0
## Medio ángulo (grados) delante del cuerpo en el que para golpes.
@export_range(0.0, 180.0) var guard_arc: float = 60.0
## Segundos, desde que se alza la guardia, en los que un golpe cuerpo a cuerpo se para del todo y
## deja vendido al que lo da. 0 = no hace paradas.
@export var parry_window: float = 0.0
## Para flechas y piedras (los escudos; una espada, no).
@export var guard_projectiles: bool = false
## Lo que suena al parar un golpe (id de CombatFx).
@export var guard_sound: StringName = &"block_metal"

@export_group("Armor Stats")
@export var armor_slot: ArmorSlot = ArmorSlot.NONE
## Protección contra cada tipo de golpe en lo que cubre (Armor.mitigate): un golpe de D contra A
## deja D·D/(D + A). Las capas puestas se suman.
@export var armor_slash: float = 0.0
@export var armor_blunt: float = 0.0
@export var armor_pierce: float = 0.0
## Partes que cubre (Armor.Region). Nada marcado = lo de su hueco (Armor.SLOT_COVERAGE).
@export_flags("Cabeza", "Tronco", "Brazos", "Antebrazos", "Manos", "Muslos", "Espinillas", "Pies") var coverage: int = 0

@export_group("Durability")
@export var has_durability: bool = false
@export var max_durability: int = 100

@export_group("Placement")
@export var placeable: bool = false
@export var placeable_on_floor: bool = true
@export var placeable_on_wall: bool = true
@export var placeable_on_ceiling: bool = false
@export var placed_collider_size: Vector3 = Vector3(0.2, 0.5, 0.2)

@export_group("Clasificación")
## Grupo dentro de su categoría (ItemTaxonomy.GROUPS): con él se ordena el inventario y se nombra el
## tipo en la ficha. Vacío = el que le toca por cómo es (ItemTaxonomy.group_of).
@export var group: StringName = &""
## Lo que se puede hacer con el objeto además de lo de arriba: comerlo, quemarlo, asarlo, llevar
## agua, abrigar, despellejar... (ItemTrait). Ver docs/items.md.
@export var traits: Array[ItemTrait] = []

## El nombre en el idioma del juego.
func get_display_name() -> String:
	return tr(display_name)


func get_description() -> String:
	return tr(description) if description != "" else ""


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
	armor_penetration = source.armor_penetration
	attack_animation = source.attack_animation
	idle_animation = source.idle_animation
	running_animation = source.running_animation
	is_attack_animation = source.is_attack_animation
	armor_slot = source.armor_slot
	armor_slash = source.armor_slash
	armor_blunt = source.armor_blunt
	armor_pierce = source.armor_pierce
	coverage = source.coverage
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
	group = source.group
	traits = source.traits.duplicate()


## El rasgo de tipo [type] (un script de ItemTrait, p. ej. EdibleTrait) o null si no lo tiene.
func get_trait(type: Script) -> ItemTrait:
	for item_trait in traits:
		if item_trait != null and is_instance_of(item_trait, type):
			return item_trait
	return null


## Sirve para pegar: lleva hoja que barre golpes (espadas, hachas, mazas, lanzas, y las
## herramientas con alcance, que también hieren).
func is_melee() -> bool:
	return reach > 0.0 and weapon_type != WeaponType.BOW and weapon_type != WeaponType.SLINGSHOT \
		and weapon_type != WeaponType.CANNON


## Dispara o se arroja apuntando: arco, tirachinas y lanza.
func is_ranged() -> bool:
	return weapon_type == WeaponType.BOW or weapon_type == WeaponType.SLINGSHOT or throwable


## Escudo: va en la mano secundaria (ranura OFFHAND) y se alza para bloquear.
func is_shield() -> bool:
	return armor_slot == ArmorSlot.OFFHAND and guard_reduction > 0.0


## Va en cualquier mano: la antorcha, que en la izquierda deja la derecha para un arma o el martillo.
func fits_either_hand() -> bool:
	return tool_type == ToolType.TORCH


## Cabe en el hueco [slot] del equipo: el suyo, o cualquiera de las dos manos si va en las dos.
func fits_slot(slot: ArmorSlot) -> bool:
	if slot == armor_slot:
		return true
	return fits_either_hand() and (slot == ArmorSlot.RIGHT_HAND or slot == ArmorSlot.OFFHAND)


## Su tecla de la barra lo pone o lo quita de la mano izquierda sin tocar la derecha: escudos y
## antorchas.
func is_offhand() -> bool:
	return is_shield() or fits_either_hand()


## Se lleva en la mano izquierda (el arco y el tirachinas se sujetan con la izquierda y la
## derecha tensa).
func is_left_handed() -> bool:
	return weapon_type == WeaponType.BOW or weapon_type == WeaponType.SLINGSHOT
