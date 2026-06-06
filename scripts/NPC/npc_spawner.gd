class_name NPCSpawner extends Node3D

## Segundos entre comprobaciones del pool.
const RECYCLE_CHECK_INTERVAL := 10.0
## Segundos de espera inicial para que el terreno voxel se genere.
const INITIAL_SPAWN_DELAY := 4.0
## Intentos máximos por posición antes de descartar.
const MAX_SPAWN_ATTEMPTS := 2
## Normal del terreno · dirección radial mínima para considerar el suelo válido (~49°).
const MIN_SLOPE_DOT := 0.65
## Duración en segundos de las líneas de debug antes de desaparecer.
const DEBUG_RAY_DURATION := 6.0

var debug_rays: bool = false
var _min_spawn_distance := 60.0
var _planets: Node3D
var _scene_path: String = ""
var _biomes: Array[int] = []
var _min_height: float = 0.0
var _max_height: float = 200.0
var _max_npcs: int = 5
var _lod_active_dist : float = 80.0
var _max_distance : float = 80.0
var _planet_radius: float = 0.0
var _atmosphere_height: float = 1400.0
var _planet_center: Vector3 = Vector3.ZERO
var _biome_latitude_ranges: Array[float] = []
var _players: Array[CharacterBody3D] = []

var _npc_scene: PackedScene = null
var _npc_pool: Array[NPCController] = []
var _recycle_timer: float = 0.0
var _spawn_queue: Array[Vector3] = []
var _queue_running: bool = false


func setup(config: Dictionary, p_radius: float, p_atmosphere_height: float,
		p_center: Vector3, p_biome_ranges: Array[float],
		p_players: Array[CharacterBody3D], planets) -> void:
	_scene_path = config.get("scene", "")
	_biomes.clear()
	for b in config.get("biomes", []):
		_biomes.append(int(b))
	_min_height = float(config.get("min_height", 0.0))
	_max_height = float(config.get("max_height", 200.0))
	_max_npcs = int(config.get("max_npcs", 5))
	_min_spawn_distance = float(config.get("min_spawn_distance", 60.0))
	_lod_active_dist = float(config.get("lod_active_dist", 50.0))
	_max_distance = float(config.get("max_distance", 100.0))
	_planet_radius = p_radius
	_atmosphere_height = p_atmosphere_height
	_planet_center = p_center
	_biome_latitude_ranges = p_biome_ranges
	_players = p_players
	_npc_scene = load(_scene_path) as PackedScene
	_planets = planets
	if not _npc_scene:
		push_error("NPCSpawner: cannot load scene '%s'" % _scene_path)


func _ready() -> void:
	if not _npc_scene or _biomes.is_empty():
		return
	await get_tree().create_timer(INITIAL_SPAWN_DELAY).timeout
	var origin := _get_player_pos()
	for _i in _max_npcs:
		var pos := _find_spawn_near(origin) if origin != Vector3.ZERO else _find_spawn_random()
		if pos != Vector3.ZERO:
			_enqueue_spawn(pos)


func _physics_process(delta: float) -> void:
	_recycle_timer += delta
	if _recycle_timer < RECYCLE_CHECK_INTERVAL:
		return
	_recycle_timer = 0.0
	_recycle_pool()


