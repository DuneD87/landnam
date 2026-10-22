@tool
extends RefCounted

## Diseño determinista: tallos, frondes, hojas y pétalos son geometría opaca.
## Los LODs conservan las hojas terminales y subconjuntos de las demás.
## Las hojas se orientan hacia fuera de la copa y sus normales se curvan hacia la
## dirección radial: la planta se ilumina como un volumen y no como facetas sueltas.
const SPECIES := ["wood_fern", "royal_fern", "round_shrub", "willow_shrub",
	"flowering_shrub", "wild_asparagus", "broadleaf", "wildflowers",
	# Bioma nevado: taiga, tundra y alta montaña.
	"dwarf_juniper", "dwarf_birch", "heather", "cottongrass", "reindeer_lichen", "arctic_poppy",
	# Hierbas que se recogen (GroundPickup).
	"yarrow"]
const GRASS_SHADER = preload("res://shaders/grass_wind.gdshader")
## Ensanchado de las hojas supervivientes por LOD. grass_wind.gdshader usa el mismo
## factor para el morph continuo entre niveles (lod_width_growth).
const WIDTH_GROWTH := 1.23
## Pieza de cada vértice en COLOR.a, para las estaciones de grass_wind.gdshader.
const PART_LEAF := 1.0
const PART_STEM := 0.75
const PART_FLOWER := 0.5
## Paletas de las flores de los arbustos.
const FLOWER_PINK := [Color(0.88, 0.62, 0.76), Color(0.93, 0.78, 0.86), Color(0.80, 0.66, 0.88)]
const FLOWER_YELLOW := [Color(0.98, 0.84, 0.2), Color(0.95, 0.76, 0.14), Color(1.0, 0.9, 0.36)]
const FLOWER_WHITE := [Color(0.95, 0.94, 0.9), Color(0.9, 0.88, 0.95), Color(0.86, 0.78, 0.92)]
## Estaciones por especie (shaders/lib/season.gdshaderinc, grass_wind.gdshader):
##   kind: 0 nada, 1 herbácea (se agosta con la pradera), 2 arbusto caduco (cambia de color y pierde
##         la hoja), 3 perenne (solo sus flores).
##   autumn: colores de otoño de la hoja (primero, pleno y seco).
##   bloom: ventana de floración [centro, ancho] en fase local (0 = equinoccio de primavera). Fuera de
##          ella las flores (y sus tallos de flor) se cierran.
const SEASONS := {
	"wood_fern": {"kind": 1, "autumn": [Color(0.72, 0.6, 0.25), Color(0.66, 0.38, 0.16), Color(0.45, 0.3, 0.18)]},
	"royal_fern": {"kind": 1, "autumn": [Color(0.72, 0.6, 0.25), Color(0.66, 0.38, 0.16), Color(0.45, 0.3, 0.18)]},
	"round_shrub": {"kind": 2, "autumn": [Color(0.8, 0.6, 0.22), Color(0.72, 0.32, 0.14), Color(0.48, 0.3, 0.18)],
		"bloom": [0.12, 0.24]},
	"flowering_shrub": {"kind": 2, "autumn": [Color(0.85, 0.6, 0.25), Color(0.7, 0.28, 0.2), Color(0.48, 0.3, 0.2)],
		"bloom": [0.14, 0.3]},
	"willow_shrub": {"kind": 2, "autumn": [Color(0.82, 0.72, 0.3), Color(0.72, 0.55, 0.22), Color(0.5, 0.38, 0.22)],
		"bloom": [0.05, 0.16]},
	"wild_asparagus": {"kind": 3},
	"broadleaf": {"kind": 1, "bloom": [0.2, 0.26]},
	"wildflowers": {"kind": 1, "bloom": [0.14, 0.34]},
	"dwarf_juniper": {"kind": 3, "bloom": [0.0, 2.0]},
	"dwarf_birch": {"kind": 2, "autumn": [Color(0.84, 0.4, 0.14), Color(0.74, 0.24, 0.12), Color(0.5, 0.25, 0.15)]},
	"heather": {"kind": 3, "bloom": [0.42, 0.24]},
	"cottongrass": {"kind": 1, "bloom": [0.3, 0.3]},
	"reindeer_lichen": {"kind": 0},
	"arctic_poppy": {"kind": 1, "bloom": [0.28, 0.26]},
	"yarrow": {"kind": 1, "bloom": [0.26, 0.36]},
}
static var _cache: Dictionary = {}

var _leaves: Array = []
var _stems: Array = []
var _rng := RandomNumberGenerator.new()
var _height: float = 1.0
# Copa como elipsoide: normales de volumen y oscurecimiento del interior.
var _canopy_center := Vector3(0.0, 0.5, 0.0)
var _canopy_size := Vector3(0.5, 0.5, 0.5)
# Copa en lóbulos (centros y semiejes), para las matas leñosas; vacía, la copa es el elipsoide.
var _lobe_centers := PackedVector3Array()
var _lobe_sizes := PackedVector3Array()
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
		"yarrow":
			builder._yarrow()
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
	_season_parameters(material, species)
	return material


func _season_parameters(material: ShaderMaterial, species: String) -> void:
	var season: Dictionary = SEASONS[species]
	material.set_shader_parameter("season_kind", season.kind)
	if season.has("autumn"):
		material.set_shader_parameter("autumn_early", season.autumn[0])
		material.set_shader_parameter("autumn_late", season.autumn[1])
		material.set_shader_parameter("autumn_withered", season.autumn[2])
	if season.has("bloom"):
		material.set_shader_parameter("bloom_center", season.bloom[0])
		material.set_shader_parameter("bloom_width", season.bloom[1])
	# Hoja media de la especie (lineal), la de los colores de otoño.
	var luma := 0.0
	var chroma := 0.0
	var count := 0
	for leaf in _leaves:
		if leaf.part != PART_LEAF:
			continue
		var c: Color = leaf.color.srgb_to_linear()
		luma += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
		chroma += c.g / maxf(c.r + c.g + c.b, 0.0001)
		count += 1
	if count > 0:
		material.set_shader_parameter("leaf_luma_ref", luma / count)
		material.set_shader_parameter("leaf_chroma_ref", chroma / count)


