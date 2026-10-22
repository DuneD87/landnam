extends RefCounted

## El aterrizaje se calcula en el marco del terreno, sin depender de chunks cargados ni del
## SpawnPoint de una versión anterior del planeta. El mapa filtra océanos; el SDF vivo decide
## la altura final, incluyendo terrazas, cuevas y ríos. La latitud evita la banda desértica.
const MIN_LATITUDE_DEGREES := 35.0
const MAX_LATITUDE_DEGREES := 45.0
const MIN_SUN_ELEVATION_DEGREES := 10.0
const MAX_ATTEMPTS := 512
const WATER_MARGIN := 8.0
const FOOT_CLEARANCE := 1.0
const MAX_SLOPE_DEGREES := 40.0
const SEARCH_STEP := 64.0

var _generator: VoxelGenerator
var _buffer := VoxelBuffer.new()


func _init() -> void:
	_buffer.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
	_buffer.create(2, 2, 2)


## Transform local al VoxelLodTerrain, o null si no hay tierra segura de día en la banda pedida.
## sun_direction apunta hacia el sol en el mismo marco local que el terreno.
func find_landing(planet: Planet, map: WorldMapData,
		rng: RandomNumberGenerator, sun_direction: Vector3) -> Variant:
	_generator = planet.voxel_terrain.generator
	if _generator == null or sun_direction.is_zero_approx():
		return null
	var sunlight := sun_direction.normalized()
	var min_sun_dot := sin(deg_to_rad(MIN_SUN_ELEVATION_DEGREES))
	var sea_radius := planet.radius - planet.water_radius
	var lower := sea_radius + WATER_MARGIN if planet.has_water else planet.radius - 4096.0
	var upper := planet.radius + 256.0
	for height in planet.definition.max_heights:
		upper = maxf(upper, planet.radius + height + 256.0)
	if map != null and map.is_valid():
		upper = maxf(upper, planet.radius + map.height_min + map.height_span + 256.0)
	for _attempt in MAX_ATTEMPTS:
		# Uniforme por área esférica, en lugar de acumular puntos hacia el norte.
		var y := rng.randf_range(sin(deg_to_rad(MIN_LATITUDE_DEGREES)),
			sin(deg_to_rad(MAX_LATITUDE_DEGREES)))
		var longitude := rng.randf_range(-PI, PI)
		var horizontal := sqrt(1.0 - y * y)
		var up := Vector3(horizontal * cos(longitude), y, horizontal * sin(longitude))
		if up.dot(sunlight) < min_sun_dot:
			continue
		if map != null and map.is_valid() and planet.has_water:
			if map.is_water_at_dir(up) or map.surface_radius_at_dir(up) < lower:
				continue
		var radius := _surface_radius(up, upper, lower)
		if not is_finite(radius):
			continue
		var point := up * radius
		var normal := Vector3(
			_sdf(point + Vector3.RIGHT) - _sdf(point - Vector3.RIGHT),
			_sdf(point + Vector3.UP) - _sdf(point - Vector3.UP),
			_sdf(point + Vector3.BACK) - _sdf(point - Vector3.BACK)).normalized()
		if normal.dot(up) < cos(deg_to_rad(MAX_SLOPE_DEGREES)):
			continue
		var right := up.cross(Vector3.RIGHT if absf(up.z) > 0.9 else Vector3.FORWARD).normalized()
		var forward := right.cross(up).normalized()
		var clear := true
		# Comprueba también el suelo alrededor: evita bordes de terraza y pequeñas crestas.
		for offset: Vector3 in [right, -right, forward, -forward]:
			var neighbor := (point + offset * 4.0).normalized()
			var neighbor_radius := _surface_radius(neighbor, radius + 8.0, maxf(lower, radius - 3.0))
			if not is_finite(neighbor_radius) or absf(neighbor_radius - radius) > 2.5:
				clear = false
				break
		if clear:
			var basis := Basis(right, up, forward).rotated(up, rng.randf_range(-PI, PI))
			return Transform3D(basis, point + up * FOOT_CLEARANCE)
	return null


## Primer cruce aire -> suelo al bajar radialmente. Los pasos cortos cerca del cero no saltan
## una terraza; la bisección da precisión subvoxel antes de añadir el margen de los pies.
func _surface_radius(up: Vector3, upper: float, lower: float) -> float:
	var radius := upper
	var value := _sdf(up * radius)
	if value <= 0.0:
		return NAN
	while radius > lower:
		var next := maxf(lower, radius - clampf(value * 0.8, 0.5, SEARCH_STEP))
		var next_value := _sdf(up * next)
		if next_value <= 0.0:
			var air := radius
			var ground := next
			for _i in 10:
				var middle := (air + ground) * 0.5
				if _sdf(up * middle) > 0.0:
					air = middle
				else:
					ground = middle
			return (air + ground) * 0.5
		radius = next
		value = next_value
	return NAN


## La misma interpolación del vóxel que usa la superficie, incluso sin terreno streameado.
func _sdf(point: Vector3) -> float:
	var cell := Vector3i(point.floor())
	_generator.generate_block(_buffer, cell, 0)
	var fraction := point - Vector3(cell)
	var rows := PackedFloat32Array()
	for z in 2:
		for y in 2:
			rows.append(lerpf(_buffer.get_voxel_f(0, y, z, VoxelBuffer.CHANNEL_SDF),
				_buffer.get_voxel_f(1, y, z, VoxelBuffer.CHANNEL_SDF), fraction.x))
	return lerpf(lerpf(rows[0], rows[1], fraction.y),
		lerpf(rows[2], rows[3], fraction.y), fraction.z)
