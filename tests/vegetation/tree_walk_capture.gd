extends "res://tests/lighting/lighting_capture.gd"

## Paseo por el bosque del juego real con el juego en PLAYING (el origen flotante rebasa el
## mundo como en una partida). Guarda fotogramas a intervalos fijos en build/tree_walk/:
## los relevos de LOD, los impostores y lo que aparece o desaparece se ven comparando
## fotogramas seguidos.
##   godot --path . res://tests/vegetation/tree_walk_capture.tscn -- --tag=x [--runs=walk,fly]

const WALK_DIR := Vector3(0.635139, 0.469472, -0.613347)
const OUT := "res://build/tree_walk"
## nombre: [velocidad m/s, duración s, altura sobre el suelo m, cabeceo grados, rumbo grados]
const RUNS := {
	"walk": [6.0, 24.0, 1.7, -2.0, 0.0],
	"run_side": [9.0, 16.0, 1.7, 0.0, 90.0],
	"fly": [22.0, 18.0, 30.0, -14.0, 180.0],
	"walk_in": [6.0, 24.0, 1.7, -2.0, 180.0],
}
const CAPTURE_EVERY := 0.5

var _rebases := 0
## Seguimiento de cuerpos de árbol: posiciones que salen y entran en cada fotograma.
var _exited_positions: Array[Vector3] = []
var _frame_events := {"exit": 0, "enter": 0, "same": 0, "moved": 0}
var _events_log: Array[String] = []
var _last_body_pos := {}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var only: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			only = arg.substr(7).split(",")
	var view := {"dir": WALK_DIR, "yaw": 0.0, "pitch": -2.0}
	_set_sun_elevation(view, TIMES["afternoon"], false)
	await _place(view)
	await _wait_streaming(90.0)
	var origin: Node = _main.get_node_or_null("FloatingOrigin")
	if origin != null:
		origin.debug_log = true
	GameManager._change_state(GameManager.State.PLAYING)
	var instancer: Node = (_earth.get("planet") as Planet).voxel_instancer
	instancer.child_exiting_tree.connect(_on_body_exit)
	instancer.child_entered_tree.connect(func(n): _on_body_enter.call_deferred(n))
	await _settle(1.0)
	if "--look" in OS.get_cmdline_user_args():
		await _look_around()
		return
	for run_name in RUNS:
		if not only.is_empty() and run_name not in only:
			continue
		await _walk(run_name, RUNS[run_name])


func _walk(run_name: String, cfg: Array) -> void:
	var speed: float = cfg[0]
	var duration: float = cfg[1]
	var height: float = cfg[2]
	var pitch := deg_to_rad(cfg[3])
	var yaw := deg_to_rad(cfg[4])
	var start_up := WALK_DIR.normalized()
	var frame := _local_frame(start_up)
	var heading := (-frame.z * cos(yaw) + frame.x * sin(yaw)).normalized()
	var axis := start_up.cross(heading).normalized()
	var radius: float = _earth.get("radius") if _earth.get("radius") != null else 30000.0
	var travelled := 0.0
	var elapsed := 0.0
	var next_capture := 0.0
	var index := 0
	# Primer punto quieto para que el streaming alcance la posición.
	_move_camera(start_up, axis, 0.0, height, pitch, radius)
	await _settle(2.0)
	while elapsed < duration:
		var dt := get_process_delta_time()
		elapsed += dt
		travelled += speed * dt
		_move_camera(start_up, axis, travelled, height, pitch, radius)
		if elapsed >= next_capture:
			next_capture += CAPTURE_EVERY
			await RenderingServer.frame_post_draw
			var path := "%s/%s_%s_%03d.png" % [OUT, _tag, run_name, index]
			get_viewport().get_texture().get_image().save_png(path)
			print("DIAG %s %03d %s" % [run_name, index, _diagnose()])
			index += 1
		else:
			await get_tree().process_frame
		if _frame_events.exit + _frame_events.enter > 0:
			print("EVENTS %s t=%.2f exit=%d enter=%d same_pos=%d new_pos=%d" % [run_name, elapsed,
				_frame_events.exit, _frame_events.enter, _frame_events.same, _frame_events.moved])
		_frame_events = {"exit": 0, "enter": 0, "same": 0, "moved": 0}
		_exited_positions.clear()
	print("WALK %s frames=%d travelled=%.0f m" % [run_name, index, travelled])


