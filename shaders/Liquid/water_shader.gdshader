shader_type spatial;
render_mode blend_mix, shadows_disabled, depth_prepass_alpha;

uniform sampler2D DEPTH_TEXTURE: hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;
uniform vec3 albedo : source_color = vec3(0.0, 0.0, 1.0);
uniform vec3 albedo2 : source_color = vec3(0.0, 0.0, 1.0);
uniform float metallic : hint_range(0.0, 1.0, 0.1) = 0;
uniform float roughness : hint_range(0.0, 1.0, 0.1) = 0.02;

uniform vec3 horizon_fog_color : source_color = vec3(0.75, 0.82, 0.92);
uniform float horizon_fog_start : hint_range(10.0, 1000.0) = 150.0;
uniform float horizon_fog_end : hint_range(50.0, 5000.0) = 2000.0;

uniform sampler2D texture_normal;
uniform sampler2D texture_normal2;
uniform sampler2D wave : repeat_enable, filter_linear_mipmap;

uniform vec2 wave_direction = vec2(2.0, 0.0);
uniform vec2 wave_direction2 = vec2(0.0, 1.0);
uniform float time_scale : hint_range(0.0, 0.2, 0.001) = 0.05;
uniform float noise_scale = 5.0;
uniform float height_scale = 0.5;

// Parámetros para romper el tiling de las normales
uniform float normal_scale1 : hint_range(0.1, 500.0) = 1.0;
uniform float normal_scale2 : hint_range(0.1, 500.0) = 2.3;
uniform float normal_scale3 : hint_range(0.1, 500.0) = 7.8;
uniform float normal_intensity : hint_range(0.0, 200.0) = 1.0;

uniform float wave_speed = 1.0;
uniform float wave_amplitude = 1.0;
uniform float wave_frequency = 1.0;

uniform vec4 color_deep : source_color;
uniform vec4 color_shallow : source_color;
uniform float beers_law = 2.0;
uniform float depth_offset = -0.75;

uniform float edge_scale = 0.01;
uniform float near = 1.0;
uniform float far = 100.0;
uniform vec3 edge_color : source_color;

// Parámetros para el fade progresivo del edge
uniform float edge_fade_distance : hint_range(0.001, 100.0) = 0.02;
uniform float edge_max_alpha : hint_range(0.0, 1.0) = 0.8;
uniform float edge_min_alpha : hint_range(0.0, 1.0) = 0.0;

uniform float view_opacity_start : hint_range(0.0, 50.0) = 5.0;
uniform float view_opacity_end : hint_range(-10000.0, 10000.0) = 30.0;
uniform float view_opacity_power : hint_range(0.01, 50.0) = 2.0;

uniform vec3 sky_color_horizon : source_color = vec3(0.8, 0.9, 1.0);
uniform vec3 sky_color_zenith : source_color = vec3(0.2, 0.4, 0.8);
uniform float sky_influence : hint_range(0.0, 20.0) = 1.0;
uniform float sky_fresnel_power : hint_range(0.1, 100.0) = 3.0;
uniform float sky_gradient_power : hint_range(0.1, 50.0) = 2.0;

// NUEVOS UNIFORMS PARA GOD RAYS
uniform vec3 sun_direction = vec3(0.3, -0.7, 0.3);
uniform vec3 godray_color : source_color = vec3(1.0, 0.95, 0.8);
uniform float godray_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float godray_density : hint_range(0.0, 1.0) = 0.3;
uniform float godray_samples : hint_range(4.0, 64.0) = 16.0;
uniform float godray_fade_distance : hint_range(1.0, 100.0) = 20.0;
uniform float godray_scatter : hint_range(0.0, 1.0) = 0.5;
uniform float godray_noise_scale : hint_range(0.1, 10.0) = 2.0;
uniform float godray_noise_speed : hint_range(0.0, 2.0) = 0.3;
uniform float godray_phase_intensity : hint_range(0.0, 5.0) = 2.0;

