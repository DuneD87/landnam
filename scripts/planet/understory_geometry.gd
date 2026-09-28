@tool
extends RefCounted

## Diseño determinista: tallos, frondes, hojas y pétalos son geometría opaca.
## Los LODs conservan las hojas terminales y subconjuntos de las demás.
## Las hojas se orientan hacia fuera de la copa y sus normales se curvan hacia la
## dirección radial: la planta se ilumina como un volumen y no como facetas sueltas.
const SPECIES := ["wood_fern", "royal_fern", "round_shrub", "willow_shrub",
	"flowering_shrub", "wild_asparagus", "broadleaf", "wildflowers",
	# Bioma nevado: taiga, tundra y alta montaña.
	"dwarf_juniper", "dwarf_birch", "heather", "cottongrass", "reindeer_lichen", "arctic_poppy"]
const GRASS_SHADER = preload("res://shaders/grass_wind.gdshader")
## Ensanchado de las hojas supervivientes por LOD. grass_wind.gdshader usa el mismo
## factor para el morph continuo entre niveles (lod_width_growth).
const WIDTH_GROWTH := 1.23
static var _cache: Dictionary = {}

var _leaves: Array = []
var _stems: Array = []
var _rng := RandomNumberGenerator.new()
var _height: float = 1.0
# Copa como elipsoide: normales de volumen y oscurecimiento del interior.
var _canopy_center := Vector3(0.0, 0.5, 0.0)
var _canopy_size := Vector3(0.5, 0.5, 0.5)
var _volume_strength: float = 0.0
var _occlusion: float = 0.0
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _colors := PackedColorArray()
var _custom := PackedFloat32Array()
var _indices := PackedInt32Array()


static func build(species: String) -> Array:
	if _cache.has(species):
		return _cache[species]
	if not species in SPECIES:
		push_error("Especie de sotobosque desconocida: " + species)
		return []
	var builder = new()
	builder._rng.seed = 7183 + SPECIES.find(species) * 7919
	match species:
		"wood_fern", "royal_fern":
			builder._fern(species == "royal_fern")
		"round_shrub", "flowering_shrub":
			builder._round_shrub(species == "flowering_shrub")
		"willow_shrub":
			builder._willow_shrub()
		"wild_asparagus":
			builder._asparagus()
		"broadleaf":
			builder._broadleaf()
		"wildflowers":
			builder._wildflowers()
		"dwarf_juniper":
			builder._juniper()
		"dwarf_birch":
			builder._dwarf_birch()
		"heather":
			builder._heather()
		"cottongrass":
			builder._cottongrass()
		"reindeer_lichen":
			builder._lichen()
		"arctic_poppy":
			builder._poppy()
	var material: ShaderMaterial = builder._material(species)
	var result: Array = []
	for lod in 4:
		result.append(builder._mesh(lod, material))
	_cache[species] = result
	return result


