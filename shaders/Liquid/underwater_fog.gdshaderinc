// Niebla submarina compartida: la paleta de in-scatter por tramos de profundidad, el corte de la
// línea de flotación y el núcleo de la composición (absorción + in-scatter). Tres consumidores:
// underwater.gdshader (el quad de pantalla completa, que compone la escena opaca sumergida),
// water_shader.gdshader (solo el corte de flotación, para descartar su mitad sumergida) y
// glass_block.gdshader (los paneles traslúcidos, que se nieblan solos porque el quad se descarta
// entero con la cámara en un compartimento seco y la pasada transparente no recibe su niebla).

uniform vec4 fog_color : source_color = vec4(0.7, 0.8, 0.9, 1.0);
uniform vec4 deep_fog_color : source_color = vec4(0.1, 0.2, 0.3, 1.0);
uniform vec4 abyss_fog_color : source_color = vec4(0.1, 0.1, 0.15, 1.0);
uniform float deep_transition_depth = 100.0;
uniform float abyss_transition_depth = 250.0;

// Distancia con signo del punto del near plane a la línea de flotación: el plano local de la
// superficie sobre la cámara (a escala del near plane, ~10 cm, la ola es un plano).
// < 0 = ese píxel arranca bajo el agua. La usan water_shader (descarta su mitad sumergida)
// y underwater (descarta su mitad emergida): mismo test, mismos argumentos → partición
// píxel-exacta de la pantalla, sin rizados artificiales que desalineen el corte.
float waterline_signed(vec3 p_near_world, vec3 surface_point, vec3 surface_normal) {
    return dot(p_near_world - surface_point, surface_normal);
}

// Color de in-scatter según la profundidad (fog → deep → abyss).
vec3 depth_tier_color(float depth_meters) {
    if (depth_meters <= deep_transition_depth) {
        float t = clamp(depth_meters / deep_transition_depth, 0.0, 1.0);
        return mix(fog_color.rgb, deep_fog_color.rgb, t);
    } else if (depth_meters <= abyss_transition_depth) {
        float t = clamp((depth_meters - deep_transition_depth) / (abyss_transition_depth - deep_transition_depth), 0.0, 1.0);
        return mix(deep_fog_color.rgb, abyss_fog_color.rgb, t);
    }
    return abyss_fog_color.rgb;
}

// Distancia de salida del rayo de la esfera de radio r; -1.0 si no hay intersección delante.
// Vive aquí y no en underwater.gdshader porque la necesitan también las superficies transparentes
// que se nieblan solas (bloques de cristal sumergidos).
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

// Núcleo de la niebla submarina: absorción Beer-Lambert por canal más in-scatter. `column` son
// metros de agua atravesados y `scatter` el color de in-scatter ya iluminado. Lo comparten el quad
// de pantalla completa y cualquier superficie transparente que tenga que nieblar lo que se ve a
// través de ella, que el quad no cubre (ver cabecera).
vec3 underwater_apply(vec3 background, vec3 absorption, float column, vec3 scatter) {
    vec3 transmission = exp(-absorption * column);
    return background * transmission + scatter * (1.0 - transmission);
}

// Profundidad equivalente a la que converge el in-scatter de un rayo: la del observador, aclarada
// si mira hacia la superficie (up_amount = dot(rd, up) * 0.5 + 0.5) y hundida con la columna que
// el rayo acumula, porque el horizonte sumergido cae a deep/abyss.
float underwater_scatter_depth(float viewer_depth, float up_amount, float column,
        float vertical_range, float distance_gain, float distance_max) {
    return max(viewer_depth
        + mix(vertical_range, -vertical_range * 0.5, up_amount)
        + min(column * distance_gain, distance_max), 0.0);
}

// Cuánto espeja la cara inferior de la superficie para un rayo que la va a cruzar: 0 dentro de la
// ventana de Snell (el rayo escapa y se ve el cielo), 1 pasado el ángulo crítico (n = 1.333,
// cos ≈ 0.661), donde lo que se ve es agua profunda reflejada. El fundido ancho evita un borde
// duro en el anillo de Snell. `surface_normal` apunta hacia fuera del agua.
float underwater_tir_amount(vec3 rd, vec3 surface_normal) {
    return 1.0 - smoothstep(0.55, 0.72, dot(rd, surface_normal));
}
