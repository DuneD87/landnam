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

// Los mapas storm_* son en realidad el mapa mundial horneado (PlanetWorldMap) enchufado al agua:
// los comparten la máscara de temporal y las olas de orilla de más abajo.

// Misma convención equirect que WorldMapData.dir_to_uv.
vec2 world_map_uv(vec3 dir) {
    return vec2(fract(0.5 - atan(dir.z, dir.x) / 6.28318530718),
                acos(clamp(dir.y, -1.0, 1.0)) / 3.14159265359);
}

// Altura del terreno sobre el radio nominal en ese téxel. textureLod y no texture: esto se evalúa
// también en el vertex, donde no hay derivadas.
float world_map_ground(vec2 uv) {
    return storm_height_min + textureLod(storm_height_map, uv, 0.0).r * storm_height_range;
}

// Recibe la uv equirect y la altura del terreno ya resueltas: las olas de orilla necesitan las dos
// también, y calcularlas aquí otra vez costaba un atan+acos y una lectura de textura de más en cada
// evaluación. La niebla submarina llama a esto ~70 veces por píxel, así que se nota.
float storm_exposure(vec2 uv, float ground) {
    if (!storm_mask_enabled) {
        return 1.0;
    }
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

    return smoothstep(storm_depth_start, storm_depth_full, storm_sea_height - ground);
}

// --- Olas de orilla ---------------------------------------------------------------------------
// En la franja costera el oleaje deja de venir de mar abierto: llega siempre de frente a la playa,
// con las crestas paralelas al litoral. Aquí NO se calcula la refracción; sale gratis haciendo que
// la FASE de esta familia sea la distancia horneada al litoral (shore_offset_map, de
// WorldMapBaker.bake_shore_field). Esa distancia es un campo escalar global y continuo con
// gradiente de módulo 1, así que la longitud de onda no cambia con la posición —y la malla no se
// raja, que es lo que prohíbe variar velocidad y longitud por posición—; y como la ola viaja por
// -grad(distancia), viaja hacia la costa por construcción.
//
// Se mezcla con el oleaje de mar abierto por AMPLITUD, nunca por fase: interpolar dos fases mete un
// término de miles de radianes que destroza las crestas. Encaja justo en el hueco que deja
// storm_exposure(), que ya vale 0 por debajo de storm_depth_start.
//
// WaterHeightSampler._gerstner_disp es la réplica CPU; cambiar una obliga a cambiar la otra.
uniform bool shore_waves_enabled = false;
uniform sampler2D shore_offset_map : filter_linear, repeat_enable; // xyz = vector al litoral (m), w = peso horneado
uniform float shore_amplitude : hint_range(0.0, 20.0, 0.05) = 2.0;
uniform float shore_length : hint_range(4.0, 300.0, 0.5) = 70.0;
uniform float shore_speed : hint_range(0.0, 10.0, 0.05) = 1.2;
uniform float shore_steepness : hint_range(0.0, 1.0, 0.01) = 0.7;
// El ancho de la franja costera lo decide la DISTANCIA al litoral (el peso horneado, SHORE_RANGE),
// no la profundidad. Atarlo a la batimetría se probó y no vale aquí: este terreno cae al 15% contra
// la orilla —las plataformas terrestres van al 0,1-1%—, así que con cualquier umbral físico la
// rompiente se quedaba en una tira de 160 m y el kilómetro siguiente se lo comía el swell global,
// viajando en una sola dirección contra toda la costa. La profundidad solo sigue apagando la ola en
// la propia línea de agua (shore_depth_fade).
uniform float shore_depth_fade : hint_range(0.1, 20.0, 0.1) = 2.0;   // profundidad a la que se apaga en la propia orilla
uniform float shore_shoal_max : hint_range(1.0, 6.0, 0.1) = 2.5;     // tope del crecimiento por shoaling
uniform float shore_incidence : hint_range(0.0, 1.0, 0.01) = 0.6;    // cuánto calma las costas a sotavento del swell
// Hasta dónde se ven las olas de orilla, en metros. 0 = toda la franja horneada. Sirve para acercar
// la rompiente a la costa SIN rehornear con un SHORE_RANGE menor, que es peor: el campo se hornea a
// ~90 m por téxel, así que una franja de 150 m son téxel y medio y la geometría de las crestas sale
// cuantizada. Mejor hornear ancho y recortar aquí.
uniform float shore_reach : hint_range(0.0, 3000.0, 10.0) = 0.0;
// Cuánto se adelanta el apagado del mar abierto al encendido de la orilla. Con un relevo simétrico
// las dos familias valen 0.5 a la vez en toda la transición y sus crestas se cruzan: eso es el mar
// cruzado, y se ve como una cuadrícula de picos. Subirlo saca antes al mar abierto (menos cruce, a
// cambio de un valle de amplitud); bajarlo a 1 vuelve al relevo simétrico.
uniform float shore_handover : hint_range(0.05, 1.0, 0.01) = 0.35;
uniform int shore_debug_mode : hint_range(0, 5) = 0;                 // ver shore_debug_color

