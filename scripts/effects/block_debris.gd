class_name BlockDebris
extends RefCounted

## Ráfaga de escombros de bloques destruidos. Los emisores se reciclan en un pool: crear un
## GPUParticles3D con sus materiales por impacto costaba ~11 ms de main thread —recursos nuevos
## del RenderingServer, que sincronizan con el hilo de render— frente a ~0.1 ms reutilizando.
## La gravedad se orienta contra el 'up' del planeta que pasa el llamante, así que los cascotes
## caen bien en cualquier punto de la esfera.

const LIFETIME := 1.6
const PARTICLES_PER_BLOCK := 6
const MAX_PARTICLES := 48
const GRAVITY := 12.0
## Color de los cascotes. Es del mesh compartido, así que no puede variar por bloque: hacerlo
## dependiente del material exigiría un mesh (y un draw pass) por material.
const DEBRIS_COLOR := Color(0.55, 0.53, 0.5)
## Ráfagas simultáneas antes de reciclar la más antigua. Cada emisor tiene su propio material de
## proceso: comparten mesh, pero no el 'up', que difiere entre barcos lejanos del planeta.
const POOL_SIZE := 6

static var _pool: Array = []
static var _next: int = 0
static var _shared_mesh: Mesh = null


## Crea el primer emisor sin emitir, para pagar de antemano la creación de sus recursos y la
## compilación de sus shaders. Medido: la primera ráfaga costaba ~14.5 ms y las siguientes ~0.08.
static func prewarm(context: Node) -> void:
	if not context or not context.is_inside_tree():
		return
	if not _pool.is_empty() and is_instance_valid(_pool[0]):
		return
	var scene_root := context.get_tree().current_scene
	if scene_root:
		_acquire(scene_root)


## Lanza una ráfaga en un punto del mundo. 'up' es el up gravitacional del planeta portador.
static func burst(context: Node, world_pos: Vector3, up: Vector3, block_count: int,
	cell_size: float = 1.0) -> void:

	if not context or not context.is_inside_tree():
		return
	var scene_root := context.get_tree().current_scene
	if not scene_root:
		return

	var node := _acquire(scene_root)
	if not node:
		return

	# El mesh es compartido y de tamaño fijo: la escala de la celda entra por el material de
	# proceso, que sí es propio de cada emisor.
	var mat := node.process_material as ParticleProcessMaterial
	mat.direction = up
	mat.gravity = -up * GRAVITY
	mat.emission_sphere_radius = cell_size * 0.6
	mat.scale_min = 0.5 * cell_size
	mat.scale_max = 1.4 * cell_size

	# El nº de partículas se modula con amount_ratio: cambiar 'amount' reasigna los buffers de la
	# GPU, que es justo el coste que el pool existe para evitar.
	node.amount_ratio = clampf(float(block_count * PARTICLES_PER_BLOCK) / float(MAX_PARTICLES), 0.15, 1.0)
	node.global_position = world_pos
	node.reset_physics_interpolation()
	node.restart()


## Emisor libre del pool, creándolo la primera vez. Los nodos viven en la escena entre ráfagas.
static func _acquire(scene_root: Node) -> GPUParticles3D:
	# Un cambio de escena libera los nodos y deja el pool con referencias muertas.
	if not _pool.is_empty() and not is_instance_valid(_pool[0]):
		_pool.clear()
		_next = 0
		_shared_mesh = null

	if _pool.size() < POOL_SIZE:
		var fresh := _build_emitter()
		scene_root.add_child(fresh)
		fresh.add_to_group("floating_origin")
		_pool.append(fresh)
		return fresh

	var node: GPUParticles3D = _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	return node


static func _build_emitter() -> GPUParticles3D:
	var node := GPUParticles3D.new()
	node.name = "BlockDebris"
	node.amount = MAX_PARTICLES
	node.lifetime = LIFETIME
	node.one_shot = true
	node.explosiveness = 1.0
	node.emitting = false
	node.process_material = _build_process_material()
	node.draw_pass_1 = _get_shared_mesh()
	# La AABB por defecto es la del emisor: sin ampliarla los cascotes se recortan al salir de ella.
	node.visibility_aabb = AABB(Vector3.ONE * -6.0, Vector3.ONE * 12.0)
	return node


static func _build_process_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.6
	mat.direction = Vector3.UP
	mat.spread = 70.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 7.0
	mat.gravity = Vector3.DOWN * GRAVITY
	mat.damping_min = 0.5
	mat.damping_max = 2.0
	mat.angular_velocity_min = -540.0
	mat.angular_velocity_max = 540.0
	mat.scale_min = 0.5
	mat.scale_max = 1.4
	return mat


## Mesh y material de dibujo son constantes entre ráfagas: se construyen una vez y se comparten.
static func _get_shared_mesh() -> Mesh:
	if _shared_mesh:
		return _shared_mesh

	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.16

	var mat := StandardMaterial3D.new()
	mat.albedo_color = DEBRIS_COLOR
	mat.roughness = 0.9
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mesh.material = mat

	_shared_mesh = mesh
	return _shared_mesh
