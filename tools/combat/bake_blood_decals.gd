extends SceneTree

## Hornea las texturas de la sangre (BloodPool en el suelo, BloodStains en el cuerpo) en
## textures/combat/, varias de cada, para que no se repitan:
##   blood_pool_N.png    charco: borde irregular con dedos por donde corrió, oscuro y espeso en
##                       medio, fino y traslúcido en el borde (empapa la tierra), con el cerco del
##                       filo, que se seca antes, y gotitas y salpicado fino alrededor
##   blood_splat_N.png   lo que cae de una herida o de un golpe: una mancha con su corona de puntas
##                       y gotas despedidas, alargadas hacia fuera; un reguero de gotas en una
##                       dirección; o solo un salpicado
##   blood_smear_N.png   sobre el cuerpo: la mancha del golpe arriba y regueros que bajan, cada uno
##                       con su gota al final (abajo en la imagen es hacia donde tira la gravedad)
## Y de cada una, _normal (el menisco del borde y el abombado de las gotas) y _orm (oclusión 1,
## rugosidad: brilla donde hay líquido y es mate donde se ha empapado, nada metálica).
##
## La sangre no es una capa de pintura: el color sale del grosor (fina, roja y traslúcida; espesa,
## casi negra), y donde es fina deja ver el suelo.
##
##   godot --headless --path . --script res://tools/combat/bake_blood_decals.gd
## Después, `godot --headless --path . --import` para importar los PNG nuevos.

const OUT := "res://textures/combat/"
const POOLS := 3
const SPLATS := 4
const SMEARS := 3
const POOL_SIZE := 512
const SPLAT_SIZE := 256
const SMEAR_SIZE := Vector2i(256, 384)
## En sRGB, como se guarda el PNG. Fina: roja y viva; espesa: granate casi negro; el cerco seco del
## filo, más pardo.
const THIN := Color(0.4, 0.03, 0.03)
const THICK := Color(0.17, 0.006, 0.01)
const RIM := Color(0.2, 0.025, 0.02)
## Cuánto cubre donde es fina y donde es espesa.
const ALPHA := Vector2(0.48, 0.97)
## Rugosidad donde es fina (empapada, mate) y donde es espesa (líquida).
const ROUGHNESS := Vector2(0.62, 0.04)
## Anchura del borde del menisco (en radios de la textura) y cuánto inclina la normal.
const MENISCUS := 0.05
const NORMAL_STRENGTH := 0.022

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
## lóbulos redondos, como la sangre que se extiende por un suelo que no es plano, y uno o dos más
## largos por donde corrió cuesta abajo.
func _bake_pool(index: int) -> void:
	var offset := index * 31.7
	var lobes: Array[Vector3] = []
	for i in _rng.randi_range(1, 3):
		var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		lobes.append(Vector3(dir.x, dir.y, _rng.randf_range(0.25, 0.45)))
	var stamps: Array[Array] = []
	_scatter(stamps, 12, Vector2(0.6, 0.92), Vector2(0.01, 0.028), 0.6, Vector2(1.0, 1.5))
	_specks(stamps, 60, Vector2(0.55, 0.98))
	var shape := func(p: Vector2) -> Vector3:
		var field := 0.55 - p.length()
		for lobe in lobes:
			var c := Vector2(lobe.x, lobe.y) * 0.45
			field = maxf(field, lobe.z - p.distance_to(c) * 1.4)
		field += 0.16 * _noise.get_noise_2d(p.x * 1.6 + offset, p.y * 1.6) \
				+ 0.05 * _noise.get_noise_2d(p.x * 5.0 + 9.0 + offset, p.y * 5.0)
		var inside := minf(field, 0.9 - p.length())
		# Más honda hacia dentro, a manchas.
		var depth := smoothstep(0.0, 0.28, inside) * (0.8 + 0.2 * _noise.get_noise_2d(p.x * 4.0 + offset, p.y * 4.0))
		return Vector3(inside, clampf(inside / MENISCUS, 0.0, 1.0), depth)
	_bake(Vector2i(POOL_SIZE, POOL_SIZE), "blood_pool_%d" % index, shape, stamps, true)


