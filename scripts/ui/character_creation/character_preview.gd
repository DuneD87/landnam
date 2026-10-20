class_name CharacterPreview
extends SubViewportContainer

## Studio view of the character being created: its own world (so it works
## over any scene), studio lights, the model playing its idle animation and a
## camera that eases between framings. Uses scenes/character/character_model.tscn
## with a live rig.
##
## The player moves the camera around the character: holding the left button
## orbits (sideways turns the model, up and down tilts the camera), holding the
## right or middle button moves the view up and down the body, and the wheel
## zooms towards the height under the cursor, so any part can be looked at
## closely. A new framing eases these back to its own view.
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
const TURN_SPEED := 0.008
const TILT_SPEED := 0.004
## Camera elevation above the framing's look, in radians (the framings look
## down slightly, BASE_TILT).
const TILT_RANGE := Vector2(-0.45, 1.0)
const BASE_TILT := 0.04
## Closest the camera gets to what it looks at, in metres, and how far it can
## back off, as a multiple of the framing's distance.
const MIN_DISTANCE := 0.35
const MAX_ZOOM_OUT := 1.6
const ZOOM_STEP := 0.88
## The view's height stays between the floor and a little above the head.
const LOOK_FLOOR := 0.05
const LOOK_ABOVE_HEAD := 0.3
const CAMERA_FLOOR := 0.08
## Horizontal shift of the framing, as a fraction of the view, so the model
## sits in the space the side panel leaves free.
@export var frame_offset := 0.12
## Body morphs as live blend shapes that follow every edit (the creation
## screen); false bakes them once on apply, for a character that does not
## change (the equipment screen).
@export var live := true
## No background: what is behind the control shows through (the blurred world
## behind the equipment screen).
@export var transparent := false

var rig: CharacterAppearanceRig
var _viewport: SubViewport
## build_studio()'s environment and lights.
var _stage: Dictionary
var _camera: Camera3D
var _model: Node3D
var _skeleton: Skeleton3D
var _head_aim: PreviewHeadAim
var _head_height := 1.65
var _framing := &"body"
var _from: Dictionary = FOCUS[&"body"]
var _to: Dictionary = FOCUS[&"body"]
var _blend := 1.0
## The player's changes to the framing: distance multiplier, height offset in
## metres and tilt in radians.
var _zoom := 1.0
var _pan := 0.0
var _tilt := 0.0
var _orbiting := false
var _panning := false
var _focus_tween: Tween


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.handle_input_locally = false
	_viewport.transparent_bg = transparent
	add_child(_viewport)
	_build_stage()
	_model = MODEL_SCENE.instantiate()
	rig = _model.get_node("AppearanceRig")
	rig.live = live
	_viewport.add_child(_model)
	_skeleton = _model.get_node("Armature/Skeleton3D")
	var animation: AnimationPlayer = _model.get_node("AnimationPlayer")
	animation.play(&"idle")
	_skeleton.add_child(PreviewPosture.new())
	_head_aim = PreviewHeadAim.new()
	_head_aim.target = _camera
	_skeleton.add_child(_head_aim)
	focus(&"body", false)


## Eases the camera to one of FOCUS, undoing the player's orbit, height and
## zoom; `animate` false jumps. With `keep_view`, a framing already shown keeps
## the player's view (switching between categories that share it).
func focus(framing: StringName, animate := true, keep_view := false) -> void:
	if not FOCUS.has(framing):
		framing = &"body"
	if keep_view and framing == _framing:
		return
	_framing = framing
	# The zoom is folded into where the camera starts from, so it eases too.
	_from = _current_framing()
	_from.distance *= _zoom
	_zoom = 1.0
	_to = FOCUS[framing]
	if _focus_tween:
		_focus_tween.kill()
	if not animate:
		_blend = 1.0
		_pan = 0.0
		_tilt = 0.0
		return
	_blend = 0.0
	_focus_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(self, "_blend", 1.0, 0.6)
	_focus_tween.tween_property(self, "_pan", 0.0, 0.6)
	_focus_tween.tween_property(self, "_tilt", 0.0, 0.6)


func get_skeleton() -> Skeleton3D:
	return _skeleton


func _process(delta: float) -> void:
	if _head_aim.head_position != Vector3.ZERO:
		_head_height = lerpf(_head_height, _head_aim.head_position.y, 1.0 - exp(-delta * 3.0))
	_place_camera()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_orbiting = event.pressed
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					var steps: float = event.factor if event.factor > 0.0 else 1.0
					if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
						steps = -steps
					_zoom_at(event.position, pow(ZOOM_STEP, steps))
		accept_event()
	elif event is InputEventMouseMotion and (_orbiting or _panning):
		if _orbiting:
			_model.rotation.y += event.relative.x * TURN_SPEED
			_tilt = clampf(_tilt + event.relative.y * TILT_SPEED, TILT_RANGE.x, TILT_RANGE.y)
		else:
			# The body follows the mouse.
			_pan += event.relative.y * _metres_per_pixel()
		_stop_easing()
		accept_event()