func _material(species: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.resource_name = species
	material.shader = GRASS_SHADER
	material.set_shader_parameter("use_vertex_color", true)
	material.set_shader_parameter("base_color", Color.WHITE)
	material.set_shader_parameter("tip_color", Color.WHITE)
	material.set_shader_parameter("ground_tint_amount", 0.0)
	material.set_shader_parameter("dry_amount", 0.0)
	material.set_shader_parameter("dry_patch_amount", 0.0)
	material.set_shader_parameter("dead_blade_ratio", 0.0)
	material.set_shader_parameter("wind_sheen", 0.08)
	material.set_shader_parameter("variation_value", 0.07)
	material.set_shader_parameter("blade_variation", 0.045)
	# Las hojas ya tienen pliegue y normales geométricas: no aplicarles la
	# curvatura ni la inclinación hacia el cielo de las cintas de hierba.
	material.set_shader_parameter("blade_curvature", 0.0)
	material.set_shader_parameter("near_normal_strength", 0.0)
	material.set_shader_parameter("distant_normal_strength", 0.06)
	material.set_shader_parameter("diffuse_wrap", 0.22)
	material.set_shader_parameter("transmission_strength", 0.35)
	material.set_shader_parameter("grass_height", _height)
	material.set_shader_parameter("bend_curve", 2.0)
	material.set_shader_parameter("wind_amplitude", 0.55 if "fern" in species or species == "cottongrass" else 0.35)
	material.set_shader_parameter("wind_speed", 0.18)
	material.set_shader_parameter("flutter_amount", 0.07)
	material.set_shader_parameter("ambient_intensity", 0.14)
	material.set_shader_parameter("ambient_color_top", Color(0.77, 0.85, 0.94))
	material.set_shader_parameter("ambient_color_bottom", Color(0.36, 0.40, 0.26))
	material.set_shader_parameter("planet_position", Vector3(0, -30000, 0))
	material.set_shader_parameter("light_direction", Vector3(0.4, 0.8, 0.3).normalized())
	material.set_shader_parameter("fade_start", 148.0)
	material.set_shader_parameter("fade_end", 176.0)
	material.set_shader_parameter("lod_width_growth", WIDTH_GROWTH)
	material.set_shader_parameter("volume_normal_both_faces", _volume_strength > 0.0)
	return material


## tier: último LOD en el que sigue la hoja (-1 = aleatorio, mitad por nivel).
## segments: tramos en LOD0 (0 = los de por defecto según su anchura).
func _leaf(a: Vector3, b: Vector3, c: Vector3, width: float, color: Color,
		terminal: bool = false, facing: Vector3 = Vector3.UP, tier: int = -1,
		segments: int = 0) -> void:
	var seed: float = _rng.randf()
	if tier < 0:
		tier = 3 if terminal else 0
		if not terminal:
			var selection: int = _rng.randi()
			while tier < 3 and (selection & (1 << tier)) == 0:
				tier += 1
	_leaves.append({"a": a, "b": b, "c": c, "width": width, "color": color,
		"seed": seed, "tier": clampi(tier, 0, 3), "facing": facing, "segments": segments})
	_height = maxf(_height, maxf(b.y, c.y))


## survival: último LOD en el que sigue el tallo. Los finos solo llegan a LOD1.
func _stem(a: Vector3, b: Vector3, width: float, color: Color, survival: int = -1) -> void:
	if a.distance_squared_to(b) < 0.000001:
		return
	if survival < 0:
		survival = 1 if width < 0.008 else 3
	_stems.append({"a": a, "b": b, "width": width, "color": color, "survival": survival})
	_height = maxf(_height, maxf(a.y, b.y))


func _fern(tall: bool) -> void:
	var count: int = 9 if tall else 11
	var leaf_color := Color(0.44, 0.62, 0.36) if tall else Color(0.38, 0.56, 0.32)
	_canopy_center = Vector3(0.0, 0.28 if tall else 0.22, 0.0)
	_canopy_size = Vector3(0.62, 0.62 if tall else 0.45, 0.62)
	_volume_strength = 0.35
	_occlusion = 0.30
	for frond in count:
		var angle: float = frond * TAU / count + _rng.randf_range(-0.12, 0.12)
		var radial := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-radial.z, 0, radial.x)
		var reach: float = _rng.randf_range(0.52, 0.82) * (0.8 if tall else 1.0)
		var top: float = _rng.randf_range(0.52, 0.82) * (1.65 if tall else 1.0)
		var root := radial * 0.05
		var control: Vector3 = radial * reach * 0.16 + Vector3.UP * top * 1.28
		var tip: Vector3 = radial * reach + Vector3.UP * top * 0.60
		# Cada fronde tiene su propio tono: unas más viejas y oscuras, otras tiernas.
		var frond_color: Color = _shade(leaf_color, _rng.randf_range(-0.07, 0.06), 0.10)
		var previous: Vector3 = root
		for step in range(1, 6):
			var point := _curve(root, control, tip, step / 5.0)
			_stem(previous, point, 0.011, frond_color.darkened(0.18))
			previous = point
		var pairs: int = 9 if tall else 11
		for pair in pairs:
			var t: float = 0.15 + float(pair) / float(pairs) * 0.78
			var center := _curve(root, control, tip, t)
			var span: float = reach * 0.40 * pow(1.0 - t, 0.55)
			for sign_side in [-1.0, 1.0]:
				var direction: Vector3 = side * sign_side + radial * 0.42
				# Pinnas algo arqueadas: la punta cae un poco por debajo del raquis.
				var end: Vector3 = center + direction * span - Vector3.UP * span * 0.10
				var mid: Vector3 = center.lerp(end, 0.55) + Vector3.UP * span * 0.22
				_leaf(center, mid, end, span * (0.34 if tall else 0.27),
					frond_color.lightened(_rng.randf_range(0, 0.08) + t * 0.05), pair == 1)
		var start := _curve(root, control, tip, 0.82)
		_leaf(start, start.lerp(tip, 0.5) + Vector3.UP * 0.025, tip,
			0.045, frond_color.lightened(0.10), true)


## Mata redonda: tallos leñosos abiertos desde la base y grupos de hojas pequeñas
## repartidos sobre un domo en dos capas. Las exteriores sobreviven más LODs
## porque son las que dibujan la silueta; las interiores solo rellenan de cerca.
func _round_shrub(flowers: bool) -> void:
	var leaf_color := Color(0.40, 0.56, 0.34) if flowers else Color(0.34, 0.52, 0.30)
	var wood := Color(0.34, 0.28, 0.20)
	var radius: float = 0.56
	var height: float = 0.92 if flowers else 0.98
	_canopy_center = Vector3(0.0, height * 0.55, 0.0)
	_canopy_size = Vector3(radius, height * 0.47, radius)
	_volume_strength = 0.75
	_occlusion = 0.40
	var forks: Array = []
	for trunk in 6:
		var angle: float = trunk * TAU / 6.0 + _rng.randf_range(-0.3, 0.3)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var fork: Vector3 = direction * radius * _rng.randf_range(0.26, 0.38) \
			+ Vector3.UP * height * _rng.randf_range(0.28, 0.40)
		_stem(direction * 0.035, fork, 0.026, wood)
		for branch in 2:
			var spread: Vector3 = direction.rotated(Vector3.UP, (branch - 0.5) * 0.9)
			var tip: Vector3 = fork + spread * radius * _rng.randf_range(0.30, 0.45) \
				+ Vector3.UP * height * _rng.randf_range(0.22, 0.42)
			_stem(fork, tip, 0.015, wood.lightened(0.08))
			forks.append(tip)
	var clusters: int = 62
	for k in clusters:
		# Espiral de Fibonacci sobre el domo, desde la copa hasta algo bajo el ecuador.
		var y: float = lerpf(0.97, -0.38, (k + 0.5) / clusters)
		var ring: float = sqrt(maxf(1.0 - y * y, 0.0))
		var phi: float = k * 2.399963 + _rng.randf_range(-0.2, 0.2)
		var outward := Vector3(cos(phi) * ring, y, sin(phi) * ring)
		var outer: bool = k % 4 != 0
		var shell: float = (1.0 if outer else 0.64) * _rng.randf_range(0.9, 1.06)
		var anchor: Vector3 = _canopy_center + outward * _canopy_size * shell
		anchor.y = maxf(anchor.y, 0.10)
		# Ramilla que asoma desde dentro de la copa: sin ella las hojas flotan, y
		# llevada hasta la horquilla dibujaba una jaula. De lejos no se ve.
		_stem(anchor.lerp(_closest(forks, anchor), 0.5), anchor, 0.006, wood.darkened(0.1), 0)
		var cluster_tier: int = _cluster_tier(outer)
		# Brotes altos más claros y cálidos; los bajos, más viejos y oscuros.
		var color: Color = _shade(leaf_color, _rng.randf_range(-0.05, 0.06), 0.10)
		color = color.lerp(Color(0.54, 0.66, 0.38), clampf(y, 0.0, 1.0) * 0.25)
		_leaf_cluster(anchor, outward, 6, 0.16 if outer else 0.18, 0.60, color, cluster_tier)
		if flowers and outer and y > 0.12 and k % 3 == 0:
			_flower_cluster(anchor + outward * 0.035, outward, cluster_tier)


