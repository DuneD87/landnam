## Bosque planetario independiente del VoxelInstancer. Posiciones de árboles
## deterministas por celda de rejilla cube-sphere (RNG sembrado por celda,
## superficie por raycast del SDF en worker threads). De cerca malla real, de
## lejos billboard: el mismo árbol en la misma posición, con transición estable.
## Las celdas solo se liberan al salir del radio de visión con histéresis, así
## que un árbol nunca desaparece delante del jugador.
class_name PlanetForest extends Node3D

const MAX_CONCURRENT_BUILDS := 3
const MAX_TREES_PER_CELL := 2500
const PROCESS_INTERVAL := 0.3
const MESH_RING_COUNT := 3
const MESH_RING_REBUILD_DISTANCE := 8.0

const FACES := [
	{ "n": Vector3(1, 0, 0), "u": Vector3(0, 1, 0), "v": Vector3(0, 0, 1) },
	{ "n": Vector3(-1, 0, 0), "u": Vector3(0, 1, 0), "v": Vector3(0, 0, 1) },
	{ "n": Vector3(0, 1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, 1) },
	{ "n": Vector3(0, -1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, 1) },
	{ "n": Vector3(0, 0, 1), "u": Vector3(1, 0, 0), "v": Vector3(0, 1, 0) },
	{ "n": Vector3(0, 0, -1), "u": Vector3(1, 0, 0), "v": Vector3(0, 1, 0) },
]

var radius: float = 1000.0
var cell_size: float = 512.0
var view_distance: float = 3000.0
var mesh_distance: float = 500.0
var fade_band: float = 80.0
var density: float = 0.002
var sink: float = 0.3
var collision_distance: float = 60.0
var mesh_shadows: bool = true
var shadow_distance: float = 100.0
var lod_bias: float = 1.0
## Distancias absolutas donde LOD0 pasa a LOD1 y LOD1 pasa a LOD2.
## mesh_distance marca el final de LOD2 y el comienzo del billboard.
var mesh_lod_distances := Vector2(200.0, 350.0)
var mesh_lod_hysteresis: float = 4.0

var _generator: VoxelGeneratorGraph
var _types: Array = []
var _impostor_material: ShaderMaterial
var _billboard_mesh: ArrayMesh
var _cells: Dictionary = {}
var _colliders: Dictionary = {}
var _build_queue: Array = []
var _queued: Dictionary = {}
var _builds_in_flight: int = 0
var _cells_per_face: int = 1
var _accum: float = 0.0
var _active: bool = false
var _reported: bool = false
var _last_cam_local: Vector3 = Vector3.ZERO
var _last_mesh_ring_cam := Vector3(1.0e20, 1.0e20, 1.0e20)
var _mesh_batches: Dictionary = {}
var _mesh_batch_signatures: Dictionary = {}
var _mesh_rings_dirty: bool = true

var billboards_visible: bool = true
var meshes_visible: bool = true


