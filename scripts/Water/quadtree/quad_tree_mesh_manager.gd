extends Node3D
class_name QuadTreeMeshManager

## Sincroniza las mallas de agua con el quadtree: crea, actualiza y elimina QuadSurface(Compute) por
## parche activo (modo CPU o GPU con recursos compute compartidos) y actualiza los uniforms del material.

enum ComputeMode {
	CPU,
	GPU
}

@export var default_material: Material
@export var compute_mode: ComputeMode = ComputeMode.GPU
@export var preload_compute_shader: bool = true
@export var atmosphere_height: float = 1000.0
@export var radius: float
@export var sub_divisions: int = 32
@export var player: CharacterBody3D

## Presupuesto por frame para dar de alta y de baja parches. Se acota por tiempo y no por número
## porque el coste de crear uno varía mucho: en modo GPU cada parche es un submit() + sync() + tres
## lecturas de buffer, un viaje a la GPU que bloquea el hilo principal.
@export var surface_budget_ms: float = 3.0

var active_quads: Dictionary = {}
var quad_tree_manager: Node3D

## Construir el conjunto de parches que pide el quadtree puede llevar varios frames, pero hasta que
## está entero NO se enseña nada: si se fueran mostrando a medias, un quad padre y sus cuatro hijos
## coexistirían coplanares y el agua parpadea por z-fighting. De ahí los tres estados.
var _target: Dictionary = {}     # id -> quad_info del conjunto que se está construyendo
var _building: Array = []        # ids que faltan por construir
var _staged: Dictionary = {}     # id -> parche ya construido pero OCULTO, esperando el relevo
var _retiring: Array = []        # parches ya ocultos, pendientes de liberar
var _needs_commit: bool = false

var compute_shader_loaded: bool = false
var shared_rd: RenderingDevice
var shared_compute_shader: RID
var shared_compute_pipeline: RID

func initialize(quadtree_manager: Node3D):
	quad_tree_manager = quadtree_manager
	quad_tree_manager.quadtree_changed.connect(_on_quadtree_changed)
	
	if compute_mode == ComputeMode.GPU and preload_compute_shader:
		_initialize_compute_resources()

func _initialize_compute_resources():
	shared_rd = RenderingServer.create_local_rendering_device()
	
	var shader_path = "res://shaders/Compute/quad_surface_compute.glsl"
	if not ResourceLoader.exists(shader_path):
		push_warning("Compute shader not found at " + shader_path + ". Falling back to CPU mode.")
		compute_mode = ComputeMode.CPU
		return false
	
	var shader_file = load(shader_path) as RDShaderFile
	if not shader_file:
		var file = FileAccess.open(shader_path, FileAccess.READ)
		if not file:
			push_error("Could not load compute shader file")
			compute_mode = ComputeMode.CPU
			return false
			
		var shader_code = file.get_as_text()
		file.close()
		
		var shader_source := RDShaderSource.new()
		shader_source.source_compute = shader_code
		shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		
		var shader_spirv = shared_rd.shader_compile_spirv_from_source(shader_source)
		if shader_spirv.compile_error_compute != "":
			push_error("Compute shader compilation error: " + shader_spirv.compile_error_compute)
			compute_mode = ComputeMode.CPU
			return false
			
		shared_compute_shader = shared_rd.shader_create_from_spirv(shader_spirv)
	else:
		var shader_spirv = shader_file.get_spirv()
		shared_compute_shader = shared_rd.shader_create_from_spirv(shader_spirv)

	shared_compute_pipeline = shared_rd.compute_pipeline_create(shared_compute_shader)
	compute_shader_loaded = true
	return true