## tier: último LOD en el que sigue la hoja (-1 = aleatorio, mitad por nivel).
## segments: tramos en LOD0 (0 = los de por defecto según su anchura).
## part: PART_LEAF o PART_FLOWER (los pétalos se abren y cierran con las estaciones).
func _leaf(a: Vector3, b: Vector3, c: Vector3, width: float, color: Color,
		terminal: bool = false, facing: Vector3 = Vector3.UP, tier: int = -1,
		segments: int = 0, part: float = PART_LEAF) -> void:
	var seed: float = _rng.randf()
	if tier < 0:
		tier = 3 if terminal else 0
		if not terminal:
			var selection: int = _rng.randi()
			while tier < 3 and (selection & (1 << tier)) == 0:
				tier += 1
	_leaves.append({"a": a, "b": b, "c": c, "width": width, "color": color,
		"seed": seed, "tier": clampi(tier, 0, 3), "facing": facing, "segments": segments, "part": part})
	_height = maxf(_height, maxf(b.y, c.y))


## survival: último LOD en el que sigue el tallo. Los finos solo llegan a LOD1.
## part: PART_STEM, o PART_FLOWER para el tallo de una flor (se cierra con ella).
func _stem(a: Vector3, b: Vector3, width: float, color: Color, survival: int = -1,
		part: float = PART_STEM) -> void:
	if a.distance_squared_to(b) < 0.000001:
		return
	if survival < 0:
		survival = 1 if width < 0.008 else 3
	_stems.append({"a": a, "b": b, "width": width, "color": color, "survival": survival, "part": part})
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


## Mata redonda: una copa de varios bultos (lóbulos) y no una cúpula perfecta, con tallos leñosos
## desde la cepa que se ramifican hasta ramilletes de hojas (_branching_shrub).
func _round_shrub(flowers: bool) -> void:
	var leaf_color := Color(0.40, 0.56, 0.34) if flowers else Color(0.34, 0.52, 0.30)
	_volume_strength = 0.75
	_occlusion = 0.40
	_set_lobes(0.56 if flowers else 0.62, 0.92 if flowers else 0.95, 5 if flowers else 6)
	# El florido, algo menor y con el doble de racimos: menos sitios.
	var sites: Array = _branching_shrub({"sites": 56 if flowers else 62, "spacing": 0.17, "stems": 7, "crown": 0.08,
		"leaves": 10, "leaf_length": 0.11, "width_ratio": 0.6, "palette": [leaf_color],
		"wood": Color(0.34, 0.28, 0.20), "min_y": 0.12})
	var blossom_sites: Array = []
	for k in sites.size():
		var site: Dictionary = sites[k]
		if not site.outer or site.rise < -0.3:
			continue
		if flowers and site.rise > 0.0 and k % 3 == 0:
			_flower_cluster(site.tip + site.normal * 0.03, site.normal, site.tier)
		elif k % 3 == 1:
			blossom_sites.append(site)
	# Flor de primavera: el florido, más racimos rosas; el redondo, flor amarilla de retama. Al
	# final y no en el bucle: el generador es uno solo y la copa y sus hojas quedan como estaban.
	for site in blossom_sites:
		_flower_cluster(site.tip + site.normal * 0.03, site.normal, site.tier,
			FLOWER_PINK if flowers else FLOWER_YELLOW)


## Copa de un lóbulo central y [satellites] alrededor, a distintas alturas y tamaños: una mata
## real es un montón de bultos, y los de fuera bajan casi hasta el suelo. El elipsoide de
## _canopy_* pasa a ser el que envuelve a todos.
func _set_lobes(radius: float, height: float, satellites: int) -> void:
	_lobe_centers = PackedVector3Array([Vector3(_rng.randf_range(-0.06, 0.06) * radius, height * 0.56,
		_rng.randf_range(-0.06, 0.06) * radius)])
	_lobe_sizes = PackedVector3Array([Vector3(radius * 0.7, height * 0.4, radius * 0.7)])
	var start: float = _rng.randf() * TAU
	for i in satellites:
		var angle: float = start + (i + _rng.randf_range(-0.3, 0.3)) * TAU / satellites
		var spread: float = radius * _rng.randf_range(0.42, 0.56)
		var across: float = radius * _rng.randf_range(0.38, 0.52)
		_lobe_centers.append(Vector3(cos(angle) * spread, height * _rng.randf_range(0.28, 0.56), sin(angle) * spread))
		_lobe_sizes.append(Vector3(across, height * _rng.randf_range(0.26, 0.36), across * _rng.randf_range(0.8, 1.2)))
	var low := Vector3.INF
	var high := -Vector3.INF
	for i in _lobe_centers.size():
		low = low.min(_lobe_centers[i] - _lobe_sizes[i])
		high = high.max(_lobe_centers[i] + _lobe_sizes[i])
	low.y = maxf(low.y, 0.0)
	_canopy_center = (low + high) * 0.5
	_canopy_size = (high - low) * 0.5


## Mata leñosa sobre la copa de lóbulos: sitios de follaje repartidos por ella, un esqueleto que
## llega a cada uno y en cada sitio un ramillete de hojas. Ni hojas flotando ni una jaula de
## varillas rectas hasta una cáscara. Devuelve los sitios, para las flores.
func _branching_shrub(shape: Dictionary) -> Array:
	var sites: Array = _canopy_sites(shape.sites, shape.spacing, shape.min_y)
	_shrub_skeleton(sites, shape.stems, shape.crown, shape.wood)
	for site in sites:
		site["rise"] = (site.position.y - _canopy_center.y) / _canopy_size.y
		site["tier"] = _cluster_tier(site.outer)
		# Brotes altos más claros y cálidos; los bajos, más viejos y oscuros.
		var color: Color = _shade(shape.palette[_rng.randi() % shape.palette.size()], _rng.randf_range(-0.05, 0.06), 0.10)
		color = color.lerp(Color(0.54, 0.66, 0.38), clampf(site.rise, 0.0, 1.0) * 0.25)
		_spray(site, shape.leaves, shape.leaf_length * (1.0 if site.outer else 1.12), shape.width_ratio,
			color, shape.wood.lightened(0.1))
	return sites


