class_name TreeFelling
extends Node3D

## Tala de los árboles del instancer (los Branching y las palmeras): cada hachazo en un tronco
## (PlayerCombat) suma trabajo hasta que el árbol cede y cae (FallingTree), dejando un
## tocón a la altura del primer hachazo. Tumbado, se parte a hachazos en trozos (TreeLog) y la copa
## en ramas; cada trozo se parte a su vez en leña que queda en el suelo para recogerla.
##
## El trabajo va con el diámetro del tronco, no con la altura: con el hacha de piedra, un abedul
## cae en tres hachazos y un pino grande en quince. La madera va con el diámetro por la altura.
## Lo que no es un hacha apenas hace mella.
##
## Cuelga del terreno, como los cuerpos del instancer: tocones y árboles caídos siguen al planeta y
## al origen flotante. El árbol talado desaparece del instancer para siempre
## (queue_free_and_notify_instancer); el tocón y el tronco caído solo duran la sesión.

const META := &"tree_felling"
## Trabajo (daño de hacha) por metro de diámetro del tronco.
const WORK_PER_METER := 270.0
const MIN_WORK := 20.0
## El tajo (strike): a qué altura sobre los pies va, hasta dónde llega por delante y la holgura
## sobre el radio del tronco, de lado (en pie) o hasta el suelo (caído). Del tronco cuenta hasta
## REACH_HEIGHT sobre el suelo junto a él: por encima ya es la copa.
const STRIKE_HEIGHT := 1.1
const STRIKE_REACH := 1.7
const STRIKE_WIDTH := 0.35
const FALLEN_WIDTH := 0.5
const REACH_HEIGHT := 2.4
## Lo hundido que puede estar un árbol (m): el instancer los entierra un poco, y en las laderas a
## veces bastante más, con la colisión entera bajo los pies de quien tala.
const BURIED_DEPTH := 6.0
## Altura del corte sobre el suelo junto al tronco (m): la del primer hachazo, entre estos límites.
const CUT_HEIGHT := Vector2(0.1, 0.8)
## Madera: por metro de diámetro y metro de altura, más MIN_WOOD.
const WOOD_PER_M2 := 3.6
const MIN_WOOD := 3
const MAX_WOOD := 90
## Lo que mella lo que no es un hacha, por tipo de golpe.
const SLASH_FACTOR := 0.3
const BLUNT_FACTOR := 0.15
const PIERCE_FACTOR := 0.1
const MAX_STUMPS := 128
const MAX_FALLEN := 8
const MAX_LOGS := 32
## Alcance de las palmeras caídas y sus tocones (sin relevo de LODs).
const PALM_RANGE := 220.0

var planet: Planet
## library id -> especie (ver _build_species); {} si no se tala.
var _species: Dictionary = {}
## instance id del cuerpo -> {work, done, cut, out, notch}
var _trees: Dictionary = {}
var _stumps: Array[Node3D] = []
var _fallen: Array[Node3D] = []
var _logs: Array[Node3D] = []

static var _cut_material: StandardMaterial3D
static var _notch_texture: Texture2D


func _init(p_planet: Planet) -> void:
	name = "TreeFelling"
	planet = p_planet
	planet.voxel_instancer.set_meta(META, self)
	planet.voxel_instancer.child_exiting_tree.connect(_on_body_exiting)


## La tala del planeta al que pertenece [body] (un cuerpo del instancer), o null.
static func for_body(body: Node) -> TreeFelling:
	var instancer := body.get_parent() if body != null else null
	if instancer is VoxelInstancer and instancer.has_meta(META):
		return instancer.get_meta(META) as TreeFelling
	return null


## Herramientas que el combate deja golpear sin enemigos delante, para talar.
static func fells(data: ItemData) -> bool:
	return data != null and data.tool_type == ItemData.ToolType.AXE


## Mella de un golpe ligero con [data], antes de los multiplicadores del golpe.
static func chop_power(data: ItemData) -> float:
	if data == null:
		return 0.0
	var power := float(data.damage) * data.harvest_multiplier
	if data.tool_type == ItemData.ToolType.AXE or data.weapon_type == ItemData.WeaponType.AXE:
		return power
	match data.damage_kind:
		ItemData.DamageKind.SLASH:
			return power * SLASH_FACTOR
		ItemData.DamageKind.BLUNT:
			return power * BLUNT_FACTOR
	return power * PIERCE_FACTOR


