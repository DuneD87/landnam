class_name ToolGrip
extends RefCounted

## Las herramientas antiguas (el hacha y el pico de piedra) traen la escala y el giro con que
## colgaban del hueso de la mano (RIGHT_GRIP dice dónde quedaba su marco de agarre). Para que el
## puño las cierre como a las armas de combate, perpendiculares al antebrazo, se pasan a ese marco
## (+Y del mango hacia la cabeza, +Z hacia donde golpea, en metros) enderezadas: el mango recto a
## lo largo de +Y y la cabeza abierta a lo largo de +Z, con el filo o la punta por delante. La
## mano sigue a la misma altura del mango.

## Fracciones de la altura (desde abajo) donde acaba el extremo del mango y empieza la cabeza.
const BUTT := 0.15
const HEAD := 0.75


## El transform de [node] (la raíz de la escena, como colgaba del hueso) dentro del marco de
## agarre.
static func align(node: Node3D) -> Transform3D:
	var xf := CombatPose.RIGHT_GRIP.affine_inverse() * node.transform
	var points := PackedVector3Array()
	_collect(node, xf, points)
	if points.size() < 4:
		return xf
	var low := INF
	var high := -INF
	for p in points:
		low = minf(low, p.y)
		high = maxf(high, p.y)
	# El mango va del centro de su extremo al de la cabeza (las mallas son de pocos vértices, casi
	# ninguno a lo largo del mango). Su eje pasa a ser +Y, y el punto del eje más cercano a la mano,
	# el agarre.
	var butt := _center_between(points, low, lerpf(low, high, BUTT))
	var axis := (_center_between(points, lerpf(low, high, HEAD), high) - butt).normalized()
	var grip := butt - axis * butt.dot(axis)
	var straight := Basis(Quaternion(axis, Vector3.UP))
	# La cabeza, abierta a lo largo de +Z: el filo del hacha sigue por delante, como colgaba.
	var xx := 0.0
	var zz := 0.0
	var xz := 0.0
	for p in points:
		if p.y > lerpf(low, high, HEAD):
			var q := straight * (p - grip)
			xx += q.x * q.x
			zz += q.z * q.z
			xz += q.x * q.z
	var angle := 0.5 * atan2(2.0 * xz, xx - zz)
	var spread := Vector3(cos(angle), 0.0, sin(angle))
	if spread.z < 0.0:
		spread = -spread
	var turn := Basis(Quaternion(spread, Vector3.BACK)) if spread.z < 0.999 else Basis.IDENTITY
	var basis := turn * straight
	return Transform3D(basis, -(basis * grip)) * xf


static func _collect(node: Node, xf: Transform3D, points: PackedVector3Array) -> void:
	var mesh_node := node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		for surface in mesh_node.mesh.get_surface_count():
			for vertex in mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				points.append(xf * (vertex as Vector3))
	for child in node.get_children():
		if child is Node3D:
			_collect(child, xf * (child as Node3D).transform, points)


## Centro de la caja de los puntos con la altura entre [from] y [to].
static func _center_between(points: PackedVector3Array, from: float, to: float) -> Vector3:
	var box := AABB()
	var first := true
	for p in points:
		if p.y >= from and p.y <= to:
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box.get_center()
