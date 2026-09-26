extends Node

## Capturas reproducibles de la iluminación sobre la escena real (sun.tscn): mismo punto de
## vista, mismas horas. Coloca una cámara propia con VoxelViewer sobre el planeta, fija el sol a
## una elevación LOCAL concreta y guarda build/lighting/<tag>_<vista>_<hora>.png. Con SkyLighting
## en la escena imprime además su estado resuelto (luces, cielo, exposición) en cada captura.
##
##   godot --path . res://tests/lighting/lighting_capture.tscn -- --tag=before
##   ... -- --tag=after --views=shore,space --times=noon,midnight --perf
##
## --explore  recorre los cuatro rumbos de cada vista a mediodía para elegir encuadres.
## --scout    lista orillas bajas del mapa del planeta con la luna a media altura.
## --perf     mide el tiempo medio de GPU del frame antes de cada captura.
## --ssao / --no-ssao  fuerza la oclusión ambiental de pantalla para compararla.
## --no-clouds  apaga las nubes del compute (para aislar lo que es terreno). Se reaplica cada
##            frame: el WeatherController las vuelve a encender al aplicar el clima.
## --debug-draw=N  Viewport.DebugDraw (p. ej. 2 = solo iluminación).
## --atmo=prop:valor,...  cambia propiedades del PlanetAtmosphere (p. ej. mie_strength:0) para A/B.
## --weather=NOMBRE  fija el clima (clear, wind, storm...). Sin él lo elige el azar y con él el
##            oleaje: dos tandas de capturas del mar no serían comparables.

const MAIN_SCENE := "res://scenes/maps/sun.tscn"
const OUT_DIR := "res://build/lighting"
const EYE_HEIGHT := 1.8

## Horas como elevación del sol sobre el horizonte LOCAL (grados). "am" = sol subiendo.
const TIMES := {
	"noon": 58.0,
	"afternoon": 24.0,
	"golden": 7.0,
	"sunset": 0.5,
	"civil": -3.5,
	"nautical": -9.0,
	"night": -35.0,
	"dawn": -5.0,
}
const MORNING_TIMES := ["dawn"]
## Horas definidas por el azimut del sol respecto al del lugar en vez de por elevación.
## "midnight" = sol en su punto más bajo; con la luna fija en -Z es cuando más llena se ve
## desde este hemisferio.
const AZIMUTH_TIMES := {"midnight": 180.0}

