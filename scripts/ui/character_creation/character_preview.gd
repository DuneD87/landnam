class_name CharacterPreview
extends SubViewportContainer

## Studio view of the character being created: its own world (so it works
## over any scene), studio lights, the model playing its idle animation and a
## camera that eases between framings. Dragging turns the model, the wheel
## zooms. Uses scenes/character/character_model.tscn with a live rig.
##
## Framings follow the head bone, so they stay right whatever the height,
## sex or pose: `head_offset` is added to the (smoothed) head height and
## `height_share` blends from the feet (0) to that point (1).

const MODEL_SCENE := preload("res://scenes/character/character_model.tscn")
const FOCUS := {
	&"body": {height_share = 0.52, head_offset = 0.1, distance = 4.1},
	&"head": {height_share = 1.0, head_offset = 0.06, distance = 1.3},
	&"face": {height_share = 1.0, head_offset = 0.09, distance = 0.95},
}
const ZOOM_RANGE := Vector2(0.55, 1.6)
const TURN_SPEED := 0.008
## Horizontal shift of the framing, as a fraction of the view, so the model
## sits in the space the side panel leaves free.
@export var frame_offset := 0.12

var rig: CharacterAppearanceRig
var _viewport: SubViewport
var _camera: Camera3D
var _model: Node3D
var _skeleton: Skeleton3D
var _head_aim: PreviewHeadAim
var _head_height := 1.65
var _from: Dictionary = FOCUS[&"body"]
var _to: Dictionary = FOCUS[&"body"]
var _blend := 1.0
var _zoom := 1.0
var _dragging := false
var _focus_tween: Tween


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.handle_input_locally = false
	add_child(_viewport)
	_build_stage()
	_model = MODEL_SCENE.instantiate()
	rig = _model.get_node("AppearanceRig")
	rig.live = true
	_viewport.add_child(_model)
	_skeleton = _model.get_node("Armature/Skeleton3D")
	var animation: AnimationPlayer = _model.get_node("AnimationPlayer")
	animation.play(&"idle")
	_head_aim = PreviewHeadAim.new()
	_head_aim.target = _camera
	_skeleton.add_child(_head_aim)
	focus(&"body", false)


## Eases the camera to one of FOCUS; `animate` false jumps.
func focus(framing: StringName, animate := true) -> void:
	_zoom = 1.0
	_from = _current_framing()
	_to = FOCUS.get(framing, FOCUS[&"body"])
	if _focus_tween:
		_focus_tween.kill()
	_blend = 0.0
	if not animate:
		_blend = 1.0
		return
	_focus_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(self, "_blend", 1.0, 0.6)


func reset_turn() -> void:
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(
			_model, "rotation:y", 0.0, 0.5)


func _process(delta: float) -> void:
	if _head_aim.head_position != Vector3.ZERO:
		_head_height = lerpf(_head_height, _head_aim.head_position.y, 1.0 - exp(-delta * 3.0))
	_place_camera()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_zoom = clampf(_zoom * 0.9, ZOOM_RANGE.x, ZOOM_RANGE.y)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom / 0.9, ZOOM_RANGE.x, ZOOM_RANGE.y)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_model.rotation.y += event.relative.x * TURN_SPEED
		accept_event()


## Framing between the last two presets, as a preset of its own.
func _current_framing() -> Dictionary:
	var result := {}
	for key in _to:
		result[key] = lerpf(_from[key], _to[key], _blend)
	return result


func _place_camera() -> void:
	if _camera == null:
		return
	var framing := _current_framing()
	var distance: float = framing.distance * _zoom
	var height: float = (_head_height + framing.head_offset) * framing.height_share
	# Shift the look-at sideways so the model is centred in the free space.
	var half_width := distance * tan(deg_to_rad(_camera.fov) * 0.5) * _aspect()
	var target := Vector3(-frame_offset * 2.0 * half_width, height, 0.0)
	_camera.position = target + Vector3(0.0, 0.04 * distance, distance)
	_camera.look_at(target)


func _aspect() -> float:
	var size := _viewport.size
	return float(size.x) / maxf(size.y, 1.0)


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("15171b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9c2cf")
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.3
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, 32, 0)
	key.light_energy = 1.05
	key.light_color = Color("fff1e0")
	key.shadow_enabled = true
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, -48, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("cfdcff")
	_viewport.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_energy = 0.8
	rim.light_color = Color("ffd9a8")
	_viewport.add_child(rim)

	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 0.65
	floor_mesh.bottom_radius = 0.65
	floor_mesh.height = 0.02
	floor_mesh.radial_segments = 96
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("1d1f23")
	floor_material.roughness = 0.9
	floor_mesh.material = floor_material
	var floor_disc := MeshInstance3D.new()
	floor_disc.mesh = floor_mesh
	floor_disc.position.y = -0.011
	_viewport.add_child(floor_disc)

	_camera = Camera3D.new()
	_camera.fov = 30.0
	_camera.near = 0.05
	# Moved every frame from _process; the project interpolates physics by default.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport.add_child(_camera)
	_camera.current = true
