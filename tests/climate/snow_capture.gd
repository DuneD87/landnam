extends "res://tests/lighting/lighting_capture.gd"

## Capturas del bioma nevado en el juego real: busca en el mapa del planeta un sitio de cada zona
## del campo de frío (ClimateField) y lo fotografía a ras de suelo y desde algo más alto.
##   godot --path . res://tests/climate/snow_capture.tscn -- --spots=taiga,tundra --times=noon
## Guarda build/lighting/snow_<sitio>_<encuadre>_<hora>.png. --list solo imprime los sitios.
##
## --debug-snow pinta en el terreno la cobertura (R), la sujeción por pendiente (G) y la nieve (B).
## Sitios: taiga, treeline, tundra, icecap, alpine (cumbre templada), coast (costa con el mar
## helado), river (cauce estrecho helado), sea (banquisa cerrada), floes (borde de la banquisa, con
## témpanos sueltos).

const SPOT_NAMES := ["taiga", "treeline", "tundra", "icecap", "alpine", "coast", "river", "sea", "floes", "forest"]

var _spots: PackedStringArray = []
var _list_only := false


func _run() -> void:
	_tag = "snow"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spots="):
			_spots = arg.substr(8).split(",")
		elif arg == "--list":
			_list_only = true

	if not _weather.is_empty():
		await _force_weather()
	var t0 := Time.get_ticks_msec()
	while not (_earth.world_map != null and _earth.world_map.is_ready()):
		await get_tree().create_timer(0.5).timeout
		if Time.get_ticks_msec() - t0 > 180000:
			push_error("snow_capture: el mapa del planeta no llega")
			return
	var planet: Planet = _earth.get("planet")
	var found := _scout_spots(planet, _earth.world_map.map)
	# El bosque templado de referencia (la vista "forest" de lighting_capture).
	var forest_dir := Vector3(0.635139, 0.469472, -0.613347).normalized()
	found["forest"] = {"dir": forest_dir, "lat": 28.0, "lon": 0.0, "alt": 0.0,
		"cold": planet.climate.coldness(forest_dir * 30010.0), "yaw": 0.0}
	for spot in SPOT_NAMES:
		if not _spots.is_empty() and spot not in _spots:
			continue
		if not found.has(spot):
			print("SPOT %s: sin candidato" % spot)
			continue
		var info: Dictionary = found[spot]
		print("SPOT %s lat=%.1f lon=%.1f alt=%.0f frío=%.1f yaw=%.0f" % [spot, info.lat, info.lon,
			info.alt, info.cold, info.yaw])
		if _list_only:
			continue
		var shots := {
			"ground": {"dir": info.dir, "yaw": info.yaw, "pitch": -4.0, "height": 1.8},
			"high": {"dir": info.dir, "yaw": info.yaw, "pitch": -16.0, "height": 45.0},
		}
		if spot == "sea" or spot == "floes":
			# "sea" en la vista coloca la cámara sobre el nivel del mar y no sobre el fondo.
			shots = {
				"ground": {"dir": info.dir, "yaw": 0.0, "pitch": -6.0, "height": 2.0, "sea": true, "sea_ahead": 0.0},
				"high": {"dir": info.dir, "yaw": 0.0, "pitch": -20.0, "height": 40.0, "sea": true, "sea_ahead": 0.0},
			}
		for shot in shots:
			var view: Dictionary = shots[shot]
			_set_sun_elevation(view, TIMES["noon"], false)
			await _place(view)
			await _wait_streaming(90.0)
			if shot == "ground":
				var center := _earth_center()
				var ground := _ground_radius(center, info.dir, 30000.0)
				var local: Vector3 = info.dir * ground
				print("SPOT %s suelo real %.1f m sobre el mar, frío %.1f, hielo marino %.2f" % [spot,
					ground - _earth.world_map.map.sea_level_radius, planet.climate.coldness(local),
					planet.climate.sea_ice(info.dir * _earth.world_map.map.sea_level_radius, 0.0)])
				if "--fauna" in OS.get_cmdline_user_args():
					# La fauna aparece alrededor del jugador (el arnés lo deja bajo la cámara) y solo
					# con la partida en marcha.
					var game_manager := get_tree().root.get_node("GameManager")
					var previous_state = game_manager.current_state
					game_manager.current_state = game_manager.State.PLAYING
					await get_tree().create_timer(70.0).timeout
					var line := "FAUNA %s:" % spot
					for spawner in _earth.get_node("VoxelLodTerrain").get_children():
						if spawner is AmbientFaunaSpawner:
							var active := 0
							for animal in spawner.get("_pool"):
								if is_instance_valid(animal) and animal.active:
									active += 1
							if active > 0:
								line += " %s=%d" % [spawner.name, active]
					print(line)
					for spawner in _earth.get_node("VoxelLodTerrain").get_children():
						if spawner is AmbientFaunaSpawner and spawner.habitat is GroundFaunaHabitat:
							print("  %s %s" % [spawner.name, spawner.habitat.report()])
					game_manager.current_state = previous_state
				if "--counts" in OS.get_cmdline_user_args():
					await get_tree().create_timer(5.0).timeout
					var counts: Dictionary = planet.voxel_instancer.debug_get_instance_counts()
					for id in counts:
						var gen: VoxelInstanceGenerator = planet.voxel_instancer.library.get_item(id).generator
						if counts[id] > 0:
							print("COUNT id=%d lod=%d density=%.4f n=%d" % [id,
								planet.voxel_instancer.library.get_item(id).lod_index, gen.density, counts[id]])
				if "--probe" in OS.get_cmdline_user_args():
					var line := "PROBE %s:" % spot
					for step in range(0, 400, 25):
						var d := _step(info.dir, deg_to_rad(float(info.yaw)), float(step))
						var r := _ground_radius(center, d, 30000.0)
						line += " %d:%.1f%s" % [step, r - _earth.world_map.map.sea_level_radius,
							"w" if _earth.world_map.map.is_water_at_dir(d) else ""]
					print(line)
			if spot == "floes" and shot == "high":
				await _shoot_iceberg(spot)
			for time_name in (_only_times if not _only_times.is_empty() else PackedStringArray(["afternoon"])):
				_set_sun_elevation(view, TIMES[time_name], time_name in MORNING_TIMES)
				await _place(view)
				await _settle(2.5)
				if _perf:
					print("PERF %s_%s_%s gpu_ms=%.3f" % [spot, shot, time_name, await _measure_gpu()])
				await _save("%s_%s_%s" % [spot, shot, time_name])


