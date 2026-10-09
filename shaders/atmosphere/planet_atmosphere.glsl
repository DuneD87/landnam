#[compute]
#version 450

// Nubes, sombras, niebla y aurora a resolución completa; solo el aire usa el caché. Las nubes
// llegan ya marchadas en su capa (planet_atmosphere_clouds) y aquí se filtran.
#include "../liquid/underwater_params.glslinc"
#include "../liquid/underwater_optics.glslinc"

#include "planet_atmosphere_pass.glslinc"
