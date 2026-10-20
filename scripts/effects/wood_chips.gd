class_name WoodChips
extends RefCounted

## Astillas que salta un hachazo en un tronco, y el polvo y las hojas que levanta un árbol al caer.
## Los emisores se reciclan en pools, como BlockDebris: crear un GPUParticles3D con sus
## materiales en cada golpe cuesta milisegundos de main thread. Cada emisor tiene su material de
## proceso (la dirección y la gravedad cambian en cada golpe) y comparten las mallas.

const CHIP_LIFETIME := 1.3
const MAX_CHIPS := 24
const CHIP_POOL := 4
const GRAVITY := 9.8
## Madera recién cortada: clara, con algo de corteza oscura entre las astillas.
const CHIP_COLOR := Color(0.78, 0.64, 0.44)
const BARK_COLOR := Color(0.28, 0.21, 0.15)
## La caída: polvo de tierra y hojarasca a lo largo del tronco tumbado.
const CRASH_POOL := 2
const DUST_COLOR := Color(0.52, 0.46, 0.38)
const LEAF_COLORS := [Color(0.30, 0.38, 0.16), Color(0.42, 0.44, 0.18), Color(0.45, 0.33, 0.16)]

static var _chips: Array[GPUParticles3D] = []
static var _next_chip: int = 0
## Pares [polvo, hojas].
static var _crashes: Array = []
static var _next_crash: int = 0
static var _chip_mesh: Mesh = null
static var _dust_mesh: Mesh = null
static var _leaf_mesh: Mesh = null


## Astillas de un hachazo en [world_pos], saltando hacia [out] (fuera del tronco, hacia quien
## golpea). [up]: el up del planeta. [power] 0..1 da la cantidad.
static func burst(context: Node, world_pos: Vector3, out: Vector3, up: Vector3, power: float) -> void:
	var scene_root := _scene_root(context)
	if scene_root == null:
		return
	if not _chips.is_empty() and not is_instance_valid(_chips[0]):
		_chips.clear()
		_next_chip = 0
	var node: GPUParticles3D
	if _chips.size() < CHIP_POOL:
		node = _build_chips()
		_adopt(scene_root, node)
		_chips.append(node)
	else:
		node = _chips[_next_chip]
		_next_chip = (_next_chip + 1) % CHIP_POOL
	var mat := node.process_material as ParticleProcessMaterial
	# Hacia fuera y algo hacia arriba: las astillas saltan del corte y caen delante del tronco.
	mat.direction = (out + up * 0.45).normalized()
	mat.gravity = -up * GRAVITY
	node.amount_ratio = lerpf(0.35, 1.0, clampf(power, 0.0, 1.0))
	node.global_position = world_pos
	node.reset_physics_interpolation()
	node.restart()


## Polvo y hojarasca a lo largo de un tronco que acaba de caer: de [from] (la base) a [to] (la
## copa), con [radius] el de la copa. [up]: el up del planeta. [power] 0..1, por el tamaño.
static func crash(context: Node, from: Vector3, to: Vector3, radius: float, up: Vector3, power: float) -> void:
	var scene_root := _scene_root(context)
	if scene_root == null or from.is_equal_approx(to):
		return
	if not _crashes.is_empty() and not is_instance_valid(_crashes[0][0]):
		_crashes.clear()
		_next_crash = 0
	var pair: Array
	if _crashes.size() < CRASH_POOL:
		pair = [_build_dust(), _build_leaves()]
		for node in pair:
			_adopt(scene_root, node)
		_crashes.append(pair)
	else:
		pair = _crashes[_next_crash]
		_next_crash = (_next_crash + 1) % CRASH_POOL
	# El emisor se orienta con el tronco: su caja de emisión va a lo largo de Z.
	var along := (to - from).normalized()
	var side := along.cross(up)
	if side.length_squared() < 1e-4:
		side = along.cross(Vector3.RIGHT if absf(along.x) < 0.9 else Vector3.FORWARD)
	side = side.normalized()
	var frame := Basis(side, along.cross(side), along).orthonormalized()
	var half := from.distance_to(to) * 0.5
	var amount := lerpf(0.4, 1.0, clampf(power, 0.0, 1.0))
	var dust: GPUParticles3D = pair[0]
	var leaves: GPUParticles3D = pair[1]
	var dust_mat := dust.process_material as ParticleProcessMaterial
	dust_mat.emission_box_extents = Vector3(radius * 0.6, 0.3, half)
	dust_mat.direction = frame.inverse() * up
	dust_mat.gravity = -up * 0.4
	var leaf_mat := leaves.process_material as ParticleProcessMaterial
	# Las hojas, sobre todo de la mitad de arriba: es donde estaba la copa.
	leaf_mat.emission_box_extents = Vector3(radius, radius * 0.5, half * 0.6)
	leaf_mat.direction = frame.inverse() * up
	leaf_mat.gravity = -up * 1.6
	for node in pair:
		var emitter := node as GPUParticles3D
		emitter.amount_ratio = amount
		emitter.global_transform = Transform3D(frame, from.lerp(to, 0.5))
		emitter.reset_physics_interpolation()
		emitter.restart()
	leaves.global_position = from.lerp(to, 0.7)