## Sitios de follaje dentro de la copa de lóbulos. Tres de cada cuatro van cerca de la superficie
## de la unión y separados entre sí, para que la silueta no tenga calvas ni grumos; el resto
## rellena el interior, que se ve entre los huecos de cerca.
func _canopy_sites(count: int, spacing: float, min_y: float) -> Array:
	var weights: Array = []
	var total: float = 0.0
	for s in _lobe_sizes:
		total += s.x * s.y + s.y * s.z + s.x * s.z
		weights.append(total)
	var sites: Array = []
	var attempts: int = 0
	var budget: int = count * 80
	while sites.size() < count and attempts < budget:
		attempts += 1
		var outer: bool = sites.size() % 4 != 0
		var pick: float = _rng.randf() * total
		var lobe: int = 0
		while pick > weights[lobe]:
			lobe += 1
		# Reparto uniforme por área sobre la esfera, sin el fondo. Algún brote asoma de la silueta.
		var y: float = _rng.randf_range(-0.7, 1.0)
		var ring: float = sqrt(1.0 - y * y)
		var phi: float = _rng.randf() * TAU
		# Los ramilletes asoman hacia fuera de su sitio: los sitios van algo por dentro de la copa.
		var shell: float = _rng.randf_range(0.25, 0.6)
		if outer:
			shell = _rng.randf_range(0.95, 1.08) if _rng.randf() < 0.15 else _rng.randf_range(0.72, 0.92)
		var position: Vector3 = _lobe_centers[lobe] + Vector3(cos(phi) * ring, y, sin(phi) * ring) * _lobe_sizes[lobe] * shell
		# Fuera: tapado por otro lóbulo no dibuja la silueta.
		if position.y < min_y or (outer and _lobe_distance(position) < 0.7):
			continue
		# La separación se relaja poco a poco para no quedarse sin sitios.
		var gap: float = spacing * (1.0 - 0.5 * attempts / budget) * (1.0 if outer else 1.5)
		var crowded: bool = false
		for other in sites:
			if other.outer == outer and other.position.distance_to(position) < gap:
				crowded = true
				break
		if not crowded:
			sites.append({"position": position, "outer": outer, "normal": _lobe_normal(position)})
	return sites


## Esqueleto hasta cada sitio: un tallo desde la cepa por sector de la copa, que se ahorquilla en
## ramas hacia los grupos de sitios del sector, y de cada rama una ramilla por sitio. Guarda en el
## sitio el arranque de su ramilla.
func _shrub_skeleton(sites: Array, stems: int, crown: float, wood: Color) -> void:
	var start: float = _rng.randf() * TAU
	var azimuths: Array = []
	var groups: Array = []
	for s in stems:
		azimuths.append(start + (s + _rng.randf_range(-0.3, 0.3)) * TAU / stems)
		groups.append([])
	for site in sites:
		var angle: float = atan2(site.position.z, site.position.x)
		var best: int = 0
		for s in stems:
			if absf(angle_difference(angle, azimuths[s])) < absf(angle_difference(angle, azimuths[best])):
				best = s
		groups[best].append(site)
	for s in stems:
		if groups[s].is_empty():
			continue
		var root := Vector3(cos(azimuths[s]), 0.0, sin(azimuths[s])) * crown * _rng.randf_range(0.3, 1.0)
		var fork: Vector3 = root.lerp(_centroid(groups[s]), _rng.randf_range(0.36, 0.48))
		_bent_stem(root, fork, 0.028, wood, 3)
		for part in _split(groups[s], 2 if groups[s].size() < 7 else 3):
			var branch: Vector3 = fork.lerp(_centroid(part), _rng.randf_range(0.42, 0.58))
			_stem(fork, branch, 0.016, wood.lightened(0.06), 1)
			for site in part:
				site["branch"] = branch


## Tallo en dos tramos con el codo desplazado: las ramas leñosas no son rectas. El segundo tramo
## empieza con el grosor en el que acaba el primero.
func _bent_stem(a: Vector3, b: Vector3, width: float, color: Color, survival: int) -> void:
	var axis: Vector3 = b - a
	var bow := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.3, 0.6), _rng.randf_range(-1.0, 1.0))
	bow = (bow - axis.normalized() * bow.dot(axis.normalized())) * axis.length() * 0.09
	var elbow: Vector3 = a.lerp(b, 0.5) + bow
	_stem(a, elbow, width, color, survival)
	_stem(elbow, b, width * 0.6, color.lightened(0.04), survival)


func _centroid(sites: Array) -> Vector3:
	var sum := Vector3.ZERO
	for site in sites:
		sum += site.position
	return sum / sites.size()


## Reparte los sitios en k grupos por cercanía (k-medias con semillas alejadas entre sí).
func _split(sites: Array, k: int) -> Array:
	k = mini(k, sites.size())
	var centers: Array = [sites[0].position]
	while centers.size() < k:
		var farthest: Vector3 = centers[0]
		var farthest_distance: float = -1.0
		for site in sites:
			var distance: float = INF
			for center in centers:
				distance = minf(distance, site.position.distance_squared_to(center))
			if distance > farthest_distance:
				farthest_distance = distance
				farthest = site.position
		centers.append(farthest)
	var parts: Array = []
	for iteration in 4:
		parts = []
		for c in k:
			parts.append([])
		for site in sites:
			var best: int = 0
			for c in k:
				if site.position.distance_squared_to(centers[c]) < site.position.distance_squared_to(centers[best]):
					best = c
			parts[best].append(site)
		for c in k:
			if not parts[c].is_empty():
				centers[c] = _centroid(parts[c])
	return parts.filter(func(part: Array) -> bool: return not part.is_empty())


