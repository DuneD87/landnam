class_name SettlementFar extends Node3D

## Los poblados de lejos: entre load_distance (donde SettlementManager levanta las casas de verdad) y
## far_distance, cada poblado es una sola malla barata con el color medio de cada material, sin texturas.
## La malla sale del mismo blueprint de cada casa, con su zócalo y su rampa, y con la empalizada:
##
## - los cubos macizos, con las caras de un mismo material en un plano juntas en rectángulos (greedy);
## - la paja, las tejuelas y el tepe de los tejados (bloques 6 y 7), cada hilera de faldones iguales como
##   una sola tira con el perfil sin las capas;
## - las rampas, esquinas, paneles y losas, como los malla ChunkMeshBuilder;
## - sin la carpintería (postes, listones, riostras, escuadras), las puertas ni el decorado: a 600 m
##   miden menos de un píxel;
## - bajo el suelo de cada casa, un faldón de piedra de SKIRT m, por si el terreno de lejos (un LOD más
##   grueso) queda más bajo que el de cerca. Lo que sobra queda enterrado.
##
## Unos 300-500 triángulos por casa en vez de 2000-7000. Cada malla se hace en un hilo
## (WorkerThreadPool) y se guarda mientras el poblado sigue a menos de far_distance + KEEP_MARGIN.
##
## Las caras van metidas INSET m hacia dentro: mientras el poblado se levanta (unos segundos) las casas
## de verdad tapan las de lejos sin parpadeo de profundidad. Cuando ya están todas, la de lejos se
## esconde. Las que son de la partida (SettlementManager._claim) no salen: se rehace sin ellas.

## Color medio de la textura de cada material (sRGB), sacado de sus albedos.
const COLORS := {
	"stone": Color("968b79"), "wood": Color("6a492d"), "glass": Color("2e383d"), "thatch": Color("8d7749"),
	"plaster": Color("d4ccb9"), "planks": Color("594433"), "shingles": Color("73604c"), "turf": Color("4c5926"),
	"ashlar": Color("989286"), "cloth": Color("af8b70"),
}
const DEFAULT_COLOR := Color("8a7a66")
const PALISADE_COLOR := Color("5e4630")
## Materiales que dejan ver lo de detrás (no tapan la cara del vecino).
const SEE_THROUGH := {"glass": false}
const THATCH_IDS: Array[int] = [6, 7]
## Lo que no se malla de lejos: la carpintería (poste, listón, riostra, escuadra) y lo naval.
const SKIP_IDS: Array[int] = [9, 10, 11, 12, 13, 15]
const SKIRT := 2.0
const INSET := 0.05
const PALISADE_HEIGHT := 2.9
const PALISADE_THICKNESS := 0.3
## Más allá de far_distance + KEEP_MARGIN se suelta la malla (histéresis).
const KEEP_MARGIN := 300.0

var _villages: Array = []
## SettlementPrefab.id -> {"bp": su blueprint (load_data), "foundation": material del zócalo}, leídos en el
## hilo principal.
var _data := {}
var _far_distance := 4000.0
## Poblado -> MeshInstance3D.
var _nodes := {}
## Poblado -> {"task": id de WorkerThreadPool, "box": _Box, "stamp": int}.
var _jobs := {}
## Poblado -> contador de cambios (lo que es de la partida): un trabajo viejo no se usa.
var _stamps := {}
var _material: StandardMaterial3D


class _Box extends RefCounted:
	var arrays: Array = []


## [frame]: del marco del terreno al del padre (el PlanetLoader). [prefabs]: SettlementPrefab por id.
func setup(villages: Array, prefabs: Dictionary, frame: Transform3D, far_distance: float) -> void:
	name = "SettlementFar"
	transform = frame
	_villages = villages
	_far_distance = far_distance
	for id in prefabs:
		var prefab: SettlementPrefab = prefabs[id]
		var data := prefab.load_data()
		if not data.is_empty():
			_data[id] = {"bp": data, "foundation": prefab.foundation_material}
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.95


## Cada CHECK_INTERVAL de SettlementManager. [local]: el jugador en el marco del terreno. [claimed]:
## "<poblado>:<casa>" de la partida. [is_up]: Callable(v) -> si todas sus casas están levantadas.
func update(local: Vector3, claimed: Dictionary, is_up: Callable) -> void:
	_collect()
	for v in _villages.size():
		var plan: Dictionary = _villages[v]
		var d := local.distance_to((plan.center as Vector3) * float(plan.ground))
		if d > _far_distance + KEEP_MARGIN:
			_drop(v)
			continue
		if d > _far_distance:
			if _nodes.has(v):
				(_nodes[v] as MeshInstance3D).visible = false
			continue
		if not _nodes.has(v) and not _jobs.has(v):
			_start(v, claimed)
		if _nodes.has(v):
			(_nodes[v] as MeshInstance3D).visible = not is_up.call(v)


## Lo que es de la partida en [v] ha cambiado: se rehace su malla.
func changed(v: int) -> void:
	_stamps[v] = int(_stamps.get(v, 0)) + 1
	if _nodes.has(v):
		(_nodes[v] as Node).queue_free()
		_nodes.erase(v)


## Todo de nuevo (al cargar una partida).
func reset() -> void:
	for v: int in _nodes.keys():
		changed(v)
	for v: int in _jobs.keys():
		_stamps[v] = int(_stamps.get(v, 0)) + 1


func _exit_tree() -> void:
	for v: int in _jobs:
		WorkerThreadPool.wait_for_task_completion(int(_jobs[v].task))
	_jobs.clear()


func _start(v: int, claimed: Dictionary) -> void:
	var plan: Dictionary = _villages[v]
	var skip := {}
	for b in (plan.buildings as Array).size():
		if claimed.has("%d:%d" % [v, b]):
			skip[b] = true
	var box := _Box.new()
	var task := WorkerThreadPool.add_task(SettlementFar.village_arrays.bind(plan, _data, skip, box),
		false, "SettlementFar")
	_jobs[v] = {"task": task, "box": box, "stamp": int(_stamps.get(v, 0))}


## Recoge los trabajos terminados y pone sus mallas.
func _collect() -> void:
	for v: int in _jobs.keys():
		var job: Dictionary = _jobs[v]
		if not WorkerThreadPool.is_task_completed(int(job.task)):
			continue
		WorkerThreadPool.wait_for_task_completion(int(job.task))
		_jobs.erase(v)
		if int(job.stamp) != int(_stamps.get(v, 0)):
			continue
		var arrays: Array = (job.box as _Box).arrays
		if arrays.is_empty():
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _material)
		var node := MeshInstance3D.new()
		node.name = "Village_%d" % v
		node.mesh = mesh
		node.transform = village_frame(_villages[v])
		node.visible = false
		add_child(node)
		_nodes[v] = node


func _drop(v: int) -> void:
	if _nodes.has(v):
		(_nodes[v] as Node).queue_free()
		_nodes.erase(v)


## El marco del poblado [plan] en el del terreno: en el centro de su plaza, con Y hacia arriba. La malla
## va en él para que sus vértices sean pequeños.
static func village_frame(plan: Dictionary) -> Transform3D:
	var up := (plan.center as Vector3).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 1.0e-6:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	return Transform3D(Basis(side, up, side.cross(up)), up * float(plan.ground))


## Los arrays de la malla de lejos del poblado [plan] (en village_frame), sin las casas de [skip]
## (índice -> true), en [box] si se pasa. [data]: SettlementPrefab.id -> {"bp": load_data(), "foundation":
## material del zócalo}. Sin tocar nada de fuera: va en un hilo.
static func village_arrays(plan: Dictionary, data: Dictionary, skip: Dictionary, box: _Box = null) -> Array:
	var to_village := village_frame(plan).affine_inverse()
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var buildings: Array = plan.buildings
	for b in buildings.size():
		if skip.has(b):
			continue
		var info: Dictionary = buildings[b]
		var entry: Dictionary = data.get(info.prefab, {})
		if entry.is_empty():
			continue
		var bp: Dictionary = entry.bp
		var xform := to_village * Transform3D(info.basis as Basis, info.origin as Vector3)
		var grids: Array = bp.grids
		for i in grids.size():
			var grid: Dictionary = grids[i]
			var blocks := GridBlueprint.blocks_dict(grid)
			if i == 0:
				_add_extra(blocks, info.get("extra", PackedInt32Array()), String(entry.foundation))
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var size := float(grid.get("cell_size", 1.0))
			building_mesh(st, blocks, size, i == 0)
			_append(st.commit_to_arrays(), xform, positions, normals, colors)
	var wall: Dictionary = plan.get("wall", {})
	if not wall.is_empty() and StringName(wall.kind) == &"palisade":
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_palisade(st, wall, to_village)
		_append(st.commit_to_arrays(), Transform3D.IDENTITY, positions, normals, colors, false)
	var out: Array = []
	if not positions.is_empty():
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = positions
		out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_COLOR] = colors
	if box != null:
		box.arrays = out
	return out