func _move_camera(start_up: Vector3, axis: Vector3, travelled: float, height: float, pitch: float,
		radius: float) -> void:
	var center := _earth_center()
	var up := start_up.rotated(axis, travelled / radius).normalized()
	var ground := _ground_only_radius(center, up, radius)
	if _earth.world_map != null and _earth.world_map.is_ready():
		ground = maxf(ground, (_earth.world_map.map as WorldMapData).sea_level_radius)
	var pos := center + up * (ground + height)
	var forward := axis.cross(up).normalized()
	forward = (forward * cos(pitch) + up * sin(pitch)).normalized()
	_camera.global_transform = Transform3D(Basis.looking_at(forward, up), pos)
	_player.global_position = pos + up * 0.5
	_player.velocity = Vector3.ZERO


## Como _ground_radius pero solo contra el terreno: ni troncos (cuerpos del instancer) ni el
## jugador, que se coloca bajo la cámara y la iba subiendo en cada paso.
func _ground_only_radius(center: Vector3, up: Vector3, radius: float) -> float:
	var space := _camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(center + up * (radius * 1.15), center + up * (radius * 0.95))
	var exclude: Array[RID] = [(_player as CollisionObject3D).get_rid()]
	for attempt in 8:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return radius
		if hit.collider is VoxelInstancerRigidBody or hit.collider is CharacterBody3D:
			exclude.append(hit.rid)
			continue
		return (hit.position - center).length()
	return radius


## Compara los árboles del instancer (sus cuerpos) con la geometría que dibuja el detalle:
## faltan = árbol a menos de 88 m sin geometría; fantasmas = geometría sin cuerpo en su sitio o
## con otra escala. También el total de instancias del instancer.
func _diagnose() -> String:
	var planet: Planet = _earth.get("planet")
	var detail: TreeDetailRenderer = planet.tree_detail_renderer
	var eye := _camera.global_position
	var drawn: Array[Transform3D] = []
	for child in detail.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or not mmi.visible:
			continue
		for i in mmi.multimesh.instance_count:
			drawn.append(mmi.global_transform * mmi.multimesh.get_instance_transform(i))
	var bodies: Array[Transform3D] = []
	for child in planet.voxel_instancer.get_children():
		var body := child as VoxelInstancerRigidBody
		if body != null and detail.lod_meshes(body.get_library_item_id()).size() == 3:
			bodies.append(body.global_transform)
	var missing := 0
	var near_bodies := 0
	for xf in bodies:
		if xf.origin.distance_to(eye) > 88.0:
			continue
		near_bodies += 1
		var found := false
		for d in drawn:
			if d.origin.distance_to(xf.origin) < 0.05:
				found = true
				break
		if not found:
			missing += 1
	var ghosts := 0
	var wrong_scale := 0
	for d in drawn:
		var match_xf = null
		for xf in bodies:
			if d.origin.distance_to(xf.origin) < 0.05:
				match_xf = xf
				break
		if match_xf == null:
			ghosts += 1
			if ghosts <= 3:
				var best := INF
				var best_v := Vector3.ZERO
				for xf in bodies:
					var dd := d.origin.distance_to(xf.origin)
					if dd < best:
						best = dd
						best_v = xf.origin - d.origin
				print("   ghost at %.1f m from eye: nearest body %.3f m away, offset %s, drawn scale %.2f" % [
					d.origin.distance_to(eye), best, best_v, d.basis.get_scale().y])
		elif absf(d.basis.get_scale().y - (match_xf as Transform3D).basis.get_scale().y) > 0.01:
			wrong_scale += 1
	var total := 0
	var counts: Dictionary = planet.voxel_instancer.debug_get_instance_counts()
	for id in counts:
		total += int(counts[id])
	# Cuerpos que se han movido desde la captura anterior.
	var moved := 0
	var moved_sample := ""
	var now := {}
	for child in planet.voxel_instancer.get_children():
		var body := child as VoxelInstancerRigidBody
		if body == null:
			continue
		var id := body.get_instance_id()
		now[id] = body.global_position
		if _last_body_pos.has(id) and (_last_body_pos[id] as Vector3).distance_to(body.global_position) > 0.01:
			moved += 1
			if moved_sample == "":
				moved_sample = " sample_move=%.3f m freeze=%s mode=%s" % [
					(_last_body_pos[id] as Vector3).distance_to(body.global_position),
					str(body.get("freeze")), str(body.get("freeze_mode"))]
	_last_body_pos = now
	return ("moved=%d%s " % [moved, moved_sample]) + "near_bodies=%d missing=%d drawn=%d ghosts=%d wrong_scale=%d bodies=%d instances=%d" % [
		near_bodies, missing, drawn.size(), ghosts, wrong_scale, bodies.size(), total]