## Ramillete de un sitio: la ramilla sale de su rama, pasa por el sitio y asoma hacia fuera y
## arriba, con hojas pequeñas alternas que giran alrededor de ella, cada una con su inclinación.
## Así la silueta queda deshilachada, con brotes que asoman, y no una bola alicatada de hojas
## tumbadas. La terminal, una del medio y una de la base heredan el nivel del grupo (silueta
## lejana); las demás caen antes.
func _spray(site: Dictionary, count: int, length: float, width_ratio: float, color: Color,
		wood: Color) -> void:
	var normal: Vector3 = site.normal
	var axis: Vector3 = ((site.position - site.branch).normalized() + normal * 0.6 + Vector3.UP * 0.35
		+ Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.2, 0.3), _rng.randf_range(-0.35, 0.35))).normalized()
	var reach: float = length * 1.9
	var tip: Vector3 = site.position + axis * reach * 0.6
	site["tip"] = tip
	_stem(site.branch, tip, 0.006, wood, 0)
	var twig: Vector3 = tip - site.branch
	var leafy: float = clampf(reach / twig.length(), 0.35, 0.85)
	var frame: Array = _frame(twig.normalized())
	var azimuth: float = _rng.randf() * TAU
	for j in count:
		var base: Vector3 = site.branch.lerp(tip, 1.0 - float(j) / count * leafy)
		azimuth += PI * 0.85 + _rng.randf_range(-0.3, 0.3)
		var side: Vector3 = frame[0] * cos(azimuth) + frame[1] * sin(azimuth)
		var open: float = _rng.randf_range(0.2, 0.4) if j == 0 else _rng.randf_range(0.7, 1.15)
		var direction: Vector3 = (twig.normalized() * cos(open) + side * sin(open)).normalized()
		# La tierna de la punta, menor.
		var size: float = length * _rng.randf_range(0.75, 1.2) * (0.7 if j == 0 else 1.0)
		var end: Vector3 = base + direction * size - Vector3.UP * size * 0.12
		# Cada hoja busca la luz a su manera: cara hacia arriba y hacia fuera, con desorden.
		var facing: Vector3 = Vector3.UP + normal * 0.4 + Vector3(_rng.randf_range(-0.35, 0.35), 0.0, _rng.randf_range(-0.35, 0.35))
		facing -= direction * facing.dot(direction)
		if facing.length_squared() < 0.05:
			facing = side.cross(direction)
		facing = facing.normalized()
		var mid: Vector3 = base.lerp(end, 0.5) + facing * size * 0.12
		var tier: int = [site.tier, mini(site.tier, 2), mini(site.tier, 1), site.tier, 0, site.tier, 0,
			mini(site.tier, 1)][j] if j < 8 else 0
		_leaf(base, mid, end, size * width_ratio, color.lightened(_rng.randf_range(-0.04, 0.06)),
			false, facing, tier, 2)


## Sauce arbustivo: varas que salen de la cepa abiertas en abanico, cada una con su inclinación, y se
## arquean hacia fuera; algunas echan una rama lateral. Las hojas, estrechas y alternas en espiral
## sobre la vara (sin pares como un helecho), apuntan hacia la punta y cuelgan un poco.
func _willow_shrub() -> void:
	var color := Color(0.53, 0.65, 0.45)
	var wood := Color(0.36, 0.31, 0.21)
	_canopy_center = Vector3(0.0, 0.78, 0.0)
	_canopy_size = Vector3(0.62, 0.78, 0.62)
	_volume_strength = 0.5
	_occlusion = 0.30
	var catkin_sites: Array = []
	var rods: int = 12
	var start: float = _rng.randf() * TAU
	for rod in rods:
		var angle: float = start + (rod + _rng.randf_range(-0.4, 0.4)) * TAU / rods
		var direction := Vector3(cos(angle), 0, sin(angle))
		# Las más abiertas, más cortas.
		var lean: float = _rng.randf_range(0.12, 0.6)
		var height: float = _rng.randf_range(1.0, 1.5) * (1.0 - lean * 0.35)
		# Cepa ancha: las varas no salen todas del mismo punto, como una escoba.
		var root: Vector3 = direction * _rng.randf_range(0.03, 0.13)
		var control: Vector3 = root + direction * height * lean * 0.3 + Vector3.UP * height * 0.78
		var end: Vector3 = root + direction * height * (lean + 0.14) + Vector3.UP * height * 0.92
		var rod_color: Color = _shade(color, _rng.randf_range(-0.06, 0.05), 0.08)
		_rod(root, control, end, 0.026, wood, rod_color, 11, 0.3, 3)
		catkin_sites.append([root, control, end, direction])
		if rod % 3 == 1:
			var origin: Vector3 = _curve(root, control, end, 0.42)
			var out: Vector3 = direction.rotated(Vector3.UP, _rng.randf_range(0.5, 0.9) * (1.0 if rod % 2 else -1.0))
			_rod(origin, origin + out * height * 0.1 + Vector3.UP * height * 0.3,
				origin + out * height * 0.34 + Vector3.UP * height * 0.4, 0.014, wood.lightened(0.06), rod_color, 6, 0.0, 1)
	# Amentos de principios de primavera, colgando de la mitad alta de cada vara. Al final, como
	# las flores del arbusto redondo, para no mover el resto de la mata.
	for site in catkin_sites:
		for c in 4:
			var origin: Vector3 = _curve(site[0], site[1], site[2], 0.5 + c * 0.13)
			var side: Vector3 = site[3].rotated(Vector3.UP, (c % 2 - 0.5) * 2.2)
			var tip: Vector3 = origin + side * 0.03 - Vector3.UP * 0.07
			_leaf(origin, origin.lerp(tip, 0.5) + side * 0.01, tip, 0.022,
				Color(0.88, 0.85, 0.45).lightened(_rng.randf_range(-0.04, 0.06)), true, side, 1 if c < 2 else 0, 0, PART_FLOWER)


