class_name FaunaCorpse
extends RigidBody3D

## El cadáver de un animal pequeño (conejo, zorro, ave): una copia quieta de las mallas de su
## modelo en la pose en que murió (las de un esqueleto, con una copia del esqueleto en esa pose),
## dentro de un cuerpo rígido que cae y se vuelca. Si la especie tiene animación de muerte, la copia
## del esqueleto la hace (desde la pose en que murió) y el cuerpo ya no rueda: lo tumba el clip. La criatura
## vuelve al pool en el acto; esto se queda aparte. Al pararse deja un charco debajo y se va pasado
## un rato, encogiéndose.
## Si su especie da algo (set_hunt: el butcher_loot de su perfil), se despieza como un animal grande
## muerto (Butchering, con un cuchillo en la mano) y lo que da se saquea: lleva lo mismo que un
## NPCController para eso (is_dead, butchered, butcher_progress, inventory, butcher_loot, body_size,
## get_skeleton, get_lock_point, butcher_shape, butcher_model). Mientras se trabaja en él no se va, y
## despiezado dura LIFETIME desde ese momento. Las aves sueltan plumas al desplumarlas (pluck).

const LIFETIME := 90.0
const SHRINK := 1.5
const MAX_ALIVE := 16
const POOL_AFTER := 0.6
const POOL_GROW := 7.0
## Fundido desde la pose en que murió hasta su animación de muerte (s).
const DEATH_BLEND := 0.2
## Los parámetros de shader por instancia que animan el modelo: quietos en el cadáver.
const STILL_PARAMS := {
	"movement": 0.0, "run_blend": 0.0, "airborne": 0.0, "vertical_speed": 0.0, "turn_amount": 0.0,
	"landing": 0.0,
}
## Lo que se despieza del largo del cuerpo (sin la cola ni el pico).
const BODY_LENGTH := 0.8

static var _alive: Array[FaunaCorpse] = []

## Para despiezarlo (Butchering, como un NPCController muerto; ver set_hunt).
var is_dead := true
var butchered := false:
	set(value):
		butchered = value
		_hold()
var butcher_progress := 0.0:
	set(value):
		butcher_progress = value
		_hold()
var butcher_loot: LootTable
var body_size := 1.0
## Lo que da, ya despiezado (null si su especie no da nada).
var inventory: Inventory
## El color de sus plumas, si es un ave (transparente si no).
var plume := Color.TRANSPARENT
## El grueso (radio) y el largo del cuerpo (m).
var _shape := Vector2(0.1, 0.3)
## Encogiéndose al irse: la escala de partida de cada cosa que se encoge.
var _shrunk := {}

var _gravity := Vector3.ZERO
var _world_mask := 1
var _time := 0.0
var _still := 0.0
var _pool: BloodPool
var _pool_size := 0.6
var _visual: Node3D