## Sauce arbustivo: varas largas con hojas estrechas que cuelgan hacia fuera.
func _willow_shrub() -> void:
	var color := Color(0.53, 0.65, 0.45)
	var wood := Color(0.36, 0.31, 0.21)
	_canopy_center = Vector3(0.0, 0.78, 0.0)
	_canopy_size = Vector3(0.62, 0.78, 0.62)
	_volume_strength = 0.5
	_occlusion = 0.30
	for branch in 11:
		var angle: float = branch * 2.399963 + _rng.randf_range(-0.25, 0.25)
		var direction := Vector3(cos(angle), 0, sin(angle))
		var height: float = _rng.randf_range(0.68, 1.12) * 1.3
		var reach: float = _rng.randf_range(0.32, 0.68)
		var root: Vector3 = direction * 0.055
		var knee: Vector3 = direction * reach * 0.28 + Vector3.UP * height * 0.42
		var end: Vector3 = direction * reach + Vector3.UP * height
		var branch_color: Color = _shade(color, _rng.randf_range(-0.06, 0.05), 0.08)
		_stem(root, knee, 0.028, wood)
		_stem(knee, end, 0.019, wood.lightened(0.08))
		for node in 6:
			var t: float = 0.05 + node * 0.18
			var origin: Vector3 = knee.lerp(end, t)
			for sign_side in [-1.0, 1.0]:
				var lateral: Vector3 = direction.rotated(Vector3.UP, sign_side * 0.95)
				var shoot: Vector3 = origin + lateral * 0.17 + Vector3.UP * 0.06
				_stem(origin, shoot, 0.006, wood.lightened(0.16))
				var length_leaf: float = _rng.randf_range(0.20, 0.28) * 1.45
				# Hoja de sauce: sale hacia arriba y la punta cuelga.
				var tip: Vector3 = shoot + lateral * length_leaf - Vector3.UP * length_leaf * 0.22
				_leaf(shoot, shoot.lerp(tip, 0.45) + Vector3.UP * length_leaf * 0.30, tip,
					length_leaf * 0.24, branch_color.lightened(_rng.randf_range(-0.03, 0.07) + t * 0.04),
					node == 5, (lateral * 0.35 + Vector3.UP).normalized())
		_leaf(end - Vector3.UP * 0.04, end + Vector3.UP * 0.14,
			end + direction * 0.10 + Vector3.UP * 0.18, 0.10, branch_color.lightened(0.12), true)


func _asparagus() -> void:
	var color := Color(0.51, 0.64, 0.39)
	_canopy_center = Vector3(0.0, 0.62, 0.0)
	_canopy_size = Vector3(0.5, 0.75, 0.5)
	_volume_strength = 0.3
	_occlusion = 0.25
	for cane in 6:
		var angle: float = cane * 2.399963
		var radial := Vector3(cos(angle), 0, sin(angle))
		var height: float = _rng.randf_range(0.95, 1.48)
		var root: Vector3 = radial * 0.075
		var top: Vector3 = radial * 0.30 + Vector3.UP * height
		var cane_color: Color = _shade(color, _rng.randf_range(-0.05, 0.05), 0.08)
		_stem(root, top, 0.014, cane_color.darkened(0.2))
		for level in 5:
			var t: float = 0.28 + level * 0.14
			var center: Vector3 = root.lerp(top, t)
			for side in 3:
				var arm: Vector3 = radial.rotated(Vector3.UP, side * TAU / 3.0 + level * 0.7)
				var branch_tip: Vector3 = center + arm * (1.0 - t) * 0.52 + Vector3.UP * 0.12
				_stem(center, branch_tip, 0.004, cane_color)
				for tuft in 3:
					var bud: Vector3 = center.lerp(branch_tip, 0.35 + tuft * 0.30)
					for needle in 3:
						var needle_dir: Vector3 = arm.rotated(Vector3.UP, (needle - 1.0) * 0.60)
						var tip: Vector3 = bud + needle_dir * 0.14 + Vector3.UP * (0.05 + needle * 0.014)
						_leaf(bud, bud.lerp(tip, 0.55) + Vector3.UP * 0.045, tip,
							0.014, cane_color.lightened(_rng.randf_range(0, 0.10)), tuft == 2 and needle == 1)


