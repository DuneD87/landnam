class_name FaunaCorpse
extends RigidBody3D

## El cadáver de un animal pequeño (conejo, zorro, ave): una copia quieta de las mallas de su
## modelo en la pose en que murió (las de un esqueleto, con una copia del esqueleto en esa pose),
## dentro de un cuerpo rígido que cae y se vuelca. Si la especie tiene animación de muerte, la copia
## del esqueleto la hace (desde la pose en que murió) y el cuerpo ya no rueda: lo tumba el clip. La criatura
## vuelve al pool en el acto; esto se queda aparte. Al pararse deja un charco debajo y se va pasado
## un rato, encogiéndose.

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

static var _alive: Array[FaunaCorpse] = []

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
	while _alive.size() > MAX_ALIVE:
		_alive.pop_front().queue_free()
	return corpse


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
