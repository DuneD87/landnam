#[compute]
#version 450

#include "../liquid/underwater_params.glslinc"
#include "../liquid/underwater_optics.glslinc"

#define GOD_RAYS_COMPOSITE_PASS
#include "god_rays_pass.glslinc"