// Suma de olas de Gerstner planetarias. Cada dirección fija define un ecuador propio y la fase
// usa la distancia geodésica firmada a ese gran círculo. Así el gradiente espacial conserva
// módulo unitario y la longitud de onda permanece constante sobre la esfera.
// Devuelve el desplazamiento world-space y, por out_normal, la normal analítica. out_crest es la
// señal de cresta/pliegue en ~[0,1]: pica donde la ola se pincha (whitecap), para la espuma.
// min_length = longitud de onda mínima (m) que tiene sentido dibujar aquí; las octavas por debajo
// se desvanecen. 0 = sin LOD, evalúa todas.
// Todo lo que la superficie necesita del mapa mundial en un punto. Se resuelve UNA vez y se
// reutiliza: la inversión de punto fijo evalúa la superficie tres veces sobre puntos separados unos
// metros, y releer las texturas en cada una triplicaba las lecturas para un dato que varía en
// decenas de metros. WaterHeightSampler ya muestreaba fuera de la iteración, así que esto además
// acerca CPU y GPU en vez de separarlas.
struct WaveContext {
    float exposure;
    vec4 shore_field;
    float shore_dist;
    float shore_depth;
    float shore_gate;
};

WaveContext wave_context(vec3 local) {
    WaveContext ctx;
    ctx.exposure = 1.0;
    ctx.shore_field = vec4(0.0);
    ctx.shore_dist = 0.0;
    ctx.shore_depth = 0.0;
    ctx.shore_gate = 0.0;
    if (!storm_mask_enabled && !shore_waves_enabled) {
        return ctx;
    }

    // La uv equirect y la altura del terreno las comparten la máscara de temporal y las olas de
    // orilla: un solo atan+acos y una sola lectura para las dos.
    vec2 uv = world_map_uv(normalize(local));
    float ground = world_map_ground(uv);
    ctx.exposure = storm_exposure(uv, ground);

    if (shore_waves_enabled) {
        ctx.shore_field = textureLod(shore_offset_map, uv, 0.0);
        ctx.shore_dist = length(ctx.shore_field.xyz);
        ctx.shore_depth = storm_sea_height - ground;
        if (ctx.shore_field.w > 0.001 && ctx.shore_dist > 1.0) {
            ctx.shore_gate = ctx.shore_field.w * (shore_reach > 0.0
                ? smoothstep(shore_reach, shore_reach * 0.6, ctx.shore_dist)
                : 1.0);
        }
    }
    return ctx;
}

