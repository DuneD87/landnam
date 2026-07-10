// Olas Gerstner planetarias compartidas: la superficie (water_shader.gdshader) y la niebla
// submarina (underwater.gdshader) incluyen este archivo, así que evalúan exactamente la misma
// superficie con los mismos uniforms. WaterHeightSampler.gd es la réplica CPU para física;
// cualquier cambio aquí debe reflejarse allí.

uniform vec2 wave_direction = vec2(2.0, 0.0);
uniform float wave_speed = 1.5;
uniform float wave_amplitude = 4.0;

// Oleaje Gerstner (trocoidal): olas grandes con crestas afiladas.
uniform float wave_base_length : hint_range(2.0, 500.0, 0.5) = 60.0; // longitud de onda de la ola principal (m)
uniform float wave_steepness : hint_range(0.0, 1.0, 0.01) = 0.5;     // Q: 0 = senoidal suave, 1 = cresta pinchada
uniform int wave_octaves : hint_range(1, 6) = 4;
uniform vec3 wave_pole = vec3(0.0, 1.0, 0.0); // eje de referencia del marco de olas (las olas viajan en su plano ecuatorial)

const int WAVE_MAX = 6;

// Suma de olas de Gerstner planetarias. La fase se deriva de la posición proyectada sobre
// direcciones de viaje FIJAS en world-space (marco ecuatorial de wave_pole); así varía a lo
// largo de la superficie (proyectar sobre el plano tangente local la anulaba: dot(radial,tan)=0).
// Devuelve el desplazamiento world-space y, por out_normal, la normal analítica. out_crest es la
// señal de cresta/pliegue en ~[0,1]: pica donde la ola se pincha (whitecap), para la espuma.
vec3 gerstner_surface(vec3 local, vec3 radial, float t, out vec3 out_normal, out float out_crest) {
    vec3 pole = normalize(wave_pole);
    vec3 gx = normalize(cross(pole, abs(pole.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0)));
    vec3 gy = cross(pole, gx);

    vec2 bd = (abs(wave_direction.x) + abs(wave_direction.y) < 1e-4)
        ? vec2(1.0, 0.0) : normalize(wave_direction);

    vec3 horiz = vec3(0.0);
    float vert = 0.0;
    vec3 grad = vec3(0.0);
    float n_up_sub = 0.0;

    float amp = wave_amplitude;
    float len = wave_base_length;
    float ang = 0.0;
    int octaves = clamp(wave_octaves, 1, WAVE_MAX);

    for (int i = 0; i < WAVE_MAX; i++) {
        if (i >= octaves) break;
        float k = 6.28318530718 / max(len, 0.1);
        float ca = cos(ang);
        float sa = sin(ang);
        // Dirección de viaje fija en world (rotada por octava).
        vec3 dir_fixed = normalize(gx * (bd.x * ca - bd.y * sa) + gy * (bd.x * sa + bd.y * ca));
        // Proyección tangente en este punto: es el gradiente espacial de la fase.
        vec3 dir_tan = dir_fixed - radial * dot(dir_fixed, radial);
        float tan_len = length(dir_tan);
        vec3 dir_unit = tan_len > 1e-4 ? dir_tan / tan_len : vec3(0.0);

        // Steepness repartida entre octavas para no auto-intersecar las crestas.
        float q = wave_steepness / max(k * amp * float(octaves), 1e-4);
        float phase = k * dot(dir_fixed, local) + t * wave_speed * sqrt(k);
        float c = cos(phase);
        float s = sin(phase);

        horiz += q * amp * dir_unit * c;
        vert  += amp * s;

        grad += dir_tan * (k * amp * c); // dir_tan (sin normalizar) codifica el estiramiento cerca del polo
        n_up_sub += q * k * amp * s;

        amp *= 0.5;
        len *= 0.5;
        ang += 2.399963; // ángulo áureo: dispersa las direcciones entre octavas
    }

    out_normal = normalize(radial * (1.0 - n_up_sub) - grad);
    // Señal de cresta: n_up_sub = Σ q·k·amp·sin(phase) pica donde sin(phase)=1, es decir
    // EN la cresta (a diferencia de la normal, que se inclina en los flancos). Está acotada a
    // ±wave_steepness; la escalamos por 2 para que una cresta a steepness=0.5 dé ~1.0. Sube con
    // el oleaje: más steepness (weather) ⇒ más área por encima del umbral ⇒ más espuma.
    out_crest = n_up_sub * 2.0;
    return horiz + radial * vert;
}

// Wrapper sin señal de cresta para los callers que solo necesitan desplazamiento y normal.
vec3 gerstner_surface(vec3 local, vec3 radial, float t, out vec3 out_normal) {
    float unused_crest;
    return gerstner_surface(local, radial, t, out_normal, unused_crest);
}

// Desplazamiento radial Y normal de la superficie sobre la dirección de 'local', invirtiendo por
// punto fijo el arrastre horizontal de Gerstner — mismo esquema que WaterHeightSampler.get_height_at.
// Ambos salen del mismo punto invertido: la normal evaluada en 'local' sin invertir pertenece a
// otra fase de la ola y desalinea el corte de la línea de flotación.
float gerstner_surface_height_normal(vec3 local, float t, out vec3 out_normal) {
    vec3 guess = local;
    for (int i = 0; i < 2; i++) {
        vec3 radial = normalize(guess);
        vec3 disp = gerstner_surface(guess, radial, t, out_normal);
        vec3 horiz = disp - radial * dot(disp, radial);
        guess = local - horiz;
    }
    vec3 radial = normalize(guess);
    return dot(gerstner_surface(guess, radial, t, out_normal), radial);
}

// Wrapper solo-altura para los callers que no necesitan la normal.
float gerstner_surface_height(vec3 local, float t) {
    vec3 unused_normal;
    return gerstner_surface_height_normal(local, t, unused_normal);
}
