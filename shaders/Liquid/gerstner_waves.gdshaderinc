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

// Jerarquía de escalas: cada octava conserva 0.5 * decay de la altura anterior.
// 1 recupera el espectro anterior; valores menores dejan respirar al mar de fondo.
uniform float wave_detail_decay : hint_range(0.3, 1.0, 0.01) = 0.72;
// Series viajeras de mar abierto. El pico conserva la amplitud del clima; las pausas la reducen.
uniform float wave_group_strength : hint_range(0.0, 0.8, 0.01) = 0.45;
uniform float wave_group_waves : hint_range(2.0, 12.0, 0.1) = 4.5;
// Variación de fase y altura a lo largo de cada frente; 0 conserva las series uniformes.
uniform float wave_irregularity : hint_range(0.0, 1.0, 0.01) = 0.8;

const int WAVE_MAX = 6;

// Abanico y lacunaridad del oleaje. Las dos existen para lo mismo: que la suma de octavas no sea
// periódica, porque una suma de senos puros sí lo es y se lee como un mantel estampado.
//
// El abanico acota las direcciones a ±WAVE_FAN alrededor de wave_direction, con el ángulo áureo
// SOLO como secuencia de baja discrepancia dentro de esa horquilla. Acumularlo (que es lo que se
// hacía) reparte las seis octavas por los 360 grados y deja pares casi opuestos —la 4 a 190 grados
// de la 0, la 5 a 190 de la 1—: dos trenes enfrentados son una onda estacionaria, y de ahí sale la
// rejilla de crestas. Un mar real tiene el oleaje repartido en un abanico estrecho a favor del
// viento, no en todas las direcciones a la vez.
//
// La lacunaridad tenía que ser 0.5 exacto, así que todas las octavas eran armónicas de la primera y
// el patrón entero se repetía cada wave_base_length metros. Con un factor que no divide a la
// fundamental el periodo común se va a cientos de metros. La caída de amplitud se controla aparte
// con wave_detail_decay; la irregularidad espacial rompe además los frentes de cada octava.
const float WAVE_FAN = 0.7;
const float WAVE_LACUNARITY = 0.53;