## Zooms by `factor`, keeping the height under `at` (a point of this control)
## where it is on screen.
func _zoom_at(at: Vector2, factor: float) -> void:
	var framing := _current_framing()
	var before: float = framing.distance * _zoom
	_zoom = clampf(_zoom * factor, MIN_DISTANCE / framing.distance, MAX_ZOOM_OUT)
	var after: float = framing.distance * _zoom
	var above_centre := (size.y * 0.5 - at.y) * _metres_per_pixel()
	_pan += above_centre * (1.0 - after / before)
	_stop_easing()


## The player took the camera: a framing still easing in stops where it is.
func _stop_easing() -> void:
	if _focus_tween and _focus_tween.is_running():
		_focus_tween.kill()
		_from = _current_framing()
		_to = _from
		_blend = 1.0


## World metres a pixel spans at the distance the camera looks at.
func _metres_per_pixel() -> float:
	var distance: float = _current_framing().distance * _zoom
	return 2.0 * distance * tan(deg_to_rad(_camera.fov) * 0.5) / maxf(size.y, 1.0)


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
	_pan = clampf(_pan, LOOK_FLOOR - height, _head_height + LOOK_ABOVE_HEAD - height)
	# Shift the look-at sideways so the model is centred in the free space.
	var half_width := distance * tan(deg_to_rad(_camera.fov) * 0.5) * _aspect()
	var target := Vector3(-frame_offset * 2.0 * half_width, height + _pan, 0.0)
	# Orbit around it, never below the floor.
	var tilt := BASE_TILT + _tilt
	tilt = maxf(tilt, asin(clampf((CAMERA_FLOOR - target.y) / distance, -1.0, 1.0)))
	_camera.position = target + Vector3(0.0, sin(tilt), cos(tilt)) * distance
	_camera.look_at(target)


func _aspect() -> float:
	var size := _viewport.size
	return float(size.x) / maxf(size.y, 1.0)


## Lighting presets: the studio (skin in its own colour) and two looks of the
## game, under the day sky and by a fire, with the world's ACES curve.
const LIGHTING := {
	&"studio": {
		tonemap = Environment.TONE_MAPPER_LINEAR, ambient = Color("b9c2cf"), ambient_energy = 0.25,
		key = [Color("fff1e0"), 0.75, Vector3(-28, 32, 0)], fill = [Color("cfdcff"), 0.2, Vector3(-12, -48, 0)],
		rim = [Color("ffd9a8"), 0.5, Vector3(-20, 160, 0)],
	},
	&"day": {
		tonemap = Environment.TONE_MAPPER_ACES, ambient = Color("9fb6d6"), ambient_energy = 0.55,
		key = [Color("fff6ea"), 1.6, Vector3(-48, 40, 0)], fill = [Color("b7cdf0"), 0.35, Vector3(-10, -60, 0)],
		rim = [Color("dfe8ff"), 0.4, Vector3(-25, 170, 0)],
	},
	&"fire": {
		tonemap = Environment.TONE_MAPPER_ACES, ambient = Color("33302f"), ambient_energy = 0.12,
		key = [Color("ff9a4a"), 1.4, Vector3(-8, 55, 0)], fill = [Color("5a6c9a"), 0.12, Vector3(-15, -70, 0)],
		rim = [Color("ff7a30"), 0.35, Vector3(-5, 150, 0)],
	},
}


## Switches the lights to one of LIGHTING.
func set_lighting(preset: StringName) -> void:
	apply_lighting(_stage, LIGHTING.get(preset, LIGHTING[&"studio"]))


## Environment and the three studio lights under `parent`, returned as
## {environment, key, fill, rim}. With `transparent` the background is left
## clear (the viewport must have transparent_bg too).
static func build_studio(parent: Node, transparent: bool) -> Dictionary:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR if transparent else Environment.BG_COLOR
	environment.background_color = Color("15171b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var world := WorldEnvironment.new()
	world.environment = environment
	parent.add_child(world)
	var stage := {environment = environment}
	for light in [&"key", &"fill", &"rim"]:
		var directional := DirectionalLight3D.new()
		directional.shadow_enabled = light == &"key"
		parent.add_child(directional)
		stage[light] = directional
	apply_lighting(stage, LIGHTING[&"studio"])
	return stage


static func apply_lighting(stage: Dictionary, preset: Dictionary) -> void:
	var environment: Environment = stage.environment
	# Lights add up to about 1 where the key hits, so in the studio skin shows
	# its own colour: filmic and ACES curves would wash it out.
	environment.tonemap_mode = preset.tonemap
	environment.ambient_light_color = preset.ambient
	environment.ambient_light_energy = preset.ambient_energy
	for light in [&"key", &"fill", &"rim"]:
		var directional: DirectionalLight3D = stage[light]
		directional.light_color = preset[light][0]
		directional.light_energy = preset[light][1]
		directional.rotation_degrees = preset[light][2]


func _build_stage() -> void:
	_stage = build_studio(_viewport, transparent)

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