## Vistas: dirección radial desde el centro de la Tierra (se normaliza), rumbo (grados desde el
## norte local hacia el este), cabeceo, y altura sobre el suelo. `look` = "sun"/"moon"/"sea"
## orienta el rumbo hacia ese astro o hacia el agua más cercana (el rumbo pasa a ser un offset);
## `shore` avanza hasta la orilla y se queda `shore_back` metros antes.
var VIEWS := {
	"forest": {"dir": Vector3(0.635139, 0.469472, -0.613347), "yaw": 0.0, "pitch": -2.0},
	"forest_moon": {"dir": Vector3(0.635139, 0.469472, -0.613347), "look": "moon", "pitch": 14.0},
	# El mismo bosque desde 60 m: copas medias y lejanas (relevo de bandas e impostores).
	"forest_high": {"dir": Vector3(0.635139, 0.469472, -0.613347), "yaw": 0.0, "pitch": -12.0, "height": 60.0},
	"dunes": {"dir": Vector3(0.708411, 0.173648, -0.684105), "yaw": 180.0, "pitch": 0.0},
	"dunes_sun": {"dir": Vector3(0.708411, 0.173648, -0.684105), "look": "sun", "pitch": 3.0},
	# El mismo sitio girado: el sol bajo queda escondido detrás de la colina de la izquierda (el aire
	# de delante está a su sombra y no debe brillar).
	"dunes_sun_hidden": {"dir": Vector3(0.708411, 0.173648, -0.684105), "look": "sun", "yaw": 35.0, "pitch": 3.0},
	# Desde alto, mirando al sol sobre crestas escalonadas (bruma entre capas de relieve).
	"ridges_sun": {"dir": Vector3(0.708411, 0.173648, -0.684105), "look": "sun", "yaw": 35.0, "pitch": -6.0, "height": 120.0},
	"space": {"dir": Vector3(0.62, 0.30, -0.72), "space": true},
	"shore": {"dir": Vector3(0.623694, 0.241922, -0.74329), "look": "sea", "shore": true, "shore_back": 25.0, "yaw": 40.0, "pitch": -4.0, "height": 2.5},
	# Cara de la luna que mira a la tierra, con la tierra en el encuadre.
	"moon_surface": {"body": "moon", "dir": Vector3(0.35, 0.25, 0.9), "look": "earth", "pitch": 12.0, "height": 2.0},
	# Desde el agua, `sea_ahead` metros mar adentro de la orilla de "shore": la estela del sol y la
	# de la luna sobre las olas.
	"sea_sun": {"dir": Vector3(0.623694, 0.241922, -0.74329), "sea": true, "sea_ahead": 160.0, "look": "sun", "pitch": 1.0, "height": 2.5},
	"sea_moon": {"dir": Vector3(0.623694, 0.241922, -0.74329), "sea": true, "sea_ahead": 160.0, "look": "moon", "pitch": 12.0, "height": 2.5},
	# La luna está a ~38° sobre ese mar: su reflejo cae por debajo del encuadre de sea_moon.
	"sea_moon_glint": {"dir": Vector3(0.623694, 0.241922, -0.74329), "sea": true, "sea_ahead": 160.0, "look": "moon", "pitch": -12.0, "height": 2.5},
}

var _tag := "after"
var _explore := false
## --perf: antes de cada captura mide el tiempo medio de GPU del frame (ms) sobre PERF_FRAMES.
var _perf := false
const PERF_FRAMES := 120
## --ssao / --no-ssao: fuerza la oclusión ambiental de pantalla del entorno para compararla.
var _ssao := false
var _ssao_forced := false
var _only_views: PackedStringArray = []
var _only_times: PackedStringArray = []
var _weather := ""
var _no_clouds_effect: Object
var _main: Node
var _sun_ctrl: Node
var _earth: Node
var _moon: Node
var _camera: Camera3D
var _player: Node3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.substr(6)
		elif arg == "--explore":
			_explore = true
		elif arg == "--perf":
			_perf = true
		elif arg == "--ssao":
			_ssao = true
		elif arg == "--no-ssao":
			_ssao = false
			_ssao_forced = true
		elif arg.begins_with("--views="):
			_only_views = arg.substr(8).split(",")
		elif arg.begins_with("--times="):
			_only_times = arg.substr(8).split(",")
		elif arg.begins_with("--weather="):
			_weather = arg.substr(10)
	get_window().size = Vector2i(1920, 1080)
	_main = load(MAIN_SCENE).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = _main
	_main.get_node("MainMenu").visible = false
	_hide_hud(_main)
	var sky_lighting := _main.get_node_or_null("SkyLighting")
	if sky_lighting != null:
		sky_lighting.set("collect_debug_state", true)
	if _ssao or _ssao_forced:
		var env: Environment = (_main.get_node("WorldEnvironment") as WorldEnvironment).environment
		env.ssao_enabled = _ssao
	_sun_ctrl = _main
	_sun_ctrl.auto_rotate = false
	_earth = _main.get_node("Planets/Earth")
	_moon = _main.get_node("Planets/Moon")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--debug-draw="):
			get_viewport().debug_draw = int(arg.substr(13)) as Viewport.DebugDraw
	if "--no-clouds" in OS.get_cmdline_user_args():
		var ctrl := _earth.get_node_or_null("PlanetAtmosphereController")
		if ctrl != null and ctrl.get("effect") != null:
			_no_clouds_effect = ctrl.effect
			# Después del WeatherController, que las enciende en su _process.
			process_priority = 1000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--atmo="):
			var effect: Object = _earth.get_node("PlanetAtmosphereController").get("effect")
			for pair in arg.substr(7).split(","):
				var kv := pair.split(":")
				effect.set(kv[0], str_to_var(kv[1]))
	_player = _main.get_node("Player")

	_camera = Camera3D.new()
	_camera.near = 0.05
	_camera.far = 100000.0
	_camera.fov = 70.0
	_main.add_child(_camera)
	var viewer := VoxelViewer.new()
	viewer.view_distance = 300000
	viewer.view_distance_vertical_ratio = 5.0
	_camera.add_child(viewer)
	_camera.current = true
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	if "--scout" in OS.get_cmdline_user_args():
		await _scout()
	else:
		await _run()
	print("LIGHTING CAPTURE COMPLETE")
	get_tree().quit()


