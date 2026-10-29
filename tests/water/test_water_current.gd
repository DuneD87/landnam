extends SceneTree

## Corriente por tipo de agua: entera en mar abierto, menguante hacia la costa, poca en los ríos y
## ninguna en lagos. Se mide con el material del agua de verdad.
##   godot --headless --path . -s res://tests/water/test_water_current.gd

const SEA_RADIUS := 1000.0
const SIZE := Vector2i(64, 32)
const TIME := 10.0
const LAKE := Rect2i(40, 10, 10, 10)
const RIVER := Rect2i(10, 10, 6, 10)

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


func _map() -> PlanetWorldMap:
	var data := WorldMapData.new()
	data.size = SIZE
	data.radius = SEA_RADIUS
	data.sea_level_radius = SEA_RADIUS
	data.has_water = true
	data.height_min = -100.0
	data.height_span = 200.0
	data.heights.resize(SIZE.x * SIZE.y)
	data.heights.fill(0.0)
	data.body_ids.resize(data.heights.size())
	data.body_ids.fill(0)
	data.bodies = [
		{"id": 0, "type": WorldMapData.WaterType.OCEAN, "area": 1000.0},
		{"id": 1, "type": WorldMapData.WaterType.LAKE, "area": 100.0},
		{"id": 2, "type": WorldMapData.WaterType.RIVER, "area": 60.0},
	]
	for y in SIZE.y:
		for x in SIZE.x:
			if LAKE.has_point(Vector2i(x, y)):
				data.body_ids[y * SIZE.x + x] = 1
			elif RIVER.has_point(Vector2i(x, y)):
				data.body_ids[y * SIZE.x + x] = 2
	data.shore_size = SIZE
	data.shore_offsets.resize(SIZE.x * SIZE.y * 4)
	data.shore_range = PlanetWorldMap.SHORE_RANGE
	var map := PlanetWorldMap.new()
	map.map = data
	map._build_storm_flags()
	return map


## Distancia firmada al litoral igual en todo el planeta, sin dirección: solo la lee la corriente.
func _set_coast(map: PlanetWorldMap, distance: float) -> void:
	for i in SIZE.x * SIZE.y:
		map.map.shore_offsets[i * 4 + 3] = distance


func _dir(texel: Vector2) -> Vector3:
	return WorldMapData.uv_to_dir(Vector2(texel.x / SIZE.x, texel.y / SIZE.y))


func _center(cell: Vector2i) -> Vector3:
	return _dir(Vector2(cell) + Vector2(0.5, 0.5))


## La corriente sola: la diferencia con la misma muestra sin arrastre deja fuera la órbita de la ola.
func _current(sampler: WaterHeightSampler, dir: Vector3) -> Vector3:
	var pos := dir * SEA_RADIUS
	var keep := WaterHeightSampler.drift_scale
	var with_drift := sampler.get_flow_at(pos, TIME, Vector3.ZERO)
	WaterHeightSampler.drift_scale = 0.0
	var without := sampler.get_flow_at(pos, TIME, Vector3.ZERO)
	WaterHeightSampler.drift_scale = keep
	return with_drift - without


func _expected(sampler: WaterHeightSampler, map: PlanetWorldMap, dir: Vector3, scale: float) -> float:
	var exposure := map.storm_exposure_local(dir * SEA_RADIUS)
	return lerpf(WaterHeightSampler.CURRENT_CALM, WaterHeightSampler.CURRENT_STORM, sampler.get_sea_state()) \
		* WaterHeightSampler.drift_scale \
		* lerpf(WaterHeightSampler.CURRENT_SHELTERED_FRAC, 1.0, exposure) * scale


func _near(value: float, target: float, message: String) -> void:
	check(absf(value - target) <= maxf(absf(target) * 0.01, 1e-4), "%s (%.4f, espera %.4f)" % [message, value, target])


