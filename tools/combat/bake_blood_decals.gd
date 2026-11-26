extends SceneTree

## Hornea las texturas de la sangre (BloodPool en el suelo, BloodStains en el cuerpo) en
## textures/combat/, varias de cada, para que no se repitan:
##   blood_pool_N.png    charco: lóbulos y algún dedo por donde corrió, de borde nítido (la sangre
##                       tiene tensión: no se difumina, acaba en un menisco), espeso y casi igual
##                       de oscuro por dentro, con un cerco empapado alrededor donde la tierra la
##                       ha chupado, y unas gotas caídas hacia un lado
##   blood_splat_N.png   lo que cae: 0, un goterón que cae de arriba (corona de puntas cortas y
##                       gotitas satélite); 1, la estela de un tajo (una fila de gotas alargadas);
##                       2, un abanico de gotas lanzadas de lado (más alargadas cuanto más lejos);
##                       3, un salpicado fino a racimos. 1 y 2 van hacia +X de la imagen, con la
##                       cola de cada gota delante (BloodPool las gira hacia donde iban).
##   blood_smear_N.png   sobre el cuerpo: la herida arriba (una mancha irregular que empapa
##                       alrededor) y unos pocos regueros desiguales que bajan serpenteando, se
##                       afinan y acaban en gota (abajo en la imagen es hacia donde tira la gravedad)
## Y de cada una, _normal (el menisco del borde y el abombado de las gotas) y _orm (oclusión 1,
## rugosidad: brilla donde hay líquido y es mate donde se ha empapado, nada metálica).
##
## La sangre no es una capa de pintura: el color sale del grosor (fina, roja; espesa, granate casi
## negro) y lo empapado alrededor es un cerco pardo y traslúcido.
##
##   godot --headless --path . --script res://tools/combat/bake_blood_decals.gd
## Después, `godot --headless --path . --import` para importar los PNG nuevos.

const OUT := "res://textures/combat/"
const POOLS := 3
const SPLATS := 4
const SMEARS := 3
const POOL_SIZE := 512
const SPLAT_SIZE := 384
const SMEAR_SIZE := Vector2i(256, 384)
## En sRGB, como se guarda el PNG. Fina: roja y viva; espesa: granate casi negro; el cerco seco del
## filo, más oscuro; lo empapado alrededor, pardo rojizo.
const THIN := Color(0.47, 0.03, 0.025)
const THICK := Color(0.2, 0.006, 0.01)
const RIM := Color(0.15, 0.018, 0.014)
const SOAK := Color(0.26, 0.04, 0.028)
## Cuánto cubre donde es fina y donde es espesa, y lo empapado.
const ALPHA := Vector2(0.72, 0.98)
const SOAK_ALPHA := 0.32
## Rugosidad donde es fina (empapada, mate) y donde es espesa (líquida), y lo empapado.
const ROUGHNESS := Vector2(0.5, 0.03)
const SOAK_ROUGHNESS := 0.85
## Anchura del borde del menisco (en radios de la textura) y cuánto inclina la normal.
const MENISCUS := 0.035
const NORMAL_STRENGTH := 0.024

var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.fractal_octaves = 3
	_rng.seed = 1977
	for i in POOLS:
		_bake_pool(i)
	for i in SPLATS:
		_bake_splat(i)
	for i in SMEARS:
		_bake_smear(i)
	print("Sangre horneada en ", OUT)
	quit()


