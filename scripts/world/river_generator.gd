class_name RiverGenerator extends RefCounted

## Enchufa el campo de ríos horneado en un VoxelGeneratorGraph ya cargado: busca los nodos con
## nombre de river_carve.tres por todas las subfunciones y les mete las imágenes y los parámetros.
##
## El grafo del terreno lleva la función de tallado siempre puesta, con imágenes neutras que no
## tallan nada. Aquí solo se sustituyen, así que un planeta sin ríos horneados sigue generando bien.

const DIST_NODE := "river_dist_map"
const BED_NODE := "river_bed_map"
const RANGE_NODE := "river_distance_m"
const SLOPE_NODE := "river_bank_slope"
const WALL_AMP_NODE := "river_wall_amplitude"
const WALL_MASK_NODE := "river_wall_mask"
const WALL_NOISE_NODE := "river_wall_noise"
const BLEND_NODE := "river_blend"
const SPHERE_NODE := "river_planet_sdf"

## Índices de parámetro de SdfSphereHeightmap: imagen, radio, factor.
const _P_IMAGE := 0
const _P_RADIUS := 1
const _P_FACTOR := 2


## Perfil de lluvia por latitud por defecto: seco en el ecuador y en los polos, húmedo en las franjas
## templadas. Coincide con los biomas del planeta Tierra del proyecto (desierto ecuatorial), y se
## puede sustituir entero desde el JSON.
const DEFAULT_RAIN := [
	[90.0, 0.15], [65.0, 0.5], [45.0, 1.2], [25.0, 0.5], [10.0, 0.35], [0.0, 0.3],
	[-10.0, 0.35], [-25.0, 0.5], [-45.0, 1.2], [-65.0, 0.5], [-90.0, 0.15],
]


## Hornea el campo de ríos de un planeta a partir de un generador SIN ríos (o con las imágenes
## neutras, que es lo mismo). Es la parte cara: unos siete segundos en un planeta de 30 km, así que
## el llamante debería cachear el resultado con RiverField.save_to.
##
## Devuelve {} si el planeta no tiene mar (sin nivel base no hay a dónde drenar) o si el generador no
## sabe hornear el mapa de alturas.
static func build_field(generator: VoxelGeneratorGraph, radius: float, sea_level_radius: float,
		height_range: float, cfg: Dictionary) -> Dictionary:
	if generator == null or not generator.has_method("bake_sphere_bumpmap"):
		return {}
	var size: Vector2i = cfg.get("hydrology_size", Vector2i(2048, 1024))
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	generator.bake_sphere_bumpmap(img, radius, -height_range, height_range)
	# El horneado deja la fila 0 en el polo SUR; el resto del pipeline asume el norte arriba, igual
	# que WorldMapBaker.
	img.flip_y()

	var height_min := -height_range
	var height_span := height_range * 2.0
	var sea_n := (sea_level_radius - radius - height_min) / height_span
	var rain: Array = cfg.get("rain_profile", DEFAULT_RAIN)

	# El valle es una V de pendiente 'bank_slope' que arranca en el lecho: solo puede subir
	# bank_slope * carve_range antes de que se acabe su alcance. Si la incisión es mayor, el valle
	# no llega a alcanzar el terreno y queda un escalón vertical de la diferencia en todo el borde.
	var incision := float(cfg.get("channel_incision", 25.0))
	var climb := float(cfg.get("bank_slope", 0.12)) * float(cfg.get("carve_range", 220.0))
	if incision > climb:
		push_warning(("[rivers] la incisión (%.0f m) supera lo que sube el talud en su alcance " +
			"(%.0f m): el valle acabará en un escalón de %.0f m. Sube bank_slope o carve_range, " +
			"o baja channel_incision.") % [incision, climb, incision - climb])

	var sol := RiverHydrology.solve(img.get_data().to_float32_array(), size, sea_n, radius, rain,
		int(cfg.get("dem_smooth_passes", 1)))
	var net := RiverHydrology.extract_channels(sol, size, sea_n, height_min, height_span, radius,
		cfg)
	if int(net.count) <= 0:
		return {}

	var field := RiverField.rasterize(net, size, radius, height_min, height_span, cfg)
	field.radius = radius
	field.height_min = height_min
	field.height_span = height_span
	field.carve_range = float(cfg.get("carve_range", 220.0))
	field.bank_slope = float(cfg.get("bank_slope", 0.12))
	field.blend_range = float(cfg.get("blend_range", 60.0))
	field.wall_amplitude = float(cfg.get("wall_amplitude", 18.0))
	field.wall_period = float(cfg.get("wall_period", 140.0))
	field.wall_start = float(cfg.get("wall_start", 25.0))
	field.wall_full = float(cfg.get("wall_full", 90.0))
	return field