vec3 gerstner_surface_ctx(vec3 local, vec3 radial, float t, float min_length, WaveContext ctx,
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
    // Dirección de viaje de la octava principal: la usa la incidencia de las olas de orilla.
    vec3 swell_dir = vec3(0.0);

    // El campo de orilla se muestrea ANTES del bucle porque su peso decide también cuánto oleaje de
    // mar abierto queda: las dos familias se RELEVAN, no se suman. Sumándolas, en una costa a
    // sotavento el swell global se sigue dibujando y se le ve viajar mar adentro, encima de una ola
    // de orilla que además la incidencia había dejado a la mitad.
    // Lo que le queda al mar abierto. Asimétrico a propósito (ver shore_handover), y sin la puerta
    // de la línea de agua: con ella el swell global reaparecería justo en la rompiente.
    float ocean_weight = 1.0 - smoothstep(0.0, shore_handover, ctx.shore_gate);

    // El temporal solo llega hasta donde dice la máscara; el resto se queda en el oleaje de calma.
    float amp = mix(wave_calm_amplitude, wave_amplitude, ctx.exposure);
    float steepness = mix(wave_calm_steepness, wave_steepness, ctx.exposure);
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
        if (i == 0) {
            swell_dir = -dir_unit;
        }

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
        lod_weight *= ocean_weight;

        horiz += q * amp * dir_unit * c * lod_weight;
        vert  += amp * s * lod_weight;

        grad += dir_unit * (k * amp * c) * lod_weight;
        n_up_sub += q * k * amp * s * lod_weight;

        amp *= 0.5;
        len *= 0.5;
        ang += 2.399963; // ángulo áureo: dispersa las direcciones entre octavas
    }

    // Familia de orilla: una sola ola cuya fase es la distancia al litoral. Suma a los mismos
    // acumuladores que las octavas, así normal y cresta salen consistentes para todos los callers.
    if (ctx.shore_gate > 0.001) {
        // Gradiente de la distancia en el plano tangente: apunta mar adentro, y la ola viaja en
        // sentido contrario. Se reproyecta al plano del vértice porque el vector horneado es el
        // del centro del téxel, no el de aquí.
        vec3 seaward = -ctx.shore_field.xyz / ctx.shore_dist;
        seaward = normalize(seaward - radial * dot(seaward, radial));

        // Shoaling (ley de Green, A ~ h^-1/4), acotado: sin tope la ola revienta en la orilla. La
        // referencia es media longitud de onda, que es la profundidad a la que una ola siente el
        // fondo de verdad; atarla a la puerta mezclaba el perfil de amplitud con el ancho de franja.
        float shoal = clamp(pow(max(ctx.shore_depth, 0.5) / max(shore_length * 0.5, 1.0), -0.25),
                            1.0, shore_shoal_max);
        float swash = smoothstep(0.0, shore_depth_fade, ctx.shore_depth);
        // Incidencia: una costa de espaldas al swell rompe menos que una de cara, pero NUNCA hasta
        // cero. Antes se apagaba del todo y las playas a sotavento se quedaban en agua muerta;
        // en la realidad les llega oleaje difractado, más pequeño.
        float lee = mix(1.0, mix(0.35, 1.0, smoothstep(-0.9, 0.6, dot(swell_dir, -seaward))),
                        shore_incidence);
        float lod_weight = min_length > 0.0
            ? smoothstep(min_length * 0.5, min_length * 1.5, shore_length)
            : 1.0;
        float w = ctx.shore_gate * swash * lee * lod_weight;

        float k = 6.28318530718 / max(shore_length, 0.1);
        // amp_ref va SIN el peso: la Q de Gerstner se normaliza contra la amplitud y se cancelaría
        // con ella, dejando arrastre horizontal donde la ola ya no existe. El peso escala después
        // los cuatro acumuladores, y así el término se apaga de verdad.
        float amp_ref = shore_amplitude * shoal;
        float q = shore_steepness / max(k * amp_ref, 1e-4);
        float phase = k * ctx.shore_dist + t * shore_speed * sqrt(k);
        float cs = cos(phase);
        float sn = sin(phase);

        horiz += q * amp_ref * seaward * cs * w;
        vert += amp_ref * sn * w;
        grad += seaward * (k * amp_ref * cs) * w;
        n_up_sub += q * k * amp_ref * sn * w;
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

// Dirección de viaje de la octava principal del oleaje de mar abierto, la misma que captura
// gerstner_surface_lod en i == 0.
vec3 swell_direction(vec3 radial) {
    vec3 pole = normalize(wave_pole);
    vec3 gx = normalize(cross(pole, abs(pole.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0)));
    vec3 gy = cross(pole, gx);
    vec2 bd = (abs(wave_direction.x) + abs(wave_direction.y) < 1e-4)
        ? vec2(1.0, 0.0) : normalize(wave_direction);
    vec3 dir_fixed = normalize(gx * bd.x + gy * bd.y);
    vec3 dir_tan = dir_fixed - radial * dot(dir_fixed, radial);
    float tan_len = length(dir_tan);
    return tan_len > 1e-4 ? -dir_tan / tan_len : vec3(0.0);
}

// Vista de depuración del campo de orilla, para localizar dónde falla sin ir a ciegas. Pinta el
// agua plana con el valor crudo del campo; devuelve negro donde no hay dato.
//   1 peso horneado (negro = sin ola)          2 fase: bandas de una longitud de onda, enseñan
//                                                hacia dónde miran las crestas
//   3 sentido de viaje CONTRA la batimetría:   4 relevo entre familias: rojo = manda el oleaje de
//     verde = la ola avanza hacia donde el        mar abierto, verde = manda la orilla
//     fondo sube; rojo = va al revés            5 amplitud final relativa de la orilla
vec3 shore_debug_color(vec3 local, float t) {
    vec3 d = normalize(local);
    vec2 uv = world_map_uv(d);
    vec4 field = textureLod(shore_offset_map, uv, 0.0);
    float dist = length(field.xyz);
    if (shore_debug_mode == 1) {
        return vec3(field.w, field.w * field.w, step(0.999, field.w));
    }
    if (dist <= 1.0) {
        return vec3(0.0);
    }

    vec3 seaward = -field.xyz / dist;
    seaward = normalize(seaward - d * dot(seaward, d));
    float depth = storm_sea_height - world_map_ground(uv);
    float swash = smoothstep(0.0, shore_depth_fade, depth);

    if (shore_debug_mode == 2) {
        float k = 6.28318530718 / max(shore_length, 0.1);
        float band = fract((k * dist + t * shore_speed * sqrt(k)) / 6.28318530718);
        return mix(vec3(0.05, 0.1, 0.25), vec3(1.0), step(0.5, band));
    }
    if (shore_debug_mode == 3) {
        // Sonda independiente del campo: si la ola viaja bien, el terreno sube en esa dirección.
        float rise = world_map_ground(world_map_uv(normalize(local - seaward * 300.0)))
                   - world_map_ground(uv);
        return mix(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), smoothstep(-2.0, 2.0, rise));
    }
    float gate = field.w;
    if (shore_debug_mode == 4) {
        return mix(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), gate);
    }
    float lee = mix(1.0, mix(0.35, 1.0, smoothstep(-0.9, 0.6, dot(swell_direction(d), -seaward))),
                    shore_incidence);
    return vec3(gate * swash * lee);
}

