class_name TerrainLeveling
extends RefCounted

## Allanar el terreno con la azada (ItemData.ToolType.HOE). Cada golpe acerca el suelo de un círculo
## a un plano perpendicular a la vertical del planeta: el de la mediana de las alturas de alrededor
## (los vóxeles vecinos) o, con el golpe cargado, el de los pies. Corta lo que sobresale y rellena lo
## hundido, gratis y como mucho STEP m por golpe, y el borde se funde con lo de fuera. Solo en suelo
## blando: la roca, el hielo, las menas y las cuevas son cosa del pico.
##
## El pincel es un VoxelGeneratorGraph que VoxelToolLodTerrain.do_graph pasa sobre la SDF que hay
## (InputSDF), en un marco con Y en la vertical y el origen en el centro del plano. Lo allanado se
## guarda con el terreno (VoxelStreamSQLite), como lo que excava el pico. El golpe
## (ActionController.level_ahead) y la vista previa (HoePreview) apuntan con el mismo aim().

## Radio que se allana del todo y radio donde se acaba el borde (m).
const RADIUS := 1.1
const EDGE := 1.9
## Parte de lo que le falta al suelo hasta el plano que recorre un golpe, con un tope (m).
const RATE := 0.7
const STEP := 0.5
## Alto del pincel sobre y bajo el plano (m): entero hasta DEPTH y a cero en DEPTH_EDGE. Es también
## lo que se busca el suelo de cada muestra hacia arriba y hacia abajo.
const DEPTH := 3.0
const DEPTH_EDGE := 4.0
## Hasta dónde llega la azada desde los pies (m).
const RANGE := 4.5
## Muestras de la altura de alrededor: [radio (m), cuántas]. Sin la mitad no hay plano.
const SAMPLES := [[0.0, 1], [0.9, 6], [EDGE, 10]]
## Peso de mena en el vóxel golpeado desde el que es roca, y metros de roca encima desde los que
## se está en una cueva (UndergroundDepth).
const ORE_WEIGHT := 0.15
const CAVE_DEPTH := 1.0
## Pasos de la búsqueda binaria del rayo de vóxeles: la altura del suelo a 1/64 de vóxel.
const RAY_REFINE := 6

static var _brush: VoxelGeneratorGraph


## Herramientas que allanan.
static func levels(data: ItemData) -> bool:
	return data != null and data.tool_type == ItemData.ToolType.HOE


## Dónde allanaría un golpe de [body] mirando por [camera]: {"terrain", "point" y "normal" (lo que
## mira), "up", "center" (el centro del plano, en el mundo) y "rock" (es roca: no se allana)}, o {}
## si no mira a terreno cargado a menos de RANGE de los pies. Con [to_feet] el plano va a la altura
## de los pies; si no, a la de alrededor.
static func aim(body: PlanetaryBody, camera: Camera3D, to_feet: bool) -> Dictionary:
	var from := camera.global_position
	var feet := body.global_position
	var to := from - camera.global_basis.z * (from.distance_to(feet) + RANGE)
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD)
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.position as Vector3).distance_to(feet) > RANGE:
		return {}
	var terrain := hit.collider as VoxelLodTerrain
	if terrain == null:
		return {}
	var up := -body.gravity_direction.normalized()
	var point: Vector3 = hit.position
	var tool := _tool(terrain)
	var out := {"terrain": terrain, "point": point, "normal": hit.normal, "up": up, "center": point,
		"rock": false}
	if _is_rock(terrain, tool, hit, body.planet, up):
		out.rock = true
	elif to_feet:
		out.center = point + up * up.dot(feet - point)
	else:
		var center = plane_center(terrain, point, up, tool)
		if center == null:
			return {}
		out.center = center
	return out


## El centro del plano de alrededor de [point] (en el mundo): la mediana de las alturas del suelo en
## las muestras (SAMPLES) del plano de [up] que pasa por [point]. La mediana y no la media: un bulto
## o un hoyo solos no tiran del plano. null si no hay suelo cargado en la mitad de las muestras.
static func plane_center(terrain: VoxelLodTerrain, point: Vector3, up: Vector3, tool: VoxelTool = null) -> Variant:
	if tool == null:
		tool = _tool(terrain)
	var basis := frame(up)
	var heights: Array[float] = []
	var count := 0
	for ring: Array in SAMPLES:
		var n: int = ring[1]
		count += n
		for i in n:
			var angle := TAU * float(i) / float(n)
			var height := ground_height(tool, point + (basis.x * cos(angle) + basis.z * sin(angle)) * float(ring[0]), up)
			if not is_nan(height):
				heights.append(height)
	if heights.size() * 2 < count:
		return null
	heights.sort()
	return point + up * heights[floori(heights.size() * 0.5)]


## Altura (m según [up]) del suelo que hay sobre o bajo [at], buscándolo hasta DEPTH_EDGE por
## encima y por debajo; NAN si no lo hay. Lee los vóxeles y no la colisión, que llega tarde: así ve
## lo que acaba de allanar el golpe anterior.
static func ground_height(tool: VoxelTool, at: Vector3, up: Vector3) -> float:
	var hit := tool.raycast(at + up * DEPTH_EDGE, -up, DEPTH_EDGE * 2.0)
	if hit == null:
		return NAN
	return DEPTH_EDGE - hit.distance