## El zócalo y la rampa del plano ("extra": x, y, z, bloque, cuartos de vuelta) en [blocks].
static func _add_extra(blocks: Dictionary, extra: PackedInt32Array, material: String) -> void:
	for i in range(0, extra.size(), 5):
		blocks[Vector3i(extra[i], extra[i + 1], extra[i + 2])] = {"block_id": extra[i + 3],
			"material_id": material, "rotation_basis": Basis(Vector3.UP, extra[i + 4] * PI * 0.5),
			"mirrored": false}


## La malla de lejos de los bloques [blocks] (celdas de [size] m) en [st], en el espacio de su grid.
## [skirt]: con el faldón de piedra bajo el suelo (la grid principal).
static func building_mesh(st: SurfaceTool, blocks: Dictionary, size: float, skirt: bool) -> void:
	var cubes: Array[Vector3i] = []
	var thatch: Array[Vector3i] = []
	for pos: Vector3i in blocks:
		var info: Dictionary = blocks[pos]
		var id := int(info.block_id)
		if id in SKIP_IDS:
			continue
		if ChunkMeshBuilder._is_solid(id):
			cubes.append(pos)
		elif id in THATCH_IDS:
			thatch.append(pos)
		else:
			var rot: Basis = info.get("rotation_basis", Basis.IDENTITY)
			var flip := false
			if info.get("mirrored", false):
				var scale := Vector3.ONE
				scale[int(info.get("mirror_axis", 0))] = -1.0
				rot = rot * Basis.from_scale(scale)
				flip = true
			var mat: String = info.get("material_id", "")
			var hidden := ChunkMeshBuilder._hidden_local_faces(blocks, pos, rot, mat, SEE_THROUGH)
			st.set_color(color_of(mat))
			ChunkMeshBuilder._emit_from_block_type(st, id, Vector3(pos) * size, rot, size, flip, hidden, mat)
	_cubes(st, blocks, cubes, size)
	_thatch(st, blocks, thatch, size)
	if skirt and not blocks.is_empty():
		_skirt(st, blocks, size)


static func color_of(material_id: String) -> Color:
	return COLORS.get(material_id, DEFAULT_COLOR)


## Las caras a la vista de los cubos [cells], juntas en rectángulos del mismo material por plano.
static func _cubes(st: SurfaceTool, blocks: Dictionary, cells: Array[Vector3i], size: float) -> void:
	for face in 6:
		var dir: Vector3i = ChunkMeshBuilder.FACE_DIRS[face]
		var axis := 0 if dir.x != 0 else (1 if dir.y != 0 else 2)
		var ua := (axis + 1) % 3
		var va := (axis + 2) % 3
		var positive := dir[axis] > 0
		# Capa -> {Vector2i(u, v): material}.
		var layers := {}
		for c in cells:
			var mat: String = blocks[c].get("material_id", "")
			if ChunkMeshBuilder._neighbor_occludes(blocks, c + dir, mat, SEE_THROUGH):
				continue
			if not layers.has(c[axis]):
				layers[c[axis]] = {}
			layers[c[axis]][Vector2i(c[ua], c[va])] = mat
		for layer: int in layers:
			var mask: Dictionary = layers[layer]
			var keys := mask.keys()
			keys.sort()
			var plane := float(layer + (1 if positive else 0)) * size
			for k: Vector2i in keys:
				if not mask.has(k):
					continue
				var mat: String = mask[k]
				var w := 1
				while mask.has(Vector2i(k.x + w, k.y)) and mask[Vector2i(k.x + w, k.y)] == mat:
					w += 1
				var h := 1
				while true:
					var row_ok := true
					for x in w:
						var at := Vector2i(k.x + x, k.y + h)
						if not mask.has(at) or mask[at] != mat:
							row_ok = false
							break
					if not row_ok:
						break
					h += 1
				for y in h:
					for x in w:
						mask.erase(Vector2i(k.x + x, k.y + y))
				var a := _point(axis, plane, k.x * size, k.y * size)
				var b := _point(axis, plane, (k.x + w) * size, k.y * size)
				var c := _point(axis, plane, (k.x + w) * size, (k.y + h) * size)
				var d := _point(axis, plane, k.x * size, (k.y + h) * size)
				st.set_color(color_of(mat))
				# (b - a) × (d - a) apunta a +axis: del revés para las caras de -axis.
				if positive:
					ChunkMeshBuilder._add_quad(st, a, b, c, d)
				else:
					ChunkMeshBuilder._add_quad(st, a, d, c, b)