## Un charco: un campo que baja del centro hacia fuera, deformado con ruido, cortado a una altura:
## lóbulos redondos, como la sangre que se extiende por un suelo que no es plano, y algún dedo por
## donde corrió cuesta abajo. El borde no es una línea pareja: arcos lisos (la tensión del líquido)
## con muescas pequeñas donde topa con un grano o una brizna, islas secas donde asoma una piedrecita,
## gotitas sueltas pegadas al filo, y casi en todo él el líquido acaba de golpe (espeso hasta el
## mismo borde); solo a trechos se extiende en una película fina y roja.
func _bake_pool(index: int) -> void:
	var offset := index * 31.7
	var lobes: Array[Vector3] = []
	for i in _rng.randi_range(2, 4):
		var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		lobes.append(Vector3(dir.x, dir.y, _rng.randf_range(0.18, 0.4)))
	# Dedos por donde corrió: una ristra de círculos que menguan, desde el borde hacia fuera.
	var fingers: Array[Vector3] = []
	for i in _rng.randi_range(0, 2):
		var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		var r := _rng.randf_range(0.06, 0.09)
		var at := dir * 0.4
		for k in 7:
			fingers.append(Vector3(at.x, at.y, r))
			dir = dir.rotated(_rng.randf_range(-0.35, 0.35))
			at += dir * r * 0.9
			r *= 0.86
	# Islas secas, sobre todo cerca del borde, donde hay poca sangre.
	var holes: Array[Vector3] = []
	for i in _rng.randi_range(2, 6):
		var at := Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf_range(0.38, 0.6)
		holes.append(Vector3(at.x, at.y, lerpf(0.008, 0.025, pow(_rng.randf(), 2.0))))
	var field_at := func(p: Vector2) -> float:
		# Torcido: los lóbulos no son círculos.
		var q := p + 0.07 * Vector2(_noise.get_noise_2d(p.x * 2.4 + offset, p.y * 2.4),
				_noise.get_noise_2d(p.x * 2.4 + offset + 50.0, p.y * 2.4 + 50.0))
		var field := 0.5 - q.length()
		for lobe in lobes:
			field = maxf(field, lobe.z - q.distance_to(Vector2(lobe.x, lobe.y) * 0.42) * 1.5)
		for f in fingers:
			field = maxf(field, f.z - q.distance_to(Vector2(f.x, f.y)))
		field += 0.06 * _noise.get_noise_2d(q.x * 2.2 + offset, q.y * 2.2) \
				+ 0.018 * _noise.get_noise_2d(q.x * 8.0 + 9.0 + offset, q.y * 8.0)
		# Muescas: el borde se engancha en lo que hay en el suelo (a trechos, no por igual).
		var catch := smoothstep(-0.1, 0.35, _noise.get_noise_2d(p.x * 4.0 + 33.0 + offset, p.y * 4.0))
		field -= catch * 0.014 * absf(_noise.get_noise_2d(p.x * 40.0 + offset, p.y * 40.0 + 11.0))
		field += 0.004 * _noise.get_noise_2d(p.x * 70.0, p.y * 70.0 + offset)
		for h in holes:
			# Irregulares: un terrón, no un círculo; y solo donde la sangre ya es poca.
			var bump := 1.0 + 0.6 * _noise.get_noise_2d(p.x * 90.0 + h.x * 40.0, p.y * 90.0)
			if field < 0.12:
				field = minf(field, p.distance_to(Vector2(h.x, h.y)) - h.z * bump)
		return minf(field, 0.92 - p.length())
	var stamps: Array[Array] = []
	# Las gotas que cayeron antes de encharcarse, hacia un lado.
	var side := Vector2.RIGHT.rotated(_rng.randf() * TAU)
	_cluster(stamps, side, 0.9, 16, Vector2(0.62, 0.95), Vector2(0.006, 0.03))
	# Gotitas sueltas junto al filo: unas tocándolo (un bulto en el borde), otras ya fuera.
	for i in 26:
		var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		var r := 0.15
		while r < 0.95 and field_at.call(dir * r) > 0.0:
			r += 0.004
		var bead := lerpf(0.004, 0.02, pow(_rng.randf(), 2.0))
		stamps.append([dir * (r + _rng.randf_range(-0.2, 2.5) * bead), dir, bead, _rng.randf_range(1.0, 1.4), 0.75])
	var shape := func(p: Vector2) -> Vector3:
		var inside: float = field_at.call(p)
		# Lo que ocupa lo fino junto al borde: casi nada en la mayor parte; a trechos, una película.
		var film := 0.004 + 0.045 * smoothstep(0.05, 0.45, _noise.get_noise_2d(p.x * 3.2 + 7.0 + offset, p.y * 3.2))
		var depth := smoothstep(0.0, film, inside) * (0.9 + 0.08 * _noise.get_noise_2d(p.x * 1.5 + offset, p.y * 1.5))
		return Vector3(inside, clampf(inside / (film + 0.012), 0.0, 1.0), depth)
	_bake(Vector2i(POOL_SIZE, POOL_SIZE), "blood_pool_%d" % index, shape, stamps, true, 0.05)