## Roseta de hojas anchas: las exteriores son más viejas, grandes, oscuras y caídas;
## las del centro, tiernas y más erguidas. Hojas grandes con más tramos de curva.
func _broadleaf() -> void:
	var color := Color(0.40, 0.57, 0.38)
	_canopy_center = Vector3(0.0, 0.18, 0.0)
	_canopy_size = Vector3(0.55, 0.40, 0.55)
	_volume_strength = 0.40
	_occlusion = 0.35
	var leaves: int = 13
	for leaf in leaves:
		var age: float = 1.0 - float(leaf) / float(leaves - 1)
		var angle: float = leaf * 2.399963
		var radial := Vector3(cos(angle), 0, sin(angle))
		var height: float = lerpf(0.62, 0.34, age) * _rng.randf_range(0.9, 1.1)
		var reach: float = lerpf(0.34, 0.62, age) * _rng.randf_range(0.9, 1.08)
		var root: Vector3 = radial * 0.045
		var neck: Vector3 = radial * lerpf(0.08, 0.16, age) + Vector3.UP * height * 0.32
		var leaf_color: Color = _shade(color, lerpf(0.10, -0.06, age), 0.08)
		_stem(root, neck, 0.014, leaf_color.darkened(0.2))
		var tip: Vector3 = radial * reach + Vector3.UP * height * lerpf(0.95, 0.30, age)
		var mid: Vector3 = radial * reach * 0.45 + Vector3.UP * height * lerpf(1.35, 1.05, age)
		_leaf(neck, mid, tip, _rng.randf_range(0.20, 0.29) * lerpf(0.85, 1.08, age),
			leaf_color.lightened(_rng.randf_range(0, 0.06)), leaf % 3 == 0,
			(Vector3.UP + radial * 0.35).normalized(), -1, 4)


func _wildflowers() -> void:
	var green := Color(0.48, 0.61, 0.36)
	_canopy_center = Vector3(0.0, 0.30, 0.0)
	_canopy_size = Vector3(0.35, 0.45, 0.35)
	_volume_strength = 0.20
	_occlusion = 0.15
	for stalk in 9:
		var angle: float = stalk * 2.399963
		var direction := Vector3(cos(angle), 0, sin(angle))
		var root: Vector3 = direction * _rng.randf_range(0.06, 0.24)
		var head: Vector3 = root + direction * 0.12 + Vector3.UP * _rng.randf_range(0.40, 0.76)
		_stem(root, head, 0.009, green.darkened(0.18))
		for side in [-1.0, 1.0]:
			var base: Vector3 = root.lerp(head, 0.26 if side < 0.0 else 0.50)
			var end: Vector3 = base + direction.rotated(Vector3.UP, side * 1.1) * 0.18 + Vector3.UP * 0.06
			_leaf(base, base.lerp(end, 0.5) + Vector3.UP * 0.06, end, 0.055, green, true)
		_flower(head, 0.070, Color(0.90, 0.85, 0.68) if stalk % 3 else Color(0.68, 0.62, 0.79))


## Enebro rastrero: brazos leñosos tumbados en abanico, cubiertos de acículas cortas azuladas,
## con alguna gálbula azul. Una alfombra baja y ancha, que asoma de la nieve.
func _juniper() -> void:
	var needle := Color(0.21, 0.34, 0.29)
	var wood := Color(0.37, 0.27, 0.21)
	_canopy_center = Vector3(0.0, 0.14, 0.0)
	_canopy_size = Vector3(0.78, 0.26, 0.78)
	_volume_strength = 0.55
	_occlusion = 0.40
	for arm in 10:
		var angle: float = arm * TAU / 10.0 + _rng.randf_range(-0.25, 0.25)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var reach: float = _rng.randf_range(0.40, 0.66)
		var root: Vector3 = direction * 0.04
		var knee: Vector3 = direction * reach * 0.45 + Vector3.UP * _rng.randf_range(0.14, 0.26)
		var end: Vector3 = direction * reach + Vector3.UP * _rng.randf_range(0.10, 0.22)
		_stem(root, knee, 0.032, wood)
		_stem(knee, end, 0.02, wood.lightened(0.05))
		var arm_color: Color = _shade(needle, _rng.randf_range(-0.05, 0.05), 0.06)
		for node in 10:
			var t: float = 0.04 + node * 0.1
			var origin: Vector3 = knee.lerp(end, t) if t > 0.2 else root.lerp(knee, 0.6 + t * 2.0)
			for spray in 2:
				var outward: Vector3 = (direction + Vector3.UP * (0.4 + spray * 0.5) + Vector3(_rng.randf_range(-0.5, 0.5), 0.0,
					_rng.randf_range(-0.5, 0.5))).normalized()
				_leaf_cluster(origin + outward * 0.03, outward, 7, 0.13, 0.18,
					arm_color.lightened(_rng.randf_range(0.0, 0.09)), _cluster_tier(node > 1 and spray == 1))
				if spray == 1 and _rng.randf() < 0.18:
					_flower(origin + outward * 0.07, 0.016, Color(0.40, 0.47, 0.62), outward, 2, 3)


