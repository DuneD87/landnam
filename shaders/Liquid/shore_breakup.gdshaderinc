// Envolvente que agrupa la rompiente en tramos, compartida por el agua (gerstner_waves.gdshaderinc,
// donde modula fase y amplitud de la ola de orilla) y por el terreno (planet_biomes.gdshader, donde
// coloca la lámina de swash sobre la playa). Vive en su propio archivo porque el terreno no puede
// incluir gerstner_waves: se traería treinta uniforms de mapas de temporal y campos de costa que no
// usa. Aquí no hay uniforms, solo la función, así que incluirla no cuesta nada.
//
// Sin esto phase = distancia hace que cada isodistancia sea una cresta continua durante cientos de
// metros. La escala (~250-350 m por ciclo) es muy superior a shore_length y no altera de forma
// apreciable el sentido hacia tierra. Las dos fases avanzan a ritmos incommensurables y lentísimos
// (periodos de ~170 y ~240 s): sin ese término el envolvente está congelado en world-space y el
// mismo tramo de playa rompe siempre fuerte y el mismo siempre flojo.

#ifndef SHORE_BREAKUP_INC
#define SHORE_BREAKUP_INC

float shore_breakup(vec3 local, float t) {
    vec3 p = local / 55.0;
    float a = sin(dot(p, vec3(0.73, 0.21, 0.65)) + t * 0.037);
    float b = sin(dot(p, vec3(-0.31, 0.88, 0.36)) * 1.37 + 1.7 - t * 0.026);
    return clamp(0.5 + a * 0.325 + b * 0.175, 0.0, 1.0);
}

#endif
