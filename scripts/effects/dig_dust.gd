class_name DigDust
extends RefCounted

## Lo que salta al picar el terreno: terrones del color del suelo y una nube de polvo. Los
## emisores se reciclan en un pool, como BlockDebris y WoodChips: crear un GPUParticles3D con sus
## materiales en cada golpe cuesta milisegundos de main thread. Cada emisor tiene su material de
## proceso (la dirección, la gravedad y el color cambian en cada golpe) y comparten las mallas.

const POOL := 4
const GRAVITY := 9.8
const CLODS := 18
const CLOD_LIFETIME := 1.1
const PUFFS := 8
const PUFF_LIFETIME := 1.8
## Color de lo que se rompe por familia de sonido del suelo (SurfaceAudio): bajo la hierba, tierra.
const COLORS := {
	&"dirtyground": Color(0.42, 0.33, 0.24),
	&"grass": Color(0.38, 0.30, 0.20),
	&"leaves": Color(0.38, 0.30, 0.20),
	&"mud": Color(0.30, 0.24, 0.17),
	&"sand": Color(0.78, 0.69, 0.52),
	&"gravel": Color(0.52, 0.50, 0.47),
	&"rock": Color(0.55, 0.53, 0.50),
	&"snow": Color(0.90, 0.93, 0.97),
}
const DEFAULT_COLOR := Color(0.42, 0.33, 0.24)

## Pares [terrones, polvo].
static var _pool: Array = []
static var _next: int = 0
static var _clod_mesh: Mesh = null
static var _puff_mesh: Mesh = null


static func color_of(family: StringName) -> Color:
	return COLORS.get(family, DEFAULT_COLOR)


## Golpe en [world_pos], en una superficie de normal [normal]; [up] es el up del planeta. [color]
## el del suelo; [power] 0..1 da la cantidad.
static func burst(context: Node, world_pos: Vector3, normal: Vector3, up: Vector3, color: Color,
		power: float) -> void:
	if context == null or not context.is_inside_tree():
		return
	var scene_root := context.get_tree().current_scene
	if scene_root == null:
		return
	# Un cambio de escena libera los nodos y deja el pool con referencias muertas.
	if not _pool.is_empty() and not is_instance_valid(_pool[0][0]):
		_pool.clear()
		_next = 0
	var pair: Array
	if _pool.size() < POOL:
		pair = [_build_clods(), _build_puff()]
		for node in pair:
			scene_root.add_child(node)
			node.add_to_group("floating_origin")
		_pool.append(pair)
	else:
		pair = _pool[_next]
		_next = (_next + 1) % POOL
	# Saltan de la superficie y algo hacia arriba, también de una pared.
	var out := (normal + up * 0.6).normalized() if normal.length_squared() > 1e-6 else up
	var clods := (pair[0] as GPUParticles3D).process_material as ParticleProcessMaterial
	clods.gravity = -up * GRAVITY
	clods.color = color
	var puff := (pair[1] as GPUParticles3D).process_material as ParticleProcessMaterial
	puff.gravity = -up * 0.3
	puff.color = color.lightened(0.15)
	for node in pair:
		var emitter := node as GPUParticles3D
		(emitter.process_material as ParticleProcessMaterial).direction = out
		emitter.amount_ratio = lerpf(0.4, 1.0, clampf(power, 0.0, 1.0))
		emitter.global_position = world_pos
		emitter.reset_physics_interpolation()
		emitter.restart()


static func _build_clods() -> GPUParticles3D:
	var node := _emitter("DigClods", CLODS, CLOD_LIFETIME, 0.95)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.1
	mat.spread = 40.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 3.8
	mat.damping_min = 0.5
	mat.damping_max = 1.5
	mat.angular_velocity_min = -540.0
	mat.angular_velocity_max = 540.0
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	# Se encogen al final: caen dentro del suelo y no chocan con él.
	mat.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(0.7, 1.0), Vector2(1.0, 0.0)])
	# Unos del color del suelo y otros más oscuros.
	mat.color_initial_ramp = _ramp([0.0, 1.0], [Color.WHITE, Color(0.7, 0.7, 0.7)])
	node.process_material = mat
	node.draw_pass_1 = _clod()
	return node


static func _build_puff() -> GPUParticles3D:
	var node := _emitter("DigPuff", PUFFS, PUFF_LIFETIME, 0.9)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.15
	mat.spread = 60.0
	mat.initial_velocity_min = 0.4
	mat.initial_velocity_max = 1.6
	mat.damping_min = 1.0
	mat.damping_max = 2.0
	mat.scale_min = 0.6
	mat.scale_max = 1.3
	# Crece y se desvanece.
	mat.scale_curve = _curve([Vector2(0.0, 0.4), Vector2(1.0, 1.0)])
	mat.color_ramp = _ramp([0.0, 0.15, 1.0], [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
	node.process_material = mat
	node.draw_pass_1 = _puff()
	return node


static func _emitter(node_name: String, amount: int, lifetime: float, explosiveness: float) -> GPUParticles3D:
	var node := GPUParticles3D.new()
	node.name = node_name
	node.amount = amount
	node.lifetime = lifetime
	node.one_shot = true
	node.explosiveness = explosiveness
	node.emitting = false
	node.local_coords = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_aabb = AABB(Vector3.ONE * -4.0, Vector3.ONE * 8.0)
	return node


static func _curve(points: Array) -> CurveTexture:
	var curve := Curve.new()
	for point in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


static func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## Un terrón: una piedrecita irregular, del color que le da el emisor.
static func _clod() -> Mesh:
	if _clod_mesh == null:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.07, 0.05, 0.06)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 1.0
		mesh.material = mat
		_clod_mesh = mesh
	return _clod_mesh


static func _puff() -> Mesh:
	if _puff_mesh == null:
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.6, 0.6)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.albedo_texture = _soft_disc()
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.roughness = 1.0
		mesh.material = mat
		_puff_mesh = mesh
	return _puff_mesh


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
