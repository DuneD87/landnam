shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Variante de UNA cara: mitad de fill que la de doble cara. Se asigna por código
// (planet.gd) a las mallas de LOD lejano de los árboles, donde el volumen de la
// doble cara no se aprecia. Cuerpo idéntico en el include compartido.
#include "res://shaders/lib/transparent_foliage_body.gdshaderinc"