## Iceberg más cercano (SeaIceFloes), visto desde el agua a unos 2,5 radios.
func _shoot_iceberg(spot: String) -> void:
	var floes: SeaIceFloes = _earth.get("sea_ice_floes")
	if floes == null:
		return
	await get_tree().create_timer(4.0).timeout
	var best: Dictionary = {}
	var cam_local := _camera.global_position - floes.global_position
	for c in floes._bergs:
		var berg: Dictionary = floes._bergs[c].berg
		if best.is_empty() or (berg.center as Vector3).distance_to(cam_local) < (best.center as Vector3).distance_to(cam_local):
			best = berg
	if best.is_empty():
		print("ICEBERG: ninguno a la vista")
		return
	var center: Vector3 = floes.global_position + best.center
	var up: Vector3 = (best.center as Vector3).normalized()
	var side := up.cross(Vector3.RIGHT).normalized()
	var pos := center + side * (float(best.radius) * 2.6) + up * (float(best.height) * 0.6 + 3.0)
	print("ICEBERG r=%.0f h=%.0f tipo %d a %.0f m" % [best.radius, best.height, best.kind,
		(best.center as Vector3).distance_to(cam_local)])
	_camera.global_transform = Transform3D(Basis.looking_at(center + up * best.height * 0.3 - pos, up), pos)
	var player_camera: Node3D = _player.get("camera")
	if player_camera != null:
		player_camera.global_position = pos
	_player.global_position = pos
	await _settle(8.0)
	await _save("%s_iceberg_noon" % spot)
	# Bajo el agua, para ver la parte sumergida.
	var below := center + side * (float(best.radius) * 2.2) - up * 6.0
	_camera.global_transform = Transform3D(Basis.looking_at(center - up * best.draft * 0.4 - below, up), below)
	if player_camera != null:
		player_camera.global_position = below
	_player.global_position = below
	await _settle(6.0)
	await _save("%s_iceberg_under_noon" % spot)