## Configura el bosque. types: diccionarios construidos por planet.gd
## (mesh, materiales, frame, colisión, alturas, noises, weight...).
func setup(generator: VoxelGenerator, planet_radius: float, types: Array, cfg: Dictionary, impostor_material: ShaderMaterial) -> void:
	_generator = generator as VoxelGeneratorGraph
	if _generator == null or not _generator.has_method("raycast_sdf_approx"):
		push_error("PlanetForest: el generador no soporta raycast_sdf_approx; bosque desactivado")
		return
	radius = planet_radius
	_types = types
	_impostor_material = impostor_material
	cell_size = cfg.get("cell_size", 512.0)
	view_distance = cfg.get("view_distance", 3000.0)
	mesh_distance = maxf(float(cfg.get("mesh_distance", 500.0)), 3.0)
	fade_band = cfg.get("fade_band", 80.0)
	density = cfg.get("density", 0.002)
	sink = cfg.get("sink", 0.3)
	collision_distance = cfg.get("collision_distance", 60.0)
	mesh_shadows = cfg.get("mesh_shadows", true)
	shadow_distance = cfg.get("shadow_distance", 100.0)
	lod_bias = cfg.get("lod_bias", 1.0)
	var default_first_split := clampf(shadow_distance / maxf(mesh_distance, 1.0), 0.2, 0.45)
	mesh_lod_distances = Vector2(
		mesh_distance * default_first_split,
		mesh_distance * maxf(default_first_split + 0.2, 0.7))
	# Formato nuevo: metros absolutos [fin de LOD0, fin de LOD1].
	var raw_distances = cfg.get("mesh_lod_distances", [])
	if raw_distances is Array and raw_distances.size() >= 2:
		mesh_lod_distances.x = clampf(float(raw_distances[0]), 1.0, mesh_distance - 2.0)
		mesh_lod_distances.y = clampf(float(raw_distances[1]), mesh_lod_distances.x + 1.0, mesh_distance - 1.0)
	# Compatibilidad con el formato anterior basado en proporciones [0..1].
	var raw_splits = cfg.get("mesh_lod_splits", [])
	if not (raw_distances is Array and raw_distances.size() >= 2) and raw_splits is Array and raw_splits.size() >= 2:
		var split_0_ratio := clampf(float(raw_splits[0]), 0.1, 0.8)
		var split_1_ratio := clampf(float(raw_splits[1]), split_0_ratio + 0.05, 0.95)
		mesh_lod_distances = Vector2(mesh_distance * split_0_ratio, mesh_distance * split_1_ratio)
	mesh_lod_hysteresis = clampf(
		float(cfg.get("mesh_lod_hysteresis", minf(4.0, mesh_lod_distances.x * 0.25))),
		0.0,
		minf(mesh_lod_distances.x, mesh_lod_distances.y - mesh_lod_distances.x) * 0.45)
	_cells_per_face = maxi(1, int(ceil(PI * 0.5 * radius / cell_size)))
	_billboard_mesh = TreeImpostorBaker.build_billboard_quad_mesh()
	add_to_group("planet_forest")

	impostor_material.set_shader_parameter("atlas_grid", float(TreeImpostorBaker.ATLAS_GRID))
	impostor_material.set_shader_parameter("near_cutoff", mesh_distance)
	impostor_material.set_shader_parameter("near_band", fade_band)
	impostor_material.set_shader_parameter("far_cutoff", view_distance * 0.95)
	impostor_material.set_shader_parameter("far_band", view_distance * 0.05)
	impostor_material.set_shader_parameter("brightness", cfg.get("billboard_brightness", 1.0))
	impostor_material.set_shader_parameter("debug_unlit", cfg.get("billboard_debug", false))
	for type_idx in _types.size():
		var t: Dictionary = _types[type_idx]
		for m in t.materials:
			m.set_shader_parameter("forest_fade_start", mesh_distance - fade_band)
			m.set_shader_parameter("forest_fade_band", fade_band)
		t["lod_ring_meshes"] = _build_lod_ring_meshes(t.mesh)
	print("PlanetForest: %d especies, %d celdas/cara, celda %.0f m, anillos LOD %.0f/%.0f/%.0f m" % [
		_types.size(), _cells_per_face, cell_size,
		mesh_lod_distances.x, mesh_lod_distances.y, mesh_distance])


## Extrae tres mallas fijas de la misma cadena LOD. De este modo todos los
## árboles conservan geometría base, pivote y altura; solo cambia el número de
## índices dibujados en los anillos medio y lejano.
func _build_lod_ring_meshes(src: ArrayMesh) -> Array:
	var importer := ImporterMesh.from_mesh(src)
	return [
		_extract_fixed_lod_mesh(src, importer, -1.0),
		_extract_fixed_lod_mesh(src, importer, 0.5),
		_extract_fixed_lod_mesh(src, importer, 1.0),
	]


