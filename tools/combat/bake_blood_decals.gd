extends SceneTree

## Hornea las texturas de la sangre en el suelo (BloodPool) en textures/combat/:
##   blood_pool.png         charco: borde irregular, más oscuro en el filo (donde se seca antes) y
##                          gotas sueltas alrededor
##   blood_pool_normal.png  el menisco del borde y el abombado de las gotas, para que brille como
##                          un líquido
##   blood_splat.png        salpicadura de las gotas que caen de una herida: una mancha y gotitas
##                          alargadas hacia fuera
##   blood_splat_normal.png
##   blood_smear.png        sangre sobre el cuerpo (BloodStains): la mancha del golpe arriba y
##                          regueros que bajan, cada uno con su gota al final (abajo en la imagen es
##                          hacia donde tira la gravedad)
##   blood_smear_normal.png
##
##   godot --headless --path . --script res://tools/combat/bake_blood_decals.gd
## Después, `godot --headless --path . --import` para importar los PNG nuevos.

const OUT := "res://textures/combat/"
const POOL_SIZE := 512
const SPLAT_SIZE := 256
const SMEAR_SIZE := Vector2i(256, 384)
## En sRGB, como se guarda el PNG: en lineal queda en ~0,15 de rojo, sangre fresca (más oscuro se
## pierde sobre la tierra con poca luz).
const BLOOD := Color(0.43, 0.025, 0.03)
## Anchura del borde del menisco (en radios de la textura) y cuánto inclina la normal.
const MENISCUS := 0.05
const NORMAL_STRENGTH := 0.022

var _noise := FastNoiseLite.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.fractal_octaves = 3

	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	# Charco: el radio del borde varía con la dirección (ruido sobre el círculo).
	var drops: Array[Vector3] = []
	for i in 18:
		var angle := rng.randf() * TAU
		var dir := Vector2(cos(angle), sin(angle))
		var edge := _pool_radius(dir)
		drops.append(Vector3(dir.x, dir.y, 0.0) * (edge + rng.randf_range(0.04, 0.3)) +
				Vector3(0, 0, rng.randf_range(0.008, 0.03)))
	_bake(Vector2i(POOL_SIZE, POOL_SIZE), "blood_pool", func(p: Vector2) -> Vector2:
		var r := p.length()
		var dir := p / maxf(r, 1e-5)
		# x: cuánto dentro del borde (>0 dentro), y: altura para la normal.
		var inside := _pool_radius(dir) - r
		var height := clampf(inside / MENISCUS, 0.0, 1.0)
		for d in drops:
			var to := p.distance_to(Vector2(d.x, d.y))
			var drop_inside := d.z - to
			if drop_inside > inside:
				inside = drop_inside
				height = sqrt(clampf(1.0 - (to / d.z) * (to / d.z), 0.0, 1.0))
		return Vector2(inside, height))

	# Salpicadura: mancha central y gotas que salen despedidas, más pequeñas y alargadas cuanto más
	# lejos, algunas en reguero.
	var splats: Array[Array] = []
	for i in 30:
		var angle := rng.randf() * TAU
		var dir := Vector2(cos(angle), sin(angle))
		var dist := rng.randf_range(0.3, 0.92)
		var radius := lerpf(0.07, 0.014, (dist - 0.3) / 0.62) * rng.randf_range(0.6, 1.2)
		splats.append([dir * dist, dir, radius, lerpf(1.2, 2.4, (dist - 0.3) / 0.62)])
	for i in 6:
		var angle := rng.randf() * TAU
		var dir := Vector2(cos(angle), sin(angle))
		for k in 4:
			var dist := 0.28 + k * 0.1 + rng.randf_range(-0.02, 0.02)
			splats.append([dir * dist, dir, 0.035 * (1.0 - k * 0.2), 1.6])
	_bake(Vector2i(SPLAT_SIZE, SPLAT_SIZE), "blood_splat", func(p: Vector2) -> Vector2:
		var r := p.length()
		var dir := p / maxf(r, 1e-5)
		var edge := 0.22 + 0.06 * _noise.get_noise_2d(dir.x * 2.0 + 40.0, dir.y * 2.0)
		var inside := edge - r
		var height := clampf(inside / MENISCUS, 0.0, 1.0)
		for s in splats:
			var center: Vector2 = s[0]
			var along: Vector2 = s[1]
			var radius: float = s[2]
			var stretch: float = s[3]
			var d := p - center
			# Elipse alargada hacia fuera.
			var q := Vector2(d.dot(along) / stretch, d.dot(along.orthogonal()))
			var to := q.length()
			var drop_inside := radius - to
			if drop_inside > inside:
				inside = drop_inside
				height = sqrt(clampf(1.0 - (to / radius) * (to / radius), 0.0, 1.0))
		return Vector2(inside, height))

	# Sobre el cuerpo: mancha arriba y regueros hacia abajo, que se afinan y acaban en gota. En
	# coordenadas de la imagen (y crece hacia abajo); la imagen es 2:3, así que en x se mide 1,5
	# veces más ancho que en y.
	var streaks: Array[Array] = []
	for i in 7:
		var x := rng.randf_range(-0.5, 0.5)
		streaks.append([x, rng.randf_range(-0.5, -0.3), rng.randf_range(-0.05, 0.85), rng.randf_range(0.035, 0.07)])
	var specks: Array[Vector3] = []
	for i in 12:
		var angle := rng.randf() * TAU
		specks.append(Vector3(cos(angle) * rng.randf_range(0.45, 0.85), -0.55 + sin(angle) * rng.randf_range(0.2, 0.35),
				rng.randf_range(0.015, 0.035)))
	_bake(SMEAR_SIZE, "blood_smear", func(p: Vector2) -> Vector2:
		var q := Vector2(p.x, (p.y + 0.55) * 1.5)
		var r := q.length()
		var dir := q / maxf(r, 1e-5)
		var edge := 0.38 + 0.1 * _noise.get_noise_2d(dir.x * 2.0 + 70.0, dir.y * 2.0)
		var inside := edge - r
		var height := clampf(inside / MENISCUS, 0.0, 1.0)
		for st in streaks:
			var x0: float = st[0]
			var top: float = st[1]
			var bottom: float = st[2]
			var width: float = st[3]
			if p.y < top or p.y > bottom + width * 2.0:
				continue
			# Se afina al bajar, con algo de vaivén, y acaba en una gota más gruesa.
			var along := clampf((p.y - top) / maxf(bottom - top, 1e-3), 0.0, 1.0)
			var cx := x0 + 0.03 * _noise.get_noise_2d(x0 * 9.0, p.y * 6.0)
			var w := width * lerpf(1.0, 0.55, along)
			var stripe := w - absf(p.x - cx) * 1.5 if p.y <= bottom else -1.0
			var drop := width * 1.25 - Vector2((p.x - cx) * 1.5, p.y - bottom).length()
			var best := maxf(stripe, drop)
			if best > inside:
				inside = best
				height = clampf(best / maxf(w, 1e-3), 0.0, 1.0)
		for sp in specks:
			var to := Vector2((p.x - sp.x) * 1.5, p.y - sp.y).length()
			if sp.z - to > inside:
				inside = sp.z - to
				height = sqrt(clampf(1.0 - (to / sp.z) * (to / sp.z), 0.0, 1.0))
		return Vector2(inside, height))
	print("Sangre horneada en ", OUT)
	quit()


