// Sendas de lejos (scripts/world/trail_field.gd): la distancia al eje de la senda más cercana, leída
// por píxel del campo de las sendas como la lee el grafo (TrailField.distance_at). Más allá de lo que
// resuelve la malla, planet_biomes.gdshader dibuja la senda con ella. Las imágenes son el juego de
// los árboles (4096×2048) en un Texture2DArray: U, V y D de cada capa seguidas (Planet las sube).

uniform sampler2DArray trail_far_images : filter_linear, repeat_enable;
// Capas de sendas en trail_far_images (0 = sin sendas de lejos).
uniform int trail_far_layers = 0;
uniform vec2 trail_far_size = vec2(4096.0, 2048.0);
// rb (alcance de U y V), dmax (de D), g0 y g1 (la compuerta) del juego (TrailField.params).
uniform vec4 trail_far_params = vec4(133.0, 133.0, 39.8, 50.9);

// UV de textura para la dirección unitaria [up]: u como el nodo SdfSphereHeightmap, v con
// RiverField.node_v. El nodo lee el téxel x en u = x / ancho, de ahí el medio téxel.
vec2 trail_far_uv(vec3 up) {
    float u = fract(0.5 - atan(up.z, up.x) / TAU);
    float v = 0.5 - (up.y + up.y * up.y * up.y) * 0.25;
    return (vec2(u, v) * trail_far_size + 0.5) / trail_far_size;
}

// Metros de [up] al eje de la senda más cercana, o 1000 lejos de todas: por capa, |(U, V)| donde la
// compuerta D abre, más 1000 m donde cierra.
float trail_far_axis(vec3 up) {
    vec2 uv = trail_far_uv(up);
    float best = 1000.0;
    for (int k = 0; k < trail_far_layers; k++) {
        float d = trail_far_params.y * (1.0 - textureLod(trail_far_images, vec3(uv, float(k * 3 + 2)), 0.0).r);
        if (d >= trail_far_params.w) {
            continue;
        }
        vec2 c = vec2(textureLod(trail_far_images, vec3(uv, float(k * 3)), 0.0).r,
            textureLod(trail_far_images, vec3(uv, float(k * 3 + 1)), 0.0).r);
        float gate = smoothstep(trail_far_params.w, trail_far_params.z, d);
        best = min(best, length(trail_far_params.x * (2.0 * c - 1.0)) + (1.0 - gate) * 1000.0);
    }
    return best;
}