## Parchea con el campo horneado cualquier grafo que lleve los nodos con nombre: sirve tanto para el
## generador del terreno (que lleva la función de tallado entera) como para los grafos de vegetación,
## que llevan una reconstrucción reducida del valle para saber dónde cae la superficie tallada.
## Devuelve true si encontró algo que parchear.
##
## 'target' puede ser un VoxelGeneratorGraph o una VoxelGraphFunction suelta: los grafos de densidad
## del VoxelInstancer son lo segundo.
static func apply(target, field: Dictionary) -> bool:
	if target == null:
		return false
	var root: VoxelGraphFunction = (target.get_main_function()
		if target is VoxelGeneratorGraph else target)
	if root == null:
		return false
	var functions: Array = [root]
	_gather(root, functions)

	var dist_fn := _owner(functions, DIST_NODE)
	if dist_fn == null:
		return false

	var radius := float(field.radius)
	var span := float(field.height_span)
	var dist := dist_fn.find_node_by_name(DIST_NODE)
	dist_fn.set_node_param(dist, _P_IMAGE, field.dist)
	dist_fn.set_node_param(dist, _P_RADIUS, radius)
	dist_fn.set_node_param(dist, _P_FACTOR, float(field.carve_range))

	# El lecho se mide hacia ABAJO desde el techo del rango (factor negativo), para que el valor
	# neutro sea 0. Si radio y factor no cuadran con los del horneado, los ríos salen a otra altura
	# que el terreno del que se dedujeron. Solo lo lleva el grafo del terreno.
	var bed_fn := _owner(functions, BED_NODE)
	if bed_fn != null:
		var bed := bed_fn.find_node_by_name(BED_NODE)
		bed_fn.set_node_param(bed, _P_IMAGE, field.bed)
		bed_fn.set_node_param(bed, _P_RADIUS, radius + float(field.height_min) + span)
		bed_fn.set_node_param(bed, _P_FACTOR, -span)

	# El alcance vive en dos sitios: como factor del muestreo de distancia y como término que
	# reconstruye los metros a partir del valor invertido. Tienen que ser el mismo número.
	var range_fn := _owner(functions, RANGE_NODE)
	if range_fn != null:
		range_fn.set_node_default_input_by_name(
			range_fn.find_node_by_name(RANGE_NODE), "b", float(field.carve_range))

	var slope_fn := _owner(functions, SLOPE_NODE)
	if slope_fn != null:
		slope_fn.set_node_default_input_by_name(
			slope_fn.find_node_by_name(SLOPE_NODE), "b", float(field.bank_slope))

	var blend_fn := _owner(functions, BLEND_NODE)
	if blend_fn != null:
		var blend := blend_fn.find_node_by_name(BLEND_NODE)
		blend_fn.set_node_param(blend, 0, 0.0)
		blend_fn.set_node_param(blend, 1, float(field.blend_range))

	# Rugosidad de las paredes del valle. Sin ella el talud es una V analítica perfecta.
	var amp_fn := _owner(functions, WALL_AMP_NODE)
	if amp_fn != null:
		amp_fn.set_node_default_input_by_name(amp_fn.find_node_by_name(WALL_AMP_NODE), "b",
			float(field.get("wall_amplitude", 18.0)))
	var mask_fn := _owner(functions, WALL_MASK_NODE)
	if mask_fn != null:
		var mask := mask_fn.find_node_by_name(WALL_MASK_NODE)
		mask_fn.set_node_param(mask, 0, float(field.get("wall_start", 25.0)))
		mask_fn.set_node_param(mask, 1, float(field.get("wall_full", 90.0)))
	var noise_fn := _owner(functions, WALL_NOISE_NODE)
	if noise_fn != null:
		var nid := noise_fn.find_node_by_name(WALL_NOISE_NODE)
		var res = noise_fn.get_node_param(nid, 0)
		if res != null:
			res.period = float(field.get("wall_period", 140.0))

	var sphere_fn := _owner(functions, SPHERE_NODE)
	if sphere_fn != null:
		sphere_fn.set_node_default_input_by_name(
			sphere_fn.find_node_by_name(SPHERE_NODE), "radius", radius)
	return true


static func _gather(fn: VoxelGraphFunction, acc: Array) -> void:
	for node_id in fn.get_node_ids():
		var info = fn.get_node_type_info(fn.get_node_type_id(node_id))
		if not (info is Dictionary and info.get("name", "") == "Function"):
			continue
		var sub = fn.get_node_param(node_id, 0)
		if sub is VoxelGraphFunction and not acc.has(sub):
			acc.append(sub)
			_gather(sub, acc)


static func _owner(functions: Array, node_name: String) -> VoxelGraphFunction:
	for fn in functions:
		if fn.find_node_by_name(node_name) > 0:
			return fn
	return null
