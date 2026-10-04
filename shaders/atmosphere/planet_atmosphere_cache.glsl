#[compute]
#version 450

// Solo transporte suave del aire: los volúmenes con jitter van en el pase completo.
#include "../liquid/underwater_params.glslinc"
#include "../liquid/underwater_optics.glslinc"

#define ATMOSPHERE_CACHE_PASS
#include "planet_atmosphere_pass.glslinc"
