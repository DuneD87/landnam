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

# Parámetros de ruido
@export_group("Noise Settings")
@export var enable_noise: bool = true
@export var noise_amplitude: float = 150.0
@export var noise_frequency: float = 0.001
@export var noise_octaves: int = 4
@export var noise_lacunarity: float = 2.0
@export var noise_gain: float = 0.5
@export var noise_seed: int = 12345

var noise: FastNoiseLite

func setup(_position: Vector3, size: float, normal: Vector3, up: Vector3, right: Vector3, level: int = 0):
	position = _position
	print(size, " ", position)
	quad_size = size
	face_normal = normal.normalized()
	face_up = up.normalized()
	face_right = right.normalized()
	quad_level = level
	needs_update = true
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
	
func get_noise_value(world_pos: Vector3) -> float:
	return noise.get_noise_3d(world_pos.x, world_pos.y, world_pos.z)
	
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

func _generate_normals():
	_calculate_normals()
		
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
			
			if enable_noise:
				var noise_value = get_noise_value(spherical_position)
				var displacement = noise_value * noise_amplitude
				var sphere_normal = spherical_position.normalized()
				spherical_position += sphere_normal * displacement
			
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
