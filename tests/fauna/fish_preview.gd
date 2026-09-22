extends Node3D

## Reviews the baked reef fish one by one. 1–6 select a species, 0 shows all of
## them side by side, H toggles head/body, P puts the camera in profile, drag
## rotates and the wheel zooms. With `-- --capture` it saves fixed views of each
## species under build/fauna/fish/ and quits.

var _models: Array[MeshInstance3D] = []
var _camera: Camera3D
var _title: Label
var _selected := -1
var _yaw := 0.65
var _pitch := 0.3
var _zoom := 1.0
var _dragging := false
var _head_view := false


func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("163346")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b4d4df")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.5
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25, 150, 0)
	fill.light_energy = 0.6
	add_child(fill)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	for kind in SimpleFishMesh.TYPES.size():
		var visual := MeshInstance3D.new()
		visual.mesh = SimpleFishMesh.mesh(kind)
		visual.material_override = SimpleFishMesh.material()
		visual.position = Vector3((kind % 3 - 1) * 1.3, 0.0, float(kind / 3) * 1.6)
		add_child(visual)
		visual.set_instance_shader_parameter("fish_type", kind)
		visual.set_instance_shader_parameter("swim_phase", float(kind))
		visual.set_instance_shader_parameter("swim_frequency", float(SimpleFishMesh.TYPES[kind].speed) * 6.0)
		_models.append(visual)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_title = Label.new()
	_title.position = Vector2(24, 24)
	_title.add_theme_font_size_override("font_size", 22)
	canvas.add_child(_title)
	_select(0)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture(canvas)


func _capture(canvas: CanvasLayer) -> void:
	canvas.hide()
	for model in _models:
		model.set_instance_shader_parameter("swim_frequency", 0.0)
	DirAccess.make_dir_recursive_absolute("res://build/fauna/fish")
	var views := {"side": [PI * 0.5, 0.0, false], "three_quarter": [0.65, 0.3, false], "top": [PI * 0.5, 1.3, false], "head": [0.9, 0.2, true], "front": [0.0, 0.1, true]}
	for kind in _models.size():
		_select(kind)
		for view in views:
			_yaw = views[view][0]
			_pitch = views[view][1]
			_head_view = views[view][2]
			_frame_model()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://build/fauna/fish/%d_%s.png" % [kind, view])
	_select(-1)
	_yaw = 0.9
	_pitch = 0.25
	_frame_model()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/fauna/fish/all.png")
	get_tree().quit()


func _select(kind: int) -> void:
	_selected = kind
	if kind < 0:
		_head_view = false
	_zoom = 1.0
	for i in _models.size():
		_models[i].visible = kind < 0 or i == kind
	var name_text: String = "Todos" if kind < 0 else SimpleFishMesh.TYPES[kind].name
	_title.text = name_text + "\n1–6 especie · 0 Todos\nArrastrar: girar · Rueda: zoom · H: cabeza/cuerpo · P: perfil"
	_frame_model()


func _frame_model() -> void:
	var bounds := AABB()
	var initialized := false
	for kind in _models.size():
		if _selected >= 0 and kind != _selected:
			continue
		var model_bounds := SimpleFishMesh.mesh(kind).get_aabb()
		model_bounds.position += _models[kind].position
		bounds = bounds.merge(model_bounds) if initialized else model_bounds
		initialized = true
	var target := bounds.get_center()
	var extent := bounds.size.length() * 1.1
	if _head_view and _selected >= 0:
		var length: float = SimpleFishMesh.TYPES[_selected].length
		target = _models[_selected].position + Vector3(0, 0, -length * 0.3)
		extent = length * 0.55
	_camera.size = extent * _zoom
	_camera.position = target + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), -cos(_yaw) * cos(_pitch)) * extent * 3.0
	_camera.look_at(target)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_6:
			_select(event.keycode - KEY_1)
		elif event.keycode == KEY_0:
			_select(-1)
		elif event.keycode == KEY_H and _selected >= 0:
			_head_view = not _head_view
			_zoom = 1.0
			_frame_model()
		elif event.keycode == KEY_P:
			_yaw = PI * 0.5
			_pitch = 0.0
			_frame_model()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom = clampf(_zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.3, 2.5)
			_frame_model()
	if event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.008, -1.3, 1.3)
		_frame_model()