func _on_body_exit(node: Node) -> void:
	if node is VoxelInstancerRigidBody:
		_frame_events.exit += 1
		_exited_positions.append((node as Node3D).global_position)


func _on_body_enter(node: Node) -> void:
	if not (node is VoxelInstancerRigidBody) or not is_instance_valid(node):
		return
	_frame_events.enter += 1
	var p := (node as Node3D).global_position
	for q in _exited_positions:
		if q.distance_to(p) < 0.05:
			_frame_events.same += 1
			return
	_frame_events.moved += 1


## Cuatro rumbos quietos a ras de suelo en el punto de partida, y un informe de las setas de
## cueva cercanas: cuántas hay y cuántas tienen terreno encima (en una cueva).
func _look_around() -> void:
	var start_up := WALK_DIR.normalized()
	var frame := _local_frame(start_up)
	var radius: float = 30000.0
	for yaw_deg in [0.0, 90.0, 180.0, 270.0]:
		var yaw := deg_to_rad(yaw_deg)
		var heading := (-frame.z * cos(yaw) + frame.x * sin(yaw)).normalized()
		_move_camera(start_up, start_up.cross(heading).normalized(), 0.0, 1.7, deg_to_rad(-4.0), radius)
		await _settle(1.5)
		var path := "%s/%s_look_%03d.png" % [OUT, _tag, int(yaw_deg)]
		get_viewport().get_texture().get_image().save_png(path)
		print("CAPTURE ", path)
	var planet: Planet = _earth.get("planet")
	var eye := _camera.global_position
	var center := _earth_center()
	var space := _camera.get_world_3d().direct_space_state
	var total := 0
	var buried := 0
	var surface := 0
	for child in planet.voxel_instancer.get_children():
		if not (child is Node3D) or child is VoxelInstancerRigidBody:
			continue
		var n := child as Node3D
		if not str(n.scene_file_path).contains("mushroom"):
			continue
		if n.global_position.distance_to(eye) > 150.0:
			continue
		total += 1
		var up := (n.global_position - center).normalized()
		var q := PhysicsRayQueryParameters3D.create(n.global_position + up * 0.3, n.global_position + up * 200.0)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.collider is VoxelInstancerRigidBody or hit.collider is CharacterBody3D:
			surface += 1
			if surface <= 5:
				print("  surface mushroom at %.1f m, height over eye %.1f m" % [
					n.global_position.distance_to(eye), (n.global_position - eye).dot(up)])
		else:
			buried += 1
	print("MUSHROOMS near=%d buried=%d open_sky=%d" % [total, buried, surface])