## Lo que cae: 0, una mancha con corona y gotas despedidas hacia fuera; 1, el impacto de un goterón
## (corona de puntas cortas y gotitas); 2, un reguero de gotas en una dirección; 3, un salpicado.
func _bake_splat(index: int) -> void:
	var offset := index * 17.3
	var stamps: Array[Array] = []
	var core := 0.0
	var spikes: Array[Vector3] = []
	match index:
		0:
			core = 0.22
			_scatter(stamps, 30, Vector2(0.3, 0.92), Vector2(0.014, 0.07), 0.8, Vector2(1.2, 2.6))
			_specks(stamps, 50, Vector2(0.3, 0.98))
		1:
			core = 0.3
			for i in 22:
				spikes.append(Vector3(_rng.randf() * TAU, _rng.randf_range(0.015, 0.06), _rng.randf_range(0.06, 0.14)))
			_scatter(stamps, 18, Vector2(0.45, 0.9), Vector2(0.01, 0.035), 0.7, Vector2(1.0, 1.8))
			_specks(stamps, 40, Vector2(0.4, 0.98))
		2:
			var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
			for k in 9:
				var t := float(k) / 8.0
				var at := dir * lerpf(-0.75, 0.8, t) + dir.orthogonal() * _rng.randf_range(-0.06, 0.06)
				var r := lerpf(0.09, 0.025, t) * _rng.randf_range(0.7, 1.2)
				# Exclamación: la gota y su cola hacia donde iba.
				stamps.append([at, dir, r, lerpf(1.1, 2.4, t), 0.8])
				stamps.append([at + dir * r * 2.2, dir, r * 0.45, 2.0, 0.5])
			_specks(stamps, 45, Vector2(0.1, 0.95))
		_:
			_scatter(stamps, 24, Vector2(0.0, 0.85), Vector2(0.012, 0.045), 0.7, Vector2(1.0, 1.9))
			_specks(stamps, 90, Vector2(0.0, 0.98))
	var shape := func(p: Vector2) -> Vector3:
		if core <= 0.0:
			return Vector3(-1.0, 0.0, 0.0)
		var r := p.length()
		var dir := p / maxf(r, 1e-5)
		var edge := core + 0.05 * _noise.get_noise_2d(dir.x * 2.0 + 40.0 + offset, dir.y * 2.0)
		var angle := dir.angle()
		for s in spikes:
			edge += s.y * exp(-pow(absf(angle_difference(angle, s.x)) / s.z, 2.0))
		var inside := edge - r
		return Vector3(inside, clampf(inside / MENISCUS, 0.0, 1.0), smoothstep(0.0, 0.14, inside) * 0.85)
	_bake(Vector2i(SPLAT_SIZE, SPLAT_SIZE), "blood_splat_%d" % index, shape, stamps, false)


