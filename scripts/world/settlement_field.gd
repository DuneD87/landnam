class_name SettlementField extends RefCounted

## Los poblados de un planeta: en qué puntas de las sendas hay uno (SettlementSites), el plano de cada
## uno (SettlementLayout) y el claro que abren en el bosque. Se calcula la primera vez que se carga el
## planeta, después de las sendas y sobre el terreno definitivo, y se guarda en caché como ellas.
## SettlementManager levanta las construcciones cuando el jugador se acerca.
##
## El claro: los árboles leen en su grafo de densidad (clear_vegetation) una imagen con la distancia con
## signo al borde del claro de cada poblado (el centro de la plaza y el radio de lo más lejano más
## clear_margin). Es una distancia a un círculo y se interpola bien salvo cerca del centro, donde no
## importa: con téxeles de unos 46 × 58 m, junto al borde el error es de una docena de metros a lo sumo
## (el claro sale algo irregular), y clear_margin lo cubre.

const FILE_MAGIC := "GVST"
## Va en la clave de la caché: hay que subirla también al cambiar cómo se traza (SettlementLayout).
const FILE_VERSION := 5
const TEMPLATE_DIR := "res://data/settlements/templates/"

## La imagen del claro (en la convención del nodo SdfSphereHeightmap, como TrailField). Guarda d, la
## distancia al borde del claro, de -CLEAR_NEAR (dentro) a CLEAR_FAR (lejos, el 0 neutro): un paso de
## medio metro en R8.
const CLEAR_SIZE := Vector2i(4096, 2048)
const CLEAR_FAR := 96.0
const CLEAR_NEAR := 32.0
## Los árboles vuelven del todo a esto del borde del claro (m).
const CLEAR_SOFT := 6.0

## Lo que se usa si settlement_settings (en el JSON del planeta) no lo trae.
const DEFAULTS := {
	"enabled": true,
	"seed": 1,
	# Parte de las puntas sueltas que lleva poblado, y distancia mínima entre dos (m).
	"fraction": 0.33,
	"min_spacing": 1500.0,
	# Sitios a un lado de las sendas: uno cada roadside_spacing m de trazo (0 = ninguno), apartado
	# roadside_setback m del eje; lleva poblado con probabilidad roadside_fraction. Las puntas mandan.
	"roadside_spacing": 0.0,
	"roadside_setback": 14.0,
	"roadside_fraction": 0.5,
	# Desnivel / distancia que se acepta en la plaza. Dentro de una huella, el desnivel puede llegar a
	# max_step (m) o a max_grade por su lado largo, lo que sea más: una iglesia de 16 m se sube a un
	# zócalo de 4 m, y una choza no pasa de 3.
	"max_slope": 0.25,
	"max_step": 3.0,
	"max_grade": 0.25,
	# Claro de los árboles más allá de lo más lejano del poblado (m).
	"clear_margin": 14.0,
	# SettlementManager: a qué distancia del centro se levanta y se quita (m).
	"load_distance": 600.0,
	"unload_distance": 800.0,
	# SettlementVillagers: a qué distancia del centro tiene gente (m; se va 60 m más allá).
	"villager_distance": 200.0,
}