## rank < 0 usa los índices originales. [0, 1] selecciona de fino a grueso
## entre los LOD embebidos que generó ImporterMesh.
func _extract_fixed_lod_mesh(src: ArrayMesh, importer: ImporterMesh, rank: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	for surface_idx in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(surface_idx)
		if rank >= 0.0:
			var lod_count := importer.get_surface_lod_count(surface_idx)
			if lod_count > 0:
				var pick := clampi(int(round(float(lod_count - 1) * rank)), 0, lod_count - 1)
				arrays[Mesh.ARRAY_INDEX] = importer.get_surface_lod_indices(surface_idx, pick)
		out.add_surface_from_arrays(src.surface_get_primitive_type(surface_idx), arrays)
		var dst_surface := out.get_surface_count() - 1
		out.surface_set_material(dst_surface, src.surface_get_material(surface_idx))
		out.surface_set_name(dst_surface, src.surface_get_name(surface_idx))
	return out


## Llamado por planet.gd cuando el atlas de billboards está horneado.
func notify_atlas_ready() -> void:
	_active = true


func _process(delta: float) -> void:
	if not _active:
		return
	_accum += delta
	if _accum < PROCESS_INTERVAL:
		return
	_accum = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_local := to_local(cam.global_position)
	_last_cam_local = cam_local
	_update_cells(cam_local)
	_update_colliders(cam_local)
	_pump_queue(cam_local)


## Toggle de diagnóstico: oculta/muestra todos los billboards del bosque.
func set_billboards_visible(on: bool) -> void:
	billboards_visible = on
	for id in _cells:
		var bb = _cells[id].billboard
		if bb != null and is_instance_valid(bb):
			bb.visible = on


## Toggle de diagnóstico: oculta/muestra todos los lotes de anillos LOD.
func set_meshes_visible(on: bool) -> void:
	meshes_visible = on
	for key in _mesh_batches:
		var mmi = _mesh_batches[key]
		if is_instance_valid(mmi):
			mmi.visible = on and mmi.multimesh != null and mmi.multimesh.instance_count > 0
	if on:
		_mesh_rings_dirty = true


## Activa/desactiva en vivo las sombras de las mallas del bosque.
func set_mesh_shadows(on: bool) -> void:
	mesh_shadows = on
	_update_ring_shadows()


## Estado del bosque + contadores de render del frame, para la consola.
func debug_stats() -> String:
	var trees := 0
	var batches := 0
	var mesh_instances := 0
	var bb := 0
	for id in _cells:
		var cell: Dictionary = _cells[id]
		trees += cell.count
		if cell.billboard != null and is_instance_valid(cell.billboard):
			bb += cell.count
	for key in _mesh_batches:
		var mmi = _mesh_batches[key]
		if is_instance_valid(mmi) and mmi.multimesh != null and mmi.multimesh.instance_count > 0:
			batches += 1
			mesh_instances += mmi.multimesh.instance_count
	return "celdas %d (cola %d) · árboles %d · billboards %d · lotes LOD %d/%d (instancias %d) · colliders %d\nFPS %.0f · draw calls %d · primitivas %.2f M · objetos %d" % [
		_cells.size(), _build_queue.size(), trees, bb, batches, _types.size() * MESH_RING_COUNT, mesh_instances, _colliders.size(),
		Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)]


## Marca un árbol como talado: colapsa su instancia en malla y billboard.
func remove_tree(id: Vector3i, type_idx: int, tree_idx: int) -> void:
	var cell = _cells.get(id)
	if cell == null:
		return
	cell.removed[Vector2i(type_idx, tree_idx)] = true
	var zero := Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.ZERO)
	var entry = cell.mesh_index_map.get(Vector2i(type_idx, tree_idx))
	if entry != null:
		var mmi = _mesh_batches.get(entry[0])
		if mmi != null and is_instance_valid(mmi):
			mmi.multimesh.set_instance_transform(entry[1], zero)
			mmi.multimesh.reset_instance_physics_interpolation(entry[1])
	if cell.billboard != null and is_instance_valid(cell.billboard) and cell.bb_offsets.size() > type_idx:
		var billboard_idx: int = cell.bb_offsets[type_idx] + tree_idx
		cell.billboard.multimesh.set_instance_transform(billboard_idx, zero)
		cell.billboard.multimesh.reset_instance_physics_interpolation(billboard_idx)
	_mesh_rings_dirty = true


func _update_cells(cam_local: Vector3) -> void:
	var drop_dist: float = view_distance + cell_size * 2.0
	for id in _cells.keys():
		if _cells[id].center.distance_to(cam_local) > drop_dist:
			_free_cell(id)

	for id in _wanted_cell_ids(cam_local):
		var cell = _cells.get(id)
		if cell == null:
			if not _queued.has(id):
				_queued[id] = true
				_build_queue.append(id)
			continue
	_update_mesh_rings(cam_local)