## Abedul enano de la tundra: mata baja de tallos rojizos y hojitas redondas en rojo y naranja
## de otoño, con alguna todavía verde.
func _dwarf_birch() -> void:
	var palette := [Color(0.74, 0.24, 0.12), Color(0.84, 0.40, 0.14), Color(0.62, 0.17, 0.13),
		Color(0.56, 0.54, 0.20)]
	var wood := Color(0.36, 0.19, 0.15)
	var radius: float = 0.46
	var height: float = 0.58
	_canopy_center = Vector3(0.0, height * 0.55, 0.0)
	_canopy_size = Vector3(radius, height * 0.47, radius)
	_volume_strength = 0.7
	_occlusion = 0.35
	var forks: Array = []
	for trunk in 8:
		var angle: float = trunk * TAU / 8.0 + _rng.randf_range(-0.3, 0.3)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var fork: Vector3 = direction * radius * _rng.randf_range(0.3, 0.5) + Vector3.UP * height * _rng.randf_range(0.3, 0.5)
		_stem(direction * 0.03, fork, 0.02, wood)
		var tip: Vector3 = fork + direction * radius * 0.35 + Vector3.UP * height * _rng.randf_range(0.2, 0.4)
		_stem(fork, tip, 0.012, wood.lightened(0.1))
		forks.append(tip)
	for k in 54:
		var y: float = lerpf(0.97, -0.3, (k + 0.5) / 54.0)
		var ring: float = sqrt(maxf(1.0 - y * y, 0.0))
		var phi: float = k * 2.399963 + _rng.randf_range(-0.2, 0.2)
		var outward := Vector3(cos(phi) * ring, y, sin(phi) * ring)
		var outer: bool = k % 4 != 0
		var anchor: Vector3 = _canopy_center + outward * _canopy_size * (1.0 if outer else 0.66)
		anchor.y = maxf(anchor.y, 0.08)
		_stem(anchor.lerp(_closest(forks, anchor), 0.5), anchor, 0.006, wood, 0)
		var color: Color = palette[_rng.randi() % palette.size()]
		_leaf_cluster(anchor, outward, 5, 0.065, 0.85, color.lightened(_rng.randf_range(-0.05, 0.08)),
			_cluster_tier(outer))


## Brezo: matorral bajo de tallos rectos con hojitas en escama y espigas de flores malva.
func _heather() -> void:
	var leaf := Color(0.24, 0.33, 0.19)
	var flowers := [Color(0.74, 0.44, 0.68), Color(0.83, 0.57, 0.77), Color(0.66, 0.36, 0.62)]
	_canopy_center = Vector3(0.0, 0.2, 0.0)
	_canopy_size = Vector3(0.36, 0.26, 0.36)
	_volume_strength = 0.45
	_occlusion = 0.3
	for stalk in 26:
		var angle: float = stalk * 2.399963
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var root: Vector3 = direction * _rng.randf_range(0.02, 0.26)
		var top: Vector3 = root + direction * 0.12 + Vector3.UP * _rng.randf_range(0.24, 0.40)
		_stem(root, top, 0.009, Color(0.36, 0.25, 0.20))
		for level in 4:
			var point: Vector3 = root.lerp(top, 0.14 + level * 0.13)
			_leaf_cluster(point, (direction + Vector3.UP).normalized(), 5, 0.05, 0.3,
				leaf.lightened(_rng.randf_range(0.0, 0.08)), 1 if level % 2 else 0)
		var color: Color = flowers[_rng.randi() % flowers.size()]
		for bud in 7:
			var point: Vector3 = root.lerp(top, 0.6 + bud * 0.06)
			var side: Vector3 = direction.rotated(Vector3.UP, bud * 2.2)
			_flower(point + side * 0.016, 0.02, color.lightened(_rng.randf_range(-0.04, 0.08)),
				(side + Vector3.UP * 0.5).normalized(), 3 if bud % 2 == 0 else 1, 4)


## Algodoncillo: macolla de hojas de junco arqueadas y tallos finos con el penacho blanco.
func _cottongrass() -> void:
	var green := Color(0.43, 0.50, 0.28)
	var straw := Color(0.62, 0.52, 0.30)
	_canopy_center = Vector3(0.0, 0.22, 0.0)
	_canopy_size = Vector3(0.3, 0.35, 0.3)
	_volume_strength = 0.2
	_occlusion = 0.2
	for blade in 14:
		var angle: float = blade * 2.399963
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var root: Vector3 = direction * 0.03
		var length: float = _rng.randf_range(0.24, 0.40)
		var tip: Vector3 = root + direction * length * 0.6 + Vector3.UP * length * 0.7
		var color: Color = green.lerp(straw, _rng.randf_range(0.0, 0.6))
		_leaf(root, root.lerp(tip, 0.5) + Vector3.UP * length * 0.25, tip, 0.02, color, blade % 3 == 0,
			(Vector3.UP + direction * 0.4).normalized())
	for head in 6:
		var angle: float = head * 2.399963 + 0.7
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var root: Vector3 = direction * 0.04
		var top: Vector3 = root + direction * _rng.randf_range(0.04, 0.12) + Vector3.UP * _rng.randf_range(0.38, 0.55)
		_stem(root, top, 0.009, Color(0.45, 0.47, 0.30))
		# Penacho: pelos blancos en todas direcciones, los de fuera hasta el LOD lejano.
		var radius: float = _rng.randf_range(0.055, 0.075)
		for hair in 22:
			var up: float = lerpf(-0.6, 1.0, _rng.randf())
			var ring: float = sqrt(maxf(1.0 - up * up, 0.0))
			var phi: float = _rng.randf() * TAU
			var out := Vector3(cos(phi) * ring, up, sin(phi) * ring)
			var center: Vector3 = top + Vector3.UP * radius * 0.6
			# La cara del pelo, perpendicular a él: paralela, la hoja se aplasta en una línea.
			_leaf(center, center + out * radius * 0.6 + Vector3.UP * 0.006, center + out * radius,
				radius * 0.75, Color(0.95, 0.95, 0.92), true, _frame(out)[1], 3 if hair < 8 else 1)