## El tronco que recibe un golpe dado desde [feet] (los pies) hacia [forward], con [up] el del
## planeta: {body, point} con un árbol en pie talable, uno caído por partir o uno de sus trozos
## (TreeLog), o {}. El tajo es un tramo a la altura del pecho, hacia delante hasta STRIKE_REACH, y
## para los caídos además uno que baja delante hasta el suelo. Cuenta el tronco cuyo eje pasa más
## cerca, dentro de su radio más la holgura. Los árboles se buscan también por debajo de los pies
## (hasta BURIED_DEPTH): uno hundido tiene la colisión enterrada y el tronco que se ve, por encima.
static func strike(scene_tree: SceneTree, space: PhysicsDirectSpaceState3D, feet: Vector3,
		forward: Vector3, up: Vector3) -> Dictionary:
	if space == null:
		return {}
	var flat := forward - up * forward.dot(up)
	if flat.length_squared() < 1e-6:
		return {}
	flat = flat.normalized()
	var chest := feet + up * STRIKE_HEIGHT
	var near := chest + flat * 0.15
	var far := chest + flat * STRIKE_REACH
	var best := {}
	var best_gap := INF
	var low_near := chest + flat * 0.9
	var low_far := feet + flat * 0.9 - up * 0.3
	for node in scene_tree.get_nodes_in_group(FallingTree.GROUP) + scene_tree.get_nodes_in_group(TreeLog.GROUP):
		var reach: Array = []
		if node is FallingTree:
			reach = (node as FallingTree).strike_reach(near, far, low_near, low_far)
		elif node is TreeLog:
			reach = (node as TreeLog).strike_reach(near, far, low_near, low_far)
		if not reach.is_empty() and reach[0] <= FALLEN_WIDTH and reach[0] < best_gap:
			best_gap = reach[0]
			best = {"body": node, "point": reach[1]}
	for result in space.intersect_shape(strike_query(feet, flat, up), 32):
		var body := result.get("collider") as VoxelInstancerRigidBody
		if body == null:
			continue
		var felling := for_body(body)
		if felling == null or not felling.is_choppable(body):
			continue
		var xf := body.global_transform
		var info := felling._species_of(body)
		var base := trunk_base(space, xf, info.height * xf.basis.y.length(), body.get_rid())
		var closest := Geometry3D.get_closest_points_between_segments(near, far, xf.origin,
			xf.origin + xf.basis.y.normalized() * (base + REACH_HEIGHT))
		var gap: float = closest[0].distance_to(closest[1]) - float(info.radius) * xf.basis.y.length()
		if gap <= STRIKE_WIDTH and gap < best_gap:
			best_gap = gap
			best = {"body": body, "point": closest[1]}
	return best


## Dónde buscar los troncos de un golpe dado desde [feet] hacia [flat] (en el plano de [up]): una
## cápsula de pie que llega STRIKE_REACH alrededor del tajo y baja del pecho a BURIED_DEPTH bajo los
## pies.
static func strike_query(feet: Vector3, flat: Vector3, up: Vector3) -> PhysicsShapeQueryParameters3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = STRIKE_REACH
	capsule.height = STRIKE_HEIGHT + BURIED_DEPTH + STRIKE_REACH * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = PhysicsLayers.WORLD
	query.shape = capsule
	var middle := feet + up * ((STRIKE_HEIGHT - BURIED_DEPTH) * 0.5) + flat * (STRIKE_REACH * 0.5)
	query.transform = Transform3D(Basis(flat, up, flat.cross(up)), middle)
	return query


## Altura sobre el origen del árbol de [xf] y [height] m (cuerpo [tree]), por su eje, a la que el
## tronco sale del suelo: 0 si no se ve el suelo o si el árbol queda por encima.
static func trunk_base(space: PhysicsDirectSpaceState3D, xf: Transform3D, height: float, tree: RID) -> float:
	var up := xf.basis.y.normalized()
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(xf.origin + up * height, xf.origin,
		PhysicsLayers.WORLD, [tree]))
	return maxf(0.0, (hit.position - xf.origin).dot(up)) if not hit.is_empty() else 0.0


func is_choppable(body: Node) -> bool:
	var tree := body as VoxelInstancerRigidBody
	return tree != null and tree.is_inside_tree() and not tree.is_queued_for_deletion() \
		and not _species_of(tree).is_empty()


## Las especies se recalculan con la vegetación (cambian los ids de la librería).
func clear_species() -> void:
	_species.clear()