## Lo que cae (ver arriba): 0 y 3 caen de arriba; 1 y 2 llegan de lado, hacia +X.
func _bake_splat(index: int) -> void:
	var offset := index * 17.3
	var stamps: Array[Array] = []
	var core := 0.0
	var spikes: Array[Vector3] = []
	match index:
		0:
			core = 0.24
			for i in 34:
				spikes.append(Vector3(_rng.randf() * TAU, _rng.randf_range(0.008, 0.03), _rng.randf_range(0.05, 0.11)))
			# Satélites: gotitas que salta la corona, alargadas hacia fuera.
			for i in 14:
				var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
				var r := lerpf(0.008, 0.028, pow(_rng.randf(), 2.0))
				_drop(stamps, dir * _rng.randf_range(0.34, 0.7), dir, r, _rng.randf_range(1.1, 1.8), 0.7, 0.0)
			_cluster(stamps, Vector2.ZERO, 0.0, 30, Vector2(0.3, 0.9), Vector2(0.003, 0.01))
		1:
			# Estela de un tajo: una fila de gotas casi iguales, un poco curvada, con cola delante.
			var bend := _rng.randf_range(-0.25, 0.25)
			var count := _rng.randi_range(9, 13)
			for k in count:
				var t := (float(k) + _rng.randf_range(-0.3, 0.3)) / float(count - 1)
				var x := lerpf(-0.85, 0.8, t)
				var at := Vector2(x, bend * (x * x - 0.5) + _rng.randf_range(-0.06, 0.06))
				var r := lerpf(0.012, 0.045, pow(_rng.randf(), 1.5)) * lerpf(1.2, 0.7, t)
				_drop(stamps, at, Vector2.RIGHT, r, _rng.randf_range(1.8, 2.8), 0.8, 0.6)
			_cluster(stamps, Vector2.RIGHT, 0.4, 40, Vector2(0.0, 0.9), Vector2(0.003, 0.009))
		2:
			# Abanico de gotas lanzadas desde la izquierda: muchas pequeñas, pocas gordas.
			var source := Vector2(-0.95, _rng.randf_range(-0.1, 0.1))
			for i in 46:
				var dir := Vector2.RIGHT.rotated(_rng.randf_range(-0.42, 0.42))
				var t := _rng.randf()
				var at := source + dir * lerpf(0.25, 1.75, t)
				if absf(at.x) > 0.93 or absf(at.y) > 0.93:
					continue
				var r := lerpf(0.006, 0.05, pow(_rng.randf(), 3.0))
				_drop(stamps, at, dir, r, lerpf(1.2, 3.0, t), 0.75, 0.5 * t)
			_cluster(stamps, Vector2.RIGHT, 0.5, 70, Vector2(0.0, 0.92), Vector2(0.003, 0.008))
		_:
			_cluster(stamps, Vector2.ZERO, 0.0, 160, Vector2(0.0, 0.9), Vector2(0.003, 0.03))
	var shape := func(p: Vector2) -> Vector3:
		if core <= 0.0:
			return Vector3(-1.0, 0.0, 0.0)
		var r := p.length()
		var dir := p / maxf(r, 1e-5)
		var edge := core + 0.03 * _noise.get_noise_2d(p.x * 4.0 + 40.0 + offset, p.y * 4.0)
		var angle := dir.angle()
		for s in spikes:
			edge += s.y * exp(-pow(absf(angle_difference(angle, s.x)) / s.z, 2.0))
		var inside := edge - r
		# Espesa hasta el borde casi en todo él (ver _bake_pool).
		var film := 0.005 + 0.03 * smoothstep(0.05, 0.45, _noise.get_noise_2d(p.x * 5.0 + 7.0 + offset, p.y * 5.0))
		return Vector3(inside, clampf(inside / (film + 0.012), 0.0, 1.0), smoothstep(0.0, film, inside) * 0.88)
	_bake(Vector2i(SPLAT_SIZE, SPLAT_SIZE), "blood_splat_%d" % index, shape, stamps, false, 0.0)


