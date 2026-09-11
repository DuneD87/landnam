class_name AmbientAnimal extends CharacterBody3D

## Assigned by the shared spawner before activation; subclasses consume their settings.
var profile: AmbientFaunaProfile

## Pool lifecycle. Subclasses implement movement and reset their own state in activate().
var active: bool = false
var habitat: AmbientFaunaHabitat


func activate(point: Vector3, environment: AmbientFaunaHabitat,
		_rng: RandomNumberGenerator) -> void:
	habitat = environment
	global_position = point
	velocity = Vector3.ZERO
	active = true
	process_mode = Node.PROCESS_MODE_INHERIT
	show()
	reset_physics_interpolation()


func deactivate() -> void:
	active = false
	velocity = Vector3.ZERO
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED
