extends SceneTree

## Los cauces de río en el mapa mundial: se tallan bajo el nivel del mar y los llena la esfera del
## océano, así que el mapa grueso los veía como agua unida al mar y los daba por océano (olas de
## orilla contra las riberas, temporal en los tramos hondos). Mapa sintético: medio planeta de mar,
## un cauce hondo que entra tierra adentro por el ecuador y una charca natural aparte.
##   godot --headless --path . -s res://tests/world/test_world_map_rivers.gd

const W := 256
const H := 128
const RADIUS := 3000.0
const HEIGHT_MIN := -100.0
const HEIGHT_SPAN := 200.0
const COAST_X := 128
const RIVER_ROW := 64
const RIVER_END_X := 200
## Igual que PlanetWorldMap.SHORE_RANGE. No se lee de ahí: esa clase arrastra la escena del planeta y
## en modo -s no compila.
const SHORE_RANGE := 300.0

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func _norm(height: float) -> float:
	return (height - HEIGHT_MIN) / HEIGHT_SPAN


func _map() -> WorldMapData:
	var map := WorldMapData.new()
	map.size = Vector2i(W, H)
	map.radius = RADIUS
	map.sea_level_radius = RADIUS
	map.has_water = true
	map.height_min = HEIGHT_MIN
	map.height_span = HEIGHT_SPAN
	map.heights.resize(W * H)
	for y in H:
		for x in W:
			map.heights[y * W + x] = _norm(-50.0 if x < COAST_X else 20.0)
	# El cauce, 80 m bajo el mar: sin separar, el temporal lo alcanzaría (empieza a 30 m).
	for x in range(COAST_X, RIVER_END_X + 1):
		map.heights[RIVER_ROW * W + x] = _norm(-80.0)
	# Charca natural de un téxel, lejos del río.
	map.heights[30 * W + 200] = _norm(-5.0)
	return map


## El eje del cauce por el centro de su fila, desde mar adentro (la prolongación de la desembocadura)
## hasta su cabecera, en tramos de un téxel como la red de verdad: un tramo largo es una cuerda que
## pasa bajo la superficie. Misma convención y resolución que el mapa.
func _rivers() -> Dictionary:
	var y := RIVER_ROW + 0.5
	var seg := PackedFloat32Array()
	for x in range(COAST_X - 8, RIVER_END_X):
		seg.append_array([x + 0.5, y, x + 1.5, y, -80.0, -80.0, 10.0, 10.0])
	return {
		"seg": seg,
		"hydro_size": Vector2i(W, H),
		"carve_range": 50.0,
		"radius": RADIUS,
	}


func _dir(x: int, y: int) -> Vector3:
	return WorldMapData.uv_to_dir(Vector2((x + 0.5) / W, (y + 0.5) / H))


func _type_at(map: WorldMapData, x: int, y: int) -> int:
	var body := map.water_body_at_dir(_dir(x, y))
	return int(body.type) if not body.is_empty() else -1


func _run() -> void:
	var rivers := _rivers()
	var upstream := _dir(170, RIVER_ROW)

	var old := _map()
	WorldMapBaker.classify_water(old)
	check(_type_at(old, 170, RIVER_ROW) == WorldMapData.WaterType.OCEAN,
		"Sin la red de ríos el cauce sale como océano (el fallo que se corrige)")

	var map := _map()
	WorldMapBaker.classify_water(map, rivers)
	WorldMapBaker.bake_shore_field(map, WorldMapBaker.open_water_ids(map), SHORE_RANGE)
	check(_type_at(map, 170, RIVER_ROW) == WorldMapData.WaterType.RIVER,
		"Con la red, el cauce tierra adentro es río")
	check(map.is_water_at_dir(upstream), "El río sigue siendo agua para quien no mira el tipo")
	check(_type_at(map, 100, 20) == WorldMapData.WaterType.OCEAN, "El mar natural sigue siendo océano")
	check(_type_at(map, COAST_X - 4, RIVER_ROW) == WorldMapData.WaterType.OCEAN,
		"El mar que rodea la prolongación de la desembocadura vuelve al océano")
	check(_type_at(map, COAST_X, RIVER_ROW) == WorldMapData.WaterType.OCEAN,
		"La boca del río (estuario) sigue siendo del mar")
	check(_type_at(map, 200, 30) == _type_at(old, 200, 30)
		and _type_at(map, 200, 30) != WorldMapData.WaterType.RIVER, "Una charca natural no se toca")
	check(_type_at(map, 170, 20) == -1, "La tierra sigue siendo tierra")

	var first := map.river_first_id()
	var ordered := first < map.bodies.size()
	for body in map.bodies:
		ordered = ordered and ((int(body.id) >= first) == (int(body.type) == WorldMapData.WaterType.RIVER))
	check(ordered, "Los ríos van numerados detrás de todos los demás cuerpos (el shader solo mira el id)")
	check(not WorldMapData.body_name(map.bodies[first]).contains(str(map.bodies[first].number)),
		"El nombre de un río no lleva número")

	var flags := PackedByteArray()
	flags.resize(map.bodies.size())
	for id in WorldMapBaker.open_water_ids(map):
		flags[id] = 1
	check(map.storm_exposure_at_dir(upstream, flags, 30.0, 150.0) == 0.0,
		"Un río hondo no recibe temporal")
	check(map.is_river_at_dir(upstream) and map.shore_waves_allowed_at_dir(upstream, flags),
		"Un río no veta la costera: la decide el campo de orilla")
	check(absf(map.shore_sample_at_dir(upstream).w) >= SHORE_RANGE * 0.99,
		"Tierra adentro el campo de orilla no ve costa en las riberas del río")
	var coast := absf(map.shore_sample_at_dir(_dir(COAST_X - 2, 20)).w)
	check(coast > 1.0 and coast < SHORE_RANGE, "La costa de verdad sí tiene olas de orilla")

	print("WORLD MAP RIVERS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
