class_name SeaIceFloes extends Node3D

## Banquisa con volumen alrededor de la cámara: témpanos que flotan con la ola y se pisan, e
## icebergs. Más allá de FLOE_RANGE la banquisa sigue siendo la dibujada por el agua
## (water_shader), con el mismo reparto de témpanos (SeaIceLayout), así que el relevo no cambia el
## dibujo.
##
## Va colgado del PlanetLoader, cuyo origen es el centro del planeta y que se mueve con el origen
## flotante: todo lo de aquí dentro está en coordenadas relativas al planeta.
##
## - Mallas: un ArrayMesh por bloque de 4x4x4 celdas, construido en hilos. El shader
##   (sea_ice.gdshader) mueve cada témpano con la ola.
## - Colisiones: solo los témpanos junto al jugador, cuerpos animables que se colocan en cada tick
##   con la réplica CPU del mismo movimiento (_pose). Van en la capa de SeaIceFloor, que solo mira
##   el jugador: los barcos los atraviesan.
## - Icebergs: mallas propias y colisión estática en la capa del mundo (los barcos chocan).
## - Témpanos sueltos: al acercarse un barco, los de su alrededor salen de la malla de su bloque y
##   pasan a ser cuerpos rígidos (SeaIceRigidFloe) que el barco empuja y parte; los que van a la
##   deriva sueltan a su vez a los que tocan. Vuelven a su sitio cuando su bloque se descarga.

const SHADER := preload("res://shaders/liquid/sea_ice.gdshader")

## Radio con témpanos 3D. Los últimos metros encogen (fade_start/end del shader) mientras el agua
## va dibujando los suyos.
const FLOE_RANGE := 480.0
const FLOE_FADE := 100.0
const BERG_RANGE := 5000.0
## Cada cuánto se revisa qué bloques hacen falta, y cuánto ha de moverse la cámara.
const SCAN_INTERVAL := 0.25
const SCAN_MOVE := 25.0
const BERG_SCAN_MOVE := 250.0
const MAX_JOBS := 3
## Témpanos con colisión: los que tienen el borde a menos de esto del jugador.
const COLLIDER_REACH := 10.0
const MAX_COLLIDERS := 24
## Capa del mundo, para los icebergs.
const WORLD_LAYER := 1
## Olas que no mueven un témpano: las más cortas que su radio por esto (sea_ice.gdshader usa el mismo
## factor). Más alto, el témpano va más quieto pero el agua le pasa por encima en los cantos.
const FLOE_WAVE_FILTER := 1.2
## Témpanos sueltos a la vez, como mucho. Por encima el barco atraviesa los que falten.
const MAX_LOOSE := 60
## Metros alrededor del casco (más lo que recorre en 0,8 s) en que los témpanos se sueltan.
const BOAT_REACH := 14.0
## Un témpano suelto más rápido que esto suelta a los que toca.
const CHAIN_SPEED := 0.6
## Trozos más pequeños que esto (m²) se deshacen en el agua al partirse.
const MIN_PIECE_AREA := 3.0
## Cuántos bloques rehace como mucho por fotograma al soltar témpanos.
const REBUILDS_PER_FRAME := 2

var water_material: ShaderMaterial
var world_map: PlanetWorldMap
var sea_radius: float
var player: Node3D
## Tamaño de la celda de los témpanos: ice_floe_size del material del agua.
var floe_size := 38.0

var _floe_material: ShaderMaterial
var _berg_material: ShaderMaterial
var _sampler: WaterHeightSampler
## Uniforms del oleaje que hay que copiar del agua (los que comparten los dos shaders).
var _synced_params: Array[StringName] = []
var _sync_timer := 0.0

## Vector3i -> {mesh: MeshInstance3D, floes: Array[Dictionary]}; o {"pending": true}.
var _chunks: Dictionary = {}
var _jobs := 0
var _mutex := Mutex.new()
var _done: Array = []
var _scan_timer := 0.0
var _last_scan := Vector3.INF
## La última revisión dejó bloques sin encargar (tope de hilos): hay que volver aunque la cámara
## no se mueva.
var _incomplete := false
var _last_berg_scan := Vector3.INF
var _berg_job := false
## Vector3i (celda) -> {node: Node3D, berg: Dictionary}
var _bergs: Dictionary = {}
## id del témpano -> {body: AnimatableBody3D, floe: Dictionary}.
var _colliders: Dictionary = {}
## id del témpano -> ConvexPolygonShape3D, para no rehacerla cada vez que se acerca.
var _shapes: Dictionary = {}
var _free_bodies: Array[AnimatableBody3D] = []
var _nearby: Array[Dictionary] = []
var _nearby_timer := 0.0
var _loose_material: ShaderMaterial
## id -> {body: SeaIceRigidFloe, floe, chunk}. Los trozos de uno partido llevan ids nuevos.
var _loose: Dictionary = {}
## id del témpano original -> bloque: ya no se dibuja en la malla del bloque.
var _removed: Dictionary = {}
var _dirty_chunks: Dictionary = {}
var _next_piece := 0