// Resuelve el mapa por su cuenta. Es la entrada normal desde el vertex del agua, que evalúa un
// punto distinto por vértice y no puede reaprovechar nada.
vec3 gerstner_surface_lod(vec3 local, vec3 radial, float t, float min_length,
                          out vec3 out_normal, out float out_crest) {
    return gerstner_surface_ctx(local, radial, t, min_length, wave_context(local),
                                out_normal, out_crest);
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
    // El mapa se resuelve UNA vez para las tres evaluaciones. El punto fijo mueve el punto unos
    // metros y estos datos varían en decenas, así que la diferencia no se aprecia y ahorra dos
    // tercios de las lecturas — que aquí pesan, porque la marcha de rayos de la niebla submarina
    // llama a esta función decenas de veces por píxel. Es además lo que ya hacía WaterHeightSampler.
    WaveContext ctx = wave_context(local);
    float unused_crest;
    vec3 guess = local;
    for (int i = 0; i < 2; i++) {
        vec3 radial = normalize(guess);
        vec3 disp = gerstner_surface_ctx(guess, radial, t, 0.0, ctx, out_normal, unused_crest);
        vec3 horiz = disp - radial * dot(disp, radial);
        guess = local - horiz;
    }
    vec3 radial = normalize(guess);
    return dot(gerstner_surface_ctx(guess, radial, t, 0.0, ctx, out_normal, unused_crest), radial);
}

// Wrapper solo-altura para los callers que no necesitan la normal.
float gerstner_surface_height(vec3 local, float t) {
    vec3 unused_normal;
    return gerstner_surface_height_normal(local, t, unused_normal);
}
