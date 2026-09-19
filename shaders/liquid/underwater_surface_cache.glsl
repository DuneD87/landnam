#[compute]
#version 450
// The expensive inverse Gerstner spectrum runs once per cache texel, not dozens
// of times per screen pixel. RGBA = radial height and the matching world normal.
layout(local_size_x=8, local_size_y=8, local_size_z=1) in;
layout(rgba32f, set=0, binding=0) uniform writeonly image2D surface_cache;
layout(rgba16f, set=0, binding=2) uniform writeonly image2D background_cache;
layout(set=0, binding=3) uniform sampler2D source_color;
layout(set=0, binding=4) uniform sampler2D source_depth;
#include "underwater_shared.glslinc"

// El mismo shader resuelve los dos niveles del campo: la extensión llega por push
// constant en vez de leerse del buffer, que es común a ambos despachos.
layout(push_constant, std430) uniform Level { float extent; float capture_background; float pad1; float pad2; } level;

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(surface_cache);
    if (any(greaterThanEqual(pixel, size))) return;
    // Snapshot before the atmosphere writes into source_color. Refracting an
    // in-place colour target would race neighbouring workgroups. Four texels
    // per invocation cover a 512² HDR background, once on the far dispatch.
    if (level.capture_background > 0.5) {
        for (int y = 0; y < 2; ++y) {
            for (int x = 0; x < 2; ++x) {
                ivec2 target = pixel * 2 + ivec2(x, y);
                vec2 uv = (vec2(target) + 0.5) / vec2(imageSize(background_cache));
                imageStore(background_cache, target, vec4(textureLod(source_color, uv, 0.0).rgb,
                    textureLod(source_depth, uv, 0.0).r));
            }
        }
    }
    vec2 plane = ((vec2(pixel) + 0.5) / vec2(size) * 2.0 - 1.0) * level.extent;
    vec3 local = uw.data[15].xyz - planet_center
        + uw.data[13].xyz * plane.x + uw.data[14].xyz * plane.y;
    vec3 normal;
    // Solo la onda analítica. El detalle óptico ya no se hornea aquí: 256 téxeles
    // sobre decenas de metros filtran a cero justo la escala que rompe el borde de
    // Snell, así que se evalúa por píxel en el punto de salida del rayo.
    float height = gerstner_surface_height_normal(local, water_time, normal);
    imageStore(surface_cache, pixel, vec4(height, normal));
}