## Primer candidato de cada sitio recorriendo el mapa en una rejilla de 0,5 grados.
func _scout_spots(planet: Planet, map: WorldMapData) -> Dictionary:
	var climate := planet.climate
	var sea := map.sea_level_radius - map.radius
	var result := {}
	var lat := -82.0
	while lat <= 82.0:
		var lon := -180.0
		while lon < 180.0:
			var dir := WorldMapData.latlon_to_dir(lat, lon)
			var h := map.height_at_dir(dir)
			var alt := h - sea
			var cold := climate.coldness(dir * (map.radius + h))
			var land := not map.is_water_at_dir(dir)
			var relief := _relief(map, dir)
			var candidate := {"dir": dir, "lat": lat, "lon": lon, "alt": alt, "cold": cold, "yaw": 0.0}
			# Por encima de 15 m: el mapa es grueso y marca como tierra lagos y lagunas de la costa.
			if land and alt > 15.0 and relief < 30.0:
				if not result.has("taiga") and cold > 44.0 and cold < 49.0 and alt < 120.0:
					result["taiga"] = candidate
				elif not result.has("treeline") and cold > 51.5 and cold < 54.0 and alt < 200.0:
					result["treeline"] = candidate
				elif not result.has("tundra") and cold > 57.0 and cold < 63.0 and alt < 120.0:
					result["tundra"] = candidate
				elif not result.has("icecap") and cold > 72.0 and alt > 60.0:
					result["icecap"] = candidate
			if land and not result.has("alpine") and absf(lat) < 32.0 and alt > 330.0 and relief < 60.0:
				result["alpine"] = candidate
			if land and alt > 3.0 and alt < 20.0 and not result.has("coast") and absf(lat) < 72.0 \
					and climate.sea_ice(dir * map.sea_level_radius, 0.0) > 0.99:
				var yaw := _water_yaw(map, dir, 250.0)
				if yaw >= 0.0 and climate.sea_ice(dir * map.sea_level_radius, 400.0) > 0.95:
					candidate["yaw"] = rad_to_deg(yaw)
					result["coast"] = candidate
			# Mar helado: agua honda (sin orilla cerca) con la banquisa cerrada.
			if not land and not result.has("sea") and map.depth_at_dir(dir) > 40.0 \
					and climate.sea_ice(dir * map.sea_level_radius, -1.0) > 0.99 and absf(lat) < 75.0:
				var frozen := candidate.duplicate()
				frozen["alt"] = 0.0
				result["sea"] = frozen
			# Borde de la banquisa: témpanos sueltos con agua entre ellos.
			if not land and not result.has("floes") and map.depth_at_dir(dir) > 40.0 \
					and absf(climate.sea_ice(dir * map.sea_level_radius, -1.0) - 0.5) < 0.15:
				var edge := candidate.duplicate()
				edge["alt"] = 0.0
				result["floes"] = edge
			if not land and not result.has("river") and absf(lat) > 44.0 and absf(lat) < 54.0:
				# Cauce: agua con tierra a menos de 60 m por los dos lados.
				if _narrow_water(map, dir):
					var back := _step(dir, 0.0, -70.0)
					if not map.is_water_at_dir(back):
						var river := candidate.duplicate()
						river["dir"] = back
						river["yaw"] = 0.0
						river["alt"] = map.height_at_dir(back) - sea
						result["river"] = river
			lon += 0.5
		lat += 0.5
	return result


## Desnivel (m) entre el punto y sus vecinos a 60 m.
func _relief(map: WorldMapData, dir: Vector3) -> float:
	var h := map.height_at_dir(dir)
	var worst := 0.0
	for k in 4:
		var a := TAU * k / 4.0
		worst = maxf(worst, absf(map.height_at_dir(_step(dir, a, 60.0)) - h))
	return worst


## Punto a `dist` metros de `dir` con rumbo `azimuth` (radianes desde el norte).
func _step(dir: Vector3, azimuth: float, dist: float) -> Vector3:
	var frame := _local_frame(dir)
	var heading := -frame.z * cos(azimuth) + frame.x * sin(azimuth)
	return (dir * 30000.0 + heading * dist).normalized()


func _water_yaw(map: WorldMapData, dir: Vector3, dist: float) -> float:
	for k in 16:
		var a := TAU * k / 16.0
		if map.is_water_at_dir(_step(dir, a, dist)):
			return a
	return -1.0


func _narrow_water(map: WorldMapData, dir: Vector3) -> bool:
	var sides := 0
	for k in 8:
		if not map.is_water_at_dir(_step(dir, TAU * k / 8.0, 60.0)):
			sides += 1
	return sides >= 4
