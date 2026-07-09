shader_type spatial;
render_mode blend_mix, shadows_disabled, depth_draw_always;

uniform sampler2D DEPTH_TEXTURE: hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;
uniform vec3 albedo : source_color = vec3(0.05, 0.20, 0.30);
uniform vec3 albedo2 : source_color = vec3(0.10, 0.35, 0.50);
uniform float metallic : hint_range(0.0, 1.0, 0.1) = 0.0;
uniform float roughness : hint_range(0.0, 1.0, 0.1) = 0.05;

uniform sampler2D texture_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D texture_normal2 : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D wave : repeat_enable, filter_linear_mipmap;

uniform vec2 wave_direction2 = vec2(0.0, 1.0);
uniform float time_scale : hint_range(0.0, 0.2, 0.001) = 0.0025;
uniform float noise_scale = 8.0;
uniform float height_scale = 0.35;

// Parámetros para romper el tiling de las normales
uniform float normal_scale1 : hint_range(0.1, 500.0) = 40.0;
uniform float normal_scale2 : hint_range(0.1, 500.0) = 120.0;
uniform float normal_scale3 : hint_range(0.1, 500.0) = 350.0;
uniform float normal_intensity : hint_range(0.0, 200.0) = 7.0;
uniform float wave_normal_sample_distance : hint_range(0.01, 100.0, 0.01) = 2.0;

uniform float wave_frequency = 2.0;
uniform float wave_world_scale : hint_range(1.0, 500.0) = 60.0; // metros por tile

// Uniforms y suma de olas Gerstner compartidos con la niebla submarina.
#include "res://shaders/liquid/gerstner_waves.gdshaderinc"
// waterline_signed(): corte de línea de flotación compartido con underwater.gdshader.
#include "res://shaders/liquid/underwater_fog.gdshaderinc"

uniform vec4 color_deep : source_color = vec4(0.02, 0.14, 0.25, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.37, 0.72, 0.71, 1.0);
uniform float beers_law = 1.5;
uniform float depth_offset = 0.0;

// Coeficientes de absorción Beer-Lambert por canal RGB.
uniform vec3 absorption_coefficients = vec3(0.45, 0.18, 0.06);

uniform float edge_scale = 10.0;
uniform float edge_disable_start : hint_range(0.0, 1000.0) = 60.0;
uniform float edge_disable_end : hint_range(0.0, 1000.0) = 150.0;
uniform float detail_fade_start : hint_range(0.0, 20000.0) = 80.0;
uniform float detail_fade_end : hint_range(0.0, 20000.0) = 250.0;
uniform float refraction_blur : hint_range(0.0, 3.0, 0.05) = 2.5; // mip máx del fondo refractado con la profundidad; 0 = nítido (sin línea oscura de orilla)

uniform float surface_alpha : hint_range(0.0, 1.0) = 0.15;
uniform float deep_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float refraction_alpha_floor : hint_range(0.0, 1.0) = 0.32;
uniform float refraction_strength : hint_range(0.0, 2.0, 0.001) = 0.05;
uniform float refraction_depth_fade : hint_range(0.01, 100.0, 0.01) = 8.0;
uniform float refraction_uv_margin : hint_range(0.0, 0.05, 0.001) = 0.002;
uniform float refraction_edge_soft : hint_range(0.001, 5.0, 0.001) = 0.5; // ancho de la transición on/off de refracción
uniform float depth_alpha_start : hint_range(0.0, 1000.0) = 0.0;
uniform float depth_alpha_end : hint_range(0.001, 10000.0) = 40.0;
uniform float depth_alpha_power : hint_range(0.01, 10.0) = 1.4;
uniform float grazing_shore_fade : hint_range(0.0, 20.0, 0.1) = 3.0; // profundidad (m) a la que el oscurecido rasante llega a pleno; evita la línea oscura en la orilla

uniform vec3 sky_color_horizon : source_color = vec3(0.75, 0.85, 0.95);
uniform vec3 sky_color_zenith : source_color = vec3(0.30, 0.55, 0.85);
uniform float sky_influence : hint_range(0.0, 20.0) = 0.6;
uniform float sky_fresnel_power : hint_range(0.1, 100.0) = 5.0;
uniform float sky_gradient_power : hint_range(0.1, 50.0) = 2.5;

uniform vec3 sun_direction = vec3(0.4, -0.7, 0.3);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_energy : hint_range(0.0, 16.0) = 1.0;
uniform float sun_specular_intensity : hint_range(0.0, 8.0) = 0.3;
uniform float glint_depth_fade : hint_range(0.0, 20.0) = 3.0; // profundidad a la que el glint alcanza su fuerza plena