## Celdas cuyo centro cae dentro del radio de visión alrededor de la cámara.
func _wanted_cell_ids(cam_local: Vector3) -> Array:
	var out: Array = []
	var cam_dir := cam_local.normalized()
	var window := int(ceil(view_distance / (cell_size * 0.6))) + 1
	var reach: float = view_distance + cell_size
	var n := float(_cells_per_face)
	for f in FACES.size():
		var face: Dictionary = FACES[f]
		var denom: float = cam_dir.dot(face.n)
		if denom <= 0.05:
			continue
		var u: float = clampf(cam_dir.dot(face.u) / denom, -1.0, 1.0)
		var v: float = clampf(cam_dir.dot(face.v) / denom, -1.0, 1.0)
		var ci := int(floor((u + 1.0) * 0.5 * n))
		var cj := int(floor((v + 1.0) * 0.5 * n))
		for i in range(maxi(0, ci - window), mini(_cells_per_face, ci + window + 1)):
			for j in range(maxi(0, cj - window), mini(_cells_per_face, cj + window + 1)):
				var id := Vector3i(f, i, j)
				var center: Vector3 = _cell_center_dir(id) * radius
				if center.distance_to(cam_local) <= reach:
					out.append(id)
	return out


func _cell_center_dir(id: Vector3i) -> Vector3:
	var n := float(_cells_per_face)
	var face: Dictionary = FACES[id.x]
	var u: float = -1.0 + 2.0 * (float(id.y) + 0.5) / n
	var v: float = -1.0 + 2.0 * (float(id.z) + 0.5) / n
	return (face.n + face.u * u + face.v * v).normalized()


func _pump_queue(cam_local: Vector3) -> void:
	if _build_queue.is_empty():
		return
	if _build_queue.size() > 1:
		_build_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			var da: float = (_cell_center_dir(a) * radius).distance_squared_to(cam_local)
			var db: float = (_cell_center_dir(b) * radius).distance_squared_to(cam_local)
			return da < db)
	while _builds_in_flight < MAX_CONCURRENT_BUILDS and not _build_queue.is_empty():
		var id: Vector3i = _build_queue.pop_front()
		_builds_in_flight += 1
		WorkerThreadPool.add_task(_build_cell.bind(id))