uniform vec3 sss_color : source_color = vec3(0.0, 0.8, 0.6);
uniform float sss_intensity : hint_range(0.0, 3.0) = 1.2;
uniform float sss_power : hint_range(1.0, 8.0) = 3.0;

uniform sampler2D foam_texture : repeat_enable, filter_linear_mipmap;
uniform float foam_edge_threshold : hint_range(0.0, 2.0) = 0.5;
uniform float foam_crest_threshold : hint_range(0.0, 1.0) = 0.6;
uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 1.0);

uniform vec3 underwater_fog_color : source_color = vec3(0.4, 0.55, 0.7);
uniform float underwater_fog_density : hint_range(0.0, 100.0) = 0.15;
uniform float underwater_fog_start : hint_range(0.0, 50.0) = 5.0;
uniform float water_time;

uniform vec3 planet_center;

varying vec3 world_pos;
varying float height;
varying float view_depth;
varying vec3 world_normal_radial;

float fresnel(float amount, vec3 normal, vec3 view) {
    return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

float edge(float depth){
    depth = 1.0 - 2.0 * depth;
    return near * far / (far + depth * (near - far));
}

// Función para generar olas procedurales como fallback
float generate_wave(vec2 pos, float time) {
    float wave1 = sin(pos.x * wave_frequency + time * wave_speed) * wave_amplitude;
    float wave2 = sin(pos.y * wave_frequency * 0.7 + time * wave_speed * 0.8) * wave_amplitude * 0.5;
    float wave3 = sin((pos.x + pos.y) * wave_frequency * 0.5 + time * wave_speed * 1.2) * wave_amplitude * 0.3;
    return (wave1 + wave2 + wave3) * 0.1;
}

// Función para calcular el color del cielo
vec3 calculate_sky_color(vec3 view_direction) {
    float vertical_angle = clamp(view_direction.y * 0.5 + 0.5, 0.0, 1.0);
    vertical_angle = pow(vertical_angle, sky_gradient_power);
    return mix(sky_color_horizon, sky_color_zenith, vertical_angle);
}

// Función para rotar coordenadas UV
vec2 rotate_uv(vec2 uv, float angle) {
    float cos_angle = cos(angle);
    float sin_angle = sin(angle);
    mat2 rotation_matrix = mat2(vec2(cos_angle, -sin_angle), vec2(sin_angle, cos_angle));
    return rotation_matrix * uv;
}

// NUEVAS FUNCIONES PARA GOD RAYS

// Función de ruido 3D simple para los god rays
float hash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    return mix(mix(mix(hash(i + vec3(0, 0, 0)),
                       hash(i + vec3(1, 0, 0)), f.x),
                   mix(hash(i + vec3(0, 1, 0)),
                       hash(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash(i + vec3(0, 0, 1)),
                       hash(i + vec3(1, 0, 1)), f.x),
                   mix(hash(i + vec3(0, 1, 1)),
                       hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Función de fase de Henyey-Greenstein para dispersión de luz
float henyeyGreenstein(float cos_theta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * 3.14159 * pow(1.0 + g2 - 2.0 * g * cos_theta, 1.5));
}

vec3 calculate_godrays(vec3 world_position, vec3 view_dir, float view_dist, vec3 surface_normal, vec3 cam_pos) {
    vec3 to_sun = normalize(-sun_direction);

    // Up desde la cámara, no desde el fragmento
    vec3 up = normalize(cam_pos - planet_center);

    // Sol proyectado al plano tangente del observador
    vec3 sun_horiz = normalize(to_sun - up * dot(to_sun, up));

    // Normal del plano cámara→sol (perpendicular a la columna)
    vec3 column_normal = normalize(cross(sun_horiz, up));

    // Distancia REAL en metros del fragmento al plano de la columna
    vec3 cam_to_frag = world_position - cam_pos;
    float lateral_dist = abs(dot(cam_to_frag, column_normal));

    // Gaussiana: ancho de la columna en metros
    float column_width = 85.0; // ajustable
   	float column = exp(-(lateral_dist * lateral_dist) / (column_width * column_width));
	column = mix(0.15, 1.0, column); // nunca baja de 0.15

    // Solo hacia el sol, no detrás
    float forward = max(dot(cam_to_frag, -sun_horiz), 0.0);
    forward = smoothstep(10.0, 100.0, forward);

    // Atenuación por distancia
    float distance_fade = 1.0 - exp(-view_dist / godray_fade_distance);

    // Variación sutil con normales
    float normal_var = dot(surface_normal, to_sun) * 0.5 + 0.5;
    normal_var = smoothstep(0.3, 0.7, normal_var);

    return godray_color * column * forward * distance_fade * (0.7 + normal_var * 0.3) * godray_intensity;
}

// Triplanar con UDN blend — devuelve normal en WORLD SPACE
vec3 triplanar_normal_udn(sampler2D tex, vec3 pos, vec3 surface_normal,
                          vec3 weights, float scale, vec2 time_offset) {
    // Sample los 3 planos y decodifica a [-1,1]
    vec3 n_xz = texture(tex, pos.xz / scale + time_offset).rgb * 2.0 - 1.0;
    vec3 n_xy = texture(tex, pos.xy / scale + time_offset).rgb * 2.0 - 1.0;
    vec3 n_yz = texture(tex, pos.yz / scale + time_offset).rgb * 2.0 - 1.0;

    // Reorientar cada sample al eje correcto del plano de proyección
    // xz → plano Y-up, xy → plano Z-up, yz → plano X-up
    vec3 world_n_xz = vec3(n_xz.x, 0.0, n_xz.y);
    vec3 world_n_xy = vec3(n_xy.x, n_xy.y, 0.0);
    vec3 world_n_yz = vec3(0.0, n_yz.y, n_yz.x);

    // UDN: sumar con la normal de superficie y re-normalizar
    vec3 blended = world_n_xz * weights.y
                 + world_n_xy * weights.z
                 + world_n_yz * weights.x;

    return normalize(blended + surface_normal);
}

float linearize_depth(float depth_sample, mat4 projection_matrix) {
    float ndc = depth_sample * 2.0 - 1.0;
    return projection_matrix[3][2] / (ndc + projection_matrix[2][2]);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 sphere_dir = normalize(world_pos - planet_center); // necesitas pasar el centro como uniform
	vec2 uv_coords = vec2(
	    atan(sphere_dir.x, sphere_dir.z),  // longitud [-PI, PI]
	    asin(sphere_dir.y)                  // latitud [-PI/2, PI/2]
	) * noise_scale;
    height = texture(wave, uv_coords / noise_scale + water_time * time_scale).r;

    float procedural_height = generate_wave(uv_coords, water_time);

    float total_height = height + procedural_height;
    VERTEX += NORMAL * total_height * height_scale;
    world_normal_radial = sphere_dir;

    vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    view_depth = -view_pos.z - 0.5;
}

void fragment() {
    float depth_texture = texture(DEPTH_TEXTURE, SCREEN_UV).r * 2.0 - 1.0;
    float depth = PROJECTION_MATRIX[3][2] / (depth_texture + PROJECTION_MATRIX[2][2]);

    float water_depth = depth + VERTEX.z + depth_offset;
    float depth_blend = exp(water_depth * -beers_law);
    depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);
    float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

    float view_distance_factor = clamp(
        (view_depth - view_opacity_start) / (view_opacity_end - view_opacity_start),
        0.0,
        1.0
    );
    view_distance_factor = pow(view_distance_factor, view_opacity_power);

    float adjusted_depth_blend = mix(depth_blend_power, 1.0, view_distance_factor);
    float screen_influence = 1.0 - view_distance_factor;
    float z_depth = edge(texture(DEPTH_TEXTURE, SCREEN_UV).x);
    float z_pos = edge(FRAGCOORD.z);
    float z_dif = z_depth - z_pos;
	float edge_visibility = 1.0 - smoothstep(10.0, 400.0, view_depth);
    vec2 time = (TIME * wave_direction) * time_scale;
    vec2 time2 = (TIME * wave_direction2) * time_scale;
    vec3 tri_pos = world_pos - planet_center;

    vec3 blend_weights = abs(world_normal_radial);
    blend_weights = pow(blend_weights, vec3(4.0));
    blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z);

    vec3 n1 = triplanar_normal_udn(texture_normal,  tri_pos, world_normal_radial,
                                    blend_weights, normal_scale1, time);
    vec3 n2 = triplanar_normal_udn(texture_normal2, tri_pos, world_normal_radial,
                                    blend_weights, normal_scale2, time2 * 0.8);
    vec3 n3 = triplanar_normal_udn(texture_normal,  tri_pos, world_normal_radial,
                                    blend_weights, normal_scale3, time * 1.3);

    vec3 final_world_normal = normalize(
        mix(mix(n1, n2, 0.5), n3, 0.3)
    );

    final_world_normal = normalize(
        mix(world_normal_radial, final_world_normal, clamp(normal_intensity, 0.0, 1.0))
    );

    float normal_edge_factor = smoothstep(0.0, edge_scale * 3.0, z_dif);
    final_world_normal = normalize(
        mix(world_normal_radial, final_world_normal, normal_edge_factor)
    );

    vec3 tangent_deviation = final_world_normal - world_normal_radial;
    // ===== REFRACCIÓN CON DEPTH CHECK =====
	   vec2 refraction_offset = tangent_deviation.xz; 

    float refraction_strength = 0.05 * screen_influence;
    vec2 refracted_uv = SCREEN_UV + refraction_offset * refraction_strength;

    // Linealizar ambas profundidades con el mismo método
    float frag_linear_depth = linearize_depth(FRAGCOORD.z, PROJECTION_MATRIX);
    float refracted_depth_sample = texture(DEPTH_TEXTURE, refracted_uv).r;
    float refracted_linear_depth = linearize_depth(refracted_depth_sample, PROJECTION_MATRIX);
	vec3 depth_color = mix(color_shallow.rgb, color_deep.rgb, adjusted_depth_blend);

    // Si el píxel refractado está delante del agua (más cerca de la cámara),
    // es un objeto que NO debería estar sumergido → fallback a UV original
    vec2 safe_refracted_uv = (refracted_linear_depth < frag_linear_depth)
                             ? SCREEN_UV
                             : refracted_uv;

    vec3 screen_color = textureLod(SCREEN_TEXTURE, safe_refracted_uv,
                                   adjusted_depth_blend * 2.5).rgb;


    vec3 color = mix(
        mix(screen_color * depth_color, depth_color * 0.25, adjusted_depth_blend * 0.5),
        depth_color,
        view_distance_factor * 0.8
    );
	
	float water_column = clamp(z_depth - z_pos, 0.0, 200.0);

    float underwater_fog_factor = 1.0 - exp(
        -max(water_column - underwater_fog_start, 0.0) * underwater_fog_density
    );
    underwater_fog_factor = clamp(underwater_fog_factor, 0.0, 1.0);
    color = mix(color, underwater_fog_color, underwater_fog_factor);
	
    float fresnel_value = fresnel(sky_fresnel_power, NORMAL, VIEW);
    vec3 surface_color = mix(albedo, albedo2, fresnel_value);

    vec3 reflected_view = reflect(-VIEW, NORMAL);
    vec3 sky_color = calculate_sky_color(reflected_view);
    vec3 sky_reflection = sky_color * sky_influence;
	float distance_alpha = clamp(view_depth / view_opacity_end, 0.0, 1.0);
	distance_alpha = pow(distance_alpha, view_opacity_power);
	float base_alpha = mix(edge_min_alpha, edge_max_alpha, distance_alpha);
	float edge_factor = clamp(z_dif / edge_fade_distance, 0.0, 1.0);
	ALPHA = base_alpha * edge_factor;
	float distance_blend = smoothstep(10.0, 500.0, view_depth);
	ALPHA = mix(ALPHA, 1.0, distance_blend);
	
	float depth_precision_scale = 1.0 + view_depth * 0.1;
	float adjusted_edge_fade = edge_fade_distance * depth_precision_scale;

	float animated_edge = edge_scale * (1.0 + height * 0.5);
    float fade_factor = 1.0 - smoothstep(0.0, animated_edge * 2.0, z_dif);
	fade_factor *= edge_visibility;

	vec3 foam_dir = normalize(world_pos); // escala sobre la esfera, no sobre la grid 3D
	vec3 foam_noise_pos = foam_dir + vec3(time.x, 0.0, time.y);	
	float foam_pattern = noise3D(foam_noise_pos) * 0.5;
	float shore_foam = 1.0 - smoothstep(0.0, foam_edge_threshold, z_dif);
	shore_foam *= (0.5 + foam_pattern * 0.5); // romper uniformidad
	shore_foam *= (0.7 + height * 0.3); // olas empujan la espuma
	shore_foam *= edge_visibility;

	float crest_foam = smoothstep(foam_crest_threshold, 1.0, height);
	float total_foam = clamp((shore_foam + crest_foam) * foam_pattern, 0.0, 1.0);
	vec3 blended_edge_color = mix(color, edge_color, fade_factor);
	// La foam se concentra más en la línea de contacto
	float foam_on_edge = clamp(fade_factor * 1.5, 0.0, 1.0);
	blended_edge_color = mix(blended_edge_color, foam_color, foam_on_edge * shore_foam);
	vec3 depth_color_adj = mix(blended_edge_color, sky_reflection, fresnel_value * 0.8);
	depth_color_adj = mix(depth_color_adj, blended_edge_color, adjusted_depth_blend * 0.3);

    vec3 final_albedo = mix(surface_color + depth_color_adj, sky_reflection, fresnel_value * sky_influence * 0.5);
	vec3 sun_dir_norm = normalize(-sun_direction);
	float sss_dot = pow(clamp(dot(VIEW, -sun_dir_norm), 0.0, 1.0), sss_power);
	float sss_depth_mask = clamp(1.0 - adjusted_depth_blend, 0.0, 1.0); // solo en zonas poco profundas
	vec3 sss_contrib = sss_color * sss_dot * sss_intensity * sss_depth_mask;
	final_albedo += sss_contrib;
	final_albedo = mix(final_albedo, foam_color, total_foam);
    vec3 view_dir_world = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec3 up_dir = normalize(world_pos - planet_center);
	float horizon_dot = 1.0 - abs(dot(view_dir_world, up_dir));
	horizon_dot = pow(horizon_dot, 20.0); // concentrar más en el horizonte

	float fog_blend = smoothstep(horizon_fog_start, horizon_fog_end, view_depth) * horizon_dot;
	final_albedo = mix(final_albedo, horizon_fog_color, fog_blend);
	/*vec3 view_dir = normalize(world_pos - CAMERA_POSITION_WORLD);
	float godray_max_dist = min(view_depth, godray_fade_distance);
	vec3 godrays = calculate_godrays(world_pos, view_dir, godray_max_dist, NORMAL, CAMERA_POSITION_WORLD);

	float godray_depth_mask = mix(1.0, 0.3, adjusted_depth_blend);
	float godray_horizon_mask = 1.0 - fog_blend;
	final_albedo += godrays * godray_depth_mask * godray_horizon_mask;*/
	vec3 reflect_sun = reflect(sun_direction, NORMAL);
	float glint = pow(max(dot(reflect_sun, -view_dir_world), 0.0), 128.0);
	final_albedo += godray_color * glint * 2.0 * (1.0 - adjusted_depth_blend);
	ALBEDO = clamp(final_albedo, vec3(0.0), vec3(1.0));
    SPECULAR = 0.5;
	METALLIC = metallic;
    ROUGHNESS = roughness;
	NORMAL = normalize((VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz);
}