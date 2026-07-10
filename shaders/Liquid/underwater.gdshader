shader_type spatial;
render_mode unshaded, depth_draw_always;

// Niebla submarina: quad a pantalla completa que compone la escena con absorción
// Beer-Lambert por canal e in-scatter por tramos de profundidad. La frontera del agua es
// la MISMA superficie Gerstner del water_shader (include compartido), de modo que la
// niebla coincide exactamente con las olas, también al cruzar la superficie. Los píxeles
// en aire con agua analítica en el near-field se nieblan desde el punto de entrada del
// rayo (sellado bajo la malla), así el corte de una ola rompiendo es exacto.

#include "res://shaders/liquid/gerstner_waves.gdshaderinc"
#include "res://shaders/liquid/underwater_fog.gdshaderinc"

uniform vec3 planet_center;
uniform float water_radius = 10000.0;
uniform float water_time = 0.0;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);

// Mismos coeficientes que water_shader: el color buceando converge con el visto desde fuera.
uniform vec3 absorption_coefficients = vec3(0.45, 0.18, 0.06);
uniform float fog_density : hint_range(0.0, 4.0) = 1.0; // multiplicador artístico de la columna de agua
uniform float sun_glow_intensity : hint_range(0.0, 2.0) = 0.35;
uniform float sun_glow_power : hint_range(1.0, 32.0) = 8.0;
uniform float tir_reflection_depth = 60.0; // el espejo TIR refleja el color de agua ~N m más profunda
uniform float scatter_vertical_range = 40.0; // gradiente claro-arriba/oscuro-abajo del in-scatter (m equivalentes)
uniform float distance_depth_gain : hint_range(0.0, 3.0) = 0.7; // m de tramo de profundidad añadidos por m de columna: oscurece la niebla con la distancia
uniform float distance_depth_max = 120.0; // tope del empuje por distancia: el horizonte converge al tramo deep; a abyss solo se llega por profundidad de cámara
uniform float meniscus_width = 0.012;   // grosor de la línea de flotación en metros sobre el near plane
uniform float meniscus_strength = 0.3;  // brillo añadido en la línea de flotación
uniform float waterline_seal_distance = 3.0; // near-field: un rayo en aire que entra en el agua analítica a menos de N m se niebla desde la entrada (sella los huecos malla-analítica al romper una ola contra la cámara)
uniform float waterline_seal_band = 0.06;    // solo se sella la banda a menos de N m sobre la línea de flotación (near plane); más arriba manda la malla, como siempre
uniform float atmosphere_leak_distance = 250.0; // tramo (m) que la atmósfera marcha bajo el agua con columna 0 (cámara pegada a la superficie)
uniform float atmosphere_leak_falloff : hint_range(0.0, 1.0) = 0.08; // caída exponencial de ese tramo por metro de columna de agua hasta la superficie

// Godrays: haces volumétricos = extrusión de la textura de cáusticas a lo largo del sol
// refractado. Raymarch corto con jitter, Beer-Lambert por canal en ambos trayectos.
uniform float godray_intensity : hint_range(0.0, 8.0) = 3.0; // 0 = apagados (se salta el march)
uniform int godray_samples : hint_range(4, 24) = 12;
uniform float godray_max_distance = 40.0;      // distancia de march: más allá la niebla los lava igualmente
uniform float godray_pattern_scale = 0.05;     // escala del patrón en la superficie (haces más anchos que las cáusticas)
uniform float godray_pattern_speed = 0.005;
uniform float godray_sharpness : hint_range(0.5, 8.0) = 2.5; // contraste de los haces
uniform float godray_phase_power : hint_range(1.0, 32.0) = 6.0;
uniform float godray_min_phase : hint_range(0.0, 1.0) = 0.15; // visibilidad mínima mirando lejos del sol

// Cáusticas: misma textura y parámetros que water_shader (los copia Underwater.setup del
// material del agua), para que el fondo se vea igual desde fuera y buceando.
uniform sampler2D caustics_texture : filter_linear_mipmap, repeat_enable;
uniform float caustics_scale : hint_range(0.1, 10.0, 0.1) = 2.0;
uniform float caustics_speed : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float caustics_intensity : hint_range(0.0, 2.0, 0.1) = 0.8;
uniform float caustics_depth_fade : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float caustics_near_fade : hint_range(0.0, 10.0, 0.1) = 1.5;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

varying float v_cam_radius;
varying float v_cam_surface_radius;
varying vec3 v_waterline_point;
varying vec3 v_waterline_normal;