## [cfg] con lo que falte de DEFAULTS.
static func settings(cfg: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate()
	out.merge(cfg, true)
	return out


## Las plantillas de TEMPLATE_DIR, por orden de nombre.
static func load_templates() -> Array[SettlementTemplate]:
	var out: Array[SettlementTemplate] = []
	if not DirAccess.dir_exists_absolute(TEMPLATE_DIR):
		return out
	var files := Array(ResourceLoader.list_directory(TEMPLATE_DIR))
	files.sort()
	for file: String in files:
		if file.ends_with(".tres") or file.ends_with(".res"):
			var t := load(TEMPLATE_DIR + file) as SettlementTemplate
			if t != null and t.weight > 0.0:
				out.append(t)
	return out


## Lo que cambia los planos de [templates]: las plantillas, sus prefabs y el contenido de sus
## blueprints. Va en la clave de la caché.
static func signature(templates: Array[SettlementTemplate]) -> String:
	var parts := PackedStringArray()
	for t in templates:
		parts.append("%s:%.3f:%d:%d:%.2f:%.2f" % [t.id, t.weight, t.count_min, t.count_max, t.plaza_radius,
			t.ring_depth])
		var prefabs: Array = [t.center]
		prefabs.append_array(t.buildings)
		for p: SettlementPrefab in prefabs:
			if p != null:
				var work := []
				for w in p.workplaces:
					work.append([w.kind, w.pose, w.indoor, w.size, w.stands, w.looks])
				parts.append("%s:%s:%s:%s:%s:%s" % [p.id, p.door, p.door_cell, p.foundation_material,
					FileAccess.get_md5(p.blueprint_path), var_to_str(work)])
	return "|".join(parts).sha256_text()


## Traza los poblados con el suelo de [generator] (el del terreno, ya compilado) en las puntas y a los
## lados de las sendas [trails] (TrailField). [sea_radius]: radio del mar (lo que queda por debajo no se
## pisa). {"radius", "villages": [planos de SettlementLayout.plan, con "site" (su índice entre los
## sitios: primero las puntas, luego los de al lado de la senda)], "stats"}. Lo caro (leer el suelo,
## ~0,15 ms por punto) va repartido en hilos.
static func build(generator: VoxelGenerator, trails: Dictionary, radius: float, sea_radius: float,
		templates: Array[SettlementTemplate], cfg: Dictionary) -> Dictionary:
	cfg = settings(cfg)
	var sites := SettlementSites.dead_ends(trails.strokes, radius)
	var dead_ends := sites.size()
	sites.append_array(SettlementSites.roadside(trails.strokes, radius, float(cfg.roadside_spacing),
		float(cfg.roadside_setback)))
	var lcfg := {"radius": radius, "sea_radius": sea_radius, "max_slope": float(cfg.max_slope),
		"max_step": float(cfg.max_step), "max_grade": float(cfg.max_grade)}
	var measures := {}
	var total_weight := 0.0
	for t in templates:
		total_weight += t.weight
		var prefabs: Array = [t.center]
		prefabs.append_array(t.buildings)
		for p: SettlementPrefab in prefabs:
			if p != null and not measures.has(p.id):
				measures[p.id] = p.measure()
	var lower := sea_radius
	var upper := radius + 4000.0

	# Primero el sorteo, y la plaza solo de los que salen: buscarla es lo caro.
	var chances := PackedFloat32Array()
	for i in sites.size():
		chances.append(float(cfg.fraction) if i < dead_ends else float(cfg.roadside_fraction))
	var rolled := SettlementSites.roll(chances, int(cfg.seed))
	var lock := Mutex.new()
	var centers: Array = []
	centers.resize(sites.size())
	var task := WorkerThreadPool.add_group_task(func(k: int) -> void:
		var probe := GroundProbe.new(generator, lower, upper)
		var site: Dictionary = sites[rolled[k]]
		var center := SettlementLayout.find_center(site, probe.radius_at, lcfg)
		if center.is_empty() and site.has("alt"):
			site = site.alt
			center = SettlementLayout.find_center(site, probe.radius_at, lcfg)
		if not center.is_empty():
			center.into = site.into
		lock.lock()
		centers[rolled[k]] = center
		lock.unlock(), rolled.size())
	WorkerThreadPool.wait_for_group_task_completion(task)
	var usable: Array = []
	var dirs: Array = []
	for i in rolled:
		if not (centers[i] as Dictionary).is_empty():
			usable.append(i)
			dirs.append(centers[i].dir)
	var picked := SettlementSites.space(dirs, radius, float(cfg.min_spacing))

	var plans: Array = []
	plans.resize(picked.size())
	var trail_distance := func(dir: Vector3) -> float: return TrailField.distance_at(trails, dir, "trees")
	task = WorkerThreadPool.add_group_task(func(k: int) -> void:
		var site: int = usable[picked[k]]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([int(cfg.seed), site])
		# La que toca por el sorteo y, si no cabe ahí, las demás por orden.
		var order: Array[SettlementTemplate] = [_choose(templates, total_weight, rng)]
		for t in templates:
			if t != order[0]:
				order.append(t)
		var probe := GroundProbe.new(generator, lower, upper)
		var plan := {}
		for template in order:
			plan = SettlementLayout.plan(template, centers[site], centers[site].into, measures,
				probe.radius_at, trail_distance, lcfg, rng)
			if not plan.is_empty():
				plan.site = site
				break
		lock.lock()
		plans[k] = plan
		lock.unlock(), picked.size())
	WorkerThreadPool.wait_for_group_task_completion(task)
	var villages: Array = []
	var buildings := 0
	for plan: Dictionary in plans:
		if not plan.is_empty():
			villages.append(plan)
			buildings += (plan.buildings as Array).size()
	return {"radius": radius, "villages": villages, "stats": {"ends": dead_ends,
		"roadside": sites.size() - dead_ends, "rolled": rolled.size(), "usable": usable.size(), "picked": picked.size(), "villages": villages.size(),
		"buildings": buildings}}


static func _choose(templates: Array[SettlementTemplate], total: float, rng: RandomNumberGenerator) -> SettlementTemplate:
	var roll := rng.randf() * total
	for t in templates:
		roll -= t.weight
		if roll < 0.0:
			return t
	return templates[-1]


## El índice del poblado de [field] más cercano a la dirección [dir], o -1 si no hay.
static func nearest(field: Dictionary, dir: Vector3) -> int:
	var best := -1
	var best_d := INF
	var villages: Array = field.get("villages", [])
	for i in villages.size():
		var d := (villages[i].center as Vector3).distance_squared_to(dir)
		if d < best_d:
			best_d = d
			best = i
	return best


## La plantilla de id [id] de las de TEMPLATE_DIR, o null.
static func template(id: StringName) -> SettlementTemplate:
	for t in load_templates():
		if t.id == id:
			return t
	return null


## El prefab de id [id] que usa alguna plantilla, o null.
static func prefab(id: StringName) -> SettlementPrefab:
	for t in load_templates():
		var prefabs: Array = [t.center]
		prefabs.append_array(t.buildings)
		for p: SettlementPrefab in prefabs:
			if p != null and p.id == id:
				return p
	return null


## La imagen del claro de los árboles de los poblados de [field] (ver CLEAR_SIZE). [margin]: lo que se
## aparta más allá de lo más lejano de cada poblado (m).
static func clearance_image(field: Dictionary, margin: float, size := CLEAR_SIZE) -> Image:
	var radius := float(field.radius)
	var w := size.x
	var h := size.y
	var data := PackedByteArray()
	data.resize(w * h)
	var span := CLEAR_FAR + CLEAR_NEAR
	for v: Dictionary in field.villages:
		var c: Vector3 = v.center
		var clear := float(v.extent) + margin
		var reach := clear + CLEAR_FAR
		var ang := reach / radius
		var lat := asin(clampf(c.y, -1.0, 1.0))
		var ya := int(floor(RiverField.node_v(sin(minf(lat + ang, PI * 0.5))) * h))
		var yb := int(ceil(RiverField.node_v(sin(maxf(lat - ang, -PI * 0.5))) * h))
		var xc := fposmod(0.5 - atan2(c.z, c.x) / TAU, 1.0) * w
		var cp := c * radius
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
				var p := Vector3(st * cos(lon), yy, -st * sin(lon)) * radius
				var d := p.distance_to(cp) - clear
				if d >= CLEAR_FAR:
					continue
				var value := int(clampf((CLEAR_FAR - d) / span, 0.0, 1.0) * 255.0 + 0.5)
				var i := y * w + xi
				data[i] = maxi(data[i], value)
	return Image.create_from_data(w, h, false, Image.FORMAT_R8, data)


## Distancia (m) al borde del claro en [dir], leída de [image] como la lee el grafo; CLEAR_FAR lejos.
static func clearance_distance(image: Image, dir: Vector3) -> float:
	var uv := Vector2(fposmod(0.5 - atan2(dir.z, dir.x) / TAU, 1.0), RiverField.node_v(dir.normalized().y))
	return CLEAR_FAR - (CLEAR_FAR + CLEAR_NEAR) * TrailField.sample(image, uv)


## Copia de [graph] (un grafo de densidad de vegetación) con la densidad a 0 dentro del claro de los
## poblados ([image], de clearance_image, en un planeta de [radius]) y entera a CLEAR_SOFT m de su borde.
static func clear_vegetation(graph: VoxelGraphFunction, image: Image, radius: float) -> VoxelGraphFunction:
	return TrailGenerator.multiply_density(graph, clearance_graph(image, radius))


## Función de x, y, z que da 0 dentro del claro y 1 a CLEAR_SOFT m de él. (SdfSphereHeightmap - esfera)
## vale -FACTOR·h con h el valor de la imagen, y d = CLEAR_FAR - (CLEAR_FAR + CLEAR_NEAR)·h. Mismo factor
## que las sendas (ver tools/build_trail_carve.gd: con imágenes en [0, 1] lee en todo el relieve).
static func clearance_graph(image: Image, radius: float) -> VoxelGraphFunction:
	var f := VoxelGraphFunction.new()
	var xyz := [
		f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(-800, 0)),
		f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(-800, 80)),
		f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(-800, 160)),
	]
	var sphere := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2(-600, -100))
	f.set_node_default_input_by_name(sphere, "radius", radius)
	var heights := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(-600, 100))
	f.set_node_param(heights, 0, image)
	f.set_node_param(heights, 1, radius)
	f.set_node_param(heights, 2, TrailGenerator.FACTOR)
	for i in 3:
		f.add_connection(xyz[i], 0, sphere, i)
		f.add_connection(xyz[i], 0, heights, i)
	var sample := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(-400, 0))
	f.add_connection(heights, 0, sample, 0)
	f.add_connection(sphere, 0, sample, 1)
	var scaled := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(-250, 0))
	f.add_connection(sample, 0, scaled, 0)
	f.set_node_default_input(scaled, 1, (CLEAR_FAR + CLEAR_NEAR) / TrailGenerator.FACTOR)
	var d := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2(-100, 0))
	f.add_connection(scaled, 0, d, 0)
	f.set_node_default_input(d, 1, CLEAR_FAR)
	var clear := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(50, 0))
	f.set_node_param(clear, 0, 0.0)
	f.set_node_param(clear, 1, CLEAR_SOFT)
	f.add_connection(d, 0, clear, 0)
	var out := f.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2(200, 0))
	f.set_node_name(out, "settlement_clearance")
	f.add_connection(clear, 0, out, 0)
	f.set("input_definitions", [["x", "InputX", 0], ["y", "InputY", 0], ["z", "InputZ", 0]])
	f.set("output_definitions", [["settlement_clearance", "CustomOutput", 0]])
	return f


