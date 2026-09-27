class_name CombatProjectile
extends Node3D

## Flecha, piedra de tirachinas o lanza arrojada. Como la bala de cañón, no es un cuerpo físico:
## avanza a mano cada tick con la gravedad del planeta y sondea con un rayo del punto anterior al
## nuevo, contra el terreno y contra los Hurtbox (áreas). Así no atraviesa nada a 60 m/s.
##
## Al acertar: la flecha y la lanza se clavan (en el terreno o en la criatura, a la que siguen);
## la piedra se pierde. Una lanza clavada en el suelo se puede recoger con la tecla de acción, y
## lo que se clava en una criatura va a parar a su inventario (se recupera al despellejarla).

enum Kind {ARROW, STONE, SPEAR}

## Grupo de las lanzas recogibles del suelo.
const PICKUP_GROUP := &"weapon_pickup"
## Terreno, grids y barcos.
const WORLD_MASK := 1
const MAX_LIFETIME := 8.0
## Segundos que queda algo clavado en el suelo antes de desaparecer (la lanza no caduca).
const STUCK_LIFETIME := 30.0

static var _arrow_mesh: Mesh
static var _pebble_mesh: Mesh

var kind: Kind = Kind.ARROW
var velocity: Vector3 = Vector3.ZERO
var damage: float = 10.0
var poise: float = 10.0
var damage_kind: ItemData.DamageKind = ItemData.DamageKind.PIERCE
## Quien dispara: no se hiere a sí mismo y es el origen del golpe.
var shooter: Node3D
## Item que representa (la lanza, para recogerla; la flecha, para el botín).
var item_data: ItemData
## Nodo planetario para la gravedad (tiene global_pos y gravity_strength).
var planet_node: Node3D

var _exclude: Array[RID] = []
var _age: float = 0.0
var _stuck: bool = false
var _stuck_age: float = 0.0
var _launch_speed: float = 1.0
var _visual: Node3D


## Lanza el proyectil. Añadirlo a la escena ANTES (coloca por global_position). [visual] es la
## malla a usar (la lanza trae la suya); null = la de su tipo.
func launch(from: Vector3, direction: Vector3, speed: float, visual: Node3D = null) -> void:
	velocity = direction.normalized() * speed
	_launch_speed = maxf(speed, 1.0)
	global_position = from
	if visual != null:
		_visual = visual
		add_child(visual)
		visual.transform = Transform3D.IDENTITY
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh_for(kind)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual = mi
		add_child(mi)
	_orient()
	reset_physics_interpolation()


## RIDs que el rayo debe ignorar (el cuerpo y los hurtboxes de quien dispara).
func set_exclude(rids: Array[RID]) -> void:
	_exclude = rids.duplicate()


func _ready() -> void:
	add_to_group("floating_origin")


static func _mesh_for(k: Kind) -> Mesh:
	match k:
		Kind.STONE:
			if _pebble_mesh == null:
				_pebble_mesh = load("res://data/items/meshes/weapons/pebble.res")
			return _pebble_mesh
		_:
			if _arrow_mesh == null:
				_arrow_mesh = load("res://data/items/meshes/weapons/arrow.res")
			return _arrow_mesh


func _physics_process(delta: float) -> void:
	if _stuck:
		_stuck_age += delta
		if kind != Kind.SPEAR and _stuck_age > STUCK_LIFETIME:
			queue_free()
		return
	_age += delta
	if _age > MAX_LIFETIME:
		queue_free()
		return
	if planet_node != null and is_instance_valid(planet_node):
		var down: Vector3 = (planet_node.global_pos - global_position).normalized()
		velocity += down * planet_node.gravity_strength * delta
	var from := global_position
	var to := from + velocity * delta
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = WORLD_MASK | Hurtbox.LAYER
	query.collide_with_areas = true
	query.exclude = _exclude
	# Hasta tres intentos por si el rayo toca hurtboxes apagados o propios.
	for attempt in 3:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var box := hit.collider as Hurtbox
		if box != null and (not box.is_enabled() or box.owner_body == shooter):
			_exclude.append(hit.rid)
			query.exclude = _exclude
			continue
		var loose := _loose_creature(from, hit.position)
		if loose != null:
			_hit_loose(loose)
			return
		if box != null:
			_hit_hurtbox(box, hit.position)
		else:
			_hit_world(hit)
		return
	var creature := _loose_creature(from, to)
	if creature != null:
		_hit_loose(creature)
		return
	global_position = to
	_orient()


func _orient() -> void:
	if velocity.length_squared() < 1e-6:
		return
	var y := velocity.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	global_basis = Basis(x, y, x.cross(y))


func _loose_creature(from: Vector3, to: Vector3) -> AmbientAnimal:
	var found := MeleeSweep.loose_creatures_on_segment(get_tree(), from, to, 0.05)
	return found[0] if not found.is_empty() else null


func _hit_loose(creature: AmbientAnimal) -> void:
	creature.take_damage(damage, shooter)
	queue_free()


func _scaled_damage() -> float:
	# Pierde fuerza con la velocidad (una flecha que cae de lejos pica menos).
	return damage * clampf(velocity.length() / _launch_speed, 0.5, 1.0)


func _hit_hurtbox(box: Hurtbox, point: Vector3) -> void:
	var info := DamageInfo.create(_scaled_damage(), shooter, point, velocity, poise)
	info.kind = damage_kind
	info.knockback = 0.3 if kind == Kind.SPEAR else 0.0
	var applied := box.receive(info)
	if applied > 0.0:
		CombatFx.blood(box.owner_body, point, velocity)
	CombatFx.impact(self, point, damage_kind, true)
	if kind == Kind.STONE:
		queue_free()
		return
	# Se clava: sigue al hurtbox (que sigue al hueso o al cuerpo).
	_stick(point + velocity.normalized() * (0.10 if kind == Kind.ARROW else 0.18), box)
	var npc := box.owner_body as NPCController
	if npc != null and item_data != null and npc.inventory != null:
		if kind == Kind.SPEAR or randf() < 0.6:
			npc.inventory.add_item(item_data, 1)
	# Sin ocupar el cuerpo para siempre: una flecha en un oso se va con el tiempo.
	get_tree().create_timer(12.0 if kind == Kind.ARROW else 25.0).timeout.connect(
		func(): if is_instance_valid(self): queue_free())


func _hit_world(hit: Dictionary) -> void:
	var point: Vector3 = hit.position
	CombatFx.impact(self, point, damage_kind, false)
	if kind == Kind.STONE:
		queue_free()
		return
	var depth := 0.16 if kind == Kind.ARROW else 0.28
	var collider := hit.collider as Node
	_stick(point + velocity.normalized() * depth, collider if collider is DynamicGridBody else null)
	if kind == Kind.SPEAR:
		add_to_group(PICKUP_GROUP)


## Deja el proyectil clavado. Colgado de [holder] si se mueve (criatura, barco): entonces ya no
## es de nivel superior y el origen flotante lo mueve con su padre.
func _stick(point: Vector3, holder: Node) -> void:
	_stuck = true
	var xform := Transform3D(global_basis, point)
	if holder != null and holder is Node3D:
		remove_from_group("floating_origin")
		get_parent().remove_child(self)
		holder.add_child(self)
	global_transform = xform
	reset_physics_interpolation()


func is_pickable() -> bool:
	return _stuck and kind == Kind.SPEAR and is_in_group(PICKUP_GROUP)