## Mete un hachazo de [power] en el tronco de [body] por [point] (mundo), dado desde [chopper]:
## mella un árbol en pie, parte uno caído o uno de sus trozos. Devuelve true si ha hecho algo.
static func chop_any(body: Node, point: Vector3, power: float, chopper: Node3D) -> bool:
	if body is FallingTree:
		return (body as FallingTree).hack(point, power, chopper)
	if body is TreeLog:
		return (body as TreeLog).hack(point, power, chopper)
	var felling := for_body(body)
	return felling != null and felling.chop(body, power, chopper)


## Mete un hachazo de [power] en el tronco de [body], dado desde [chopper]. Devuelve true si ha
## mellado (era un árbol talable).
func chop(body: Node, power: float, chopper: Node3D) -> bool:
	var tree := body as VoxelInstancerRigidBody
	if tree == null or power <= 0.0 or not tree.is_inside_tree() or tree.is_queued_for_deletion():
		return false
	var info := _species_of(tree)
	if info.is_empty():
		return false
	var xf := tree.global_transform
	var up := xf.basis.y.normalized()
	var scale := xf.basis.y.length()
	var radius: float = info.radius * scale
	var to_chopper := chopper.global_position - xf.origin if chopper != null else xf.basis.z
	var out := (to_chopper - up * to_chopper.dot(up))
	out = out.normalized() if out.length_squared() > 1e-6 else xf.basis.z.normalized()
	var key := tree.get_instance_id()
	var state: Dictionary = _trees.get(key, {})
	if state.is_empty():
		# El corte, a la altura del primer hachazo: la de la cintura de quien tala, sobre el suelo
		# (en un árbol hundido, el tocón asoma igual).
		var hand := chopper.global_position + up * 0.75 if chopper != null else xf.origin
		var base := trunk_base(tree.get_world_3d().direct_space_state, xf, info.height * scale, tree.get_rid())
		state = {"work": maxf(MIN_WORK, WORK_PER_METER * radius * 2.0), "done": 0.0,
			"cut": clampf((hand - xf.origin).dot(up), base + CUT_HEIGHT.x, base + CUT_HEIGHT.y),
			"out": out, "notch": null}
		_trees[key] = state
	state.done += power
	var progress := clampf(state.done / state.work, 0.0, 1.0)
	var at: Vector3 = xf.origin + up * state.cut + out * radius
	WoodChips.burst(self, at, out, up, power / 30.0)
	play_sound(&"tree_chop", &"block_wood", at, {"pitch": clampf(0.3 / maxf(radius, 0.05), 0.8, 1.2) * randf_range(0.95, 1.05)})
	if progress >= 1.0:
		_fell(tree, info, state, out, chopper)
	else:
		_update_notch(state, xf.origin + up * state.cut, up, radius, progress)
	return true


func _on_body_exiting(node: Node) -> void:
	var key := node.get_instance_id()
	if _trees.has(key):
		var notch: Variant = _trees[key].notch
		if is_instance_valid(notch):
			(notch as Node).queue_free()
		_trees.erase(key)


func _fell(tree: VoxelInstancerRigidBody, info: Dictionary, state: Dictionary, out: Vector3, chopper: Node3D) -> void:
	var xf := tree.global_transform
	var up := xf.basis.y.normalized()
	var scale := xf.basis.y.length()
	var radius: float = info.radius * scale
	var height: float = info.height * scale
	# Cae hacia el otro lado de quien lo tala, con algo de azar.
	var fall_dir := (-out).rotated(up, randf_range(-0.15, 0.15)).normalized()
	var wood := clampi(roundi(WOOD_PER_M2 * radius * 2.0 * height) + MIN_WOOD, MIN_WOOD, MAX_WOOD)
	var relative_base := xf.origin - (planet.voxel_terrain.get_parent() as Node3D).global_position

	_stumps.append(_build_stump(info, xf, state.cut, radius))
	while _stumps.size() > MAX_STUMPS:
		var old: Node3D = _stumps.pop_front()
		if is_instance_valid(old):
			old.queue_free()

	var falling := FallingTree.new()
	add_child(falling)
	falling.setup({"species": info, "transform": xf, "cut": state.cut, "radius": radius, "height": height,
		"fall_dir": fall_dir, "chopper": chopper, "wood": info.wood, "wood_amount": wood,
		"bark": info.barks[0],
		"relative_base": relative_base, "cut_material": cut_material()})
	for i in range(_fallen.size() - 1, -1, -1):
		if not is_instance_valid(_fallen[i]) or _fallen[i].is_queued_for_deletion():
			_fallen.remove_at(i)
	_fallen.append(falling)
	while _fallen.size() > MAX_FALLEN:
		var old: Node3D = _fallen.pop_front()
		if is_instance_valid(old):
			old.queue_free()

	if is_instance_valid(state.notch):
		(state.notch as Node).queue_free()
	_trees.erase(tree.get_instance_id())
	play_sound(&"tree_crack", &"guard_break", xf.origin + up * (state.cut + 1.0),
		{"pitch": clampf(0.35 / maxf(radius, 0.05), 0.55, 1.0)})
	# Lo saca del bosque (y de su guardado) para siempre. El detalle se va en el siguiente reparto,
	# con el árbol que cae ya dibujado encima en la misma pose.
	tree.queue_free_and_notify_instancer()


