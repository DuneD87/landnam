class_name FishBloodCloud extends Node3D

## Small underwater puff, retained for reuse by its habitat. No debris or physics bodies.
const LIFETIME: float = 3.0
var active: bool = false
var _age: float = 0.0
var _particles: GPUParticles3D
var _water: WaterFaunaHabitat


func _ready() -> void:
	add_to_group("fish_blood_cloud")
	_particles = GPUParticles3D.new()
	_particles.amount = 20
	_particles.lifetime = LIFETIME
	_particles.one_shot = true
	_particles.explosiveness = 1.0
	_particles.emitting = false
	_particles.local_coords = true
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_particles.visibility_aabb = AABB(Vector3.ONE * -2.5, Vector3.ONE * 5.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.18
	process.spread = 180.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.55
	process.damping_min = 0.25
	process.damping_max = 0.5
	process.scale_min = 0.5
	process.scale_max = 1.1
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.3))
	growth.add_point(Vector2(0.5, 0.8))
	growth.add_point(Vector2(1.0, 1.0))
	var curve := CurveTexture.new()
	curve.curve = growth
	process.scale_curve = curve
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var gradient := GradientTexture1D.new()
	gradient.gradient = ramp
	process.color_ramp = gradient
	_particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 1.3
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/fauna/fish_blood_cloud.gdshader")
	quad.material = material
	_particles.draw_pass_1 = quad
	add_child(_particles)
	visible = false
	set_process(false)


func burst(point: Vector3, water: WaterFaunaHabitat) -> void:
	_water = water
	global_position = point
	_age = 0.0
	active = true
	visible = true
	set_process(true)
	_update_water()
	reset_physics_interpolation()
	_particles.restart()
	_particles.emitting = true


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME + 0.15:
		active = false
		visible = false
		_particles.emitting = false
		# Break the habitat/cloud ownership cycle while the pooled effect is idle.
		_water = null
		set_process(false)
		return
	_update_water()


func _update_water() -> void:
	_particles.set_instance_shader_parameter("planet_center", _water.center())
	_particles.set_instance_shader_parameter("water_radius", _water.surface_radius(global_position))
