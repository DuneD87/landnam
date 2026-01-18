extends StaticBody3D
class_name PlanetItem

const config = preload("res://scripts/config.gd")

signal destroyed(type: config.OBJECT_TYPE, position: Vector3, amount: int, item_data: ItemData)

@export var type: config.OBJECT_TYPE
@export var health: int = 300
@export var drop_amount_min: int = 1
@export var drop_amount_max: int = 3

func take_damage(damage: int) -> void:
	health -= damage
	
	if health <= 0:
		_on_destroyed()

func _on_destroyed() -> void:
	destroyed.emit(type, global_position, get_drop_amount(), ItemData.new(type))
	queue_free()

func get_drop_amount() -> int:
	return randi_range(drop_amount_min, drop_amount_max)