## Cuelga [chunk], un trozo de tronco recién partido (FallingTree): pasado MAX_LOGS, los más viejos
## se van.
func add_log(chunk: TreeLog) -> void:
	add_child(chunk)
	for i in range(_logs.size() - 1, -1, -1):
		if not is_instance_valid(_logs[i]) or _logs[i].is_queued_for_deletion():
			_logs.remove_at(i)
	_logs.append(chunk)
	while _logs.size() > MAX_LOGS:
		var old: Node3D = _logs.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## Suena [id] si hay clips grabados; si no, [fallback] (que sí los tiene) más grave.
static func play_sound(id: StringName, fallback: StringName, pos: Vector3, opts: Dictionary = {}) -> void:
	if CombatFx.has_sound(id):
		CombatFx.play(id, pos, opts)
		return
	var low := opts.duplicate()
	low["pitch"] = float(opts.get("pitch", 1.0)) * 0.8
	CombatFx.play(fallback, pos, low)


## Especie de [tree]: mallas y alcances del árbol que cae, radio del tronco y altura de la malla
## (en unidades de la malla), la madera que da y la corteza de cada malla para el tocón.
func _species_of(tree: VoxelInstancerRigidBody) -> Dictionary:
	var id := tree.get_library_item_id()
	if not _species.has(id):
		_species[id] = _build_species(id)
	return _species[id]


func _build_species(id: int) -> Dictionary:
	if not planet.planet_item_packed_scenes.has(id):
		return {}
	var item := planet.voxel_instancer.library.get_item(id) as VoxelInstanceLibraryMultiMeshItem
	var registered := planet.planet_item_scenes.get(id) as Item
	if item == null or registered == null or registered.item_data == null:
		return {}
	var shapes: Array = item.collision_shapes
	var cylinder := shapes[0] as CylinderShape3D if not shapes.is_empty() else null
	if cylinder == null:
		return {}
	var meshes: Array = []
	var ranges: Array[Vector2] = []
	var detail: Array = planet.tree_detail_renderer.lod_meshes(id) if planet.tree_detail_renderer != null else []
	var branching := not detail.is_empty()
	if branching:
		# Los mismos LODs del bosque, con sus fundidos: el árbol que cae se ve igual de lejos.
		meshes = detail
		var fades: Array = TreeDetailRenderer.LOD_FADES
		for lod in detail.size():
			var begin: float = 0.0 if lod == 0 else fades[lod - 1].x - TreeDetailRenderer.MARGIN
			ranges.append(Vector2(begin, fades[lod].y + TreeDetailRenderer.MARGIN))
	else:
		var mesh := item.get_mesh(0)
		if mesh == null:
			return {}
		meshes = [mesh]
		ranges = [Vector2(0.0, PALM_RANGE)]
	var barks: Array = []
	for mesh in meshes:
		barks.append(_bark_material(mesh, branching))
	var aabb: AABB = (meshes[0] as Mesh).get_aabb()
	return {"meshes": meshes, "ranges": ranges, "branching": branching, "barks": barks,
		"radius": cylinder.radius, "height": aabb.end.y, "crown": maxf(aabb.size.x, aabb.size.z) * 0.5,
		"wood": registered.item_data}


static func _bark_material(mesh: Mesh, branching: bool) -> Material:
	for s in mesh.get_surface_count():
		var material := mesh.surface_get_material(s)
		if branching and material is ShaderMaterial and material.shader != null \
				and material.shader.resource_path.ends_with("tree_bark.gdshader"):
			return material
	return mesh.surface_get_material(0) if not branching and mesh.get_surface_count() > 0 else null


