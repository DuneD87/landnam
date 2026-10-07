class_name DroppedItem
extends Node3D

## Algo soltado en el suelo (arrastrado fuera del inventario): cae delante de quien lo suelta y se
## recoge con la tecla de acción. Las armas y escudos de combate se ven con su malla, tumbados
## sobre su cara más ancha; lo demás, en un saquito. Como la lanza clavada, no es un cuerpo
## físico: cae a mano a lo largo de la gravedad hasta el suelo que encuentra un rayo, y sigue al
## origen flotante (o al barco sobre el que cae).

const GROUP := &"dropped_item"
## Terreno, grids y barcos.
const WORLD_MASK := 1
## Distancia a la que se recoge (m, desde los pies de quien recoge).
const PICKUP_RANGE := 2.6
## Mirándolo (ángulo entre la vista y el objeto, grados) se recoge antes que otras cosas cercanas.
const LOOK_ANGLE := 30.0
## Desde dónde cae: altura de la mano sobre los pies y cuánto por delante del cuerpo (m).
const DROP_HEIGHT := 1.1
const DROP_AHEAD := 0.7
## Hasta dónde busca suelo por debajo de la mano (m): por un barranco abajo, también.
const GROUND_SEARCH := 60.0
const GRAVITY := 9.8
## Escenas con la malla en metros, que se pueden dejar tal cual en el suelo (las de las
## herramientas antiguas vienen a la escala del hueso de la mano).
const MESH_SCENES := "res://scenes/items/weapons/combat/"

static var _leather: StandardMaterial3D

var item_data: ItemData
var quantity: int = 1

var _down: Vector3 = Vector3.DOWN
var _fall_left: float = 0.0
var _fall_speed: float = 0.0


## Suelta [amount] de [data] delante de [dropper] (mira por +Z), con la gravedad [down].
static func spawn(dropper: Node3D, data: ItemData, amount: int, down: Vector3) -> DroppedItem:
	var item := DroppedItem.new()
	item.item_data = data
	item.quantity = amount
	item.name = "Dropped_%s" % data.id
	dropper.get_tree().current_scene.add_child(item)
	var up := -down.normalized()
	var forward := dropper.global_basis.z - up * dropper.global_basis.z.dot(up)
	forward = forward.normalized() if forward.length_squared() > 1e-6 else up.cross(Vector3.RIGHT).normalized()
	var exclude: Array[RID] = []
	if dropper is CollisionObject3D:
		exclude.append((dropper as CollisionObject3D).get_rid())
	item._drop(dropper.global_position + up * DROP_HEIGHT, forward, up, exclude)
	return item


## Lo soltado al alcance de [picker] que se recoge con la tecla de acción. Con [look_dir] (la
## vista desde [look_from]), solo lo que se está mirando; sin ella, lo más cercano.
static func find(picker: Node3D, look_from: Vector3 = Vector3.ZERO, look_dir: Vector3 = Vector3.ZERO) -> DroppedItem:
	var best: DroppedItem = null
	var best_score := INF
	for node in picker.get_tree().get_nodes_in_group(GROUP):
		var item := node as DroppedItem
		if item == null or item.item_data == null or item.quantity <= 0:
			continue
		var d := item.global_position.distance_to(picker.global_position)
		if d > PICKUP_RANGE:
			continue
		var score := d
		if look_dir != Vector3.ZERO:
			var angle := rad_to_deg(look_dir.angle_to(item.global_position - look_from))
			if angle > LOOK_ANGLE:
				continue
			score = angle
		if score < best_score:
			best = item
			best_score = score
	return best


## Lo mete en [inventory]; lo que no cabe se queda en el suelo. Devuelve true si ha entrado algo.
func pick_into(inventory: Inventory) -> bool:
	var left := inventory.add_item(item_data, quantity)
	if left >= quantity:
		return false
	quantity = left
	if quantity <= 0:
		queue_free()
	return true


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group("floating_origin")