func _process(_delta: float) -> void:
	if _no_clouds_effect != null:
		_no_clouds_effect.set(&"clouds_enabled", false)


## Busca en el mapa del planeta orillas templadas con la luna a media altura y lista las mejores.
func _scout() -> void:
	var t0 := Time.get_ticks_msec()
	while not (_earth.world_map != null and _earth.world_map.is_ready()):
		await get_tree().create_timer(0.5).timeout
		if Time.get_ticks_msec() - t0 > 120000:
			push_error("world map no listo")
			return
	var map: WorldMapData = _earth.world_map.map
	var center := _earth_center()
	var moon := _moon_center()
	var found := 0
	for lat in range(-40, 41, 2):
		for lon in range(-180, 180, 2):
			var d := WorldMapData.latlon_to_dir(lat, lon)
			var alt := map.surface_radius_at_dir(d) - map.sea_level_radius
			if alt < 3.0 or alt > 14.0:
				continue
			var pos := center + d * map.surface_radius_at_dir(d)
			var moon_el := rad_to_deg(asin(d.dot((moon - pos).normalized())))
			if moon_el < 12.0 or moon_el > 40.0:
				continue
			# Agua a ~600-1500 m en algún rumbo: orilla con mar a la vista.
			var frame := _local_frame(d)
			var sea_dirs := 0
			for k in 8:
				var a := TAU * k / 8.0
				var step := (frame.x * cos(a) - frame.z * sin(a))
				var probe := (d * 30000.0 + step * 160.0).normalized()
				if map.is_water_at_dir(probe):
					sea_dirs += 1
			if sea_dirs < 2 or sea_dirs > 4:
				continue
			# Tierra de verdad detrás: el lado opuesto al agua sube.
			var inland := 0
			for k in 8:
				var a2 := TAU * k / 8.0
				var step2 := (frame.x * cos(a2) - frame.z * sin(a2))
				var probe2 := (d * 30000.0 + step2 * 400.0).normalized()
				if map.surface_radius_at_dir(probe2) - map.sea_level_radius > alt + 6.0:
					inland += 1
			if inland < 1:
				continue
			print("SCOUT lat=%d lon=%d alt=%.0f moon_el=%.0f sea_dirs=%d dir=%s" % [lat, lon, alt, moon_el, sea_dirs, str(d)])
			found += 1
	print("SCOUT found ", found)