static func _point(axis: int, along: float, u: float, v: float) -> Vector3:
	var p := Vector3.ZERO
	p[axis] = along
	p[(axis + 1) % 3] = u
	p[(axis + 2) % 3] = v
	return p


## Los faldones y cumbreras de [cells] (bloques 6 y 7): cada hilera de piezas iguales seguidas a lo
## largo de su X, como una sola tira con el perfil sin las capas (ThatchRoofMesh.profile).
static func _thatch(st: SurfaceTool, blocks: Dictionary, cells: Array[Vector3i], size: float) -> void:
	var groups := {}
	for pos in cells:
		var info: Dictionary = blocks[pos]
		var key := [int(info.block_id), String(info.get("material_id", "")), info.get("rotation_basis", Basis.IDENTITY),
			bool(info.get("mirrored", false)), int(info.get("mirror_axis", 0))]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(pos)
	var t := ThatchRoofMesh.THICKNESS
	var slope := PackedVector2Array([Vector2(0, 0), Vector2(1, 1), Vector2(1, 1.0 + t), Vector2(0, t)])
	var ridge := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, t), Vector2(0.5, 0.5 + t),
		Vector2(0, t)])
	for key: Array in groups:
		var rot: Basis = key[2]
		var flip := false
		if key[3]:
			var scale := Vector3.ONE
			scale[int(key[4])] = -1.0
			rot = rot * Basis.from_scale(scale)
			flip = true
		var along := rot * Vector3.RIGHT
		var step := Vector3i(roundi(along.x), roundi(along.y), roundi(along.z))
		var left := {}
		for pos: Vector3i in groups[key]:
			left[pos] = true
		var ordered: Array = groups[key].duplicate()
		ordered.sort_custom(func(p: Vector3i, q: Vector3i) -> bool:
			return Vector3(p).dot(Vector3(step)) < Vector3(q).dot(Vector3(step)))
		st.set_color(color_of(key[1]))
		for pos: Vector3i in ordered:
			if not left.has(pos):
				continue
			var run := 0
			while left.has(pos + step * run):
				left.erase(pos + step * run)
				run += 1
			_extrude(st, ridge if int(key[0]) == 7 else slope, float(run), Vector3(pos) * size, rot, size, flip)


## El perfil [outline] (Z, Y, antihorario) extruido a lo largo de X de 0 a [length] celdas, con las
## tapas en los dos extremos, como ThatchRoofMesh.emit.
static func _extrude(st: SurfaceTool, outline: PackedVector2Array, length: float, offset: Vector3, rot: Basis,
		size: float, flip: bool) -> void:
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		ThatchRoofMesh._quad(st, Vector3(0, a.y, a.x), Vector3(length, a.y, a.x), Vector3(length, b.y, b.x),
			Vector3(0, b.y, b.x), offset, rot, size, flip)
	var indices := Geometry2D.triangulate_polygon(outline)
	for i in range(0, indices.size(), 3):
		var a := outline[indices[i]]
		var b := outline[indices[i + 1]]
		var c := outline[indices[i + 2]]
		ThatchRoofMesh._triangle(st, Vector3(0, a.y, a.x), Vector3(0, b.y, b.x), Vector3(0, c.y, c.x),
			offset, rot, size, flip)
		ThatchRoofMesh._triangle(st, Vector3(length, c.y, c.x), Vector3(length, b.y, b.x),
			Vector3(length, a.y, a.x), offset, rot, size, flip)