// Control de iluminación puntual (antorcha, etc.) para evitar reventones de especular
uniform float light_specular_clamp : hint_range(0.0, 4.0) = 0.6;   // tope de especular por luz
uniform float light_roughness_floor : hint_range(0.0, 1.0) = 0.25; // ensancha el brillo puntual
uniform float light_diffuse_strength : hint_range(0.0, 2.0) = 1.0;
uniform float light_diffuse_wrap : hint_range(0.0, 1.0) = 0.6; // 0 = Lambert puro (dorso de ola a negro), 1 = half-Lambert

// Screen-space reflections
uniform bool ssr_enabled = true;
uniform int ssr_max_steps : hint_range(0, 64) = 20;
uniform float ssr_step : hint_range(0.05, 5.0) = 0.6;         // paso inicial en metros (view space)
uniform float ssr_thickness : hint_range(0.05, 10.0) = 10.0;   // grosor de impacto tolerado
uniform float ssr_distance_fade : hint_range(1.0, 5000.0) = 400.0; // apaga SSR con la distancia

uniform vec3 sss_color : source_color = vec3(0.15, 0.55, 0.45);
uniform float sss_intensity : hint_range(0.0, 3.0) = 0.8;
uniform float sss_power : hint_range(1.0, 8.0) = 4.0;

// Espuma procedural
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 0.98);
uniform float foam_noise_scale : hint_range(0.0, 10.0, 0.01) = 2.0;
uniform float foam_noise_speed : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float foam_crest_threshold : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float foam_crest_softness  : hint_range(0.02, 0.8, 0.01) = 0.3; // ancho de la banda de cresta (dot). Bajo = línea dura
uniform float foam_crest_amount    : hint_range(0.0, 10.0, 0.1) = 2.0;
uniform float foam_noise_amount    : hint_range(0.0, 1.0, 0.01) = 0.2; // cuánto deforma el ruido el borde de la banda de cresta
uniform float foam_noise_warp      : hint_range(0.0, 4.0, 0.01) = 1.5; // domain warp: riza el borde en vez de ondularlo

// Estela de espuma de las grids dinámicas (lo rellena FoamWakeManager por frame).
// Cada estela = rango de puntos [wake_ranges] con culling por esfera envolvente [wake_bounds].
const int MAX_WAKES = 8;
const int MAX_WAKE_POINTS = 512;
uniform int wake_count = 0;
uniform vec4 wake_bounds[MAX_WAKES];    // xyz = centro, w = radio de la esfera envolvente
uniform vec2 wake_ranges[MAX_WAKES];    // x = primer punto, y = nº de puntos
uniform vec4 wake_points[MAX_WAKE_POINTS];  // xyz = posición world, w = radio del punto
uniform float wake_alphas[MAX_WAKE_POINTS];
uniform float shore_soft_width : hint_range(0.01, 10.0, 0.01) = 1.5;

// Caustics
uniform sampler2D caustics_texture : filter_linear_mipmap, repeat_enable;
uniform float caustics_scale : hint_range(0.1, 10.0, 0.1) = 2.0;
uniform float caustics_speed : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float caustics_intensity : hint_range(0.0, 2.0, 0.1) = 0.8;
uniform float caustics_depth_fade : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float caustics_near_fade : hint_range(0.0, 10.0, 0.1) = 1.5;

uniform float water_time;
uniform vec3 planet_center;
uniform float water_radius;

varying vec3 world_pos;
varying vec3 base_world_pos;
varying float view_depth;
varying vec3 world_normal_radial;
varying vec3 world_gerstner_normal;
varying float wave_crest_signal;
varying vec3 waterline_point;
varying vec3 waterline_normal;