func _pool_radius(dir: Vector2) -> float:
	return 0.56 + 0.17 * _noise.get_noise_2d(dir.x * 1.2, dir.y * 1.2) \
			+ 0.05 * _noise.get_noise_2d(dir.x * 3.5 + 10.0, dir.y * 3.5)


## [shape] da, para un punto en [-1, 1]², cuánto dentro de la mancha está (en radios; >0 dentro) y
## la altura del líquido (0..1) para la normal.
func _bake(size: Vector2i, name: String, shape: Callable) -> void:
	var albedo := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var heights := PackedFloat32Array()
	heights.resize(size.x * size.y)
	var pixel := 2.0 / size.x
	var pixel_y := 2.0 / size.y
	for y in size.y:
		for x in size.x:
			var p := Vector2((x + 0.5) * pixel - 1.0, (y + 0.5) * pixel_y - 1.0)
			var s: Vector2 = shape.call(p)
			var alpha := smoothstep(-pixel, pixel, s.x)
			# El filo se seca antes y queda más oscuro; dentro, algo de variación.
			var rim := 1.0 - smoothstep(0.0, 0.035, s.x)
			var tone := 0.88 + 0.22 * _noise.get_noise_2d(p.x * 6.0 + 3.0, p.y * 6.0)
			var color := BLOOD * tone
			color = color.lerp(Color(0.26, 0.01, 0.015), rim * 0.6)
			color.a = alpha * 0.97
			albedo.set_pixel(x, y, color)
			heights[y * size.x + x] = s.y * alpha
	albedo.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	# Normal (convención OpenGL, +Y arriba en la imagen) desde la altura.
	var normal := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for y in size.y:
		for x in size.x:
			var hx := heights[y * size.x + mini(x + 1, size.x - 1)] - heights[y * size.x + maxi(x - 1, 0)]
			var hy := heights[mini(y + 1, size.y - 1) * size.x + x] - heights[maxi(y - 1, 0) * size.x + x]
			var n := Vector3(-hx / (2.0 * pixel) * NORMAL_STRENGTH, hy / (2.0 * pixel_y) * NORMAL_STRENGTH, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	normal.save_png(ProjectSettings.globalize_path(OUT + name + "_normal.png"))
