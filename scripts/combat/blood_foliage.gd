class_name BloodFoliage
extends Node

## Sangre sobre la hierba y los arbustos: una lista de hasta MAX salpicaduras (centro, radio, edad)
## que lee el shader de la vegetación (shaders/lib/blood_splats.gdshaderinc) en una textura global
## de MAX × 2. Al subirlas se reparten por cercanía en grupos de GROUP_SIZE, cada uno con su esfera:
## una hoja solo recorre los grupos en cuya esfera cae, así que el coste no crece con el total. El
## shader tiñe a gotas las hojas que caen dentro, sobre su posición en reposo, así que la sangre va
## pegada a ellas con el viento.
## Las salpicaduras van en coordenadas canónicas (mundo + desplazamiento del origen flotante), como
## u_world_offset, y no hay que moverlas al rebasar.
##
## Las añade quien deja sangre: BloodPool (charcos y manchas en el suelo) y CombatFx (el golpe
## salpica las matas de alrededor). Un nodo de la escena las va secando y quita las que caducan.

const MAX := 128
const GROUP_SIZE := 8
const GROUPS := MAX / GROUP_SIZE
## Hasta dónde se junta una salpicadura con un grupo que ya tiene sitio antes de abrir otro (m).
const GROUP_REACH := 4.0
const LIFETIME := 180.0
const FADE := 15.0
const DRY_TIME := 90.0
## Una salpicadura que cae casi encima de otra la agranda (hasta cubrir las dos, con tope) en vez
## de ocupar otra plaza.
const MERGE := 0.5
const MAX_RADIUS := 3.0

static var _splats: Array[Dictionary] = []
static var _image: Image
static var _texture: ImageTexture
static var _node: BloodFoliage
static var _origin: FloatingOrigin

var _tick := 0.0


## Las variables globales del shader, por si project.godot no las trae (el editor puede haberlo
## reescrito): sin ellas el shader de la vegetación no compila. Antes de cargar el planeta.
static func register_globals() -> void:
	# Las de project.godot ya las ha cargado el motor (y la lista de las registradas solo se puede
	# pedir en el editor).
	for entry in [[&"blood_splats", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, null],
			[&"blood_splat_count", RenderingServer.GLOBAL_VAR_TYPE_INT, 0],
			[&"blood_splat_bounds", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO]]:
		if not ProjectSettings.has_setting("shader_globals/" + String(entry[0])):
			RenderingServer.global_shader_parameter_add(entry[0], entry[1], entry[2])


## Sangre sobre la vegetación en una esfera de [radius] m alrededor de [point] (mundo).
static func add(point: Vector3, radius: float) -> void:
	if SettingsManager.gore_level() == SettingsManager.GORE_OFF or not _ensure_node():
		return
	var center := point + _offset()
	var now := Time.get_ticks_msec() / 1000.0
	for splat in _splats:
		var d := (splat.center as Vector3).distance_to(center)
		if d < maxf(splat.radius, radius) * MERGE:
			splat.radius = minf(maxf(splat.radius, d + radius), MAX_RADIUS)
			splat.born = now
			_upload()
			return
	_splats.append({center = center, radius = radius, born = now})
	while _splats.size() > MAX:
		_splats.pop_front()
	_upload()


static func clear() -> void:
	_splats.clear()
	if _texture != null:
		_upload()


static func _ensure_node() -> bool:
	if _node != null and is_instance_valid(_node) and _node.is_inside_tree():
		return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return false
	_node = BloodFoliage.new()
	_node.name = "BloodFoliage"
	tree.current_scene.add_child(_node)
	return true


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
		RenderingServer.global_shader_parameter_set(&"blood_splats", _texture)
	_image.fill(Color(0, 0, 0, 0))
	var groups := _group()
	var now := Time.get_ticks_msec() / 1000.0
	var low := Vector3.INF
	var high := -Vector3.INF
	for g in groups.size():
		var group_low := Vector3.INF
		var group_high := -Vector3.INF
		var members: Array = groups[g]
		for k in members.size():
			var splat: Dictionary = members[k]
			var center: Vector3 = splat.center
			var age: float = now - splat.born
			# Al final se encoge hasta desaparecer; el radio va en milímetros (parte entera, al menos
			# 1: 0 es hueco y cortaría el grupo) y lo seca que está en la parte decimal.
			var radius: float = splat.radius * clampf((LIFETIME - age) / FADE, 0.0, 1.0)
			var dry := clampf(age / DRY_TIME, 0.0, 0.99)
			_image.set_pixel(g * GROUP_SIZE + k, 0, Color(center.x, center.y, center.z, maxf(floorf(radius * 1000.0), 1.0) + dry))
			group_low = group_low.min(center - Vector3.ONE * radius)
			group_high = group_high.max(center + Vector3.ONE * radius)
		var mid := (group_low + group_high) * 0.5
		_image.set_pixel(g, 1, Color(mid.x, mid.y, mid.z, (group_high - group_low).length() * 0.5))
		low = low.min(group_low)
		high = high.max(group_high)
	_texture.update(_image)
	RenderingServer.global_shader_parameter_set(&"blood_splat_count", groups.size())
	var bounds := Vector4.ZERO
	if not groups.is_empty():
		var mid := (low + high) * 0.5
		bounds = Vector4(mid.x, mid.y, mid.z, (high - low).length() * 0.5)
	RenderingServer.global_shader_parameter_set(&"blood_splat_bounds", bounds)


## Reparte las salpicaduras en grupos de vecinas: cada una va al grupo con sitio más cercano, o abre
## otro si queda lejos de todos y aún quedan. Caben siempre: MAX = GROUPS × GROUP_SIZE.
static func _group() -> Array:
	var groups: Array = []
	var centers: Array[Vector3] = []
	for splat in _splats:
		var center: Vector3 = splat.center
		var best := -1
		var best_d := INF
		for g in groups.size():
			if (groups[g] as Array).size() >= GROUP_SIZE:
				continue
			var d := centers[g].distance_to(center)
			if d < best_d:
				best_d = d
				best = g
		if best < 0 or (best_d > GROUP_REACH and groups.size() < GROUPS):
			groups.append([splat])
			centers.append(center)
		else:
			var members: Array = groups[best]
			members.append(splat)
			centers[best] = centers[best].lerp(center, 1.0 / members.size())
	return groups


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or _splats.is_empty():
		return
	# Secarse y apagarse es lento: basta con revisarlas cada segundo.
	_tick = 1.0
	var now := Time.get_ticks_msec() / 1000.0
	_splats = _splats.filter(func(splat: Dictionary) -> bool: return now - splat.born < LIFETIME)
	_upload()


func _exit_tree() -> void:
	# Fuera de la partida (menú, otra escena) no queda sangre colgando de un mundo que ya no está.
	if _node == self:
		clear()
		_node = null
