class_name SettlementStreets extends RefCounted

## Las calles y la plaza de las villas (SettlementLayout._plan_streets), pintadas por el propio terreno
## con el material de las sendas: el mismo borde, la misma mezcla por altura, mojadas con la lluvia y
## tapadas por la nieve, y sin hierba encima. No hay malla: se pasan a los sombreadores como tramos
## (shaders/lib/settlement_streets.gdshaderinc) en una textura global, en coordenadas canónicas (mundo
## + desplazamiento del origen flotante), y planet_biomes.gdshader y grass_wind.gdshader miran la
## distancia a ellos. SettlementManager pone las de una villa con su cerca (show) y las quita con ella
## (hide).
##
## Cada calle del plano es su eje leído en el suelo cada 2,5 m; aquí se queda con los puntos que la
## apartan más de SIMPLIFY de la recta (sube y baja con el suelo), para no gastar MAX tramos.

## Tramos como mucho entre todas las villas cercanas (ancho de la textura).
const MAX := 128
const SIMPLIFY := 0.25

## Los tramos de cada villa: v -> [[a, b, medio ancho]] (canónicos).
static var _shown := {}
static var _image: Image
static var _texture: ImageTexture
static var _origin: FloatingOrigin


## Las variables globales del shader, por si project.godot no las trae (el editor puede haberlo
## reescrito): sin ellas no compilan el terreno ni la hierba. Antes de cargar el planeta.
static func register_globals() -> void:
	for entry in [[&"settlement_streets", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, null],
			[&"settlement_street_count", RenderingServer.GLOBAL_VAR_TYPE_INT, 0],
			[&"settlement_street_bounds", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO]]:
		if not ProjectSettings.has_setting("shader_globals/" + String(entry[0])):
			RenderingServer.global_shader_parameter_add(entry[0], entry[1], entry[2])


## Pinta las calles y la plaza de la villa [v] (su plano [plan]); [frame]: el global_transform del
## terreno (el plano va en su marco).
static func show(v: int, plan: Dictionary, frame: Transform3D) -> void:
	var to := Transform3D(frame.basis, frame.origin + _offset())
	_shown[v] = segments(plan, to)
	_upload()


static func hide(v: int) -> void:
	if _shown.erase(v):
		_upload()


static func clear() -> void:
	_shown.clear()
	if _texture != null:
		_upload()


## Los tramos de [plan] en [frame]: [[a, b, medio ancho]], la plaza como un tramo de un punto.
static func segments(plan: Dictionary, frame: Transform3D) -> Array:
	var out: Array = []
	for street: Dictionary in plan.get("streets", []):
		var line := _simplify(street.points, SIMPLIFY)
		var half := float(street.width) * 0.5
		for i in line.size() - 1:
			out.append([frame * line[i], frame * line[i + 1], half])
	var plaza: Dictionary = plan.get("plaza", {})
	if not plaza.is_empty():
		var at := frame * (plaza.center as Vector3)
		out.append([at, at, float(plaza.radius)])
	return out


## [points] sin los que, quitados, no la apartan más de [tolerance] (Douglas-Peucker).
static func _simplify(points: PackedVector3Array, tolerance: float) -> PackedVector3Array:
	if points.size() < 3:
		return points
	var a := points[0]
	var b := points[points.size() - 1]
	var worst := -1
	var far := tolerance
	for i in range(1, points.size() - 1):
		var d := Geometry3D.get_closest_point_to_segment(points[i], a, b).distance_to(points[i])
		if d > far:
			far = d
			worst = i
	if worst < 0:
		return PackedVector3Array([a, b])
	var head := _simplify(points.slice(0, worst + 1), tolerance)
	head.append_array(_simplify(points.slice(worst), tolerance).slice(1))
	return head


## Desplazamiento del origen flotante (global canónico = global actual + esto).
static func _offset() -> Vector3:
	if _origin == null or not is_instance_valid(_origin):
		var tree := Engine.get_main_loop() as SceneTree
		_origin = tree.get_first_node_in_group(&"floating_origin_manager") as FloatingOrigin if tree != null else null
	return _origin.total_offset if _origin != null else Vector3.ZERO


static func _upload() -> void:
	if _image == null:
		_image = Image.create(MAX, 2, false, Image.FORMAT_RGBAF)
		_texture = ImageTexture.create_from_image(_image)
		RenderingServer.global_shader_parameter_set(&"settlement_streets", _texture)
	_image.fill(Color(0, 0, 0, 0))
	var count := 0
	var low := Vector3.INF
	var high := -Vector3.INF
	for v: int in _shown:
		for seg: Array in _shown[v]:
			if count >= MAX:
				push_warning("[settlements] más de %d tramos de calle cerca: sobran." % MAX)
				break
			var a: Vector3 = seg[0]
			var b: Vector3 = seg[1]
			var half: float = seg[2]
			_image.set_pixel(count, 0, Color(a.x, a.y, a.z, half))
			_image.set_pixel(count, 1, Color(b.x, b.y, b.z, 0.0))
			low = low.min(a.min(b) - Vector3.ONE * half)
			high = high.max(a.max(b) + Vector3.ONE * half)
			count += 1
	_texture.update(_image)
	RenderingServer.global_shader_parameter_set(&"settlement_street_count", count)
	var bounds := Vector4.ZERO
	if count > 0:
		# Algo más: el borde de la senda se ensancha con ruido.
		var mid := (low + high) * 0.5
		bounds = Vector4(mid.x, mid.y, mid.z, (high - low).length() * 0.5 + 2.0)
	RenderingServer.global_shader_parameter_set(&"settlement_street_bounds", bounds)