// x = envolvente, y = derivada espacial a lo largo del swell, z = derivada temporal.
// La fase del oleaje no se modifica: la serie viaja a la mitad de la velocidad de la
// ola principal. Dos escalas evitan que todas las series tengan la misma intensidad.
// Réplica CPU: WaterHeightSampler._wave_group().
vec3 wave_group(float signed_arc, float t) {
    float strength = clamp(wave_group_strength, 0.0, 0.8);
    if (strength <= 0.0) { return vec3(1.0, 0.0, 0.0); }
    float k = 6.28318530718 / max(wave_base_length, 0.1);
    float count = max(wave_group_waves, 2.0);
    float group_k = k / count;
    float group_omega = wave_speed * sqrt(k) * 0.5 / count;
    float p1 = group_k * signed_arc + group_omega * t + 0.7;
    float p2 = group_k * 0.61 * signed_arc + group_omega * 0.61 * t + 2.3;
    float slope = -strength * (0.35 * sin(p1) + 0.15 * 0.61 * sin(p2));
    return vec3(1.0 - strength * (0.5 - 0.35 * cos(p1) - 0.15 * cos(p2)),
                slope * group_k, slope * group_omega);
}

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
float storm_exposure(vec2 uv, float ground, out bool shore_allowed) {
    if (!storm_mask_enabled) {
        shore_allowed = true;
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
    // Tierra es -1 = RGBA(255). Cerca de la costa el mapa grueso puede decir "tierra" aunque la
    // malla de agua visible siga bajo este vértice: es un dato incierto y NO debe cortar la ola.
    // Solo un id positivo conocido como lago/charca constituye una exclusión fiable.
    bool coarse_land = c.r > 0.998 && c.g > 0.998 && c.b > 0.998 && c.a > 0.998;
    shore_allowed = coarse_land || exposed;
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
// xyz = dirección unitaria hacia tierra; w = distancia/fase firmada (+mar, -tierra). Tras el filtro,
// length(xyz) mide cuánto coinciden las direcciones vecinas sin contaminar la fase.
uniform sampler2D shore_offset_map : filter_linear, repeat_enable;
uniform float shore_amplitude : hint_range(0.0, 20.0, 0.05) = 2.0;
uniform float shore_length : hint_range(4.0, 300.0, 0.5) = 20.0;
uniform float shore_speed : hint_range(0.0, 10.0, 0.05) = 1.2;
uniform float shore_steepness : hint_range(0.0, 1.0, 0.01) = 0.45;
// El ancho de la franja costera lo decide la DISTANCIA al litoral (acotada por SHORE_RANGE),
// no la profundidad. Atarlo a la batimetría se probó y no vale aquí: este terreno cae al 15% contra
// la orilla —las plataformas terrestres van al 0,1-1%—, así que con cualquier umbral físico la
// rompiente se quedaba en una tira de 160 m y el kilómetro siguiente se lo comía el swell global,
// viajando en una sola dirección contra toda la costa. El mapa es demasiado grueso para usar su
// profundidad en la línea de agua. Se conserva el nombre de este uniform por compatibilidad, pero
// ahora controla el mínimo de metros desde el litoral en los que entra suavemente el desplazamiento.
uniform float shore_depth_fade : hint_range(0.1, 20.0, 0.1) = 2.0;
uniform float shore_shoal_max : hint_range(1.0, 6.0, 0.1) = 2.5;     // tope del crecimiento por shoaling
uniform float shore_incidence : hint_range(0.0, 1.0, 0.01) = 0.6;    // cuánto calma las costas a sotavento del swell
// Hasta dónde se ven las olas de orilla, en metros. 0 = toda la franja horneada. Sirve para acercar
// la rompiente a la costa SIN rehornear con un SHORE_RANGE menor, que es peor: el campo se hornea a
// ~90 m por téxel, así que una franja de 150 m son téxel y medio y la geometría de las crestas sale
// cuantizada. Mejor hornear ancho y recortar aquí.
uniform float shore_reach : hint_range(0.0, 3000.0, 10.0) = 0.0;
// Alcance con el que se horneó el campo (lo empuja PlanetLoader). Es el que manda si shore_reach
// vale 0, y hace falta aquí para poder dar forma a la transición sin rehornear.
uniform float shore_range = 1200.0;
// Qué fracción del alcance ocupa el degradado de entrada, medido desde fuera hacia la costa.
// 0.5 = la mitad exterior de la franja es transición. Subirlo difumina el corte entre mar adentro y
// zona costera; bajarlo lo concentra. Cuidado: la transición es donde conviven las dos familias, así
// que estirarla mucho reaparece el mar cruzado — se compensa bajando shore_handover.
uniform float shore_fade : hint_range(0.05, 0.95, 0.01) = 0.5;
// Cuánto se adelanta el apagado del mar abierto al encendido de la orilla. Con un relevo simétrico
// las dos familias valen 0.5 a la vez en toda la transición y sus crestas se cruzan: eso es el mar
// cruzado, y se ve como una cuadrícula de picos. Subirlo saca antes al mar abierto (menos cruce, a
// cambio de un valle de amplitud); bajarlo a 1 vuelve al relevo simétrico.
uniform float shore_handover : hint_range(0.05, 1.0, 0.01) = 0.35;
// Cuánto oleaje de mar abierto SOBREVIVE al relevo, solo en las octavas mucho más cortas que la ola
// de orilla. Sin esto la franja costera es una única ola de Gerstner —una longitud de onda, una
// dirección, una fase— y por muy bien que se mueva se lee como una plancha ondulada. El relevo tiene
// sentido para el swell largo, que refracta y cede el paso a la rompiente; el chop de viento es de
// generación local y existe también dentro de la bahía. Subirlo mucho reabre el mar cruzado que
// shore_handover existe para evitar, pero solo puede hacerlo a escalas ya muy separadas de la
// rompiente: las octavas comparables a shore_length siguen apagándose enteras.
uniform float shore_chop : hint_range(0.0, 10.0, 0.01) = 0.35;
uniform int shore_debug_mode : hint_range(0, 5) = 0;                 // ver shore_debug_color

// shore_breakup(): dobla la cresta y la parte en tramos. Vive en su propio include para que pueda
// usarla un shader incapaz de traerse este archivo entero (aquí hay treinta uniforms). Su aporte al
// gradiente de la fase está acotado a ~0.45k, así que deforma la ola sin poder plegarla; el
// razonamiento está en ese archivo.
#include "res://shaders/liquid/shore_breakup.gdshaderinc"

// Suma de olas de Gerstner planetarias. Cada dirección fija define un ecuador propio y la fase
// usa la distancia geodésica firmada a ese gran círculo. Así el gradiente espacial conserva
// módulo unitario y la longitud de onda permanece constante sobre la esfera.
// Devuelve el desplazamiento world-space y, por out_normal, la normal analítica. out_crest es la
// señal de cresta/pliegue en ~[0,1]: pica donde la ola se pincha (whitecap), para la espuma.
// min_length = longitud de onda mínima (m) que tiene sentido dibujar aquí; las octavas por debajo
// se desvanecen. 0 = sin LOD, evalúa todas.
// Todo lo que la superficie necesita del mapa mundial en un punto. Se resuelve UNA vez y se
// reutiliza: la inversión de punto fijo evalúa la superficie cuatro veces sobre puntos separados unos
// metros, y releer las texturas en cada una cuadruplicaría las lecturas para un dato que varía en
// decenas de metros. WaterHeightSampler ya muestreaba fuera de la iteración, así que esto además
// acerca CPU y GPU en vez de separarlas.
struct WaveContext {
    float exposure;
    vec4 shore_field;
    float shore_dist;
    float shore_quality;
    float shore_depth;
    float shore_gate;
};

WaveContext wave_context(vec3 local) {
    WaveContext ctx;
    ctx.exposure = 1.0;
    ctx.shore_field = vec4(0.0);
    ctx.shore_dist = 0.0;
    ctx.shore_quality = 0.0;
    ctx.shore_depth = 0.0;
    ctx.shore_gate = 0.0;
    if (!storm_mask_enabled && !shore_waves_enabled) {
        return ctx;
    }

    // La uv equirect y la altura del terreno las comparten la máscara de temporal y las olas de
    // orilla: un solo atan+acos y una sola lectura para las dos.
    vec2 uv = world_map_uv(normalize(local));
    float ground = world_map_ground(uv);
    bool shore_allowed;
    ctx.exposure = storm_exposure(uv, ground, shore_allowed);

    // Un id interior confirmado bloquea esta familia. "Tierra" no: en el borde grueso del mapa
    // también puede significar agua visible y convertirlo en veto dibuja rectángulos de un téxel.
    if (shore_waves_enabled && shore_allowed) {
        ctx.shore_field = textureLod(shore_offset_map, uv, 0.0);
        ctx.shore_dist = abs(ctx.shore_field.w);
        ctx.shore_quality = clamp(length(ctx.shore_field.xyz), 0.0, 1.0);
        ctx.shore_depth = storm_sea_height - ground;
        if (ctx.shore_dist > 1.0) {
            float reach = shore_reach > 0.0 ? shore_reach : shore_range;
            ctx.shore_gate = 1.0
                - smoothstep(reach * (1.0 - shore_fade), reach, ctx.shore_dist);
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

    // El mapa mundial es mucho más grueso que el terreno visible y puede marcar como tierra puntos
    // donde todavía hay agua. Por eso la presencia costera NO se decide con shore_depth: hacerlo
    // dejaba la costera a cero en esos puntos. La propia distancia al litoral es el dato fiable y
    // apaga el desplazamiento en los primeros metros de la línea de contacto.
    float shoreline_fade_end = max(shore_length * 0.25, shore_depth_fade);
    float shoreline_fade = smoothstep(1.0, shoreline_fade_end, ctx.shore_dist);
    float shore_lod_weight = min_length > 0.0
        ? smoothstep(min_length * 0.5, min_length * 1.5, shore_length)
        : 1.0;
    float shore_presence = ctx.shore_gate * shoreline_fade * shore_lod_weight;
    float ocean_weight = 1.0 - smoothstep(0.0, shore_handover, shore_presence);

    // El temporal solo llega hasta donde dice la máscara; el resto se queda en el oleaje de calma.
    float amp = mix(wave_calm_amplitude, wave_amplitude, ctx.exposure);
    float steepness = mix(wave_calm_steepness, wave_steepness, ctx.exposure);
    float len = wave_base_length;
    int octaves = clamp(wave_octaves, 1, WAVE_MAX);
    float detail_decay = clamp(wave_detail_decay, 0.3, 1.0);
    float detail_weight = 1.0;
    float weight_sum = detail_decay > 0.9999 ? float(octaves)
        : (1.0 - pow(detail_decay, float(octaves))) / (1.0 - detail_decay);
    // Reservar margen para el gradiente de la envolvente en el arrastre horizontal.
    float group_budget = 1.0 + 0.45 * clamp(wave_group_strength, 0.0, 0.8) / max(wave_group_waves, 2.0);
    float irregularity = clamp(wave_irregularity, 0.0, 1.0);
    // Cota de los gradientes añadidos de fase (<0.58k) y amplitud (<0.11k).
    group_budget *= 1.0 + 0.7 * irregularity;
    vec3 packet = vec3(1.0, 0.0, 0.0);

    for (int i = 0; i < WAVE_MAX; i++) {
        if (i >= octaves) break;
        float k = 6.28318530718 / max(len, 0.1);
        // La octava 0 va sin desviar: es la que define swell_dir y la dirección del mar.
        float ang = WAVE_FAN * sin(float(i) * 2.399963);
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

        // Repartir también el pliegue: reducir solo amp se cancelaría dentro de q,
        // dejando las olas pequeñas igual de afiladas pese a perder altura.
        float q = steepness * detail_weight / max(k * amp * weight_sum * group_budget, 1e-4);
        // Distancia geodésica firmada al gran círculo de la ola. Su gradiente tangente
        // tiene módulo 1: conserva la longitud de onda en vez de estirarla en el ecuador.
        float signed_arc = length(local) * asin(dir_dot);
        if (i == 0) { packet = wave_group(signed_arc, t); }
        // El desfase por octava es constante, así que no aporta gradiente y no puede rajar la malla.
        // Sin él las seis octavas cruzan el cero a la vez sobre su gran círculo y ahí se alinean.
        float omega = wave_speed * sqrt(k);
        float phase = k * signed_arc + t * omega + float(i) * 2.399963;
        vec3 phase_gradient = dir_unit * k;
        float shape_amplitude = 1.0;
        vec3 amplitude_gradient = vec3(0.0);
        if (irregularity > 0.0) {
            // Dominios globales continuos, oblicuos al swell y distintos por octava.
            // No se altera k según la posición: se añade una fase acotada y derivable.
            // Así las crestas se curvan y pierden altura a tramos, sin costuras entre parches.
            vec3 side = cross(pole, dir_fixed);
            vec3 a = normalize(dir_fixed * 0.42 + side * 0.86 + pole * 0.29) * (k / 3.7);
            vec3 b = normalize(-dir_fixed * 0.68 + side * 0.31 - pole * 0.66) * (k / 2.3);
            float p1 = dot(local, a) + t * omega * 0.12 + float(i) * 1.71;
            float p2 = dot(local, b) - t * omega * 0.17 + float(i) * 2.43 + 1.3;
            float s1 = sin(p1);
            float c1 = cos(p1);
            float s2 = sin(p2);
            float c2 = cos(p2);
            vec3 a_tan = a - radial * dot(a, radial);
            vec3 b_tan = b - radial * dot(b, radial);
            phase += irregularity * (1.25 * s1 + 0.55 * s2);
            phase_gradient += irregularity * (1.25 * c1 * a_tan + 0.55 * c2 * b_tan);
            shape_amplitude = 1.0 - irregularity * (0.32 + 0.22 * c1 + 0.10 * c2);
            amplitude_gradient = irregularity * (0.22 * s1 * a_tan + 0.10 * s2 * b_tan);
        }
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
        // El relevo se aplica a esta octava según su escala: entera al swell, atenuada por shore_chop
        // a lo que sea mucho más corto que la rompiente. Fuera de la franja ocean_weight ya vale 1 y
        // el max() no hace nada. Coste cero: la octava se estaba evaluando igual para multiplicarla
        // por ~0.
        float chop_gate = 1.0 - smoothstep(shore_length * 0.25, shore_length * 0.75, len);
        // Límite de agua somera. Una ola rompe cuando su altura llega a ~0.8 de la profundidad, o sea
        // amplitud ~0.4·h. El chop no tenía ningún tope: en la línea de agua sumaba metros de oleaje
        // sobre centímetros de agua y levantaba al jugador por encima del umbral de nado bastante
        // antes de que llegara la rompiente visible. La profundidad del mapa es gruesa, pero aquí solo
        // ACOTA una amplitud —nunca decide si la familia existe—, que es el uso que el shoaling de más
        // abajo ya da a este mismo dato. Con la costera apagada shore_depth vale 0 y esto anula el
        // chop, lo cual da igual: ahí ocean_weight ya es 1 y manda el max().
        float chop_shallow = clamp(ctx.shore_depth * 0.4 / max(amp, 0.01), 0.0, 1.0);
        lod_weight *= max(ocean_weight, shore_chop * chop_gate * chop_shallow);

        horiz += q * amp * shape_amplitude * dir_unit * c * lod_weight;
        vert  += amp * shape_amplitude * s * lod_weight;

        grad += amp * (shape_amplitude * c * phase_gradient + s * amplitude_gradient) * lod_weight;
        n_up_sub += q * amp * (shape_amplitude * s * dot(dir_unit, phase_gradient)
                    - c * dot(dir_unit, amplitude_gradient)) * lod_weight;

        amp *= 0.5 * detail_decay;
        detail_weight *= detail_decay;
        len *= WAVE_LACUNARITY;
    }

    // Regla del producto: la normal y la señal de cresta siguen la forma de la serie,
    // incluidos sus flancos. Aplicar antes de la familia costera conserva su relevo.
    vec3 packet_grad = -swell_dir * packet.y;
    grad = grad * packet.x + packet_grad * vert;
    n_up_sub = n_up_sub * packet.x - dot(horiz, packet_grad);
    horiz *= packet.x;
    vert *= packet.x;

    // Familia de orilla: una sola ola cuya fase es la distancia al litoral. Suma a los mismos
    // acumuladores que las octavas, así normal y cresta salen consistentes para todos los callers.
    if (shore_presence > 0.001) {
        // Gradiente de la distancia en el plano tangente: apunta mar adentro, y la ola viaja en
        // sentido contrario. Se reproyecta al plano del vértice porque el vector horneado es el
        // del centro del téxel, no el de aquí.
        vec3 seaward = ctx.shore_quality > 1e-4
            ? -ctx.shore_field.xyz / ctx.shore_quality : vec3(0.0);
        seaward -= radial * dot(seaward, radial);
        float seaward_len = length(seaward);
        seaward = seaward_len > 1e-4 ? seaward / seaward_len : vec3(0.0);

        // Shoaling (ley de Green, A ~ h^-1/4), acotado: sin tope la ola revienta en la orilla. La
        // referencia es media longitud de onda, que es la profundidad a la que una ola siente el
        // fondo de verdad. Una profundidad errónea solo puede alterar este realce acotado; ya no
        // puede decidir si la familia costera existe o no.
        float shoal_raw = clamp(
            pow(max(ctx.shore_depth, 0.5) / max(shore_length * 0.5, 1.0), -0.25),
            1.0, shore_shoal_max);
        // En canales estrechos la batimetría gruesa suele decir "casi cero" y disparar el shoaling
        // al máximo. Solo se acepta ese realce donde la dirección costera es coherente; siempre se
        // conserva al menos la amplitud base.
        float shoal = mix(1.0, shoal_raw, ctx.shore_quality);
        // Incidencia: una costa de espaldas al swell rompe menos que una de cara, pero NUNCA hasta
        // cero. Antes se apagaba del todo y las playas a sotavento se quedaban en agua muerta;
        // en la realidad les llega oleaje difractado, más pequeño.
        float lee_target = mix(0.35, 1.0,
            smoothstep(-0.9, 0.6, dot(swell_dir, -seaward)));
        float lee = mix(1.0, lee_target, shore_incidence * ctx.shore_quality);
        float w = shore_presence * lee;

        float k = 6.28318530718 / max(shore_length, 0.1);
        // amp_ref va SIN el peso: la Q de Gerstner se normaliza contra la amplitud y se cancelaría
        // con ella, dejando arrastre horizontal donde la ola ya no existe. El peso escala después
        // los cuatro acumuladores, y así el término se apaga de verdad.
        // Límite geométrico de rompiente: H/L ~ 0.16 como máximo. El mapa de profundidad grueso
        // puede disparar shoal al tope; sin este límite A=5 m y L=20 m generaban paredes de 10 m.
        float amp_ref = min(shore_amplitude * shoal, shore_length * 0.08);
        float q = shore_steepness / max(k * amp_ref, 1e-4);
        // W es firmada: incluso si el litoral grueso coloca este vértice visible en su lado tierra,
        // su gradiente sigue apuntando mar adentro y la fase avanza siempre hacia tierra.
        vec2 breakup = shore_breakup(local, t, shore_length);
        float phase = k * ctx.shore_field.w + t * shore_speed * sqrt(k) + breakup.x;
        // La superficie nunca queda inmóvil, pero el tramo débil cae por debajo del umbral de
        // espuma y corta visualmente la cinta continua.
        w *= breakup.y;
        float cs = cos(phase);
        float sn = sin(phase);

        // En el eje de un estrecho las direcciones de ambas riberas se oponen. Reducir solo el
        // arrastre horizontal evita que la malla se pliegue en picos; altura y cresta siguen vivas.
        horiz += q * amp_ref * seaward * cs * w * ctx.shore_quality;
        vert += amp_ref * sn * w;
        grad += seaward * (k * amp_ref * cs) * w * ctx.shore_quality;
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
//   1 cobertura/calidad de dirección           2 fase: bandas de una longitud de onda, enseñan
//                                                hacia dónde miran las crestas
//   3 sentido de viaje CONTRA la batimetría:   4 relevo entre familias: rojo = manda el oleaje de
//     verde = la ola avanza hacia donde el        mar abierto, verde = manda la orilla
//     fondo sube; rojo = va al revés            5 amplitud final relativa de la orilla
vec3 shore_debug_color(vec3 local, float t) {
    vec3 d = normalize(local);
    vec2 uv = world_map_uv(d);
    vec4 field = textureLod(shore_offset_map, uv, 0.0);
    float dist = abs(field.w);
    float quality = clamp(length(field.xyz), 0.0, 1.0);
    if (shore_debug_mode == 1) {
        float coverage = 1.0 - smoothstep(shore_range * 0.75, shore_range, dist);
        return vec3(coverage, quality, step(0.999, quality));
    }
    if (dist <= 1.0) {
        return vec3(0.0);
    }

    vec3 seaward = quality > 1e-4 ? -field.xyz / quality : vec3(0.0);
    seaward -= d * dot(seaward, d);
    float seaward_len = length(seaward);
    seaward = seaward_len > 1e-4 ? seaward / seaward_len : vec3(0.0);
    float shoreline_fade = smoothstep(1.0, max(shore_length * 0.25, shore_depth_fade), dist);

    if (shore_debug_mode == 2) {
        float k = 6.28318530718 / max(shore_length, 0.1);
        vec2 breakup = shore_breakup(local, t, shore_length);
        float band = fract((k * field.w + t * shore_speed * sqrt(k)
            + breakup.x) / 6.28318530718);
        return mix(vec3(0.05, 0.1, 0.25), vec3(1.0), step(0.5, band));
    }
    if (shore_debug_mode == 3) {
        // Sonda independiente del campo: si la ola viaja bien, el terreno sube en esa dirección.
        float rise = world_map_ground(world_map_uv(normalize(local - seaward * 300.0)))
                   - world_map_ground(uv);
        return mix(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), smoothstep(-2.0, 2.0, rise));
    }
    float reach = shore_reach > 0.0 ? shore_reach : shore_range;
    float gate = 1.0 - smoothstep(reach * (1.0 - shore_fade), reach, dist);
    if (shore_debug_mode == 4) {
        return mix(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), gate);
    }
    float lee = mix(1.0, mix(0.35, 1.0, smoothstep(-0.9, 0.6, dot(swell_direction(d), -seaward))),
                    shore_incidence);
    float packet = shore_breakup(local, t, shore_length).y;
    return vec3(gate * shoreline_fade * lee * packet);
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
    // El mapa se resuelve UNA vez para las cuatro evaluaciones. El punto fijo mueve el punto unos
    // metros y estos datos varían en decenas, así que la diferencia no se aprecia y ahorra tres
    // cuartas partes de las lecturas — que aquí pesan, porque la marcha de rayos de la niebla submarina
    // llama a esta función decenas de veces por píxel. Es además lo que ya hacía WaterHeightSampler.
    WaveContext ctx = wave_context(local);
    float unused_crest;
    vec3 guess = local;
    // Mismo número que WaterHeightSampler._INVERT_ITERATIONS, también con series activas.
    for (int i = 0; i < 3; i++) {
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
