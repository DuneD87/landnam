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
// inside_ship_interior(): OBB de cascos de barcos, interior seco sin niebla submarina.
#include "res://shaders/liquid/ship_interiors.gdshaderinc"

uniform vec3 planet_center;
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
uniform float meniscus_width = 0.25;    // longitud de columna de agua (m) por debajo de la cual el rayo cuenta como silueta de la ola
uniform float meniscus_strength = 0.3;  // brillo añadido en la línea de flotación
uniform float waterline_seal_distance = 3.0; // near-field: un rayo en aire que entra en el agua analítica a menos de N m se niebla desde la entrada (sella los huecos malla-analítica al romper una ola contra la cámara)
uniform float waterline_seal_band = 0.06;    // solo se sella la banda a menos de N m sobre la línea de flotación (near plane); más arriba manda la malla. Ensanchar esto NO ondula el corte: la niebla se dibuja ANTES que el agua, así que pasa a ser el fondo contra el que mezcla surface_alpha y se come la superficie vista desde fuera
uniform float waterline_seal_depth_bias = 0.0; // metros POR DEBAJO de la superficie a los que un píxel sellado escribe su profundidad; 0 = justo en la entrada, como escribiría la malla
uniform float surface_search_distance = 80.0; // alcance de la búsqueda de la superficie de salida; más allá la absorción ya satura, así que se da por columna infinita
uniform float underside_refraction : hint_range(0.0, 8.0) = 1.5; // distorsión de lo que se ve a través de la superficie según la normal Gerstner del punto de salida (relieve de las olas vistas desde abajo)
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

// Modo debug: sustituye el color final por la magnitud que se quiera inspeccionar.
// 0 = off | 1 = clasificación de píxel | 2 = columna de agua | 3 = normal del techo | 4 = búsqueda de salida
uniform int debug_mode : hint_range(0, 4) = 0;
uniform float debug_scale = 20.0; // metros que saturan las vistas 2 y 4

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

varying float v_cam_radius;
varying float v_cam_surface_radius;
// Ver la cabecera de waterline_point en water_shader.gdshader: lo empuja OceanSystem a los dos.
uniform vec3 waterline_point;
uniform vec3 waterline_normal;

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);

    // La altura de superficie sobre la cámara es constante para todo el quad: se evalúa aquí.
    vec3 cam_local = CAMERA_POSITION_WORLD - planet_center;
    v_cam_radius = length(cam_local);

    // El plano de la línea de flotación ya no se calcula aquí: viene por uniform, el MISMO que
    // recibe water_shader (ver waterline_point). Así los dos cortan por idéntico sitio por
    // construcción, en vez de por que dos cuentas independientes coincidan.
    v_cam_surface_radius = length(waterline_point - planet_center);
}

