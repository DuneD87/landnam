class_name BloodCloud extends Node3D

## Small blood puff, retained for reuse by its habitat. No debris or physics bodies.
## Underwater it hangs in place and clips to the sea surface; in the air it is a shorter
## burst that falls with gravity.
const LIFETIME: float = 3.0
const AIR_LIFETIME: float = 1.8
var active: bool = false
var _age: float = 0.0
var _lifetime: float = LIFETIME
var _underwater: bool = true
var _particles: GPUParticles3D
var _puff: ParticleProcessMaterial
var _habitat: AmbientFaunaHabitat


func _ready() -> void:
	add_to_group("blood_cloud")
	_particles = GPUParticles3D.new()
	_particles.amount = 20
	_particles.lifetime = LIFETIME
	_particles.one_shot = true
	_particles.explosiveness = 1.0
	_particles.emitting = false
	_particles.local_coords = true
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_particles.visibility_aabb = AABB(Vector3.ONE * -2.5, Vector3.ONE * 5.0)
	_puff = ParticleProcessMaterial.new()
	_puff.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_puff.emission_sphere_radius = 0.18
	_puff.spread = 180.0
	_puff.gravity = Vector3.ZERO
	_puff.initial_velocity_min = 0.15
	_puff.initial_velocity_max = 0.55
	_puff.damping_min = 0.25
	_puff.damping_max = 0.5
	_puff.scale_min = 0.5
	_puff.scale_max = 1.1
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.3))
	growth.add_point(Vector2(0.5, 0.8))
	growth.add_point(Vector2(1.0, 1.0))
	var curve := CurveTexture.new()
	curve.curve = growth
	_puff.scale_curve = curve
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var gradient := GradientTexture1D.new()
	gradient.gradient = ramp
	_puff.color_ramp = gradient
	_particles.process_material = _puff
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 1.3
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/fauna/blood_cloud.gdshader")
	quad.material = material
	_particles.draw_pass_1 = quad
	add_child(_particles)
	visible = false
	set_process(false)


func burst(point: Vector3, environment: AmbientFaunaHabitat) -> void:
	_habitat = environment
	global_position = point
	_age = 0.0
	active = true
	visible = true
	set_process(true)
	_apply_medium()
	reset_physics_interpolation()
	_particles.restart()
	_particles.emitting = true


func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime + 0.15:
		active = false
		visible = false
		_particles.emitting = false
		# Break the habitat/cloud ownership cycle while the pooled effect is idle.
		_habitat = null
		set_process(false)
		return
	if _underwater:
		_update_water()


## Retunes the shared particle material for water or air before restarting the burst.
func _apply_medium() -> void:
	_underwater = _habitat != null and _habitat.is_underwater()
	_lifetime = LIFETIME if _underwater else AIR_LIFETIME
	_particles.lifetime = _lifetime
	_particles.set_instance_shader_parameter(&"underwater", 1.0 if _underwater else 0.0)
	if _underwater:
		_puff.gravity = Vector3.ZERO
		_puff.initial_velocity_min = 0.15
		_puff.initial_velocity_max = 0.55
		_puff.damping_min = 0.25
		_puff.damping_max = 0.5
		_particles.visibility_aabb = AABB(Vector3.ONE * -2.5, Vector3.ONE * 5.0)
		_update_water()
		return
	# Particles are simulated in local space, so gravity has to be expressed there too.
	var up := Vector3.UP if _habitat == null else (global_position - _habitat.center()).normalized()
	_puff.gravity = global_basis.inverse() * (-up * 3.0)
	_puff.initial_velocity_min = 1.0
	_puff.initial_velocity_max = 3.2
	_puff.damping_min = 1.5
	_puff.damping_max = 3.0
	# The mist falls a few metres before fading: a tighter box culls it while it is still visible.
	_particles.visibility_aabb = AABB(Vector3.ONE * -6.0, Vector3.ONE * 12.0)


func _update_water() -> void:
	_particles.set_instance_shader_parameter("planet_center", _habitat.center())
	_particles.set_instance_shader_parameter("water_radius", _habitat.surface_radius(global_position))
