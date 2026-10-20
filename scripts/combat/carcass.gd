class_name Carcass
extends RefCounted

## Lo que queda de un animal despiezado (Butchering): la canal, panza arriba y abierta, sin cabeza,
## sin cola y sin las patas de abajo, la misma para todas las especies y a la medida de cada una (la
## de su cuerpo: butcher_shape, el largo y el grueso). Lo mismo para un animal grande (NPCController)
## que para uno pequeño (FaunaCorpse).
##   - strip(): al quitarle la piel, el cuerpo se esconde y en su sitio queda la canal, sobre el
##     suelo (con su normal) y con el cuello hacia donde tenía la cabeza.
##   - spill_guts(): las vísceras salen al suelo, aparte (GutPile).
## Solo con todo el gore (SettingsManager.GORE_FULL). clear() lo deja como estaba (al volver la
## criatura del pool).
##
## La canal es la de un caballo, de tools/combat/build_carcass.py (sobre Lowpoly Horse Skeleton
## (Rigged), de Azazel750, Sketchfab, CC-BY 4.0): a lo largo de +Z (el cuello delante), panza arriba
## (+Y), el suelo en y = 0 y el origen bajo el centro del tronco.

const SCENE := preload("res://models/animals/carcass/carcass.glb")
const META := &"carcass"
## La cápsula del caballo (radio, alto; Horse.tscn), a cuya medida está la canal.
const HORSE_CAPSULE := Vector2(0.75, 2.6)
## Lo que puede ensancharse o estrecharse respecto a escalarlo igual en todo, para no deformarlo.
const CROSS_LIMITS := Vector2(0.75, 1.35)


## Quita la piel a [body] (un NPCController muerto o un FaunaCorpse): esconde su cuerpo y deja la
## canal en el suelo bajo [center] (mundo, el centro del cuerpo).
static func strip(body: Node3D, center: Vector3, up: Vector3) -> void:
	var state: Dictionary = body.get_meta(META, {})
	if SettingsManager.gore_level() < SettingsManager.GORE_FULL or state.get("node") != null:
		return
	var hit := _ground(body, center, up)
	if hit.is_empty():
		return
	var ground_up := (hit.normal as Vector3).normalized()
	var forward := _head_point(body) - center
	forward -= ground_up * forward.dot(ground_up)
	if forward.length_squared() < 1e-4:
		forward = _facing(body) - ground_up * _facing(body).dot(ground_up)
	forward = forward.normalized()
	var side := ground_up.cross(forward).normalized()
	var size := _size(body)
	var carcass := SCENE.instantiate() as Node3D
	carcass.name = "Carcass"
	body.add_child(carcass)
	var basis := Basis(side * size.x, ground_up * size.y, forward * size.z)
	carcass.global_transform = Transform3D(basis, hit.position)
	state.node = carcass
	state.hidden = []
	var model: Node3D = body.butcher_model()
	if model != null and model.visible:
		model.visible = false
		state.hidden.append(model)
	body.set_meta(META, state)


## Saca las vísceras de [body] al suelo junto a [point] (mundo), hacia [side] (horizontal), del
## tamaño del animal ([radius], m).
static func spill_guts(body: Node3D, point: Vector3, side: Vector3, up: Vector3, radius: float) -> void:
	if SettingsManager.gore_level() < SettingsManager.GORE_FULL:
		return
	var guts := GutPile.spawn(body, point, side, up, radius)
	if guts == null:
		return
	var state: Dictionary = body.get_meta(META, {})
	if state.is_empty():
		state = {node = null, hidden = []}
		body.set_meta(META, state)
	state.guts = guts


## Lo deja todo como estaba: el cuerpo a la vista, sin canal ni vísceras.
static func clear(body: Node3D) -> void:
	var state: Dictionary = body.get_meta(META, {})
	if state.is_empty():
		return
	for key in ["node", "guts"]:
		var node: Node = state.get(key)
		if node != null and is_instance_valid(node):
			node.queue_free()
	for node: Node3D in state.hidden:
		if is_instance_valid(node):
			node.visible = true
	body.remove_meta(META)


## La medida de [body] respecto al caballo (butcher_shape: el grueso y el largo del cuerpo, como el
## radio y el alto de su cápsula): a lo largo (Z), por el largo; de través (X, Y), por el grueso, sin
## apartarse de escalarlo igual más de CROSS_LIMITS.
static func _size(body: Node3D) -> Vector3:
	var shape: Vector2 = body.butcher_shape()
	var along := shape.y / HORSE_CAPSULE.y
	var cross := clampf(shape.x / HORSE_CAPSULE.x, along * CROSS_LIMITS.x, along * CROSS_LIMITS.y)
	return Vector3(cross, cross, along)


## Hacia dónde mira el cuerpo sin esqueleto: las criaturas grandes, a +Z; la fauna pequeña, a -Z.
static func _facing(body: Node3D) -> Vector3:
	return -body.global_basis.z if body is FaunaCorpse else body.global_basis.z


## Dónde tiene la cabeza (mundo): el hueso que acaba en "head" con más huesos debajo.
static func _head_point(body: Node3D) -> Vector3:
	var skeleton: Skeleton3D = body.get_skeleton()
	if skeleton == null:
		return body.global_position + _facing(body)
	var best := -1
	var best_count := -1
	for bone in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(bone).to_lower()
		if not name.ends_with("head") or name.contains("end") or name.contains("slider"):
			continue
		var count := _descendants(skeleton, bone)
		if count > best_count:
			best = bone
			best_count = count
	if best < 0:
		return body.global_position + _facing(body)
	return skeleton.global_transform * skeleton.get_bone_global_pose(best).origin


static func _descendants(skeleton: Skeleton3D, bone: int) -> int:
	var count := 0
	for child in skeleton.get_bone_children(bone):
		count += 1 + _descendants(skeleton, child)
	return count


## El suelo bajo [point] (terreno, grids, barcos), por la gravedad: {position, normal}, o vacío.
static func _ground(body: Node3D, point: Vector3, up: Vector3) -> Dictionary:
	return Raycast.ground(body, point, up, 2.0, 4.0, PhysicsLayers.WORLD)
