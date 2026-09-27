class_name MeleeSweep
extends RefCounted

## Barrido de una hoja (un segmento con grosor) de un fotograma de física al siguiente contra los
## Hurtbox. Un golpe rápido recorre medio metro por tick: consultar solo la pose actual deja
## huecos por los que pasa un oso entero, así que se interpolan poses intermedias entre la
## anterior y la actual hasta que la separación es menor que el grosor de la hoja.
##
## Cada dueño se golpea una sola vez por barrido (reset() al empezar el siguiente golpe). Si en
## el mismo tick la hoja toca varias partes de un mismo cuerpo, cuenta la que más duele.

## Grosor de la hoja (radio de la cápsula), en metros.
var radius: float = 0.08
## Capas contra las que barre: los hurtboxes.
var mask: int = Hurtbox.LAYER
## Áreas propias a ignorar (los hurtboxes de quien golpea).
var exclude: Array[RID] = []
## Máximo de poses intermedias por tick.
var max_substeps: int = 10

var _prev_base: Vector3
var _prev_tip: Vector3
var _has_prev: bool = false
var _hit_owners: Dictionary = {}
var _shape := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


func _init(blade_radius: float = 0.08) -> void:
	radius = blade_radius
	_query.collide_with_areas = true
	_query.collide_with_bodies = false


## Olvida la pose anterior y los golpes dados: empieza un golpe nuevo.
func reset() -> void:
	_has_prev = false
	_hit_owners.clear()


## Marca a un dueño como ya golpeado (p. ej. por otra fuente del mismo ataque).
func mark_hit(owner: Object) -> void:
	_hit_owners[owner.get_instance_id()] = true


func has_hit(owner: Object) -> bool:
	return _hit_owners.has(owner.get_instance_id())


## Barre de la pose anterior a [base]–[tip] (mundo) y devuelve los golpes nuevos:
## [{hurtbox, point, direction}], uno por dueño.
func sweep(space: PhysicsDirectSpaceState3D, base: Vector3, tip: Vector3) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if space == null:
		return hits
	if not _has_prev:
		_prev_base = base
		_prev_tip = tip
		_has_prev = true
	var travel := maxf(base.distance_to(_prev_base), tip.distance_to(_prev_tip))
	var steps := clampi(int(ceil(travel / maxf(radius * 1.5, 0.02))), 1, max_substeps)
	var motion := tip - _prev_tip
	var best: Dictionary = {}
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var a := _prev_base.lerp(base, t)
		var b := _prev_tip.lerp(tip, t)
		for result in _overlaps(space, a, b):
			var box := result as Hurtbox
			if box == null or not box.is_enabled() or box.owner_body == null:
				continue
			var key := box.owner_body.get_instance_id()
			if _hit_owners.has(key):
				continue
			if best.has(key) and (best[key].hurtbox as Hurtbox).damage_multiplier >= box.damage_multiplier:
				continue
			var point := Geometry3D.get_closest_point_to_segment(box.global_position, a, b)
			best[key] = {"hurtbox": box, "point": point, "direction": motion}
	for key in best:
		_hit_owners[key] = true
		hits.append(best[key])
	_prev_base = base
	_prev_tip = tip
	return hits


## Esfera que se mueve (una zarpa, una cabeza): el caso de hoja de longitud cero.
func sweep_point(space: PhysicsDirectSpaceState3D, point: Vector3) -> Array[Dictionary]:
	return sweep(space, point, point)


func _overlaps(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Array:
	var axis := b - a
	var length := axis.length()
	_shape.radius = radius
	_shape.height = length + radius * 2.0
	var basis := Basis.IDENTITY
	if length > 1e-4:
		var y := axis / length
		var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		basis = Basis(x, y, x.cross(y))
	_query.shape = _shape
	_query.transform = Transform3D(basis, (a + b) * 0.5)
	_query.collision_mask = mask
	_query.exclude = exclude
	var found: Array = []
	for result in space.intersect_shape(_query, 16):
		found.append(result.get("collider"))
	return found


## Criaturas sin hurtbox (conejos, ratones, pájaros…) que la hoja cruza entre [a] y [b]. No
## tienen capa de colisión propia, así que se miden contra el segmento, como hace la bala.
static func loose_creatures_on_segment(tree: SceneTree, a: Vector3, b: Vector3,
		blade_radius: float) -> Array[AmbientAnimal]:
	var found: Array[AmbientAnimal] = []
	if tree == null:
		return found
	for node in tree.get_nodes_in_group(AmbientAnimal.GROUP):
		var creature := node as AmbientAnimal
		if creature == null or not creature.active or creature is NPCController:
			continue
		var reach := blade_radius + creature.impact_radius
		var closest := Geometry3D.get_closest_point_to_segment(creature.global_position, a, b)
		if closest.distance_squared_to(creature.global_position) <= reach * reach:
			found.append(creature)
	return found
