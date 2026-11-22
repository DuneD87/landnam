class_name SettlementFlatten extends RefCounted

## El aplanado de los poblados: el terreno de cada uno se acerca a un plano con su pendiente media (por
## mínimos cuadrados, con tope MAX_TILT), una parte STRENGTH de lo que le falta (queda algo del relieve
## natural), hasta PLATEAU m más allá de lo más lejano y fundiéndose con el de alrededor en FALL m más. Va en el grafo del terreno (data/graph_functions/
## settlement_flatten.tres, de tools/build_settlement_flatten.gd), entre las sendas y las cuevas: el
## terreno nace ya aplanado, sin ediciones que guardar.
##
## El grafo lee dos imágenes en la convención del nodo SdfSphereHeightmap (como TrailField y el claro de
## SettlementField), de SIZE téxeles (unos 46 m en el ecuador):
##   - la cota del plano (settlement_flat_t): (radio del plano - radio del planeta) / FACTOR, que el nodo
##     convierte directamente en la SDF del plano. Se escribe más allá de donde hay peso, para que el
##     bilineal no la mezcle con el 0 de fuera donde aún aplana.
##   - el peso (settlement_flat_w), de 0 a 1.
## Lo que cada poblado escribe en ellas lo calcula fit al trazarlo y se guarda con el campo de los
## poblados (SettlementField: "flats"), así que al cargar solo se pintan los téxeles.
##
## El nodo lee como 0 las zonas donde la imagen es constante (medido; ver RiverField.rasterize): fuera
## de los poblados eso es justo el neutro (peso 0), pero dentro el peso vale 1 en todo un trozo, y en un
## llano la cota también es igual. Por eso los téxeles escritos llevan un temblor de DITHER (1 mm de
## cota, una millonésima de peso). Y el nodo solo lee la imagen cerca de su propia superficie (entre el
## mínimo y el máximo de la imagen, más 1,2 veces ese rango a cada lado): dos téxeles del polo llevan
## RANGE para que lea todo el relieve.
##
## Dónde no aplana: bajo el mar, cerca de un río (de RIVER_NEAR a RIVER_FAR m del cauce, para no
## rellenarlo) y donde haría falta mover más de MAX_CUT m de tierra (un barranco o un risco junto al
## poblado se quedan). El plano de las casas se traza después sobre el terreno ya aplanado
## (SettlementField.replan), así que se asientan en lo que haya de verdad.

const SIZE := Vector2i(4096, 2048)
## Factores de los SdfSphereHeightmap de la cota y del peso: los de tools/build_settlement_flatten.gd
## (ver allí por qué el del peso es tan grande).
const FACTOR := 1000.0
const WEIGHT_FACTOR := 1000000.0
const MAX_TILT := 0.25
## El anillo de la plaza que entra en el ajuste del plano (m del centro).
const PLAZA_RING := 6.0
const PLATEAU := 40.0
const FALL := 75.0
## Cuánto se acerca al plano (el peso dentro): con 1 queda un plano perfecto, que en terreno ondulado se
## ve como una plataforma recortada en el paisaje; con menos se queda parte del relieve natural. Se
## mezclan las SDF, no las alturas, y la del terreno crece menos de un metro por metro (bajo tierra, un
## tercio): el suelo se acerca al plano algo más que esto, de 0,75 a 0,9 según el sitio.
const STRENGTH := 0.75
const MAX_CUT := 12.0
const RIVER_NEAR := 15.0
const RIVER_FAR := 45.0
const DITHER := 2.0e-6
## Cota (en unidades de la imagen) de los dos téxeles que abren la lectura del nodo: -1200 y 2200 m.
const RANGE := Vector2(-1.2, 2.2)
const TARGET_NODE := "settlement_flat_t"
const WEIGHT_NODE := "settlement_flat_w"
const SPHERE_NODE := "settlement_planet_sdf"
## Índices de parámetro de SdfSphereHeightmap: imagen, radio, factor.
const _P_IMAGE := 0
const _P_RADIUS := 1
const _P_FACTOR := 2


