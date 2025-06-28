shader_type spatial;
render_mode cull_back, unshaded;

uniform float wind_strength = 0.2;
uniform float wind_speed = 1.0;
uniform float wind_scale = 1.0;
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.0); // Dirección del viento

uniform float stiffness = 0.3; // 0.0 = muy flexible, 1.0 = rígido

void vertex() {
    // Factor basado en la altura del vértice (Y), para que solo las puntas se muevan
    float weight = clamp(1.0 - (VERTEX.y * stiffness), 0.0, 1.0);

    // Oscilación por viento: usa tiempo y posición para animación
    float t = TIME * wind_speed;
    float wind_wave = sin((VERTEX.x + VERTEX.z) * wind_scale + t);

    // Aplica desplazamiento en la dirección del viento
    vec3 offset = wind_direction * wind_wave * wind_strength * weight;

    VERTEX += offset;
}
