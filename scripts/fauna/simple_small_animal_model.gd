class_name SimpleSmallAnimalModel extends Node3D

## Continuous offline-sculpted skin, animated on the GPU with smooth joint weights.
## Mesh resources and material are shared; no geometry is generated during play.
const NAMES := ["Conejo", "Zorro", "Ratón"]
const RADII := [0.13, 0.18, 0.055]
const HEIGHTS := [0.40, 0.65, 0.14]
const MAX_ANIMATION_DISPLACEMENT := [0.09, 0.20, 0.035]
const MESHES: Array[ArrayMesh] = [preload("res://data/fauna/meshes/rabbit.res"), preload("res://data/fauna/meshes/fox.res"), preload("res://data/fauna/meshes/mouse.res")]
static var _material: ShaderMaterial
var body: MeshInstance3D
var _kind: int = 0
var _phase: float = 0.0
var _clock: float = 0.0
var _speed: float = 0.0
var _air: float = 0.0
var _landing: float = 0.0
var _was_grounded: bool = true


func _ready() -> void:
	body = MeshInstance3D.new()
	body.name = "Skin"
	add_child(body)
	set_species(0)


func set_species(kind: int) -> void:
	_kind = clampi(kind, 0, 2)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://shaders/fauna/small_animal.gdshader")
	body.mesh = MESHES[_kind]
	body.material_override = _material
	body.extra_cull_margin = MAX_ANIMATION_DISPLACEMENT[_kind]
	body.set_instance_shader_parameter("species", _kind)
	_phase = 0.0
	_clock = 0.0
	_speed = 0.0
	_air = 0.0
	_landing = 0.0
	_was_grounded = true
	animate(0.0, 0.0)


func animate(time: float, speed: float) -> void:
	# Deterministic posing for previews. Gameplay integrates cadence with advance().
	var cycles := time * (3.0 if _kind == 2 else 2.0)
	_apply_pose(time, cycles, speed, 0.0, 0.0, 0.0, 0.0)


func advance(delta: float, speed: float, grounded: bool = true,
		vertical_speed: float = 0.0, turn: float = 0.0) -> void:
	_clock += delta
	_speed = lerpf(_speed, maxf(speed, 0.0), 1.0 - exp(-delta * 12.0))
	var stride := [0.28, 0.40, 0.095][_kind] as float
	var cadence := minf(_speed / stride, 6.0 if _kind == 2 else 4.5)
	_phase = fposmod(_phase + delta * cadence, 1.0)
	_air = move_toward(_air, 0.0 if grounded else 1.0, delta * 16.0)
	if grounded and not _was_grounded:
		_landing = 1.0
	_landing = move_toward(_landing, 0.0, delta * 7.0)
	_was_grounded = grounded
	_apply_pose(_clock, _phase, _speed, _air, vertical_speed, turn, _landing)


func _apply_pose(time: float, phase: float, speed: float, airborne: float,
		vertical_speed: float, turn: float, landing: float) -> void:
	body.set_instance_shader_parameter("animation_time", time)
	body.set_instance_shader_parameter("gait_phase", phase)
	body.set_instance_shader_parameter("movement", smoothstep(0.02, 0.4, speed))
	body.set_instance_shader_parameter("run_blend", smoothstep(1.8 if _kind == 1 else 0.8, 4.0 if _kind == 1 else 2.0, speed))
	body.set_instance_shader_parameter("airborne", airborne)
	body.set_instance_shader_parameter("vertical_speed", vertical_speed)
	body.set_instance_shader_parameter("turn_amount", clampf(turn, -1.0, 1.0))
	body.set_instance_shader_parameter("landing", landing)
