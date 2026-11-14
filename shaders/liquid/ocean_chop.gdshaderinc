// Mar de viento: la banda corta del oleaje (de unos 14 m a diez centímetros) que la malla no puede llevar
// —sus vértices van cada metro cerca y cada decenas lejos— y que es lo que hace que una ola grande
// parezca agua y no una duna lisa. Son ondas planas de verdad: viajan con su velocidad de fase, con
// la cresta afilada y el seno tendido. Solo dan pendiente a la normal, no desplazan.
//
// Las direcciones, los números de onda y las fases los pone OceanChop (CPU): con el planeta de 30 km
// y horas de partida, k·posición y omega·tiempo no caben en un float y la ola pequeña iba a saltos.
// La CPU resuelve en doble precisión la fase en chop_anchor (la cámara) y aquí solo se suma el tramo
// corto hasta el píxel.
const int CHOP_MODES = 16;
// xyz = dirección fija en el marco del planeta, w = número de onda (0 = sin ola).
uniform vec4 chop_waves[CHOP_MODES];
// x = fase en chop_anchor (rad), y = pendiente máxima de la ola.
uniform vec4 chop_state[CHOP_MODES];
uniform vec3 chop_anchor = vec3(0.0);
uniform float chop_strength : hint_range(0.0, 3.0) = 1.0;
// Cuánto se afila la cresta (segundo armónico). 0 = senoide.
uniform float chop_sharpness : hint_range(0.0, 0.45) = 0.3;

// Gradiente de altura del mar de viento en 'p' (posición en reposo, relativa al centro del
// planeta). 'hidden' recibe la varianza de pendiente de las ondas que el píxel ya no resuelve.
vec3 ocean_chop(vec3 p, vec3 radial, vec3 dpx, vec3 dpy, float scale, out float hidden) {
    // Crestas dobladas (ocean_ripple_warp) y cortas (ocean_short_crest): sin eso una docena de
    // ondas planas se cruzan en una malla de rombos perfectamente regular.
    vec3 warp = ocean_ripple_warp(p);
    vec3 rel = p - chop_anchor + warp;
    vec3 slope = vec3(0.0);
    float major = max(length(dpx), length(dpy));
    hidden = 0.0;
    for (int i = 0; i < CHOP_MODES; i++) {
        float k = chop_waves[i].w;
        if (k <= 0.0) {
            continue;
        }
        vec3 dir = chop_waves[i].xyz;
        float steep = chop_state[i].y * scale;
        vec3 tangent_dir = dir - radial * dot(dir, radial);
        // Píxeles por longitud de onda, medidos a lo largo de la ola (ver ocean_breaker_history).
        float pixel = 1.0 - smoothstep(0.22, 0.45,
            max(max(abs(dot(dpx, dir)), abs(dot(dpy, dir))), major * 0.75) * k / 6.28318530718);
        hidden += steep * steep * 0.5 * dot(tangent_dir, tangent_dir) * (1.0 - pixel * pixel);
        if (pixel <= 0.001) {
            continue;
        }
        float packet = ocean_short_crest(p, dir, k, i);
        float phase = k * dot(rel, dir) + chop_state[i].x;
        float s = sin(phase);
        slope += tangent_dir * (steep * packet * pixel * cos(phase) * (1.0 + 4.0 * chop_sharpness * s));
    }
    return slope;
}
