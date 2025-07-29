extends Node3D
class_name QuadTreeMeshManager

enum ComputeMode {
	CPU,
	GPU
}

@export var default_material: Material
@export var compute_mode: ComputeMode = ComputeMode.GPU
@export var preload_compute_shader: bool = true

var active_quads: Dictionary = {}
var quad_tree_manager: Node3D

# For GPU compute mode - shared resources
var compute_shader_loaded: bool = false
var shared_rd: RenderingDevice
var shared_compute_shader: RID

func initialize(quadtree_manager: Node3D):
	quad_tree_manager = quadtree_manager
	quad_tree_manager.quadtree_changed.connect(_on_quadtree_changed)
	
	# Initialize shared compute resources if using GPU mode
	if compute_mode == ComputeMode.GPU and preload_compute_shader:
		_initialize_compute_resources()

func _initialize_compute_resources():
	# Create shared rendering device
	shared_rd = RenderingServer.create_local_rendering_device()
	
	# Load and compile shader once
	var shader_path = "res://shaders/Compute/quad_surface_compute.glsl"
	if not ResourceLoader.exists(shader_path):
		push_warning("Compute shader not found at " + shader_path + ". Falling back to CPU mode.")
		compute_mode = ComputeMode.CPU
		return false
	
	var shader_file = load(shader_path) as RDShaderFile
	if not shader_file:
		# Try alternative loading method
		var file = FileAccess.open(shader_path, FileAccess.READ)
		if not file:
			push_error("Could not load compute shader file")
			compute_mode = ComputeMode.CPU
			return false
			
		var shader_code = file.get_as_text()
		file.close()
		
		# Create shader from source
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
	
	compute_shader_loaded = true
	return true

func _on_quadtree_changed(active_quad_data: Array):
	_update_quad_surfaces(active_quad_data)

func _create_quad_surface(quad_info: Dictionary):
	var quad_surface
	
	if compute_mode == ComputeMode.GPU:
		if not compute_shader_loaded:
			_initialize_compute_resources()
		
		if compute_mode == ComputeMode.GPU:  # Check again in case it fell back
			quad_surface = QuadSurfaceCompute.new()
			# Pass shared resources to the compute surface
			quad_surface.set_shared_resources(shared_rd, shared_compute_shader)
		else:
			quad_surface = QuadSurface.new()
	else:
		quad_surface = QuadSurface.new()
	
	quad_surface.setup(
		quad_info.position,
		quad_info.size,
		quad_info.face_normal,
		quad_info.face_up,
		quad_info.face_right,
		quad_info.level
	)
	
	if quad_surface.mesh:
		quad_surface.mesh.surface_set_material(0, default_material)
	
	add_child(quad_surface)
	active_quads[quad_info.id] = quad_surface

func _update_quad_surface(quad_info: Dictionary):
	var quad_surface = active_quads[quad_info.id]
   
	if quad_surface.global_position != quad_info.position or quad_surface.quad_size != quad_info.size:
		quad_surface.setup(
			quad_info.position,
			quad_info.size,
			quad_info.face_normal,
			quad_info.face_up,
			quad_info.face_right,
			quad_info.level
		)

func _remove_quad_surface(quad_id):
	if active_quads.has(quad_id):
		var quad_surface = active_quads[quad_id]
		quad_surface.queue_free()
		active_quads.erase(quad_id)

func _update_quad_surfaces(quad_data: Array):
	var current_ids = active_quads.keys()
	var new_ids = []
	
	for quad_info in quad_data:
		var quad_id = quad_info.id
		new_ids.append(quad_id)
		
		if not active_quads.has(quad_id):
			_create_quad_surface(quad_info)
		else:
			_update_quad_surface(quad_info)
	
	for current_id in current_ids:
		if not current_id in new_ids:
			_remove_quad_surface(current_id)

func set_compute_mode(mode: ComputeMode):
	if compute_mode == mode:
		return
		
	compute_mode = mode
	
	# Clean up compute resources if switching away from GPU
	if mode == ComputeMode.CPU and shared_compute_shader.is_valid():
		shared_rd.free_rid(shared_compute_shader)
		shared_compute_shader = RID()
		compute_shader_loaded = false
	elif mode == ComputeMode.GPU and not compute_shader_loaded:
		_initialize_compute_resources()
	
	# Recreate all surfaces with new mode
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
	
	# Clear existing quads
	for quad_id in active_quads.keys():
		_remove_quad_surface(quad_id)
	
	# Recreate with new mode
	for quad_info in quad_data:
		_create_quad_surface(quad_info)

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

func _exit_tree():
	# Clean up shared compute resources
	if shared_compute_shader.is_valid():
		shared_rd.free_rid(shared_compute_shader)