## Apunta qué conjunto de parches hace falta; construirlo se reparte entre frames en _process.
## Las actualizaciones de los ya visibles sí van aquí: no cuestan nada salvo que el quad se haya
## movido, y retrasarlas los descolocaría.
func _on_quadtree_changed(active_quad_data: Array):
	var next: Dictionary = {}
	for quad_info in active_quad_data:
		next[quad_info.id] = quad_info
		if active_quads.has(quad_info.id):
			_update_quad_surface(quad_info)
	_target = next

	# Lo ya construido que sigue haciendo falta se conserva; lo que ha dejado de hacer falta se
	# retira sin haberse llegado a ver.
	for quad_id in _staged.keys():
		if not _target.has(quad_id):
			_retiring.append(_staged[quad_id])
			_staged.erase(quad_id)

	# La cola se recalcula entera, no se acumula: entre un frame y el siguiente el quadtree puede
	# haber cambiado de idea, y encolar sin más dejaría parches que ya nadie quiere.
	_building.clear()
	for quad_id in _target:
		if not active_quads.has(quad_id) and not _staged.has(quad_id):
			_building.append(quad_id)
	_needs_commit = true


## Avanza la construcción dentro del presupuesto del frame y, cuando el conjunto está completo,
## hace el relevo. Liberar los retirados va al final porque ya están ocultos: no se ven aunque
## tarden varios frames en desaparecer del todo.
func _advance_surface_work() -> void:
	if _building.is_empty() and _retiring.is_empty() and not _needs_commit:
		return

	var probe_start := Time.get_ticks_usec()
	var deadline := probe_start + int(maxf(surface_budget_ms, 0.1) * 1000.0)
	# Sin un solo parche todavía (arranque, o cambio de modo) no hay nada que proteger: mejor un
	# tirón durante la carga que ver el océano aparecer a trozos durante segundos.
	var unlimited := active_quads.is_empty()

	while not _building.is_empty():
		var quad_id = _building.pop_back()
		if _target.has(quad_id) and not active_quads.has(quad_id) and not _staged.has(quad_id):
			_staged[quad_id] = _create_quad_surface(_target[quad_id])
			if not unlimited and Time.get_ticks_usec() >= deadline:
				break

	if _building.is_empty() and _needs_commit:
		_commit_target()
		_needs_commit = false

	while not _retiring.is_empty():
		var surface = _retiring.pop_back()
		if is_instance_valid(surface):
			surface.queue_free()
		if not unlimited and Time.get_ticks_usec() >= deadline:
			break


## Relevo: enseña de golpe lo construido y oculta lo que sobra. Es lo que garantiza que nunca se
## vean a la vez un quad y sus hijos. Mostrar y ocultar es gratis, así que da igual que toque
## cientos de parches; lo caro (construir y liberar) queda fuera, repartido.
func _commit_target() -> void:
	for quad_id in _staged:
		var surface = _staged[quad_id]
		surface.visible = true
		active_quads[quad_id] = surface
	_staged.clear()

	for quad_id in active_quads.keys():
		if not _target.has(quad_id):
			var surface = active_quads[quad_id]
			surface.visible = false
			_retiring.append(surface)
			active_quads.erase(quad_id)

## Construye un parche y lo devuelve oculto y sin dar de alta: quién lo enseña lo decide
## _commit_target.
func _create_quad_surface(quad_info: Dictionary) -> Node3D:
	var quad_surface

	if compute_mode == ComputeMode.GPU:
		if not compute_shader_loaded:
			_initialize_compute_resources()
		
		if compute_mode == ComputeMode.GPU:
			quad_surface = QuadSurfaceCompute.new()
			quad_surface.set_shared_resources(shared_rd, shared_compute_shader, shared_compute_pipeline)
		else:
			quad_surface = QuadSurface.new()
	else:
		quad_surface = QuadSurface.new()
	
	var local_position = to_local(quad_info.position)

	# Resolución completa también en niveles bajos: con pocas subdivisiones un quad que abarca mucho
	# arco se hunde bajo la esfera entre vértices (cuerda vs arco) y el fondo marino asoma a lo lejos.
	quad_surface.setup(
		local_position,
		quad_info.size,
		quad_info.face_normal,
		quad_info.face_up,
		quad_info.face_right,
		radius,
		sub_divisions,
		quad_info.level
	)

	if quad_surface.mesh:
		quad_surface.mesh.surface_set_material(0, default_material)

	quad_surface.visible = false
	add_child(quad_surface)
	return quad_surface

