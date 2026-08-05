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

// --- Máscara de temporal ---------------------------------------------------------------------
// El clima sube el oleaje sobre un ÚNICO material para todo el planeta, así que sin esto una
// tormenta levanta olas de mar abierto también dentro de un lago y en la rompiente. La máscara sale
// del mapa mundial precomputado (PlanetWorldMap): solo los cuerpos marcados como océano o mar
// reciben temporal, y aun ahí entra progresivamente con la profundidad.
//
// Solo se enmascaran AMPLITUD y STEEPNESS. La velocidad y la longitud de onda tienen que seguir
// siendo globales: variarlas por posición cambia la fase entre vértices vecinos y raja la malla.
//
// Con storm_mask_enabled = false la exposición es 1 en todo el planeta, o sea el comportamiento de
// siempre. PlanetWorldMap.storm_exposure_local es la réplica CPU; cambiar una obliga a cambiar la otra.
uniform bool storm_mask_enabled = false;
uniform sampler2D storm_height_map : filter_linear, repeat_enable;
uniform sampler2D storm_body_map : filter_nearest, repeat_enable;
uniform float storm_height_min = 0.0;
uniform float storm_height_range = 1.0;
uniform float storm_sea_height = 0.0;
uniform int storm_body_ids[8];
uniform int storm_body_count = 0;
uniform float storm_depth_start = 30.0;
uniform float storm_depth_full = 150.0;
// Oleaje al que vuelve el agua sin exposición. Lo escribe el WeatherController con los valores
// base del material, los de antes de aplicarle el evento de clima.
uniform float wave_calm_amplitude = 4.0;
uniform float wave_calm_steepness = 0.5;

float storm_exposure(vec3 local) {
    if (!storm_mask_enabled) {
        return 1.0;
    }
    vec3 d = normalize(local);
    // Misma convención equirect que WorldMapData.dir_to_uv.
    vec2 uv = vec2(fract(0.5 - atan(d.z, d.x) / 6.28318530718),
                   acos(clamp(d.y, -1.0, 1.0)) / 3.14159265359);

    // textureLod y no texture: esto se evalúa también en el vertex, donde no hay derivadas.
    vec4 c = textureLod(storm_body_map, uv, 0.0);
    int id = int(round(c.r * 255.0))
        | (int(round(c.g * 255.0)) << 8)
        | (int(round(c.b * 255.0)) << 16)
        | (int(round(c.a * 255.0)) << 24);

    bool exposed = false;
    for (int i = 0; i < 8; i++) {
        if (i >= storm_body_count) break;
        if (storm_body_ids[i] == id) {
            exposed = true;
            break;
        }
    }
    if (!exposed) {
        return 0.0;
    }

    float h = storm_height_min + textureLod(storm_height_map, uv, 0.0).r * storm_height_range;
    return smoothstep(storm_depth_start, storm_depth_full, storm_sea_height - h);
}

// Suma de olas de Gerstner planetarias. Cada dirección fija define un ecuador propio y la fase
// usa la distancia geodésica firmada a ese gran círculo. Así el gradiente espacial conserva
// módulo unitario y la longitud de onda permanece constante sobre la esfera.
// Devuelve el desplazamiento world-space y, por out_normal, la normal analítica. out_crest es la
// señal de cresta/pliegue en ~[0,1]: pica donde la ola se pincha (whitecap), para la espuma.
// min_length = longitud de onda mínima (m) que tiene sentido dibujar aquí; las octavas por debajo
// se desvanecen. 0 = sin LOD, evalúa todas.
vec3 gerstner_surface_lod(vec3 local, vec3 radial, float t, float min_length,
                          out vec3 out_normal, out float out_crest) {
    vec3 pole = normalize(wave_pole);
    vec3 gx = normalize(cross(pole, abs(pole.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0)));
    vec3 gy = cross(pole, gx);

    vec2 bd = (abs(wave_direction.x) + abs(wave_direction.y) < 1e-4)
        ? vec2(1.0, 0.0) : normalize(wave_direction);

    vec3 horiz = vec3(0.0);
    float vert = 0.0;
    vec3 grad = vec3(0.0);
    float n_up_sub = 0.0;

    // El temporal solo llega hasta donde dice la máscara; el resto se queda en el oleaje de calma.
    float exposure = storm_exposure(local);
    float amp = mix(wave_calm_amplitude, wave_amplitude, exposure);
    float steepness = mix(wave_calm_steepness, wave_steepness, exposure);
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
        // Dirección del gradiente geodésico en el plano tangente.
        float dir_dot = clamp(dot(dir_fixed, radial), -1.0, 1.0);
        vec3 dir_tan = dir_fixed - radial * dir_dot;
        float tan_len = length(dir_tan);
        vec3 dir_unit = tan_len > 1e-4 ? dir_tan / tan_len : vec3(0.0);

        // Steepness repartida entre octavas para no auto-intersecar las crestas.
        float q = steepness / max(k * amp * float(octaves), 1e-4);
        // Distancia geodésica firmada al gran círculo de la ola. Su gradiente tangente
        // tiene módulo 1: conserva la longitud de onda en vez de estirarla en el ecuador.
        float signed_arc = length(local) * asin(dir_dot);
        float phase = k * signed_arc + t * wave_speed * sqrt(k);
        float c = cos(phase);
        float s = sin(phase);

        // Octava por debajo de lo representable a esta distancia: el quadtree separa los vértices
        // con la distancia, la fase acaba dando varias vueltas entre vértices vecinos y la octava
        // deja de ser una ola para ser ruido, que se interpola en manchas del tamaño del triángulo.
        // Se apagan de la más corta a la más larga; con todas apagadas out_normal vuelve a ser la
        // radial y out_crest a 0 (esfera lisa, sin espuma).
        float lod_weight = min_length > 0.0
            ? smoothstep(min_length * 0.5, min_length * 1.5, len)
            : 1.0;

        horiz += q * amp * dir_unit * c * lod_weight;
        vert  += amp * s * lod_weight;

        grad += dir_unit * (k * amp * c) * lod_weight;
        n_up_sub += q * k * amp * s * lod_weight;

        amp *= 0.5;
        len *= 0.5;
        ang += 2.399963; // ángulo áureo: dispersa las direcciones entre octavas
    }

    out_normal = normalize(radial * (1.0 - n_up_sub) - grad);
    // Señal de cresta: n_up_sub = Σ q·k·amp·sin(phase) pica donde sin(phase)=1, es decir
    // EN la cresta (a diferencia de la normal, que se inclina en los flancos). Está acotada a
    // ±steepness; la escalamos por 2 para que una cresta a steepness=0.5 dé ~1.0. Sube con el
    // oleaje: más steepness (weather) ⇒ más área por encima del umbral ⇒ más espuma. Por eso la
    // espuma sigue a la máscara de temporal sola, sin enmascararla también aquí.
    out_crest = n_up_sub * 2.0;
    return horiz + radial * vert;
}

// Wrapper sin LOD ni señal de cresta: evalúa todas las octavas. Lo usan la línea de flotación y la
// niebla submarina, que muestrean junto a la cámara y no pueden desviarse del sampler de CPU.
vec3 gerstner_surface(vec3 local, vec3 radial, float t, out vec3 out_normal) {
    float unused_crest;
    return gerstner_surface_lod(local, radial, t, 0.0, out_normal, unused_crest);
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
