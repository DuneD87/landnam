shader_type spatial;
render_mode cull_disabled;

// Pez de un pack horneado sin esqueleto (tools/fauna/bake_static_mesh.gd): nada ondulando el
// cuerpo de lado a lado, cada vez más hacia la cola, con la onda corriendo de la cabeza a la cola.
// La cabeza va hacia -Z: de head_z a tail_z (instancia, de la caja de la malla).

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 0.45;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

instance uniform float head_z = -0.3;
instance uniform float tail_z = 0.3;
// Lo que se aparta la cola, en fracción del largo.
instance uniform float sway = 0.08;
instance uniform float swim_phase = 0.0;
// Rad/s del coletazo.
instance uniform float swim_frequency = 12.0;
instance uniform vec4 tint : source_color = vec4(1.0);

// Cuántas veces cabe la onda en el cuerpo (rad de cabeza a cola).
const float WAVE = 4.0;

void vertex() {
    float body = max(tail_z - head_z, 0.001);
    float t = clamp((VERTEX.z - head_z) / body, 0.0, 1.0);
    float phase = TIME * swim_frequency + swim_phase;
    float envelope = 0.15 + t * t;
    float wave = sin(phase - t * WAVE);
    VERTEX.x += wave * sway * body * envelope;
    // La normal sigue a la curva: la pendiente de lo que se aparta a lo largo del cuerpo.
    float slope = sway * (-WAVE * cos(phase - t * WAVE) * envelope + wave * 2.0 * t);
    NORMAL = normalize(vec3(NORMAL.x, NORMAL.y, NORMAL.z - NORMAL.x * slope));
}

void fragment() {
    ALBEDO = texture(albedo_texture, UV).rgb * tint.rgb;
    ROUGHNESS = roughness;
    SPECULAR = specular;
}