func setup(water: ShaderMaterial, map: PlanetWorldMap, radius: float, who: Node3D) -> void:
	name = "SeaIceFloes"
	water_material = water
	world_map = map
	sea_radius = radius
	player = who
	var size: Variant = WaterHeightSampler._param(water, &"ice_floe_size")
	if size != null:
		floe_size = size
	_floe_material = ShaderMaterial.new()
	_floe_material.shader = SHADER
	_floe_material.set_shader_parameter(&"fade_start", FLOE_RANGE - FLOE_FADE)
	_floe_material.set_shader_parameter(&"fade_end", FLOE_RANGE)
	_berg_material = ShaderMaterial.new()
	_berg_material.shader = SHADER
	_berg_material.set_shader_parameter(&"floating", false)
	_loose_material = ShaderMaterial.new()
	_loose_material.shader = SHADER
	_loose_material.set_shader_parameter(&"floating", false)
	_loose_material.set_shader_parameter(&"rigid", true)
	var water_names := {}
	for uniform in water.shader.get_shader_uniform_list():
		water_names[StringName(uniform.name)] = true
	for uniform in SHADER.get_shader_uniform_list():
		var uname := StringName(uniform.name)
		if water_names.has(uname):
			_synced_params.append(uname)
	_sync_params()
	# El agua dibuja sus témpanos solo donde acaban los de aquí.
	water.set_shader_parameter(&"ice_geometry_start", FLOE_RANGE - FLOE_FADE)
	water.set_shader_parameter(&"ice_geometry_end", FLOE_RANGE)
	_sampler = WaterHeightSampler.new()
	add_child(_sampler)
	_sampler.setup(water, map, radius)


func set_world_map(map: PlanetWorldMap) -> void:
	world_map = map
	if _sampler != null:
		_sampler.world_map = map
	# Lo construido sin mapa no sabía de costas ni de fondo: se rehace.
	_clear_all()


func _exit_tree() -> void:
	if water_material != null:
		water_material.set_shader_parameter(&"ice_geometry_end", 0.0)


func _process(delta: float) -> void:
	if water_material == null:
		return
	var _t0 := Time.get_ticks_usec()
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = 0.5
		_sync_params()
	_floe_material.set_shader_parameter(&"water_time", water_material.get_shader_parameter(&"water_time"))
	var center: Variant = water_material.get_shader_parameter(&"planet_center")
	_floe_material.set_shader_parameter(&"planet_center", center)
	_berg_material.set_shader_parameter(&"planet_center", center)
	_loose_material.set_shader_parameter(&"planet_center", center)
	_collect_jobs()
	_rebuild_dirty()
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_scan()
	DebugStats.report_cost(&"agua:banquisa", Time.get_ticks_usec() - _t0)


func _sync_params() -> void:
	for pname in _synced_params:
		var value: Variant = water_material.get_shader_parameter(pname)
		if value != null:
			_floe_material.set_shader_parameter(pname, value)
			_berg_material.set_shader_parameter(pname, value)
			_loose_material.set_shader_parameter(pname, value)


func _sample_context() -> Dictionary:
	var shore: Variant = WaterHeightSampler._param(water_material, &"shore_waves_enabled")
	var params: Variant = WaterHeightSampler._param(water_material, &"sea_ice_params")
	return {
		"map": world_map if world_map != null and world_map.is_ready() else null,
		"shore_on": shore != null and bool(shore) and world_map != null and world_map.is_ready(),
		"params": params if params is Vector4 else Vector4(57.0, 63.0, 10.0, 300.0),
		"radius": sea_radius,
		"bergs": [],
	}


func _enabled() -> bool:
	var on: Variant = WaterHeightSampler._param(water_material, &"sea_ice_enabled")
	return on != null and bool(on)


