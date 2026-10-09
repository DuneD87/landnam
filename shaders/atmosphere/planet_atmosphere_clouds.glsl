#[compute]
#version 450

// Capa de nubes por encima de la escala de render: solo el march de nubes y su perspectiva aérea.
#include "../liquid/underwater_params.glslinc"
#include "../liquid/underwater_optics.glslinc"

#define ATMOSPHERE_CLOUD_PASS
#include "planet_atmosphere_pass.glslinc"
