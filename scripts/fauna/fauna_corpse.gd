class_name FaunaCorpse
extends RigidBody3D

## El cadáver de un animal pequeño (conejo, zorro, ave): una copia quieta de las mallas de su
## modelo en la pose en que murió, dentro de un cuerpo rígido que cae y se vuelca. La criatura
## vuelve al pool en el acto; esto se queda aparte. Al pararse deja un charco debajo y se va pasado
## un rato, encogiéndose.

const LIFETIME := 90.0
const SHRINK := 1.5
const MAX_ALIVE := 16
const POOL_AFTER := 0.6
const POOL_GROW := 7.0
## Los parámetros de shader por instancia que animan el modelo: quietos en el cadáver.
const STILL_PARAMS := {
	"movement": 0.0, "run_blend": 0.0, "airborne": 0.0, "vertical_speed": 0.0, "turn_amount": 0.0,
	"landing": 0.0,
}

static var _alive: Array[FaunaCorpse] = []

var _gravity := Vector3.ZERO
var _world_mask := 1
var _time := 0.0
var _still := 0.0
var _pool: BloodPool
var _pool_size := 0.6
var _visual: Node3D


## Deja el cadáver de [model] (las mallas visibles que lleve dentro) donde está, saliendo con
## [velocity] y la gravedad [gravity]. null si el modelo no tiene nada que ver.
static func spawn(host: Node, model: Node3D, velocity: Vector3, gravity: Vector3, world_mask: int) -> FaunaCorpse:
	if gravity.length_squared() < 1e-6:
		return null
	var meshes: Array[MeshInstance3D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.visible and mi.is_visible_in_tree() and mi.mesh != null:
			meshes.append(mi)
	if meshes.is_empty():
		return null
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
	corpse.global_transform = Transform3D(model.global_basis.orthonormalized(), box.get_center())
	corpse._visual = Node3D.new()
	corpse.add_child(corpse._visual)
	for mi in meshes:
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
	for copy in corpse._visual.get_children():
		var b := (corpse.global_transform.affine_inverse() * (copy as MeshInstance3D).global_transform) \
			* (copy as MeshInstance3D).get_aabb()
		local_box = b if first else local_box.merge(b)
		first = false
	var shape := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = (local_box.size * 0.85).max(Vector3.ONE * 0.04)
	shape.shape = bshape
	shape.position = local_box.get_center()
	corpse.add_child(shape)
	corpse.mass = clampf(bshape.size.x * bshape.size.y * bshape.size.z * 120.0, 0.2, 30.0)
	corpse._pool_size = clampf(local_box.size.length() * 1.4, 0.35, 1.4)
	corpse.linear_velocity = velocity
	# Se vuelca hacia un lado al caer.
	var up := -gravity.normalized()
	var side := up.cross(model.global_basis.z).normalized()
	corpse.angular_velocity = model.global_basis.z.normalized() * randf_range(3.0, 6.0) * (1.0 if randf() < 0.5 else -1.0) \
		+ side * randf_range(-1.5, 1.5)
	_alive = _alive.filter(func(other: FaunaCorpse) -> bool: return is_instance_valid(other))
	_alive.append(corpse)
	while _alive.size() > MAX_ALIVE:
		_alive.pop_front().queue_free()
	return corpse


func _physics_process(delta: float) -> void:
	_time += delta
	if _time >= LIFETIME:
		queue_free()
		return
	if _time > LIFETIME - SHRINK and _visual != null:
		_visual.scale = Vector3.ONE * maxf((LIFETIME - _time) / SHRINK, 0.01)
	if _pool != null:
		return
	# La gravedad que se suma en cada paso (9,8 / 60 ≈ 0,16 m/s) sigue ahí aunque esté en el suelo.
	if linear_velocity.length() < 0.3:
		_still += delta
	else:
		_still = 0.0
	if _still >= POOL_AFTER:
		_pool = BloodPool.spawn(self, global_position, _gravity, _pool_size, POOL_GROW, _world_mask)
		_still = -INF


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# La gravedad del planeta, no la del proyecto.
	state.linear_velocity += _gravity * state.step
