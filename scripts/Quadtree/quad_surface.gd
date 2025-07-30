extends MeshInstance3D
class_name QuadSurface

@export var quad_resolution: int = 32
@export var quad_size: float = 100.0
@export var sphere_radius: float = 20000

var face_normal: Vector3
var face_up: Vector3  
var face_right: Vector3
var quad_level: int
var vertices: PackedVector3Array
var indices: PackedInt32Array
var uvs: PackedVector2Array
var normals: PackedVector3Array
var needs_update: bool = true

# Parámetros de ruido base
@export_group("Noise Settings")
@export var enable_noise: bool = true
@export var noise_amplitude: float = 150.0
@export var noise_frequency: float = 0.001
@export var noise_octaves: int = 4
@export var noise_lacunarity: float = 2.0
@export var noise_gain: float = 0.5
@export var noise_seed: int = 12345

# Parámetros de océano
@export_group("Ocean Settings")
@export var enable_ocean_animation: bool = true
@export var animation_distance_threshold: float = 5000.0  # Solo animar quads dentro de esta distancia
@export var wave_speed: float = 2.0
@export var wave_amplitude: float = 50.0
@export var wave_frequency: float = 0.003
@export var wave_direction: Vector2 = Vector2(1.0, 0.3)  # Dirección principal de las olas
@export var secondary_wave_amplitude: float = 25.0
@export var secondary_wave_frequency: float = 0.007
@export var secondary_wave_direction: Vector2 = Vector2(-0.5, 1.0)
@export var foam_wave_amplitude: float = 10.0
@export var foam_wave_frequency: float = 0.02
@export var foam_wave_speed: float = 4.0

var noise: FastNoiseLite
var camera_position: Vector3 = Vector3.ZERO
var current_time: float = 0.0
var should_animate: bool = false

func setup(_position: Vector3, size: float, normal: Vector3, up: Vector3, right: Vector3, level: int = 0):
	position = _position
	quad_size = size
	face_normal = normal.normalized()
	face_up = up.normalized()
	face_right = right.normalized()
	quad_level = level
	needs_update = true
	
	# Configurar ruido
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	noise.frequency = noise_frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = noise_octaves
	noise.fractal_lacunarity = noise_lacunarity
	noise.fractal_gain = noise_gain
	
	generate_mesh()
	
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	gi_mode = GeometryInstance3D.GI_MODE_STATIC
	
	if level > 6:
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ready():
	# Buscar la cámara para calcular distancias
	var viewport = get_viewport()
	if viewport:
		var camera = viewport.get_camera_3d()
		if camera:
			camera_position = camera.global_position

func _process(delta):
	if not enable_ocean_animation:
		return
		
	current_time += delta
	
	# Actualizar posición de la cámara
	var viewport = get_viewport()
	if viewport:
		var camera = viewport.get_camera_3d()
		if camera:
			camera_position = camera.global_position
	
	# Verificar si debemos animar este quad basado en la distancia
	var distance_to_camera = position.distance_to(camera_position)
	var should_animate_now = distance_to_camera <= animation_distance_threshold

	# Solo regenerar si el estado de animación cambió o si debemos animar
	if should_animate_now != should_animate or should_animate_now:
		should_animate = should_animate_now
		if should_animate:
			generate_mesh()

func get_noise_value(world_pos: Vector3) -> float:
	return noise.get_noise_3d(world_pos.x, world_pos.y, world_pos.z)

func get_ocean_wave_height(world_pos: Vector3, time: float) -> float:
	if not enable_ocean_animation or not should_animate:
		return 0.0
	
	var height = 0.0
	
	# Normalizar direcciones de olas
	var wave_dir_norm = wave_direction.normalized()
	var secondary_dir_norm = secondary_wave_direction.normalized()
	
	# Ola principal
	var wave_pos = Vector2(world_pos.x, world_pos.z)
	var wave_offset = wave_pos.dot(wave_dir_norm) * wave_frequency + time * wave_speed
	height += sin(wave_offset) * wave_amplitude
	
	# Ola secundaria (diferente dirección y frecuencia)
	var secondary_offset = wave_pos.dot(secondary_dir_norm) * secondary_wave_frequency + time * wave_speed * 0.7
	height += sin(secondary_offset) * secondary_wave_amplitude
	
	# Olas de espuma (alta frecuencia, baja amplitud)
	var foam_offset = wave_pos.dot(wave_dir_norm) * foam_wave_frequency + time * foam_wave_speed
	height += sin(foam_offset * 3.0) * foam_wave_amplitude * 0.3
	height += sin(foam_offset * 5.0 + 1.5) * foam_wave_amplitude * 0.2
	
	# Olas cruzadas para mayor realismo
	var cross_wave = Vector2(-wave_dir_norm.y, wave_dir_norm.x)
	var cross_offset = wave_pos.dot(cross_wave) * wave_frequency * 0.5 + time * wave_speed * 0.8
	height += sin(cross_offset) * wave_amplitude * 0.3
	
	return height

func _generate_indices():
	var triangle_count = quad_resolution * quad_resolution * 2
	indices.resize(triangle_count * 3)
	
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

func _create_array_mesh():
	var array_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
   
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
   
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = array_mesh

func _calculate_normals():
	normals.resize(vertices.size())
	for i in range(normals.size()):
		normals[i] = Vector3.ZERO
	
	for i in range(0, indices.size(), 3):
		var i1 = indices[i]
		var i2 = indices[i + 1]
		var i3 = indices[i + 2]
		
		var v1 = vertices[i1]
		var v2 = vertices[i2]
		var v3 = vertices[i3]
		
		var edge1 = v2 - v1
		var edge2 = v3 - v1
		var triangle_normal = edge2.cross(edge1).normalized()
		
		if triangle_normal.dot(face_normal) < 0:
			triangle_normal = -triangle_normal
		
		normals[i1] += triangle_normal
		normals[i2] += triangle_normal
		normals[i3] += triangle_normal
	
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
		if normals[i].dot(face_normal) < 0:
			normals[i] = -normals[i]

