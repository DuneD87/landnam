class_name FallingTree
extends Node3D

## Árbol talado: gira sobre la bisagra del corte (el borde del tronco del lado hacia el que cae)
## como una vara que vuelca, despacio al principio y cada vez más deprisa, hasta dar con el suelo.
## Al caer levanta polvo y hojarasca, hace temblar la cámara y hiere a lo que pille debajo. Queda
## tumbado (con colisión) y a hachazos se parte en trozos (TreeLog), que se apartan del golpe y caen
## al suelo con la madera repartida; la copa se deshace en hojarasca y ramas. Si la cámara se aleja
## antes, se va.
##
## Se dibuja con las mismas mallas (y LODs) que el bosque. La corteza y el follaje leen por
## instancia la base del árbol en pie, el corte y el viento del tronco (tree_felled.gdshaderinc).
## Cuelga de TreeFelling, bajo el terreno: sigue al planeta y al origen flotante.

const GROUP := &"felled_tree"
const GRAVITY := 9.8
## Inclinación y giro con que arranca (rad, rad/s): el árbol cruje y empieza a ceder.
const START_ANGLE := 0.03
const START_SPEED := 0.06
## Hasta dónde puede volcar (cuesta abajo pasa de la horizontal).
const MAX_ANGLE := deg_to_rad(115.0)
## Rebote al dar en el suelo (fracción del giro que devuelve) y rebotes antes de quedarse quieto.
const BOUNCE := 0.14
const MAX_BOUNCES := 2
## Paso del perfil del suelo a lo largo de la caída (m).
const PROFILE_STEP := 0.5
## Daño de la caída: por metro de diámetro del tronco, con este mínimo y máximo.
const DAMAGE_PER_METER := 220.0
const DAMAGE_RANGE := Vector2(25.0, 260.0)
## Se va cuando la cámara se aleja más que esto (para entonces ya no se ve).
const DESPAWN_DISTANCE := 170.0
## Trabajo para partir el tronco tumbado: fijo más por metro de diámetro.
const SPLIT_WORK := 12.0
const SPLIT_WORK_PER_METER := 50.0
## Los trozos: lo que ocupan del largo del árbol (lo de arriba es copa), su largo (m) y cuántos,
## el hueco entre ellos y lo que se apartan del hachazo al partirse (m).
const TRUNK_SHARE := 0.7
const LOG_LENGTH := 2.5
const LOG_COUNT := Vector2i(2, 6)
const LOG_GAP := 0.08
const LOG_PUSH := 0.25
## Ramas que suelta la copa al deshacerse: un puñado como el de una rama caída
## (GroundPickup.BRANCHES) por cada tantos metros de altura.
const METERS_PER_BRANCH := 6.0
const MAX_BRANCHES := 5
const BRANCH_ID := &"branch_01"

var _felling: TreeFelling
var _chopper: Node3D
var _wood: ItemData
var _wood_amount := 0
var _bark: Material
## Trabajo para partir el tronco tumbado y el acumulado; ya partido.
var _split_work := 0.0
var _work := 0.0
var _split := false
var _body: StaticBody3D
## Altura del corte sobre la base del árbol (m).
var _cut := 0.0
var _radius := 0.3
var _height := 10.0
var _length := 9.0
var _crown := 2.0
## En el marco de TreeFelling: transform del árbol en pie, bisagra y eje de giro.
var _start: Transform3D
var _hinge: Vector3
var _axis: Vector3
var _up: Vector3
var _dir: Vector3
var _theta := START_ANGLE
var _omega := START_SPEED
var _land := MAX_ANGLE
var _landed := false
var _bounces := 0
var _resting := false
var _despawn_check := 0.0