## El aplanado del poblado [plan] (de SettlementLayout.plan, trazado sobre el terreno sin aplanar) con el
## suelo de [ground] (dirección -> radio). [rivers]: Planet.get_river_network() ({} sin ríos).
## {"center", "into" (los del plano del poblado), "plane": Vector3(radio en el centro, pendiente hacia
## right, hacia into), "tilt": su pendiente, "fit_tilt": la del suelo (sin el tope),
## "texels": PackedInt32Array de x, y, "t": la cota y "w": el peso de cada uno (PackedFloat32Array)}, o
## {} si no hay suelo para ajustarlo.
static func fit(plan: Dictionary, ground: Callable, rivers: Dictionary, radius: float, sea_radius: float,
		size := SIZE) -> Dictionary:
	var c: Vector3 = plan.center
	var fwd: Vector3 = (plan.into as Vector3).slide(c).normalized()
	var right := c.cross(fwd).normalized()
	var base := float(plan.ground)
	var extent := float(plan.extent)
	# El plano: h = a + b·u + d·v (m sobre base), por mínimos cuadrados sobre el suelo de lo ocupado (no
	# de todo el círculo: en el borde de una meseta, medio círculo es ladera abajo).
	var s := PackedFloat64Array()
	s.resize(9)  # count, Σu, Σv, Σuu, Σvv, Σuv, Σh, Σuh, Σvh
	for dir in occupied(plan):
		var g: float = ground.call(dir)
		if is_nan(g) or g < sea_radius + 1.0:
			continue
		var facing := dir.dot(c)
		var u := radius * dir.dot(right) / facing
		var v := radius * dir.dot(fwd) / facing
		var h := g - base
		s[0] += 1.0
		s[1] += u
		s[2] += v
		s[3] += u * u
		s[4] += v * v
		s[5] += u * v
		s[6] += h
		s[7] += u * h
		s[8] += v * h
	if s[0] < 6.0:
		return {}
	var plane := _solve([[s[0], s[1], s[2]], [s[1], s[3], s[5]], [s[2], s[5], s[4]]], [s[6], s[7], s[8]])
	if plane.is_empty():
		return {}
	var a: float = plane[0]
	var slope := Vector2(plane[1], plane[2])
	var fit_tilt := slope.length()
	if slope.length() > MAX_TILT:
		# Con menos pendiente, el plano sigue pasando por la media de lo ocupado.
		var mean := Vector2(s[1], s[2]) / s[0]
		var capped := slope.normalized() * MAX_TILT
		a += (slope - capped).dot(mean)
		slope = capped

	# Los téxeles: la cota hasta donde el bilineal la lee junto a un téxel con peso; el peso, hasta FALL.
	var zone := extent + PLATEAU + FALL
	var texel := maxf(TAU * radius / size.x, PI * radius / size.y)
	var reach := zone + 2.0 * texel
	var texels := PackedInt32Array()
	var targets := PackedFloat32Array()
	var weights := PackedFloat32Array()
	var w := size.x
	var h := size.y
	var ang := reach / radius
	var lat := asin(clampf(c.y, -1.0, 1.0))
	var ya := int(floor(RiverField.node_v(sin(minf(lat + ang, PI * 0.5))) * h))
	var yb := int(ceil(RiverField.node_v(sin(maxf(lat - ang, -PI * 0.5))) * h))
	var xc := fposmod(0.5 - atan2(c.z, c.x) / TAU, 1.0) * w
	for y in range(clampi(mini(ya, yb), 0, h - 1), clampi(maxi(ya, yb), 0, h - 1) + 1):
		var yy := RiverField.inv_node_v(float(y) / h)
		var st := sqrt(maxf(1.0 - yy * yy, 0.0))
		var half := reach * w / maxf(radius * st * TAU, 1.0e-3)
		var x_lo := 0
		var x_hi := w - 1
		if half < w * 0.5:
			x_lo = int(floor(xc - half))
			x_hi = int(ceil(xc + half))
		for xr in range(x_lo, x_hi + 1):
			var xi := posmod(xr, w)
			var lon := (float(xi) / w - 0.5) * TAU
			var p := Vector3(st * cos(lon), yy, -st * sin(lon))
			var facing := p.dot(c)
			if facing <= 0.0:
				continue
			var d := radius * acos(clampf(facing, -1.0, 1.0))
			if d > reach:
				continue
			var u := radius * p.dot(right) / facing
			var v := radius * p.dot(fwd) / facing
			var target := base + a + slope.x * u + slope.y * v
			var weight := STRENGTH * (1.0 - smoothstep(extent + PLATEAU, zone, d))
			if weight > 0.0:
				var g: float = ground.call(p)
				if is_nan(g) or g < sea_radius + 1.0:
					weight = 0.0
				else:
					weight *= 1.0 - smoothstep(MAX_CUT, MAX_CUT * 1.75, absf(g - target))
					weight *= smoothstep(RIVER_NEAR, RIVER_FAR, RiverField.distance_at(rivers, p))
			texels.append(xi)
			texels.append(y)
			targets.append((target - radius) / FACTOR)
			weights.append(weight)
	return {"center": c, "into": fwd, "plane": Vector3(base + a, slope.x, slope.y), "tilt": slope.length(), "fit_tilt": fit_tilt, "texels": texels,
		"t": targets, "w": weights}