func _camera_local() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	var pos := cam.global_position if cam != null else (player.global_position if player != null else Vector3.ZERO)
	return pos - global_position


## Qué bloques hacen falta: los que cortan el mar a menos de FLOE_RANGE de la cámara y donde el
## hielo, con toda la ventaja de costa, puede existir.
func _scan() -> void:
	if not _enabled():
		if not _chunks.is_empty() or not _bergs.is_empty():
			_clear_all()
		return
	var cam := _camera_local()
	var ctx := _sample_context()
	if cam.distance_to(_last_berg_scan) > BERG_SCAN_MOVE and not _berg_job:
		_last_berg_scan = cam
		_berg_job = true
		_jobs += 1
		WorkerThreadPool.add_task(_berg_scan_job.bind(cam, ctx, _bergs.duplicate()), false, "Icebergs")
	if cam.distance_to(_last_scan) < SCAN_MOVE and not _incomplete:
		return
	_last_scan = cam
	var altitude := cam.length() - sea_radius
	var chunk_size := floe_size * SeaIceLayout.CHUNK_CELLS
	var wanted := {}
	if altitude < FLOE_RANGE:
		var ground := cam.normalized() * sea_radius
		var reach := FLOE_RANGE + chunk_size
		var lo := ((ground - Vector3.ONE * reach) / chunk_size).floor()
		var hi := ((ground + Vector3.ONE * reach) / chunk_size).floor()
		var params: Vector4 = ctx.params
		for x in range(int(lo.x), int(hi.x) + 1):
			for y in range(int(lo.y), int(hi.y) + 1):
				for z in range(int(lo.z), int(hi.z) + 1):
					var key := Vector3i(x, y, z)
					var mid := (Vector3(key) + Vector3.ONE * 0.5) * chunk_size
					# El bloque ha de tocar la corteza del mar...
					if absf(mid.length() - sea_radius) > chunk_size * 0.87 + floe_size * 1.6:
						continue
					var on_sea := mid.normalized() * sea_radius
					if on_sea.distance_to(ground) > reach:
						continue
					# ...y poder tener hielo (la costa lo adelanta como mucho params.z grados).
					if ClimateField.sea_ice_with(on_sea, 0.0, params) <= 0.0:
						continue
					wanted[key] = on_sea.distance_to(cam)
	# Fuera lo que ya no hace falta (con holgura para no rehacer al ir y venir).
	for key in _chunks.keys():
		if wanted.has(key):
			continue
		var mid := (Vector3(key) + Vector3.ONE * 0.5) * chunk_size
		if mid.normalized().distance_to(cam.normalized()) * sea_radius < FLOE_RANGE + chunk_size * 2.0 \
				and altitude < FLOE_RANGE * 1.5:
			continue
		_drop_chunk(key)
	# Los que faltan, del más cercano al más lejano.
	var missing: Array = []
	for key in wanted:
		if not _chunks.has(key):
			missing.append(key)
	missing.sort_custom(func(a, b): return wanted[a] < wanted[b])
	_incomplete = false
	for key in missing:
		if _jobs >= MAX_JOBS:
			_incomplete = true
			break
		_chunks[key] = {"pending": true}
		_jobs += 1
		WorkerThreadPool.add_task(_chunk_job.bind(key, ctx), false, "Témpanos")


func _chunk_job(key: Vector3i, ctx: Dictionary) -> void:
	var chunk_size := floe_size * SeaIceLayout.CHUNK_CELLS
	var mid := (Vector3(key) + Vector3.ONE * 0.5) * chunk_size
	ctx.bergs = _bergs_near(mid, chunk_size, ctx)
	var floes := SeaIceLayout.chunk_floes(key, floe_size, ctx)
	var origin := mid.normalized() * sea_radius
	var arrays := SeaIceMeshes.floe_arrays(floes, origin)
	_mutex.lock()
	_done.append({"kind": "chunk", "key": key, "floes": floes, "arrays": arrays, "origin": origin})
	_mutex.unlock()


## Icebergs que pueden tocar un bloque: las celdas de iceberg de alrededor.
static func _bergs_near(mid: Vector3, chunk_size: float, ctx: Dictionary) -> Array:
	var out := []
	var cell := (mid / SeaIceLayout.ICEBERG_CELL).floor()
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var berg := SeaIceLayout.cell_berg(Vector3i(cell) + Vector3i(dx, dy, dz), ctx)
				if not berg.is_empty() and berg.center.distance_to(mid) < chunk_size + berg.radius * 2.0:
					out.append(berg)
	return out


