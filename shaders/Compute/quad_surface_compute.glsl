#[compute]
#version 450

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

// Storage buffer for parameters
layout(set = 0, binding = 0, std430) restrict readonly buffer Params {
	vec4 quad_position;      // xyz = position, w = padding
	vec4 face_normal;        // xyz = normal, w = padding
	vec4 face_up;            // xyz = up, w = padding
	vec4 face_right;         // xyz = right, w = padding
	vec4 params1;            // x = quad_size, y = sphere_radius, z = quad_resolution, w = enable_noise
	vec4 noise_params1;      // x = amplitude, y = frequency, z = octaves, w = lacunarity
	vec4 noise_params2;      // x = gain, y = seed, z = padding, w = padding
} params;

// Storage buffers
layout(set = 0, binding = 1, std430) restrict writeonly buffer VertexBuffer {
	float vertices[];
} vertex_buffer;

layout(set = 0, binding = 2, std430) restrict writeonly buffer NormalBuffer {
	float normals[];
} normal_buffer;

layout(set = 0, binding = 3, std430) restrict writeonly buffer UVBuffer {
	float uvs[];
} uv_buffer;

// Simplex noise functions
vec3 mod289(vec3 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 mod289(vec4 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x) {
	return mod289(((x * 34.0) + 10.0) * x);
}

vec4 taylorInvSqrt(vec4 r) {
	return 1.79284291400159 - 0.85373472095314 * r;
}

float snoise(vec3 v) {
	const vec2 C = vec2(1.0/6.0, 1.0/3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
	
	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);
	
	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);
	
	vec3 x1 = x0 - i1 + C.xxx;
	vec3 x2 = x0 - i2 + C.yyy;
	vec3 x3 = x0 - D.yyy;
	
	i = mod289(i);
	vec4 p = permute(permute(permute(
		i.z + vec4(0.0, i1.z, i2.z, 1.0))
		+ i.y + vec4(0.0, i1.y, i2.y, 1.0))
		+ i.x + vec4(0.0, i1.x, i2.x, 1.0));
	
	float n_ = 0.142857142857;
	vec3 ns = n_ * D.wyz - D.xzx;
	
	vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
	
	vec4 x_ = floor(j * ns.z);
	vec4 y_ = floor(j - 7.0 * x_);
	
	vec4 x = x_ * ns.x + ns.yyyy;
	vec4 y = y_ * ns.x + ns.yyyy;
	vec4 h = 1.0 - abs(x) - abs(y);
	
	vec4 b0 = vec4(x.xy, y.xy);
	vec4 b1 = vec4(x.zw, y.zw);
	
	vec4 s0 = floor(b0) * 2.0 + 1.0;
	vec4 s1 = floor(b1) * 2.0 + 1.0;
	vec4 sh = -step(h, vec4(0.0));
	
	vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
	vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
	
	vec3 p0 = vec3(a0.xy, h.x);
	vec3 p1 = vec3(a0.zw, h.y);
	vec3 p2 = vec3(a1.xy, h.z);
	vec3 p3 = vec3(a1.zw, h.w);
	
	vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
	p0 *= norm.x;
	p1 *= norm.y;
	p2 *= norm.z;
	p3 *= norm.w;
	
	vec4 m = max(0.5 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
	m = m * m;
	return 105.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

float fbm(vec3 p, float frequency, float amplitude, int octaves, float lacunarity, float gain) {
	float value = 0.0;
	float amp = amplitude;
	float freq = frequency;
	
	for (int i = 0; i < octaves; i++) {
		value += amp * snoise(p * freq + vec3(params.noise_params2.y));
		freq *= lacunarity;
		amp *= gain;
	}
	
	return value;
}

void main() {
	uint x = gl_GlobalInvocationID.x;
	uint y = gl_GlobalInvocationID.y;
	
	// Get resolution from params
	uint resolution = uint(params.params1.z);
	if (x > resolution || y > resolution) {
		return;
	}
	
	float quad_size = params.params1.x;
	float sphere_radius = params.params1.y;
	bool enable_noise = params.params1.w > 0.5;
	
	vec3 face_normal = params.face_normal.xyz;
	vec3 face_up = params.face_up.xyz;
	vec3 face_right = params.face_right.xyz;
	vec3 quad_pos = params.quad_position.xyz;
	
	// Calculate local position on the quad
	float step = quad_size / float(resolution);
	float half_size = quad_size * 0.5;
	float local_x = (float(x) * step) - half_size;
	float local_y = (float(y) * step) - half_size;
	
	// Calculate position on the plane using corrected factor (sphere_radius / 2.0)
	vec3 plane_position = face_right * local_x + face_up * local_y;
	vec3 vertex_world_position = quad_pos + plane_position;
	vec3 spherical_position = normalize(vertex_world_position) * sphere_radius;
	
	if (enable_noise) {
		float noise_value = fbm(
			spherical_position,
			params.noise_params1.y,  // frequency
			params.noise_params1.x,  // amplitude
			int(params.noise_params1.z),  // octaves
			params.noise_params1.w,  // lacunarity
			params.noise_params2.x   // gain
		);
		vec3 sphere_normal = normalize(spherical_position);
		spherical_position += sphere_normal * noise_value;
	}
	
	// Convert to local position relative to quad
	vec3 local_position = spherical_position - quad_pos;
	
	// Calculate vertex index
	uint vertex_index = y * (resolution + 1) + x;
	uint vertex_offset = vertex_index * 3;
	
	// Write vertex position
	vertex_buffer.vertices[vertex_offset] = local_position.x;
	vertex_buffer.vertices[vertex_offset + 1] = local_position.y;
	vertex_buffer.vertices[vertex_offset + 2] = local_position.z;
	
	// Calculate normal correctly taking noise into account
	vec3 normal;
	
	if (enable_noise) {
		// Calculate neighboring positions for finite differences
		float epsilon = step; // Use step size for finite differences
		
		// Calculate neighboring positions in quad space
		vec3 plane_pos_right = face_right * (local_x + epsilon) + face_up * local_y + face_normal * (sphere_radius / 2.0);
		vec3 plane_pos_left = face_right * (local_x - epsilon) + face_up * local_y + face_normal * (sphere_radius / 2.0);
		vec3 plane_pos_up = face_right * local_x + face_up * (local_y + epsilon) + face_normal * (sphere_radius / 2.0);
		vec3 plane_pos_down = face_right * local_x + face_up * (local_y - epsilon) + face_normal * (sphere_radius / 2.0);
		
		// Calculate world positions for neighbors
		vec3 world_pos_right = quad_pos + plane_pos_right;
		vec3 world_pos_left = quad_pos + plane_pos_left;
		vec3 world_pos_up = quad_pos + plane_pos_up;
		vec3 world_pos_down = quad_pos + plane_pos_down;
		
		// Project to sphere and apply noise
		vec3 sphere_pos_right = normalize(world_pos_right) * sphere_radius;
		vec3 sphere_pos_left = normalize(world_pos_left) * sphere_radius;
		vec3 sphere_pos_up = normalize(world_pos_up) * sphere_radius;
		vec3 sphere_pos_down = normalize(world_pos_down) * sphere_radius;
		
		// Apply noise to neighboring positions
		float noise_right = fbm(sphere_pos_right, params.noise_params1.y, params.noise_params1.x, 
								int(params.noise_params1.z), params.noise_params1.w, params.noise_params2.x);
		float noise_left = fbm(sphere_pos_left, params.noise_params1.y, params.noise_params1.x,
							   int(params.noise_params1.z), params.noise_params1.w, params.noise_params2.x);
		float noise_up = fbm(sphere_pos_up, params.noise_params1.y, params.noise_params1.x,
							 int(params.noise_params1.z), params.noise_params1.w, params.noise_params2.x);
		float noise_down = fbm(sphere_pos_down, params.noise_params1.y, params.noise_params1.x,
							   int(params.noise_params1.z), params.noise_params1.w, params.noise_params2.x);
		
		// Apply displacement to neighboring positions
		sphere_pos_right += normalize(sphere_pos_right) * noise_right;
		sphere_pos_left += normalize(sphere_pos_left) * noise_left;
		sphere_pos_up += normalize(sphere_pos_up) * noise_up;
		sphere_pos_down += normalize(sphere_pos_down) * noise_down;
		
		// Calculate tangent vectors using finite differences
		vec3 tangent_x = normalize(sphere_pos_right - sphere_pos_left);
		vec3 tangent_y = normalize(sphere_pos_up - sphere_pos_down);
		
		// Calculate normal as cross product (matching CPU version order)
		normal = normalize(cross(tangent_y, tangent_x));
		
		// Ensure normal points outward from sphere center
		vec3 sphere_normal = normalize(spherical_position);
		if (dot(normal, sphere_normal) < 0.0) {
			normal = -normal;
		}
	} else {
		// When noise is disabled, use simple sphere normal
		normal = normalize(spherical_position);
	}
	
	// Write normal
	normal_buffer.normals[vertex_offset] = normal.x;
	normal_buffer.normals[vertex_offset + 1] = normal.y;
	normal_buffer.normals[vertex_offset + 2] = normal.z;
	
	// Calculate and write UV
	float u = float(x) / float(resolution);
	float v = float(y) / float(resolution);
	uint uv_offset = vertex_index * 2;
	uv_buffer.uvs[uv_offset] = u;
	uv_buffer.uvs[uv_offset + 1] = v;
}