## Vara curva en tres tramos, con [leaves] hojas de sauce alternas en espiral desde [leaf_start]
## (fracción de la vara) hasta la punta. Las de la punta, más cortas y tiernas, duran más LODs.
## survival: último LOD de la vara; la punta, fina, cae uno antes.
func _rod(root: Vector3, control: Vector3, end: Vector3, width: float, wood: Color, leaf_color: Color,
		leaves: int, leaf_start: float, survival: int) -> void:
	var previous: Vector3 = root
	for step in range(1, 4):
		var point: Vector3 = _curve(root, control, end, step / 3.0)
		_stem(previous, point, width * (1.0 - (step - 1) * 0.28), wood.lightened(step * 0.04),
			survival if step < 3 else maxi(survival - 1, 0))
		previous = point
	var azimuth: float = _rng.randf() * TAU
	for i in leaves:
		var t: float = lerpf(leaf_start, 0.98, float(i) / (leaves - 1))
		var base: Vector3 = _curve(root, control, end, t)
		var tangent: Vector3 = ((control - root) * (1.0 - t) + (end - control) * t).normalized()
		azimuth += 2.4
		var frame: Array = _frame(tangent)
		var side: Vector3 = frame[0] * cos(azimuth) + frame[1] * sin(azimuth)
		var length_leaf: float = _rng.randf_range(0.28, 0.4) * lerpf(1.0, 0.75, t)
		var open: float = _rng.randf_range(0.55, 0.95)
		var direction: Vector3 = (tangent * cos(open) + side * sin(open)).normalized()
		# Sale hacia arriba y la punta cuelga.
		var tip: Vector3 = base + direction * length_leaf - Vector3.UP * length_leaf * 0.24
		var facing: Vector3 = Vector3.UP if absf(direction.y) < 0.9 else side
		_leaf(base, base.lerp(tip, 0.45) + Vector3.UP * length_leaf * 0.16, tip, length_leaf * 0.22,
			leaf_color.lightened(_rng.randf_range(-0.03, 0.07) + t * 0.05), i >= leaves - 2, facing)


## Esparraguera: una maraña de tallos finos que salen de la cepa, se arquean hacia fuera y caen,
## quebrados en zigzag en cada nudo, con ramillas cortas y penachos de cladodios finos como
## agujas. Una mata enredada y no un manojo de cañas derechas.
func _asparagus() -> void:
	var color := Color(0.51, 0.64, 0.39)
	_canopy_center = Vector3(0.0, 0.42, 0.0)
	_canopy_size = Vector3(0.6, 0.5, 0.6)
	_volume_strength = 0.3
	_occlusion = 0.25
	var canes: int = 10
	var start: float = _rng.randf() * TAU
	for cane in canes:
		var angle: float = start + (cane + _rng.randf_range(-0.4, 0.4)) * TAU / canes
		var radial := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-radial.z, 0, radial.x)
		var height: float = _rng.randf_range(0.55, 1.05)
		var reach: float = _rng.randf_range(0.25, 0.6)
		var root: Vector3 = radial * _rng.randf_range(0.02, 0.06)
		# Sube y se arquea hacia fuera; la punta cae.
		var control: Vector3 = root + radial * reach * 0.35 + Vector3.UP * height * 1.25
		var end: Vector3 = root + radial * reach + Vector3.UP * height * _rng.randf_range(0.55, 0.8)
		var cane_color: Color = _shade(color, _rng.randf_range(-0.05, 0.05), 0.08)
		var previous: Vector3 = root
		var nodes: int = 5
		for node in range(1, nodes + 1):
			var t: float = float(node) / nodes
			var zig: float = 1.0 if node % 2 else -1.0
			# Zigzag: cada nudo se aparta un poco a un lado y al otro.
			var point: Vector3 = _curve(root, control, end, t) + side * zig * 0.035 * t
			_stem(previous, point, lerpf(0.012, 0.006, t), cane_color.darkened(0.2), 3 if node < 3 else 1)
			var forward: Vector3 = (point - previous).normalized()
			# Ramilla en el nudo, hacia el lado del quiebro, con penachos a lo largo.
			var out: Vector3 = (forward * 0.5 + side * zig * 0.8 + Vector3.UP * 0.3).normalized()
			var twig_tip: Vector3 = point + out * _rng.randf_range(0.1, 0.18) * (1.2 - t * 0.5)
			_stem(point, twig_tip, 0.004, cane_color)
			for tuft in 4:
				_needle_tuft(point.lerp(twig_tip, 0.25 + tuft * 0.25), out, cane_color, tuft == 3)
			_needle_tuft(previous.lerp(point, 0.5), (forward + Vector3.UP * 0.3).normalized(), cane_color, false)
			previous = point
		_needle_tuft(previous, (end - control).normalized(), cane_color, true)


## Penacho de tres cladodios (las "hojas" de la esparraguera, finas como agujas) abiertos desde un
## punto hacia [direction].
func _needle_tuft(origin: Vector3, direction: Vector3, color: Color, terminal: bool) -> void:
	var frame: Array = _frame(direction)
	var start: float = _rng.randf() * TAU
	for needle in 3:
		var angle: float = start + needle * TAU / 3.0 + _rng.randf_range(-0.4, 0.4)
		var spread: Vector3 = frame[0] * cos(angle) + frame[1] * sin(angle)
		var size: float = _rng.randf_range(0.08, 0.12)
		var tip: Vector3 = origin + (direction + spread * 0.7).normalized() * size
		_leaf(origin, origin.lerp(tip, 0.55) + Vector3.UP * size * 0.15, tip, 0.014,
			color.lightened(_rng.randf_range(0, 0.10)), terminal and needle == 0)


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
	# Dos espigas de flor blanca y lila que salen del centro en primavera; el tallo se cierra con
	# ellas. Al final, para no mover las hojas.
	for spike in 2:
		var lean := Vector3(cos(spike * PI + 0.6), 0.0, sin(spike * PI + 0.6))
		var base := lean * 0.03 + Vector3.UP * 0.12
		var top: Vector3 = base + lean * 0.12 + Vector3.UP * (0.62 if spike == 0 else 0.5)
		_stem(base, top, 0.012, Color(0.42, 0.52, 0.32), 2, PART_FLOWER)
		var spike_color: Color = FLOWER_WHITE[_rng.randi() % FLOWER_WHITE.size()]
		for bloom in 7:
			var t: float = 0.45 + bloom * 0.08
			var side: Vector3 = lean.rotated(Vector3.UP, bloom * 2.4)
			_flower(base.lerp(top, t) + side * 0.03, 0.03, spike_color.lightened(_rng.randf_range(-0.04, 0.05)),
				(side + Vector3.UP * 0.6).normalized(), 2 if bloom % 2 == 0 else 1, 5)


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