## Guarda [field] con su clave de configuración.
static func save_to(field: Dictionary, path: String, key: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("[settlements] no se pudo escribir la caché en %s" % path)
		return
	f.store_string(FILE_MAGIC)
	f.store_32(FILE_VERSION)
	f.store_pascal_string(key)
	f.store_var({"radius": field.radius, "villages": field.villages, "stats": field.get("stats", {})})
	f.close()


## Los poblados cacheados, o {} si no hay o su clave no coincide.
static func load_from(path: String, key: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	if f.get_buffer(4).get_string_from_ascii() != FILE_MAGIC or f.get_32() != FILE_VERSION:
		return {}
	if f.get_pascal_string() != key:
		return {}
	var data: Variant = f.get_var()
	return data if data is Dictionary else {}


## El radio del suelo bajo una dirección, leído del generador como NewGameLanding (sin esperar a que el
## terreno cargue). Uno por hilo: cada uno lleva su búfer.
class GroundProbe:
	var _generator: VoxelGenerator
	var _buffer := VoxelBuffer.new()
	var _lower: float
	var _upper: float
	## El último suelo encontrado: los siguientes se buscan cerca de él.
	var _hint := NAN

	func _init(generator: VoxelGenerator, lower: float, upper: float) -> void:
		_generator = generator
		_lower = lower
		_upper = upper
		_buffer.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
		_buffer.create(2, 2, 2)

	## Radio del primer cruce de aire a suelo bajando por [dir], o NAN.
	func radius_at(dir: Vector3) -> float:
		var r := NAN
		if not is_nan(_hint):
			r = _search(dir, minf(_hint + 60.0, _upper), maxf(_hint - 60.0, _lower))
		if is_nan(r):
			r = _search(dir, _upper, _lower)
		if not is_nan(r):
			_hint = r
		return r

	func _search(dir: Vector3, upper: float, lower: float) -> float:
		var radius := upper
		var value := _sdf(dir * radius)
		if value <= 0.0:
			return NAN
		while radius > lower:
			var next := maxf(lower, radius - clampf(value * 0.8, 0.5, 64.0))
			var next_value := _sdf(dir * next)
			if next_value <= 0.0:
				var air := radius
				var solid := next
				for _i in 8:
					var middle := (air + solid) * 0.5
					if _sdf(dir * middle) > 0.0:
						air = middle
					else:
						solid = middle
				return (air + solid) * 0.5
			radius = next
			value = next_value
		return NAN

	func _sdf(point: Vector3) -> float:
		var cell := Vector3i(point.floor())
		_generator.generate_block(_buffer, cell, 0)
		var t := point - Vector3(cell)
		var rows := PackedFloat32Array()
		for z in 2:
			for y in 2:
				rows.append(lerpf(_buffer.get_voxel_f(0, y, z, VoxelBuffer.CHANNEL_SDF),
					_buffer.get_voxel_f(1, y, z, VoxelBuffer.CHANNEL_SDF), t.x))
		return lerpf(lerpf(rows[0], rows[1], t.y), lerpf(rows[2], rows[3], t.y), t.z)