func _berg_scan_job(cam: Vector3, ctx: Dictionary, existing: Dictionary) -> void:
	var found := {}
	var ground := cam.normalized() * sea_radius
	var lo := ((ground - Vector3.ONE * BERG_RANGE) / SeaIceLayout.ICEBERG_CELL).floor()
	var hi := ((ground + Vector3.ONE * BERG_RANGE) / SeaIceLayout.ICEBERG_CELL).floor()
	var params: Vector4 = ctx.params
	var reach := Vector4(params.x - SeaIceLayout.ICEBERG_REACH, params.y, params.z, params.w)
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				var c := Vector3i(x, y, z)
				var mid := (Vector3(c) + Vector3.ONE * 0.5) * SeaIceLayout.ICEBERG_CELL
				if absf(mid.length() - sea_radius) > SeaIceLayout.ICEBERG_CELL:
					continue
				var on_sea := mid.normalized() * sea_radius
				if on_sea.distance_to(ground) > BERG_RANGE:
					continue
				if ClimateField.sea_ice_with(on_sea, 0.0, reach) <= 0.0:
					continue
				var berg := SeaIceLayout.cell_berg(c, ctx)
				if berg.is_empty():
					continue
				if existing.has(c):
					found[c] = {"berg": berg}
					continue
				var mesh := SeaIceMeshes.berg_mesh(berg)
				found[c] = {"berg": berg, "arrays": mesh.surface_get_arrays(0)}
	_mutex.lock()
	_done.append({"kind": "bergs", "found": found})
	_mutex.unlock()


func _collect_jobs() -> void:
	_mutex.lock()
	var done := _done
	_done = []
	_mutex.unlock()
	for job in done:
		_jobs -= 1
		if job.kind == "bergs":
			_berg_job = false
			_apply_bergs(job.found)
			continue
		var key: Vector3i = job.key
		if not _chunks.has(key):
			continue
		var entry := {"floes": job.floes, "mesh": null}
		if not job.arrays.is_empty():
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job.arrays, [], {},
				SeaIceMeshes.FLOE_FORMAT)
			mesh.surface_set_material(0, _floe_material)
			# La ola mueve los témpanos hasta unos metros: el AABB de reposo se quedaría corto.
			mesh.custom_aabb = mesh.get_aabb().grow(6.0)
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.position = job.origin
			add_child(instance)
			entry.mesh = instance
		_chunks[key] = entry


func _apply_bergs(found: Dictionary) -> void:
	for c in _bergs.keys():
		if not found.has(c):
			(_bergs[c].node as Node).queue_free()
			_bergs.erase(c)
	for c in found:
		if _bergs.has(c):
			continue
		var entry: Dictionary = found[c]
		if not entry.has("arrays"):
			continue
		var berg: Dictionary = entry.berg
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, entry.arrays)
		mesh.surface_set_material(0, _berg_material)
		var body := StaticBody3D.new()
		body.name = "Iceberg"
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		var up: Vector3 = berg.center.normalized()
		var basis := SeaIceLayout.frame(up).rotated(up, float(berg.seed % 628) * 0.01)
		body.transform = Transform3D(basis, berg.center)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.visibility_range_end = BERG_RANGE
		instance.visibility_range_end_margin = 400.0
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		body.add_child(instance)
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		add_child(body)
		_bergs[c] = {"node": body, "berg": berg}


func _drop_chunk(key: Vector3i) -> void:
	var entry: Dictionary = _chunks[key]
	_chunks.erase(key)
	_dirty_chunks.erase(key)
	if entry.get("mesh") != null:
		(entry.mesh as Node).queue_free()
	for floe in entry.get("floes", []):
		_release_collider(floe.id)
		_shapes.erase(floe.id)
		_removed.erase(floe.id)
	# Lo soltado de este bloque se va con él: al volver, la banquisa está como siempre.
	for id in _loose.keys():
		if _loose[id].chunk == key:
			(_loose[id].body as Node).queue_free()
			_loose.erase(id)