## Siembra una celda en un worker thread: RNG determinista por celda,
## superficie por raycast del SDF, filtros de noise/altura/pendiente.
func _build_cell(id: Vector3i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var n := float(_cells_per_face)
	var face: Dictionary = FACES[id.x]
	var du: float = 2.0 / n
	var u0: float = -1.0 + du * float(id.y)
	var v0: float = -1.0 + du * float(id.z)
	var uc: float = u0 + du * 0.5
	var vc: float = v0 + du * 0.5
	var cell_center: Vector3 = (face.n + face.u * uc + face.v * vc).normalized() * radius

	var rho2: float = uc * uc + vc * vc
	var area: float = pow(2.0 * radius / n, 2.0) / pow(1.0 + rho2, 1.5)
	var target := mini(int(density * area), MAX_TREES_PER_CELL)

	var mesh_t: Array = []
	var bb_t: Array = []
	for t in _types.size():
		mesh_t.append([])
		bb_t.append([])

	var total := 0
	for k in target:
		var ti := _pick_type(rng)
		var u: float = u0 + du * rng.randf()
		var v: float = v0 + du * rng.randf()
		var t: Dictionary = _types[ti]
		var dir: Vector3 = (face.n + face.u * u + face.v * v).normalized()
		var cands: Array = _variant_candidates(t, dir)
		if cands.is_empty():
			continue
		var ground: float = _find_surface(dir, t.min_height, t.max_height)
		if ground < 0.0:
			continue
		var va: Dictionary = {}
		var slope_cos: float = 2.0
		for c in cands:
			if ground < radius + c.min_height or ground > radius + c.max_height:
				continue
			if slope_cos > 1.0:
				slope_cos = _slope_cos(dir, ground)
			if slope_cos >= c.cos_max_slope:
				va = c
				break
		if va.is_empty():
			continue
		var s: float = rng.randf_range(va.min_scale, va.max_scale)
		var yaw: float = rng.randf() * TAU

		var up := dir
		var refv: Vector3 = Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT
		var t1: Vector3 = up.cross(refv).normalized().rotated(up, yaw)
		var t2: Vector3 = t1.cross(up)
		var rel: Vector3 = dir * (ground - sink) - cell_center
		mesh_t[ti].append(Transform3D(Basis(t1 * s, up * s, t2 * s), rel))
		var bs: float = t.frame_size * s
		bb_t[ti].append(Transform3D(Basis(t1 * bs, up * bs, t2 * bs), rel + up * (t.frame_center * s)))
		total += 1

	call_deferred("_finish_cell", id, cell_center, mesh_t, bb_t, total)


func _pick_type(rng: RandomNumberGenerator) -> int:
	if _types.size() == 1:
		return 0
	var total := 0.0
	for t in _types:
		total += t.weight
	var r: float = rng.randf() * total
	for i in _types.size():
		r -= _types[i].weight
		if r <= 0.0:
			return i
	return _types.size() - 1


## Variantes de generador aplicables en esta dirección, de mayor a menor valor
## de noise (la zona más fuerte gana). Una variante sin noise vale el umbral.
func _variant_candidates(t: Dictionary, dir: Vector3) -> Array:
	var p: Vector3 = dir * radius
	var thr: float = t.noise_threshold
	var out: Array = []
	for va in t.variants:
		var val: float = thr if va.noise == null else va.noise.get_noise_3d(p.x, p.y, p.z)
		if val >= thr:
			out.append([val, va])
	if out.size() > 1:
		out.sort_custom(func(a, b): return a[0] > b[0])
	return out.map(func(e): return e[1])


## Radio del suelo a lo largo de dir, o -1 si no hay superficie válida.
## Dos pasadas de raycast_sdf_approx: gruesa (stride 4) y refinado (stride 0.5).
func _find_surface(dir: Vector3, min_h: float, max_h: float) -> float:
	var top: float = radius + max_h + 10.0
	var bottom: float = radius + min_h - 10.0
	if bottom >= top:
		return -1.0
	var hit: float = _generator.raycast_sdf_approx(dir * top, dir * bottom, 4.0)
	if hit < 0.0:
		return -1.0
	var coarse: float = top - hit
	var r0: float = coarse + 5.0
	var fine: float = _generator.raycast_sdf_approx(dir * r0, dir * (coarse - 5.0), 0.5)
	var ground: float = coarse if fine < 0.0 else r0 - fine
	if ground < radius + min_h or ground > radius + max_h:
		return -1.0
	return ground


func _surface_near(dir_n: Vector3, ref_r: float) -> float:
	var top: float = ref_r + 12.0
	var hit: float = _generator.raycast_sdf_approx(dir_n * top, dir_n * (ref_r - 12.0), 1.0)
	if hit < 0.0:
		return -1.0
	return top - hit


## Coseno de la pendiente local (1 = llano) por diferencias de altura en dos
## vecinos tangentes a 6 m; si las sondas fallan se asume llano (permisivo).
func _slope_cos(dir: Vector3, ground: float) -> float:
	var e := 6.0
	var refv: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var t1: Vector3 = dir.cross(refv).normalized()
	var t2: Vector3 = dir.cross(t1)
	var h1: float = _surface_near((dir * ground + t1 * e).normalized(), ground)
	var h2: float = _surface_near((dir * ground + t2 * e).normalized(), ground)
	if h1 < 0.0 or h2 < 0.0:
		return 1.0
	var d1: float = (h1 - ground) / e
	var d2: float = (h2 - ground) / e
	return 1.0 / sqrt(1.0 + d1 * d1 + d2 * d2)


func _finish_cell(id: Vector3i, center: Vector3, mesh_t: Array, bb_t: Array, count: int) -> void:
	_builds_in_flight -= 1
	_queued.erase(id)
	var cell := {
		"center": center,
		"count": count,
		"mesh_t": mesh_t,
		"bb_t": bb_t,
		"bb_offsets": PackedInt32Array(),
		"billboard": null,
		"mesh_index_map": {},
		"mesh_ring_map": {},
		"removed": {},
	}
	_cells[id] = cell
	_mesh_rings_dirty = true
	if count > 0:
		_create_billboard(cell)
	if not _reported and _cells.size() >= 20:
		_reported = true
		var total := 0
		for cid in _cells:
			total += _cells[cid].count
		print("PlanetForest: primeras %d celdas sembradas, %d árboles" % [_cells.size(), total])
	_pump_queue(_last_cam_local)


func _create_billboard(cell: Dictionary) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _billboard_mesh
	mm.instance_count = cell.count
	# Los árboles son estáticos y los slots se crean/destruyen por streaming.
	# Interpolar un slot desde su transform anterior produce un árbol que cruza
	# el mundo (y a veces el plano cercano de la cámara) durante un frame.
	RenderingServer.multimesh_set_physics_interpolated(mm.get_rid(), false)
	var offsets := PackedInt32Array()
	offsets.resize(_types.size())
	var idx := 0
	for t in _types.size():
		offsets[t] = idx
		var fit: Vector2 = _types[t].get("bb_fit", Vector2.ONE)
		var fit_top: float = _types[t].get("bb_fit_top", 0.0)
		for xf in cell.bb_t[t]:
			mm.set_instance_transform(idx, xf)
			mm.set_instance_custom_data(idx, Color(float(t), fit.x, fit.y, fit_top))
			idx += 1
	mm.reset_instances_physics_interpolation()
	cell.bb_offsets = offsets

	var mmi := MultiMeshInstance3D.new()
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.multimesh = mm
	mmi.material_override = _impostor_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.position = cell.center
	mmi.visible = billboards_visible
	add_child(mmi)
	mmi.reset_physics_interpolation()
	cell.billboard = mmi

	# Fade de nacimiento: si la celda llega tarde (vuelo rápido), no hace pop.
	mmi.set_instance_shader_parameter("cell_fade", 0.0)
	var tw := mmi.create_tween()
	tw.tween_property(mmi, "instance_shader_parameters/cell_fade", 1.0, 1.5)


## Reconstruye como máximo al desplazarse MESH_RING_REBUILD_DISTANCE metros o
## cuando entra/sale una celda. El resultado son solo tres MultiMesh por especie:
## malla completa, LOD medio y LOD bajo. Los lotes permanecen anclados al origen
## local del planeta para no mover el nodo y su buffer en comandos separados.
func _update_mesh_rings(cam_local: Vector3, force := false) -> void:
	if not force and not _mesh_rings_dirty:
		if cam_local.distance_squared_to(_last_mesh_ring_cam) < MESH_RING_REBUILD_DISTANCE * MESH_RING_REBUILD_DISTANCE:
			return

	var buckets: Array = []
	var owners: Array = []
	var signatures: Array = []
	for type_idx in _types.size():
		var type_buckets: Array = []
		var type_owners: Array = []
		var type_signatures: Array = []
		for ring_idx in MESH_RING_COUNT:
			type_buckets.append([])
			type_owners.append([])
			type_signatures.append(5381)
		buckets.append(type_buckets)
		owners.append(type_owners)
		signatures.append(type_signatures)

	for id in _cells:
		var cell: Dictionary = _cells[id]
		if cell.count == 0 or cell.center.distance_to(cam_local) > mesh_distance + cell_size:
			continue
		for type_idx in cell.mesh_t.size():
			var transforms: Array = cell.mesh_t[type_idx]
			for tree_idx in transforms.size():
				var tree_key := Vector2i(type_idx, tree_idx)
				if cell.removed.has(tree_key):
					continue
				var xf: Transform3D = transforms[tree_idx]
				var world_pos: Vector3 = cell.center + xf.origin
				var distance: float = world_pos.distance_to(cam_local)
				var previous_ring: int = int(cell.mesh_ring_map.get(tree_key, -1))
				var ring_idx := _mesh_ring_for_distance(distance, previous_ring)
				if ring_idx < 0:
					cell.mesh_ring_map.erase(tree_key)
					continue
				cell.mesh_ring_map[tree_key] = ring_idx
				xf.origin = world_pos
				buckets[type_idx][ring_idx].append(xf)
				owners[type_idx][ring_idx].append([cell, tree_key])
				signatures[type_idx][ring_idx] = hash(Vector3i(
					int(signatures[type_idx][ring_idx]), hash(id), tree_idx))

	for type_idx in _types.size():
		for ring_idx in MESH_RING_COUNT:
			_upload_mesh_ring(
				type_idx, ring_idx,
				buckets[type_idx][ring_idx], owners[type_idx][ring_idx],
				int(signatures[type_idx][ring_idx]), force)

	_last_mesh_ring_cam = cam_local
	_mesh_rings_dirty = false
	_update_ring_shadows()


func _mesh_ring_for_distance(distance: float, previous_ring := -1) -> int:
	var split_0 := mesh_lod_distances.x
	var split_1 := mesh_lod_distances.y
	var h := mesh_lod_hysteresis
	match previous_ring:
		0:
			if distance >= mesh_distance + h:
				return -1
			if distance > split_1 + h:
				return 2
			if distance > split_0 + h:
				return 1
			return 0
		1:
			if distance >= mesh_distance + h:
				return -1
			if distance < split_0 - h:
				return 0
			if distance > split_1 + h:
				return 2
			return 1
		2:
			if distance >= mesh_distance + h:
				return -1
			if distance < split_0 - h:
				return 0
			if distance < split_1 - h:
				return 1
			return 2

	if distance >= mesh_distance:
		return -1
	if distance < split_0:
		return 0
	if distance < split_1:
		return 1
	return 2


## Sube todas las transforms del lote en una única operación. El orden de los
## 12 floats es el formato 3D row-major esperado por MultiMesh.buffer.
func _upload_mesh_ring(type_idx: int, ring_idx: int, transforms: Array, owners: Array, signature: int, force := false) -> void:
	var batch_key := Vector2i(type_idx, ring_idx)
	if not force and _mesh_batch_signatures.get(batch_key) == signature:
		return
	_clear_mesh_index_map_for_batch(batch_key)
	_mesh_batch_signatures[batch_key] = signature
	var mmi = _mesh_batches.get(batch_key)
	if transforms.is_empty():
		if mmi != null and is_instance_valid(mmi):
			mmi.visible = false
			if mmi.multimesh != null:
				mmi.multimesh.visible_instance_count = 0
		return

	if mmi == null or not is_instance_valid(mmi):
		mmi = MultiMeshInstance3D.new()
		mmi.name = "Forest_%02d_LOD%d" % [type_idx, ring_idx]
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(mmi)
		_mesh_batches[batch_key] = mmi
		var new_mm := MultiMesh.new()
		new_mm.transform_format = MultiMesh.TRANSFORM_3D
		new_mm.mesh = _types[type_idx].lod_ring_meshes[ring_idx]
		RenderingServer.multimesh_set_physics_interpolated(new_mm.get_rid(), false)
		mmi.multimesh = new_mm
		mmi.position = Vector3.ZERO
		mmi.reset_physics_interpolation()

	var buffer := PackedFloat32Array()
	buffer.resize(transforms.size() * 12)
	var min_pos: Vector3 = transforms[0].origin
	var max_pos: Vector3 = min_pos
	var max_padding := 0.0
	for instance_idx in transforms.size():
		var xf: Transform3D = transforms[instance_idx]
		var offset := instance_idx * 12
		buffer[offset] = xf.basis.x.x
		buffer[offset + 1] = xf.basis.y.x
		buffer[offset + 2] = xf.basis.z.x
		buffer[offset + 3] = xf.origin.x
		buffer[offset + 4] = xf.basis.x.y
		buffer[offset + 5] = xf.basis.y.y
		buffer[offset + 6] = xf.basis.z.y
		buffer[offset + 7] = xf.origin.y
		buffer[offset + 8] = xf.basis.x.z
		buffer[offset + 9] = xf.basis.y.z
		buffer[offset + 10] = xf.basis.z.z
		buffer[offset + 11] = xf.origin.z
		min_pos = Vector3(minf(min_pos.x, xf.origin.x), minf(min_pos.y, xf.origin.y), minf(min_pos.z, xf.origin.z))
		max_pos = Vector3(maxf(max_pos.x, xf.origin.x), maxf(max_pos.y, xf.origin.y), maxf(max_pos.z, xf.origin.z))
		max_padding = maxf(max_padding, _types[type_idx].frame_size * xf.basis.y.length())
		var owner_entry: Array = owners[instance_idx]
		owner_entry[0].mesh_index_map[owner_entry[1]] = [batch_key, instance_idx]

	var mm: MultiMesh = mmi.multimesh
	RenderingServer.multimesh_set_physics_interpolated(mm.get_rid(), false)
	if mm.instance_count != transforms.size():
		mm.instance_count = transforms.size()
	mm.buffer = buffer
	# El orden de slots puede cambiar al pasar un árbol de anillo. Nunca debe
	# interpolarse el slot N antiguo hacia el árbol que ahora ocupa el slot N.
	mm.reset_instances_physics_interpolation()
	mm.visible_instance_count = -1
	mm.custom_aabb = AABB(
		min_pos - Vector3.ONE * max_padding,
		max_pos - min_pos + Vector3.ONE * max_padding * 2.0)
	mmi.lod_bias = lod_bias
	mmi.visible = meshes_visible


func _clear_mesh_index_map_for_batch(batch_key: Vector2i) -> void:
	for id in _cells:
		var index_map: Dictionary = _cells[id].mesh_index_map
		for tree_key in index_map.keys():
			if index_map[tree_key][0] == batch_key:
				index_map.erase(tree_key)


## Un lote proyecta sombras solo si su anillo completo cae dentro de la
## distancia configurada. Así nunca duplicamos la pasada de todos los árboles
## del anillo medio para ganar apenas unos metros de sombra.
func _update_ring_shadows() -> void:
	for batch_key in _mesh_batches:
		var mmi = _mesh_batches[batch_key]
		if not is_instance_valid(mmi):
			continue
		var ring_idx: int = batch_key.y
		var ring_end: float
		if ring_idx == 0:
			ring_end = mesh_lod_distances.x
		elif ring_idx == 1:
			ring_end = mesh_lod_distances.y
		else:
			ring_end = mesh_distance
		var casts := mesh_shadows and ring_end <= shadow_distance + 0.5
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _free_cell(id: Vector3i) -> void:
	var cell: Dictionary = _cells[id]
	if cell.billboard != null and is_instance_valid(cell.billboard):
		cell.billboard.queue_free()
	_cells.erase(id)
	_mesh_rings_dirty = true


## Colliders solo para árboles a menos de collision_distance de la cámara.
func _update_colliders(cam_local: Vector3) -> void:
	var want := {}
	var cd2: float = collision_distance * collision_distance
	for id in _cells:
		var cell: Dictionary = _cells[id]
		if cell.count == 0:
			continue
		if cell.center.distance_to(cam_local) > collision_distance + cell_size:
			continue
		for t in cell.mesh_t.size():
			if _types[t].collision_radius <= 0.0:
				continue
			var arr: Array = cell.mesh_t[t]
			for i in arr.size():
				if cell.removed.has(Vector2i(t, i)):
					continue
				var xf: Transform3D = arr[i]
				var pos: Vector3 = cell.center + xf.origin
				if pos.distance_squared_to(cam_local) > cd2:
					continue
				want["%s_%d_%d" % [id, t, i]] = [id, t, i, xf, pos]

	for key in _colliders.keys():
		if not want.has(key):
			var b = _colliders[key]
			if is_instance_valid(b):
				b.queue_free()
			_colliders.erase(key)
	for key in want:
		if _colliders.has(key) and is_instance_valid(_colliders[key]):
			continue
		var e: Array = want[key]
		_colliders[key] = _spawn_collider(e[0], e[1], e[2], e[3], e[4])


func _spawn_collider(id: Vector3i, t: int, i: int, xf: Transform3D, pos: Vector3) -> ForestTreeBody:
	var ty: Dictionary = _types[t]
	var s: float = xf.basis.y.length()
	var up: Vector3 = xf.basis.y / s
	var body := ForestTreeBody.new()
	body.forest = self
	body.cell_id = id
	body.type_index = t
	body.tree_index = i
	body.source_scene = ty.packed_scene
	body.registered_scene = ty.registered_scene
	var shape := CylinderShape3D.new()
	shape.radius = ty.collision_radius * s
	shape.height = ty.collision_height * s
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.transform = Transform3D(xf.basis.orthonormalized(), pos + up * (ty.collision_height * s * 0.5))
	add_child(body)
	return body