## Deja el cadáver de [model] (las mallas visibles que lleve dentro) donde está, saliendo con
## [velocity] y la gravedad [gravity], y con la muerte [death] si la trae. null si el modelo no
## tiene nada que ver.
static func spawn(host: Node, model: Node3D, velocity: Vector3, gravity: Vector3, world_mask: int,
		death: Animation = null) -> FaunaCorpse:
	if gravity.length_squared() < 1e-6:
		return null
	var meshes: Array[MeshInstance3D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.visible and mi.is_visible_in_tree() and mi.mesh != null:
			meshes.append(mi)
	if meshes.is_empty():
		return null
	var skeletons: Array[Skeleton3D] = []
	for node in model.find_children("*", "Skeleton3D", true, false):
		if (node as Skeleton3D).is_visible_in_tree():
			skeletons.append(node as Skeleton3D)
	var box := AABB()
	for i in meshes.size():
		var world_box := meshes[i].global_transform * meshes[i].get_aabb()
		box = world_box if i == 0 else box.merge(world_box)
	var corpse := FaunaCorpse.new()
	corpse.name = "FaunaCorpse"
	corpse._gravity = gravity
	corpse._world_mask = world_mask
	corpse.collision_layer = 0
	corpse.collision_mask = world_mask
	corpse.gravity_scale = 0.0
	corpse.continuous_cd = true
	host.add_child(corpse, true)
	corpse.add_to_group(&"floating_origin")
	corpse.add_to_group(GameManager.RESET_ON_LOAD_GROUP)
	corpse.global_transform = Transform3D(model.global_basis.orthonormalized(), box.get_center())
	corpse._visual = Node3D.new()
	corpse.add_child(corpse._visual)
	# Un esqueleto se copia entero, con su pose de ahora y sus mallas (sin scripts ni señales).
	var dying := false
	for skeleton in skeletons:
		var posed := skeleton.duplicate(0) as Skeleton3D
		corpse._visual.add_child(posed)
		posed.global_transform = skeleton.global_transform
		if death != null and not dying:
			dying = _play_death(posed, death)
	for mi in meshes:
		if skeletons.any(func(skeleton: Skeleton3D) -> bool: return skeleton.is_ancestor_of(mi)):
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.material_override = mi.material_override
		for s in mi.get_surface_override_material_count():
			copy.set_surface_override_material(s, mi.get_surface_override_material(s))
		copy.cast_shadow = mi.cast_shadow
		corpse._visual.add_child(copy)
		copy.global_transform = mi.global_transform
		for prop in mi.get_property_list():
			var prop_name: String = prop.name
			if prop_name.begins_with("instance_shader_parameters/"):
				var key := prop_name.trim_prefix("instance_shader_parameters/")
				copy.set_instance_shader_parameter(key, STILL_PARAMS.get(key, mi.get(prop_name)))
	var local_box := AABB()
	var first := true
	for copy in corpse._visual.find_children("*", "MeshInstance3D", true, false):
		var b := (corpse.global_transform.affine_inverse() * (copy as MeshInstance3D).global_transform) \
			* (copy as MeshInstance3D).get_aabb()
		local_box = b if first else local_box.merge(b)
		first = false
	# Mira a -Z, como el modelo: el largo del cuerpo es su fondo.
	corpse._shape = Vector2(minf(local_box.size.x, local_box.size.y) * 0.5, local_box.size.z * BODY_LENGTH)
	var shape := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = (local_box.size * 0.85).max(Vector3.ONE * 0.04)
	shape.shape = bshape
	shape.position = local_box.get_center()
	corpse.add_child(shape)
	corpse.mass = clampf(bshape.size.x * bshape.size.y * bshape.size.z * 120.0, 0.2, 30.0)
	corpse._pool_size = clampf(local_box.size.length() * 1.4, 0.35, 1.4)
	corpse.linear_velocity = velocity
	if dying:
		corpse.lock_rotation = true
	else:
		# Se vuelca hacia un lado al caer.
		var up := -gravity.normalized()
		var side := up.cross(model.global_basis.z).normalized()
		corpse.angular_velocity = model.global_basis.z.normalized() * randf_range(3.0, 6.0) * (1.0 if randf() < 0.5 else -1.0) \
			+ side * randf_range(-1.5, 1.5)
	# Fuera los que ya se han ido. Sin filter: un liberado no entra en un parámetro tipado, y el
	# filtro fallaba en cuanto se iba el primero.
	for i in range(_alive.size() - 1, -1, -1):
		if not is_instance_valid(_alive[i]):
			_alive.remove_at(i)
	_alive.append(corpse)
	# Sobran: se va el más viejo, antes uno que nadie haya empezado a despiezar.
	while _alive.size() > MAX_ALIVE:
		var drop := 0
		for i in _alive.size() - 1:
			if _alive[i].butcher_progress == 0.0:
				drop = i
				break
		_alive.pop_at(drop).queue_free()
	return corpse


## Lo que da al despiezarlo ([loot], el de su especie; null = nada, y no se despieza), su tamaño, el
## grueso de su cuerpo ([radius], m; el de la criatura) y, si es un ave, el color de sus plumas
## ([feathers]; transparente si no). Lo llama AmbientAnimal.die al dejarlo.
func set_hunt(loot: LootTable, size: float, radius: float, feathers: Color) -> void:
	butcher_loot = loot
	body_size = size
	plume = feathers
	if radius > 0.0:
		_shape.x = radius
	if loot != null and inventory == null:
		inventory = Inventory.new()
		inventory.name = "Inventory"
		add_child(inventory)


## Si se puede despiezar, o ya despiezado le queda algo que saquear.
func butcherable() -> bool:
	if butcher_loot == null or inventory == null or is_queued_for_deletion():
		return false
	return not butchered or inventory.get_free_slots() < inventory.max_slots


## El más cercano a [point], a menos de [reach] m, que se puede despiezar o saquear (butcherable).
static func nearest(point: Vector3, reach: float) -> FaunaCorpse:
	var best: FaunaCorpse = null
	var best_d := reach * reach
	for corpse in _alive:
		if not is_instance_valid(corpse) or not corpse.is_inside_tree() or not corpse.butcherable():
			continue
		var d := corpse.global_position.distance_squared_to(point)
		if d <= best_d:
			best = corpse
			best_d = d
	return best


## La copia del esqueleto (en la pose en que quedó), o null si el modelo no tiene.
func get_skeleton() -> Skeleton3D:
	if _visual == null:
		return null
	for child in _visual.get_children():
		if child is Skeleton3D:
			return child
	return null


## El centro del cuerpo (el de su caja).
func get_lock_point() -> Vector3:
	for child in get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).global_position
	return global_position