## Tocón: un cilindro con la corteza de la especie hasta el corte, y la madera del corte arriba.
## Lleva un relevo por LOD como el árbol (con los fundidos de cada corteza) y colisión.
func _build_stump(info: Dictionary, xf: Transform3D, cut: float, radius: float) -> Node3D:
	var stump := Node3D.new()
	stump.name = "Stump"
	add_child(stump)
	stump.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	var side := _stump_side(radius, cut)
	var ranges: Array = info.ranges
	for lod in info.barks.size():
		if info.barks[lod] == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = side
		mi.material_override = info.barks[lod]
		mi.visibility_range_begin = ranges[lod].x
		mi.visibility_range_end = ranges[lod].y
		stump.add_child(mi)
	var top := MeshInstance3D.new()
	top.mesh = disc(radius, true)
	top.material_override = cut_material()
	top.position.y = cut
	top.visibility_range_end = ranges[ranges.size() - 1].y
	stump.add_child(top)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = cut + 0.3
	shape.shape = cylinder
	shape.position.y = (cut - 0.3) * 0.5
	body.add_child(shape)
	stump.add_child(body)
	return stump


## Lado del tocón, de algo bajo el suelo (en pendiente no queda al aire) hasta el corte, un poco
## más ancho abajo. COLOR y UV2 como la madera del tronco en tree_bark: oclusión 1, sin viento.
static func _stump_side(radius: float, cut: float) -> ArrayMesh:
	const SEGMENTS := 14
	var bottom := -0.4
	var around := maxf(1.0, roundf(TAU * radius / 0.7))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := [[bottom, radius * 1.12], [0.0, radius * 1.06], [cut, radius]]
	for i in SEGMENTS:
		var a0 := TAU * float(i) / float(SEGMENTS)
		var a1 := TAU * float(i + 1) / float(SEGMENTS)
		for r in rows.size() - 1:
			var quad := []
			for corner in [[a0, r], [a1, r], [a1, r + 1], [a0, r + 1]]:
				var angle: float = corner[0]
				var row: Array = rows[corner[1]]
				var dir := Vector3(sin(angle), 0.0, cos(angle))
				quad.append([dir * float(row[1]) + Vector3.UP * float(row[0]), dir,
					Vector2(angle / TAU * around, -float(row[0]) / 0.7)])
			for index in [0, 2, 1, 0, 3, 2]:
				st.set_color(Color(1.0, 0.0, 0.0, 1.0))
				st.set_uv2(Vector2.ZERO)
				st.set_normal(quad[index][1])
				st.set_uv(quad[index][2])
				st.add_vertex(quad[index][0])
	st.generate_tangents()
	return st.commit()


## Leño de [radius] y [length] a lo largo de X, apoyado en y = 0: la corteza [bark] alrededor y la
## madera del corte en las testas. COLOR y UV2 como la madera del tronco en tree_bark.
static func log_mesh(radius: float, length: float, bark: Material) -> ArrayMesh:
	const SEGMENTS := 10
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var around := maxf(1.0, roundf(TAU * radius / 0.7))
	for i in SEGMENTS:
		var a0 := TAU * float(i) / float(SEGMENTS)
		var a1 := TAU * float(i + 1) / float(SEGMENTS)
		var quad := []
		for corner in [[a0, -0.5], [a1, -0.5], [a1, 0.5], [a0, 0.5]]:
			var angle: float = corner[0]
			var dir := Vector3(0.0, cos(angle), sin(angle))
			quad.append([Vector3(float(corner[1]) * length, radius, 0.0) + dir * radius, dir,
				Vector2(angle / TAU * around, float(corner[1]) * length / 0.7)])
		# Godot toma por cara delantera la que se ve en sentido horario.
		for index in [0, 2, 1, 0, 3, 2]:
			st.set_color(Color(1.0, 0.0, 0.0, 1.0))
			st.set_uv2(Vector2.ZERO)
			st.set_normal(quad[index][1])
			st.set_uv(quad[index][2])
			st.add_vertex(quad[index][0])
	st.generate_tangents()
	st.commit(mesh)
	mesh.surface_set_material(0, bark)
	# Las testas: discos de cara a +X y -X.
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for end in [-1.0, 1.0]:
		var normal := Vector3(end, 0.0, 0.0)
		for i in SEGMENTS:
			var a0 := TAU * float(i) / float(SEGMENTS)
			var a1 := TAU * float(i + 1) / float(SEGMENTS)
			var tri := [Vector2.ZERO, Vector2(cos(a0), sin(a0)), Vector2(cos(a1), sin(a1))]
			for index in ([0, 2, 1] if end > 0.0 else [0, 1, 2]):
				var p: Vector2 = tri[index]
				st.set_normal(normal)
				st.set_uv(Vector2(0.5 + p.x * 0.5, 0.5 + p.y * 0.5))
				st.add_vertex(Vector3(end * length * 0.5, radius + p.x * radius, p.y * radius))
	st.generate_tangents()
	st.commit(mesh)
	mesh.surface_set_material(1, cut_material())
	return mesh