float fresnel(float amount, vec3 normal, vec3 view) {
    return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

vec3 calculate_sky_color(vec3 view_direction) {
    float vertical_angle = clamp(view_direction.y * 0.5 + 0.5, 0.0, 1.0);
    vertical_angle = pow(vertical_angle, sky_gradient_power);
    return mix(sky_color_horizon, sky_color_zenith, vertical_angle);
}

// Triplanar con UDN blend — devuelve normal en WORLD SPACE
vec3 triplanar_normal_udn(sampler2D tex, vec3 pos, vec3 surface_normal,
                          vec3 weights, float scale, vec2 time_offset) {
    vec3 n_xz = texture(tex, pos.xz / scale + time_offset).rgb * 2.0 - 1.0;
    vec3 n_xy = texture(tex, pos.xy / scale + time_offset).rgb * 2.0 - 1.0;
    vec3 n_yz = texture(tex, pos.yz / scale + time_offset).rgb * 2.0 - 1.0;

    vec3 world_n_xz = vec3(n_xz.x, 0.0, n_xz.y);
    vec3 world_n_xy = vec3(n_xy.x, n_xy.y, 0.0);
    vec3 world_n_yz = vec3(0.0, n_yz.y, n_yz.x);

    vec3 blended = world_n_xz * weights.y
                 + world_n_xy * weights.z
                 + world_n_yz * weights.x;

    return normalize(blended + surface_normal);
}

float linearize_depth(vec2 uv, float depth_sample, mat4 inv_projection_matrix) {
    vec3 ndc;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
        ndc = vec3(uv, depth_sample) * 2.0 - 1.0;
    #else
        ndc = vec3(uv * 2.0 - 1.0, depth_sample);
    #endif

    vec4 view = inv_projection_matrix * vec4(ndc, 1.0);
    view.xyz /= view.w;
    return -view.z;
}

vec3 reconstruct_world_position(vec2 uv, float depth_sample, mat4 inv_projection_matrix, mat4 inv_view_matrix) {
    vec3 ndc;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
        ndc = vec3(uv, depth_sample) * 2.0 - 1.0;
    #else
        ndc = vec3(uv * 2.0 - 1.0, depth_sample);
    #endif

    vec4 world = inv_view_matrix * inv_projection_matrix * vec4(ndc, 1.0);
    return world.xyz / world.w;
}

float ray_sphere_depth(vec3 ray_origin, vec3 ray_direction, vec3 sphere_center, float sphere_radius) {
    if (sphere_radius <= 0.0) {
        return 0.0;
    }

    vec3 offset = ray_origin - sphere_center;
    float b = dot(offset, ray_direction);
    float c = dot(offset, offset) - sphere_radius * sphere_radius;
    float discriminant = b * b - c;

    if (discriminant <= 0.0) {
        return 0.0;
    }

    float root = sqrt(discriminant);
    float enter_distance = max(-b - root, 0.0);
    float exit_distance = max(-b + root, 0.0);
    return max(exit_distance - enter_distance, 0.0);
}

// Ray-march del rayo reflejado contra el depth buffer. Devuelve el color de escena
// reflejado y en `hit` la confianza [0,1] (0 = fallo → usar cielo como fallback).
vec3 screen_space_reflection(vec3 view_pos, vec3 view_normal, mat4 projection,
                             mat4 inv_projection, out float hit) {
    hit = 0.0;
    vec3 refl = reflect(normalize(view_pos), view_normal);
    float step_len = ssr_step;
    vec3 p = view_pos;

    for (int i = 0; i < ssr_max_steps; i++) {
        p += refl * step_len;
        if (-p.z <= 0.0) {
            break; // el rayo pasa por detrás de la cámara
        }
        vec4 clip = projection * vec4(p, 1.0);
        vec2 uv = (clip.xy / clip.w) * 0.5 + 0.5;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            break; // fuera de pantalla
        }
        float scene = linearize_depth(uv, texture(DEPTH_TEXTURE, uv).r, inv_projection);
        float ray_depth = -p.z;
        float diff = ray_depth - scene;
        if (diff > 0.0 && diff < ssr_thickness) {
            vec2 edge = abs(uv - 0.5) * 2.0;
            hit = smoothstep(1.0, 0.7, max(edge.x, edge.y)); // desvanecer en bordes de pantalla
            return textureLod(SCREEN_TEXTURE, uv, 0.0).rgb;
        }
        step_len *= 1.15; // pasos crecientes: precisión cerca, alcance lejos
    }
    return vec3(0.0);
}

// --- Foam noise helpers ---

float hash13(vec3 p) {
    uvec3 q = uvec3(ivec3(p)) * uvec3(1597334677u, 3812015801u, 2798796415u);
    uint n = (q.x ^ q.y ^ q.z) * 1597334677u;
    return float(n) * (1.0 / 4294967295.0);
}