## Enebro rastrero: brazos leñosos tumbados que serpentean a ras de suelo, cubiertos de ramillas en
## cepillo (acículas en verticilos de tres que apuntan hacia delante y arriba). Una alfombra baja e
## irregular, más alta cerca de la cepa, que asoma de la nieve, con alguna gálbula azul.
func _juniper() -> void:
	var needle := Color(0.21, 0.34, 0.29)
	var wood := Color(0.37, 0.27, 0.21)
	_canopy_center = Vector3(0.0, 0.14, 0.0)
	_canopy_size = Vector3(0.78, 0.26, 0.78)
	_volume_strength = 0.55
	_occlusion = 0.40
	var arms: int = 7
	var start: float = _rng.randf() * TAU
	for arm in arms:
		var heading: float = start + (arm + _rng.randf_range(-0.35, 0.35)) * TAU / arms
		var reach: float = _rng.randf_range(0.45, 0.78)
		var arm_color: Color = _shade(needle, _rng.randf_range(-0.05, 0.05), 0.06)
		var root := Vector3(cos(heading), 0.0, sin(heading)) * 0.03
		var lift: float = _rng.randf_range(0.8, 1.2)
		var fork: Vector3 = _creeping_arm(root, heading, reach, [0.17, 0.16, 0.12, 0.07], lift, 0.032, arm_color, wood)
		# Brazo secundario desde el primer codo, hacia el hueco entre este brazo y el siguiente.
		var turn: float = _rng.randf_range(0.5, 0.85) * (1.0 if arm % 2 == 0 else -1.0)
		_creeping_arm(fork, heading + turn, reach * 0.6, [0.15, 0.09], lift, 0.02, arm_color.lightened(0.03), wood)


## Brazo tumbado de enebro: tramos que serpentean siguiendo [heights] (sube desde la cepa y baja
## hasta apoyar la punta), con ramillas en cepillo a los lados y una hacia arriba que da espesor a
## la alfombra. Devuelve el primer codo, de donde sale el brazo secundario. Hasta cuatro tramos.
func _creeping_arm(point: Vector3, heading: float, reach: float, heights: Array, lift: float,
		width: float, color: Color, wood: Color) -> Vector3:
	var first_elbow: Vector3 = point
	var segments: int = heights.size()
	for segment in segments:
		heading += _rng.randf_range(-0.45, 0.45)
		var next: Vector3 = Vector3(point.x, 0.0, point.z) + Vector3(cos(heading), 0.0, sin(heading)) * reach / segments
		next.y = heights[segment] * lift
		var t: float = float(segment) / maxf(segments - 1, 1)
		# De lejos solo se ve la base de los brazos; lo demás queda bajo las acículas.
		_stem(point, next, lerpf(width, 0.016, t), wood.lightened(segment * 0.02), [3, 2, 1, 0][segment])
		var flat := Vector3(next.x - point.x, 0.0, next.z - point.z).normalized()
		# Junto a la cepa y en el brazo secundario, sin el cepillo hacia arriba.
		for brush in 3 if segments > 2 and segment > 0 else 2:
			var origin: Vector3 = point.lerp(next, [0.35, 0.8, 0.6][brush])
			var side_turn: float = _rng.randf_range(0.5, 1.0) * (1.0 if (brush + segment) % 2 == 0 else -1.0)
			var direction: Vector3 = flat.rotated(Vector3.UP, side_turn) + Vector3.UP * 0.45
			if brush == 2:
				direction = flat * 0.6 + Vector3.UP * 0.9
			var length: float = lerpf(0.21, 0.13, t) * _rng.randf_range(0.85, 1.15)
			_brush(origin, direction.normalized(), length, color, wood, _cluster_tier(brush != 2 or segment > 0))
		if segment == 0:
			first_elbow = next
		point = next
	_brush(point, (Vector3(cos(heading), 0.0, sin(heading)) + Vector3.UP * 0.35).normalized(), 0.14,
		color, wood, _cluster_tier(true))
	return first_elbow


## Ramilla en cepillo: un tallito con verticilos de tres acículas que se abren hacia delante. Las de
## la punta son las que más duran en los LODs.
func _brush(start: Vector3, direction: Vector3, length: float, color: Color, wood: Color, cluster_tier: int) -> void:
	var end: Vector3 = start + direction * length
	_stem(start, end, 0.007, wood.lightened(0.05), 0)
	var frame: Array = _frame(direction)
	var count: int = 0
	for whorl in 4:
		var base: Vector3 = start.lerp(end, 1.0 - whorl * 0.25)
		for k in 3:
			var angle: float = k * TAU / 3.0 + whorl * PI / 3.0 + _rng.randf_range(-0.3, 0.3)
			var side: Vector3 = frame[0] * cos(angle) + frame[1] * sin(angle)
			var needle_dir: Vector3 = (direction * 0.75 + side * 0.65 + Vector3.UP * 0.2).normalized()
			var size: float = _rng.randf_range(0.07, 0.1)
			var tip: Vector3 = base + needle_dir * size
			var tier: int = [cluster_tier, cluster_tier, mini(cluster_tier, 1), mini(cluster_tier, 1), mini(cluster_tier, 1),
				0, mini(cluster_tier, 1)][count] if count < 7 else 0
			_leaf(base, base.lerp(tip, 0.5) + Vector3.UP * size * 0.12, tip, 0.022,
				color.lightened(_rng.randf_range(0.0, 0.09)), false, side, tier, 2)
			count += 1
	if _rng.randf() < 0.2:
		_flower(end + Vector3.UP * 0.02, 0.016, Color(0.40, 0.47, 0.62), (direction + Vector3.UP).normalized(), 2, 3)