static func _scene_root(context: Node) -> Node:
	if context == null or not context.is_inside_tree():
		return null
	return context.get_tree().current_scene


static func _adopt(scene_root: Node, node: GPUParticles3D) -> void:
	scene_root.add_child(node)
	node.add_to_group("floating_origin")


static func _build_chips() -> GPUParticles3D:
	var node := BurstParticles.create(MAX_CHIPS, CHIP_LIFETIME, 0.95, "WoodChips")
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.06
	mat.spread = 38.0
	mat.initial_velocity_min = 1.8
	mat.initial_velocity_max = 5.0
	mat.damping_min = 0.3
	mat.damping_max = 1.2
	mat.angular_velocity_min = -720.0
	mat.angular_velocity_max = 720.0
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	# Una de cada cinco, más oscura: un trozo de corteza.
	mat.color_initial_ramp = BurstParticles.ramp([0.0, 0.8, 0.81, 1.0], [CHIP_COLOR, CHIP_COLOR, BARK_COLOR, BARK_COLOR])
	node.process_material = mat
	node.draw_pass_1 = _chip()
	node.visibility_aabb = AABB(Vector3.ONE * -4.0, Vector3.ONE * 8.0)
	return node


static func _build_dust() -> GPUParticles3D:
	var node := BurstParticles.create(48, 2.6, 0.9, "TreeCrashDust")
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.spread = 70.0
	mat.initial_velocity_min = 0.6
	mat.initial_velocity_max = 2.4
	mat.damping_min = 1.0
	mat.damping_max = 2.0
	mat.scale_min = 0.6
	mat.scale_max = 1.6
	# Crece y se desvanece.
	mat.scale_curve = BurstParticles.curve([Vector2(0.0, 0.4), Vector2(1.0, 1.0)])
	mat.color_ramp = BurstParticles.ramp([0.0, 0.15, 1.0], [Color(DUST_COLOR, 0.0), Color(DUST_COLOR, 0.45), Color(DUST_COLOR, 0.0)])
	node.process_material = mat
	node.draw_pass_1 = _dust()
	node.visibility_aabb = AABB(Vector3.ONE * -20.0, Vector3.ONE * 40.0)
	return node


static func _build_leaves() -> GPUParticles3D:
	var node := BurstParticles.create(64, 3.2, 0.85, "TreeCrashLeaves")
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.spread = 80.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.5
	# Mucho rozamiento: las hojas planean y caen despacio.
	mat.damping_min = 2.0
	mat.damping_max = 3.5
	mat.angular_velocity_min = -360.0
	mat.angular_velocity_max = 360.0
	mat.scale_min = 0.6
	mat.scale_max = 1.3
	mat.color_initial_ramp = BurstParticles.ramp([0.0, 0.5, 1.0], LEAF_COLORS)
	node.process_material = mat
	node.draw_pass_1 = _leaf()
	node.visibility_aabb = AABB(Vector3.ONE * -20.0, Vector3.ONE * 40.0)
	return node


## Una astilla: una lámina fina y alargada que gira al volar.
static func _chip() -> Mesh:
	if _chip_mesh == null:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.05, 0.012, 0.022)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		mesh.material = mat
		_chip_mesh = mesh
	return _chip_mesh


static func _dust() -> Mesh:
	if _dust_mesh == null:
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.9, 0.9)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.albedo_texture = _soft_disc()
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mesh.material = mat
		_dust_mesh = mesh
	return _dust_mesh


static func _leaf() -> Mesh:
	if _leaf_mesh == null:
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.07, 0.05)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.85
		mesh.material = mat
		_leaf_mesh = mesh
	return _leaf_mesh


## Disco de borde suave para el polvo.
static func _soft_disc() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	return texture