## Allana un golpe hacia el plano de centro [center] (en el mundo) y vertical [up]. false si ese
## trozo de terreno no está cargado.
static func apply(terrain: VoxelLodTerrain, center: Vector3, up: Vector3) -> bool:
	var to_local := terrain.global_transform.affine_inverse()
	var local_center := to_local * center
	var side := 2.0 * maxf(EDGE, DEPTH_EDGE) + 2.0
	var tool := terrain.get_voxel_tool() as VoxelToolLodTerrain
	if tool == null or not tool.is_area_editable(AABB(local_center - Vector3.ONE * side * 0.5, Vector3.ONE * side)):
		return false
	tool.channel = VoxelBuffer.CHANNEL_SDF
	tool.do_graph(_graph(), Transform3D(frame(to_local.basis * up), local_center), Vector3.ONE * side)
	# Allanar no pasa por ninguna rejilla: lo construido que se quede sin apoyo hay que mirarlo a mano.
	GridManager.mark_collapse_checks_near(center, EDGE)
	return true


## Sube a [body] sobre el suelo si el golpe de centro [center] le ha rellenado bajo los pies: si no,
## se quedaría hundido en el suelo nuevo.
static func lift_onto_ground(terrain: VoxelLodTerrain, body: Node3D, center: Vector3, up: Vector3) -> void:
	var feet := body.global_position
	var offset := feet - center
	if (offset - up * up.dot(offset)).length() > EDGE:
		return
	var height := ground_height(_tool(terrain), feet, up)
	# A DEPTH_EDGE el rayo ha salido de dentro de la tierra: está bajo techo, no hundido.
	if not is_nan(height) and height > 0.0 and height < DEPTH_EDGE:
		body.global_position += up * (height + 0.02)


## Base ortonormal con Y en [up].
static func frame(up: Vector3) -> Basis:
	var y := up.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


## Si lo golpeado en [hit] es roca: el suelo rocoso y el hielo (SurfaceAudio), una mena o una cueva.
static func _is_rock(terrain: VoxelLodTerrain, tool: VoxelTool, hit: Dictionary, planet_root: Node3D,
		up: Vector3) -> bool:
	if SurfaceAudio.resolve(hit, planet_root, up) == &"rock":
		return true
	# El vóxel de justo debajo de la superficie golpeada.
	var p := Vector3i(terrain.to_local(hit.position - hit.normal * 0.3).round())
	tool.channel = VoxelBuffer.CHANNEL_INDICES
	var indices_u16 := tool.get_voxel(p)
	tool.channel = VoxelBuffer.CHANNEL_WEIGHTS
	var weights_u16 := tool.get_voxel(p)
	var indices := VoxelTool.u16_indices_to_vec4i(indices_u16)
	var weights := VoxelTool.u16_weights_to_color(weights_u16)
	for slot in 4:
		# La profundidad bajo tierra viaja en otro hueco de los pesos y no es una mena.
		if indices[slot] > 0 and indices[slot] != UndergroundDepth.LAYER and weights[slot] > ORE_WEIGHT:
			return true
	return UndergroundDepth.decode(indices_u16, weights_u16) > CAVE_DEPTH


static func _tool(terrain: VoxelLodTerrain) -> VoxelTool:
	var tool := terrain.get_voxel_tool()
	if tool is VoxelToolLodTerrain:
		(tool as VoxelToolLodTerrain).set_raycast_binary_search_iterations(RAY_REFINE)
	return tool


## El pincel: sdf + clamp(RATE · (y - sdf), -STEP, STEP) · peso, con el peso entero dentro de
## RADIUS y DEPTH, a cero en EDGE y DEPTH_EDGE, y suavizado.
##
## do_graph multiplica lo que sale del grafo por la longitud del vector de escala del marco y divide
## por lo mismo la SDF que entra (√3 con un marco ortonormal), así que el grafo trabaja con la SDF
## entre √3 y saca el resultado entre √3; lo comprueba tests/planet/test_terrain_leveling. Las
## expresiones del módulo no tienen menos unario ni paréntesis tras un operador: van sin agrupar.
static func _graph() -> VoxelGeneratorGraph:
	if _brush != null:
		return _brush
	var k := sqrt(3.0)
	var graph := VoxelGeneratorGraph.new()
	var fn := graph.get_main_function()
	var x := fn.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2.ZERO)
	var y := fn.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2.ZERO)
	var z := fn.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2.ZERO)
	var sdf := fn.create_node(VoxelGraphFunction.NODE_INPUT_SDF, Vector2.ZERO)
	var reach := _expression(fn, "clamp(%f - sqrt(x * x + z * z) * %f, 0.0, 1.0) * clamp(%f - abs(y) * %f, 0.0, 1.0)" % [
			EDGE / (EDGE - RADIUS), 1.0 / (EDGE - RADIUS), DEPTH_EDGE / (DEPTH_EDGE - DEPTH), 1.0 / (DEPTH_EDGE - DEPTH)],
		{"x": x, "y": y, "z": z})
	var weight := _expression(fn, "w * w * 3.0 - w * w * w * 2.0", {"w": reach})
	var level := _expression(fn, "sdf + clamp(y * %f - sdf * %f, 0.0 - %f, %f) * w" % [RATE / k, RATE, STEP / k, STEP / k],
		{"sdf": sdf, "y": y, "w": weight})
	fn.add_connection(level, 0, fn.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2.ZERO), 0)
	var result: Dictionary = graph.compile()
	if not result.get("success", false):
		push_error("TerrainLeveling: el pincel no compila: %s" % result)
	_brush = graph
	return _brush


## Nodo de expresión de [fn] con sus entradas {nombre: nodo}, en ese orden.
static func _expression(fn: VoxelGraphFunction, expression: String, inputs: Dictionary) -> int:
	var node := fn.create_node(VoxelGraphFunction.NODE_EXPRESSION, Vector2.ZERO)
	fn.set_node_param(node, 0, expression)
	fn.set_expression_node_inputs(node, PackedStringArray(inputs.keys()))
	var port := 0
	for input_name: String in inputs:
		fn.add_connection(inputs[input_name], 0, node, port)
		port += 1
	return node