func _run() -> void:
	var map := _map()
	var data := map.map
	var sea := _center(Vector2i(28, 16))
	var lake := _center(Vector2i(44, 14))
	var river := _center(Vector2i(12, 14))

	check(data.current_mix_at_dir(sea, map._current_kinds).is_equal_approx(Vector2(1, 0)), "El mar reparte todo a mar")
	check(data.current_mix_at_dir(lake, map._current_kinds).is_zero_approx(), "Un lago no reparte nada")
	check(data.current_mix_at_dir(river, map._current_kinds).is_equal_approx(Vector2(0, 1)), "Un río reparte todo a río")
	var mouth := data.current_mix_at_dir(_dir(Vector2(RIVER.position.x, 14.5)), map._current_kinds)
	check(mouth.is_equal_approx(Vector2(0.5, 0.5)), "En el borde mar-río se mezclan a medias (%s)" % mouth)
	var lake_edge := data.current_mix_at_dir(_dir(Vector2(LAKE.position.x, 14.5)), map._current_kinds)
	check(lake_edge.is_equal_approx(Vector2(0.5, 0)), "En el borde mar-lago la corriente se apaga a medias (%s)" % lake_edge)
	# Costa de mar en la fila 16: agua hasta x = 28, tierra desde 29. En el centro de la fila solo vota ella.
	for x in range(29, 32):
		data.body_ids[16 * SIZE.x + x] = -1
	var shore := data.current_mix_at_dir(_dir(Vector2(29.0, 16.5)), map._current_kinds)
	check(shore.is_equal_approx(Vector2(1, 0)), "Un téxel de tierra junto al mar no recorta la corriente (%s)" % shore)
	shore = data.current_mix_at_dir(_dir(Vector2(29.25, 16.5)), map._current_kinds)
	check(shore.is_equal_approx(Vector2(1, 0)), "Ni un cuarto de téxel tierra adentro (%s)" % shore)
	shore = data.current_mix_at_dir(_dir(Vector2(29.4, 16.5)), map._current_kinds)
	check(shore.is_equal_approx(Vector2(0.4, 0)), "Más adentro se apaga sin escalón (%s)" % shore)
	shore = data.current_mix_at_dir(_dir(Vector2(29.6, 16.5)), map._current_kinds)
	check(shore.is_zero_approx(), "Pasado el centro del téxel de tierra ya no hay mar (%s)" % shore)
	for x in range(26, 32):
		for y in range(14, 19):
			data.body_ids[y * SIZE.x + x] = -1
	check(data.current_mix_at_dir(sea, map._current_kinds).is_zero_approx(),
		"Agua más fina que un téxel, rodeada de tierra, no arrastra")
	data.body_ids.fill(0)
	for y in SIZE.y:
		for x in SIZE.x:
			if LAKE.has_point(Vector2i(x, y)):
				data.body_ids[y * SIZE.x + x] = 1
			elif RIVER.has_point(Vector2i(x, y)):
				data.body_ids[y * SIZE.x + x] = 2

	var material: ShaderMaterial = load("res://data/resources/WaterSphere_material.tres").duplicate()
	var sampler := WaterHeightSampler.new()
	sampler.setup(material, map, SEA_RADIUS)
	_set_coast(map, 1000.0)
	var open := _current(sampler, sea).length()
	check(open > 0.1, "Mar abierto arrastra (%.3f m/s)" % open)
	_near(open, _expected(sampler, map, sea, 1.0), "Mar abierto lejos de la costa: corriente entera")
	check(_current(sampler, lake).length() < 1e-4, "Un lago no tiene corriente")
	_near(_current(sampler, river).length(), _expected(sampler, map, river, WaterHeightSampler.CURRENT_RIVER_FRAC),
		"Un río conserva una fracción")
	# En la línea de costa la rompiente aún no ha tomado el relevo: sale la corriente de mar sola.
	_set_coast(map, 0.0)
	_near(_current(sampler, sea).length(), open * WaterHeightSampler.CURRENT_COAST_FRAC, "A pie de costa casi se apaga")
	check(_current(sampler, lake).length() < 1e-4, "El lago sigue quieto con la costa al lado")

	# La rampa, sin olas de orilla: el campo sintético no tiene dirección y la rompiente se comería la
	# corriente de mar. Es también el caso de un mar sin temporal, que no lee el campo para las olas.
	var flat: ShaderMaterial = material.duplicate()
	flat.set_shader_parameter("shore_waves_enabled", false)
	sampler.setup(flat, map, SEA_RADIUS)
	_set_coast(map, -40.0)
	_near(_current(sampler, sea).length(), open * WaterHeightSampler.CURRENT_COAST_FRAC,
		"Donde el mapa ya da tierra, lo mismo que en la orilla")
	_set_coast(map, WaterHeightSampler.CURRENT_COAST_RANGE * 0.5)
	_near(_current(sampler, sea).length(), open * lerpf(WaterHeightSampler.CURRENT_COAST_FRAC, 1.0, 0.5),
		"A media rampa, a medio camino")
	_set_coast(map, WaterHeightSampler.CURRENT_COAST_RANGE)
	_near(_current(sampler, sea).length(), open, "Al final de la rampa, entera")

	# Otro material: los parámetros se cachean por material y frame de física, que aquí no avanza.
	var calm_sea := open
	var storm: ShaderMaterial = material.duplicate()
	storm.set_shader_parameter("wave_amplitude", float(storm.get_shader_parameter("wave_calm_amplitude")) * 7.0)
	sampler.setup(storm, map, SEA_RADIUS)
	check(sampler.get_sea_state() > 0.99, "Temporal pleno")
	check(_current(sampler, sea).length() > calm_sea * 2.0, "El temporal sube la corriente del mar")
	check(_current(sampler, lake).length() < 1e-4, "Ni con temporal se mueve un lago")

	var bare := WaterHeightSampler.new()
	bare.setup(material, null, SEA_RADIUS)
	check(bare._current_scale(lake * SEA_RADIUS, NAN) == 1.0, "Sin mapa del planeta, todo es mar como antes")

	map.free()
	print("%d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)
