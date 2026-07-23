shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Variante de doble cara (volumen). El cuerpo está en el include compartido;
// la variante de una cara es transparent_material_shader_singleside.gdshader.
#include "res://shaders/lib/transparent_foliage_body.gdshaderinc"
