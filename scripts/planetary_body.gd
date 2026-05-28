extends CharacterBody3D
class_name PlanetaryBody

## Clase base para cualquier entidad física que vive en la superficie de un planeta.
## Gestiona la referencia al planeta más cercano, la dirección de gravedad y las
## operaciones de alineación / rotación en espacio esférico.
##
## Heredar en lugar de CharacterBody3D:
##   extends PlanetaryBody
##
## Los herederos obtienen automáticamente:
##   - planets (@export): nodo padre que contiene los planetas de la escena
##   - planet:    planeta más cercano (actualizado con update_nearest_planet())
##   - gravity_direction: vector hacia el centro del planeta
##   - align_to_gravity()
##   - rotate_toward_direction()
##   - project_on_gravity_plane()
##   - update_nearest_planet()

@export var planets: Node3D

var gravity_direction: Vector3 = Vector3.DOWN
var planet: Node3D


## Alinea el eje Y del cuerpo al vector opuesto de [param gravity_dir].
## Usar [param blend] = [code]delta[/code] para suavizado progresivo,
## o [param blend] = [code]1.0[/code] para alineación instantánea.
func align_to_gravity(gravity_dir: Vector3, blend: float) -> void:
	var up_dir := -gravity_dir.normalized()
	var current_up := global_transform.basis.y
	var rotation_axis := current_up.cross(up_dir)
	var angle := acos(clamp(current_up.dot(up_dir), -1.0, 1.0))
	if angle > 0.001 and rotation_axis.length() > 0.001:
		var rot := Quaternion(rotation_axis.normalized(), angle * blend)
		global_transform.basis = Basis(rot) * global_transform.basis
		orthonormalize()


## Rota el cuerpo para que su eje Z apunte hacia [param target_dir].
## [param target_dir] debe estar ya proyectado en el plano de gravedad.
## [param speed] controla la velocidad de giro (grados efectivos/frame ∝ speed·delta).
func rotate_toward_direction(target_dir: Vector3, delta: float, speed: float = 8.0) -> void:
	if target_dir.length() < 0.1:
		return
	var current_forward := global_transform.basis.z
	var angle := acos(clamp(current_forward.dot(target_dir), -1.0, 1.0))
	if angle > deg_to_rad(5.0):
		var axis := current_forward.cross(target_dir)
		if axis.length() < 0.01:
			axis = global_transform.basis.y  # vectores casi antiparalelos: girar sobre el eje up local
		var rot := Quaternion(axis.normalized(), angle * delta * speed)
		global_transform.basis = Basis(rot) * global_transform.basis
		orthonormalize()


## Proyecta [param dir] sobre el plano perpendicular a [member gravity_direction]
## y devuelve el resultado normalizado. Devuelve Vector3.ZERO si el vector
## resultante es degenerado (ej: dir paralelo a la gravedad).
func project_on_gravity_plane(dir: Vector3) -> Vector3:
	var n := gravity_direction.normalized()
	var projected := dir - n * dir.dot(n)
	if projected.length() < 0.001:
		return Vector3.ZERO
	return projected.normalized()


## Devuelve true cuando hay geometría de terreno bajo el cuerpo.
## Útil para esperar a que el terreno voxel esté generado antes de activar física.
func is_ground_ready() -> bool:
	if not planet:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		global_position - gravity_direction * 2.0,
		planet.global_position
	)
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Busca en [member planets] el planeta más cercano a la posición actual
## y lo asigna a [member planet].
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
