class_name CompanionPortraits
extends Node

## Retratos de los del grupo (Companion) para la barra de la rueda de órdenes (GroupOrderWheel): su
## humano, vestido como va (Villager.build_model, con lo de su poblado), retratado de cara fuera de
## pantalla en un mundo propio con las luces del estudio de la creación (CharacterPreview), como las
## miniaturas de ChoiceThumbnails. Cada uno se retrata una sola vez por partida (se guarda por su
## poblado y su id) y de uno en uno: vestir a un humano son ~100 ms. request() lo pide; llega por
## portrait_ready.
##
## Antes de la foto se espera a que el rig acabe de ajustarle la ropa (hasta entonces lo tapa entero).
## La cara se busca en una foto de cuerpo entero (_find_face): cada uno tiene su estatura y los huesos
## no la dicen tal como se ve. La cámara y el modelo van sin interpolación de física: con ella, la
## cámara saldría a medio camino entre una foto y otra.

signal portrait_ready(key: String, texture: Texture2D)

const SIZE := 192
## Lo más que se espera (s) a que el rig acabe de ajustarle la ropa (mientras, lo tapa entero).
const DRESS_WAIT := 6.0
## Encuadre de cerca: distancia a la cara (m, en uno de 1,75 m), cuánto queda la cara por delante del
## eje del cuerpo, giro del modelo (rad) y cuánto mira a la cámara.
const DISTANCE := 0.95
const FACE_AHEAD := 0.07
const TURN := 0.3
const AIM := 0.8
## La foto de cuerpo entero para encontrar la cara (_find_face): ortográfica, de WIDE_SIZE m de alto,
## centrada a WIDE_CENTER m y desde WIDE_BACK m delante. Lo alto de la cabeza se busca a menos de
## HEAD_BAND m del centro, y la cara queda FACE_DROP m más abajo (en uno de 1,75 m).
const WIDE_SIZE := 2.6
const WIDE_CENTER := 1.15
const WIDE_BACK := 4.0
const HEAD_BAND := 0.12
const FACE_DROP := 0.13

## Lo ya retratado: clave (key_of) -> Texture2D. Sobrevive a cerrar y abrir la rueda.
static var _cache := {}

var _viewport: SubViewport
var _camera: Camera3D
## {key, who} por retratar, y las claves en cola.
var _queue: Array[Dictionary] = []
var _queued := {}
var _busy := false


## La clave del retrato de [c]: su poblado y su id.
static func key_of(c: Companion) -> String:
	return "%d:%s" % [c.village, String(c.resident.get("id", ""))]


## El retrato de [c] si ya está hecho, o null.
static func cached(c: Companion) -> Texture2D:
	return _cache.get(key_of(c)) as Texture2D


func _ready() -> void:
	# Un modelo que se pone y se gira de golpe no debe salir a medio camino (interpolación de física).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	CharacterPreview.build_studio(_viewport, true)
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = 30.0
	_camera.near = 0.05
	_viewport.add_child(_camera)
	_camera.current = true


## Pide el retrato de [c], si no está hecho ni pedido.
func request(c: Companion) -> void:
	if c == null or not is_instance_valid(c):
		return
	var key := key_of(c)
	if _cache.has(key) or _queued.has(key):
		return
	_queued[key] = true
	_queue.append({key = key, who = c.resident})
	if not _busy:
		_pump()


