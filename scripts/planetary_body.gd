extends CharacterBody3D
class_name PlanetaryBody

## Clase base de cualquier entidad física sobre la superficie de un planeta: mantiene el planeta más
## cercano y la dirección de gravedad, y ofrece alineación/rotación y proyección en espacio esférico.

@export var planets: Node3D

var gravity_direction: Vector3 = Vector3.DOWN
var planet: Node3D


## Alinea el eje Y del cuerpo con -gravity_dir; blend=delta suaviza, blend=1.0 alinea al instante.
func align_to_gravity(gravity_dir: Vector3, blend: float) -> void:
	var up_dir := -gravity_dir.normalized()
	var current_up := global_transform.basis.y
	var rotation_axis := current_up.cross(up_dir)
	var angle := acos(clamp(current_up.dot(up_dir), -1.0, 1.0))
	if angle > 0.001 and rotation_axis.length() > 0.001:
		var rot := Quaternion(rotation_axis.normalized(), angle * blend)
		global_transform.basis = Basis(rot) * global_transform.basis
		orthonormalize()


## Rota el cuerpo para que su eje Z apunte hacia target_dir (ya proyectado en el plano de gravedad).
func rotate_toward_direction(target_dir: Vector3, delta: float, speed: float = 8.0) -> void:
	if target_dir.length() < 0.1:
		return
	var current_forward := global_transform.basis.z
	var angle := acos(clamp(current_forward.dot(target_dir), -1.0, 1.0))
	if angle > deg_to_rad(5.0):
		var axis := current_forward.cross(target_dir)
		if axis.length() < 0.01:
			axis = global_transform.basis.y
		var rot := Quaternion(axis.normalized(), angle * delta * speed)
		global_transform.basis = Basis(rot) * global_transform.basis
		orthonormalize()


## Proyecta dir sobre el plano perpendicular a gravity_direction (ZERO si el resultado es degenerado).
func project_on_gravity_plane(dir: Vector3) -> Vector3:
	var n := gravity_direction.normalized()
	var projected := dir - n * dir.dot(n)
	if projected.length() < 0.001:
		return Vector3.ZERO
	return projected.normalized()


## True si hay geometría de terreno bajo el cuerpo (para esperar a que el voxel esté generado).
func is_ground_ready() -> bool:
	if not planet:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		global_position - gravity_direction * 2.0,
		planet.global_position
	)
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Asigna a 'planet' el planeta más cercano de 'planets'.
func update_nearest_planet() -> void:
	if not planets or planets.get_child_count() == 0:
		return
	var closest: Node3D = null
	var closest_dist := INF
	for p in planets.get_children():
		var dist := global_position.distance_to(p.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = p
	planet = closest