## Disco del corte de [radius], mirando arriba ([facing_up]) o abajo, con las UV centradas para
## los anillos de cut_material().
static func disc(radius: float, facing_up: bool) -> ArrayMesh:
	const SEGMENTS := 16
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal := Vector3.UP if facing_up else Vector3.DOWN
	for i in SEGMENTS:
		var a0 := TAU * float(i) / float(SEGMENTS)
		var a1 := TAU * float(i + 1) / float(SEGMENTS)
		var tri := [Vector3.ZERO, Vector3(sin(a0), 0.0, cos(a0)), Vector3(sin(a1), 0.0, cos(a1))]
		# Godot toma por cara delantera la que se ve en sentido horario.
		var order := [0, 2, 1] if facing_up else [0, 1, 2]
		for index in order:
			var p: Vector3 = tri[index]
			st.set_normal(normal)
			st.set_uv(Vector2(0.5 + p.x * 0.5, 0.5 + p.z * 0.5))
			st.add_vertex(p * radius)
	st.generate_tangents()
	return st.commit()


## Madera del corte: anillos claros con el centro algo más oscuro.
static func cut_material() -> StandardMaterial3D:
	if _cut_material != null:
		return _cut_material
	const SIZE := 128
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var pale := Color(0.80, 0.66, 0.46)
	var ring := Color(0.62, 0.47, 0.30)
	var heart := Color(0.55, 0.38, 0.22)
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x, y) / float(SIZE - 1) * 2.0 - Vector2.ONE
			var d := p.length() + noise.get_noise_2d(x, y) * 0.04
			var rings := 0.5 + 0.5 * sin(d * 46.0)
			var color := pale.lerp(ring, pow(rings, 6.0) * 0.8)
			color = heart.lerp(color, smoothstep(0.05, 0.35, d))
			image.set_pixel(x, y, color)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(image)
	mat.roughness = 0.85
	_cut_material = mat
	return _cut_material


## Muesca del corte: una Decal en la cara del tronco que mira a quien tala, que crece con el
## trabajo hecho. Solo pinta RenderLayers.NOTCH (los árboles del bosque).
func _update_notch(state: Dictionary, axis_point: Vector3, up: Vector3, radius: float, progress: float) -> void:
	var notch := state.notch as Decal
	if not is_instance_valid(notch):
		notch = Decal.new()
		notch.texture_albedo = _notch()
		notch.cull_mask = RenderLayers.NOTCH
		notch.normal_fade = 0.25
		notch.distance_fade_enabled = true
		notch.distance_fade_begin = 40.0
		notch.distance_fade_length = 10.0
		add_child(notch)
		state.notch = notch
	var out: Vector3 = state.out
	var thick := clampf(radius / 0.3, 0.6, 1.4)
	notch.size = Vector3(radius * 2.0 * lerpf(0.55, 1.0, progress), radius * 1.2,
		lerpf(0.1, 0.26, progress) * thick)
	notch.global_transform = Transform3D(Basis(out.cross(up), out, up), axis_point + out * radius * 0.5)


static func _notch() -> Texture2D:
	if _notch_texture != null:
		return _notch_texture
	const W := 128
	const H := 64
	var image := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.15
	var wood := Color(0.82, 0.68, 0.48)
	var edge := Color(0.42, 0.30, 0.18)
	for y in H:
		for x in W:
			var u := float(x) / float(W - 1) * 2.0 - 1.0
			var v := float(y) / float(H - 1) * 2.0 - 1.0
			# Cuña: más alta en el centro, afilada a los lados, con el borde mordido.
			var half := (1.0 - u * u) * (0.9 + noise.get_noise_2d(x, y) * 0.15)
			var inside := 1.0 - smoothstep(half - 0.12, half, absf(v))
			var fibre := 0.9 + 0.1 * sin(float(y) * 1.7 + noise.get_noise_2d(x * 3, y) * 4.0)
			var color := wood.lerp(edge, smoothstep(half * 0.5, half, absf(v))) * fibre
			color.a = inside
			image.set_pixel(x, y, color)
	_notch_texture = ImageTexture.create_from_image(image)
	return _notch_texture