## Abedul enano de la tundra: mata baja y extendida de tallos rojizos muy ramificados y hojitas
## redondas, verdes en verano. El rojo y el naranja del otoño los pone el shader (SEASONS).
func _dwarf_birch() -> void:
	var palette := [Color(0.36, 0.52, 0.22), Color(0.43, 0.57, 0.25), Color(0.31, 0.47, 0.2),
		Color(0.5, 0.58, 0.26)]
	_volume_strength = 0.7
	_occlusion = 0.35
	_set_lobes(0.5, 0.56, 6)
	_branching_shrub({"sites": 62, "spacing": 0.15, "stems": 9, "crown": 0.1,
		"leaves": 6, "leaf_length": 0.075, "width_ratio": 0.85, "palette": palette,
		"wood": Color(0.36, 0.19, 0.15), "min_y": 0.06})


## Brezo: un cojín bajo y redondeado. Las puntas de los brotes cubren una cúpula, las del centro
## más altas; cada brote sale de la horquilla de un tallo leñoso de la cepa, tumbado y luego
## erguido si va hacia el borde, derecho si va al centro. Hojitas en escama a lo largo del brote y
## espigas malva en la punta.
func _heather() -> void:
	var leaf := Color(0.24, 0.33, 0.19)
	var flowers := [Color(0.74, 0.44, 0.68), Color(0.83, 0.57, 0.77), Color(0.66, 0.36, 0.62)]
	var wood := Color(0.36, 0.25, 0.20)
	_canopy_center = Vector3(0.0, 0.2, 0.0)
	_canopy_size = Vector3(0.36, 0.26, 0.36)
	_volume_strength = 0.45
	_occlusion = 0.3
	var radius: float = 0.4
	var height: float = 0.36
	var stems: int = 6
	var start: float = _rng.randf() * TAU
	var forks: Array = []
	for stem in stems:
		var angle: float = start + (stem + _rng.randf_range(-0.3, 0.3)) * TAU / stems
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var fork: Vector3 = direction * _rng.randf_range(0.05, 0.1) + Vector3.UP * _rng.randf_range(0.03, 0.05)
		_stem(direction * _rng.randf_range(0.0, 0.02), fork, 0.016, wood.darkened(0.1), 2)
		forks.append(fork)
	var shoots: int = 26
	for shoot in shoots:
		# Girasol: puntas repartidas por igual sobre el disco, con algo de desorden.
		var phi: float = shoot * 2.399963 + _rng.randf_range(-0.3, 0.3)
		var reach: float = radius * sqrt((shoot + _rng.randf_range(0.2, 0.8)) / shoots)
		var top := Vector3(cos(phi), 0.0, sin(phi)) * reach
		top.y = maxf(height * sqrt(maxf(1.0 - pow(reach / radius, 2.0), 0.0)) * _rng.randf_range(0.85, 1.05), 0.1)
		var fork: Vector3 = forks[0]
		for candidate in forks:
			if Vector2(candidate.x - top.x, candidate.z - top.z).length() < Vector2(fork.x - top.x, fork.z - top.z).length():
				fork = candidate
		var control: Vector3 = Vector3(fork.x, 0.0, fork.z).lerp(Vector3(top.x, 0.0, top.z), 0.6) \
			+ Vector3.UP * lerpf(fork.y, top.y, 0.3)
		# De lejos el cojín son sus hojas y flores: los brotes solo se dibujan de cerca.
		var previous: Vector3 = fork
		for step in range(1, 3):
			var point: Vector3 = _curve(fork, control, top, step / 2.0)
			_stem(previous, point, 0.009, wood, 1 if step == 1 else 0)
			previous = point
		var spread: Vector3 = Vector3(top.x - fork.x, 0.0, top.z - fork.z).normalized()
		var up: Vector3 = (top - control).normalized()
		for level in 4:
			var point: Vector3 = _curve(fork, control, top, 0.2 + level * 0.12)
			_leaf_cluster(point, (spread + Vector3.UP).normalized(), 5, 0.05, 0.3,
				leaf.lightened(_rng.randf_range(0.0, 0.08)), 1 if level % 2 else 0)
		var color: Color = flowers[_rng.randi() % flowers.size()]
		for bud in 7:
			var point: Vector3 = _curve(fork, control, top, 0.66 + bud * 0.055)
			var side: Vector3 = spread.rotated(Vector3.UP, bud * 2.2)
			_flower(point + side * 0.016, 0.02, color.lightened(_rng.randf_range(-0.04, 0.08)),
				(side + up * 0.5).normalized(), 3 if bud % 2 == 0 else 1, 4)


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
				radius * 0.75, Color(0.95, 0.95, 0.92), true, _frame(out)[1], 3 if hair < 8 else 1, 0, PART_FLOWER)


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


