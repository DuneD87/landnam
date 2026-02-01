extends RigidBody3D
class_name ItemPhysics

const config = preload("res://scripts/config.gd")

signal destroyed(position: Vector3, amount: int, item_data: ItemData)

@export var health: int = 300
@export var drop_amount_min: int = 1
@export var drop_amount_max: int = 3
@export var item_data: ItemData

@onready var planets: Node3D = $"../Planets"
@export var planet: Node3D
@onready var highlight_light: OmniLight3D

@export var equipped: bool = false  # Corregido typo: equiped -> equipped


func set_equipped(value: bool) -> void:
	equipped = value
	if equipped:
		# Desactivar físicas y colisiones
		freeze = true
		set_physics_process(false)
		collision_layer = 0
		collision_mask = 0
		# Ocultar luz
		if highlight_light:
			highlight_light.visible = false
	else:
		# Reactivar físicas y colisiones
		freeze = false
		set_physics_process(true)
		collision_layer = 1  # Ajusta según tu configuración
		collision_mask = 1   # Ajusta según tu configuración
		if highlight_light:
			highlight_light.visible = true

func _ready() -> void:
	if equipped:
		freeze = true
		return
	
	highlight_light = OmniLight3D.new()
	highlight_light.light_color = Color(1.0, 0.9, 0.5)
	highlight_light.light_energy = 10.8
	highlight_light.omni_range = 2.5
	highlight_light.omni_attenuation = 1.5
	add_child(highlight_light)


func _physics_process(delta: float) -> void:
	if planets == null or planets.get_children().size() == 0 or equipped:
		return
	
	# Encontrar planeta más cercano
	var closest_distance = INF
	for _planet in planets.get_children():
		var distance = global_position.distance_to(_planet.global_position)
		if distance < closest_distance:
			closest_distance = distance
			planet = _planet
	
	var direction_to_planet = (planet.planet.global_position - global_position).normalized()
	apply_central_force(direction_to_planet * planet.gravity_strength * mass)


func take_damage(damage: int) -> void:
	health -= damage
	if health <= 0:
		_on_destroyed()


func _on_destroyed() -> void:
	destroyed.emit(global_position, get_drop_amount(), item_data)
	queue_free()


func get_drop_amount() -> int:
	return randi_range(drop_amount_min, drop_amount_max)