func _recycle_pool() -> void:
	if _players.is_empty():
		return
	var player_pos := _players[0].global_position
	var i := _npc_pool.size() - 1
	while i >= 0:
		var npc := _npc_pool[i]
		if not is_instance_valid(npc):
			# El NPC murió — eliminar de la pool y reponer
			_npc_pool.remove_at(i)
			var pos := _find_spawn_near(player_pos)
			if pos != Vector3.ZERO:
				_enqueue_spawn(pos)
		else:
			var dist := npc.global_position.distance_to(player_pos)
			if dist > _max_distance:
				var recycled := _teleport_npc(npc, player_pos)
				if recycled:
					npc.set_physics_process(true)
				else:
					# No hay posición válida en este bioma (p.ej. player en otro bioma):
					# eliminar de la pool para que el conteo refleje la realidad.
					npc.queue_free()
					_npc_pool.remove_at(i)
			else:
				var lod_active := dist <= _lod_active_dist or not npc.is_on_floor()
				npc.set_physics_process(lod_active)
				if lod_active:
					npc._physics_interval = 0.0 if dist < 15.0 else 0.5
				if npc.perception:
					npc.perception.set_physics_process(lod_active)
		i -= 1

	# Rellenar si el pool está por debajo del máximo (p.ej. tras muertes).
	# Se cuenta también lo que hay en cola para no encolar de más.
	var total := _npc_pool.size() + _spawn_queue.size()
	while total < _max_npcs:
		var pos := _find_spawn_near(player_pos)
		if pos == Vector3.ZERO:
			break
		_enqueue_spawn(pos)
		total += 1


func _enqueue_spawn(pos: Vector3) -> void:
	_spawn_queue.append(pos)
	if not _queue_running:
		_run_spawn_queue()


func _run_spawn_queue() -> void:
	_queue_running = true
	while not _spawn_queue.is_empty():
		var pos : Vector3 = _spawn_queue.pop_front()
		_spawn_npc_at(pos)
		await get_tree().process_frame
	_queue_running = false


func _spawn_npc_at(pos: Vector3) -> void:
	var npc := _npc_scene.instantiate() as NPCController
	if not npc:
		return
	npc.planets = _planets
	var stride : int = max(1, _max_npcs)
	npc._frame_offset = _npc_pool.size() % stride
	npc._ai_update_stride = stride
	add_child(npc)
	npc.global_position = pos
	_npc_pool.append(npc)


## Intenta teleportar el NPC a una posición válida cerca del player.
## Devuelve true si encontró posición, false si no hay spawn válido en el bioma actual.
func _teleport_npc(npc: NPCController, player_pos: Vector3) -> bool:
	var pos := _find_spawn_near(player_pos)
	if pos == Vector3.ZERO:
		return false
	npc.global_position = pos
	npc.velocity = Vector3.ZERO
	npc.ai_controller.transition_to(npc.initial_ai_state)
	return true


# ── Posicionamiento ──────────────────────────────────────────────────────────

## Busca una posición válida cerca del player: elige una dirección en un radio
## aleatorio alrededor del player (proyectado en la esfera), y lanza un raycast
## desde la altura de la atmósfera para encontrar la superficie.
## El ángulo se muestrea del arco fuera del frustum de la cámara para que
## el jugador nunca vea aparecer un NPC.
func _find_spawn_near(player_pos: Vector3) -> Vector3:
	var up := (player_pos - _planet_center).normalized()
	var right := _perp(up)
	var fwd := up.cross(right).normalized()

	# Arco prohibido: proyección horizontal del frustum sobre el plano tangente.
	var forbidden_center := 0.0
	var half_fov := PI  # sin restricción por defecto
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera:
		var cam_fwd := -camera.global_basis.z
		var cam_fwd_flat := cam_fwd - up * cam_fwd.dot(up)
		if cam_fwd_flat.length_squared() > 0.001:
			cam_fwd_flat = cam_fwd_flat.normalized()
			forbidden_center = atan2(cam_fwd_flat.dot(fwd), cam_fwd_flat.dot(right))
			var aspect := get_viewport().get_visible_rect().size.aspect()
			var h_fov := 2.0 * atan(tan(deg_to_rad(camera.fov)) * aspect)
			half_fov = clamp(h_fov * 0.5 + 0.35, 0.0, PI)  # margen extra de ~20°

	var safe_arc := TAU - 2.0 * half_fov

	for _attempt in MAX_SPAWN_ATTEMPTS:
		var angle: float
		if safe_arc > 0.01:
			# Muestrea uniformemente fuera del arco prohibido.
			angle = fmod(forbidden_center + half_fov + randf_range(0.0, safe_arc), TAU)
		else:
			angle = randf_range(0.0, TAU)
		var dist := randf_range(_min_spawn_distance, _max_distance * 0.6)
		var dir := (player_pos + (right * cos(angle) + fwd * sin(angle)) * dist - _planet_center).normalized()
		var lat := rad_to_deg(asin(clamp(dir.y, -1.0, 1.0)))
		if _is_valid_latitude(lat):
			var pos := _raycast_surface(dir)
			if pos != Vector3.ZERO and not _is_in_player_frustum(pos):
				return pos
	return Vector3.ZERO