## Un faldón de piedra de SKIRT m bajo la caja de la capa más baja de [blocks] (el suelo, con el zócalo).
static func _skirt(st: SurfaceTool, blocks: Dictionary, size: float) -> void:
	var low := 1 << 30
	for c: Vector3i in blocks:
		low = mini(low, c.y)
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	for c: Vector3i in blocks:
		if c.y == low:
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.z))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.z))
	var top := float(low) * size
	var bottom := top - SKIRT
	var x0 := lo.x * size
	var x1 := (hi.x + 1) * size
	var z0 := lo.y * size
	var z1 := (hi.y + 1) * size
	st.set_color(color_of("stone"))
	# Las cuatro caras, con la normal hacia fuera ((b - a) × (d - a)).
	ChunkMeshBuilder._add_quad(st, Vector3(x0, bottom, z1), Vector3(x1, bottom, z1), Vector3(x1, top, z1),
		Vector3(x0, top, z1))
	ChunkMeshBuilder._add_quad(st, Vector3(x1, bottom, z0), Vector3(x0, bottom, z0), Vector3(x0, top, z0),
		Vector3(x1, top, z0))
	ChunkMeshBuilder._add_quad(st, Vector3(x1, bottom, z1), Vector3(x1, bottom, z0), Vector3(x1, top, z0),
		Vector3(x1, top, z1))
	ChunkMeshBuilder._add_quad(st, Vector3(x0, bottom, z0), Vector3(x0, bottom, z1), Vector3(x0, top, z1),
		Vector3(x0, top, z0))


## La empalizada (SettlementWall, &"palisade") como una tapia: las dos caras y el canto de arriba de cada
## tramo cerrado, en el marco del poblado ([to_village], desde el del terreno).
static func _palisade(st: SurfaceTool, wall: Dictionary, to_village: Transform3D) -> void:
	var points: PackedVector3Array = wall.points
	var open: PackedByteArray = wall.open
	var n := points.size()
	if n < 3:
		return
	var center := Vector3.ZERO
	for p in points:
		center += p
	center /= n
	st.set_color(PALISADE_COLOR)
	var half := PALISADE_THICKNESS * 0.5
	for j in n:
		if open[j] != 0:
			continue
		var a := points[j]
		var b := points[(j + 1) % n]
		var up := (a + b).normalized()
		var run := (b - a).slide(up)
		if run.length() < 0.01:
			continue
		var out := run.normalized().cross(up)
		if out.dot(a - center) < 0.0:
			out = -out
		var down := -up * SettlementWall.BURY
		var rise := up * PALISADE_HEIGHT
		for side: float in [1.0, -1.0]:
			var o := out * half * side
			_facing(st, to_village * (a + o + down), to_village * (b + o + down), to_village * (b + o + rise),
				to_village * (a + o + rise), to_village.basis * (out * side))
		_facing(st, to_village * (a + out * half + rise), to_village * (b + out * half + rise),
			to_village * (b - out * half + rise), to_village * (a - out * half + rise), to_village.basis * up)


## El cuadrilátero a, b, c, d con la cara hacia [normal].
static func _facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	if (b - a).cross(d - a).dot(normal) >= 0.0:
		ChunkMeshBuilder._add_quad(st, a, b, c, d)
	else:
		ChunkMeshBuilder._add_quad(st, a, d, c, b)


## Añade [arrays] (sin índices) movidos por [xform], metidos INSET hacia dentro si [inset].
static func _append(arrays: Array, xform: Transform3D, positions: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, inset: bool = true) -> void:
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return
	var p: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := idx.size() if not idx.is_empty() else p.size()
	var base := positions.size()
	positions.resize(base + count)
	normals.resize(base + count)
	colors.resize(base + count)
	for i in count:
		var k := idx[i] if not idx.is_empty() else i
		var n := nrm[k]
		positions[base + i] = xform * (p[k] - n * INSET if inset else p[k])
		normals[base + i] = (xform.basis * n).normalized()
		colors[base + i] = col[k] if k < col.size() else DEFAULT_COLOR