## Sobre el cuerpo: la herida arriba y regueros que bajan, se afinan y acaban en gota. La imagen es
## 2:3, así que en x se mide 1,5 veces más ancho que en y.
func _bake_smear(index: int) -> void:
	var offset := index * 23.9
	var wound := Vector2(_rng.randf_range(-0.08, 0.08), -0.5)
	var streaks: Array[Array] = []
	for i in _rng.randi_range(2, 5):
		streaks.append([wound.x + _rng.randf_range(-0.22, 0.22), wound.y + _rng.randf_range(0.0, 0.08),
				lerpf(-0.15, 0.85, pow(_rng.randf(), 0.7)), _rng.randf_range(0.03, 0.075)])
	var stamps: Array[Array] = []
	_cluster(stamps, Vector2.ZERO, 0.0, 12, Vector2(0.0, 0.0), Vector2(0.006, 0.025), wound, Vector2(0.75, 0.3))
	var shape := func(p: Vector2) -> Vector3:
		var q := Vector2(p.x, (p.y - wound.y) * 1.5)
		var edge := 0.3 + 0.1 * _noise.get_noise_2d(q.x * 2.5 + 70.0 + offset, q.y * 2.5) \
				+ 0.035 * _noise.get_noise_2d(q.x * 8.0 + offset, q.y * 8.0)
		var inside := edge - q.length()
		var height := clampf(inside / MENISCUS, 0.0, 1.0)
		var film := 0.015 + 0.07 * smoothstep(0.0, 0.45, _noise.get_noise_2d(q.x * 4.5 + 7.0 + offset, q.y * 4.5))
		var depth := smoothstep(0.0, film, inside) * (0.78 + 0.1 * _noise.get_noise_2d(q.x * 4.0 + offset, q.y * 4.0))
		for st in streaks:
			var x0: float = st[0]
			var top: float = st[1]
			var bottom: float = st[2]
			var width: float = st[3]
			if p.y < top or p.y > bottom + width * 2.0:
				continue
			var along := clampf((p.y - top) / maxf(bottom - top, 1e-3), 0.0, 1.0)
			# Serpentea siguiendo lo que encuentra, y engorda donde se detiene.
			var cx := x0 + 0.06 * _noise.get_noise_2d(x0 * 9.0 + offset, p.y * 2.5) \
					+ 0.015 * _noise.get_noise_2d(x0 * 3.0, p.y * 11.0 + offset)
			var w := width * lerpf(1.0, 0.45, along) * (0.85 + 0.3 * _noise.get_noise_2d(x0 * 5.0, p.y * 7.0 + offset))
			var stripe := w - absf(p.x - cx) * 1.5 if p.y <= bottom else -1.0
			var drop := width * 1.15 - Vector2((p.x - cx) * 1.5, (p.y - bottom) * 0.85).length()
			var best := maxf(stripe, drop)
			if best > inside:
				inside = best
				height = clampf(best / maxf(w, 1e-3), 0.0, 1.0)
				depth = height * (0.7 if drop > stripe else 0.45)
		return Vector3(inside, height, depth)
	_bake(SMEAR_SIZE, "blood_smear_%d" % index, shape, stamps, false, 0.05)


