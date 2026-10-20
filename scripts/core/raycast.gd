class_name Raycast
extends RefCounted

## Rayos contra la física desde cualquier nodo del mundo, para no repetir la consulta en cada sitio.
## La máscara se pide siempre: PhysicsRayQueryParameters3D.create sin ella mira todas las capas.

## Primer choque de [from] a [to] en las capas de [mask], sin los cuerpos de [exclude]: {} si no da
## en nada (ver PhysicsDirectSpaceState3D.intersect_ray).
static func cast(context: Node3D, from: Vector3, to: Vector3, mask: int,
		exclude: Array[RID] = []) -> Dictionary:
	return context.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, mask, exclude))


## El suelo bajo [point] siguiendo [up]: el rayo va de [above] m por encima a [below] m por debajo.
static func ground(context: Node3D, point: Vector3, up: Vector3, above: float, below: float, mask: int,
		exclude: Array[RID] = []) -> Dictionary:
	return cast(context, point + up * above, point - up * below, mask, exclude)
