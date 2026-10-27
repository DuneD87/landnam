class_name ChoiceThumbnails
extends Node

## Miniaturas de las opciones de elección de la creación (peinados, barbas, cejas, rostros y
## pieles): el personaje que se está creando con cada una puesta, retratado fuera de pantalla por
## un segundo modelo con su propio mundo y las luces del estudio. request() pide las de unas
## opciones; llegan de una en una por thumbnail_ready. Una opción solo se vuelve a retratar si ha
## cambiado algo de lo que se ve en ella (no lo que ella misma elige), y pedir de nuevo descarta
## lo pendiente.

signal thumbnail_ready(option_id: StringName, choice_id: StringName, texture: Texture2D)

const MODEL_SCENE := preload("res://scenes/character/character_model.tscn")
const SIZE := 200
## Encuadre de cada opción: altura sobre la articulación de la cabeza y distancia (m), giro del
## modelo (rad) y cuánto mira la cabeza a la cámara.
const FRAMING := {
	AppearanceCatalog.HAIR_STYLE: {height = 0.1, distance = 0.95, turn = 0.6, aim = 0.2},
	AppearanceCatalog.BEARD: {height = 0.0, distance = 0.62, turn = 0.4, aim = 0.4},
	AppearanceCatalog.EYEBROWS: {height = 0.09, distance = 0.32, turn = 0.15, aim = 1.0},
	AppearanceCatalog.FACE_PRESET: {height = 0.05, distance = 0.62, turn = 0.25, aim = 1.0},
	AppearanceCatalog.SKIN: {height = -0.3, distance = 1.5, turn = 0.35, aim = 0.6},
}
## El de una elección sin encuadre propio: la cara.
const DEFAULT_FRAMING := {height = 0.05, distance = 0.62, turn = 0.25, aim = 1.0}

var _viewport: SubViewport
var _camera: Camera3D
var _model: Node3D
var _rig: CharacterAppearanceRig
var _head_aim: PreviewHeadAim
## [option_id, choice_id, CharacterAppearance, firma] por retratar.
var _queue: Array = []
var _busy := false
## Firma del último conjunto completo de retratos de cada opción.
var _signatures := {}
## Opciones y firmas de la petición actual, aunque aún se estén retratando.
var _requested := {}


static func supports(option: AppearanceOption) -> bool:
	return option.kind == AppearanceOption.Kind.CHOICE or option.kind == AppearanceOption.Kind.PRESET


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	CharacterPreview.build_studio(_viewport, true)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_camera.near = 0.05
	_viewport.add_child(_camera)
	_camera.current = true
	_model = MODEL_SCENE.instantiate()
	_rig = _model.get_node("AppearanceRig")
	_rig.live = true
	_viewport.add_child(_model)
	var skeleton: Skeleton3D = _model.get_node("Armature/Skeleton3D")
	skeleton.add_child(PreviewPosture.new())
	_head_aim = PreviewHeadAim.new()
	_head_aim.target = _camera
	skeleton.add_child(_head_aim)
	(_model.get_node("AnimationPlayer") as AnimationPlayer).play(&"idle")


## Retrata de nuevo las opciones de [options] (las que lo admiten) cuyo aspecto haya cambiado en
## [base]. Una petición idéntica conserva la cola; otra descarta lo pendiente.
func request(options: Array, base: CharacterAppearance) -> void:
	var sex := base.get_sex()
	var wanted := {}
	for option: AppearanceOption in options:
		if not supports(option) or not option.is_available(sex):
			continue
		wanted[option.id] = _signature(option, base)
	if wanted == _requested:
		return
	_requested = wanted
	_queue.clear()
	for option: AppearanceOption in options:
		if not wanted.has(option.id):
			continue
		var signature: String = wanted[option.id]
		if _signatures.get(option.id) == signature:
			continue
		_signatures.erase(option.id)
		for choice in option.choices_for(sex):
			var look := CharacterAppearance.from_dict(base.to_dict())
			if option.kind == AppearanceOption.Kind.PRESET:
				look.apply_preset(option, choice.id)
			else:
				look.set_value(option.id, choice.id)
			_queue.append([option.id, choice.id, look, signature])
	if not _busy and not _queue.is_empty():
		_pump()


## Olvida lo retratado: lo próximo que se pida se retrata aunque no haya cambiado.
func forget() -> void:
	_signatures.clear()
	_requested.clear()


## Todo lo que se ve en la opción menos lo que ella misma elige (y, en los rostros, los rasgos
## que fija el rostro elegido).
func _signature(option: AppearanceOption, base: CharacterAppearance) -> String:
	var values := base.to_dict()
	values.erase(String(option.id))
	if option.kind == AppearanceOption.Kind.PRESET:
		for id in AppearanceCatalog.preset_scope(option.id):
			values.erase(String(id))
	return JSON.stringify(values, "", true)


func _pump() -> void:
	_busy = true
	while not _queue.is_empty():
		var job: Array = _queue.pop_front()
		var framing: Dictionary = FRAMING.get(job[0], DEFAULT_FRAMING)
		_rig.apply(job[2])
		_model.rotation.y = framing.turn
		_head_aim.weight = framing.aim
		# Un fotograma para que el esqueleto (y la cabeza) tomen el cuerpo nuevo.
		await get_tree().process_frame
		if not is_inside_tree():
			return
		_place_camera(framing)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return
		if _requested.get(job[0]) != job[3]:
			continue
		var image := _viewport.get_texture().get_image()
		if _queue.is_empty() or _queue[0][0] != job[0]:
			_signatures[job[0]] = job[3]
		thumbnail_ready.emit(job[0], job[1], ImageTexture.create_from_image(image))
	_busy = false


func _place_camera(framing: Dictionary) -> void:
	var head := _head_aim.head_position
	if head == Vector3.ZERO:
		head = Vector3(0, 1.6, 0)
	var target := head + Vector3(0, framing.height, 0)
	_camera.position = target + Vector3(0, 0.03, framing.distance)
	_camera.look_at(target)