func _run() -> void:
	if not _weather.is_empty():
		await _force_weather()
	for view_name in VIEWS:
		if not _only_views.is_empty() and view_name not in _only_views:
			continue
		var view: Dictionary = VIEWS[view_name]
		_set_sun_elevation(view, TIMES["noon"], false)
		await _place(view)
		await _wait_streaming(90.0)
		await _place(view)
		if _explore and not view.get("space", false):
			for yaw in [0.0, 90.0, 180.0, 270.0]:
				var v := view.duplicate()
				v["yaw"] = yaw
				await _place(v)
				await _settle(1.0)
				await _save("%s_explore_%03d" % [view_name, int(yaw)])
			continue
		var names: Array = TIMES.keys() + AZIMUTH_TIMES.keys()
		for time_name in names:
			if not _only_times.is_empty() and time_name not in _only_times:
				continue
			if AZIMUTH_TIMES.has(time_name):
				_set_sun_azimuth_offset(view, AZIMUTH_TIMES[time_name])
			else:
				_set_sun_elevation(view, TIMES[time_name], time_name in MORNING_TIMES)
			await _place(view)
			await _settle(2.5)
			if _perf:
				var gpu := await _measure_gpu()
				# Coste de la vegetación del planeta (árboles, hierba, rocas): el mismo fotograma
				# con su instancer oculto.
				var veg_ms := -1.0
				var instancer: Node3D = _vegetation_instancer(view)
				var detail: Node3D = _tree_detail(view)
				if instancer != null:
					# Tres ciclos alternos con mediana: una sola pareja variaba ±1 ms.
					var diffs: Array[float] = []
					for cycle in 3:
						var on := await _median_gpu()
						instancer.visible = false
						if detail != null:
							detail.visible = false
						await _settle(0.3)
						var off := await _median_gpu()
						instancer.visible = true
						if detail != null:
							detail.visible = true
						await _settle(0.3)
						diffs.append(on - off)
					diffs.sort()
					veg_ms = diffs[1]
				var sweep_ms := -1.0
				var detail_node := _tree_detail(view)
				if detail_node != null:
					sweep_ms = (detail_node as TreeDetailRenderer).last_sweep_usec / 1000.0
				print("PERF %s_%s gpu_ms=%.3f vegetation_ms=%.3f tree_sweep_cpu_ms=%.2f" % [
					view_name, time_name, gpu, veg_ms, sweep_ms])
			await _save("%s_%s" % [view_name, time_name])
			_print_state("%s_%s" % [view_name, time_name])


## Fija el clima y espera a que termine la transición (el oleaje sale de él).
func _force_weather() -> void:
	var t0 := Time.get_ticks_msec()
	var ctrl: Node = null
	while Time.get_ticks_msec() - t0 < 60000:
		ctrl = _earth.get("weather_controller") as Node
		if ctrl != null and ctrl.get("_ready_to_run"):
			break
		await get_tree().create_timer(0.5).timeout
	if ctrl == null:
		push_warning("lighting_capture: sin WeatherController, clima sin fijar")
		return
	ctrl.call(&"force_weather", _weather)
	await get_tree().create_timer(float(ctrl.get("transition_time")) + 0.5).timeout