func _update_quad_surface(quad_info: Dictionary):
	var quad_surface = active_quads[quad_info.id]

	var local_position = to_local(quad_info.position)

	# Comparar en local y con tolerancia, nunca 'global_position != position'. Ese sitio hace un
	# viaje de ida y vuelta (to_local al crear el parche, global_position al leerlo) que con el
	# planeta lejos del origen no es exacto en coma flotante: fallaba para la mayoría de los
	# parches y regeneraba su malla entera (submit+sync del compute) en cada paso del quadtree.
	var moved := local_position.distance_squared_to(quad_surface.position) > \
		pow(quad_info.size * 1e-3, 2.0)

	if moved or quad_surface.quad_size != quad_info.size:
		quad_surface.setup(
			local_position,
			quad_info.size,
			quad_info.face_normal,
			quad_info.face_up,
			quad_info.face_right,
			radius,
			sub_divisions,
			quad_info.level
		)

		# setup() regenera un ArrayMesh nuevo sin material; hay que reaplicarlo o el quad
		# renderiza con el material blanco por defecto (visible tras un rebase del FloatingOrigin).
		if quad_surface.mesh:
			quad_surface.mesh.surface_set_material(0, default_material)

func _remove_quad_surface(quad_id):
	if active_quads.has(quad_id):
		var quad_surface = active_quads[quad_id]
		quad_surface.queue_free()
		active_quads.erase(quad_id)

func set_compute_mode(mode: ComputeMode):
	if compute_mode == mode:
		return
		
	compute_mode = mode
	
	if mode == ComputeMode.CPU and shared_compute_shader.is_valid():
		if shared_compute_pipeline.is_valid():
			shared_rd.free_rid(shared_compute_pipeline)
			shared_compute_pipeline = RID()
		shared_rd.free_rid(shared_compute_shader)
		shared_compute_shader = RID()
		compute_shader_loaded = false
	elif mode == ComputeMode.GPU and not compute_shader_loaded:
		_initialize_compute_resources()
	
	var quad_data = []
	for quad_id in active_quads:
		var quad = active_quads[quad_id]
		var quad_info = {
			"id": quad_id,
			"position": quad.global_position,
			"size": quad.quad_size,
			"level": quad.quad_level,
			"face_normal": quad.face_normal,
			"face_up": quad.face_up,
			"face_right": quad.face_right
		}
		quad_data.append(quad_info)
	
	for quad_id in active_quads.keys():
		_remove_quad_surface(quad_id)

	# Cambiar de modo es una acción manual de depuración: aquí sí se rehace todo de golpe, y el
	# trabajo repartido se descarta para que no deshaga lo que se acaba de construir.
	_building.clear()
	_staged.clear()
	_needs_commit = false
	for quad_info in quad_data:
		var surface := _create_quad_surface(quad_info)
		surface.visible = true
		active_quads[quad_info.id] = surface

func get_statistics() -> Dictionary:
	var stats = {
		"active_quads": active_quads.size(),
		"compute_mode": "GPU" if compute_mode == ComputeMode.GPU else "CPU",
		"total_vertices": 0,
		"total_triangles": 0
	}
	
	for quad in active_quads.values():
		var resolution = quad.quad_resolution
		stats.total_vertices += (resolution + 1) * (resolution + 1)
		stats.total_triangles += resolution * resolution * 2
	
	return stats
	
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_advance_surface_work()
	var camera = player.camera
	if !camera:
		return
	var distance = camera.global_position.distance_to(global_position)
	var altitude = distance - radius
	if distance > (radius + atmosphere_height):
		default_material.render_priority = 0
	else:
		default_material.render_priority = 0
	
	default_material.set_shader_parameter("camera_altitude", altitude)
	default_material.set_shader_parameter("atmosphere_height", atmosphere_height)
	default_material.set_shader_parameter("water_radius", radius)

func _exit_tree():
	if shared_compute_pipeline.is_valid():
		shared_rd.free_rid(shared_compute_pipeline)
	if shared_compute_shader.is_valid():
		shared_rd.free_rid(shared_compute_shader)