## Sobre el cuerpo: mancha arriba y regueros que bajan, se afinan y acaban en gota. La imagen es
## 2:3, así que en x se mide 1,5 veces más ancho que en y.
func _bake_smear(index: int) -> void:
	var offset := index * 23.9
	var streaks: Array[Array] = []
	for i in _rng.randi_range(4, 8):
		streaks.append([_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, -0.3), _rng.randf_range(-0.1, 0.85),
				_rng.randf_range(0.03, 0.065)])
	var stamps: Array[Array] = []
	for i in 14:
		var angle := _rng.randf() * TAU
		var at := Vector2(cos(angle) * _rng.randf_range(0.4, 0.85), -0.55 + sin(angle) * _rng.randf_range(0.2, 0.35))
		stamps.append([Vector2(at.x, at.y), Vector2.RIGHT, _rng.randf_range(0.012, 0.03), 1.0, 0.5])
	var shape := func(p: Vector2) -> Vector3:
		var q := Vector2(p.x, (p.y + 0.55) * 1.5)
		var r := q.length()
		var dir := q / maxf(r, 1e-5)
		var edge := 0.36 + 0.11 * _noise.get_noise_2d(dir.x * 2.0 + 70.0 + offset, dir.y * 2.0)
		var inside := edge - r
		var height := clampf(inside / MENISCUS, 0.0, 1.0)
		var depth := smoothstep(0.0, 0.2, inside) * 0.8
		for st in streaks:
			var x0: float = st[0]
			var top: float = st[1]
			var bottom: float = st[2]
			var width: float = st[3]
			if p.y < top or p.y > bottom + width * 2.0:
				continue
			var along := clampf((p.y - top) / maxf(bottom - top, 1e-3), 0.0, 1.0)
			var cx := x0 + 0.03 * _noise.get_noise_2d(x0 * 9.0 + offset, p.y * 6.0)
			var w := width * lerpf(1.0, 0.5, along)
			var stripe := w - absf(p.x - cx) * 1.5 if p.y <= bottom else -1.0
			var drop := width * 1.25 - Vector2((p.x - cx) * 1.5, p.y - bottom).length()
			var best := maxf(stripe, drop)
			if best > inside:
				inside = best
				height = clampf(best / maxf(w, 1e-3), 0.0, 1.0)
				depth = height * (0.65 if drop > stripe else 0.4)
		return Vector3(inside, height, depth)
	_bake(SMEAR_SIZE, "blood_smear_%d" % index, shape, stamps, false)


## [count] gotas despedidas, entre [reach] del centro, de radio [size] (las de lejos, más pequeñas
## y alargadas hacia fuera, hasta [stretch]).
func _scatter(stamps: Array[Array], count: int, reach: Vector2, size: Vector2, thick: float, stretch: Vector2) -> void:
	for i in count:
		var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		var t := _rng.randf()
		var dist := lerpf(reach.x, reach.y, t)
		stamps.append([dir * dist, dir, lerpf(size.y, size.x, t) * _rng.randf_range(0.6, 1.2), lerpf(stretch.x, stretch.y, t), thick])


## Salpicado fino: puntitos de neblina que han caído.
func _specks(stamps: Array[Array], count: int, reach: Vector2) -> void:
	for i in count:
		var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		stamps.append([dir * lerpf(reach.x, reach.y, sqrt(_rng.randf())), dir, _rng.randf_range(0.003, 0.009), 1.0, 0.3])


## [shape] da, para un punto en [-1, 1]², cuánto dentro de la mancha está (x, en radios; >0 dentro),
## la altura del líquido (y, 0..1, para la normal) y su grosor (z, 0..1, para el color). Las gotas
## de [stamps] ([centro, dirección, radio, estirado, grosor]) se estampan encima. Con [rim], el cerco
## seco del filo.
func _bake(size: Vector2i, name: String, shape: Callable, stamps: Array[Array], rim: bool) -> void:
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
			# Empapa la tierra a manchas donde es fina.
			var soak := 0.82 + 0.18 * _noise.get_noise_2d(p.x * 9.0 + 5.0, p.y * 9.0)
			var color := THIN.lerp(THICK, thick)
			color *= 0.92 + 0.12 * _noise.get_noise_2d(p.x * 6.0 + 3.0, p.y * 6.0)
			var alpha := lerpf(ALPHA.x * soak, ALPHA.y, thick)
			if rim:
				# El filo se seca antes: un cerco más oscuro y más cubierto.
				var ring := exp(-pow(inside[k] / 0.03, 2.0)) * (0.6 + 0.4 * _noise.get_noise_2d(p.x * 12.0, p.y * 12.0))
				color = color.lerp(RIM, ring * 0.35)
				alpha = lerpf(alpha, 0.8, ring * 0.3)
			color.a = alpha * cover
			albedo.set_pixel(x, y, color)
			orm.set_pixel(x, y, Color(1.0, lerpf(ROUGHNESS.x, ROUGHNESS.y, thick), 0.0))
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