func _pump() -> void:
	_busy = true
	while not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		var who: Dictionary = job.who
		var model := Villager.build_model(who, SettlementVillagers.pieces_of(who))
		model.rotation.y = TURN
		model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_viewport.add_child(model)
		var skeleton := model.get_node("Armature/Skeleton3D") as Skeleton3D
		skeleton.add_child(PreviewPosture.new())
		var aim := PreviewHeadAim.new()
		aim.target = _camera
		aim.weight = AIM
		skeleton.add_child(aim)
		(model.get_node("AnimationPlayer") as AnimationPlayer).play(Villager.ANIM_IDLE)
		# El rig ajusta la ropa en otros hilos y tapa el cuerpo hasta acabar: se espera a que acabe (y,
		# luego, dos fotogramas para que el esqueleto y la cabeza tomen la pose).
		var rig := model.get_node("AppearanceRig") as CharacterAppearanceRig
		var waited := 0.0
		while rig != null and rig.is_dressing() and waited < DRESS_WAIT:
			waited += get_process_delta_time()
			await get_tree().process_frame
			if not is_inside_tree():
				return
		await get_tree().process_frame
		await get_tree().process_frame
		if not is_inside_tree():
			return
		# Primero, de cuerpo entero y sin lo que lleve en la cabeza: dónde le queda (cada uno tiene su
		# estatura, y los huesos no la dicen tal como se ve).
		var hats := _head_pieces(skeleton, who)
		for hat in hats:
			hat.visible = false
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = WIDE_SIZE
		_camera.position = Vector3(0.0, WIDE_CENTER, WIDE_BACK)
		_camera.rotation = Vector3.ZERO
		if not await _render():
			return
		var face := _find_face(_viewport.get_texture().get_image())
		for hat in hats:
			if is_instance_valid(hat):
				hat.visible = true
		# Luego, la cara de cerca.
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		var target := Vector3(face.x, face.y, FACE_AHEAD)
		_camera.position = Vector3(target.x, target.y + 0.03, target.z + DISTANCE * face.z)
		_camera.look_at(target)
		if not await _render():
			return
		var texture := ImageTexture.create_from_image(_viewport.get_texture().get_image())
		_viewport.remove_child(model)
		model.queue_free()
		_cache[job.key] = texture
		_queued.erase(job.key)
		portrait_ready.emit(job.key, texture)
	_busy = false


## Pinta el viewport una vez con lo que haya puesto y espera a que esté: UPDATE_ONCE pinta en el
## fotograma siguiente, así que el primer frame_post_draw aún trae la foto de antes. Falso si se ha
## salido del árbol mientras.
func _render() -> bool:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for k in 2:
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return false
	return true


## Lo que lleva en la cabeza [who] (las piezas que tapan el pelo), entre lo que cuelga de [skeleton].
static func _head_pieces(skeleton: Skeleton3D, who: Dictionary) -> Array[Node3D]:
	var paths := {}
	for piece: Array in SettlementVillagers.pieces_of(who):
		if bool(piece[1]):
			paths[String(piece[0])] = true
	var out: Array[Node3D] = []
	for child in skeleton.get_children():
		if child is Node3D and paths.has(child.scene_file_path):
			out.append(child)
	return out


## En la foto de cuerpo entero ([image], ortográfica: WIDE_SIZE m de alto, centrada en WIDE_CENTER):
## el centro de la cara (x, y, en m) y en z cuánto más grande que uno de 1,75 m es. Lo alto de la
## cabeza es la primera fila con algo en la franja central; la cara queda FACE_DROP más abajo y centrada
## en lo que hay en el palmo de debajo. Sin nada, una cara a 1,6 m.
static func _find_face(image: Image) -> Vector3:
	var w := image.get_width()
	var h := image.get_height()
	var per_m := h / WIDE_SIZE
	var top := -1
	var band := int(HEAD_BAND * per_m)
	for y in h:
		for x in range(maxi(w / 2 - band, 0), mini(w / 2 + band, w)):
			if image.get_pixel(x, y).a > 0.5:
				top = y
				break
		if top >= 0:
			break
	if top < 0:
		return Vector3(0.0, 1.6, 1.0)
	# Los pies: la última fila con algo, a todo lo ancho (entre las piernas no hay nada).
	var bottom := top
	for y in range(h - 1, top, -1):
		var found := false
		for x in w:
			if image.get_pixel(x, y).a > 0.5:
				found = true
				break
		if found:
			bottom = y
			break
	var top_y := WIDE_CENTER + (h * 0.5 - top) / per_m
	var feet_y := WIDE_CENTER + (h * 0.5 - bottom) / per_m
	var scale := clampf((top_y - feet_y) / 1.75, 0.7, 1.4)
	# El centro de la cabeza, a lo ancho: el de lo que hay en el palmo bajo lo alto.
	var sum := 0.0
	var count := 0
	for y in range(top, mini(top + int(0.2 * scale * per_m), h)):
		for x in range(maxi(w / 2 - band * 2, 0), mini(w / 2 + band * 2, w)):
			if image.get_pixel(x, y).a > 0.5:
				sum += x
				count += 1
	var cx := (sum / count - w * 0.5) / per_m if count > 0 else 0.0
	return Vector3(cx, top_y - FACE_DROP * scale, scale)
