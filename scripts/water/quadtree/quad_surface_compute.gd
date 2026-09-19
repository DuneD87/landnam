extends MeshInstance3D
class_name QuadSurfaceCompute

## Genera la malla de un parche del quadtree de agua en la GPU (compute shader): calcula vértices,
## normales y UVs proyectados sobre la esfera, con ruido opcional. Usa recursos compute compartidos.

@export var quad_resolution: int = 32
@export var quad_size: float = 1000.0
@export var sphere_radius: float = 20000

var face_normal: Vector3
var face_up: Vector3  
var face_right: Vector3
var quad_level: int
var needs_update: bool = true

## La superficie base del océano es una proyección esférica; las olas van en el material.
## Resolverla directamente evita submit + sync + tres readbacks por cada parche nuevo.
## Se conserva la ruta compute para comparar resultados y para el modo con ruido.
@export var use_direct_projection: bool = true

@export_group("Noise Settings")
@export var enable_noise: bool = false
@export var noise_amplitude: float = 150.0
@export var noise_frequency: float = 0.001
@export var noise_octaves: int = 4
@export var noise_lacunarity: float = 2.0
@export var noise_gain: float = 0.5
@export var noise_seed: int = 12345

var rd: RenderingDevice
var compute_shader: RID
## Pipeline prestado por el manager. Crearlo por parche costaba una construcción de pipeline de
## Vulkan (y su destrucción) en cada malla generada.
var compute_pipeline: RID
var is_using_shared_resources: bool = false

var vertex_buffer: RID
var normal_buffer: RID
var uv_buffer: RID
var uniform_set: RID
var uniform_buffer: RID
var cached_indices: PackedInt32Array

func _init():
	pass

func set_shared_resources(shared_rd: RenderingDevice, shared_shader: RID, shared_pipeline: RID = RID()):
	"""Set shared compute resources from the manager"""
	rd = shared_rd
	compute_shader = shared_shader
	compute_pipeline = shared_pipeline
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
	cast_shadow = SHADOW_CASTING_SETTING_OFF

	if not is_using_shared_resources and (not use_direct_projection or enable_noise):
		_setup_own_compute_resources()
	
	generate_mesh()
	

func _setup_own_compute_resources():
	"""Fallback method if shared resources are not provided"""
	rd = RenderingServer.create_local_rendering_device()
	_setup_compute_shader()

func _setup_compute_shader():
	const COMPUTE_SHADER_PATH = "res://shaders/Compute/quad_surface_compute.glsl"
	var shader_file = load(COMPUTE_SHADER_PATH) as RDShaderFile
	if not shader_file:
		var file = FileAccess.open(COMPUTE_SHADER_PATH, FileAccess.READ)
		if not file:
			push_error("Could not load compute shader file")
			return
			
		var shader_code = file.get_as_text()
		file.close()
		
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
	
	var vertex_data = PackedFloat32Array()
	vertex_data.resize(vertex_count * 3)
	var vertex_bytes = vertex_data.to_byte_array()
	vertex_buffer = rd.storage_buffer_create(vertex_bytes.size(), vertex_bytes)
	
	var normal_data = PackedFloat32Array()
	normal_data.resize(vertex_count * 3)
	var normal_bytes = normal_data.to_byte_array()
	normal_buffer = rd.storage_buffer_create(normal_bytes.size(), normal_bytes)
	
	var uv_data = PackedFloat32Array()
	uv_data.resize(vertex_count * 2)
	var uv_bytes = uv_data.to_byte_array()
	uv_buffer = rd.storage_buffer_create(uv_bytes.size(), uv_bytes)

	cached_indices = PackedInt32Array()
	cached_indices.resize(index_count)
	_fill_indices(cached_indices)

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

	uniform_set = rd.uniform_set_create([uniform, vertex_uniform, normal_uniform, uv_uniform], compute_shader, 0)

	# El del manager si lo hay; si no (sin recursos compartidos), uno propio de usar y tirar.
	var pipeline := compute_pipeline
	var owns_pipeline := false
	if not pipeline.is_valid():
		pipeline = rd.compute_pipeline_create(compute_shader)
		owns_pipeline = true

	# El shader cubre (res+1)² vértices con workgroups de 32x32 en un único pase.
	var groups = (quad_resolution + 1 + 31) / 32

	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, groups, groups, 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

	if owns_pipeline:
		rd.free_rid(pipeline)