## [params]: species, transform (mundo, el del árbol en pie), cut, radius, height (m), fall_dir
## (mundo), chopper, wood, wood_amount, relative_base (base respecto al centro del planeta) y
## cut_material.
func setup(params: Dictionary) -> void:
	_felling = get_parent() as TreeFelling
	name = "FallingTree"
	var info: Dictionary = params.species
	_chopper = params.chopper
	_wood = params.wood
	_wood_amount = params.wood_amount
	_bark = params.get("bark")
	_radius = params.radius
	_height = params.height
	_length = _height * 0.92
	var to_local := _felling.global_transform.affine_inverse()
	_start = to_local * (params.transform as Transform3D)
	var scale := _start.basis.y.length()
	_crown = float(info.crown) * scale
	_up = _start.basis.y.normalized()
	_dir = (to_local.basis * (params.fall_dir as Vector3)).normalized()
	_dir = (_dir - _up * _dir.dot(_up)).normalized()
	var cut: float = params.cut
	_cut = cut
	_hinge = _start.origin + _up * cut + _dir * _radius
	_axis = _up.cross(_dir).normalized()

	var relative_base: Vector3 = params.relative_base
	var meshes: Array = info.meshes
	var ranges: Array = info.ranges
	for lod in meshes.size():
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[lod]
		mi.visibility_range_begin = ranges[lod].x
		mi.visibility_range_end = ranges[lod].y
		add_child(mi)
		if info.branching:
			mi.set_instance_shader_parameter(&"fell_base", Vector4(relative_base.x, relative_base.y, relative_base.z, 1.0))
			mi.set_instance_shader_parameter(&"fell_cut_height", cut / scale)
			mi.set_instance_shader_parameter(&"fell_sway", 0.0)
	# La cara del corte, abajo del tronco que cae (en metros: deshace la escala del árbol).
	var face := MeshInstance3D.new()
	face.mesh = TreeFelling.disc(_radius, false)
	face.material_override = params.cut_material
	face.transform = Transform3D(Basis.from_scale(Vector3.ONE / scale), Vector3.UP * (cut / scale))
	face.visibility_range_end = ranges[ranges.size() - 1].y
	add_child(face)

	_apply()
	reset_physics_interpolation()
	_land = _landing_angle()


func _physics_process(delta: float) -> void:
	if _resting:
		_despawn_check -= delta
		if _despawn_check <= 0.0:
			_despawn_check = 1.0
			var camera := get_viewport().get_camera_3d()
			if camera != null and camera.global_position.distance_to(global_transform * Vector3.ZERO) > DESPAWN_DISTANCE:
				queue_free()
		return
	# Vara que vuelca sobre un extremo: θ'' = 3g / (2L) · sen θ.
	_omega += 1.5 * GRAVITY / _length * sin(_theta) * delta
	_theta += _omega * delta
	if _theta >= _land:
		_theta = _land
		if not _landed:
			_landed = true
			_on_impact()
		if _bounces < MAX_BOUNCES and _omega > 0.4:
			_omega = -_omega * BOUNCE
			_bounces += 1
		else:
			_omega = 0.0
			_rest()
	_apply()


func _apply() -> void:
	var rotation := Basis(_axis, _theta)
	transform = Transform3D(rotation, _hinge - rotation * _hinge) * _start


## Ángulo al que el tronco toca el suelo. El perfil del terreno a lo largo de la caída se mide
## una vez (el suelo no se mueve): alturas respecto a la bisagra cada PROFILE_STEP metros. Los
## otros árboles no cuentan (las copas se atraviesan); los tocones y troncos caídos, sí.
func _landing_angle() -> float:
	var space := get_world_3d().direct_space_state
	var to_world := _felling.global_transform
	var hinge := to_world * _hinge
	var up := (to_world.basis * _up).normalized()
	var dir := (to_world.basis * _dir).normalized()
	var reach := _length + 1.0
	var heights := PackedFloat32Array()
	var x := 0.0
	while x <= reach:
		var from := hinge + dir * x + up * (_length * 0.5 + 4.0)
		var to := hinge + dir * x - up * (_length + 4.0)
		var hit := ground(space, from, to)
		heights.append((hit - hinge).dot(up) if hit.is_finite() else -INF)
		x += PROFILE_STEP
	var theta := START_ANGLE
	while theta < MAX_ANGLE:
		var s := 1.0
		while s <= _length:
			var horizontal := s * sin(theta)
			var index := clampi(roundi(horizontal / PROFILE_STEP), 0, heights.size() - 1)
			# El tronco se afila hacia la copa.
			var radius := _radius * (1.0 - 0.7 * s / _length)
			if s * cos(theta) - radius <= heights[index]:
				return theta
			s += 0.5
		theta += deg_to_rad(0.5)
	return MAX_ANGLE


## Primer suelo entre [from] y [to] que no es un árbol del bosque ni [skip], o un vector infinito.
static func ground(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, skip: Array[RID] = []) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD)
	var exclude: Array[RID] = skip.duplicate()
	for attempt in 6:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return Vector3.INF
		if hit.collider is VoxelInstancerRigidBody:
			exclude.append(hit.rid)
			continue
		return hit.position
	return Vector3.INF