## Comprueba si una posición en mundo está dentro del frustum de la cámara activa.
func _is_in_player_frustum(pos: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return false
	for plane in camera.get_frustum():
		if plane.distance_to(pos) < 0.0:
			return false
	return true


## Busca una posición válida aleatoria dentro del bioma.
func _find_spawn_random() -> Vector3:
	for _attempt in MAX_SPAWN_ATTEMPTS:
		var pos := _raycast_surface(_random_biome_dir())
		if pos != Vector3.ZERO:
			return pos
	return Vector3.ZERO


## Lanza un raycast desde la atmósfera en la dirección dada hacia el centro del planeta.
## Devuelve la posición sobre la superficie si cumple los criterios (altura y pendiente),
## o Vector3.ZERO si no hay hit válido.
func _raycast_surface(dir: Vector3) -> Vector3:
	var space_state := get_world_3d().direct_space_state
	var from := _planet_center + dir * (_planet_radius + _atmosphere_height)
	var query := PhysicsRayQueryParameters3D.create(from, _planet_center)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		if debug_rays:
			DebugUtils.draw_debug_line(from, _planet_center, Color.GRAY, DEBUG_RAY_DURATION)
		return Vector3.ZERO
	var hit_pos: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	if hit_normal.dot(dir) < MIN_SLOPE_DOT:
		if debug_rays:
			DebugUtils.draw_debug_line(from, hit_pos, Color.ORANGE, DEBUG_RAY_DURATION)
		return Vector3.ZERO
	var height := hit_pos.distance_to(_planet_center) - _planet_radius
	if height < _min_height or height > _max_height:
		if debug_rays:
			DebugUtils.draw_debug_line(from, hit_pos, Color.RED, DEBUG_RAY_DURATION)
		return Vector3.ZERO
	var spawn_pos := hit_pos + hit_normal * 10.0
	if debug_rays:
		DebugUtils.draw_debug_line(from, hit_pos, Color.GREEN, DEBUG_RAY_DURATION)
		DebugUtils.draw_debug_point(spawn_pos, Color.GREEN, 3.0, DEBUG_RAY_DURATION)
	return spawn_pos


func _random_biome_dir() -> Vector3:
	var biome_idx := _biomes[randi() % _biomes.size()]
	if biome_idx + 1 >= _biome_latitude_ranges.size():
		biome_idx = 0
	var lat_rad := deg_to_rad(randf_range(_biome_latitude_ranges[biome_idx], _biome_latitude_ranges[biome_idx + 1]))
	var lon_rad := randf_range(-PI, PI)
	return Vector3(cos(lat_rad) * cos(lon_rad), sin(lat_rad), cos(lat_rad) * sin(lon_rad))


func _is_valid_latitude(lat: float) -> bool:
	for idx in _biomes:
		if idx + 1 >= _biome_latitude_ranges.size():
			continue
		if lat >= _biome_latitude_ranges[idx] and lat <= _biome_latitude_ranges[idx + 1]:
			return true
	return false


func _get_player_pos() -> Vector3:
	if not _players.is_empty() and is_instance_valid(_players[0]):
		return _players[0].global_position
	return Vector3.ZERO


func _perp(v: Vector3) -> Vector3:
	var p := v.cross(Vector3.UP)
	if p.length_squared() < 0.001:
		p = v.cross(Vector3.RIGHT)
	return p.normalized()