// Distancia de salida del rayo de la esfera de radio r; -1.0 si no hay intersección delante.
float ray_sphere_exit(vec3 center, float r, vec3 ro, vec3 rd) {
    vec3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - r * r;
    float disc = b * b - c;
    if (disc <= 0.0) {
        return -1.0;
    }
    return -b + sqrt(disc);
}

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);

    // La altura de superficie sobre la cámara es constante para todo el quad: se evalúa aquí.
    vec3 cam_local = CAMERA_POSITION_WORLD - planet_center;
    v_cam_radius = length(cam_local);

    // Plano local de la línea de flotación: punto de superficie sobre la cámara + normal
    // Gerstner analítica (del MISMO punto invertido que la altura). El corte en pantalla lo
    // decide cada píxel contra este plano.
    vec3 up_dir = normalize(cam_local);
    vec3 surface_normal;
    v_cam_surface_radius = water_radius + gerstner_surface_height_normal(cam_local, water_time, surface_normal);
    v_waterline_point = planet_center + up_dir * v_cam_surface_radius;
    v_waterline_normal = normalize(surface_normal);
}

void fragment() {
    // Reconstrucción del punto de escena y del rayo en world-space.
    float depth_raw = texture(depth_texture, SCREEN_UV).x;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
    vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view_coords.xyz /= view_coords.w;
    float scene_distance = length(view_coords.xyz);

    vec3 ro = CAMERA_POSITION_WORLD;
    vec3 rd = normalize((INV_VIEW_MATRIX * vec4(normalize(view_coords.xyz), 0.0)).xyz);

    // Punto del near plane de este píxel (ndc z = 1 con reverse-z): el corte en pantalla lo
    // dicta la superficie real de las olas, píxel a píxel, no un flip de pantalla completa.
    vec4 near_view = INV_PROJECTION_MATRIX * vec4(ndc.xy, 1.0, 1.0);
    near_view.xyz /= near_view.w;
    vec3 p_near = (INV_VIEW_MATRIX * vec4(near_view.xyz, 1.0)).xyz;

    float waterline = waterline_signed(p_near, v_waterline_point, v_waterline_normal);

    // Franja radial que contiene toda la superficie posible: R ± amplitud total de las octavas.
    float band = wave_amplitude * 2.0 + 0.5;

    // Sellado del near-field: los píxeles que arrancan en aire no se descartan de inmediato.
    // Si el rayo entra en la superficie ANALÍTICA a menos de waterline_seal_distance, se niebla
    // desde ese punto de entrada; la malla del agua (lineal entre vértices, se comba mm-cm bajo
    // la superficie exacta) se dibuja encima. Así el corte al romper una ola contra la cámara lo
    // decide la misma superficie que el resto de la niebla, sin rendijas de cielo en la frontera.
    float t_enter = 0.0;
    if (waterline >= 0.0) {
        if (waterline >= waterline_seal_band) {
            discard; // aire franco, lejos del corte: lo pintan la superficie/escena normales
        }
        // La marcha nace en el near plane (donde se decidió que el píxel arranca en aire), no
        // en la cámara: en pleno cruce la cámara puede estar sumergida con media pantalla en aire.
        const int SEAL_STEPS = 6;
        float seal_step = waterline_seal_distance / float(SEAL_STEPS);
        float t_near = length(p_near - ro);
        float t_air = t_near;
        float t_wet = -1.0;
        for (int i = 1; i <= SEAL_STEPS; i++) {
            float ti = t_near + float(i) * seal_step;
            vec3 pl = ro + rd * ti - planet_center;
            if (length(pl) - (water_radius + gerstner_surface_height(pl, water_time)) < 0.0) {
                t_wet = ti;
                break;
            }
            t_air = ti;
        }
        if (t_wet < 0.0) {
            discard; // sin agua por delante en el near-field: píxel de aire normal
        }
        for (int i = 0; i < 5; i++) {
            float mid = 0.5 * (t_air + t_wet);
            vec3 pl = ro + rd * mid - planet_center;
            if (length(pl) - (water_radius + gerstner_surface_height(pl, water_time)) < 0.0) {
                t_wet = mid;
            } else {
                t_air = mid;
            }
        }
        t_enter = 0.5 * (t_air + t_wet);
        if (scene_distance <= t_enter) {
            discard; // la escena corta el rayo antes de llegar al agua: píxel de aire
        }
    }

    float t_lo = ray_sphere_exit(planet_center, water_radius - band, ro, rd);
    float t_hi = ray_sphere_exit(planet_center, water_radius + band, ro, rd);
    float lo = max(max(t_lo, 0.0), t_enter);
    float hi = max(t_hi, lo + 0.001);

    // Salida por la superficie: bisección de r(t) - (R + h_gerstner) dentro de la franja.
    // El bracket es válido siempre (f(lo) < 0 dentro del agua, f(hi) > 0 fuera) y es estable
    // también en rayos rasantes, donde un punto fijo sobre esferas diverge.
    float t_exit;
    if (scene_distance <= lo) {
        t_exit = scene_distance; // la escena corta antes de cualquier superficie posible
    } else {
        for (int i = 0; i < 8; i++) {
            float mid = 0.5 * (lo + hi);
            vec3 p_local = ro + rd * mid - planet_center;
            float f = length(p_local) - (water_radius + gerstner_surface_height(p_local, water_time));
            if (f < 0.0) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        t_exit = 0.5 * (lo + hi);
    }

    float water_path = max(min(t_exit, scene_distance) - t_enter, 0.0);

    // Fuga de atmósfera: la profundidad del near plane borraría la atmósfera (compositor POST_TRANSPARENT)
    // en todo el submarino. En su lugar se escribe la de un punto sobre el rayo cuya distancia decae con
    // la columna de agua hasta la superficie: velo pleno mirando arriba a ras de superficie, apagado hacia
    // el fondo — la misma atenuación exp del corte que vivía en el compute. Se acota por delante de la
    // escena para que la niebla no pierda el test de profundidad contra la geometría cercana.
    float leak_t = atmosphere_leak_distance * exp(-atmosphere_leak_falloff * water_path);
    leak_t = clamp(leak_t, 0.01, scene_distance * 0.995);
    if (t_enter > 0.0) {
        // Píxel de aire sellado: se escribe la profundidad del punto de entrada al agua,
        // la misma que escribiría la malla de la superficie en ese píxel.
        leak_t = min(t_enter, scene_distance * 0.995);
    }
    vec4 leak_clip = PROJECTION_MATRIX * vec4(normalize(view_coords.xyz) * leak_t, 1.0);
    DEPTH = clamp(leak_clip.z / leak_clip.w, 0.0, 1.0);

    float water_column = water_path * fog_density;

    // L = escena * T + scatter * (1 - T), con transmitancia Beer-Lambert por canal RGB.
    vec3 transmission = exp(-absorption_coefficients * water_column);
    float cam_depth = v_cam_surface_radius - v_cam_radius;

    // La luz llega de arriba: el scatter mirando hacia la superficie es el de aguas menos
    // profundas (más claro) y mirando al fondo el de aguas más profundas (más oscuro).
    // Además se oscurece con la distancia: cuanta más columna de agua acumula el rayo, más
    // profundo es el tramo al que converge la niebla (el horizonte sumergido cae a deep/abyss).
    vec3 up = normalize(ro - planet_center);
    float up_amount = dot(rd, up) * 0.5 + 0.5;
    float scatter_depth = cam_depth
        + mix(scatter_vertical_range, -scatter_vertical_range * 0.5, up_amount)
        + min(water_column * distance_depth_gain, distance_depth_max);
    vec3 scatter_color = depth_tier_color(max(scatter_depth, 0.0));

    // In-scatter direccional barato: halo hacia el sol. Ojo al convenio: sun_controller
    // propaga sun_dir apuntando HACIA el sol (posición de la luz normalizada), al contrario
    // que el water_shader, que lo niega. Fallback si aún no ha llegado (frame inicial = 0).
    vec3 to_sun = dot(sun_direction, sun_direction) > 1e-6
        ? normalize(sun_direction)
        : vec3(0.37, 0.65, 0.66);
    float sun_glow = pow(max(dot(rd, to_sun), 0.0), sun_glow_power);
    vec3 lit_scatter = scatter_color * (1.0 + sun_glow * sun_glow_intensity);

    vec3 screen = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;

    // Normal del fondo por derivadas, FUERA de la rama (dFdx no está definido en control de
    // flujo no uniforme) y con guardia contra normalize(0) en los bordes de profundidad.
    vec3 scene_world = ro + rd * scene_distance;
    vec3 bg_dx = dFdx(scene_world);
    vec3 bg_dy = dFdy(scene_world);
    vec3 bg_cross = cross(bg_dy, bg_dx);
    float bg_cross_len = length(bg_cross);

    // Cáusticas sobre la escena sumergida: réplica del triplanar de water_shader. Se añaden
    // al color de escena antes de la niebla, así la transmisión las apaga con la distancia.
    if (scene_distance <= t_exit) {
        vec3 scene_local = scene_world - planet_center;
        float scene_depth = max(
            water_radius + gerstner_surface_height(scene_local, water_time) - length(scene_local),
            0.0
        );
        vec3 bg_normal = bg_cross_len > 1e-6 ? bg_cross / bg_cross_len : normalize(scene_local);

        vec3 tri_weights = abs(bg_normal);
        tri_weights = pow(tri_weights, vec3(4.0));
        tri_weights /= (tri_weights.x + tri_weights.y + tri_weights.z + 1e-5);

        vec3 cp = scene_world * caustics_scale;
        vec2 scroll1 = vec2(TIME * caustics_speed, 0.0);
        vec2 scroll2 = vec2(0.0, -TIME * caustics_speed * 0.8);

        float c_xz = texture(caustics_texture, cp.xz + scroll1).r
                   * texture(caustics_texture, cp.xz * 0.7 + scroll2).r;
        float c_xy = texture(caustics_texture, cp.xy + scroll1).r
                   * texture(caustics_texture, cp.xy * 0.7 + scroll2).r;
        float c_yz = texture(caustics_texture, cp.yz + scroll1).r
                   * texture(caustics_texture, cp.yz * 0.7 + scroll2).r;

        float caustics_value = c_xz * tri_weights.y
                             + c_xy * tri_weights.z
                             + c_yz * tri_weights.x;

        float caustics_fade = smoothstep(0.0, caustics_near_fade, scene_depth)
                            * (1.0 - clamp(scene_depth * caustics_depth_fade, 0.0, 1.0));
        float caustics_contrib = caustics_value * caustics_intensity * caustics_fade;

        // Screen blend, como en water_shader: añade luz sin quemar el color existente.
        screen = screen + caustics_contrib - screen * caustics_contrib;
    }

    // Reflexión interna total: más allá del ángulo crítico (n = 1.333, cos ≈ 0.661) la cara
    // inferior de la superficie es un espejo del agua profunda, no una ventana al cielo.
    // El fundido ancho evita un borde duro en el anillo de Snell.
    if (t_exit < scene_distance) {
        vec3 exit_local = ro + rd * t_exit - planet_center;
        vec3 surf_normal;
        gerstner_surface(exit_local, normalize(exit_local), water_time, surf_normal);
        float cos_incidence = dot(rd, normalize(surf_normal));
        float tir = 1.0 - smoothstep(0.55, 0.72, cos_incidence);
        vec3 tir_color = depth_tier_color(cam_depth + tir_reflection_depth);
        screen = mix(screen, tir_color, tir);
    }

    ALBEDO = screen * transmission + lit_scatter * (1.0 - transmission);

    // Godrays: en cada muestra del segmento de agua se proyecta hasta la superficie siguiendo
    // el sol REFRACTADO (Snell: los haces se inclinan hacia la vertical) y se muestrea el
    // patrón de cáusticas en un marco tangente estable ⊥ sol. La atenuación por canal de los
    // trayectos sol→muestra y muestra→cámara les da el tinte y el apagado con la profundidad.
    float sun_up_amount = dot(up, to_sun);
    float day = smoothstep(0.02, 0.25, sun_up_amount);
    if (godray_intensity > 0.001 && day > 0.001) {
        vec3 refr = refract(-to_sun, up, 0.7501875); // eta = 1 / 1.333
        vec3 sun_w = length(refr) > 1e-4 ? -normalize(refr) : to_sun;

        vec3 gr_tan = normalize(cross(abs(sun_w.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0), sun_w));
        vec3 gr_bitan = cross(sun_w, gr_tan);

        float march_end = min(min(t_exit, scene_distance), t_enter + godray_max_distance);
        float step_len = max(march_end - t_enter, 0.0) / float(godray_samples);
        float jitter = fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233))) * 43758.5453);

        vec3 accum = vec3(0.0);
        for (int i = 0; i < 24; i++) {
            if (i >= godray_samples) {
                break;
            }
            float t = t_enter + (float(i) + jitter) * step_len;
            vec3 sample_pos = ro + rd * t;
            float light_path = ray_sphere_exit(planet_center, water_radius, sample_pos, sun_w);
            if (light_path < 0.0) {
                continue;
            }
            vec3 entry_local = sample_pos + sun_w * light_path - planet_center;
            vec2 suv = vec2(dot(entry_local, gr_tan), dot(entry_local, gr_bitan)) * godray_pattern_scale;
            float m1 = texture(caustics_texture, suv + TIME * godray_pattern_speed).r;
            float m2 = texture(caustics_texture, suv * 0.53 - TIME * godray_pattern_speed * 0.7).r;
            // ×2.5 compensa la energía del producto de dos capas (media ≈ 0.25) antes del pow.
            float shaft_mask = pow(clamp(m1 * m2 * 2.5, 0.0, 1.0), godray_sharpness);

            vec3 light_atten = exp(-absorption_coefficients * light_path);
            vec3 view_atten = exp(-absorption_coefficients * (t - t_enter));
            accum += shaft_mask * light_atten * view_atten;
        }
        accum /= float(godray_samples);

        float phase = mix(godray_min_phase, 1.0, pow(max(dot(rd, sun_w), 0.0), godray_phase_power));
        ALBEDO += accum * godray_intensity * phase * day;
    }

    // Menisco: línea brillante fina a ambos lados de la línea de flotación (con el sellado
    // near-field también se renderizan píxeles de aire, así que se mide con abs).
    float meniscus = 1.0 - smoothstep(0.0, meniscus_width, abs(waterline));
    ALBEDO += fog_color.rgb * meniscus * meniscus_strength;

    ALPHA = 1.0;
}