## El grueso (radio) y el largo del cuerpo (m), para el despiece (Butchering, Carcass).
func butcher_shape() -> Vector2:
	return _shape


## Lo que se esconde al quedar la canal (Carcass.strip).
func butcher_model() -> Node3D:
	return _visual


## Al desplumarlo: [amount] plumas (FeatherPuff) que salen de [point] hacia [up]. Nada si no es un ave.
func pluck(point: Vector3, up: Vector3, amount: int) -> void:
	if plume.a > 0.0:
		FeatherPuff.spawn(self, point, up, plume, amount, _shape.x)


## Se está trabajando en él: no se va (vuelve a contar LIFETIME) y se queda quieto donde está.
func _hold() -> void:
	_time = 0.0
	if not freeze:
		set_deferred(&"freeze", true)


## La muerte sobre la copia del esqueleto, fundida desde la pose de ahora: un clip de una sola
## clave con esa pose y, encima, la muerte.
static func _play_death(skeleton: Skeleton3D, death: Animation) -> bool:
	var pose := Animation.new()
	for track in death.get_track_count():
		var path := death.track_get_path(track)
		var bone := skeleton.find_bone(path.get_concatenated_subnames())
		if bone < 0:
			continue
		var copy := pose.add_track(death.track_get_type(track))
		pose.track_set_path(copy, path)
		match death.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				pose.rotation_track_insert_key(copy, 0.0, skeleton.get_bone_pose_rotation(bone))
			Animation.TYPE_POSITION_3D:
				pose.position_track_insert_key(copy, 0.0, skeleton.get_bone_pose_position(bone))
	var library := AnimationLibrary.new()
	library.add_animation(&"Pose", pose)
	library.add_animation(&"Death", death)
	var player := AnimationPlayer.new()
	player.name = "Death"
	skeleton.add_child(player)
	player.add_animation_library(&"", library)
	player.play(&"Pose")
	player.advance(0.0)
	player.play(&"Death", DEATH_BLEND)
	return true


func _physics_process(delta: float) -> void:
	_time += delta
	if _time >= LIFETIME:
		queue_free()
		return
	_shrink(clampf((LIFETIME - _time) / SHRINK, 0.01, 1.0))
	if _pool != null:
		return
	# La gravedad que se suma en cada paso (9,8 / 60 ≈ 0,16 m/s) sigue ahí aunque esté en el suelo.
	if linear_velocity.length() < 0.3 or freeze:
		_still += delta
	else:
		_still = 0.0
	if _still >= POOL_AFTER:
		_pool = BloodPool.spawn(self, global_position, _gravity, _pool_size, POOL_GROW, _world_mask)
		_still = -INF


## Al irse se encoge (a [factor] de su tamaño) con lo que haya dejado el despiece (la canal, las
## vísceras); si vuelve a 1 (se ha empezado a despiezar), recupera su tamaño.
func _shrink(factor: float) -> void:
	if factor >= 1.0 and _shrunk.is_empty():
		return
	if _shrunk.is_empty():
		var remains: Array = [_visual]
		var carcass: Dictionary = get_meta(Carcass.META, {})
		remains.append(carcass.get("node"))
		remains.append(carcass.get("guts"))
		for node in remains:
			if is_instance_valid(node) and node is Node3D:
				_shrunk[node] = (node as Node3D).scale
	for node in _shrunk:
		if is_instance_valid(node):
			(node as Node3D).scale = (_shrunk[node] as Vector3) * factor
	if factor >= 1.0:
		_shrunk.clear()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# La gravedad del planeta, no la del proyecto.
	state.linear_velocity += _gravity * state.step