## Liquen de los renos: cojines gris verdoso claro de ramitas finas en forma de coral.
func _lichen() -> void:
	var pale := Color(0.80, 0.82, 0.71)
	_canopy_center = Vector3(0.0, 0.1, 0.0)
	_canopy_size = Vector3(0.32, 0.16, 0.32)
	_volume_strength = 0.6
	_occlusion = 0.35
	for mound in 5:
		var angle: float = mound * TAU / 5.0 + _rng.randf_range(-0.4, 0.4)
		var center: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * (0.0 if mound == 0 else _rng.randf_range(0.12, 0.2))
		var height: float = _rng.randf_range(0.36, 0.40) if mound == 0 else _rng.randf_range(0.14, 0.24)
		var color: Color = pale.lerp(Color(0.70, 0.76, 0.60), _rng.randf())
		var width: float = height * 0.9
		for branch in 30:
			# Puntas repartidas sobre la cúpula del cojín, no en un haz.
			var up: float = lerpf(0.25, 1.0, sqrt(_rng.randf()))
			var ring: float = sqrt(maxf(1.0 - up * up, 0.0))
			var phi: float = _rng.randf() * TAU
			var out := Vector3(cos(phi) * ring, up, sin(phi) * ring)
			var tip: Vector3 = center + out * Vector3(width, height, width)
			_stem(center + Vector3(out.x, 0.0, out.z) * width * 0.3, tip, 0.012, color.darkened(0.08), 2)
			for fork in 4:
				var spread: Vector3 = (out + Vector3(_rng.randf_range(-0.6, 0.6), 0.3, _rng.randf_range(-0.6, 0.6))).normalized()
				_leaf(tip, tip + spread * 0.025, tip + spread * 0.055, 0.024,
					color.lightened(_rng.randf_range(0.0, 0.1)), fork == 0, _frame(spread)[1], -1)


## Amapola ártica: roseta de hojas vellosas y tallos con la copa amarilla abierta al sol.
func _poppy() -> void:
	var leaf := Color(0.46, 0.53, 0.37)
	_canopy_center = Vector3(0.0, 0.12, 0.0)
	_canopy_size = Vector3(0.2, 0.2, 0.2)
	_volume_strength = 0.25
	_occlusion = 0.2
	for basal in 9:
		var angle: float = basal * 2.399963
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var tip: Vector3 = direction * _rng.randf_range(0.09, 0.14) + Vector3.UP * 0.05
		_leaf(direction * 0.01, direction * 0.06 + Vector3.UP * 0.06, tip, 0.035,
			leaf.lightened(_rng.randf_range(-0.03, 0.06)), basal % 3 == 0, (Vector3.UP + direction * 0.5).normalized())
	for stalk in 6:
		var angle: float = stalk * 2.399963 + 0.4
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var head: Vector3 = direction * _rng.randf_range(0.03, 0.08) + Vector3.UP * _rng.randf_range(0.2, 0.3)
		_stem(direction * 0.01, head, 0.009, Color(0.42, 0.48, 0.30))
		var color := Color(0.98, 0.84, 0.24).lerp(Color(0.98, 0.93, 0.62), _rng.randf_range(0.0, 0.5))
		_flower(head, 0.06, color, (Vector3.UP + direction * 0.35).normalized(), 3, 4)


## Grupo de hojas pequeñas alrededor de un brote, inclinadas hacia fuera y sin
## el reparto regular de una estrella. Las dos primeras heredan el nivel del grupo
## (silueta lejana) y las demás van cayendo en los LODs cercanos.
func _leaf_cluster(anchor: Vector3, outward: Vector3, count: int, length: float,
		width_ratio: float, color: Color, cluster_tier: int) -> void:
	var frame: Array = _frame(outward)
	var start: float = _rng.randf() * TAU
	for j in count:
		var angle: float = start + j * TAU / count + _rng.randf_range(-0.45, 0.45)
		var spread: Vector3 = frame[0] * cos(angle) + frame[1] * sin(angle)
		var size: float = length * _rng.randf_range(0.75, 1.2)
		var lift: float = _rng.randf_range(0.35, 0.8)
		var direction: Vector3 = (spread + outward * lift).normalized()
		var base: Vector3 = anchor + spread * size * 0.12
		var tip: Vector3 = base + direction * size - Vector3.UP * size * 0.12
		var mid: Vector3 = base.lerp(tip, 0.5) + outward * size * 0.14
		var tier: int = [cluster_tier, cluster_tier, mini(cluster_tier, 2), mini(cluster_tier, 1)][j] if j < 4 else 0
		_leaf(base, mid, tip, size * width_ratio, color.lightened(_rng.randf_range(-0.03, 0.05)),
			false, outward, tier, 2)


## Ramillete de flores pequeñas en la punta de un brote.
func _flower_cluster(center: Vector3, outward: Vector3, cluster_tier: int) -> void:
	var palette := [Color(0.88, 0.62, 0.76), Color(0.93, 0.78, 0.86), Color(0.80, 0.66, 0.88)]
	var color: Color = palette[_rng.randi() % palette.size()]
	var frame: Array = _frame(outward)
	for f in 5:
		var angle: float = f * TAU / 4.0 + _rng.randf_range(-0.3, 0.3)
		var offset: Vector3 = Vector3.ZERO if f == 0 else (frame[0] * cos(angle) + frame[1] * sin(angle)) * 0.045
		var tier: int = mini(cluster_tier, 3 if f == 0 else (2 if f < 3 else 1))
		_flower(center + offset + outward * _rng.randf_range(0.0, 0.015), 0.032,
			color.lightened(_rng.randf_range(-0.03, 0.06)), outward, tier, 4)