## Milenrama: una roseta de hojas finas como plumas y tallos derechos con hojuelas, rematados por
## umbelas planas de florecillas blancas (alguna rosada). Se arranca para curar (GroundPickup).
func _yarrow() -> void:
	var green := Color(0.40, 0.55, 0.30)
	_canopy_center = Vector3(0.0, 0.28, 0.0)
	_canopy_size = Vector3(0.3, 0.45, 0.3)
	_volume_strength = 0.2
	_occlusion = 0.15
	# Roseta: hojas largas y estrechas con hojuelas a los lados, tumbadas.
	for basal in 7:
		var angle: float = basal * 2.399963
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-direction.z, 0.0, direction.x)
		var reach: float = _rng.randf_range(0.12, 0.18)
		var tip: Vector3 = direction * reach + Vector3.UP * 0.05
		_stem(direction * 0.01, tip, 0.004, green.darkened(0.15))
		for f in 5:
			var t: float = 0.25 + f * 0.15
			var base: Vector3 = (direction * 0.01).lerp(tip, t)
			for sign_side in [-1.0, 1.0]:
				var end: Vector3 = base + (side * sign_side + direction * 0.6).normalized() * 0.03 * (1.1 - t)
				_leaf(base, base.lerp(end, 0.5) + Vector3.UP * 0.006, end, 0.012,
					green.lightened(_rng.randf_range(-0.04, 0.06)), f == 4, Vector3.UP, -1, 1)
	# Tallos con su umbela.
	var stalks: int = 5
	for stalk in stalks:
		var angle: float = stalk * 2.399963 + 0.7
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var root: Vector3 = direction * _rng.randf_range(0.02, 0.07)
		var head: Vector3 = root + direction * _rng.randf_range(0.03, 0.07) + Vector3.UP * _rng.randf_range(0.36, 0.56)
		_stem(root, head, 0.006, green.darkened(0.2))
		for leaf_index in 3:
			var base: Vector3 = root.lerp(head, 0.25 + leaf_index * 0.18)
			var out: Vector3 = direction.rotated(Vector3.UP, 1.3 + leaf_index * 2.1)
			var end: Vector3 = base + out * 0.07 + Vector3.UP * 0.035
			_leaf(base, base.lerp(end, 0.5) + Vector3.UP * 0.01, end, 0.018, green, false, Vector3.UP, -1, 1)
		# Umbela: un corro aplastado de florecillas, la del centro algo más alta.
		var white: Color = Color(0.95, 0.94, 0.9) if stalk % 4 else Color(0.93, 0.80, 0.86)
		for flower in 9:
			var around: float = flower * 2.399963
			var r: float = 0.0 if flower == 0 else sqrt(float(flower) / 9.0) * 0.045
			var center: Vector3 = head + Vector3(cos(around) * r, -r * 0.35, sin(around) * r)
			_flower(center, 0.014, white.lightened(_rng.randf_range(-0.03, 0.04)), Vector3.UP,
				3 if flower < 3 else (2 if flower < 6 else 1), 5)


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
func _flower_cluster(center: Vector3, outward: Vector3, cluster_tier: int,
		palette: Array = FLOWER_PINK) -> void:
	var color: Color = palette[_rng.randi() % palette.size()]
	var frame: Array = _frame(outward)
	for f in 4:
		var angle: float = f * TAU / 3.0 + _rng.randf_range(-0.3, 0.3)
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
			center + outward * radius, radius * 0.65, color, true, facing, tier, 0, PART_FLOWER)
	# Centro cálido sin material ni draw call adicional.
	_leaf(center - frame[0] * radius * 0.20 + facing * 0.005,
		center + facing * 0.032 * radius / 0.07, center + frame[0] * radius * 0.20 + facing * 0.005,
		radius * 0.42, Color(0.79, 0.62, 0.28), true, facing, tier, 0, PART_FLOWER)


func _cluster_tier(outer: bool) -> int:
	if not outer:
		return 1 if _rng.randf() < 0.35 else 0
	var roll: float = _rng.randf()
	return 3 if roll < 0.45 else (2 if roll < 0.80 else (1 if roll < 0.95 else 0))


## Distancia normalizada a la copa de lóbulos: menor que 1 dentro de alguno, 1 en su superficie.
func _lobe_distance(position: Vector3) -> float:
	var best: float = INF
	for i in _lobe_centers.size():
		best = minf(best, ((position - _lobe_centers[i]) / _lobe_sizes[i]).length())
	return best


## Normal de la copa de lóbulos: mezcla suave de los gradientes de cada lóbulo, con más peso el que
## tiene el punto más dentro o más cerca de su superficie. Cada bulto se ilumina como un volumen
## y la junta entre dos no hace escalón.
func _lobe_normal(position: Vector3) -> Vector3:
	var nearest: float = _lobe_distance(position)
	var sum := Vector3.ZERO
	for i in _lobe_centers.size():
		var q: Vector3 = (position - _lobe_centers[i]) / _lobe_sizes[i]
		var gradient: Vector3 = q / _lobe_sizes[i]
		if gradient.length_squared() > 1e-8:
			sum += gradient.normalized() * exp(-8.0 * (q.length() - nearest))
	return sum.normalized() if sum.length_squared() > 1e-8 else Vector3.UP


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
				offset, packed, leaf.part)
	_vertex(leaf.c, normal, Vector2(0.5, leaf.seed), leaf.color * 1.08, Vector3.ZERO, packed, leaf.part)
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
	var q: Vector3 = _lobe_normal(position) if not _lobe_centers.is_empty() \
		else (position - _canopy_center) / (_canopy_size * _canopy_size)
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
			_vertex(along + offset, normal, Vector2(float(corner % 2), 0.5), stem.color, offset, packed,
				stem.part)
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
				n * radius, packed, stem.part)
	for face in sides:
		var next: int = (face + 1) % sides
		_triangle(base + face, base + next, base + sides + face)
		_triangle(base + next, base + sides + next, base + sides + face)


func _vertex(position: Vector3, normal: Vector3, uv: Vector2, color: Color,
		morph_offset: Vector3, packed: float, part: float) -> void:
	_v.append(position)
	_n.append(normal)
	_uv.append(uv)
	_uv2.append(Vector2(clampf(position.y / _height, 0, 1), 1.0))
	# COLOR no lleva la conversión source_color de los uniforms.
	var linear: Color = (color * _occlusion_at(position)).srgb_to_linear()
	linear.a = part
	_colors.append(linear)
	# CUSTOM0: desplazamiento respecto al eje de la hoja o tallo y niveles, para el
	# morph de LOD del shader (4 * LOD de la malla + último LOD de la pieza).
	_custom.append_array(PackedFloat32Array([morph_offset.x, morph_offset.y, morph_offset.z, packed]))


## Interior y base de la copa más oscuros: la luz no llega igual al centro de la mata.
func _occlusion_at(position: Vector3) -> float:
	if _occlusion <= 0.0:
		return 1.0
	var distance: float = _lobe_distance(position) if not _lobe_centers.is_empty() \
		else ((position - _canopy_center) / _canopy_size).length()
	var depth: float = clampf(1.0 - distance, 0.0, 1.0)
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