func _calculate_normal_with_neighbors(world_pos: Vector3, epsilon: float) -> Vector3:
	# Calcular posiciones vecinas para diferencias finitas
	var pos_right = world_pos + Vector3(epsilon, 0, 0)
	var pos_left = world_pos + Vector3(-epsilon, 0, 0)
	var pos_forward = world_pos + Vector3(0, 0, epsilon)
	var pos_back = world_pos + Vector3(0, 0, -epsilon)
	
	# Obtener alturas incluyendo ruido base y olas
	var height_center = 0.0
	var height_right = 0.0
	var height_left = 0.0
	var height_forward = 0.0
	var height_back = 0.0
	
	if enable_noise:
		height_center = get_noise_value(world_pos) * noise_amplitude
		height_right = get_noise_value(pos_right) * noise_amplitude
		height_left = get_noise_value(pos_left) * noise_amplitude
		height_forward = get_noise_value(pos_forward) * noise_amplitude
		height_back = get_noise_value(pos_back) * noise_amplitude
	
	# Añadir componente oceánico
	height_center += get_ocean_wave_height(world_pos, current_time)
	height_right += get_ocean_wave_height(pos_right, current_time)
	height_left += get_ocean_wave_height(pos_left, current_time)
	height_forward += get_ocean_wave_height(pos_forward, current_time)
	height_back += get_ocean_wave_height(pos_back, current_time)
	
	# Calcular vectores tangentes usando diferencias finitas
	var tangent_x = Vector3(2.0 * epsilon, height_right - height_left, 0.0).normalized()
	var tangent_z = Vector3(0.0, height_forward - height_back, 2.0 * epsilon).normalized()
	
	# Normal como producto cruzado
	var normal = tangent_z.cross(tangent_x).normalized()
	
	return normal

func _generate_normals():
	normals.resize(vertices.size())
	var step = quad_size / float(quad_resolution)
	var epsilon = step * 0.5  # Usar la mitad del step para diferencias finitas
	
	for y in range(quad_resolution + 1):
		for x in range(quad_resolution + 1):
			var local_x = (x * step) - (quad_size * 0.5)
			var local_y = (y * step) - (quad_size * 0.5)
			
			var plane_position = face_right * local_x + face_up * local_y + face_normal * (sphere_radius / 2)
			var vertex_world_position = position + plane_position
			var spherical_position = project_to_sphere(vertex_world_position, Vector3.ZERO)
			
			var vertex_index = y * (quad_resolution + 1) + x
			
			if enable_ocean_animation and should_animate:
				# Calcular normal considerando las olas
				normals[vertex_index] = _calculate_normal_with_neighbors(spherical_position, epsilon)
			else:
				# Normal simple de esfera
				normals[vertex_index] = spherical_position.normalized()
			
			# Asegurar que la normal apunta hacia afuera
			if normals[vertex_index].dot(face_normal) < 0:
				normals[vertex_index] = -normals[vertex_index]
		
func _generate_uvs():
	uvs.resize(vertices.size())
   
	for y in range(quad_resolution + 1):
		for x in range(quad_resolution + 1):
			var u = float(x) / float(quad_resolution)
			var v = float(y) / float(quad_resolution)
   		
			var vertex_index = y * (quad_resolution + 1) + x
			uvs[vertex_index] = Vector2(u, v)
			
func project_to_sphere(point: Vector3, center: Vector3) -> Vector3:
	var direction = (point - center).normalized()
	return center + direction * sphere_radius

func _generate_vertices():
	var vertex_count = (quad_resolution + 1) * (quad_resolution + 1)
	vertices.resize(vertex_count)
	
	var step = quad_size / float(quad_resolution)
	var half_size = quad_size * 0.5
	
	for y in range(quad_resolution + 1):
		for x in range(quad_resolution + 1):
			var local_x = (x * step) - half_size
			var local_y = (y * step) - half_size
			
			var plane_position = face_right * local_x + face_up * local_y + face_normal * (sphere_radius / 2)
			var vertex_world_position = position + plane_position
			var spherical_position = project_to_sphere(vertex_world_position, Vector3.ZERO)
			
			# Aplicar ruido base
			if enable_noise:
				var noise_value = get_noise_value(spherical_position)
				var displacement = noise_value * noise_amplitude
				var sphere_normal = spherical_position.normalized()
				spherical_position += sphere_normal * displacement
			
			# Aplicar olas oceánicas
			if enable_ocean_animation and should_animate:
				var wave_height = get_ocean_wave_height(spherical_position, current_time)
				var sphere_normal = spherical_position.normalized()
				spherical_position += sphere_normal * wave_height
			
			var local_position = spherical_position - position
			
			var vertex_index = y * (quad_resolution + 1) + x
			vertices[vertex_index] = local_position

func generate_mesh():
	if not needs_update:
		return
	
	_generate_vertices()
	_generate_indices()
	_generate_uvs()
	_generate_normals()
	_create_array_mesh()
	
	needs_update = false

# Función para obtener estadísticas de animación
func get_animation_info() -> Dictionary:
	return {
		"is_animating": should_animate,
		"distance_to_camera": global_position.distance_to(camera_position),
		"animation_threshold": animation_distance_threshold,
		"current_time": current_time,
		"level": quad_level
	}
