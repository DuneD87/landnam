class_name GroundFit
extends RefCounted

## Asienta algo redondo y bajo (una hoguera) sobre el terreno, sin que quede hundido por un lado ni
## flotando por otro. Sondea el suelo en el centro y en un corro a su alrededor, ajusta un plano a
## lo que encuentra y lo inclina con la pendiente, hasta [max_tilt] grados. Luego lo baja lo justo
## para que el lado que queda más bajo no flote.


## [center] es donde apunta el jugador, en el suelo; [up], la vertical del planeta ahí.
## Devuelve {ok, transform, tilt (grados de pendiente), rough (m de desnivel que queda)}.
static func fit(space: PhysicsDirectSpaceState3D, center: Vector3, up: Vector3, facing: Vector3,
		radius: float, mask: int, exclude: Array[RID], max_tilt: float = 20.0, samples: int = 8) -> Dictionary:
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var forward := up.cross(right)
	var ring: Array[Vector3] = []
	for i in samples:
		var a := TAU * float(i) / samples
		var hit = _probe(space, center + (right * cos(a) + forward * sin(a)) * radius, up, mask, exclude)
		if hit != null:
			ring.append(hit)
	var middle = _probe(space, center, up, mask, exclude)
	if ring.size() < samples - 2 or middle == null:
		return {"ok": false}
	var points: Array[Vector3] = ring.duplicate()
	points.append(middle)
	var c := Vector3.ZERO
	for p in points:
		c += p
	c /= points.size()
	# Normal del plano (Newell sobre el corro, que va en orden), hacia arriba.
	var n := Vector3.ZERO
	for i in ring.size():
		n += (ring[i] - c).cross(ring[(i + 1) % ring.size()] - c)
	if n.length_squared() < 1e-8:
		n = up
	n = n.normalized()
	if n.dot(up) < 0.0:
		n = -n
	var tilt := rad_to_deg(up.angle_to(n))
	if tilt > max_tilt:
		n = up.slerp(n, max_tilt / tilt).normalized()
	var low := 0.0
	var high := 0.0
	for p in points:
		var r := (p - c).dot(n)
		low = minf(low, r)
		high = maxf(high, r)
	# El centro del objeto, sobre el plano en la vertical de donde se apunta, y algo más bajo para
	# que lo más hundido del terreno no deje huecos.
	var to_center: Vector3 = middle - c
	var origin := c + (to_center - n * to_center.dot(n)) + n * clampf(low * 0.6, -0.1, 0.0)
	var z := facing - n * facing.dot(n)
	z = z.normalized() if z.length_squared() > 1e-6 else n.cross(right).normalized()
	var basis := Basis(n.cross(z).normalized(), n, z)
	return {"ok": true, "transform": Transform3D(basis, origin), "tilt": tilt, "rough": high - low}


static func _probe(space: PhysicsDirectSpaceState3D, at: Vector3, up: Vector3, mask: int, exclude: Array[RID]):
	var from := at + up * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, from - up * 2.3, mask)
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	return hit.position if not hit.is_empty() else null