func _on_impact() -> void:
	var to_world := _felling.global_transform
	var rotation := Basis(_axis, _theta)
	var trunk := (to_world.basis * (rotation * _up)).normalized()
	var base := to_world * _hinge
	var tip := base + trunk * _length
	var up := (to_world.basis * _up).normalized()
	var power := clampf(_radius / 0.4, 0.2, 1.0)
	WoodChips.crash(self, base + trunk * (_length * 0.15), tip, maxf(_crown * 0.6, 1.0), up, power)
	TreeFelling.play_sound(&"tree_fall", &"hit_blunt", base.lerp(tip, 0.5),
		{"pitch": clampf(0.4 / maxf(_radius, 0.05), 0.6, 1.1)})
	AudioManager.play_material(&"block_impact", &"wood", base.lerp(tip, 0.4), {"volume_offset_db": -2.0})
	_shake(base.lerp(tip, 0.5), power)
	_hurt(base, tip, up)
	_split_work = SPLIT_WORK + SPLIT_WORK_PER_METER * _radius * 2.0


## Tiembla la cámara de quien está cerca, más cuanto más grande el árbol y más cerca.
func _shake(at: Vector3, power: float) -> void:
	var player := GameManager.player
	if player == null or not is_instance_valid(player) or not "camera_controller" in player:
		return
	var distance := (player as Node3D).global_position.distance_to(at)
	var amount := power * 0.35 * clampf(1.0 - distance / (_length + 25.0), 0.0, 1.0)
	if amount > 0.01:
		player.camera_controller.add_shake(amount)


