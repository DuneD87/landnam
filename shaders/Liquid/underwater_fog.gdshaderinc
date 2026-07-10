// Paleta de niebla submarina compartida: color de in-scatter por tramos según la profundidad
// de la cámara. La incluyen underwater.gdshader (quad de pantalla completa sobre la escena
// opaca) y water_shader.gdshader (la superficie vista desde abajo se niebla a sí misma,
// porque el quad de niebla no cubre la pasada transparente).

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
