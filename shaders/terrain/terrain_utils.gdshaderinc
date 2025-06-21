// utils.gdshaderinc
// Función para obtener el factor secundario de transvoxel
float get_transvoxel_secondary_factor(int idata, int transition_mask) {
    int cell_border_mask = idata & 63;
    int vertex_border_mask = (idata >> 8) & 63;
    int m = transition_mask & cell_border_mask;
    float t = float(m != 0);
    t *= float((vertex_border_mask & ~transition_mask) == 0);
    return t;
}

// Función para obtener la posición transvoxel
vec3 get_transvoxel_position(vec3 vertex_pos, vec4 fdata, int transition_mask) {
    int idata = floatBitsToInt(fdata.a);
    float secondary_factor = get_transvoxel_secondary_factor(idata, transition_mask);
    vec3 secondary_position = fdata.xyz;
    vec3 pos = mix(vertex_pos, secondary_position, secondary_factor);
    int itransition = (idata >> 16) & 0xff;
    float transition_cull = float(itransition == 0 || (itransition & transition_mask) != 0);
    pos *= transition_cull;
    return pos;
}

// Función de hash
float hash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Función de ruido procedural
float noise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f); // Interpolación suave
    return mix(
        mix(
            mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
            mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x),
            f.y
        ),
        mix(
            mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
            mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x),
            f.y
        ),
        f.z
    );
}

// Función para muestrear texturas con mapeo triplanar
vec3 triplanar_sample(sampler2D tex, vec3 pos, vec3 normal, float scale) {
    vec2 uv_x = pos.yz * scale;
    vec2 uv_y = pos.xz * scale;
    vec2 uv_z = pos.xy * scale;
    vec3 col_x = texture(tex, uv_x).rgb;
    vec3 col_y = texture(tex, uv_y).rgb;
    vec3 col_z = texture(tex, uv_z).rgb;
    vec3 blend = pow(abs(normal), vec3(2.0)); // Aumentar contraste en la mezcla
    blend = normalize(max(blend, 0.0001));
    blend /= (blend.x + blend.y + blend.z);
    return col_x * blend.x + col_y * blend.y + col_z * blend.z;
}

// Convierte el normal map en un vector de normales en espacio tangente
vec3 unpack_normal(vec3 n) {
    return normalize(n * 2.0 - 1.0);
}

// Función triplanar para normal maps con rotación a espacio mundial
vec3 triplanar_normal_sample(sampler2D tex, vec3 pos, vec3 normal, float scale) {
    // UVs para cada plano
    vec2 uv_x = pos.yz * scale;
    vec2 uv_y = pos.xz * scale;
    vec2 uv_z = pos.xy * scale;

    // Samplear los normal maps en espacio tangente
    vec3 n_x = unpack_normal(texture(tex, uv_x).rgb);
    vec3 n_y = unpack_normal(texture(tex, uv_y).rgb);
    vec3 n_z = unpack_normal(texture(tex, uv_z).rgb);

    // Construir TBN para cada eje
    mat3 tbn_x = mat3(
        vec3(0.0, 0.0, 1.0),  // T
        vec3(0.0, 1.0, 0.0),  // B
        vec3(1.0, 0.0, 0.0)   // N
    );

    mat3 tbn_y = mat3(
        vec3(1.0, 0.0, 0.0),  // T
        vec3(0.0, 0.0, 1.0),  // B
        vec3(0.0, 1.0, 0.0)   // N
    );

    mat3 tbn_z = mat3(
        vec3(1.0, 0.0, 0.0),  // T
        vec3(0.0, 1.0, 0.0),  // B
        vec3(0.0, 0.0, 1.0)   // N
    );

    // Transformar cada normal de tangente a espacio mundial local
    vec3 world_n_x = normalize(tbn_x * n_x);
    vec3 world_n_y = normalize(tbn_y * n_y);
    vec3 world_n_z = normalize(tbn_z * n_z);

    // Calcular pesos de mezcla según la normal original
    vec3 blend = pow(abs(normal), vec3(4.0)); // exponente más alto = mezcla más precisa
    blend = blend / (blend.x + blend.y + blend.z);

    // Mezclar las normales transformadas
    vec3 blended = world_n_x * blend.x + world_n_y * blend.y + world_n_z * blend.z;
    return normalize(blended);
}

// Función para muestrear roughness maps con mapeo triplanar (escala de grises)
float triplanar_roughness_sample(sampler2D tex, vec3 pos, vec3 normal, float scale) {
    vec2 uv_x = pos.yz * scale;
    vec2 uv_y = pos.xz * scale;
    vec2 uv_z = pos.xy * scale;
    float rough_x = texture(tex, uv_x).r;
    float rough_y = texture(tex, uv_y).r;
    float rough_z = texture(tex, uv_z).r;
    vec3 blend = abs(normal);
    blend = normalize(max(blend, 0.0001));
    blend /= (blend.x + blend.y + blend.z);
    return rough_x * blend.x + rough_y * blend.y + rough_z * blend.z;
}