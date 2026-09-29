class_name SeaIceRigidFloe extends RigidBody3D

## Témpano suelto: SeaIceFloes lo saca de la malla de su bloque cuando se le acerca un barco (o
## otro témpano suelto a la deriva) y a partir de ahí lo mueve la física. Flota con un muelle hacia
## la superficie del agua (la misma ola que el resto, sin las más cortas que él), se alinea con su
## normal y el agua lo frena. El barco lo empuja según las masas, y un embiste que supere su
## resistencia lo parte (SeaIceFloes.shatter).
##
## Va en la capa del mundo: lo tocan los barcos, el jugador y los demás témpanos sueltos.

const ICE_DENSITY := 917.0
## Energía para partirlo, por m² de sección (ancho × grosor): la placa cede por flexión a lo largo
## de una grieta que la cruza. Con un casco de ~20 t (la masa efectiva de impacto): a 12 m/s parte
## trozos de unos 10 m; a 20 m/s, placas de 25 m. Las mayores piden varias embestidas.
const BREAK_ENERGY_PER_M2 := 4000.0
## Muelle de flotación (rad/s) y su amortiguamiento, en vertical y en cabeceo.
const HEAVE_FREQ := 2.2
const TILT_FREQ := 1.8
const DAMPING := 0.8
## Frenado del agua en horizontal (1/s): un témpano empujado se desliza unos segundos.
const DRAG := 0.35

var floe: Dictionary
var damage := 0.0
var _owner: SeaIceFloes
var _sea_radius: float
var _break_energy: float
var _mesh: MeshInstance3D
var _target_height := 0.0
var _target_normal := Vector3.UP
var _wave_tick := 0


## `xf`: dónde está ahora (relativo al planeta, que es el marco de SeaIceFloes).
func setup(owner_floes: SeaIceFloes, data: Dictionary, xf: Transform3D, material: ShaderMaterial,
		velocity: Vector3) -> void:
	name = "LooseFloe"
	_owner = owner_floes
	floe = data
	_sea_radius = owner_floes.sea_radius
	collision_layer = 1
	collision_mask = 1
	gravity_scale = 0.0
	can_sleep = false
	angular_damp = 0.8
	var poly: PackedVector2Array = data.poly
	var thickness := float(data.top) - float(data.bottom)
	var area := absf(SeaIceLayout._area(poly))
	mass = maxf(area * thickness * ICE_DENSITY, 50.0)
	_break_energy = BREAK_ENERGY_PER_M2 * 2.0 * float(data.radius) * thickness
	var points := PackedVector3Array()
	for v in poly:
		points.append(Vector3(v.x, data.top, v.y))
		points.append(Vector3(v.x, data.bottom, v.y))
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	var shape := CollisionShape3D.new()
	shape.shape = convex
	add_child(shape)
	# La malla del témpano en su marco local (centro en la línea de agua).
	var local := data.duplicate()
	local.center = Vector3.ZERO
	local.basis = Basis.IDENTITY
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		SeaIceMeshes.floe_arrays([local], Vector3.ZERO), [], {}, SeaIceMeshes.FLOE_FORMAT)
	mesh.surface_set_material(0, material)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	add_child(_mesh)
	transform = xf
	_mesh.set_instance_shader_parameter(&"rest_origin", xf.origin)
	linear_velocity = velocity
	_target_normal = xf.origin.normalized()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var local := state.transform.origin - _owner.global_position
	var up := local.normalized()
	var height := local.length() - _sea_radius
	# La ola, un tick de cada tres: varía en segundos y es lo que cuesta. Con la banquisa cerrada
	# no hay oleaje y ni se muestrea.
	if float(floe.ice) < 0.95:
		_wave_tick = (_wave_tick + 1) % 3
		if _wave_tick == 0:
			var time := WaterHeightSampler.get_water_time(_owner.water_material)
			var disp := _owner.wave_sampler().rest_displacement(up * _sea_radius, time,
				float(floe.radius) * SeaIceFloes.FLOE_WAVE_FILTER)
			_target_height = disp.dot(up)
			_target_normal = _owner.wave_sampler().last_normal()
	else:
		_target_height = 0.0
		_target_normal = up
	var dt := state.step
	var v := state.linear_velocity
	var v_up := v.dot(up)
	var accel := up * (-HEAVE_FREQ * HEAVE_FREQ * (height - _target_height) - 2.0 * DAMPING * HEAVE_FREQ * v_up)
	accel -= (v - up * v_up) * DRAG
	state.linear_velocity = v + accel * dt
	var axis := state.transform.basis.y.normalized().cross(_target_normal)
	var w := state.angular_velocity
	state.angular_velocity = w + (axis * TILT_FREQ * TILT_FREQ - w * 2.0 * DAMPING * TILT_FREQ) * dt


## Embiste de un barco (DynamicGridBody._apply_impact), en julios. Se acumula.
func ram_damage(energy: float, world_pos: Vector3, rammer: Node) -> void:
	damage += energy
	if damage >= _break_energy:
		_owner.shatter(self, world_pos, rammer)
	else:
		AudioManager.play_material(&"block_impact", &"rock", world_pos, {"volume_offset_db": -10.0})