## Una gota en [at] de radio [r], alargada [stretch] en [dir] (hacia donde iba) y, si [tail] > 0,
## con su colita delante: la sangre que sigue de largo al tocar.
func _drop(stamps: Array[Array], at: Vector2, dir: Vector2, r: float, stretch: float, thick: float,
		tail: float) -> void:
	stamps.append([at, dir, r, stretch, thick])
	if tail > 0.0:
		stamps.append([at + dir * r * stretch * 1.25, dir, r * 0.32, 2.4 * (0.5 + tail), thick * 0.6])


## [count] gotitas a racimos (donde el ruido lo deja), entre [reach] del centro (o, con [box], en un
## rectángulo de esa mitad de lado alrededor de [center]), de radio entre [size] con muchas más
## pequeñas que grandes. Con [bias] > 0 caen más hacia [toward].
func _cluster(stamps: Array[Array], toward: Vector2, bias: float, count: int, reach: Vector2,
		size: Vector2, center := Vector2.ZERO, box := Vector2.ZERO) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 20:
		tries += 1
		var at: Vector2
		if box != Vector2.ZERO:
			at = center + Vector2(_rng.randf_range(-box.x, box.x), _rng.randf_range(-box.y, box.y))
		else:
			var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
			if bias > 0.0 and toward != Vector2.ZERO:
				dir = dir.lerp(toward, bias * _rng.randf()).normalized()
			at = dir * lerpf(reach.x, reach.y, sqrt(_rng.randf()))
		if _noise.get_noise_2d(at.x * 3.0 + 50.0, at.y * 3.0) < -0.1:
			continue
		var out := at.normalized() if at.length_squared() > 1e-6 else Vector2.RIGHT
		var r := lerpf(size.x, size.y, pow(_rng.randf(), 3.0))
		stamps.append([at, out, r, _rng.randf_range(1.0, 1.5), lerpf(0.3, 0.7, r / maxf(size.y, 1e-4))])
		placed += 1