func _clear_all() -> void:
	for key in _chunks.keys():
		if not _chunks[key].has("pending"):
			_drop_chunk(key)
	for c in _bergs:
		(_bergs[c].node as Node).queue_free()
	_bergs.clear()
	for id in _loose:
		(_loose[id].body as Node).queue_free()
	_loose.clear()
	_removed.clear()
	_last_scan = Vector3.INF
	_last_berg_scan = Vector3.INF


# --- Colisiones --------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if player == null or _chunks.is_empty():
		if not _colliders.is_empty():
			for id in _colliders.keys():
				_release_collider(id)
		return
	_release_near_boats()
	var local := player.global_position - global_position
	_nearby_timer -= delta
	if _nearby_timer <= 0.0:
		_nearby_timer = 0.2
		_nearby = _floes_near(local, COLLIDER_REACH)
		var keep := {}
		for floe in _nearby:
			keep[floe.id] = true
		for id in _colliders.keys():
			if not keep.has(id):
				_release_collider(id)
	var time := WaterHeightSampler.get_water_time(water_material)
	for floe in _nearby:
		var entry: Dictionary = _colliders.get(floe.id, {})
		var body: AnimatableBody3D = entry.get("body")
		if body == null:
			if _colliders.size() >= MAX_COLLIDERS:
				continue
			body = _acquire_collider(floe)
		body.transform = _pose(floe, time)