void fragment() {
    // Cámara dentro de un casco: interior seco — sin niebla, menisco ni corte de flotación,
    // aunque el interior quede analíticamente bajo la superficie Gerstner.
    if (inside_ship_interior(CAMERA_POSITION_WORLD)) {
        discard;
    }

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

    float waterline = waterline_signed(p_near, waterline_point, waterline_normal);

    // Franja radial conservadora para los grupos solapados y la familia costera.
    float band = max(wave_amplitude,wave_calm_amplitude)*5.2
        + min(shore_amplitude*shore_shoal_max,shore_length*0.08)*1.5 + 0.5;

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
    // El bracket geométrico llega a ~500 m en rayos rasantes: 8 bisecciones daban 2 m de
    // resolución (más que la amplitud de la ola) y convergían a UNA raíz cualquiera de las
    // muchas que cruza el rayo, no a la primera — el techo de agua salía liso. Se acota la
    // búsqueda a surface_search_distance: más allá la absorción ya satura y el punto exacto
    // de salida no se ve, así que basta con declarar la columna "infinita".
    float hi = min(max(t_hi, lo + 0.001), lo + surface_search_distance);

    // Salida por la superficie: bisección de r(t) - (R + h_gerstner) dentro de la franja.
    // f(lo) < 0 (dentro del agua) siempre; f(hi) solo es > 0 si el rayo sale de verdad dentro
    // del alcance, así que se comprueba antes de bisecar. Estable también en rayos rasantes,
    // donde un punto fijo sobre esferas diverge.
    float t_exit;
    bool exit_found = true;
    if (scene_distance <= lo) {
        t_exit = scene_distance; // la escena corta antes de cualquier superficie posible
        exit_found = false;
    } else {
        vec3 hi_local = ro + rd * hi - planet_center;
        if (length(hi_local) - (water_radius + gerstner_surface_height(hi_local, water_time)) < 0.0) {
            t_exit = hi; // sigue bajo el agua al final del alcance: columna saturada
            exit_found = false;
        } else {
            for (int i = 0; i < 10; i++) {
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
        // Píxel de aire sellado: la profundidad se escribe unos cm POR DEBAJO del punto de
        // entrada al agua. Escribirla justo en la superficie empata con la malla del agua (que
        // se comba mm-cm bajo la superficie exacta) y la niebla acaba tapándola vista desde
        // fuera. El sesgo vertical se convierte a longitud de rayo con el coseno de incidencia,
        // acotado para que un rayo rasante no lo dispare.
        float bias_cos = max(abs(dot(rd, normalize(ro + rd * t_enter - planet_center))), 0.05);
        leak_t = min(t_enter + waterline_seal_depth_bias / bias_cos, scene_distance * 0.995);
    }
    vec4 leak_clip = PROJECTION_MATRIX * vec4(normalize(view_coords.xyz) * leak_t, 1.0);
    DEPTH = clamp(leak_clip.z / leak_clip.w, 0.0, 1.0);

    float water_column = water_path * fog_density;

    float cam_depth = v_cam_surface_radius - v_cam_radius;

    // La luz llega de arriba: el scatter mirando hacia la superficie es el de aguas menos
    // profundas (más claro) y mirando al fondo el de aguas más profundas (más oscuro).
    // Además se oscurece con la distancia: cuanta más columna de agua acumula el rayo, más
    // profundo es el tramo al que converge la niebla (el horizonte sumergido cae a deep/abyss).
    vec3 up = normalize(ro - planet_center);
    float up_amount = dot(rd, up) * 0.5 + 0.5;
    vec3 scatter_color = depth_tier_color(underwater_scatter_depth(cam_depth, up_amount,
        water_column, scatter_vertical_range, distance_depth_gain, distance_depth_max));

    // In-scatter direccional barato: halo hacia el sol. Ojo al convenio: sun_controller
    // propaga sun_dir apuntando HACIA el sol (posición de la luz normalizada), al contrario
    // que el water_shader, que lo niega. Fallback si aún no ha llegado (frame inicial = 0).
    vec3 to_sun = dot(sun_direction, sun_direction) > 1e-6
        ? normalize(sun_direction)
        : vec3(0.37, 0.65, 0.66);
    float sun_glow = pow(max(dot(rd, to_sun), 0.0), sun_glow_power);
    vec3 lit_scatter = scatter_color * (1.0 + sun_glow * sun_glow_intensity);

    // Normal Gerstner del punto de salida. Bajo el agua la malla se descarta entera (water_shader
    // corta por línea de flotación), así que el techo de agua lo pinta solo este quad: sin usar la
    // normal, lo único que variaba con la ola era la longitud de columna y la superficie leía como
    // una ventana lisa. Se calcula una vez y sirve para la refracción y para el espejo TIR.
    // Refracción del otro lado de la superficie: la desviación normal-radial proyectada a pantalla
    // ondula lo que se ve a través (cielo, sol, ventana de Snell) siguiendo la forma de la ola.
    bool surface_ahead = exit_found && t_exit < scene_distance;
    vec3 exit_normal = up;
    vec2 refracted_uv = SCREEN_UV;
    if (surface_ahead) {
        vec3 exit_local = ro + rd * t_exit - planet_center;
        vec3 exit_radial = normalize(exit_local);
        vec3 n_exit;
        gerstner_surface(exit_local, exit_radial, water_time, n_exit);
        exit_normal = normalize(n_exit);

        vec4 dev_clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(exit_normal - exit_radial, 0.0);
        refracted_uv = clamp(SCREEN_UV + dev_clip.xy * underside_refraction * 0.05,
                             vec2(0.002), vec2(0.998));
    }
    vec3 screen = textureLod(screen_texture, refracted_uv, 0.0).rgb;

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
    if (surface_ahead) {
        float tir = underwater_tir_amount(rd, exit_normal);
        vec3 tir_color = depth_tier_color(cam_depth + tir_reflection_depth);
        screen = mix(screen, tir_color, tir);
    }

    // L = escena * T + scatter * (1 - T), con transmitancia Beer-Lambert por canal RGB.
    ALBEDO = underwater_apply(screen, absorption_coefficients, water_column, lit_scatter);

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

    // Menisco: borde brillante donde el rayo apenas atraviesa agua, o sea la silueta real de la
    // ola contra el aire. Antes se medía contra el PLANO de la línea de flotación y pintaba una
    // recta cruzando la pantalla por mucho oleaje que hubiera delante.
    float meniscus = surface_ahead ? 1.0 - smoothstep(0.0, meniscus_width, water_path) : 0.0;
    ALBEDO += fog_color.rgb * meniscus * meniscus_strength;

    // Vistas de depuración: cualquier cosa que no sea negro aquí es un píxel que ESTE quad pinta.
    // 1: rojo = sellado desde aire (t_enter > 0) | verde = arranca sumergido | azul = hay superficie
    //    de salida por delante. Sirve para ver dónde se come el quad la vista de fuera.
    // 2: columna de agua del rayo en escala de grises (satura a debug_scale m).
    // 3: normal Gerstner del punto de salida — el relieve del techo de agua; gris plano = liso.
    // 4: verde = salida encontrada (brillo = distancia) | rojo = columna saturada sin salida.
    if (debug_mode == 1) {
        ALBEDO = vec3(t_enter > 0.0 ? 1.0 : 0.0, waterline < 0.0 ? 1.0 : 0.0, surface_ahead ? 1.0 : 0.0);
    } else if (debug_mode == 2) {
        ALBEDO = vec3(clamp(water_path / max(debug_scale, 0.001), 0.0, 1.0));
    } else if (debug_mode == 3) {
        ALBEDO = surface_ahead ? exit_normal * 0.5 + 0.5 : vec3(0.0);
    } else if (debug_mode == 4) {
        ALBEDO = exit_found
            ? vec3(0.0, clamp(t_exit / max(debug_scale, 0.001), 0.0, 1.0), 0.0)
            : vec3(1.0, 0.0, 0.0);
    }

    ALPHA = 1.0;
}
