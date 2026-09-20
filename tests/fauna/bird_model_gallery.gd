extends Node3D

var _birds: Array[SimpleBirdModel] = []
var _camera: Camera3D
var _label: Label
var _selected := 1
var _flying := false
var _paused := false
var _head := false
var _dragging := false
var _time := 0.0
var _yaw := 0.8
var _pitch := 0.22
var _zoom := 1.0


func _ready() -> void:
	var world := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("243c3b")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("e0e6d9")
	settings.ambient_light_energy = 0.65
	world.environment = settings
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 1.15
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(15, 145, 0)
	fill.light_energy = 0.45
	add_child(fill)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.01
	add_child(_camera)
	_camera.current = true
	for kind in 5:
		var bird := SimpleBirdModel.new()
		bird.position.x = [-2.0, -1.15, -0.3, 0.9, 2.25][kind]
		add_child(bird)
		bird.set_species(kind)
		_birds.append(bird)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(_label)
	_select(1)


func _process(delta: float) -> void:
	if _paused:
		return
	_time += delta
	for bird in _birds:
		bird.animate(_time, _flying, delta)


func _select(kind: int) -> void:
	_selected = kind
	_zoom = 1.0
	if kind < 0:
		_head = false
	for i in _birds.size():
		_birds[i].visible = kind < 0 or kind == i
	_caption()
	_frame()


func _caption() -> void:
	var title: String = SimpleBirdModel.NAMES[_selected] if _selected >= 0 else "Todas las aves · escala relativa"
	_label.text = title + (" · vuelo" if _flying else " · reposo") + (" · pausa" if _paused else "")
	_label.text += "\n1 Gorrión · 2 Petirrojo · 3 Herrerillo · 4 Gaviota · 5 Pato · 0 Todas"
	_label.text += "\nEspacio: vuelo/reposo · P: pausa · H: cabeza · F: perfil\nArrastrar: girar · Rueda: zoom"


func _frame() -> void:
	var target := Vector3(0, .25, 0)
	var extent := 5.6
	if _selected >= 0:
		target = _birds[_selected].position + Vector3(0, .24 if _selected<3 else .32, 0)
		extent = 0.90 if _selected<3 else 1.65
		if _head:
			target += Vector3(0, .085 if _selected<3 else .145, -.14 if _selected<3 else -.29)
			extent = .32 if _selected<3 else .53
	_camera.size = extent * _zoom
	_camera.position = target + Vector3(sin(_yaw)*cos(_pitch), sin(_pitch), -cos(_yaw)*cos(_pitch)) * extent * 2.0
	_camera.look_at(target)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_select(event.keycode - KEY_1)
		elif event.keycode == KEY_0:
			_select(-1)
		elif event.keycode == KEY_SPACE:
			_flying = not _flying
			if _paused:
				for bird in _birds:
					bird.animate(_time, _flying, 1.0)
		elif event.keycode == KEY_P:
			_paused = not _paused
		elif event.keycode == KEY_H and _selected >= 0:
			_head = not _head
			_zoom = 1.0
		elif event.keycode == KEY_F:
			_yaw = PI*.5
			_pitch = 0.0
		_caption()
		_frame()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom = clampf(_zoom*(.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), .3, 2.5)
			_frame()
	if event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x*.008
		_pitch = clampf(_pitch+event.relative.y*.008, -1.2, 1.2)
		_frame()