func _read_buffers_and_create_mesh():
	var vertex_count = (quad_resolution + 1) * (quad_resolution + 1)
	
	var vertex_bytes = rd.buffer_get_data(vertex_buffer)
	var vertices = vertex_bytes.to_float32_array()
	
	var normal_bytes = rd.buffer_get_data(normal_buffer)
	var normals = normal_bytes.to_float32_array()
	
	var uv_bytes = rd.buffer_get_data(uv_buffer)
	var uvs = uv_bytes.to_float32_array()

	var vertex_array = PackedVector3Array()
	var normal_array = PackedVector3Array()
	var uv_array = PackedVector2Array()
	
	for i in range(vertex_count):
		var base_idx = i * 3
		vertex_array.append(Vector3(vertices[base_idx], vertices[base_idx + 1], vertices[base_idx + 2]))
		normal_array.append(Vector3(normals[base_idx], normals[base_idx + 1], normals[base_idx + 2]))
		
		var uv_idx = i * 2
		uv_array.append(Vector2(uvs[uv_idx], uvs[uv_idx + 1]))
	
	var array_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	arrays[Mesh.ARRAY_VERTEX] = vertex_array
	arrays[Mesh.ARRAY_INDEX] = cached_indices
	arrays[Mesh.ARRAY_TEX_UV] = uv_array
	arrays[Mesh.ARRAY_NORMAL] = normal_array
	
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = array_mesh

func generate_mesh():
	if not needs_update:
		return
	if use_direct_projection and not enable_noise:
		_generate_projected_mesh()
		needs_update = false
		return
	if not rd or not compute_shader.is_valid():
		return
	
	_create_buffers()
	_create_uniform_buffer()
	_dispatch_compute()
	_read_buffers_and_create_mesh()
	_cleanup_buffers()
	
	needs_update = false


## Mismas posiciones, normales radiales, UV e índices que quad_surface_compute.glsl.
## No usa QuadSurface: esa clase también tiene ruido y animación CPU propios.
func _generate_projected_mesh() -> void:
	var side := quad_resolution + 1
	var vertex_array := PackedVector3Array()
	var normal_array := PackedVector3Array()
	var uv_array := PackedVector2Array()
	vertex_array.resize(side * side)
	normal_array.resize(side * side)
	uv_array.resize(side * side)
	var step := quad_size / float(quad_resolution)
	var half_size := quad_size * 0.5
	for y in side:
		for x in side:
			var index := y * side + x
			var plane := face_right * (float(x) * step - half_size) + face_up * (float(y) * step - half_size)
			var spherical := (position + plane).normalized() * sphere_radius
			vertex_array[index] = spherical - position
			normal_array[index] = spherical.normalized()
			uv_array[index] = Vector2(float(x), float(y)) / float(quad_resolution)
	if cached_indices.size() != quad_resolution * quad_resolution * 6:
		cached_indices.resize(quad_resolution * quad_resolution * 6)
		_fill_indices(cached_indices)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertex_array
	arrays[Mesh.ARRAY_NORMAL] = normal_array
	arrays[Mesh.ARRAY_TEX_UV] = uv_array
	arrays[Mesh.ARRAY_INDEX] = cached_indices
	var projected := ArrayMesh.new()
	projected.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = projected

## Libera el uniform set y los buffers del compute; los RID quedan a cero para que sea reentrante.
func _cleanup_buffers():
	if not rd:
		return
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
		uniform_set = RID()
	if vertex_buffer.is_valid():
		rd.free_rid(vertex_buffer)
		vertex_buffer = RID()
	if normal_buffer.is_valid():
		rd.free_rid(normal_buffer)
		normal_buffer = RID()
	if uv_buffer.is_valid():
		rd.free_rid(uv_buffer)
		uv_buffer = RID()
	if uniform_buffer.is_valid():
		rd.free_rid(uniform_buffer)
		uniform_buffer = RID()


func _exit_tree():
	_cleanup_buffers()
	
	if not is_using_shared_resources and compute_shader.is_valid():
		rd.free_rid(compute_shader)