float noise3d(in vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    // Fade quíntico (Perlin mejorado): derivada segunda continua, sin rejilla visible.
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(
        mix(
            mix(hash13(i + vec3(0.0, 0.0, 0.0)), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
            mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
        mix(
            mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
            mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

// fBm de 3 octavas rotando el dominio entre capas para no acumular artefactos de eje.
// Devuelve ~[0,1].
float fbm3d(vec3 p) {
    const mat3 rot = mat3(
        vec3( 0.00,  0.80,  0.60),
        vec3(-0.80,  0.36, -0.48),
        vec3(-0.60, -0.48,  0.64));
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        v += a * noise3d(p);
        p = rot * p * 2.03 + vec3(31.7);
        a *= 0.5;
    }
    return v * (1.0 / 0.875);
}

// ---

void vertex() {
    base_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 sphere_dir = normalize(base_world_pos - planet_center);

    vec3 gerstner_normal;
    float crest_signal;
    vec3 disp = gerstner_surface(base_world_pos - planet_center, sphere_dir, water_time, gerstner_normal, crest_signal);
    wave_crest_signal = crest_signal;

    // disp es world-space; lo llevamos al espacio local del modelo para modificar VERTEX.
    VERTEX += inverse(mat3(MODEL_MATRIX)) * disp;
    world_normal_radial = sphere_dir;
    world_gerstner_normal = gerstner_normal;
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    view_depth = -view_pos.z - 0.5;

    // Plano local de la línea de flotación (idéntico al de underwater.gdshader): los píxeles
    // que arrancan bajo el agua no se dibujan aquí — la vista sumergida la renderiza entera
    // el quad de niebla contra la MISMA superficie Gerstner (este shader está pensado para
    // verse desde arriba y desde abajo produce iluminación sin sentido).
    vec3 cam_local = CAMERA_POSITION_WORLD - planet_center;
    vec3 up_dir = normalize(cam_local);
    float cam_surface_radius = water_radius + gerstner_surface_height(cam_local, water_time);
    vec3 cam_surface_normal;
    gerstner_surface(cam_local, up_dir, water_time, cam_surface_normal);
    waterline_point = planet_center + up_dir * cam_surface_radius;
    waterline_normal = normalize(cam_surface_normal);
}

void fragment() {
    // Corte de línea de flotación por píxel: mismo test y argumentos que underwater.gdshader,
    // así ambos particionan la pantalla píxel-exacto al cruzar la superficie.
    vec4 wl_near_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
    wl_near_view.xyz /= wl_near_view.w;
    vec3 wl_p_near = (INV_VIEW_MATRIX * vec4(wl_near_view.xyz, 1.0)).xyz;
    if (waterline_signed(wl_p_near, waterline_point, waterline_normal, SCREEN_UV.x, TIME) < 0.0) {
        discard;
    }

    float scene_depth_sample = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    float frag_linear = linearize_depth(SCREEN_UV, FRAGCOORD.z, INV_PROJECTION_MATRIX);
    vec3 view_dir_w = normalize(world_pos - CAMERA_POSITION_WORLD);
    vec3 cam_fwd    = -normalize((INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
    float cos_view  = max(abs(dot(view_dir_w, cam_fwd)), 0.15);
    vec3 scene_world_pos = reconstruct_world_position(SCREEN_UV, scene_depth_sample, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
    float terrain_water_depth = max(water_radius - length(scene_world_pos - planet_center), 0.0);
    float detail_fade = smoothstep(detail_fade_start, detail_fade_end, view_depth);
	float water_depth = terrain_water_depth + depth_offset;
    float depth_blend = exp(water_depth * -beers_law);
    depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);
    float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

    float view_distance = length(world_pos - CAMERA_POSITION_WORLD);
    float view_opacity_factor = smoothstep(0.0, edge_disable_end, view_distance);
    float adjusted_depth_blend = mix(depth_blend_power, 1.0, view_opacity_factor);

    float z_dif = linearize_depth(SCREEN_UV, scene_depth_sample, INV_PROJECTION_MATRIX) - frag_linear;
    float edge_disable = smoothstep(edge_disable_start, edge_disable_end, view_depth);

    vec3 radial_normal = normalize(world_normal_radial);
    vec3 wave_world_normal = normalize(world_gerstner_normal);
    vec3 final_world_normal = wave_world_normal;

    if (detail_fade < 0.999) {
        vec2 time  = (TIME * wave_direction)  * time_scale;
        vec2 time2 = (TIME * wave_direction2) * time_scale;
        vec3 tri_pos = world_pos - planet_center;

        vec3 blend_weights = abs(wave_world_normal);
        blend_weights = pow(blend_weights, vec3(4.0));
        blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z);

        vec3 n1 = triplanar_normal_udn(texture_normal,  tri_pos, wave_world_normal, blend_weights, normal_scale1, time);
        vec3 n2 = triplanar_normal_udn(texture_normal2, tri_pos, wave_world_normal, blend_weights, normal_scale2, time2 * 0.8);
        vec3 n3 = triplanar_normal_udn(texture_normal,  tri_pos, wave_world_normal, blend_weights, normal_scale3, time * 1.3);

        vec3 detailed_normal = normalize(mix(mix(n1, n2, 0.5), n3, 0.3));
        detailed_normal = normalize(
            mix(wave_world_normal, detailed_normal, clamp(normal_intensity, 0.0, 100.0))
        );

        // Fade hacia normal radial lisa con la distancia
        final_world_normal = normalize(mix(detailed_normal, wave_world_normal, detail_fade));
    }

    float normal_edge_factor = smoothstep(0.0, edge_scale * 3.0, z_dif);
    normal_edge_factor = mix(normal_edge_factor, 1.0, edge_disable);
    final_world_normal = normalize(mix(radial_normal, final_world_normal, normal_edge_factor));

    // Detección de cresta: usamos wave_crest_signal (término de pliegue Gerstner), que PICA en
    // la cresta real (sin(phase)=1). La normal, en cambio, se inclina en los flancos, así que la
    // espuma antigua caía en las laderas y no en el pico. Señal alta = cresta; banda suave con el
    // umbral deformado por ruido para romper la línea.
    // fBm con domain warp: una primera pasada de ruido desplaza el dominio de la segunda,
    // rizando el borde de la banda con filamentos orgánicos en lugar de manchas blandas.
    vec3 foam_np = (world_pos - planet_center) * foam_noise_scale;
    vec3 foam_drift = vec3(0.0, water_time * foam_noise_speed, 0.0);
    float warp = fbm3d(foam_np * 0.45 + foam_drift * 1.6 + vec3(13.1));
    float crest_noise = fbm3d(foam_np + foam_drift + (warp - 0.5) * foam_noise_warp * vec3(1.0, 0.35, 1.0));
    float deformed_crest = wave_crest_signal + (crest_noise - 0.5) * foam_noise_amount;
    float wave_crest_factor = smoothstep(foam_crest_threshold, foam_crest_threshold + foam_crest_softness, deformed_crest);
    wave_crest_factor = pow(wave_crest_factor, 1.5) * foam_crest_amount;
    float crest_foam = clamp(wave_crest_factor, 0.0, 1.0);
    float foam_level = crest_foam;

    // Refracción — suprimida donde aparece espuma
    vec3 tangent_deviation = final_world_normal - radial_normal;
    vec3 enhanced_deviation = tangent_deviation * 5.0;
    vec3 tangent_dev_view = (VIEW_MATRIX * vec4(enhanced_deviation, 0.0)).xyz;

    vec2 probe_offset = tangent_dev_view.xy * refraction_strength * 0.5;
    vec2 probe_uv = clamp(SCREEN_UV + probe_offset,
                          vec2(refraction_uv_margin),
                          vec2(1.0 - refraction_uv_margin));
    float probe_depth_sample = texture(DEPTH_TEXTURE, probe_uv).r;
    float probe_linear = linearize_depth(probe_uv, probe_depth_sample, INV_PROJECTION_MATRIX);
    float depth_at_probe = max(probe_linear - frag_linear, 0.0);

    float depth_fac = clamp(depth_at_probe / refraction_depth_fade, 0.0, 4.0);

    float refraction_angle_factor = smoothstep(0.15, 0.6, cos_view);
    vec4 dev_clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(enhanced_deviation, 0.0);
    vec2 dev_screen = dev_clip.xy / max(frag_linear, 0.001);

    vec2 refraction_offset = dev_screen
                           * refraction_strength
                           * depth_fac
                           * refraction_angle_factor
                           * (1.0 - foam_level); // sin refracción en orillas

    vec2 refracted_uv = clamp(
        SCREEN_UV + refraction_offset,
        vec2(refraction_uv_margin),
        vec2(1.0 - refraction_uv_margin)
    );

    float refracted_depth_sample = texture(DEPTH_TEXTURE, refracted_uv).r;
    float refr_linear = linearize_depth(refracted_uv, refracted_depth_sample, INV_PROJECTION_MATRIX);
    // Transición suave (antes step() → línea dura donde el punto refractado cruza la superficie).
    float refracted_is_under_water = smoothstep(frag_linear, frag_linear + refraction_edge_soft, refr_linear);
    // Clamp a [0,1]: depth_fac llega a 4 y sin clamp el mix EXTRAPOLA la UV fuera de rango.
    float refract_mix = clamp(refracted_is_under_water * depth_fac, 0.0, 1.0);
    vec2 final_uv = mix(SCREEN_UV, refracted_uv, refract_mix);
	float final_uv_depth_sample = texture(DEPTH_TEXTURE, final_uv).r;
	
    vec3 screen_color = textureLod(SCREEN_TEXTURE, final_uv, adjusted_depth_blend * refraction_blur).rgb;

    // Cáusticas submarinas con triplanar mapping (evita estiramiento en caras verticales)
	vec4 bg_ndc = vec4(final_uv * 2.0 - 1.0, final_uv_depth_sample, 1.0);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	bg_ndc.z = bg_ndc.z * 2.0 - 1.0;
	#endif
	vec4 bg_world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * bg_ndc;
	vec3 bg_world_pos = bg_world.xyz / bg_world.w;

	// Normal del fondo desde derivadas. FUERA de la rama: dFdx/dFdy no está definido en
	// control de flujo no uniforme. Y en el borde de profundidad cross(...) ≈ 0 →
	// normalize(0) = NaN, que colaba como línea negra (NaN * caustics_intensity sigue siendo NaN).
	vec3 bg_dx = dFdx(bg_world_pos);
	vec3 bg_dy = dFdy(bg_world_pos);
	vec3 bg_cross = cross(bg_dy, bg_dx);
	float bg_cross_len = length(bg_cross);
	vec3 bg_normal = bg_cross_len > 1e-6 ? bg_cross / bg_cross_len : radial_normal;

	float caustics_contrib = 0.0;
	if (water_depth > 0.0) {
	    // Pesos triplanar XYZ. Exponente alto para que el plano dominante "gane" claramente
	    // y evitar mezclas borrosas en transiciones.
	    vec3 tri_weights = abs(bg_normal);
	    tri_weights = pow(tri_weights, vec3(4.0));
	    tri_weights /= (tri_weights.x + tri_weights.y + tri_weights.z + 1e-5);

	    // Coordenadas mundiales escaladas. Cada plano de proyección parametriza la cara
	    // perpendicular a ese eje sin estirarse.
	    vec3 cp = bg_world_pos * caustics_scale;
	    vec2 scroll1 = vec2(TIME * caustics_speed, 0.0);
	    vec2 scroll2 = vec2(0.0, -TIME * caustics_speed * 0.8);

	    // Tres proyecciones (top XZ, front XY, side YZ), cada una con sus dos capas animadas.
	    float c_xz = texture(caustics_texture, cp.xz + scroll1).r
	               * texture(caustics_texture, cp.xz * 0.7 + scroll2).r;
	    float c_xy = texture(caustics_texture, cp.xy + scroll1).r
	               * texture(caustics_texture, cp.xy * 0.7 + scroll2).r;
	    float c_yz = texture(caustics_texture, cp.yz + scroll1).r
	               * texture(caustics_texture, cp.yz * 0.7 + scroll2).r;

	    // Mezcla según la normal: tri_weights.y → cara horizontal (normal en Y),
	    // tri_weights.z → cara perpendicular a Z, tri_weights.x → cara perpendicular a X.
	    float caustics_value = c_xz * tri_weights.y
	                         + c_xy * tri_weights.z
	                         + c_yz * tri_weights.x;

	    float caustics_fade = smoothstep(0.0, caustics_near_fade, water_depth)
	                        * (1.0 - clamp(water_depth * caustics_depth_fade, 0.0, 1.0));
	    caustics_contrib = caustics_value * caustics_intensity * caustics_fade;
	}

    // Absorción Beer-Lambert con corrección por ángulo
    float scene_linear = linearize_depth(final_uv, final_uv_depth_sample, INV_PROJECTION_MATRIX);
    float depth_diff = max(scene_linear - frag_linear, 0.0);
    float water_column = depth_diff / cos_view;

    float sphere_water_depth = ray_sphere_depth(CAMERA_POSITION_WORLD, view_dir_w, planet_center, water_radius);
    float measured_water_depth = max(terrain_water_depth, water_column);
    float has_scene_depth = 1.0 - step(0.9999, scene_depth_sample);
    float use_sphere_fallback = (1.0 - has_scene_depth) * (1.0 - step(0.001, measured_water_depth));
    float opacity_depth = mix(measured_water_depth, sphere_water_depth, use_sphere_fallback);
    float depth_alpha_factor = smoothstep(depth_alpha_start, depth_alpha_end, opacity_depth);
    depth_alpha_factor = pow(depth_alpha_factor, depth_alpha_power);
    float grazing = 1.0 - clamp(dot(radial_normal, -view_dir_w), 0.0, 1.0);
    float grazing_opacity = smoothstep(0.65, 0.95, grazing);
    // El oscurecido rasante (→ color_deep) solo tiene sentido en mar profundo; en la orilla
    // creaba una línea oscura en la silueta agua-terreno. Lo desvanecemos con la profundidad.
    grazing_opacity *= smoothstep(0.0, grazing_shore_fade, water_depth);
    float opacity_factor = max(max(depth_alpha_factor, view_opacity_factor), grazing_opacity);

    vec3 transmission = exp(-absorption_coefficients * opacity_depth);

    float scatter_t = 1.0 - exp(-opacity_depth * 0.08);
    vec3 water_scatter = mix(color_shallow.rgb, color_deep.rgb, scatter_t);

    float visibility = max(max(transmission.r, transmission.g), transmission.b) * (1.0 - opacity_factor);
    vec3 refracted_light = screen_color * transmission;
    vec3 color = mix(water_scatter, refracted_light, visibility);
    color = mix(color, color_deep.rgb, view_opacity_factor);

    vec3 view_normal = normalize((VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz);
    NORMAL = view_normal;

    // Fresnel Schlick dieléctrico (F0 ≈ 0.02 para agua): ~0 mirando recto abajo,
    // ~1 a rasante. Sustituye el pow ad-hoc anterior.
    float ndv = max(dot(view_normal, normalize(VIEW)), 0.0);
    float fresnel_value = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

    // Reflexión: cielo procedural como base, refinado con SSR donde acierta.
    vec3 reflected_view = reflect(-VIEW, view_normal);
    vec3 sky_reflection = calculate_sky_color(reflected_view) * sky_influence;
    vec3 reflection_color = sky_reflection;

    if (ssr_enabled) {
        float ssr_dist_fade = 1.0 - smoothstep(ssr_distance_fade * 0.5, ssr_distance_fade, view_distance);
        if (ssr_dist_fade > 0.001) {
            float ssr_hit;
            vec3 ssr_col = screen_space_reflection(VERTEX, view_normal, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, ssr_hit);
            // Sin reflejo bajo espuma; funde a cielo en fallos y con la distancia.
            float ssr_weight = ssr_hit * ssr_dist_fade * (1.0 - foam_level);
            reflection_color = mix(sky_reflection, ssr_col, ssr_weight);
        }
    }

    vec3 surface_color = mix(albedo, albedo2, fresnel_value);
    vec3 final_albedo = mix(color, reflection_color, fresnel_value);
    final_albedo += surface_color * fresnel_value * 0.15;
    final_albedo = mix(final_albedo, color_deep.rgb, opacity_factor);

    // Subsurface scattering
    vec3 safe_sun_direction = sun_direction;
    if (dot(safe_sun_direction, safe_sun_direction) < 0.0001) {
        safe_sun_direction = vec3(0.4, -0.7, 0.3);
    }
    vec3 sun_dir_norm = normalize(-safe_sun_direction);
    float sss_dot = pow(clamp(dot(VIEW, -sun_dir_norm), 0.0, 1.0), sss_power);
    float sss_depth_mask = clamp(1.0 - adjusted_depth_blend, 0.0, 1.0);
    vec3 sss_contrib = sss_color * sss_dot * sss_intensity * sss_depth_mask * visibility;
    final_albedo += sss_contrib;

    // Glint especular del sol (Blinn-Phong estrecho): lo que "chispea" en las crestas.
    vec3 to_sun = sun_dir_norm;              // desde la superficie hacia el sol
    vec3 to_cam = -view_dir_w;               // hacia la cámara
    vec3 half_vec = normalize(to_sun + to_cam);
    float ndh = max(dot(final_world_normal, half_vec), 0.0);
    float spec_power = mix(4000.0, 16.0, roughness);   // crestas afiladas con poca rugosidad
    float sun_glint = pow(ndh, spec_power);
    float sun_up = smoothstep(-0.1, 0.15, dot(radial_normal, to_sun)); // apaga con sol bajo el horizonte
    // En agua somera la superficie se aplana hacia la radial y el glint forma una franja
    // continua exagerada en la orilla. Lo desvanecemos con la profundidad del agua.
    float glint_shore_fade = smoothstep(0.0, glint_depth_fade, water_depth);
    final_albedo += sun_color * sun_energy * sun_glint
                  * sun_specular_intensity * sun_up * (1.0 - foam_level) * glint_shore_fade;

    // Espuma suave de orilla: línea blanca difusa justo en el contacto agua-terreno (z_dif ≈ 0).
    float shore_contact = smoothstep(shore_soft_width, 0.0, max(z_dif, 0.0));

    // Estela de espuma de los barcos: solo los píxeles dentro de la esfera envolvente
    // de alguna estela recorren sus puntos.
    float wake_foam = 0.0;
    for (int w = 0; w < wake_count; w++) {
        vec3 bd = world_pos - wake_bounds[w].xyz;
        float br = wake_bounds[w].w;
        if (dot(bd, bd) > br * br) { continue; }
        int p_start = int(wake_ranges[w].x);
        int p_end = p_start + int(wake_ranges[w].y);
        for (int i = p_start; i < p_end; i++) {
            vec4 p = wake_points[i];
            float m = 1.0 - smoothstep(p.w * 0.55, p.w, distance(world_pos, p.xyz));
            wake_foam = max(wake_foam, m * wake_alphas[i]);
        }
    }
    final_albedo = mix(final_albedo, foam_color, crest_foam);
    final_albedo = mix(final_albedo, foam_color, shore_contact);
    final_albedo = mix(final_albedo, foam_color, wake_foam);

    // La espuma está mojada: capta el sol con un brillo más ancho que el glint de agua.
    float foam_wet = max(crest_foam, max(shore_contact, wake_foam));
    float foam_glint = pow(max(dot(final_world_normal, half_vec), 0.0), 60.0);
    final_albedo += sun_color * sun_energy * foam_glint * foam_wet * 0.3 * sun_up;
    // Screen blend: añade luz sin quemar los colores existentes (A + B - A*B)
    final_albedo = final_albedo + caustics_contrib - final_albedo * caustics_contrib;

    ALBEDO = clamp(final_albedo, vec3(0.0), vec3(1.0));

    // Alpha: se desvanece suavemente en la línea de contacto con el terreno
    float shore_alpha_fade = smoothstep(0.0, shore_soft_width, max(z_dif, 0.0));
    float base_alpha = mix(surface_alpha, deep_alpha, opacity_factor);
    float refraction_alpha = refraction_alpha_floor * (1.0 - opacity_factor);
    float foam_opacity = max(crest_foam, max(shore_contact, wake_foam));
    float final_alpha = max(max(base_alpha, refraction_alpha), foam_opacity);
    final_alpha *= shore_alpha_fade;
    final_alpha = mix(final_alpha, 1.0, edge_disable);
    ALPHA = clamp(final_alpha, 0.0, deep_alpha);

    ROUGHNESS = mix(roughness, 0.8, clamp(max(crest_foam, wake_foam), 0.0, 1.0));
    SPECULAR = 0.5;
    METALLIC = metallic;
}

// Iluminación custom: reemplaza el lighting por defecto del motor para el agua.
// Sin esto, una luz puntual cercana y brillante (antorcha) revienta el especular
// del agua casi-espejo (roughness ~0.05) a un óvalo blanco saturado.
void light() {
    float ndl = dot(NORMAL, LIGHT);

    // Difuso wrap: el agua dispersa la luz internamente, así que la ladera a contraluz no cae a
    // negro (con oleaje fuerte, Lambert puro pintaba bandas negras siguiendo los dorsos de ola).
    // El pico (cara a la luz) no cambia; solo se levanta la zona muerta ndl <= 0.
    float ndotl = clamp((ndl + light_diffuse_wrap) / (1.0 + light_diffuse_wrap), 0.0, 1.0);
    DIFFUSE_LIGHT += ALBEDO * ndotl * ATTENUATION * LIGHT_COLOR * light_diffuse_strength;

    // Especular con suelo de rugosidad (ensancha el brillo puntual) y tope duro
    // para que ninguna luz individual pueda saturar a blanco. Se enmascara con el
    // ndl real: un dorso sin línea de visión a la luz no puede tener brillo especular.
    vec3 half_dir = normalize(LIGHT + VIEW);
    float ndh = max(dot(NORMAL, half_dir), 0.0);
    float r = max(ROUGHNESS, light_roughness_floor);
    float shininess = 2.0 / max(r * r, 1e-4) - 2.0;
    float spec = pow(ndh, shininess) * max(ndl, 0.0);
    spec = min(spec, light_specular_clamp);
    SPECULAR_LIGHT += spec * ATTENUATION * LIGHT_COLOR * SPECULAR_AMOUNT;
}
