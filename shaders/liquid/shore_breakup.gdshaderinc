// Rotura de la ola de orilla: lo que impide que cada cresta sea la isolínea exacta del campo de
// distancia horneado, es decir una cinta perfectamente recta y de anchura constante durante
// kilómetros. Devuelve a la vez el desplazamiento de fase (dobla la cresta) y el factor de amplitud
// (la parte en gaps, y con ella la espuma, que solo aparece por encima de un umbral de cresta).
//
// Vive en su propio archivo para poder incluirla desde un shader que no pueda traerse
// gerstner_waves entero: allí hay treinta uniforms de mapas de temporal y campos de costa. Aquí no
// hay uniforms, solo la función, así que incluirla no cuesta nada.
//
// Tres escalas, todas atadas a la longitud de onda salvo la primera:
//   - envolvente larga (~350 m): agrupa la rompiente en tramos, un mismo trozo de playa rompe
//     fuerte y el de al lado flojo. Sus dos fases avanzan a ritmos incommensurables y lentísimos
//     (periodos de ~170 y ~240 s); sin ese término está congelada en world-space y el mismo tramo
//     rompe siempre igual.
//   - meandro (3λ y 1.5λ): dobla la línea de cresta. Es el único término que se ve como forma, y
//     por eso el que fija el presupuesto de gradiente, ver más abajo.
//   - celdas (4λ y 2.4λ): apagan la amplitud a trozos, que es lo que parte la cinta de espuma.
//
// Presupuesto de gradiente: un desplazamiento de fase añade a la fase total un gradiente de
// amplitud·(2π/periodo), o sea amplitud·λ/periodo veces k. Con 0.85 rad a 3λ y 0.25 rad a 1.5λ el
// peor caso suma ~0.45k: la longitud de onda local se comprime o estira hasta un ±45%, que es
// justo lo que se lee como vida, y queda lejos del 100% en el que la cresta se plegaría sobre sí
// misma. Subir esas amplitudes sin bajar el periodo rompe esa garantía.
//
// WaterHeightSampler._shore_breakup es la réplica CPU; cambiar una obliga a cambiar la otra.

#ifndef SHORE_BREAKUP_INC
#define SHORE_BREAKUP_INC

const float SHORE_BREAKUP_TAU = 6.28318530718;

// x = desplazamiento de fase en radianes; y = factor de amplitud en [0,1].
vec2 shore_breakup(vec3 local, float t, float wavelength) {
    float wl = max(wavelength, 1.0);

    vec3 p = local / 55.0;
    float a = sin(dot(p, vec3(0.73, 0.21, 0.65)) + t * 0.037);
    float b = sin(dot(p, vec3(-0.31, 0.88, 0.36)) * 1.37 + 1.7 - t * 0.026);
    float env = clamp(0.5 + a * 0.325 + b * 0.175, 0.0, 1.0);

    vec3 m1 = local * (SHORE_BREAKUP_TAU / (wl * 3.0));
    vec3 m2 = local * (SHORE_BREAKUP_TAU / (wl * 1.5));
    float w1 = sin(dot(m1, vec3(0.83, -0.28, 0.48)) + t * 0.19);
    float w2 = sin(dot(m2, vec3(-0.37, 0.62, 0.69)) + 1.3 - t * 0.31);

    vec3 c1 = local * (SHORE_BREAKUP_TAU / (wl * 4.0));
    float e1 = sin(dot(c1, vec3(0.29, 0.75, -0.60)) + t * 0.13);
    float e2 = sin(dot(c1, vec3(-0.71, 0.41, 0.57)) * 1.63 - t * 0.11);
    float cells = clamp(0.5 + e1 * 0.34 + e2 * 0.22, 0.0, 1.0);

    // Las dos envolventes pesan lo mismo y se suman ANTES del umbral, en vez de multiplicar dos
    // factores independientes: multiplicarlas encadena los mínimos y deja zonas de agua muerta.
    float packet = env * 0.5 + cells * 0.5;
    return vec2((env - 0.5) * 0.9 + w1 * 0.55 + w2 * 0.25, mix(0.25, 1.0, smoothstep(0.2, 0.8, packet)));
}

#endif