## [shape] da, para un punto en [-1, 1]², cuánto dentro de la mancha está (x, en radios; >0 dentro),
## la altura del líquido (y, 0..1, para la normal) y su grosor (z, 0..1, para el color). Las gotas
## de [stamps] ([centro, dirección, radio, estirado, grosor]) se estampan encima. Con [rim], el cerco
## seco del filo. Con [halo] (radios), un cerco empapado y mate alrededor de la mancha (no de las
## gotas sueltas).
func _bake(size: Vector2i, name: String, shape: Callable, stamps: Array[Array], rim: bool, halo: float) -> void:
	var pixel := 2.0 / size.x
	var pixel_y := 2.0 / size.y
	var count := size.x * size.y
	var inside := PackedFloat32Array()
	var height := PackedFloat32Array()
	var depth := PackedFloat32Array()
	inside.resize(count)
	height.resize(count)
	depth.resize(count)
	for y in size.y:
		for x in size.x:
			var s: Vector3 = shape.call(Vector2((x + 0.5) * pixel - 1.0, (y + 0.5) * pixel_y - 1.0))
			var k := y * size.x + x
			inside[k] = s.x
			height[k] = s.y
			depth[k] = s.z
	# El cerco empapado sale de la mancha, no de las gotas sueltas.
	var base := inside.duplicate()
	for st in stamps:
		var center: Vector2 = st[0]
		var along: Vector2 = st[1]
		var radius: float = st[2]
		var stretch: float = st[3]
		var thick: float = st[4]
		var reach := radius * maxf(stretch, 1.0) + pixel * 2.0
		var x0 := maxi(int((center.x - reach + 1.0) / pixel), 0)
		var x1 := mini(int((center.x + reach + 1.0) / pixel) + 1, size.x)
		var y0 := maxi(int((center.y - reach + 1.0) / pixel_y), 0)
		var y1 := mini(int((center.y + reach + 1.0) / pixel_y) + 1, size.y)
		for y in range(y0, y1):
			for x in range(x0, x1):
				var d := Vector2((x + 0.5) * pixel - 1.0, (y + 0.5) * pixel_y - 1.0) - center
				var to := Vector2(d.dot(along) / stretch, d.dot(along.orthogonal())).length()
				var k := y * size.x + x
				if radius - to > inside[k]:
					inside[k] = radius - to
					var dome := sqrt(clampf(1.0 - (to / radius) * (to / radius), 0.0, 1.0))
					height[k] = dome
					depth[k] = thick * dome
	var albedo := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var orm := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for y in size.y:
		for x in size.x:
			var k := y * size.x + x
			var p := Vector2((x + 0.5) * pixel - 1.0, (y + 0.5) * pixel_y - 1.0)
			var cover := smoothstep(-pixel, pixel, inside[k])
			var thick := clampf(depth[k], 0.0, 1.0)
			# Donde es fina deja ver algo, a manchas.
			var soak := 0.88 + 0.12 * _noise.get_noise_2d(p.x * 9.0 + 5.0, p.y * 9.0)
			var color := THIN.lerp(THICK, pow(thick, 0.8))
			color *= 0.95 + 0.06 * _noise.get_noise_2d(p.x * 5.0 + 3.0, p.y * 5.0)
			var alpha := lerpf(ALPHA.x * soak, ALPHA.y, thick)
			if rim:
				# El filo se seca antes: un cerco fino más oscuro, a trechos.
				var ring := exp(-pow(inside[k] / 0.008, 2.0)) * smoothstep(-0.1, 0.4, _noise.get_noise_2d(p.x * 7.0, p.y * 7.0))
				color = color.lerp(RIM, ring * 0.35)
				alpha = lerpf(alpha, 0.8, ring * 0.3)
			var rough := lerpf(ROUGHNESS.x, ROUGHNESS.y, thick)
			color.a = alpha * cover
			if halo > 0.0 and cover < 1.0:
				# Lo empapado: más ancho a trechos, más claro hacia fuera.
				# Solo a trechos, y granulado: la tierra la chupa por sus poros, así que se deshace
				# hacia fuera en puntitos en vez de acabar en un cerco parejo.
				var reach := halo * smoothstep(-0.15, 0.3, _noise.get_noise_2d(p.x * 4.5 + 21.0, p.y * 4.5)) \
						* (0.6 + 0.4 * _noise.get_noise_2d(p.x * 13.0 + 4.0, p.y * 13.0))
				var near := clampf(1.0 + base[k] / maxf(reach, 1e-4), 0.0, 1.0)
				var grain := _noise.get_noise_2d(p.x * 32.0 + 3.0, p.y * 32.0) * 0.5 + 0.5
				var wet := smoothstep(0.5, 0.62, near * 0.75 + grain * 0.45) if reach > 1e-4 else 0.0
				var soak_a := SOAK_ALPHA * clampf(wet, 0.0, 1.0) * (1.0 - cover)
				if soak_a > 0.0:
					var total := color.a + soak_a * (1.0 - color.a)
					var mixed := SOAK.lerp(color, color.a / maxf(total, 1e-4))
					color = Color(mixed.r, mixed.g, mixed.b, total)
					rough = lerpf(SOAK_ROUGHNESS, rough, cover)
			albedo.set_pixel(x, y, color)
			orm.set_pixel(x, y, Color(1.0, rough, 0.0))
			height[k] *= cover
	albedo.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	orm.save_png(ProjectSettings.globalize_path(OUT + name + "_orm.png"))
	# Normal (convención OpenGL, +Y arriba en la imagen) desde la altura.
	var normal := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for y in size.y:
		for x in size.x:
			var hx := height[y * size.x + mini(x + 1, size.x - 1)] - height[y * size.x + maxi(x - 1, 0)]
			var hy := height[mini(y + 1, size.y - 1) * size.x + x] - height[maxi(y - 1, 0) * size.x + x]
			var n := Vector3(-hx / (2.0 * pixel) * NORMAL_STRENGTH, hy / (2.0 * pixel_y) * NORMAL_STRENGTH, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	normal.save_png(ProjectSettings.globalize_path(OUT + name + "_normal.png"))
	print("  ", name)
