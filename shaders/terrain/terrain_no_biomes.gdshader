shader_type spatial;

#include "res://shaders/terrain/terrain_utils.gdshaderinc"

uniform int u_transition_mask;
uniform float radius = 5000.0;
uniform vec3 center;

#define MAX_TEXTURES 8
#define MAX_BIOMES 8 // máximo seguro (ajustable si necesitas más)
#define MAX_HEIGHTS 24
#define MAX_LATITUDE_RANGES 9
uniform sampler2D textures[MAX_TEXTURES]: source_color;
uniform sampler2D normal_textures[MAX_TEXTURES];
uniform sampler2D roughness_textures[MAX_TEXTURES];

uniform float max_heights[MAX_HEIGHTS]; // 3 alturas por bioma
uniform int biome_count = 6;
uniform int textures_per_biome = 3;
uniform float biome_latitude_ranges[MAX_LATITUDE_RANGES]; // n+1 rangos para n biomas
uniform int biome_texture_indices[MAX_HEIGHTS];   // índices por bioma

uniform sampler2D slope_texture;
uniform sampler2D slope_normal_texture;
uniform sampler2D slope_roughness_texture;
uniform float slope_threshold = 0.7;
uniform float slope_smoothness = 0.2;
uniform float transition_smoothness = 1.5;

uniform float biome_transition_smoothness = 1.0; // nueva uniform para suavizar transiciones
uniform float noise_strength = 1.0;
uniform float noise_scale = 0.1;
uniform float texture_scale = 0.5;
uniform float normal_strength = 0.7;

varying vec3 world_pos;
varying float height;
varying vec3 world_normal;

void vertex() {
	VERTEX = get_transvoxel_position(VERTEX, CUSTOM0, u_transition_mask);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	height = length(world_pos - center) - radius;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float noise_value = noise(world_pos * noise_scale) * noise_strength;
	float adjusted_height = height + noise_value;

	float slope = 1.0 - dot(world_normal, normalize(world_pos - center));
	float slope_factor = smoothstep(slope_threshold - slope_smoothness, slope_threshold + slope_smoothness, slope);

	vec3 slope_color = triplanar_sample(slope_texture, world_pos, world_normal, texture_scale);
	vec3 slope_normal = triplanar_normal_sample(slope_normal_texture, world_pos, world_normal, texture_scale);
	float slope_roughness = triplanar_roughness_sample(slope_roughness_texture, world_pos, world_normal, texture_scale);

	// Calcular latitud
	vec3 dir = (center - world_pos);
	float rho = length(dir);
	float phi = acos(world_pos.y / rho);
	float latitude = degrees((PI / 2.0) - phi);

	// Calcular pesos de biomas suavizados
	float biome_weights[MAX_BIOMES];
	for (int i = 0; i < MAX_BIOMES; i++) biome_weights[i] = 0.0;

	for (int i = 0; i < biome_count; i++) {
		float lower = biome_latitude_ranges[i];
		float upper = biome_latitude_ranges[i + 1];
		float center_lat = (lower + upper) * 0.5;
		float range = upper - lower;

		float weight = 1.0 - abs(latitude - center_lat) / (range * biome_transition_smoothness);
		weight = clamp(weight, 0.0, 1.0);
		biome_weights[i] = smoothstep(0.0, 1.0, weight);
	}

	vec3 final_color = vec3(0.0);
	vec3 final_normal = vec3(0.0);
	float final_roughness = 0.0;
	float total_factor = 0.0;

	for (int b = 0; b < biome_count; b++) {
		float biome_weight = biome_weights[b];
		if (biome_weight < 0.01) continue;

		int offset = b * textures_per_biome;

		for (int j = 0; j < textures_per_biome; j++) {
			int tex_index = biome_texture_indices[offset + j];

			vec3 tex_color = triplanar_sample(textures[tex_index], world_pos, world_normal, texture_scale);
			vec3 tex_normal = triplanar_normal_sample(normal_textures[tex_index], world_pos, world_normal, texture_scale);
			float tex_roughness = triplanar_roughness_sample(roughness_textures[tex_index], world_pos, world_normal, texture_scale);

			float factor = 0.0;
			if (j == 0) {
				factor = smoothstep(-transition_smoothness, transition_smoothness, max_heights[offset + j] - adjusted_height);
			} else {
				float lower = max_heights[offset + j - 1];
				float upper = max_heights[offset + j];
				float step1 = smoothstep(-transition_smoothness, transition_smoothness, upper - adjusted_height);
				float step2 = smoothstep(-transition_smoothness, transition_smoothness, lower - adjusted_height);
				factor = step1 * (1.0 - step2);
			}

			factor *= (1.0 - slope_factor);
			factor *= biome_weight;

			final_color += tex_color * factor;
			final_normal += tex_normal * factor;
			final_roughness += tex_roughness * factor;
			total_factor += factor;
		}
	}

	// Aplicar textura de pendiente
	final_color += slope_color * slope_factor;
	final_normal += slope_normal * slope_factor;
	final_roughness += slope_roughness * slope_factor;
	total_factor += slope_factor;

	if (total_factor > 0.0) {
		final_color /= total_factor;
		final_normal = normalize(final_normal);
		final_roughness /= total_factor;
	} else {
		final_color = vec3(0.5);
		final_normal = vec3(0.0, 0.0, 1.0);
		final_roughness = 0.5;
	}

	ALBEDO = final_color;
	//NORMAL_MAP = final_normal * normal_strength;
	ROUGHNESS = final_roughness;
	//NORMAL_MAP_DEPTH = normal_strength;
}
