class_name TrailMap extends RefCounted

## Las sendas del mundo (Planet.get_trail_network) listas para dibujarlas como líneas sobre el mapa
## grande (WorldMapUI) y el minimapa (Minimap): nítidas a cualquier zoom, cosa que una imagen más en
## world_map.gdshader no daría a 3 km de vista. Los trazos van simplificados sobre la esfera
## (Douglas-Peucker) a dos tolerancias y partidos en trozos con su extensión, para descartar de un
## vistazo lo que no cae en la vista. Se preparan una vez y se guardan en el propio campo.

## Tolerancias de la simplificación (m): la fina para el minimapa (un píxel son unos 14 m) y el mapa
## grande de cerca, la gruesa para el mapa grande de lejos.
const FINE := 6.0
const COARSE := 60.0
## Por encima de estos metros por píxel el mapa grande usa la gruesa.
const COARSE_FROM := 40.0
## Largo máximo de un trozo (m).
const PIECE := 1500.0
## Color de las sendas, el mismo en los dos mapas: un pardo oscuro que se lee sobre el verde y el ocre.
const COLOR := Color(0.27, 0.17, 0.09, 0.9)


## {"fine": [{"points": PackedVector3Array (direcciones), "center": Vector3, "reach": float (en la
## esfera unidad)}], "coarse": igual, "fine_uv": [{"points": PackedVector2Array (UV del mapa,
## WorldMapData.dir_to_uv), "box": Rect2}], "coarse_uv": igual}. {} sin sendas.
static func lines(field: Dictionary) -> Dictionary:
	if field.is_empty():
		return {}
	if field.has("map_lines"):
		return field.map_lines
	var radius := float(field.radius)
	var out := {}
	for pair in [["fine", FINE], ["coarse", COARSE]]:
		var pieces: Array = []
		var runs: Array = []
		for line: PackedVector3Array in field.strokes:
			var simple := _simplify(line, float(pair[1]) / radius)
			for piece in _chop(simple, PIECE / radius):
				pieces.append(_bounded(piece))
			runs.append_array(_uv_runs(simple))
		out[pair[0]] = pieces
		out[pair[0] + "_uv"] = runs
	field.map_lines = out
	return out


## Douglas-Peucker sobre direcciones unitarias: quita los puntos a menos de [tolerance] (en la
## esfera unidad) de la cuerda entre los que se quedan.
static func _simplify(line: PackedVector3Array, tolerance: float) -> PackedVector3Array:
	if line.size() < 3:
		return line
	var keep := PackedByteArray()
	keep.resize(line.size())
	keep[0] = 1
	keep[line.size() - 1] = 1
	var stack := PackedInt32Array([0, line.size() - 1])
	while not stack.is_empty():
		var last := stack[stack.size() - 1]
		var first := stack[stack.size() - 2]
		stack.resize(stack.size() - 2)
		var a := line[first]
		var ab := line[last] - a
		var ab2 := maxf(ab.length_squared(), 1.0e-18)
		var worst := -1
		var worst_d := tolerance
		for i in range(first + 1, last):
			var t := clampf((line[i] - a).dot(ab) / ab2, 0.0, 1.0)
			var d := line[i].distance_to(a + ab * t)
			if d > worst_d:
				worst_d = d
				worst = i
		if worst >= 0:
			keep[worst] = 1
			stack.append_array([first, worst, worst, last])
	var out := PackedVector3Array()
	for i in line.size():
		if keep[i] != 0:
			out.append(line[i])
	return out


## [line] en trozos de como mucho [length] (en la esfera unidad) que comparten el punto del corte.
static func _chop(line: PackedVector3Array, length: float) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var start := 0
	var run := 0.0
	for i in range(1, line.size()):
		run += line[i].distance_to(line[i - 1])
		if run >= length or i == line.size() - 1:
			out.append(line.slice(start, i + 1))
			start = i
			run = 0.0
	return out


## Un trozo con su centro y lo que se aleja de él.
static func _bounded(points: PackedVector3Array) -> Dictionary:
	var sum := Vector3.ZERO
	for p in points:
		sum += p
	var center := sum.normalized()
	var reach := 0.0
	for p in points:
		reach = maxf(reach, p.distance_to(center))
	return {"points": points, "center": center, "reach": reach}


## [line] en UV del mapa, partida donde cruza el antimeridiano (de un borde del mapa al otro): el
## tramo que lo cruza se corta en él y el punto del corte va a los dos bordes. Con la caja de cada uno.
static func _uv_runs(line: PackedVector3Array) -> Array:
	var out: Array = []
	var run := PackedVector2Array()
	for i in line.size():
		var uv := WorldMapData.dir_to_uv(line[i])
		if not run.is_empty() and absf(uv.x - run[run.size() - 1].x) > 0.5:
			# El antimeridiano es z = 0 con x < 0 (u = 0 o 1).
			var a := line[i - 1]
			var b := line[i]
			var cut := a.lerp(b, a.z / (a.z - b.z) if absf(a.z - b.z) > 1.0e-12 else 0.5).normalized()
			var v := WorldMapData.dir_to_uv(cut).y
			var before := 1.0 if run[run.size() - 1].x > 0.5 else 0.0
			run.append(Vector2(before, v))
			out.append(_boxed(run))
			run = PackedVector2Array([Vector2(1.0 - before, v)])
		run.append(uv)
	if run.size() > 1:
		out.append(_boxed(run))
	return out


static func _boxed(run: PackedVector2Array) -> Dictionary:
	var box := Rect2(run[0], Vector2.ZERO)
	for uv in run:
		box = box.expand(uv)
	return {"points": run, "box": box}