func _flower(center: Vector3, radius: float, color: Color, facing: Vector3 = Vector3.UP,
		tier: int = 3, petals: int = 5) -> void:
	var frame: Array = _frame(facing)
	for petal in petals:
		var angle: float = petal * TAU / petals
		var outward: Vector3 = frame[0] * cos(angle) + frame[1] * sin(angle)
		_leaf(center, center + outward * radius * 0.5 + facing * 0.025 * radius / 0.07,
			center + outward * radius, radius * 0.65, color, true, facing, tier)
	# Centro cálido sin material ni draw call adicional.
	_leaf(center - frame[0] * radius * 0.20 + facing * 0.005,
		center + facing * 0.032 * radius / 0.07, center + frame[0] * radius * 0.20 + facing * 0.005,
		radius * 0.42, Color(0.79, 0.62, 0.28), true, facing, tier)


func _cluster_tier(outer: bool) -> int:
	if not outer:
		return 1 if _rng.randf() < 0.35 else 0
	var roll: float = _rng.randf()
	return 3 if roll < 0.45 else (2 if roll < 0.80 else (1 if roll < 0.95 else 0))


func _closest(points: Array, target: Vector3) -> Vector3:
	var best: Vector3 = points[0]
	for point in points:
		if point.distance_squared_to(target) < best.distance_squared_to(target):
			best = point
	return best


## Dos ejes perpendiculares a una dirección.
func _frame(axis: Vector3) -> Array:
	var tangent: Vector3 = axis.cross(Vector3.UP)
	if tangent.length_squared() < 0.01:
		tangent = axis.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	return [tangent, axis.cross(tangent).normalized()]


## Variación de tono: value > 0 aclara y amarillea, < 0 oscurece y enfría un poco.
func _shade(color: Color, value: float, hue_shift: float) -> Color:
	var shaded: Color = color.lightened(value) if value >= 0.0 else color.darkened(-value)
	return shaded.lerp(Color(0.55, 0.60, 0.30) if value >= 0.0 else Color(0.24, 0.40, 0.30),
		absf(value) * hue_shift / 0.07)


func _mesh(lod: int, material: Material) -> ArrayMesh:
	_v.clear()
	_n.clear()
	_uv.clear()
	_uv2.clear()
	_colors.clear()
	_custom.clear()
	_indices.clear()
	for stem in _stems:
		# Ramitas muy finas no necesitan cilindros en los LODs distantes.
		if stem.survival >= lod:
			_append_stem(stem, lod)
	for leaf in _leaves:
		if leaf.tier >= lod:
			_append_leaf(leaf, lod)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_CUSTOM0] = _custom
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.surface_set_material(0, material)
	return mesh


func _append_leaf(leaf: Dictionary, lod: int) -> void:
	var segments: int = [3, 2, 2, 1][lod]
	var columns: int = 3 if lod < 2 else 2
	if leaf.width < 0.025:
		segments = 2 if lod == 0 else 1
		columns = 2
	elif leaf.segments > 0:
		segments = [leaf.segments, maxi(leaf.segments - 1, 1), maxi(leaf.segments - 2, 1), 1][lod]
	var width_gain: float = pow(WIDTH_GROWTH, lod)
	var packed: float = float(lod * 4 + leaf.tier)
	var base: int = _v.size()
	var first_index: int = _indices.size()
	var length_axis: Vector3 = (leaf.c - leaf.a).normalized()
	var side: Vector3 = length_axis.cross(leaf.facing)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var normal: Vector3 = side.cross(length_axis).normalized()
	for row in segments:
		# Una hoja de un solo tramo es un triángulo: su base va en la parte ancha
		# (t = 0,3) y no en el arranque, que mide un 13 % y la dejaba en astilla.
		var t: float = float(row) / segments if segments > 1 else 0.3
		var center := _curve(leaf.a, leaf.b, leaf.c, t)
		var tangent: Vector3 = ((leaf.b - leaf.a) * (1.0 - t) + (leaf.c - leaf.b) * t).normalized()
		var row_normal: Vector3 = side.cross(tangent).normalized()
		var profile: float = 0.13 + sin(PI * pow(t, 0.80)) * 0.87
		for column in columns:
			var u: float = float(column) / (columns - 1)
			var width: float = leaf.width * width_gain * profile
			var offset: Vector3 = side * (u - 0.5) * width
			offset += row_normal * (1.0 - absf(u * 2.0 - 1.0)) * width * 0.13
			var n: Vector3 = (row_normal + side * (u - 0.5) * 0.35).normalized()
			_vertex(center + offset, n, Vector2(u, leaf.seed), leaf.color * lerpf(0.83, 1.08, t),
				offset, packed)
	_vertex(leaf.c, normal, Vector2(0.5, leaf.seed), leaf.color * 1.08, Vector3.ZERO, packed)
	for row in segments - 1:
		for column in columns - 1:
			var a: int = base + row * columns + column
			_triangle(a, a + columns, a + 1)
			_triangle(a + 1, a + columns, a + columns + 1)
	var last: int = base + (segments - 1) * columns
	for column in columns - 1:
		_triangle(last + column, base + segments * columns, last + column + 1)
	_leaf_normals(base, first_index)
	_volume_normals(base, first_index)


func _leaf_normals(first_vertex: int, first_index: int) -> void:
	# Derivar la normal del pliegue y la curva realmente triangulados. La punta
	# antes heredaba la normal de la cuerda raíz->punta, orientada hacia arriba
	# incluso en hojas que caen. Cada hoja conserva sus vértices independientes.
	for vertex in range(first_vertex, _v.size()):
		_n[vertex] = Vector3.ZERO
	for offset in range(first_index, _indices.size(), 3):
		var a: int = _indices[offset]
		var b: int = _indices[offset + 1]
		var c: int = _indices[offset + 2]
		# Caras horarias: el producto vectorial convencional apunta hacia dentro.
		var face: Vector3 = (_v[c] - _v[a]).cross(_v[b] - _v[a])
		_n[a] += face
		_n[b] += face
		_n[c] += face
	for vertex in range(first_vertex, _v.size()):
		_n[vertex] = _n[vertex].normalized()