## Lo suelta desde la mano [hand] (a la altura de la mano sobre los pies), DROP_AHEAD por delante
## si no hay pared, y lo deja cayendo hasta el suelo de debajo.
func _drop(hand: Vector3, forward: Vector3, up: Vector3, exclude: Array[RID]) -> void:
	var space := get_world_3d().direct_space_state
	var from := hand + forward * DROP_AHEAD
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(hand, from, WORLD_MASK, exclude))
	if not wall.is_empty():
		from = (wall.position as Vector3) - forward * 0.15
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from - up * GROUND_SEARCH,
		WORLD_MASK, exclude))
	# Tumbado sobre el suelo que encuentra (en cuesta, a lo largo de ella), girado al azar.
	var ground_up := up
	if not ground.is_empty() and (ground.normal as Vector3).dot(up) > 0.5:
		ground_up = ground.normal
	var basis := Basis.looking_at(forward - ground_up * forward.dot(ground_up), ground_up)
	global_transform = Transform3D(Basis(ground_up, randf() * TAU) * basis, from)
	add_child(_make_visual())
	_down = -up
	_fall_left = GROUND_SEARCH if ground.is_empty() else (from - (ground.position as Vector3)).dot(up)
	# Sobre un barco, colgado de él y ya en su sitio (cayendo, el barco se movería debajo).
	var holder := ground.get("collider") as Node3D
	if holder is DynamicGridBody:
		global_position = ground.position
		_fall_left = 0.0
		remove_from_group("floating_origin")
		var xform := global_transform
		get_parent().remove_child(self)
		holder.add_child(self)
		global_transform = xform
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if _fall_left <= 0.0:
		set_physics_process(false)
		return
	_fall_speed += GRAVITY * delta
	var step := minf(_fall_speed * delta, _fall_left)
	global_position += _down * step
	_fall_left -= step


## La malla del arma o escudo (en metros), tumbada sobre su cara más ancha con lo de abajo en el
## origen; si no la hay, un saquito.
func _make_visual() -> Node3D:
	var path := item_data.scene_path
	if not path.begins_with(MESH_SCENES) or not ResourceLoader.exists(path):
		return _sack()
	var visual: Node3D = (load(path) as PackedScene).instantiate()
	var box := _local_aabb(visual)
	if box.size == Vector3.ZERO:
		return visual
	# Su eje más fino, hacia arriba.
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var thin: Vector3 = axes[0]
	for axis: Vector3 in axes:
		if box.size.dot(axis) < box.size.dot(thin):
			thin = axis
	var rot := Basis(Quaternion(thin, Vector3.UP))
	var turned := Transform3D(rot, Vector3.ZERO) * box
	var center := turned.get_center()
	visual.transform = Transform3D(rot, -Vector3(center.x, turned.position.y, center.z))
	return visual


## Caja de las mallas de [root] en su propio marco (sin estar aún en el árbol).
static func _local_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xform := Transform3D.IDENTITY
		var node: Node = mi
		while node != root and node is Node3D:
			xform = (node as Node3D).transform * xform
			node = node.get_parent()
		var local := xform * mi.get_aabb()
		box = local if first else box.merge(local)
		first = false
	return box


## Saquito de cuero atado: lo que no tiene malla propia (materiales, ropa, herramientas).
static func _sack() -> Node3D:
	if _leather == null:
		_leather = StandardMaterial3D.new()
		_leather.albedo_color = Color(0.36, 0.25, 0.15)
		_leather.roughness = 0.9
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.2
	sphere.material = _leather
	body.mesh = sphere
	body.position = Vector3(0.0, 0.1, 0.0)
	root.add_child(body)
	var neck := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.035
	cone.bottom_radius = 0.06
	cone.height = 0.08
	cone.material = _leather
	neck.mesh = cone
	neck.position = Vector3(0.0, 0.22, 0.0)
	root.add_child(neck)
	return root