## Las direcciones del suelo de lo ocupado de [plan]: el origen y la puerta de cada construcción y el
## punto entre ellos, la plaza (un anillo de PLAZA_RING m) y, en una villa, sus calles.
static func occupied(plan: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var c: Vector3 = plan.center
	var fwd: Vector3 = (plan.into as Vector3).slide(c).normalized()
	var right := c.cross(fwd).normalized()
	out.append(c)
	for k in 8:
		var a := TAU * k / 8.0
		out.append((c + (right * sin(a) + fwd * cos(a)) * PLAZA_RING / float(plan.ground)).normalized())
	for b: Dictionary in plan.get("buildings", []):
		var o := (b.origin as Vector3).normalized()
		var d := (b.door as Vector3).normalized()
		out.append_array([o, d, (o + d).normalized()])
	for street: Dictionary in plan.get("streets", []):
		for p: Vector3 in street.points:
			out.append(p.normalized())
	return out


## Las dos imágenes del grafo con el aplanado de todos los poblados de [field] (sus "flats", de fit):
## {"t", "w"}, o {} si ninguno aplana.
static func images(field: Dictionary, size := SIZE) -> Dictionary:
	var any := false
	var t := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	var w := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	for flat: Dictionary in field.get("flats", []):
		if flat.is_empty():
			continue
		var texels: PackedInt32Array = flat.texels
		var targets: PackedFloat32Array = flat.t
		var weights: PackedFloat32Array = flat.w
		for k in targets.size():
			var x := texels[2 * k]
			var y := texels[2 * k + 1]
			# El temblor, distinto en cada téxel vecino: nunca dos iguales seguidos.
			var jitter := DITHER * float((x * 7 + y * 13) % 5 - 2)
			t.set_pixel(x, y, Color(targets[k] + jitter, 0, 0))
			if weights[k] > 0.0:
				w.set_pixel(x, y, Color(clampf(weights[k] - absf(jitter), 0.0, 1.0), 0, 0))
				any = true
	if not any:
		return {}
	t.set_pixel(0, 0, Color(RANGE.x, 0, 0))
	t.set_pixel(1, 0, Color(RANGE.y, 0, 0))
	return {"t": t, "w": w}


## Mete [imgs] (de images) en el grafo de [target] (un VoxelGeneratorGraph o una VoxelGraphFunction),
## en un planeta de [radius]. true si encontró el aplanado.
static func apply(target, imgs: Dictionary, radius: float) -> bool:
	var functions := TrailGenerator._functions(target)
	var found := false
	for entry in [[TARGET_NODE, imgs.t, FACTOR], [WEIGHT_NODE, imgs.w, WEIGHT_FACTOR]]:
		var fn := TrailGenerator._owner(functions, entry[0])
		if fn == null:
			return false
		var node := fn.find_node_by_name(entry[0])
		fn.set_node_param(node, _P_IMAGE, entry[1])
		fn.set_node_param(node, _P_RADIUS, radius)
		fn.set_node_param(node, _P_FACTOR, entry[2])
		found = true
	TrailGenerator._set_input(functions, SPHERE_NODE, "radius", radius)
	return found


## Si [target] (un VoxelGeneratorGraph o una VoxelGraphFunction) lleva el aplanado.
static func present(target) -> bool:
	return TrailGenerator._owner(TrailGenerator._functions(target), WEIGHT_NODE) != null


## [m] · x = [r] para una matriz de 3 × 3, por Cramer en doble precisión. [] si es singular.
static func _solve(m: Array, r: Array) -> Array:
	var det := _det(m)
	if absf(det) < 1.0e-9:
		return []
	var out := []
	for col in 3:
		var mc := [m[0].duplicate(), m[1].duplicate(), m[2].duplicate()]
		for row in 3:
			mc[row][col] = r[row]
		out.append(_det(mc) / det)
	return out


static func _det(m: Array) -> float:
	return m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) \
		- m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) \
		+ m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