## Gira la hoja para que su cara mire hacia fuera de la copa y curva sus normales
## hacia la dirección radial del elipsoide. Con una mezcla menor que 1 la normal
## sigue en el mismo hemisferio que la cara, así que el orden de vértices vale.
func _volume_normals(first_vertex: int, first_index: int) -> void:
	if _volume_strength <= 0.0:
		return
	var mean_position := Vector3.ZERO
	var mean_normal := Vector3.ZERO
	for vertex in range(first_vertex, _v.size()):
		mean_position += _v[vertex]
		mean_normal += _n[vertex]
	mean_position /= float(_v.size() - first_vertex)
	if mean_normal.dot(_radial(mean_position)) < 0.0:
		for vertex in range(first_vertex, _v.size()):
			_n[vertex] = -_n[vertex]
		for offset in range(first_index, _indices.size(), 3):
			var b: int = _indices[offset + 1]
			_indices[offset + 1] = _indices[offset + 2]
			_indices[offset + 2] = b
	for vertex in range(first_vertex, _v.size()):
		_n[vertex] = (_n[vertex] + _radial(_v[vertex]) * _volume_strength).normalized()


## Normal del elipsoide de la copa en un punto (gradiente, no dirección al centro).
## Por debajo del centro no apunta hacia abajo: una hoja baja y tumbada quedaba de
## espaldas al cielo y salía negra. La luz de una planta llega sobre todo de arriba.
func _radial(position: Vector3) -> Vector3:
	var q: Vector3 = (position - _canopy_center) / (_canopy_size * _canopy_size)
	q.y = maxf(q.y, 0.0)
	if q.length_squared() < 0.000001:
		return Vector3.UP
	return (q.normalized() + Vector3.UP * 0.35).normalized()


func _append_stem(stem: Dictionary, lod: int) -> void:
	var direction: Vector3 = (stem.b - stem.a).normalized()
	var side: Vector3 = direction.cross(Vector3.FORWARD)
	if side.length_squared() < 0.001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var normal: Vector3 = side.cross(direction).normalized()
	var base: int = _v.size()
	var packed: float = float(lod * 4 + mini(stem.survival, 3))
	if lod == 3:
		# En pantalla ocupa menos de un píxel: una cinta conserva el tallo.
		for corner in 4:
			var along: Vector3 = stem.a if corner < 2 else stem.b
			var offset: Vector3 = side * stem.width * (0.7 if corner < 2 else 0.4) * (-1.0 if corner % 2 == 0 else 1.0)
			_vertex(along + offset, normal, Vector2(float(corner % 2), 0.5), stem.color, offset, packed)
		_triangle(base, base + 1, base + 2)
		_triangle(base + 1, base + 3, base + 2)
		return
	# Las ramitas finas no necesitan cuatro caras ni de cerca.
	var sides: int = 4 if lod == 0 and stem.width >= 0.008 else 3
	for ring in 2:
		var center: Vector3 = stem.a if ring == 0 else stem.b
		var radius: float = stem.width * (0.5 if ring == 0 else 0.30)
		for face in sides:
			var angle: float = TAU * face / sides
			var n: Vector3 = side * cos(angle) + normal * sin(angle)
			_vertex(center + n * radius, n, Vector2(float(face) / sides, 0.5), stem.color,
				n * radius, packed)
	for face in sides:
		var next: int = (face + 1) % sides
		_triangle(base + face, base + next, base + sides + face)
		_triangle(base + next, base + sides + next, base + sides + face)


func _vertex(position: Vector3, normal: Vector3, uv: Vector2, color: Color,
		morph_offset: Vector3, packed: float) -> void:
	_v.append(position)
	_n.append(normal)
	_uv.append(uv)
	_uv2.append(Vector2(clampf(position.y / _height, 0, 1), 1.0))
	# COLOR no lleva la conversión source_color de los uniforms.
	var linear: Color = (color * _occlusion_at(position)).srgb_to_linear()
	linear.a = 1.0
	_colors.append(linear)
	# CUSTOM0: desplazamiento respecto al eje de la hoja o tallo y niveles, para el
	# morph de LOD del shader (4 * LOD de la malla + último LOD de la pieza).
	_custom.append_array(PackedFloat32Array([morph_offset.x, morph_offset.y, morph_offset.z, packed]))


## Interior y base de la copa más oscuros: la luz no llega igual al centro de la mata.
func _occlusion_at(position: Vector3) -> float:
	if _occlusion <= 0.0:
		return 1.0
	var depth: float = clampf(1.0 - ((position - _canopy_center) / _canopy_size).length(), 0.0, 1.0)
	var low: float = clampf(1.0 - position.y / maxf(_canopy_center.y + _canopy_size.y, 0.01), 0.0, 1.0)
	return 1.0 - _occlusion * clampf(depth * 0.85 + low * 0.35, 0.0, 1.0)


func _triangle(a: int, b: int, c: int) -> void:
	var face: Vector3 = (_v[b] - _v[a]).cross(_v[c] - _v[a])
	if face.dot(_n[a] + _n[b] + _n[c]) > 0:
		_indices.append_array(PackedInt32Array([a, c, b]))
	else:
		_indices.append_array(PackedInt32Array([a, b, c]))


static func _curve(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)
