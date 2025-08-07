extends MeshInstance3D
class_name QuadSurfaceCompute

@export var quad_resolution: int = 32
@export var quad_size: float = 1000.0
@export var sphere_radius: float = 20000

var face_normal: Vector3
var face_up: Vector3  
var face_right: Vector3
var quad_level: int
var needs_update: bool = true

# Parámetros de ruido
@export_group("Noise Settings")
@export var enable_noise: bool = false
@export var noise_amplitude: float = 150.0
@export var noise_frequency: float = 0.001
@export var noise_octaves: int = 4
@export var noise_lacunarity: float = 2.0
@export var noise_gain: float = 0.5
@export var noise_seed: int = 12345

# Compute shader resources - now shared
var rd: RenderingDevice
var compute_shader: RID
var is_using_shared_resources: bool = false

# Per-instance buffers
var vertex_buffer: RID
var normal_buffer: RID
var uv_buffer: RID
var index_buffer: RID
var uniform_set: RID
var uniform_buffer: RID

func _init():
	# Don't create RenderingDevice here anymore
	pass

func set_shared_resources(shared_rd: RenderingDevice, shared_shader: RID):
	"""Set shared compute resources from the manager"""
	rd = shared_rd
	compute_shader = shared_shader
	is_using_shared_resources = true

func setup(_position: Vector3, size: float, normal: Vector3, up: Vector3, right: Vector3, radius: float, sub_divisions: int, level: int = 0):
	position = _position
	
	quad_size = size
	face_normal = normal.normalized()
	face_up = up.normalized()
	face_right = right.normalized()
	quad_level = level
	needs_update = true
	sphere_radius = radius
	quad_resolution = sub_divisions
	# Only setup shader if not using shared resources
	cast_shadow = SHADOW_CASTING_SETTING_OFF

	if not is_using_shared_resources:
		_setup_own_compute_resources()
	
	generate_mesh()
	

func _setup_own_compute_resources():
	"""Fallback method if shared resources are not provided"""
	rd = RenderingServer.create_local_rendering_device()
	_setup_compute_shader()

func _setup_compute_shader():
	# Load shader file
	const COMPUTE_SHADER_PATH = "res://shaders/Compute/quad_surface_compute.glsl"
	var shader_file = load(COMPUTE_SHADER_PATH) as RDShaderFile
	if not shader_file:
		# Try alternative loading method
		var file = FileAccess.open(COMPUTE_SHADER_PATH, FileAccess.READ)
		if not file:
			push_error("Could not load compute shader file")
			return
			
		var shader_code = file.get_as_text()
		file.close()
		
		# Create shader from source
		var shader_source := RDShaderSource.new()
		shader_source.source_compute = shader_code
		shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		
		var shader_spirv = rd.shader_compile_spirv_from_source(shader_source)
		if shader_spirv.compile_error_compute != "":
			push_error("Compute shader compilation error: " + shader_spirv.compile_error_compute)
			return
			
		compute_shader = rd.shader_create_from_spirv(shader_spirv)
	else:
		var shader_spirv = shader_file.get_spirv()
		compute_shader = rd.shader_create_from_spirv(shader_spirv)

func _create_buffers():
	var vertex_count = (quad_resolution + 1) * (quad_resolution + 1)
	var index_count = quad_resolution * quad_resolution * 6
	
	# Create vertex buffer (vec3 per vertex)
	var vertex_data = PackedFloat32Array()
	vertex_data.resize(vertex_count * 3)
	var vertex_bytes = vertex_data.to_byte_array()
	vertex_buffer = rd.storage_buffer_create(vertex_bytes.size(), vertex_bytes)
	
	# Create normal buffer (vec3 per vertex)
	var normal_data = PackedFloat32Array()
	normal_data.resize(vertex_count * 3)
	var normal_bytes = normal_data.to_byte_array()
	normal_buffer = rd.storage_buffer_create(normal_bytes.size(), normal_bytes)
	
	# Create UV buffer (vec2 per vertex)
	var uv_data = PackedFloat32Array()
	uv_data.resize(vertex_count * 2)
	var uv_bytes = uv_data.to_byte_array()
	uv_buffer = rd.storage_buffer_create(uv_bytes.size(), uv_bytes)
	
	# Create index buffer
	var index_data = PackedInt32Array()
	index_data.resize(index_count)
	_fill_indices(index_data)
	var index_bytes = index_data.to_byte_array()
	index_buffer = rd.storage_buffer_create(index_bytes.size(), index_bytes)

func _fill_indices(indices: PackedInt32Array):
	var index = 0
	for y in range(quad_resolution):
		for x in range(quad_resolution):
			var top_left = y * (quad_resolution + 1) + x
			var top_right = top_left + 1
			var bottom_left = (y + 1) * (quad_resolution + 1) + x
			var bottom_right = bottom_left + 1
			
			indices[index] = top_left
			indices[index + 1] = bottom_left
			indices[index + 2] = top_right
			
			indices[index + 3] = top_right
			indices[index + 4] = bottom_left
			indices[index + 5] = bottom_right
			
			index += 6