## Témpanos cuyo borde queda a menos de `reach` de `local`, del más cercano al más lejano.
func _floes_near(local: Vector3, reach: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var chunk_size := floe_size * SeaIceLayout.CHUNK_CELLS
	var base := (local.normalized() * sea_radius / chunk_size).floor()
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var entry: Dictionary = _chunks.get(Vector3i(base) + Vector3i(dx, dy, dz), {})
				for floe in entry.get("floes", []):
					var r: float = floe.radius + reach
					if (floe.center as Vector3).distance_squared_to(local) < r * r \
							and not _removed.has(floe.id):
						out.append(floe)
	out.sort_custom(func(a, b): return (a.center as Vector3).distance_squared_to(local) \
		< (b.center as Vector3).distance_squared_to(local))
	return out


## Réplica CPU del vertex() de sea_ice.gdshader: dónde está el témpano ahora (relativo al planeta).
func _pose(floe: Dictionary, time: float) -> Transform3D:
	var c: Vector3 = floe.center
	var up := c.normalized()
	var disp := _sampler.rest_displacement(c, time, float(floe.radius) * FLOE_WAVE_FILTER)
	var n := _sampler.last_normal()
	var open := 1.0 - smoothstep(0.85, 1.0, _sampler.last_ice)
	var ph: float = float(floe.seed) * TAU
	var basis: Basis = floe.basis
	var drift: Vector3 = (basis.x * sin(time * 0.071 + ph) + basis.z * sin(time * 0.053 + ph * 1.7)) * (0.5 * open)
	var yaw := sin(time * 0.037 + ph * 2.3) * 0.06 * open
	var rot := Basis(up, yaw)
	var tilt_axis := up.cross(n)
	if tilt_axis.length_squared() > 1e-10:
		rot = Basis(tilt_axis.normalized(), up.angle_to(n)) * rot
	return Transform3D(rot * basis, c + disp + drift)


func _acquire_collider(floe: Dictionary) -> AnimatableBody3D:
	var body: AnimatableBody3D
	var shape: CollisionShape3D
	if _free_bodies.is_empty():
		body = AnimatableBody3D.new()
		body.name = "Floe"
		body.collision_layer = SeaIceFloor.LAYER
		body.collision_mask = 0
		body.sync_to_physics = true
		shape = CollisionShape3D.new()
		body.add_child(shape)
		add_child(body)
	else:
		body = _free_bodies.pop_back()
		shape = body.get_child(0)
		body.process_mode = Node.PROCESS_MODE_INHERIT
		shape.disabled = false
	if not _shapes.has(floe.id):
		var points := PackedVector3Array()
		for v in floe.poly:
			points.append(Vector3(v.x, floe.top, v.y))
			points.append(Vector3(v.x, floe.bottom, v.y))
		var convex := ConvexPolygonShape3D.new()
		convex.points = points
		_shapes[floe.id] = convex
	shape.shape = _shapes[floe.id]
	_colliders[floe.id] = {"body": body, "floe": floe}
	return body


func _release_collider(id: Vector4i) -> void:
	var entry: Dictionary = _colliders.get(id, {})
	if entry.is_empty():
		return
	var body: AnimatableBody3D = entry.body
	_colliders.erase(id)
	(body.get_child(0) as CollisionShape3D).disabled = true
	body.process_mode = Node.PROCESS_MODE_DISABLED
	_free_bodies.append(body)


# --- Témpanos sueltos --------------------------------------------------------------------------

func wave_sampler() -> WaterHeightSampler:
	return _sampler


## Suelta los témpanos alrededor de cada barco, y los que tocan los témpanos sueltos a la deriva.
func _release_near_boats() -> void:
	for node in DynamicGridBody.bodies_in_play(get_tree()):
		var boat := node as DynamicGridBody
		if boat == null or not boat.is_inside_tree():
			continue
		var bounds := boat.get_hull_bounds()
		if bounds.is_empty():
			continue
		var local := boat.get_hull_center_world() - global_position
		var reach: float = (bounds.half as Vector3).length() + BOAT_REACH + boat.linear_velocity.length() * 0.8
		if absf(local.length() - sea_radius) > reach + 10.0:
			continue
		for floe in _floes_near(local, reach):
			_loosen(floe)
	for id in _loose.keys():
		var body: SeaIceRigidFloe = _loose[id].body
		if body.linear_velocity.length() > CHAIN_SPEED:
			for floe in _floes_near(body.position, 2.5):
				_loosen(floe)


## Saca un témpano de la malla de su bloque y lo convierte en cuerpo rígido, justo donde el shader
## lo estaba dibujando y con la velocidad que llevaba.
func _loosen(floe: Dictionary) -> void:
	if _removed.has(floe.id) or _loose.size() >= MAX_LOOSE:
		return
	var id: Vector4i = floe.id
	var chunk := Vector3i(floori(id.x / float(SeaIceLayout.CHUNK_CELLS)),
		floori(id.y / float(SeaIceLayout.CHUNK_CELLS)), floori(id.z / float(SeaIceLayout.CHUNK_CELLS)))
	var time := WaterHeightSampler.get_water_time(water_material)
	var pose := _pose(floe, time)
	var velocity := (_pose(floe, time + 0.1).origin - pose.origin) / 0.1
	_release_collider(id)
	_removed[id] = chunk
	_dirty_chunks[chunk] = true
	_spawn_loose(id, floe, chunk, pose, velocity)


func _spawn_loose(id: Vector4i, floe: Dictionary, chunk: Vector3i, xf: Transform3D, velocity: Vector3) -> SeaIceRigidFloe:
	var body := SeaIceRigidFloe.new()
	add_child(body)
	body.setup(self, floe, xf, _loose_material, velocity)
	_loose[id] = {"body": body, "floe": floe, "chunk": chunk}
	return body


## Rehace las mallas de los bloques de los que se han soltado témpanos, sin ellos.
func _rebuild_dirty() -> void:
	var done := 0
	for key in _dirty_chunks.keys():
		if done >= REBUILDS_PER_FRAME:
			break
		_dirty_chunks.erase(key)
		var entry: Dictionary = _chunks.get(key, {})
		if entry.is_empty() or entry.has("pending"):
			continue
		done += 1
		var kept: Array[Dictionary] = []
		for floe in entry.floes:
			if not _removed.has(floe.id):
				kept.append(floe)
		var instance: MeshInstance3D = entry.get("mesh")
		if instance == null:
			continue
		var arrays := SeaIceMeshes.floe_arrays(kept, instance.position)
		if arrays.is_empty():
			instance.queue_free()
			entry.mesh = null
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, SeaIceMeshes.FLOE_FORMAT)
		mesh.surface_set_material(0, _floe_material)
		mesh.custom_aabb = mesh.get_aabb().grow(6.0)
		instance.mesh = mesh


