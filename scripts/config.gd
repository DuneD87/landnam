# config.gd
extends Node

enum ANIMATION {IDLE, RUN, JUMP_START, JUMP_IDLE, JUMP_LAND, ATTACK_1, SPRINT, FALLING, SWIM, SWIM_IDLE}
enum OBJECT_TYPE {NONE, WOOD, STONE, FIBER}

const ITEM_CONFIG: Dictionary = {
	OBJECT_TYPE.WOOD: {
		"object_name": "Madera",
		"description": "Madera obtenida de los árboles.",
		"icon": "res://textures/icons/icon_wood.png",
		"stackable" : true,
		"max_stack": 99,
		"value": 5,
	},
	OBJECT_TYPE.STONE: {
		"object_name": "Piedra",
		"description": "Piedra común extraída de rocas.",
		"icon": "res://textures/icons/icon_stone.png",
		"stackable" : true,
		"max_stack": 99,
		"value": 3,
	},
	OBJECT_TYPE.FIBER: {
		"object_name": "Fibra",
		"description": "Fibra vegetal para fabricar cuerdas.",
		"icon": "res://textures/icons/icon_fiber.png",
		"stackable" : true,
		"max_stack": 50,
		"value": 2,
	},
}

# Método helper para obtener config de un tipo
static func get_item_config(type: OBJECT_TYPE) -> Dictionary:
	if ITEM_CONFIG.has(type):
		return ITEM_CONFIG[type]
	return {}