func _create_uniform_buffer():
	# Uniform structure (must match shader)
	var uniform_data = PackedFloat32Array([
		# quad_position (vec3 + padding)
		position.x, position.y, position.z, 0.0,
		# face_normal (vec3 + padding)
		face_normal.x, face_normal.y, face_normal.z, 0.0,
		# face_up (vec3 + padding)
		face_up.x, face_up.y, face_up.z, 0.0,
		# face_right (vec3 + padding)
		face_right.x, face_right.y, face_right.z, 0.0,
		# params (quad_size, sphere_radius, quad_resolution, enable_noise)
		quad_size, sphere_radius, float(quad_resolution), float(1 if enable_noise else 0),
		# noise params 1
		noise_amplitude, noise_frequency, float(noise_octaves), noise_lacunarity,
		# noise params 2
		noise_gain, float(noise_seed), 0.0, 0.0
	])
	
	var uniform_bytes = uniform_data.to_byte_array()
	uniform_buffer = rd.storage_buffer_create(uniform_bytes.size(), uniform_bytes)

func _dispatch_compute():
	# Create uniform set with index buffer included
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(uniform_buffer)
	
	var vertex_uniform := RDUniform.new()
	vertex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	vertex_uniform.binding = 1
	vertex_uniform.add_id(vertex_buffer)
	
	var normal_uniform := RDUniform.new()
	normal_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	normal_uniform.binding = 2
	normal_uniform.add_id(normal_buffer)
	
	var uv_uniform := RDUniform.new()
	uv_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uv_uniform.binding = 3
	uv_uniform.add_id(uv_buffer)
	
	var index_uniform := RDUniform.new()
	index_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	index_uniform.binding = 4
	index_uniform.add_id(index_buffer)
	
	uniform_set = rd.uniform_set_create([uniform, vertex_uniform, normal_uniform, uv_uniform, index_uniform], compute_shader, 0)
	
	# Create compute pipeline
	var pipeline = rd.compute_pipeline_create(compute_shader)
	
	# Push constant for pass type
	var push_constant := PackedInt32Array([0]) # Start with pass 0
	
	# PASS 1: Calculate vertices and UVs
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	push_constant[0] = 0
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 4)
	
	# Dispatch for vertices (grid of vertices)
	var groups_x = (quad_resolution) / 16
	var groups_y = (quad_resolution) / 16
	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	
	# Add memory barrier between passes
	
	# PASS 2: Calculate normals from triangles
	compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	push_constant[0] = 1
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 4)
	
	# Dispatch for triangles - treat as 1D
	var total_triangles = quad_resolution * quad_resolution * 2
	var triangle_groups = (total_triangles + 63) / 64  # 64 threads per group (8x8)
	rd.compute_list_dispatch(compute_list, triangle_groups, 1, 1)
	
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	
	# Add memory barrier between passes
	rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)
	
	# PASS 3: Normalize normals
	compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	push_constant[0] = 2
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 4)
	
	# Dispatch for vertices - treat as 1D
	var total_vertices = (quad_resolution + 1) * (quad_resolution + 1)
	var vertex_groups = (total_vertices + 63) / 64  # 64 threads per group (8x8)
	rd.compute_list_dispatch(compute_list, vertex_groups, 1, 1)
	
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func _read_buffers_and_create_mesh():
	var vertex_count = (quad_resolution + 1) * (quad_resolution + 1)
	
	# Read vertex data
	var vertex_bytes = rd.buffer_get_data(vertex_buffer)
	var vertices = vertex_bytes.to_float32_array()
	
	# Read normal data
	var normal_bytes = rd.buffer_get_data(normal_buffer)
	var normals = normal_bytes.to_float32_array()
	
	# Read UV data
	var uv_bytes = rd.buffer_get_data(uv_buffer)
	var uvs = uv_bytes.to_float32_array()
	
	# Read index data
	var index_bytes = rd.buffer_get_data(index_buffer)
	var indices = index_bytes.to_int32_array()
	
	# Convert to PackedVector3Array and PackedVector2Array
	var vertex_array = PackedVector3Array()
	var normal_array = PackedVector3Array()
	var uv_array = PackedVector2Array()
	
	for i in range(vertex_count):
		var base_idx = i * 3
		vertex_array.append(Vector3(vertices[base_idx], vertices[base_idx + 1], vertices[base_idx + 2]))
		normal_array.append(Vector3(normals[base_idx], normals[base_idx + 1], normals[base_idx + 2]))
		
		var uv_idx = i * 2
		uv_array.append(Vector2(uvs[uv_idx], uvs[uv_idx + 1]))
	
	# Create mesh
	var array_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	arrays[Mesh.ARRAY_VERTEX] = vertex_array
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_TEX_UV] = uv_array
	arrays[Mesh.ARRAY_NORMAL] = normal_array
	
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = array_mesh

func generate_mesh():
	if not needs_update or not rd or not compute_shader.is_valid():
		return
	
	_create_buffers()
	_create_uniform_buffer()
	_dispatch_compute()
	_read_buffers_and_create_mesh()
	_cleanup_buffers()
	
	needs_update = false

func _cleanup_buffers():
	# Only clean up per-instance buffers
	if vertex_buffer.is_valid():
		rd.free_rid(vertex_buffer)
	if normal_buffer.is_valid():
		rd.free_rid(normal_buffer)
	if uv_buffer.is_valid():
		rd.free_rid(uv_buffer)
	if index_buffer.is_valid():
		rd.free_rid(index_buffer)
	if uniform_buffer.is_valid():
		rd.free_rid(uniform_buffer)
	
	# Don't clean up shared shader or RenderingDevice
	
func _exit_tree():
	_cleanup_buffers()
	
	# Only free shader if we own it (not shared)
	if not is_using_shared_resources and compute_shader.is_valid():
		rd.free_rid(compute_shader)