## Parte un témpano suelto por donde lo ha golpeado un barco: dos o tres trozos que se separan,
## y los que quedan demasiado pequeños se deshacen en el agua.
func shatter(body: SeaIceRigidFloe, world_pos: Vector3, rammer: Node) -> void:
	var key: Variant = null
	for id in _loose:
		if _loose[id].body == body:
			key = id
			break
	if key == null or body.is_queued_for_deletion():
		return
	var entry: Dictionary = _loose[key]
	_loose.erase(key)
	var floe: Dictionary = body.floe
	var xf := body.transform
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ _next_piece
	# La grieta pasa por el punto del golpe, no por el centro.
	var hit := xf.affine_inverse() * (world_pos - global_position)
	var cuts := 1 if body.damage < body._break_energy * 2.0 else 2
	var pieces := SeaIceLayout._break_through(floe.poly, rng, cuts, Vector2(hit.x, hit.z))
	var push := Vector3.ZERO
	if rammer is RigidBody3D:
		push = (rammer as RigidBody3D).linear_velocity * 0.25
	var up := xf.basis.y
	for piece in pieces:
		var area := absf(SeaIceLayout._area(piece))
		if area < MIN_PIECE_AREA:
			continue
		var pc := SeaIceLayout._centroid(piece)
		var local_poly := PackedVector2Array()
		var radius := 0.0
		for v in piece:
			local_poly.append(v - pc)
			radius = maxf(radius, v.distance_to(pc))
		var offset := xf.basis * Vector3(pc.x, 0.0, pc.y)
		var part := floe.duplicate()
		part.poly = local_poly
		part.radius = radius
		_next_piece += 1
		part.id = Vector4i(-1, -1, _next_piece, 0)
		var out_dir := (offset - up * offset.dot(up)).normalized() if offset.length() > 0.01 else Vector3.ZERO
		var velocity := body.linear_velocity + body.angular_velocity.cross(offset) + out_dir * 1.2 + push
		var piece_body := _spawn_loose(part.id, part, entry.chunk,
			Transform3D(xf.basis, xf.origin + offset), velocity)
		piece_body.angular_velocity = body.angular_velocity + up * rng.randf_range(-0.3, 0.3)
	body.queue_free()
	var world_up := (world_pos - global_position).normalized()
	BlockDebris.burst(self, world_pos, world_up, 6, 0.5)
	AudioManager.play_material(&"block_impact", &"rock", world_pos, {"volume_offset_db": 0.0})
	AudioManager.play_3d(&"water_splash", world_pos)


## Cuerpos de témpano que el jugador puede pisar: los que siguen a la ola junto a él y los sueltos.
func _bodies() -> Array:
	var out := []
	for id in _colliders:
		out.append(_colliders[id])
	for id in _loose:
		out.append(_loose[id])
	return out


# --- Consultas del jugador ---------------------------------------------------------------------

## El témpano (con colisión) sobre el que está `world_pos`, o {} si ninguno. Sirve para decidir
## que el jugador camina y no nada.
func floe_under(world_pos: Vector3, margin: float = 0.35) -> Dictionary:
	for entry in _bodies():
		var body: Node3D = entry.body
		var floe: Dictionary = entry.floe
		var p := body.global_transform.affine_inverse() * world_pos
		if p.y < float(floe.bottom) or p.y > float(floe.top) + 1.4:
			continue
		if _inside(floe.poly, Vector2(p.x, p.z), margin):
			return floe
	return {}


## Punto sobre el canto de un témpano al que puede subirse un nadador en `world_pos`, o INF.
func haul_out_point(world_pos: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := 1.6
	for entry in _bodies():
		var body: Node3D = entry.body
		var floe: Dictionary = entry.floe
		var xf := body.global_transform
		var p := xf.affine_inverse() * world_pos
		# Nadando, el origen del cuerpo va unos 2,5 m bajo la superficie (swimming_offset).
		if p.y > float(floe.top) + 0.5 or p.y < -3.5:
			continue
		var flat := Vector2(p.x, p.z)
		var edge := _closest_on_poly(floe.poly, flat)
		var d := edge.distance_to(flat)
		if d < best_d:
			best_d = d
			# Un poco hacia dentro del canto, de pie sobre la cara de arriba.
			var inward := -edge.normalized() if edge.length() > 0.01 else Vector2.ZERO
			var stand := edge + inward * minf(0.8, edge.length() * 0.5)
			best = xf * Vector3(stand.x, float(floe.top) + 0.1, stand.y)
	return best


static func _inside(poly: PackedVector2Array, p: Vector2, margin: float) -> bool:
	var count := poly.size()
	for i in count:
		var a := poly[i]
		var e := poly[(i + 1) % count] - a
		# Antihorario: el interior queda a la izquierda de cada arista.
		if e.cross(p - a) < -margin * e.length():
			return false
	return true


static func _closest_on_poly(poly: PackedVector2Array, p: Vector2) -> Vector2:
	var best := poly[0]
	var best_d := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var q := a + ab * t
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best