## Fuera HUD, hotbar y overlay de estadísticas: solo interesa la imagen 3D.
func _hide_hud(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasLayer:
			child.visible = false
		elif child is Control and child.get_parent() is Node3D:
			child.visible = false
		_hide_hud(child)


func _earth_center() -> Vector3:
	return (_earth.get_node("VoxelLodTerrain") as Node3D).global_position


func _moon_center() -> Vector3:
	return (_moon.get_node("VoxelLodTerrain") as Node3D).global_position


func _up_of(view: Dictionary) -> Vector3:
	return (view["dir"] as Vector3).normalized()


## Marco tangente local: norte = eje Y del mundo proyectado sobre el plano tangente.
func _local_frame(up: Vector3) -> Basis:
	var north := (Vector3.UP - up * up.dot(Vector3.UP))
	if north.length_squared() < 1e-6:
		north = Vector3.FORWARD
	north = north.normalized()
	var east := north.cross(up).normalized()
	return Basis(east, up, -north)


## Azimut del sol (rotación en torno a Y del sun_controller, elevación global 0) que deja el sol a
## `elevation_deg` sobre el horizonte local. De tarde por defecto (el sol baja al girar).
func _set_sun_elevation(view: Dictionary, elevation_deg: float, morning: bool) -> void:
	var up := _up_of(view)
	var r := Vector2(up.x, up.z).length()
	var az0 := atan2(up.x, up.z)
	var c := clampf(sin(deg_to_rad(elevation_deg)) / maxf(r, 0.0001), -1.0, 1.0)
	var az := az0 - acos(c) if morning else az0 + acos(c)
	_sun_ctrl.sun_elevation_deg = 0.0
	_sun_ctrl.sun_azimuth_deg = wrapf(rad_to_deg(az), -180.0, 180.0)
	_sun_ctrl._update_sun()


func _vegetation_instancer(view: Dictionary) -> Node3D:
	var body: Node = _moon if view.get("body", "earth") == "moon" else _earth
	var planet = body.get("planet")
	return (planet as Planet).voxel_instancer if planet is Planet else null


func _tree_detail(view: Dictionary) -> Node3D:
	var body: Node = _moon if view.get("body", "earth") == "moon" else _earth
	var planet = body.get("planet")
	return (planet as Planet).tree_detail_renderer if planet is Planet else null


func _median_gpu() -> float:
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for i in 10:
		await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	for i in PERF_FRAMES:
		await RenderingServer.frame_post_draw
		samples.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	samples.sort()
	return samples[samples.size() / 2]


func _measure_gpu() -> float:
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for i in 10:
		await RenderingServer.frame_post_draw
	var total := 0.0
	for i in PERF_FRAMES:
		await RenderingServer.frame_post_draw
		total += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return total / PERF_FRAMES


func _set_sun_azimuth_offset(view: Dictionary, offset_deg: float) -> void:
	var up := _up_of(view)
	_sun_ctrl.sun_elevation_deg = 0.0
	_sun_ctrl.sun_azimuth_deg = wrapf(rad_to_deg(atan2(up.x, up.z)) + offset_deg, -180.0, 180.0)
	_sun_ctrl._update_sun()


func _print_state(label: String) -> void:
	var sky := _main.get_node_or_null("SkyLighting")
	if sky == null or sky.get("debug_state") == null:
		return
	var st: Dictionary = sky.debug_state
	if st.is_empty():
		return
	var f := func(v: Vector3) -> String: return "(%.3f %.3f %.3f)" % [v.x, v.y, v.z]
	print("STATE %s sun_elev=%.1f sun=%s moon_elev=%.1f moon_raw=%.3f moon=%s amb_up=%s ground=%s exp=%.2f cost_us=%d" % [
		label, st.sun_elev, f.call(st.sun_rgb), st.moon_elev, st.moon_raw, f.call(st.moon_rgb),
		f.call(st.ambient_up), f.call(st.ground), st.exposure, int(st.get("cost_usec", -1))])
	var raw: Array = st.sky_raw
	var amb: Array = st.ambient
	var refl: Array = st.reflected
	print("      reflect zen%s horS%s horA%s" % [f.call(refl[0]), f.call(refl[3]), f.call(refl[5])])
	var names := ["zen", "midS", "midA", "horS", "horSide", "horA"]
	var line := "      "
	for i in raw.size():
		line += "%s raw%s amb%s  " % [names[i], f.call(raw[i]), f.call(amb[i])]
	print(line)


func _body_center(view: Dictionary) -> Vector3:
	return _moon_center() if view.get("body", "earth") == "moon" else _earth_center()


func _body_radius(view: Dictionary) -> float:
	return 6000.0 if view.get("body", "earth") == "moon" else 30000.0


func _place(view: Dictionary) -> void:
	var center := _body_center(view)
	var up := _up_of(view)
	if view.get("space", false):
		var pos := center + up * 95000.0
		_camera.global_transform = Transform3D(Basis.looking_at(center - pos, Vector3.UP), pos)
		_player.global_position = pos
		return
	var frame := _local_frame(up)
	if view.get("shore", false):
		# Avanza por el rumbo del agua hasta la orilla y se queda unos metros antes, en tierra.
		up = _shore_point(up, frame, float(view.get("shore_back", 12.0)))
		frame = _local_frame(up)
	elif view.get("sea", false):
		up = _shore_point(up, frame, -float(view.get("sea_ahead", 100.0)))
		frame = _local_frame(up)
	var ground := _ground_radius(center, up, _body_radius(view))
	if view.get("sea", false) and _earth.world_map != null and _earth.world_map.is_ready():
		ground = maxf(ground, (_earth.world_map.map as WorldMapData).sea_level_radius)
	var pos := center + up * (ground + float(view.get("height", EYE_HEIGHT)))
	var yaw := deg_to_rad(float(view.get("yaw", 0.0)))
	var look: String = view.get("look", "")
	var north := -frame.z
	var east := frame.x
	if look == "sea":
		yaw += _sea_azimuth(up, frame)
	elif look != "":
		var target := _sun_dir()
		if look == "moon":
			target = (_moon_center() - pos).normalized()
		elif look == "earth":
			target = (_earth_center() - pos).normalized()
		var flat := target - up * target.dot(up)
		if flat.length_squared() > 1e-6:
			flat = flat.normalized()
			yaw += atan2(flat.dot(east), flat.dot(north))
	var forward := north * cos(yaw) + east * sin(yaw)
	var pitch := deg_to_rad(float(view.get("pitch", 0.0)))
	forward = (forward * cos(pitch) + up * sin(pitch)).normalized()
	_camera.global_transform = Transform3D(Basis.looking_at(forward, up), pos)
	_player.global_position = pos + up * 0.5


## Dirección radial de un punto de tierra a `back` metros de la orilla, siguiendo el rumbo del agua.
func _shore_point(up: Vector3, frame: Basis, back: float) -> Vector3:
	var map: WorldMapData = _earth.world_map.map if _earth.world_map != null and _earth.world_map.is_ready() else null
	if map == null:
		return up
	var a := _sea_azimuth(up, frame)
	var dir := -frame.z * cos(a) + frame.x * sin(a)
	var d := 0.0
	while d < 800.0:
		var probe := (up * 30000.0 + dir * d).normalized()
		if map.is_water_at_dir(probe):
			return (up * 30000.0 + dir * maxf(d - back, 0.0)).normalized()
		d += 4.0
	return up


## Rumbo (radianes desde el norte local) hacia el agua más cercana según el mapa del planeta.
func _sea_azimuth(up: Vector3, frame: Basis) -> float:
	if _earth.world_map == null or not _earth.world_map.is_ready():
		return 0.0
	var map: WorldMapData = _earth.world_map.map
	var north := -frame.z
	var east := frame.x
	for dist in [60.0, 120.0, 200.0, 320.0, 500.0]:
		for k in 32:
			var a := TAU * k / 32.0
			var probe: Vector3 = (up * 30000.0 + (north * cos(a) + east * sin(a)) * float(dist)).normalized()
			if map.is_water_at_dir(probe):
				return a
	return 0.0


func _sun_dir() -> Vector3:
	return (_main.get_node("DirectionalLight3D") as Node3D).global_transform.basis.z.normalized()


## Radio del suelo bajo la vista: rayo físico contra la colisión del terreno; si aún no la hay,
## se queda en el radio de la dirección original de la vista.
func _ground_radius(center: Vector3, up: Vector3, radius: float) -> float:
	var from := center + up * (radius * 1.15)
	var to := center + up * (radius * 0.95)
	var space := _camera.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return radius
	return (hit.position - center).length()


func _wait_streaming(max_seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	var quiet := 0
	await _settle(3.0)
	while (Time.get_ticks_msec() - t0) / 1000.0 < max_seconds:
		await get_tree().create_timer(0.5).timeout
		var pending := _pending_tasks()
		quiet = quiet + 1 if pending == 0 else 0
		if quiet >= 6:
			break
	print("streaming settled after %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))


func _pending_tasks() -> int:
	var stats: Dictionary = VoxelEngine.get_stats()
	var total := 0
	var tasks: Dictionary = stats.get("tasks", {})
	for key in tasks:
		total += int(tasks[key])
	return total


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := "%s/%s_%s.png" % [OUT_DIR, _tag, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path)