## Lo que pilla el tronco (y menos, la copa) al caer.
func _hurt(base: Vector3, tip: Vector3, up: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var damage := clampf(DAMAGE_PER_METER * _radius * 2.0, DAMAGE_RANGE.x, DAMAGE_RANGE.y)
	var crown_start := base.lerp(tip, 0.55)
	var hit_owners: Dictionary = {}
	for part in [[base, crown_start, _radius + 0.45, 1.0], [crown_start, tip, maxf(_crown * 0.45, 0.8), 0.5]]:
		var a: Vector3 = part[0]
		var b: Vector3 = part[1]
		var radius: float = part[2]
		var amount: float = damage * float(part[3])
		var shape := CapsuleShape3D.new()
		var axis := b - a
		shape.radius = radius
		shape.height = axis.length() + radius * 2.0
		var y := axis.normalized()
		var x := y.cross(up).normalized()
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		query.collision_mask = PhysicsLayers.HURTBOX
		for result in space.intersect_shape(query, 32):
			var box := result.get("collider") as Hurtbox
			if box == null or not box.is_enabled() or box.owner_body == null:
				continue
			var key := box.owner_body.get_instance_id()
			if hit_owners.has(key):
				continue
			hit_owners[key] = true
			var point := Geometry3D.get_closest_point_to_segment(box.global_position, a, b)
			var info := DamageInfo.create(amount, _chopper if is_instance_valid(_chopper) else null, point, -up,
				amount * 0.5)
			info.kind = ItemData.DamageKind.BLUNT
			info.knockback = 1.2
			info.parryable = false
			box.receive(info)
		for creature in MeleeSweep.loose_creatures_on_segment(get_tree(), a, b, radius):
			var key := creature.get_instance_id()
			if not hit_owners.has(key):
				hit_owners[key] = true
				creature.take_damage(amount, _chopper if is_instance_valid(_chopper) else null)


## Tumbado: colisión a lo largo del tronco, para pisarlo o saltarlo, y ya se puede partir.
func _rest() -> void:
	_resting = true
	add_to_group(GROUP)
	var scale := _start.basis.y.length()
	var body := StaticBody3D.new()
	_body = body
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	# En unidades del árbol: el cuerpo cuelga de este nodo, que lleva su escala.
	cylinder.radius = _radius * 0.85 / scale
	cylinder.height = _length * 0.8 / scale
	shape.shape = cylinder
	shape.position = Vector3.UP * (_length * 0.42 / scale)
	body.add_child(shape)
	add_child(body)


## Eje del tronco tumbado en mundo: [base (el corte), punta].
func _axis_world() -> PackedVector3Array:
	var to_world := _felling.global_transform
	var trunk := (to_world.basis * (Basis(_axis, _theta) * _up)).normalized()
	var base := to_world * _hinge
	return PackedVector3Array([base, base + trunk * _length])


## [hueco, punto]: lo que separa la superficie del tronco tumbado del tajo (los tramos [a]–[b] y
## [c]–[d]) y el punto de su eje más cercano; [] si aún cae o ya está partido.
func strike_reach(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Array:
	if not _resting or _split:
		return []
	var axis := _axis_world()
	var best := []
	for segment in [[a, b], [c, d]]:
		var closest := Geometry3D.get_closest_points_between_segments(segment[0], segment[1], axis[0], axis[1])
		var gap: float = closest[0].distance_to(closest[1]) - _radius
		if best.is_empty() or gap < best[0]:
			best = [gap, closest[1]]
	return best


## Hachazo de [power] al tronco tumbado por [point] (en su eje), dado desde [chopper]: al completar
## el trabajo, se parte en trozos y la copa se deshace.
func hack(point: Vector3, power: float, chopper: Node3D) -> bool:
	if not _resting or _split or power <= 0.0:
		return false
	var axis := _axis_world()
	var up := (_felling.global_transform.basis * _up).normalized()
	var side := _side(point, axis, up, chopper)
	var surface := point + side * _radius * 0.8 + up * _radius * 0.5
	WoodChips.burst(self, surface, (side + up).normalized(), up, power / 30.0)
	TreeFelling.play_sound(&"tree_chop", &"block_wood", surface,
		{"pitch": clampf(0.3 / maxf(_radius, 0.05), 0.8, 1.2) * randf_range(1.0, 1.1)})
	_work += power
	if _work < _split_work:
		return true
	_split = true
	TreeFelling.play_sound(&"tree_crack", &"guard_break", surface,
		{"pitch": clampf(0.5 / maxf(_radius, 0.05), 0.9, 1.4), "volume_offset_db": -4.0})
	_cut_logs(point, up)
	_break_up(axis, up, side)
	return true


## De lado del tronco hacia quien golpea (los leños caen a ese lado, a mano).
func _side(point: Vector3, axis: PackedVector3Array, up: Vector3, chopper: Node3D) -> Vector3:
	var along := (axis[1] - axis[0]).normalized()
	var side := along.cross(up).normalized()
	if is_instance_valid(chopper) and side.dot(chopper.global_position - point) < 0.0:
		side = -side
	return side


## Parte el tronco en trozos (TreeLog) que se apartan de [point], el hachazo, y caen al suelo, con
## la madera repartida según su grosor (uno como poco cada uno).
func _cut_logs(point: Vector3, up: Vector3) -> void:
	var scale := _start.basis.y.length()
	var along := global_basis.y.normalized()
	var lift := (up - along * along.dot(up)).normalized()
	var across := along.cross(lift)
	var base := global_transform * (Vector3.UP * (_cut / scale))
	var hit := (point - base).dot(along)
	var trunk := _length * TRUNK_SHARE
	var count := mini(clampi(roundi(trunk / LOG_LENGTH), LOG_COUNT.x, LOG_COUNT.y), maxi(_wood_amount, 1))
	var piece_length := trunk / float(count)
	var radii: Array = []
	for i in count:
		# El tronco se afila hacia la copa, como en _landing_angle.
		radii.append(_radius * (1.0 - 0.7 * (float(i) + 0.5) * piece_length / _length))
	var sections := radii.map(func(r: float) -> float: return r * r)
	var shares := RockMining.share(maxi(_wood_amount - count, 0), sections)
	var exclude: Array[RID] = []
	if _body != null:
		exclude.append(_body.get_rid())
	for i in count:
		var s := (float(i) + 0.5) * piece_length
		var push := along * (LOG_PUSH * (1.0 if s > hit else -1.0)) + across * randf_range(-0.1, 0.1)
		var chunk := TreeLog.new()
		_felling.add_log(chunk)
		chunk.setup(Transform3D(Basis(along, lift, across), base + along * s), radii[i], piece_length - LOG_GAP, _bark,
			_wood, shares[i] + 1 if _wood_amount > 0 else 0, up, push, exclude)
	_wood_amount = 0


## Lo que queda de la copa se deshace en hojarasca y suelta las ramas.
func _break_up(axis: PackedVector3Array, up: Vector3, side: Vector3) -> void:
	var power := clampf(_radius / 0.4, 0.2, 1.0)
	WoodChips.crash(self, axis[0].lerp(axis[1], 0.2), axis[1], maxf(_crown * 0.5, 0.8), up, power * 0.7)
	var crown := axis[0].lerp(axis[1], 0.7)
	TreeFelling.play_sound(&"tree_fall", &"hit_blunt", crown, {"pitch": 1.3, "volume_offset_db": -6.0})
	var branch := ItemCatalog.get_item(BRANCH_ID)
	var branches := clampi(roundi(_height / METERS_PER_BRANCH), 1, MAX_BRANCHES) \
		* randi_range(GroundPickup.BRANCHES.x, GroundPickup.BRANCHES.y)
	if branch != null:
		DroppedItem.spawn_at(self, branch, branches, crown + side * (_radius + 0.6) + up * 1.5, -up)
	queue_free()
